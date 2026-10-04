-- Phase 2 database additions: adding people you know, the invite preview, and trip photo storage.
begin;
create extension if not exists pgtap with schema extensions;
select plan(11);

select tests.users('you', 'alex', 'sam', 'olive');
select tests.trip('cr', array['you', 'alex']);          -- you and Alex share Coast Road
select tests.trip('lh', array['you', 'sam']);           -- you and Sam share Lake House

-- add_member: you can add someone you already share a trip with.
select tests.authenticate_as(tests.id('you'));
select public.add_member(tests.id('cr'), tests.id('sam'));
select ok(private.is_active_member(tests.id('cr'), tests.id('sam')), 'add_member: Sam (from Lake House) is now on Coast Road');
select is((select count(*) from public.activity_events where trip_id = tests.id('cr') and kind = 'member_joined'
           and subject = (select display_name from public.profiles where id = tests.id('sam')))::int, 1,
          'add_member: logged as a member joining');
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

-- Trip photos: members upload under the trip's folder; outsiders can't read or write.
select tests.authenticate_as(tests.id('alex'));
select lives_ok(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)',
                       'trip-photos', tests.id('cr') || '/cover.jpg', tests.id('alex')),
                'photos: a member can upload to their trip''s folder');
select tests.authenticate_as(tests.id('olive'));
select is((select count(*) from storage.objects where bucket_id = 'trip-photos')::int, 0, 'photos: outsiders can''t see them');
select throws_ok(format('insert into storage.objects (bucket_id, name, owner_id) values (%L, %L, %L)',
                        'trip-photos', tests.id('cr') || '/sneaky.jpg', tests.id('olive')),
                 '42501', null, 'photos: outsiders can''t upload');

select * from finish();
rollback;
