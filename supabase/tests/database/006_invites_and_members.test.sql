-- Phase 2 database additions: adding people you know and the invite preview.
begin;
create extension if not exists pgtap with schema extensions;
select plan(10);

select tests.users('you', 'alex', 'sam', 'olive');
select tests.trip('cr', array['you', 'alex']);          -- you and Alex share Coast Road
select tests.trip('lh', array['you', 'sam']);           -- you and Sam share Lake House

-- add_member: you can add someone you already share a trip with.
select tests.authenticate_as(tests.id('you'));
select public.add_member(tests.id('cr'), tests.id('sam'));
select ok(private.is_active_member(tests.id('cr'), tests.id('sam')), 'add_member: Sam (from Lake House) is now on Coast Road');
select is((select count(*) from public.activity_events where trip_id = tests.id('cr') and kind = 'member_joined'
           and actor_id = tests.id('sam') and subject = 'cr')::int, 1,
          'add_member: logged as Sam joining the trip');
select throws_ok(format('select public.add_member(%L, %L)', tests.id('cr'), tests.id('olive')),
                 'P0001', 'you can only add people you already share a trip with', 'add_member: strangers need the link');
select tests.authenticate_as(tests.id('olive'));
select throws_ok(format('select public.add_member(%L, %L)', tests.id('cr'), tests.id('olive')),
                 'P0001', 'not a member of this trip', 'add_member: outsiders can''t add themselves');

-- invite_preview: readable before signing in, shows only the trip name, inviter, and stamp.
select tests.clear_authentication();
set local role anon;
select is((select trip_name from public.invite_preview((select token from tests.names where k = 'cr'))), 'cr',
          'invite_preview: signed-out users see the trip name');
select is((select inviter_name from public.invite_preview((select token from tests.names where k = 'cr'))), 'you',
          'invite_preview: and who created it');
select is((select count(*) from public.invite_preview('not-a-token'))::int, 0, 'invite_preview: unknown tokens return nothing');
reset role;
select tests.authenticate_as(tests.id('you'));
select public.delete_trip(tests.id('lh'));
select tests.clear_authentication();
set local role anon;
select is((select count(*) from public.invite_preview((select token from tests.names where k = 'lh')))::int, 0,
          'invite_preview: deleted trips return nothing');
reset role;

-- Removed members keep their name on the trip, and still see the people they shared it with.
select tests.authenticate_as(tests.id('you'));
select public.remove_member(tests.id('cr'), tests.id('alex'));
select is((select display_name from public.profiles where id = tests.id('alex')), 'alex',
          'profiles: a removed member''s name stays visible to the trip');
select tests.authenticate_as(tests.id('alex'));
select is((select display_name from public.profiles where id = tests.id('you')), 'you',
          'profiles: a removed member still sees who they settle up with');

select * from finish();
rollback;
