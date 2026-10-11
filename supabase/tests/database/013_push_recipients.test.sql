-- Who gets a push for each activity event (TRIP-24, docs/events.md). Every push cell, the actor rule, and the
-- preferences. The push function calls push_recipients as the service role; these run as the test owner.
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- Recipients of the latest `kind` event on `trip`, as sorted names: 'atish,you'.
create function pg_temp.recipients(p_kind text, p_trip text) returns text language plpgsql as $$
declare v_event uuid;
begin
  perform tests.clear_authentication();
  select id into v_event from public.activity_events
  where kind = p_kind and trip_id = tests.id(p_trip) order by created_at desc limit 1;
  return coalesce((select string_agg(n.k, ',' order by n.k) from public.push_recipients(v_event) r join tests.names n on n.id = r), '');
end $$;

create function pg_temp.pref(who text, col text, val boolean) returns void language plpgsql as $$
begin
  perform tests.clear_authentication();
  execute format('update public.profiles set %I = %L where id = %L', col, val, tests.id(who));
end $$;

-- Coast Road: you create it, then Atish and Tyler join (in that order).
select tests.users('you', 'atish', 'tyler', 'sam');
select tests.trip('cr', array['you', 'atish', 'tyler']);
select is(pg_temp.recipients('trip_created', 'cr'), '', 'trip_created: nobody');
select is(pg_temp.recipients('member_joined', 'cr'), 'atish,you', 'member_joined: every other active member, not the person joining');
select pg_temp.pref('atish', 'notify_join', false);
select tests.authenticate_as(tests.id('sam'));
select public.join_trip((select token from tests.names where k = 'cr'));
select is(pg_temp.recipients('member_joined', 'cr'), 'tyler,you', 'member_joined: notify_join off drops Atish');
select tests.authenticate_as(tests.id('sam'));
select public.leave_trip(tests.id('cr'));
select is(pg_temp.recipients('member_removed', 'cr'), '', 'member_removed (leaving): nobody');

-- Expenses: members whose balance changes, never the actor.
select tests.authenticate_as(tests.id('tyler'));  -- the temp table must belong to the signed-in role
create temp table t_stay on commit drop as select tests.equal('cr', 'tyler', 6000, array['you', 'atish', 'tyler']) as id;
grant select on t_stay to authenticated;
select is(pg_temp.recipients('expense_added', 'cr'), 'atish,you', 'expense_added: members whose balance changes, not Tyler who added it');
select tests.equal('cr', 'tyler', 1000, array['you', 'tyler']);
select is(pg_temp.recipients('expense_added', 'cr'), 'you', 'expense_added: Atish, not in it, gets nothing');
select pg_temp.pref('atish', 'notify_expense', false);
select tests.authenticate_as(tests.id('you'));
select public.save_expense(tests.id('cr'), (select id from t_stay), 'Stay', 'lodging', 9000, tests.id('tyler'), 'equal',
  jsonb_build_array(jsonb_build_object('user_id', tests.id('you'), 'value', 1), jsonb_build_object('user_id', tests.id('atish'), 'value', 1),
                    jsonb_build_object('user_id', tests.id('tyler'), 'value', 1)), current_date);
select is(pg_temp.recipients('expense_updated', 'cr'), 'tyler', 'expense_updated: notify_expense off drops Atish; you edited it');
select pg_temp.pref('atish', 'notify_expense', true);
select tests.authenticate_as(tests.id('you'));
select public.delete_expense((select id from t_stay));
select is(pg_temp.recipients('expense_deleted', 'cr'), 'atish,tyler', 'expense_deleted: members whose balance changes');
select tests.authenticate_as(tests.id('atish'));
select public.restore_expense((select id from t_stay));
select is(pg_temp.recipients('expense_restored', 'cr'), 'tyler,you', 'expense_restored: members whose balance changes');

-- Payments: the payee only; a removed payment goes to the other person.
select tests.authenticate_as(tests.id('you'));
select public.log_payment(tests.id('tyler'), 'pay', 'cash', gen_random_uuid(), current_date,
                          jsonb_build_array(jsonb_build_object('trip_id', tests.id('cr'), 'cents', 1000)));
select is(pg_temp.recipients('payment_logged', 'cr'), 'tyler', 'payment_logged: only the payee; Atish, not on it, gets nothing');
select tests.authenticate_as(tests.id('tyler'));
select public.log_payment(tests.id('you'), 'record', 'cash', gen_random_uuid(), current_date,
                          jsonb_build_array(jsonb_build_object('trip_id', tests.id('cr'), 'cents', 1000)));
select is(pg_temp.recipients('payment_logged', 'cr'), '', 'payment_logged: the payee recorded it, so nobody');
select tests.authenticate_as(tests.id('you'));
select public.delete_payment((select id from public.payments where trip_id = tests.id('cr') and logged_by = tests.id('you')));
select is(pg_temp.recipients('payment_deleted', 'cr'), 'tyler', 'payment_deleted: the other person on it');
select pg_temp.pref('tyler', 'notify_paid', false);
select tests.authenticate_as(tests.id('you'));
select public.log_payment(tests.id('tyler'), 'pay', 'cash', gen_random_uuid(), current_date,
                          jsonb_build_array(jsonb_build_object('trip_id', tests.id('cr'), 'cents', 500)));
select is(pg_temp.recipients('payment_logged', 'cr'), '', 'payment_logged: notify_paid off drops Tyler');

-- Deleting and restoring the trip: every other active member.
select tests.authenticate_as(tests.id('atish'));
select public.delete_trip(tests.id('cr'));
select is(pg_temp.recipients('trip_deleted', 'cr'), 'tyler,you', 'trip_deleted: every other active member');
select pg_temp.pref('you', 'notify_trip_deleted', false);
select tests.authenticate_as(tests.id('tyler'));
select public.undelete_trip(tests.id('cr'));
select is(pg_temp.recipients('trip_undeleted', 'cr'), 'atish', 'trip_undeleted: notify_trip_deleted off drops you');

-- Renaming writes no event, so nothing to push; and signed-in people can't call push_recipients.
select tests.authenticate_as(tests.id('you'));
update public.trips set name = 'Coast Road 2026' where id = tests.id('cr');
select is((select count(*) from public.activity_events where trip_id = tests.id('cr') and kind not in
          ('trip_created','member_joined','member_removed','expense_added','expense_updated','expense_deleted',
           'expense_restored','payment_logged','payment_deleted','trip_deleted','trip_undeleted'))::int, 0,
          'a rename writes no activity row');
select throws_ok(format('select public.push_recipients(%L)', (select id from public.activity_events limit 1)),
                 '42501', null, 'signed-in people can''t call push_recipients');

select * from finish();
rollback;
