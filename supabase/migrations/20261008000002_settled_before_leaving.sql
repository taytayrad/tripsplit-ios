-- Remove or leave only when settled (TRIP-14, docs/money-rules.md › Removing and leaving). Keep and wipe go away:
-- a member leaves only at $0, so nothing is re-split and nobody needs a way back in to settle.

-- New removals are `settled`; rows removed with keep or wipe before this stay as they were.
alter table public.trip_members drop constraint trip_members_removal_check;
alter table public.trip_members add constraint trip_members_removal_check check (removal in ('keep', 'wipe', 'settled'));

drop function public.remove_member(uuid, uuid, text);
drop function private.wipe_member(uuid, uuid);

-- Marks a settled member removed and writes the event (no money moves, so the deltas are empty).
create function private.remove_settled(p_trip uuid, p_user uuid, p_actor uuid)
returns void
language plpgsql
set search_path = ''
as $$
begin
  update public.trip_members set removed_at = now(), removed_by = p_actor, removal = 'settled'
  where trip_id = p_trip and user_id = p_user;
  insert into public.activity_events (trip_id, actor_id, kind, subject, deltas)
  select p_trip, p_actor, 'member_removed', p.display_name, '{}'::jsonb from public.profiles p where p.id = p_user;
end;
$$;

create function public.remove_member(p_trip uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  perform private.lock_trip(p_trip);
  perform private.require_active_trip(p_trip, v_user);
  if p_user = v_user then
    raise exception 'use leave_trip to leave';
  end if;
  if not private.is_active_member(p_trip, p_user) then
    raise exception 'that person is not on this trip';
  end if;
  if private.member_net(p_trip, p_user) <> 0 then
    raise exception 'only members with a $0 balance can be removed';
  end if;
  perform private.remove_settled(p_trip, p_user, v_user);
end;
$$;

create function public.leave_trip(p_trip uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  perform private.lock_trip(p_trip);
  perform private.require_active_trip(p_trip, v_user);
  if private.member_net(p_trip, v_user) <> 0 then
    raise exception 'settle up before leaving';
  end if;
  perform private.remove_settled(p_trip, v_user, v_user);
end;
$$;

revoke execute on function public.remove_member(uuid, uuid) from public, anon;
revoke execute on function public.leave_trip(uuid) from public, anon;
grant execute on function public.remove_member(uuid, uuid) to authenticated;
grant execute on function public.leave_trip(uuid) to authenticated;
