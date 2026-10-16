-- Delete account (TRIP-28).
begin;
create extension if not exists pgtap with schema extensions;
select plan(26);

-- Refused while a live trip has a balance; nothing changes.
select tests.users('owe', 'pal');
select tests.trip('live', array['owe', 'pal']);
select tests.equal('live', 'pal', 2000, array['owe', 'pal']);  -- owe -$10
select tests.authenticate_as(tests.id('owe'));
select is(public.my_unsettled_trip_count(), 1, 'a live balance counts');
select throws_ok('select public.delete_account()', 'P0001', 'settle up on every trip before deleting your account',
                 'refused with a live balance');
select ok(private.is_active_member(tests.id('live'), tests.id('owe')), 'nothing changed');

-- Refused while a deleted trip has a balance: deleted isn't settled.
select tests.users('ghost', 'mate');
select tests.trip('gone', array['ghost', 'mate']);
select tests.equal('gone', 'ghost', 2000, array['ghost', 'mate']);  -- ghost +$10
select tests.authenticate_as(tests.id('mate'));
select public.delete_trip(tests.id('gone'));
select tests.authenticate_as(tests.id('ghost'));
select is(public.my_unsettled_trip_count(), 1, 'a deleted trip''s balance counts');
select throws_ok('select public.delete_account()', 'P0001', 'settle up on every trip before deleting your account',
                 'refused with a balance on a deleted trip');

-- Settled everywhere: a shared trip with a balance between others, a trip where they're the last member, and a
-- deleted trip at $0.
select tests.users('jordan', 'alex', 'sam');
select tests.trip('shared', array['jordan', 'alex', 'sam']);
select tests.equal('shared', 'alex', 2000, array['alex', 'sam']);  -- alex +10, sam -10, jordan 0
select tests.trip('solo', array['jordan']);
select tests.trip('old', array['jordan', 'alex']);
select tests.authenticate_as(tests.id('alex'));
select public.delete_trip(tests.id('old'));
select tests.clear_authentication();
create temp table before_nets on commit drop as
  select user_id, cents from private.member_nets where trip_id = tests.id('shared');
select tests.authenticate_as(tests.id('jordan'));
select public.register_device_token('jordan-token');
select is(public.my_unsettled_trip_count(), 0, 'settled everywhere');
select lives_ok('select public.delete_account()', 'deleted when settled everywhere');

select tests.clear_authentication();
select is((select count(*)::int from auth.users where id = tests.id('jordan')), 0, 'the auth user is gone');
select results_eq(
  format('select display_name, venmo_username, has_zelle, has_apple_cash, notify_paid from public.profiles where id = %L', tests.id('jordan')),
  $$ values ('Deleted account'::text, null::text, false, false, false) $$,
  'the profile stays, renamed and cleared');
select is((select count(*)::int from public.device_tokens where user_id = tests.id('jordan')), 0, 'device tokens are gone');
select is((select count(*)::int from public.trip_members where user_id = tests.id('jordan') and removed_at is null), 0,
          'removed from every trip, deleted ones too');
select is((select count(*)::int from public.trip_members where user_id = tests.id('jordan') and removal = 'settled'), 3,
          'each removal is settled');
select results_eq(format('select user_id, cents from private.member_nets where trip_id = %L order by user_id', tests.id('shared')),
                  'select user_id, cents from before_nets order by user_id', 'others'' nets don''t change');

-- The last member's trip is deleted, so its invite dies; a trip with others stays and its invite works.
select isnt((select deleted_at from public.trips where id = tests.id('solo')), null, 'the last member''s trip is deleted');
select is((select deleted_at from public.trips where id = tests.id('shared')), null, 'a trip with others stays');
select tests.users('newbie');
select tests.authenticate_as(tests.id('newbie'));
select throws_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'solo')),
                 'P0001', 'invite link not found', 'the deleted trip''s invite fails');
select lives_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'shared')),
                'the shared trip''s invite still works');

-- A deleted account can't be added back: it has no sign-in.
select tests.trip('next', array['alex']);
select tests.authenticate_as(tests.id('alex'));
select throws_ok(format('select public.add_member(%L, %L)', tests.id('next'), tests.id('jordan')),
                 'P0001', 'that account was deleted', 'a deleted account can''t be added to a trip');

-- Past leaves stay leaves: the snapshot keeps the name they had.
select tests.clear_authentication();
select is((select actor_name from public.activity_events
           where trip_id = tests.id('shared') and kind = 'member_removed' and actor_id = tests.id('jordan')), 'jordan',
          'the leave keeps the actor''s name from before the rename');

-- Signing up again with the same name creates a separate person, with no old membership or debt.
insert into tests.names (k, id) values ('jordan-returned', tests.create_user('jordan'));
select tests.authenticate_as(tests.id('jordan-returned'));
select is((select count(*)::int from public.trips), 0, 'the new account starts without trips');
select lives_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'shared')),
                'the new account can rejoin the shared trip by invite');
select is((select count(*)::int from public.trips where id = tests.id('shared')), 1,
          'the joined trip is readable on the new account');
select is((select count(*)::int from public.trip_members m
           left join public.profiles p on p.id = m.user_id
           where m.trip_id = tests.id('shared') and p.id is null), 0,
          'every embedded member profile is readable, including the deleted account');
select is((select coalesce(sum(cents), 0)::int from public.my_trip_nets()), 0,
          'the new account has no inherited balance');
select tests.authenticate_as(tests.id('alex'));
select is((select display_name from public.profiles where id = tests.id('jordan-returned')), 'jordan',
          'friends can read the new account''s name');
select is((select display_name from public.profiles where id = tests.id('jordan')), 'Deleted account',
          'the old account stays anonymized');

select * from finish();
rollback;
