-- Allocation golden cases A1–A6 and balance case M9 (docs/money-rules.md), plus payment deletion.
-- Scenario: you owe Jordan $30 on Lake House (Sep 12, older) and $60 on Coast Road (Oct 3).
begin;
create extension if not exists pgtap with schema extensions;
select plan(17);

-- A fresh copy of the Jordan scenario for person-suffix s; returns nothing.
create function pg_temp.jordan_scenario(s text) returns void language plpgsql as $$
begin
  perform tests.users('you' || s, 'jordan' || s);
  perform tests.trip('lh' || s, array['you' || s, 'jordan' || s], date '2026-09-12');
  perform tests.trip('cr' || s, array['you' || s, 'jordan' || s], date '2026-10-03');
  perform tests.equal('lh' || s, 'jordan' || s, 3000, array['you' || s]);
  perform tests.equal('cr' || s, 'jordan' || s, 6000, array['you' || s]);
end $$;

-- `who` logs a payment with `other` and returns the rows created, oldest trip first: 'lhA:3000,crA:6000'.
create function pg_temp.log(who text, other text, cents int, direction text, request uuid default gen_random_uuid())
returns text language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return (select string_agg(n.k || ':' || r.amount_cents, ',' order by t.start_date, n.k)
          from public.log_payment(tests.id(other), cents, direction,
                                  case direction when 'pay' then 'venmo' else 'recorded' end, request) r
          join tests.names n on n.id = r.trip_id
          join public.trips t on t.id = r.trip_id);
end $$;

create function pg_temp.combined(who text, other text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_combined_balances() where other_user_id = tests.id(other)), 0);
end $$;

create function pg_temp.pair(who text, trip text, other text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_pair_balances()
                   where trip_id = tests.id(trip) and other_user_id = tests.id(other)), 0);
end $$;

-- A1: pay the full $90.
select pg_temp.jordan_scenario('A1');
select is(pg_temp.log('youA1', 'jordanA1', 9000, 'pay'), 'lhA1:3000,crA1:6000', 'A1 $90 fills Lake House then Coast Road');
select is(pg_temp.combined('youA1', 'jordanA1'), 0::bigint, 'A1 settled with Jordan');

-- A2: pay $50.
select pg_temp.jordan_scenario('A2');
select is(pg_temp.log('youA2', 'jordanA2', 5000, 'pay', '00000000-0000-0000-0000-0000000000a2'),
          'lhA2:3000,crA2:2000', 'A2 $50 pays off Lake House, then $20 toward Coast Road');
select is(pg_temp.pair('youA2', 'crA2', 'jordanA2'), -4000::bigint, 'A2 $40 left, all on Coast Road');

-- A3: pay $20.
select pg_temp.jordan_scenario('A3');
select is(pg_temp.log('youA3', 'jordanA3', 2000, 'pay'), 'lhA3:2000', 'A3 $20 goes to Lake House only');

-- A4: overpaying is rejected.
select pg_temp.jordan_scenario('A4');
select throws_ok($$ select pg_temp.log('youA4', 'jordanA4', 10000, 'pay') $$, 'P0001',
                 'amount is more than what is owed', 'A4 can''t log more than the $90 owed');

-- A5: Alex owes you $28.06; you record it.
select tests.users('youA5', 'alexA5');
select tests.trip('crA5', array['youA5', 'alexA5']);
select tests.equal('crA5', 'youA5', 2806, array['alexA5']);
select is(pg_temp.log('youA5', 'alexA5', 2806, 'record'), 'crA5:2806', 'A5 recording a payment from Alex');
select is((select payer_id from public.payments where trip_id = tests.id('crA5')), tests.id('alexA5'),
          'A5 Alex is the payer of the recorded payment');

-- A6: A2's log retried with the same request id creates nothing new.
select is(pg_temp.log('youA2', 'jordanA2', 5000, 'pay', '00000000-0000-0000-0000-0000000000a2'),
          'lhA2:3000,crA2:2000', 'A6 retry returns the existing payments');
select tests.authenticate_as(tests.id('youA2'));
select is((select count(*) from public.payments where payer_id = tests.id('youA2'))::int, 2, 'A6 still exactly two payment rows');

-- M9: M1's world; Alex logs a $28.06 payment to you.
select tests.users('youM9', 'alexM9', 'jordanM9');
select tests.trip('crM9', array['youM9', 'alexM9', 'jordanM9']);
select tests.equal('crM9', 'youM9', 8420, array['youM9', 'alexM9', 'jordanM9']);
select pg_temp.log('alexM9', 'youM9', 2806, 'pay');
select is(pg_temp.pair('youM9', 'crM9', 'alexM9'), 0::bigint, 'M9 pair(you, Alex) is $0');
select tests.authenticate_as(tests.id('youM9'));
select is((select cents from public.my_trip_nets() where trip_id = tests.id('crM9')), 2808::bigint, 'M9 your net is now +28.08');
select tests.authenticate_as(tests.id('alexM9'));
select is(coalesce((select cents from public.my_trip_nets() where trip_id = tests.id('crM9')), 0), 0::bigint, 'M9 Alex is settled');

-- Activity: each payment row is an event with the effect on each person.
select tests.authenticate_as(tests.id('youA1'));
select is((select deltas from public.activity_events
           where trip_id = tests.id('lhA1') and kind = 'payment_logged'),
          jsonb_build_object(tests.id('youA1'), 3000, tests.id('jordanA1'), -3000),
          'a logged payment records +amount for the payer and −amount for the payee');

-- Deleting a payment: Jordan (the payee) deletes A2's Coast Road payment.
select tests.authenticate_as(tests.id('jordanA2'));
select public.delete_payment((select id from public.payments where trip_id = tests.id('crA2')));
select is(pg_temp.combined('youA2', 'jordanA2'), -6000::bigint, 'a deleted payment no longer counts');
select tests.authenticate_as(tests.id('jordanA2'));
select is((select count(*) from public.activity_events where trip_id = tests.id('crA2') and kind = 'payment_deleted')::int, 1,
          'deleting a payment is an Activity event');

-- Nothing owed: logging is rejected.
select throws_ok($$ select pg_temp.log('youA1', 'jordanA1', 100, 'pay') $$, 'P0001', 'nothing is owed', 'can''t pay when nothing is owed');

select * from finish();
rollback;
