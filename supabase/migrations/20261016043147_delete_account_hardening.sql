-- Account deletion must outlive neither authorization nor an in-flight membership/write.
alter table public.profiles add column deleted_at timestamptz;
-- Backfill from identity, never from an editable name; also erase any stale-token profile edits.
update public.profiles p
set deleted_at = now(), display_name = 'Deleted account', venmo_username = null,
    has_zelle = false, has_apple_cash = false,
    notify_paid = false, notify_expense = false, notify_join = false, notify_trip_deleted = false
where not exists (select 1 from auth.users u where u.id = p.id);
delete from public.device_tokens d using public.profiles p where p.id = d.user_id and p.deleted_at is not null;

-- Shared account locks precede trip locks. Deletion takes the exclusive version before enumerating trips.
create function private.lock_account(p_user uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_user is null then return false; end if;
  perform pg_advisory_xact_lock_shared(hashtextextended('account:' || p_user::text, 0));
  return exists (select 1 from auth.users u join public.profiles p on p.id = u.id
                 where u.id = p_user and p.deleted_at is null);
end;
$$;
revoke all on function private.lock_account(uuid) from public, anon, authenticated;

-- RLS returns false for a deleted subscriber, so Realtime can skip it without an authorization error.
create function private.account_is_active()
returns boolean language sql volatile security definer set search_path = '' as $$
  select private.lock_account(auth.uid());
$$;
revoke all on function private.account_is_active() from public, anon;
grant execute on function private.account_is_active() to authenticated;

create or replace function private.current_user_id()
returns uuid language plpgsql volatile security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
begin
  if v_user is null then raise exception 'not signed in'; end if;
  if not private.lock_account(v_user) then raise exception 'that account was deleted'; end if;
  return v_user;
end;
$$;
revoke all on function private.current_user_id() from public, anon;
grant execute on function private.current_user_id() to authenticated;

-- This trigger sorts before trip_members_limit, so an add never holds a trip while waiting on deletion.
create function private.require_live_member()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if not private.lock_account(new.user_id) then raise exception 'that account was deleted'; end if;
  return new;
end;
$$;
revoke all on function private.require_live_member() from public, anon, authenticated;
create trigger trip_members_account before insert or update of user_id, removed_at on public.trip_members
  for each row when (new.removed_at is null) execute function private.require_live_member();

-- Restrictive policies also cover direct profile/trip edits and all table reads with an old JWT.
do $$
declare v_table text;
begin
  foreach v_table in array array['profiles', 'trips', 'trip_members', 'expenses', 'expense_shares', 'payments', 'activity_events', 'device_tokens'] loop
    execute format('create policy "account must exist" on public.%I as restrictive for all to authenticated
      using ((select private.account_is_active()))
      with check ((select private.account_is_active()))', v_table);
  end loop;
end;
$$;

create or replace function public.my_trip_nets()
returns table (trip_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select n.trip_id, n.cents from private.member_nets n where n.user_id = (select private.current_user_id()) and n.cents <> 0;
$$;

-- Every suggested payment on the trips you're an active member of (members can see each other's nets), plus
-- any that involve you on a trip you were removed from.
create or replace function public.my_trip_settlements()
returns table (trip_id uuid, seq integer, payer_id uuid, payee_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select m.trip_id, s.seq, s.payer_id, s.payee_id, s.cents
  from public.trip_members m
  join public.trips t on t.id = m.trip_id and t.deleted_at is null
  cross join lateral private.suggested_payments(m.trip_id) s
  where m.user_id = (select private.current_user_id())
    and (m.removed_at is null or (select private.current_user_id()) in (s.payer_id, s.payee_id));
$$;

create or replace function public.my_unsettled_trip_count()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.trip_members m
  where m.user_id = (select private.current_user_id())
    and private.net_including_deleted(m.trip_id, m.user_id) <> 0;
$$;
revoke execute on function public.my_unsettled_trip_count() from public, anon;
grant execute on function public.my_unsettled_trip_count() to authenticated;

create or replace function public.delete_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid();
  v_trip uuid;
  v_url text;
  v_secret text;
begin
  if v_user is null then raise exception 'not signed in'; end if;
  perform pg_advisory_xact_lock(hashtextextended('account:' || v_user::text, 0));
  if not private.lock_account(v_user) then raise exception 'that account was deleted'; end if;
  for v_trip in select trip_id from public.trip_members where user_id = v_user order by trip_id loop
    perform private.lock_trip(v_trip);
  end loop;
  if exists (select 1 from public.trip_members m
             where m.user_id = v_user
               and private.net_including_deleted(m.trip_id, v_user) <> 0) then
    raise exception 'settle up on every trip before deleting your account';
  end if;

  -- A live trip where you're the last member is deleted (as delete_trip does), so its invite stops working.
  for v_trip in select m.trip_id from public.trip_members m join public.trips t on t.id = m.trip_id
                where m.user_id = v_user and m.removed_at is null and t.deleted_at is null
                  and not exists (select 1 from public.trip_members o
                                  where o.trip_id = m.trip_id and o.user_id <> v_user and o.removed_at is null) loop
    update public.trips set deleted_at = now(), deleted_by = v_user where id = v_trip;
    insert into public.activity_events (trip_id, actor_id, kind, subject)
    select v_trip, v_user, 'trip_deleted', name from public.trips where id = v_trip;
  end loop;

  -- Leave every trip, deleted ones too, at $0 (the same writes as leave_trip). Before the rename, so the leave
  -- events carry the name you had.
  for v_trip in select trip_id from public.trip_members where user_id = v_user and removed_at is null loop
    -- Recheck under the trip lock before marking the membership settled.
    perform private.lock_trip(v_trip);
    if private.net_including_deleted(v_trip, v_user) <> 0 then
      raise exception 'settle up on every trip before deleting your account';
    end if;
    perform private.remove_settled(v_trip, v_user, v_user);
  end loop;

  update public.profiles
  set deleted_at = now(), display_name = 'Deleted account', venmo_username = null, has_zelle = false, has_apple_cash = false,
      notify_paid = false, notify_expense = false, notify_join = false, notify_trip_deleted = false
  where id = v_user;
  delete from public.device_tokens where user_id = v_user;  -- the profile stays, so its cascade never runs

  if exists (select 1 from public.apple_tokens where user_id = v_user) then
    begin
      select decrypted_secret into v_url from vault.decrypted_secrets where name = 'apple_function_url';
      select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'apple_webhook_secret';
      if coalesce(v_url, '') <> '' and coalesce(v_secret, '') <> '' then
        perform net.http_post(
          url := v_url,
          headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
          body := jsonb_build_object('revoke', v_user),
          timeout_milliseconds := 10000);
      end if;
    exception when others then
      -- The token stays stored; docs/apple-revoke-setup.md retries it. The delete still happens.
      raise warning 'Apple revoke enqueue failed for %, SQLSTATE %', v_user, sqlstate;
    end;
  end if;

  delete from auth.users where id = v_user;  -- identities and sessions cascade; the profile stays
end;
$$;
revoke execute on function public.delete_account() from public, anon;
grant execute on function public.delete_account() to authenticated;
