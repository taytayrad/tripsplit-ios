-- Net model golden cases (docs/money-rules.md): nets M1–M9, suggested payments G1–G5, payments P1–P6.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- `who`'s net on `trip` (0 when there's no row).
create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = tests.id(trip)), 0);
end $$;

-- The trip's suggested payments as `who` sees them, in order: 'jordan>you:2808,alex>you:2806'.
create function pg_temp.suggest(who text, trip text) returns text language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(who));
  return coalesce((select string_agg(regexp_replace(a.k, '[A-Z0-9]+$', '') || '>' || regexp_replace(b.k, '[A-Z0-9]+$', '') || ':' || s.cents, ','
                                     order by s.seq)
                   from public.my_trip_settlements() s
                   join tests.names a on a.id = s.payer_id join tests.names b on b.id = s.payee_id
                   where s.trip_id = tests.id(trip)), '');
end $$;

-- `who` logs a payment with `other`; parts is 'trip:cents,trip:cents'. Returns the stored rows the same way.
create function pg_temp.log(who text, other text, direction text, parts text, request uuid default gen_random_uuid(),
                            paid_on date default current_date) returns text language plpgsql as $$
declare v_parts jsonb;
begin
  select jsonb_agg(jsonb_build_object('trip_id', tests.id(split_part(p, ':', 1)), 'cents', split_part(p, ':', 2)::int))
    into v_parts from unnest(string_to_array(parts, ',')) p;
  perform tests.authenticate_as(tests.id(who));
  return (select string_agg(n.k || ':' || r.amount_cents, ',' order by n.k)
          from public.log_payment(tests.id(other), direction, case direction when 'pay' then 'venmo' else 'cash' end,
                                  request, paid_on, v_parts) r
          join tests.names n on n.id = r.trip_id);
end $$;

-- G1's world for suffix s: Coast Road with you, Atish, Tyler; Tyler pays $60, Atish pays $30, both equal.
create function pg_temp.g1(s text) returns void language plpgsql as $$
begin
  perform tests.users('you' || s, 'atish' || s, 'tyler' || s);
  perform tests.trip('cr' || s, array['you' || s, 'atish' || s, 'tyler' || s]);
  perform tests.equal('cr' || s, 'tyler' || s, 6000, array['you' || s, 'atish' || s, 'tyler' || s]);
  perform tests.equal('cr' || s, 'atish' || s, 3000, array['you' || s, 'atish' || s, 'tyler' || s]);
end $$;

-- M1, M2: nets per member.
select tests.users('y1', 'a1', 'j1');
select tests.trip('cr1', array['y1', 'a1', 'j1']);
select tests.equal('cr1', 'y1', 8420, array['y1', 'a1', 'j1']);
select is(pg_temp.net('y1', 'cr1'), 5614::bigint, 'M1 you +56.14');
select is(pg_temp.net('a1', 'cr1'), -2806::bigint, 'M1 Alex −28.06');
select is(pg_temp.net('j1', 'cr1'), -2808::bigint, 'M1 Jordan −28.08');
select tests.users('y2', 'a2', 'j2');
select tests.trip('nm2', array['y2', 'a2', 'j2']);
select tests.equal('nm2', 'y2', 3000, array['a2', 'j2']);
select is(pg_temp.net('y2', 'nm2'), 3000::bigint, 'M2 the payer outside the split is owed the full $30');

-- G2: M1's suggestions, largest debtor first.
select is(pg_temp.suggest('a1', 'cr1'), 'j>y:2808,a>y:2806', 'G2 Jordan pays you 28.08, Alex pays you 28.06');

-- M6, M7: deleting and undeleting the trip.
select tests.authenticate_as(tests.id('a1'));
select public.delete_trip(tests.id('cr1'));
select is(pg_temp.net('y1', 'cr1'), 0::bigint, 'M6 a deleted trip has no nets');
select is(pg_temp.suggest('y1', 'cr1'), '', 'M6 and no suggestions');
select tests.authenticate_as(tests.id('j1'));
select public.undelete_trip(tests.id('cr1'));
select is(pg_temp.net('y1', 'cr1'), 5614::bigint, 'M7 undeleting restores the nets exactly');

