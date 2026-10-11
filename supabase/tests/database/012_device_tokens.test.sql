-- Push tokens (TRIP-23, PR #36 review): one account per phone token.
begin;
create extension if not exists pgtap with schema extensions;
select plan(7);

select tests.users('you', 'jo');

-- You register this phone.
select tests.authenticate_as(tests.id('you'));
select public.register_device_token('phone-a');
select is((select count(*) from public.device_tokens where token = 'phone-a')::int, 1, 'your token is saved');
select public.register_device_token('phone-a');
select is((select count(*) from public.device_tokens)::int, 1, 'registering again keeps one row');

-- You signed out without the row being deleted (offline). Jo signs in on the same phone.
select tests.authenticate_as(tests.id('jo'));
select public.register_device_token('phone-a');
select tests.authenticate_as(tests.id('you'));
select is((select count(*) from public.device_tokens)::int, 0, 'the token is no longer yours');
select tests.authenticate_as(tests.id('jo'));
select is((select count(*) from public.device_tokens where token = 'phone-a')::int, 1, 'it is Jo''s now');

-- Writes go through the function; your own rows can still be deleted.
select throws_ok($$ insert into public.device_tokens (user_id, token) values (auth.uid(), 'phone-b') $$,
                 '42501', null, 'no direct insert');
delete from public.device_tokens where token = 'phone-a';
select is((select count(*) from public.device_tokens)::int, 0, 'you can delete your own token (sign-out)');
select throws_ok($$ select public.register_device_token('') $$, 'P0001', 'a device token is required', 'an empty token is refused');

select * from finish();
rollback;
