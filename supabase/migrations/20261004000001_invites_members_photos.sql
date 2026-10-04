-- Phase 2: adding people you know, the pre-sign-in invite preview, and trip photo storage.

-- "On TripSplit": add someone you already share a trip with. Everyone else joins by link.
create function public.add_member(p_trip uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  perform private.require_active_trip(p_trip, v_user);
  if private.is_active_member(p_trip, p_user) then
    return;
  end if;
  if not private.shares_a_trip(v_user, p_user) then
    raise exception 'you can only add people you already share a trip with';
  end if;
  insert into public.trip_members (trip_id, user_id) values (p_trip, p_user)
  on conflict (trip_id, user_id) do update set removed_at = null, removed_by = null, removal = null;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select p_trip, v_user, 'member_joined', p.display_name from public.profiles p where p.id = p_user;
end;
$$;

-- What the sign-in screen shows for an invite link, before the person has an account:
-- the trip's name and stamp, and the creator's name. Nothing else about the trip.
create function public.invite_preview(p_invite_token text)
returns table (trip_name text, inviter_name text, stamp jsonb)
language sql
stable
security definer
set search_path = ''
as $$
  select t.name, p.display_name, t.stamp
  from public.trips t join public.profiles p on p.id = t.created_by
  where t.invite_token = p_invite_token and t.deleted_at is null;
$$;

grant execute on function public.add_member(uuid, uuid) to authenticated;
grant execute on function public.invite_preview(text) to anon, authenticated;

-- Trip photos live at trip-photos/<trip_id>/<file>. Active members of that trip can read and write.
insert into storage.buckets (id, name, public) values ('trip-photos', 'trip-photos', false)
on conflict (id) do nothing;

create function private.is_member_of_folder(p_object_name text)
returns boolean
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  return private.is_active_member(split_part(p_object_name, '/', 1)::uuid, auth.uid());
exception when invalid_text_representation then
  return false;
end;
$$;
grant execute on function private.is_member_of_folder(text) to authenticated;

create policy "trip photos: members read" on storage.objects for select to authenticated
  using (bucket_id = 'trip-photos' and private.is_member_of_folder(name));
create policy "trip photos: members upload" on storage.objects for insert to authenticated
  with check (bucket_id = 'trip-photos' and private.is_member_of_folder(name));
create policy "trip photos: members replace" on storage.objects for update to authenticated
  using (bucket_id = 'trip-photos' and private.is_member_of_folder(name));
create policy "trip photos: members delete" on storage.objects for delete to authenticated
  using (bucket_id = 'trip-photos' and private.is_member_of_folder(name));

-- Profiles: anyone you've ever shared a trip with, removed or not. A removed member's name still shows on
-- the trip, and with "keep" they still settle up, so both sides need each other's name and pay methods.
create or replace function private.shares_a_trip(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_members a
    join public.trip_members b on b.trip_id = a.trip_id
    where a.user_id = p_a and b.user_id = p_b
  );
$$;
