-- Editing and deleting expenses, joining rules, the 20-member cap, and who may remove members.
-- (Removing and leaving at $0: 009_remove_and_leave.)
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = tests.id(trip)), 0);
end $$;
-- M1's world for suffix s: you pay $84.20 equal You/Alex/Jordan. Returns the expense id.
create function pg_temp.m1(s text) returns uuid language plpgsql as $$
begin
  perform tests.users('you' || s, 'alex' || s, 'jordan' || s);
  perform tests.trip('cr' || s, array['you' || s, 'alex' || s, 'jordan' || s]);
  return tests.equal('cr' || s, 'you' || s, 8420, array['you' || s, 'alex' || s, 'jordan' || s]);
end $$;

-- Edit: M1 re-saved at $90 → shares 30/30/30; the event records the change.
select tests.authenticate_as(tests.id('youK'));
create temp table t_e on commit drop as select pg_temp.m1('E') as id;
grant select on t_e to authenticated;
select tests.authenticate_as(tests.id('youE'));
select public.save_expense(tests.id('crE'), (select id from t_e), 'Dinner', 'restaurant', 9000, tests.id('youE'), 'equal',
  jsonb_build_array(jsonb_build_object('user_id', tests.id('youE'), 'value', 1),
                    jsonb_build_object('user_id', tests.id('alexE'), 'value', 1),
                    jsonb_build_object('user_id', tests.id('jordanE'), 'value', 1)), current_date);
select is(pg_temp.net('youE', 'crE'), 6000::bigint, 'edit: your net follows the new amount');
select tests.authenticate_as(tests.id('youE'));
select is((select deltas from public.activity_events where trip_id = tests.id('crE') and kind = 'expense_updated'),
          jsonb_build_object(tests.id('youE'), 386, tests.id('alexE'), -194, tests.id('jordanE'), -192),
          'edit: the event records only the change');

-- Delete: permanent, and undeleting the trip doesn't bring it back.
select tests.authenticate_as(tests.id('youE'));
select public.delete_expense((select id from t_e));
select is(pg_temp.net('youE', 'crE'), 0::bigint, 'delete: the expense comes off everyone''s balance');
select tests.authenticate_as(tests.id('youE'));
select public.delete_trip(tests.id('crE'));
select public.undelete_trip(tests.id('crE'));
select is(pg_temp.net('youE', 'crE'), 0::bigint, 'delete is permanent: undeleting the trip doesn''t restore it');

-- Joining twice is a no-op.
select tests.authenticate_as(tests.id('alexE'));
select public.join_trip((select token from tests.names where k = 'crE'));
select tests.authenticate_as(tests.id('youE'));
select is((select count(*) from public.trip_members where trip_id = tests.id('crE'))::int, 3, 'joining again doesn''t add a second membership');

-- 20-member cap.
select tests.users(variadic (select array_agg('p' || g) from generate_series(1, 21) g));
select tests.trip('big', (select array_agg('p' || g order by g) from generate_series(1, 20) g));
select tests.authenticate_as(tests.id('p21'));
select throws_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'big')),
                 'P0001', 'a trip can have at most 20 members', 'the 21st member is turned away');

-- Only active members can remove people.
select tests.authenticate_as(tests.id('p21'));
select throws_ok(format('select public.remove_member(%L, %L)', tests.id('big'), tests.id('p2')),
                 'P0001', 'not a member of this trip', 'outsiders can''t remove members');

select * from finish();
rollback;
