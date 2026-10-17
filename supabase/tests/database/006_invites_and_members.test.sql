-- Phase 2 database additions: the invite preview. Since TRIP-40 the link is the only way to add people.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

select tests.users('you', 'alex', 'sam');
select tests.trip('cr', array['you', 'alex']);          -- you and Alex share Coast Road
select tests.trip('lh', array['you', 'sam']);           -- you and Sam share Lake House

select hasnt_function('public', 'add_member', array['uuid', 'uuid'], 'add_member is gone: people join only by link');

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
