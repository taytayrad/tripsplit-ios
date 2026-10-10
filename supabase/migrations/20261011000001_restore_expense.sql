-- Restore a deleted expense (TRIP-27, docs/money-rules.md › Expense lifecycle). Deleting an expense now keeps
-- it with `deleted_at`, out of every net, and any active member can put it back. Expenses deleted before this
-- migration were removed outright and stay gone.

alter table public.expenses
  add column deleted_at timestamptz,
  add column deleted_by uuid references public.profiles (id);

alter table public.activity_events drop constraint activity_events_kind_check;
alter table public.activity_events add constraint activity_events_kind_check check (kind in (
  'trip_created', 'trip_deleted', 'trip_undeleted', 'member_joined', 'member_removed',
  'expense_added', 'expense_updated', 'expense_deleted', 'expense_restored', 'payment_logged', 'payment_deleted'));

-- Each member's net on each live trip, leaving out deleted expenses (and, as before, deleted payments).
create or replace view private.member_nets as
select x.trip_id, x.user_id, sum(x.cents)::bigint as cents
from (
  select e.trip_id, e.payer_id as user_id, e.amount_cents as cents from public.expenses e where e.deleted_at is null
  union all
  select e.trip_id, s.user_id, -s.share_cents from public.expenses e join public.expense_shares s on s.expense_id = e.id
  where e.deleted_at is null
  union all
  select p.trip_id, p.payer_id, p.amount_cents from public.payments p where p.deleted_at is null
  union all
  select p.trip_id, p.payee_id, -p.amount_cents from public.payments p where p.deleted_at is null
) x
join public.trips t on t.id = x.trip_id and t.deleted_at is null
group by x.trip_id, x.user_id;

-- A deleted expense can't be edited (save_expense updates the row first, so the whole save is refused).
-- Restoring is the one change allowed: it clears deleted_at.
create function private.refuse_editing_deleted_expense()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if old.deleted_at is not null and new.deleted_at is not null then
    raise exception 'this expense was deleted; restore it first';
  end if;
  return new;
end;
$$;
revoke execute on function private.refuse_editing_deleted_expense() from public, anon, authenticated;
create trigger expenses_refuse_editing_deleted
  before update on public.expenses
  for each row execute function private.refuse_editing_deleted_expense();

-- A restore's Activity row also carries the own-cost snapshot (payer, amount, payer's share).
create or replace function private.snapshot_expense_facts()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.expense_id is not null
     and new.kind in ('expense_added', 'expense_updated', 'expense_deleted', 'expense_restored') then
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

-- Delete keeps the expense and its shares. The Activity deltas are the expense coming off everyone's net.
create or replace function public.delete_expense(p_expense uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_e public.expenses;
begin
  select * into v_e from public.expenses where id = p_expense;
  if v_e.id is null or v_e.deleted_at is not null then
    raise exception 'expense not found';
  end if;
  perform private.require_active_trip(v_e.trip_id, v_user);
  perform private.lock_trip(v_e.trip_id);
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_deleted', p_expense, v_e.description,
          private.jsonb_delta(private.expense_effect(p_expense), '{}'));
  update public.expenses set deleted_at = now(), deleted_by = v_user where id = p_expense;
end;
$$;

-- Put a deleted expense back exactly as it was. Any active member of a live trip can. Refused when someone on
-- the expense is no longer on the trip: it would give them a balance (docs/money-rules.md › Removing and leaving).
-- Restoring one that's already back does nothing, so a retried tap is harmless.
create function public.restore_expense(p_expense uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_e public.expenses;
begin
  select * into v_e from public.expenses where id = p_expense;
  if v_e.id is null then
    raise exception 'expense not found';
  end if;
  perform private.require_active_trip(v_e.trip_id, v_user);
  perform private.lock_trip(v_e.trip_id);
  select * into v_e from public.expenses where id = p_expense;  -- re-read under the lock
  if v_e.deleted_at is null then
    return;
  end if;
  if exists (select 1 from (select v_e.payer_id as user_id
                            union select s.user_id from public.expense_shares s where s.expense_id = p_expense) p
             where not private.is_active_member(v_e.trip_id, p.user_id)) then
    raise exception 'someone on this expense left the trip; add them back first';
  end if;
  update public.expenses set deleted_at = null, deleted_by = null where id = p_expense;
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_restored', p_expense, v_e.description,
          private.jsonb_delta('{}', private.expense_effect(p_expense)));
end;
$$;

revoke execute on function public.restore_expense(uuid) from public, anon;
grant execute on function public.restore_expense(uuid) to authenticated;
