-- Someone who left a trip at $0 stays at $0 (TRIP-14 review). Editing or deleting an expense they were on, or
-- deleting a payment of theirs, would otherwise give them a balance on a trip they can no longer see. Checked at
-- commit, like the share sum, so a function's whole write is judged at once. Members removed with keep before
-- TRIP-14 aren't covered: their balance was meant to stay.
create function private.check_departed_settled()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_trip uuid;
begin
  if tg_table_name = 'expense_shares' then
    select e.trip_id into v_trip from public.expenses e where e.id = coalesce(new.expense_id, old.expense_id);
    if v_trip is null then return null; end if;  -- the expense was deleted; its own trigger checks the trip
  else
    v_trip := coalesce(new.trip_id, old.trip_id);
  end if;
  if exists (select 1 from public.trip_members m
             where m.trip_id = v_trip and m.removal = 'settled' and private.member_net(v_trip, m.user_id) <> 0) then
    raise exception 'that would change the balance of someone who left this trip; add them back first';
  end if;
  return null;
end;
$$;

create constraint trigger expenses_departed_settled
  after insert or update or delete on public.expenses
  deferrable initially deferred
  for each row execute function private.check_departed_settled();
create constraint trigger expense_shares_departed_settled
  after insert or update or delete on public.expense_shares
  deferrable initially deferred
  for each row execute function private.check_departed_settled();
create constraint trigger payments_departed_settled
  after insert or update or delete on public.payments
  deferrable initially deferred
  for each row execute function private.check_departed_settled();

revoke execute on function private.check_departed_settled() from public, anon, authenticated;
