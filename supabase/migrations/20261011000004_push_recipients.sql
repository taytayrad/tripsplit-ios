-- Who gets a push for one activity event (TRIP-24, docs/events.md). The push function (TRIP-25) calls this with
-- the service role for each inserted event, then sends to each recipient's device tokens. Never the actor; a
-- preference that is off drops that person. Name, date, and stamp edits write no event, so they push nothing.
create function public.push_recipients(p_event uuid)
returns setof uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
  e public.activity_events;
begin
  select * into e from public.activity_events where id = p_event;
  if e.id is null then
    return;
  end if;

  return query
  with candidates as (
    -- Every other active member: someone joined, or the trip was deleted or restored.
    select m.user_id from public.trip_members m
    where e.kind in ('member_joined', 'trip_deleted', 'trip_undeleted')
      and m.trip_id = e.trip_id and m.removed_at is null
    union
    -- Members whose balance the expense changes.
    select d.key::uuid from jsonb_each(e.deltas) d
    where e.kind in ('expense_added', 'expense_updated', 'expense_deleted', 'expense_restored')
      and d.value::bigint <> 0
    union
    -- A logged payment: only the person paid.
    select p.payee_id from public.payments p
    where e.kind = 'payment_logged' and p.id = e.payment_id
    union
    -- A removed payment: the other person on it.
    select x.user_id from public.payments p
    cross join lateral (values (p.payer_id), (p.payee_id)) x (user_id)
    where e.kind = 'payment_deleted' and p.id = e.payment_id
  )
  select c.user_id
  from candidates c
  join public.profiles pr on pr.id = c.user_id
  where c.user_id <> e.actor_id
    and case
          when e.kind = 'member_joined' then pr.notify_join
          when e.kind like 'expense\_%' then pr.notify_expense
          when e.kind like 'payment\_%' then pr.notify_paid
          when e.kind in ('trip_deleted', 'trip_undeleted') then pr.notify_trip_deleted
          else false  -- trip_created, member_removed, and any kind added later: nobody until decided
        end;
end;
$$;

revoke execute on function public.push_recipients(uuid) from public, anon, authenticated;
grant execute on function public.push_recipients(uuid) to service_role;
