-- Split golden cases S1–S12 (docs/money-rules.md), through save_expense, read back as the app would.
begin;
create extension if not exists pgtap with schema extensions;
select plan(13);

create temp table t_ids (k text primary key, id uuid) on commit drop;
grant all on t_ids to authenticated;
insert into t_ids values
  ('you', tests.create_user('You')),
  ('alex', tests.create_user('Alex')),
  ('jordan', tests.create_user('Jordan'));

create function pg_temp.id(k text) returns uuid language sql as $$ select id from t_ids where t_ids.k = $1 $$;

-- You create Coast Road; Alex then Jordan join (member order: You, Alex, Jordan).
select tests.authenticate_as(pg_temp.id('you'));
insert into t_ids select 'trip', public.create_trip('Coast Road',
  '{"shape":"ticket","glyph":"road","ink":"blue","rotation":-6,"offsetX":0.02,"offsetY":-0.015}', null, null);
select set_config('test.token', (select invite_token from public.trips where id = pg_temp.id('trip')), true);
select tests.authenticate_as(pg_temp.id('alex'));
select public.join_trip(current_setting('test.token'));
select tests.authenticate_as(pg_temp.id('jordan'));
select public.join_trip(current_setting('test.token'));
select tests.authenticate_as(pg_temp.id('you'));

-- Saves an expense paid by You and returns shares in member order as text, e.g. '2806,2806,2808'.
create function pg_temp.split(p_kind text, p_amount int, p_you numeric, p_alex numeric, p_jordan numeric)
returns text language plpgsql as $$
declare v_expense uuid;
begin
  v_expense := public.save_expense(pg_temp.id('trip'), null, 'Test', 'general', p_amount, pg_temp.id('you'),
    p_kind, jsonb_build_array(
      jsonb_build_object('user_id', pg_temp.id('you'), 'value', p_you),
      jsonb_build_object('user_id', pg_temp.id('alex'), 'value', p_alex),
      jsonb_build_object('user_id', pg_temp.id('jordan'), 'value', p_jordan)), current_date);
  return (select string_agg(coalesce(s.share_cents::text, '-'), ',' order by o.ord)
          from (values (pg_temp.id('you'), 1), (pg_temp.id('alex'), 2), (pg_temp.id('jordan'), 3)) o(uid, ord)
          left join public.expense_shares s on s.expense_id = v_expense and s.user_id = o.uid);
end $$;

select is(pg_temp.split('equal', 8420, 1, 1, 1), '2806,2806,2808', 'S1 equal $84.20 in thirds, remainder to last');
select is(pg_temp.split('equal', 1000, 1, 1, 1), '333,333,334', 'S2 equal $10.00 in thirds');
select is(pg_temp.split('equal', 8420, 1, 1, 0), '4210,4210,-', 'S3 equal with Jordan unchecked');
select is(pg_temp.split('equal', 1, 1, 1, 0), '0,1,-', 'S4 equal $0.01 between two');
select is(pg_temp.split('percent', 10000, 33.33, 33.33, 33.34), '3333,3333,3334', 'S5 percent 33.33/33.33/33.34');
select is(pg_temp.split('percent', 1000, 50, 50, 0), '500,500,-', 'S6 percent 50/50/0');
select throws_ok($$ select pg_temp.split('percent', 10000, 50, 49, 0) $$, 'P0001', 'percentages must add up to 100', 'S7 percent 99% is invalid');
select is(pg_temp.split('shares', 8420, 2, 1, 1), '4210,2105,2105', 'S8 shares 2/1/1');
select is(pg_temp.split('shares', 10000, 1, 1, 1), '3333,3333,3334', 'S9 shares 1/1/1');
select throws_ok($$ select pg_temp.split('shares', 5000, 0, 0, 0) $$, 'P0001', 'at least one person must be in the split', 'S10 shares total 0 is invalid');
select is(pg_temp.split('exact', 8420, 4000, 4000, 420), '4000,4000,420', 'S11 exact amounts');
select throws_ok($$ select pg_temp.split('exact', 8420, 4000, 4000, 0) $$, 'P0001', 'amounts must add up to the expense', 'S12 exact $4.20 short is invalid');
select throws_ok($$ select pg_temp.split('equal', 8420, 0, 0, 0) $$, 'P0001', 'at least one person must be in the split', 'equal with nobody checked is invalid');

select * from finish();
rollback;
