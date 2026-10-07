-- Access rules (docs/permissions.md): who can read what, and that money tables only change via functions.
begin;
create extension if not exists pgtap with schema extensions;
select plan(19);

select tests.users('you', 'alex', 'olive');  -- Olive is an outsider
select tests.trip('cr', array['you', 'alex']);
create temp table t_e on commit drop as select tests.equal('cr', 'you', 8420, array['you', 'alex']) as id;
grant select on t_e to authenticated;
select tests.authenticate_as(tests.id('alex'));
select public.log_payment(tests.id('you'), 'pay', 'cash', gen_random_uuid(), current_date,
                          jsonb_build_array(jsonb_build_object('trip_id', tests.id('cr'), 'cents', 1000)));

-- An outsider sees nothing of the trip.
select tests.authenticate_as(tests.id('olive'));
select is((select count(*) from public.trips)::int, 0, 'outsider: no trips');
select is((select count(*) from public.trip_members)::int, 0, 'outsider: no members');
select is((select count(*) from public.expenses)::int, 0, 'outsider: no expenses');
select is((select count(*) from public.expense_shares)::int, 0, 'outsider: no shares');
select is((select count(*) from public.payments)::int, 0, 'outsider: no payments');
select is((select count(*) from public.activity_events)::int, 0, 'outsider: no activity');
select is((select count(*) from public.profiles where id <> tests.id('olive'))::int, 0, 'outsider: no one else''s profile');
select throws_ok(format('select public.save_expense(%L, null, %L, %L, 100, %L, %L, %L, current_date)',
                        tests.id('cr'), 'Sneaky', 'general', tests.id('olive'), 'equal',
                        jsonb_build_array(jsonb_build_object('user_id', tests.id('olive'), 'value', 1))),
                 'P0001', 'not a member of this trip', 'outsider: can''t add expenses');

-- Members see each other.
select tests.authenticate_as(tests.id('alex'));
select is((select count(*) from public.profiles)::int, 2, 'member: sees own and co-member profiles');

-- Money tables can't be written directly, even by members.
select tests.authenticate_as(tests.id('you'));
select throws_ok(format('insert into public.expenses (trip_id, description, amount_cents, payer_id, split_kind, created_by) values (%L, %L, 100, %L, %L, %L)',
                        tests.id('cr'), 'Direct', tests.id('you'), 'equal', tests.id('you')),
                 '42501', null, 'expenses: no direct insert');
select throws_ok(format('insert into public.payments (trip_id, payer_id, payee_id, amount_cents, method, logged_by, request_id) values (%L, %L, %L, 100, %L, %L, gen_random_uuid())',
                        tests.id('cr'), tests.id('alex'), tests.id('you'), 'cash', tests.id('you')),
                 '42501', null, 'payments: no direct insert');
select throws_ok(format('update public.expense_shares set share_cents = 0 where expense_id = %L', (select id from t_e)),
                 '42501', null, 'shares: no direct update');
select throws_ok(format('update public.trips set deleted_at = now() where id = %L', tests.id('cr')),
                 '42501', null, 'trips: deleted_at can only change through delete_trip');

-- What members can edit directly: trip details and their own profile.
update public.trips set name = 'Coast Road 2026' where id = tests.id('cr');
select is((select name from public.trips where id = tests.id('cr')), 'Coast Road 2026', 'trips: members can rename');
update public.trips set stamp = '{"shape":"circle"}' where id = tests.id('cr');
select is((select stamp->>'shape' from public.trips where id = tests.id('cr')), 'circle', 'trips: members can change the stamp');
update public.profiles set display_name = 'Hacked' where id = tests.id('alex');
select tests.authenticate_as(tests.id('alex'));
select isnt((select display_name from public.profiles where id = tests.id('alex')), 'Hacked', 'profiles: can''t edit someone else''s');

-- Signed out: no functions.
select tests.clear_authentication();
set local role anon;
select throws_ok('select public.my_header_total()', '42501', null, 'anon: can''t call balance functions');
reset role;

-- The share-sum invariant holds even for writes that bypass the functions.
insert into public.expense_shares (expense_id, user_id, share_cents) values ((select id from t_e), tests.id('alex'), 1)
  on conflict (expense_id, user_id) do update set share_cents = public.expense_shares.share_cents + 1;
select throws_ok('set constraints all immediate', 'P0001', null, 'shares that don''t add up to the expense are rejected');

-- Signed-out callers get nothing but the invite preview. A new function that forgets to revoke PUBLIC fails here.
select is(
  (select array_agg(p.proname::text order by p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute')),
  array['invite_preview'],
  'anon can execute only invite_preview');

select * from finish();
rollback;
