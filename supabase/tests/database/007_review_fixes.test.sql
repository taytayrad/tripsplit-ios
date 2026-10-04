-- Fixes from the Phase 2 architectural review (prd.md › Prototype decisions › Removed members can't rejoin).
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = tests.id(trip)), 0);
end $$;

-- A removed member can't rejoin with the old link; an active member can add them back.
select tests.users('you', 'alex', 'jordan');
select tests.trip('cr', array['you', 'alex', 'jordan']);
select tests.equal('cr', 'you', 8420, array['you', 'alex', 'jordan']);
select tests.authenticate_as(tests.id('you'));
select public.remove_member(tests.id('cr'), tests.id('jordan'), 'wipe');
select tests.authenticate_as(tests.id('jordan'));
select throws_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'cr')),
                 'P0001', 'you were removed from this trip', 'join_trip: a removed member can''t rejoin by link');
select tests.authenticate_as(tests.id('you'));
select public.add_member(tests.id('cr'), tests.id('jordan'));
select ok(private.is_active_member(tests.id('cr'), tests.id('jordan')), 'add_member: an active member can add them back');
select is(pg_temp.net('jordan', 'cr'), 0::bigint, 'add_member after wipe: they come back with no share in old expenses');
select is((select count(*) from public.activity_events
           where trip_id = tests.id('cr') and kind = 'member_joined' and actor_id = tests.id('jordan') and subject = 'cr')::int,
          2, 'member_joined: add_member writes the same shape as join_trip (actor = joiner, subject = trip name)');

-- Wipe leaves a split the editor can round-trip: the rewritten expense becomes exact.
select is((select split_kind from public.expenses where trip_id = tests.id('cr')), 'exact',
          'wipe: the rewritten expense is stored as an exact split');

-- Payments: retrying someone else's request_id is refused; deleting on a deleted trip is refused.
select tests.users('youP', 'alexP', 'samP');
select tests.trip('crP', array['youP', 'alexP']);
select tests.trip('lhP', array['youP', 'alexP', 'samP']);
select tests.equal('crP', 'alexP', 6000, array['youP']);   -- you owe Alex 60 on Coast Road
select tests.equal('lhP', 'alexP', 3000, array['youP']);   -- and 30 on Lake House
select tests.authenticate_as(tests.id('youP'));
create temp table t_req on commit drop as select gen_random_uuid() as id;
grant select on t_req to authenticated;
select public.log_payment(tests.id('alexP'), 9000, 'pay', 'venmo', (select id from t_req));
select is((select count(*) from public.log_payment(tests.id('alexP'), 9000, 'pay', 'venmo', (select id from t_req)))::int, 2,
          'log_payment: the same person retrying gets their rows back');
select tests.authenticate_as(tests.id('samP'));
select throws_ok(format('select public.log_payment(%L, 9000, %L, %L, %L)', tests.id('alexP'), 'pay', 'venmo', (select id from t_req)),
                 'P0001', 'request id already used', 'log_payment: someone else''s request_id is refused');
select tests.authenticate_as(tests.id('youP'));
select public.delete_trip(tests.id('crP'));
select throws_ok(format('select public.delete_payment(%L)', (select id from public.payments where trip_id = tests.id('crP'))),
                 'P0001', 'this trip is deleted', 'delete_payment: refused on a deleted trip');
select public.undelete_trip(tests.id('crP'));
select is(pg_temp.net('youP', 'crP'), 0::bigint, 'undelete: the payment still counts, so the trip is back exactly');

select * from finish();
rollback;
