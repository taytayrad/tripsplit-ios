-- Removing and leaving only at $0 (docs/money-rules.md › Removing and leaving, golden cases R1–R3).
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = tests.id(trip)), 0);
end $$;

-- G1: Coast Road with you, Atish, Tyler; Tyler pays $60, Atish pays $30. You −30 · Atish 0 · Tyler +30.
select tests.users('you', 'atish', 'tyler');
select tests.trip('cr', array['you', 'atish', 'tyler']);
select tests.equal('cr', 'tyler', 6000, array['you', 'atish', 'tyler']);
select tests.equal('cr', 'atish', 3000, array['you', 'atish', 'tyler']);

-- R1: Tyler is owed $30, so he can't be removed.
select tests.authenticate_as(tests.id('you'));
select throws_ok(format('select public.remove_member(%L, %L)', tests.id('cr'), tests.id('tyler')),
                 'P0001', 'only members with a $0 balance can be removed', 'R1 an unsettled member can''t be removed');

-- R2: Atish is settled, so removing him changes nothing.
select public.remove_member(tests.id('cr'), tests.id('atish'));
select ok(not private.is_active_member(tests.id('cr'), tests.id('atish')), 'R2 a settled member can be removed');
select is(pg_temp.net('you', 'cr'), -3000::bigint, 'R2 your net is unchanged');
select is(pg_temp.net('tyler', 'cr'), 3000::bigint, 'R2 and so is Tyler''s');
select tests.authenticate_as(tests.id('you'));
select is((select deltas from public.activity_events where trip_id = tests.id('cr') and kind = 'member_removed'), '{}'::jsonb,
          'R2 the removal moves no money');

-- R3: you owe $30, so you can't leave; after paying Tyler you can.
select tests.authenticate_as(tests.id('you'));
select throws_ok(format('select public.leave_trip(%L)', tests.id('cr')),
                 'P0001', 'settle up before leaving', 'R3 you can''t leave while you owe');
select tests.authenticate_as(tests.id('tyler'));
select throws_ok(format('select public.leave_trip(%L)', tests.id('cr')),
                 'P0001', 'settle up before leaving', 'R3 nor while you''re owed');
select tests.authenticate_as(tests.id('you'));
select public.log_payment(tests.id('tyler'), 'pay', 'cash', gen_random_uuid(), current_date,
                          jsonb_build_array(jsonb_build_object('trip_id', tests.id('cr'), 'cents', 3000)));
select public.leave_trip(tests.id('cr'));
select ok(not private.is_active_member(tests.id('cr'), tests.id('you')), 'R3 once settled, you can leave');
select tests.authenticate_as(tests.id('tyler'));  -- you can't read the trip's Activity any more
select is((select count(*) from public.activity_events
           where trip_id = tests.id('cr') and kind = 'member_removed' and actor_id = tests.id('you'))::int, 2,
          'R3 leaving is a member_removed event with you as the actor');

-- remove_member is for other people; you leave with leave_trip.
select tests.authenticate_as(tests.id('tyler'));
select throws_ok(format('select public.remove_member(%L, %L)', tests.id('cr'), tests.id('tyler')),
                 'P0001', 'use leave_trip to leave', 'remove_member: not for yourself');

select * from finish();
rollback;
