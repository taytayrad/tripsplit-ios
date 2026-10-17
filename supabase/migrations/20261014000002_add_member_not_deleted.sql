-- A deleted account (TRIP-28) keeps its profile for friends' history, but it has no sign-in, so it can't be added
-- back to a trip.
create or replace function public.add_member(p_trip uuid, p_user uuid)
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
  if not exists (select 1 from auth.users where id = p_user) then
    raise exception 'that account was deleted';
  end if;
  if not private.shares_a_trip(v_user, p_user) then
    raise exception 'you can only add people you already share a trip with';
  end if;
  insert into public.trip_members (trip_id, user_id) values (p_trip, p_user)
  on conflict (trip_id, user_id) do update set removed_at = null, removed_by = null, removal = null;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select p_trip, p_user, 'member_joined', name from public.trips where id = p_trip;
end;
$$;
