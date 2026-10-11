-- A phone's push token belongs to one account at a time (PR #36 review). Otherwise a token left behind by an
-- account that signed out (offline, or after a relaunch the app no longer knew its token) would keep receiving
-- that account's pushes on a phone someone else now uses. Registering through register_device_token moves the
-- token to you, removing it from any other account, and the unique index makes that the only possible state.

delete from public.device_tokens d
where exists (select 1 from public.device_tokens n where n.token = d.token and n.updated_at > d.updated_at);
create unique index device_tokens_token_key on public.device_tokens (token);

create function public.register_device_token(p_token text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  if p_token is null or length(p_token) = 0 then
    raise exception 'a device token is required';
  end if;
  delete from public.device_tokens where token = p_token and user_id <> v_user;
  insert into public.device_tokens (user_id, token, updated_at) values (v_user, p_token, now())
  on conflict (user_id, token) do update set updated_at = now();
end;
$$;

revoke execute on function public.register_device_token(text) from public, anon;
grant execute on function public.register_device_token(text) to authenticated;
-- Writes go through the function; you can still delete your own rows (sign-out).
revoke insert, update on public.device_tokens from authenticated;
