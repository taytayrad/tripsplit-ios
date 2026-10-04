-- Local and CI only (seed files are never pushed to the hosted project).
-- Test helpers: create users and act as them, the way the app's signed-in requests do.

create schema if not exists tests;
grant usage on schema tests to anon, authenticated;

-- Creates an auth user (the profile trigger creates their profile) and returns the id.
create or replace function tests.create_user(p_name text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_id uuid := gen_random_uuid();
begin
  insert into auth.users (id, instance_id, aud, role, email, raw_user_meta_data, created_at, updated_at)
  values (v_id, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
          lower(p_name) || '-' || left(v_id::text, 8) || '@test.local',
          jsonb_build_object('name', p_name), now(), now());
  return v_id;
end;
$$;

-- Act as a signed-in user for the rest of the transaction.
create or replace function tests.authenticate_as(p_user uuid)
returns void
language plpgsql
as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_user, 'role', 'authenticated')::text, true);
  execute 'set local role authenticated';
end;
$$;

-- Back to the test runner's role (postgres).
create or replace function tests.clear_authentication()
returns void
language plpgsql
as $$
begin
  execute 'reset role';
  perform set_config('request.jwt.claims', '', true);
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;

-- Named people and trips for readable tests: tests.users('you', 'alex'), tests.id('alex').
create table tests.names (k text primary key, id uuid not null, token text);
grant all on tests.names to anon, authenticated;

create or replace function tests.id(p_k text)
returns uuid language sql stable as $$ select id from tests.names where k = p_k $$;

create or replace function tests.users(variadic p_names text[])
returns void language sql as $$
  insert into tests.names (k, id) select k, tests.create_user(k) from unnest(p_names) k
$$;

-- A trip created by people[1]; the rest join in order (that order is member order).
create or replace function tests.trip(p_k text, p_people text[], p_start date default null)
returns uuid language plpgsql as $$
declare
  v_trip uuid;
  v_token text;
  p text;
begin
  perform tests.authenticate_as(tests.id(p_people[1]));
  v_trip := public.create_trip(p_k, '{"shape":"circle","glyph":"house","ink":"green","rotation":0,"offsetX":0,"offsetY":0}',
                               p_start, p_start + 3);
  v_token := (select invite_token from public.trips where id = v_trip);
  insert into tests.names (k, id, token) values (p_k, v_trip, v_token);
  foreach p in array p_people[2:] loop
    perform tests.authenticate_as(tests.id(p));
    perform public.join_trip(v_token);
  end loop;
  return v_trip;
end;
$$;

-- An expense paid by p_payer, split equally among p_people. Returns the expense id.
create or replace function tests.equal(p_trip text, p_payer text, p_cents integer, p_people text[])
returns uuid language plpgsql as $$
begin
  perform tests.authenticate_as(tests.id(p_payer));
  return public.save_expense(tests.id(p_trip), null, 'Expense', 'general', p_cents, tests.id(p_payer), 'equal',
    (select jsonb_agg(jsonb_build_object('user_id', tests.id(p), 'value', 1)) from unnest(p_people) p), current_date);
end;
$$;

grant execute on all functions in schema tests to anon, authenticated;
