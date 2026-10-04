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
