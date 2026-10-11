-- The same token keeps its learned host. A new token or owner starts unclassified.
create or replace function public.register_device_token(p_token text)
returns void language plpgsql security definer set search_path = '' as $$
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

-- Credentials stay in Vault, rather than in trigger arguments or migrations. pg_net sends only after commit.
create or replace function private.push_activity_event()
returns trigger language plpgsql security definer set search_path = '' as $$
declare
  v_url text;
  v_secret text;
begin
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'push_function_url';
  select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
  if coalesce(v_url, '') = '' or coalesce(v_secret, '') = '' then
    -- Local tests and a project awaiting setup still save activity normally.
    return new;
  end if;
  -- shortcut: no durable webhook retry; add an outbox when the beta needs recovery after delivery failures.
  perform net.http_post(
    url := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_secret),
    body := jsonb_build_object('type', 'INSERT', 'schema', 'public', 'table', 'activity_events',
                              'record', jsonb_build_object('id', new.id)),
    timeout_milliseconds := 10000
  );
  return new;
exception when others then
  -- Push is best effort; queue/Vault failures must not roll back expenses or payments.
  raise warning 'Push enqueue failed for activity %, SQLSTATE %', new.id, sqlstate;
  return new;
end;
$$;
revoke all on function private.push_activity_event() from public, anon, authenticated;

drop trigger push_activity_event on public.activity_events;
create trigger push_activity_event after insert on public.activity_events
for each row when (new.kind not in ('trip_created', 'member_removed'))
execute function private.push_activity_event();
