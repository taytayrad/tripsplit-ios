-- Delete account (TRIP-28): delete the auth user, keep the profile as "Deleted account" so friends keep their
-- history, and revoke Sign in with Apple after the commit.

-- The profile outlives its auth user. handle_new_user still creates one for each new auth user.
alter table public.profiles drop constraint profiles_id_fkey;

-- The actor's name when the row was written. A leave is a member_removed whose subject equals it, so renaming the
-- profile to "Deleted account" doesn't turn past leaves into removals. Screens still show the live name.
alter table public.activity_events add column actor_name text;
update public.activity_events a set actor_name = p.display_name from public.profiles p where p.id = a.actor_id;

create function private.snapshot_actor_name()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.actor_name is null then
    select display_name into new.actor_name from public.profiles where id = new.actor_id;
  end if;
  return new;
end;
$$;
revoke execute on function private.snapshot_actor_name() from public, anon, authenticated;
create trigger activity_events_actor_name before insert on public.activity_events
  for each row execute function private.snapshot_actor_name();

-- Apple refresh tokens, kept until Apple accepts the revoke. No foreign key: the row must outlive the auth user so
-- the revoke can run after the delete. Only the service role (the apple function) reads or writes it.
create table public.apple_tokens (
  user_id uuid primary key,
  refresh_token text not null,
  updated_at timestamptz not null default now()
);
alter table public.apple_tokens enable row level security;
revoke all on public.apple_tokens from public, anon, authenticated;

-- A person's net on a trip, deleted trips included (member_nets leaves them out; undelete brings a balance back).
create function private.net_including_deleted(p_trip uuid, p_user uuid)
returns bigint language sql stable set search_path = '' as $$
  select coalesce(sum(c), 0)::bigint from (
    select e.amount_cents as c from public.expenses e
    where e.trip_id = p_trip and e.payer_id = p_user and e.deleted_at is null
    union all
    select -s.share_cents from public.expenses e join public.expense_shares s on s.expense_id = e.id
    where e.trip_id = p_trip and s.user_id = p_user and e.deleted_at is null
    union all
    select p.amount_cents from public.payments p where p.trip_id = p_trip and p.payer_id = p_user and p.deleted_at is null
    union all
    select -p.amount_cents from public.payments p where p.trip_id = p_trip and p.payee_id = p_user and p.deleted_at is null
  ) x;
$$;
revoke execute on function private.net_including_deleted(uuid, uuid) from public, anon, authenticated;

-- Trips, live or deleted, where you still have a balance. Profile's delete check (F6).
create function public.my_unsettled_trip_count()
returns integer language sql stable security definer set search_path = '' as $$
  select count(*)::integer from public.trip_members m
  where m.user_id = private.current_user_id() and m.removed_at is null
    and private.net_including_deleted(m.trip_id, m.user_id) <> 0;
$$;
revoke execute on function public.my_unsettled_trip_count() from public, anon;
grant execute on function public.my_unsettled_trip_count() to authenticated;

-- One transaction. Revoking Sign in with Apple is queued with pg_net, which sends only after commit, so a rollback
-- revokes nothing and a failed revoke can't undo the delete.
create function public.delete_account()
returns void language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := private.current_user_id();
  v_trip uuid;
  v_url text;
  v_secret text;
begin
  for v_trip in select trip_id from public.trip_members where user_id = v_user and removed_at is null order by trip_id loop
    perform private.lock_trip(v_trip);
  end loop;
  if exists (select 1 from public.trip_members m
             where m.user_id = v_user and m.removed_at is null
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
    perform private.remove_settled(v_trip, v_user, v_user);
  end loop;

  update public.profiles
  set display_name = 'Deleted account', venmo_username = null, has_zelle = false, has_apple_cash = false,
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
