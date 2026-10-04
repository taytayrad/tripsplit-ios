-- Balance golden cases M1–M8, M10 (docs/money-rules.md), through the balance read functions.
-- M9 needs payments and lives in 003_payments. Each scenario has its own people so header totals don't mix.
begin;
create extension if not exists pgtap with schema extensions;
select plan(18);

create temp table t_ids (k text primary key, id uuid) on commit drop;
create temp table t_tok (k text primary key, token text) on commit drop;
grant all on t_ids, t_tok to authenticated;
create function pg_temp.id(k text) returns uuid language sql as $$ select id from t_ids where t_ids.k = $1 $$;

create function pg_temp.users(variadic ks text[]) returns void language sql as $$
  insert into t_ids select k, tests.create_user(k) from unnest(ks) k $$;

-- Creates a trip owned by the first person; the rest join in order.
create function pg_temp.trip(k text, people text[], p_start date default null) returns void language plpgsql as $$
declare p text; v_token text;
begin
  perform tests.authenticate_as(pg_temp.id(people[1]));
  insert into t_ids values (k, public.create_trip(k, '{"shape":"circle","glyph":"house","ink":"green","rotation":0,"offsetX":0,"offsetY":0}',
                                                  p_start, p_start + 3));
  v_token := (select invite_token from public.trips where id = pg_temp.id(k));
  insert into t_tok values (k, v_token);
  foreach p in array people[2:] loop
    perform tests.authenticate_as(pg_temp.id(p));
    perform public.join_trip(v_token);
  end loop;
end $$;

-- An expense paid by `payer`, split equally among `people`.
create function pg_temp.equal(trip text, payer text, cents int, people text[]) returns void language plpgsql as $$
begin
  perform tests.authenticate_as(pg_temp.id(payer));
  perform public.save_expense(pg_temp.id(trip), null, 'Expense', 'general', cents, pg_temp.id(payer), 'equal',
    (select jsonb_agg(jsonb_build_object('user_id', pg_temp.id(p), 'value', 1)) from unnest(people) p), current_date);
end $$;

