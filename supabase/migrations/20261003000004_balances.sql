-- Balances (docs/money-rules.md › Balances). Calculated, never stored. Deleted trips contribute nothing.

-- pair(a, b) on a trip: positive means b owes a. Expenses: each share holder owes the payer their share.
-- Payments: the payer's side moves up by the amount, the payee's down.
create view private.pair_balances as
select x.trip_id, x.user_a, x.user_b, sum(x.cents)::bigint as cents
from (
  select e.trip_id, e.payer_id as user_a, s.user_id as user_b, s.share_cents as cents
  from public.expenses e join public.expense_shares s on s.expense_id = e.id
  where s.user_id <> e.payer_id
  union all
  select e.trip_id, s.user_id, e.payer_id, -s.share_cents
  from public.expenses e join public.expense_shares s on s.expense_id = e.id
  where s.user_id <> e.payer_id
  union all
  select p.trip_id, p.payer_id, p.payee_id, p.amount_cents
  from public.payments p where p.deleted_at is null
  union all
  select p.trip_id, p.payee_id, p.payer_id, -p.amount_cents
  from public.payments p where p.deleted_at is null
) x
join public.trips t on t.id = x.trip_id and t.deleted_at is null
group by x.trip_id, x.user_a, x.user_b;

-- Your pairwise balances: one row per (trip, other person) that isn't $0. Positive = they owe you.
create function public.my_pair_balances()
returns table (trip_id uuid, other_user_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select trip_id, user_b, cents from private.pair_balances
  where user_a = (select auth.uid()) and cents <> 0;
$$;

-- Your net per trip.
create function public.my_trip_nets()
returns table (trip_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select trip_id, sum(cents)::bigint from public.my_pair_balances() group by trip_id;
$$;

-- Your Balance rows: one per person, across every shared trip; $0 people omitted.
create function public.my_combined_balances()
returns table (other_user_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select other_user_id, sum(cents)::bigint from public.my_pair_balances()
  group by other_user_id having sum(cents) <> 0;
$$;

-- The balance chip: the sum of Your Balance rows.
create function public.my_header_total()
returns bigint
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(sum(cents), 0)::bigint from public.my_pair_balances();
$$;

create function public.delete_trip(p_trip uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  perform private.require_active_trip(p_trip, v_user);
  update public.trips set deleted_at = now(), deleted_by = v_user where id = p_trip;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select p_trip, v_user, 'trip_deleted', name from public.trips where id = p_trip;
end;
$$;

-- Restores a deleted trip exactly as it was: its stored rows were never changed.
create function public.undelete_trip(p_trip uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  if not private.is_active_member(p_trip, v_user) then
    raise exception 'not a member of this trip';
  end if;
  update public.trips set deleted_at = null, deleted_by = null where id = p_trip and deleted_at is not null;
  if not found then
    raise exception 'this trip is not deleted';
  end if;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select p_trip, v_user, 'trip_undeleted', name from public.trips where id = p_trip;
end;
$$;

grant execute on function public.my_pair_balances() to authenticated;
grant execute on function public.my_trip_nets() to authenticated;
grant execute on function public.my_combined_balances() to authenticated;
grant execute on function public.my_header_total() to authenticated;
grant execute on function public.delete_trip(uuid) to authenticated;
grant execute on function public.undelete_trip(uuid) to authenticated;
