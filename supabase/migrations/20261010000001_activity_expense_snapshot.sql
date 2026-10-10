-- Own-cost Activity lines ("You paid $X") need the amount at the moment the event was written.
-- Deltas drop zeros, so that amount is not in the delta. Reading the live expense later rewrites
-- earlier rows when the expense is edited. Snapshot the payer, the amount, and the payer's share
-- onto the event. Rows written before this stay null, and the app then shows no own-cost line.

alter table public.activity_events
  add column expense_payer_id uuid,
  add column expense_amount_cents integer,
  add column expense_payer_share_cents integer;

create function private.snapshot_expense_facts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.expense_id is not null
     and new.kind in ('expense_added', 'expense_updated', 'expense_deleted') then
    select e.payer_id, e.amount_cents,
           (select s.share_cents from public.expense_shares s
            where s.expense_id = e.id and s.user_id = e.payer_id)
      into new.expense_payer_id, new.expense_amount_cents, new.expense_payer_share_cents
    from public.expenses e
    where e.id = new.expense_id;
  end if;
  return new;
end;
$$;

revoke execute on function private.snapshot_expense_facts() from public, anon, authenticated;

create trigger activity_events_snapshot_expense
  before insert on public.activity_events
  for each row execute function private.snapshot_expense_facts();

-- The expense has to still exist when the delete event is inserted, so the trigger can read it.
create or replace function public.delete_expense(p_expense uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_e public.expenses;
  v_old jsonb;
begin
  select * into v_e from public.expenses where id = p_expense;
  if v_e.id is null then
    raise exception 'expense not found';
  end if;
  perform private.require_active_trip(v_e.trip_id, v_user);
  perform private.lock_trip(v_e.trip_id);
  v_old := private.expense_effect(p_expense);
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_deleted', p_expense, v_e.description, private.jsonb_delta(v_old, '{}'));
  delete from public.expenses where id = p_expense;  -- shares cascade
end;
$$;