-- Reads, as `who`.
create function pg_temp.net(who text, trip text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(pg_temp.id(who));
  return coalesce((select cents from public.my_trip_nets() where trip_id = pg_temp.id(trip)), 0);
end $$;
create function pg_temp.pair(who text, trip text, other text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(pg_temp.id(who));
  return coalesce((select cents from public.my_pair_balances() where trip_id = pg_temp.id(trip) and other_user_id = pg_temp.id(other)), 0);
end $$;
create function pg_temp.combined(who text) returns text language plpgsql as $$
begin
  perform tests.authenticate_as(pg_temp.id(who));
  return coalesce((select string_agg(k || '=' || cents, ',' order by k)
                   from public.my_combined_balances() b join t_ids on t_ids.id = b.other_user_id), '');
end $$;
create function pg_temp.header(who text) returns bigint language plpgsql as $$
begin
  perform tests.authenticate_as(pg_temp.id(who));
  return public.my_header_total();
end $$;

-- M1: You pay $84.20, equal You/Alex/Jordan.
select pg_temp.users('y1', 'a1', 'j1');
select pg_temp.trip('cr1', array['y1', 'a1', 'j1']);
select pg_temp.equal('cr1', 'y1', 8420, array['y1', 'a1', 'j1']);
select is(pg_temp.net('y1', 'cr1'), 5614::bigint, 'M1 your trip net +56.14');
select is(pg_temp.net('a1', 'cr1'), -2806::bigint, 'M1 Alex −28.06');
select is(pg_temp.net('j1', 'cr1'), -2808::bigint, 'M1 Jordan −28.08');
select is(pg_temp.pair('y1', 'cr1', 'a1'), 2806::bigint, 'M1 pair(you, Alex) +28.06');
select is(pg_temp.pair('y1', 'cr1', 'j1'), 2808::bigint, 'M1 pair(you, Jordan) +28.08');

-- M2: You pay $30 split equally between Alex and Jordan only (payer outside the split).
select pg_temp.users('y2', 'a2', 'j2');
select pg_temp.trip('nm2', array['y2', 'a2', 'j2']);
select pg_temp.equal('nm2', 'y2', 3000, array['a2', 'j2']);
select is(pg_temp.net('y2', 'nm2'), 3000::bigint, 'M2 payer outside the split is owed the full $30');
select is(pg_temp.net('a2', 'nm2'), -1500::bigint, 'M2 Alex −15');

-- M3: the PRD's header example. You owe Alex 90, Jordan 90, Connor 12; Tyler owes you 64.
select pg_temp.users('y3', 'a3', 'j3', 'c3', 't3');
select pg_temp.trip('cr3', array['y3', 'a3', 'j3']);
select pg_temp.trip('nm3', array['y3', 'c3']);
select pg_temp.trip('lh3', array['y3', 't3']);
select pg_temp.equal('cr3', 'a3', 9000, array['y3']);
select pg_temp.equal('cr3', 'j3', 9000, array['y3']);
select pg_temp.equal('nm3', 'c3', 1200, array['y3']);
select pg_temp.equal('lh3', 'y3', 6400, array['t3']);
select is(pg_temp.header('y3'), -12800::bigint, 'M3 header is −128');
select is(pg_temp.combined('y3'), 'a3=-9000,c3=-1200,j3=-9000,t3=6400', 'M3 one row per person, signed, summing to the header');

-- M4: you owe Alex 60 on Coast Road and 30 on Lake House → one combined row of −90.
select pg_temp.users('y4', 'a4');
select pg_temp.trip('cr4', array['y4', 'a4']);
select pg_temp.trip('lh4', array['y4', 'a4']);
select pg_temp.equal('cr4', 'a4', 6000, array['y4']);
select pg_temp.equal('lh4', 'a4', 3000, array['y4']);
select is(pg_temp.combined('y4'), 'a4=-9000', 'M4 two trips with Alex are one row');

-- M5: you owe Alex 20 on one trip, Alex owes you 20 on another → combined 0, not listed.
select pg_temp.users('y5', 'a5');
select pg_temp.trip('cr5', array['y5', 'a5']);
select pg_temp.trip('lh5', array['y5', 'a5']);
select pg_temp.equal('cr5', 'a5', 2000, array['y5']);
select pg_temp.equal('lh5', 'y5', 2000, array['a5']);
select is(pg_temp.combined('y5'), '', 'M5 a combined $0 person is not listed');
select is(pg_temp.header('y5'), 0::bigint, 'M5 header $0');

-- M6 / M7: M1's trip deleted, then undeleted.
select tests.authenticate_as(pg_temp.id('a1'));
select public.delete_trip(pg_temp.id('cr1'));
select is(pg_temp.header('y1'), 0::bigint, 'M6 a deleted trip contributes nothing to the header');
select is(pg_temp.combined('y1'), '', 'M6 and nobody is listed');
select tests.authenticate_as(pg_temp.id('j1'));
select public.undelete_trip(pg_temp.id('cr1'));
select is(pg_temp.header('y1'), 5614::bigint, 'M7 undeleting restores the balance exactly');

-- M8: Sam joins M1's trip after the expense.
select pg_temp.users('s1');
select tests.authenticate_as(pg_temp.id('s1'));
select public.join_trip((select token from t_tok where k = 'cr1'));
select is(pg_temp.net('y1', 'cr1'), 5614::bigint, 'M8 a late joiner leaves earlier balances unchanged');
select is(pg_temp.net('s1', 'cr1'), 0::bigint, 'M8 and owes nothing');

-- M10: Alex pays $60 dinner and you pay $30 gas, both equal You/Alex/Jordan → you owe Alex $10.
select pg_temp.users('y10', 'a10', 'j10');
select pg_temp.trip('cr10', array['y10', 'a10', 'j10']);
select pg_temp.equal('cr10', 'a10', 6000, array['y10', 'a10', 'j10']);
select pg_temp.equal('cr10', 'y10', 3000, array['y10', 'a10', 'j10']);
select is(pg_temp.pair('y10', 'cr10', 'a10'), -1000::bigint, 'M10 pairwise, no debt simplification: you owe Alex $10');

select * from finish();
rollback;
