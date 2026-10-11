-- Webhook setup and routing state. Everything rolls back, including pg_net's queue: no live APNs calls.
begin;
create extension if not exists pgtap with schema extensions;
select plan(12);
select tests.users('you', 'jo');
delete from vault.secrets where name in ('push_function_url', 'push_webhook_secret');
create temporary table initial_queue as select count(*) n from net.http_request_queue;

select tests.trip('push trip', array['you','jo']);
select tests.clear_authentication();
select is((select count(*) from net.http_request_queue), (select n from initial_queue),
          'without setup, activity saves without making a request');

select vault.create_secret('https://push.test/functions/v1/push', 'push_function_url');
select vault.create_secret('local-test-secret', 'push_webhook_secret');
select tests.equal('push trip', 'you', 10000, array['you','jo']);
select tests.clear_authentication();
select is((select count(*) from net.http_request_queue), (select n + 1 from initial_queue),
          'an activity insert queues exactly one webhook');
select is((select url from net.http_request_queue order by id desc limit 1), 'https://push.test/functions/v1/push', 'URL comes from Vault');
select is((select headers->>'Authorization' from net.http_request_queue order by id desc limit 1), 'Bearer local-test-secret', 'webhook credential comes from Vault');
select is((select convert_from(body, 'UTF8')::jsonb from net.http_request_queue order by id desc limit 1),
          jsonb_build_object('type','INSERT','schema','public','table','activity_events','record',
            jsonb_build_object('id',(select id from public.activity_events where kind = 'expense_added'))),
          'payload is the committed event id, not client-supplied wording');

select tests.authenticate_as(tests.id('you'));
select public.register_device_token('phone');
select tests.clear_authentication();
select is((select apns_environment from public.device_tokens where token = 'phone'), null, 'new tokens have an unknown APNs environment');
update public.device_tokens set apns_environment = 'sandbox' where token = 'phone';
select is((select apns_environment from public.device_tokens where token = 'phone'), 'sandbox', 'sender can save the accepted host');
select tests.authenticate_as(tests.id('you'));
select throws_ok($$ update public.device_tokens set apns_environment = 'production' where token = 'phone' $$,
                 '42501', null, 'clients cannot choose a host directly');
select public.register_device_token('phone');
select tests.clear_authentication();
select is((select apns_environment from public.device_tokens where token = 'phone'), null, 're-registration clears the learned environment');
select throws_ok($$ update public.device_tokens set apns_environment = 'invalid' where token = 'phone' $$,
                 '23514', null, 'only sandbox and production are allowed');
update public.device_tokens set apns_environment = 'sandbox' where token = 'phone';
select tests.authenticate_as(tests.id('jo'));
select public.register_device_token('phone');
select tests.clear_authentication();
select is((select user_id from public.device_tokens where token = 'phone'), tests.id('jo'), 'account takeover still leaves one owner');
select tests.authenticate_as(tests.id('jo'));
select throws_ok($$ select private.push_activity_event() $$, '42501', null, 'clients cannot invoke the privileged webhook trigger');
select * from finish();
rollback;
