-- Read access (docs/permissions.md). Writes go through functions; these policies only cover selects,
-- plus updating your own profile, your own device tokens, and trip details for active members.

create function private.shares_a_trip(p_a uuid, p_b uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_members a
    join public.trip_members b on b.trip_id = a.trip_id
    where a.user_id = p_a and b.user_id = p_b and a.removed_at is null and b.removed_at is null
  );
$$;
grant execute on function private.shares_a_trip(uuid, uuid) to authenticated;

create policy "profiles: self and co-members" on public.profiles for select to authenticated
  using (id = (select auth.uid()) or private.shares_a_trip((select auth.uid()), id));
create policy "profiles: update self" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "trips: active members" on public.trips for select to authenticated
  using (private.is_active_member(id, (select auth.uid())));
create policy "trips: active members edit details" on public.trips for update to authenticated
  using (private.is_active_member(id, (select auth.uid())) and deleted_at is null)
  with check (private.is_active_member(id, (select auth.uid())));

create policy "trip_members: active members" on public.trip_members for select to authenticated
  using (private.is_active_member(trip_id, (select auth.uid())));

create policy "expenses: active members" on public.expenses for select to authenticated
  using (private.is_active_member(trip_id, (select auth.uid())));

create policy "expense_shares: active members" on public.expense_shares for select to authenticated
  using (exists (select 1 from public.expenses e
                 where e.id = expense_id and private.is_active_member(e.trip_id, (select auth.uid()))));

-- Removed members (kept balance) still see payments they're part of.
create policy "payments: active members and parties" on public.payments for select to authenticated
  using (private.is_active_member(trip_id, (select auth.uid()))
         or (select auth.uid()) in (payer_id, payee_id));

create policy "activity_events: active members" on public.activity_events for select to authenticated
  using (private.is_active_member(trip_id, (select auth.uid())));

create policy "device_tokens: own" on public.device_tokens for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