-- M8: Sam joins after the expense.
select tests.users('s1');
select tests.authenticate_as(tests.id('s1'));
select public.join_trip((select token from tests.names where k = 'cr1'));
select is(pg_temp.net('y1', 'cr1'), 5614::bigint, 'M8 a late joiner leaves the nets unchanged');
select is(pg_temp.net('s1', 'cr1'), 0::bigint, 'M8 and owes nothing');

-- M9: Alex pays you $28.06.
select pg_temp.log('a1', 'y1', 'pay', 'cr1:2806');
select is(pg_temp.net('y1', 'cr1'), 2808::bigint, 'M9 you +28.08');
select is(pg_temp.net('a1', 'cr1'), 0::bigint, 'M9 Alex is settled');

-- G1: the comps' scenario. Atish paid for your dinner, but you pay Tyler.
select pg_temp.g1('G');
select is(pg_temp.net('atishG', 'crG'), 0::bigint, 'G1 Atish is settled');
select is(pg_temp.suggest('youG', 'crG'), 'you>tyler:3000', 'G1 one payment: you pay Tyler $30');

-- G3: two payments where pairwise would need them between the right people anyway.
select tests.users('annG3', 'boG3', 'cyG3', 'diG3');
select tests.trip('tG3', array['annG3', 'boG3', 'cyG3', 'diG3']);
select tests.equal('tG3', 'annG3', 6000, array['annG3', 'cyG3']);
select tests.equal('tG3', 'boG3', 4000, array['boG3', 'diG3']);
select is(pg_temp.suggest('annG3', 'tG3'), 'cy>ann:3000,di>bo:2000', 'G3 two payments settle four people');

-- G4, P1: a partial payment, then the rest with a date.
select pg_temp.log('youG', 'tylerG', 'pay', 'crG:1000');
select is(pg_temp.suggest('youG', 'crG'), 'you>tyler:2000', 'G4 a partial payment leaves the rest suggested');
select pg_temp.log('youG', 'tylerG', 'pay', 'crG:2000', gen_random_uuid(), date '2026-10-04');
select is(pg_temp.suggest('tylerG', 'crG'), '', 'G5 / P1 everyone is settled');
select is((select paid_on from public.payments where trip_id = tests.id('crG') and amount_cents = 2000), date '2026-10-04',
          'P1 the payment keeps its date');

-- P2, P3: limits.
select pg_temp.g1('L');
select throws_ok($$ select pg_temp.log('youL', 'tylerL', 'pay', 'crL:4000') $$, 'P0001', 'amount is more than what is owed',
                 'P2 can''t pay more than Tyler is owed');
select throws_ok($$ select pg_temp.log('youL', 'atishL', 'pay', 'crL:1000') $$, 'P0001', 'nothing is owed',
                 'P3 can''t pay Atish, who isn''t owed anything');

-- P4, P5: the total across two trips, then a retry.
select tests.users('youP', 'tylerP');
select tests.trip('crP', array['youP', 'tylerP']);
select tests.trip('lhP', array['youP', 'tylerP']);
select tests.equal('crP', 'tylerP', 3000, array['youP']);
select tests.equal('lhP', 'tylerP', 1500, array['youP']);
select is(pg_temp.log('youP', 'tylerP', 'pay', 'crP:3000,lhP:1500', '00000000-0000-0000-0000-0000000000f4'),
          'crP:3000,lhP:1500', 'P4 one payment per trip');
select is(pg_temp.log('youP', 'tylerP', 'pay', 'crP:3000,lhP:1500', '00000000-0000-0000-0000-0000000000f4'),
          'crP:3000,lhP:1500', 'P5 a retry returns the same payments');
select is((select count(*) from public.payments where payer_id = tests.id('youP'))::int, 2, 'P5 and creates nothing new');

-- P6: recording what someone paid you.
select tests.users('youR', 'joR');
select tests.trip('crR', array['youR', 'joR']);
select tests.equal('crR', 'youR', 800, array['joR']);
select pg_temp.log('youR', 'joR', 'record', 'crR:800');
select is(pg_temp.net('joR', 'crR'), 0::bigint, 'P6 recording settles Jo');

select * from finish();
rollback;
