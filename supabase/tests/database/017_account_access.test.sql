-- Deletion must revoke access even while the caller still has the old JWT.
begin;
create extension if not exists pgtap with schema extensions;
select plan(16);

select tests.users('gone', 'friend');
select tests.trip('shared', array['gone', 'friend']);
select tests.trip('target', array['friend']);
select tests.authenticate_as(tests.id('gone'));
select public.delete_account();
select is_empty($$update public.profiles set display_name = 'Restored' where id = tests.id('gone') returning id$$,
                'an old JWT cannot restore a deleted profile');
select throws_ok($$select public.register_device_token('stale-token')$$,
                 'P0001', 'that account was deleted', 'an old JWT cannot register a device');
select throws_ok(format('select public.join_trip(%L)', (select token from tests.names where k = 'target')),
                 'P0001', 'that account was deleted', 'an old JWT cannot join another trip');
select throws_ok($$select public.create_trip('New', '{"shape":"circle"}', null, null)$$,
                 'P0001', 'that account was deleted', 'an old JWT cannot create a trip');
select throws_ok(format('select public.save_expense(%L, null, %L, %L, 100, %L, %L, %L, current_date)',
                        tests.id('target'), 'Stale write', 'general', tests.id('gone'), 'equal',
                        jsonb_build_array(jsonb_build_object('user_id', tests.id('gone'), 'value', 1))),
                 'P0001', 'that account was deleted', 'an old JWT cannot write money through an RPC');
select is_empty('select * from public.profiles', 'an old JWT cannot read profiles');
select throws_ok('select * from public.my_trip_nets()',
                 'P0001', 'that account was deleted', 'an old JWT cannot read nets through a privileged RPC');
select throws_ok('select * from public.my_trip_settlements()',
                 'P0001', 'that account was deleted', 'an old JWT cannot read settlements through a privileged RPC');
select tests.clear_authentication();
select isnt((select deleted_at from public.profiles where id = tests.id('gone')), null,
            'deletion is recorded separately from the editable name');
select is((select display_name from public.profiles where id = tests.id('gone')), 'Deleted account',
          'failed stale writes leave the anonymous name intact');

-- A real person may choose the same name as the tombstone label.
select tests.authenticate_as(tests.id('friend'));
update public.profiles set display_name = 'Deleted account' where id = tests.id('friend');
select is((select deleted_at from public.profiles where id = tests.id('friend')), null,
          'using the tombstone label does not delete a living person');
select throws_ok('update public.profiles set deleted_at = now()', '42501', null,
                 'clients cannot change deletion status');

-- Old keep removals still carry money, including on a deleted trip.
select tests.users('kept', 'pal');
select tests.trip('legacy', array['kept', 'pal']);
select tests.equal('legacy', 'pal', 2000, array['kept', 'pal']);
select tests.clear_authentication();
update public.trip_members set removed_at = now(), removal = 'keep', removed_by = tests.id('pal')
where trip_id = tests.id('legacy') and user_id = tests.id('kept');
select tests.authenticate_as(tests.id('kept'));
select is(public.my_unsettled_trip_count(), 1, 'a removed keep balance counts');
select throws_ok('select public.delete_account()', 'P0001', 'settle up on every trip before deleting your account',
                 'a keep balance blocks deletion');
select tests.authenticate_as(tests.id('pal'));
select public.delete_trip(tests.id('legacy'));
select tests.authenticate_as(tests.id('kept'));
select is(public.my_unsettled_trip_count(), 1, 'a keep balance on a deleted trip counts');
select throws_ok('select public.delete_account()', 'P0001', 'settle up on every trip before deleting your account',
                 'a keep balance on a deleted trip blocks deletion');

select * from finish();
rollback;
