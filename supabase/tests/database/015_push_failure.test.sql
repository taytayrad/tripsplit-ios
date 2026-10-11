-- Simulate a broken pg_net queue inside a rollback-only transaction. No notifications are sent.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);
select tests.users('you', 'jo');
delete from vault.secrets where name in ('push_function_url', 'push_webhook_secret');
select vault.create_secret('https://push.test/functions/v1/push', 'push_function_url');
select vault.create_secret('local-test-secret', 'push_webhook_secret');
select tests.trip('push failure', array['you','jo']);
select tests.clear_authentication();
create temporary table initial_queue as select count(*) n from net.http_request_queue;

create function pg_temp.fail_push_queue() returns trigger language plpgsql as $$
begin
  raise exception 'simulated queue failure' using errcode = '58000';
end;
$$;
create trigger fail_push_queue before insert on net.http_request_queue
for each row execute function pg_temp.fail_push_queue();

select lives_ok($$ select tests.equal('push failure', 'jo', 10000, array['you','jo']) $$,
                'a queue failure does not block saving an expense');
select tests.clear_authentication();
select is((select count(*) from public.expenses where trip_id = tests.id('push failure')), 1::bigint,
          'the expense survives the push failure');
select is((select count(*) from public.activity_events where trip_id = tests.id('push failure') and kind = 'expense_added'),
          1::bigint, 'expense activity survives the push failure');

select tests.authenticate_as(tests.id('you'));
select lives_ok($$ select public.log_payment(tests.id('jo'), 'pay', 'cash', gen_random_uuid(), current_date,
                  jsonb_build_array(jsonb_build_object('trip_id', tests.id('push failure'), 'cents', 2500))) $$,
                'a queue failure does not block logging a payment');
select tests.clear_authentication();
select is((select count(*) from public.payments where trip_id = tests.id('push failure')), 1::bigint,
          'the payment survives the push failure');
select is((select count(*) from public.activity_events where trip_id = tests.id('push failure') and kind = 'payment_logged'),
          1::bigint, 'payment activity survives the push failure');
select is((select count(*) from net.http_request_queue), (select n from initial_queue),
          'failed enqueue leaves no partial request');
select * from finish();
rollback;
