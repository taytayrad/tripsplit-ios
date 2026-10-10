-- delete_expense and restore_expense take the trip lock before checking the caller (PR #32 review). Checked
-- first, a member being removed, or the trip being deleted, while the call waits on the lock would go unseen.

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
  if v_e.id is null then
    raise exception 'expense not found';
  end if;
  perform private.lock_trip(v_e.trip_id);
  perform private.require_active_trip(v_e.trip_id, v_user);
  select * into v_e from public.expenses where id = p_expense;  -- re-read under the lock
  if v_e.deleted_at is not null then
    raise exception 'expense not found';
  end if;
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_deleted', p_expense, v_e.description,
          private.jsonb_delta(private.expense_effect(p_expense), '{}'));
  update public.expenses set deleted_at = now(), deleted_by = v_user where id = p_expense;
end;
$$;

create or replace function public.restore_expense(p_expense uuid)
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
  perform private.lock_trip(v_e.trip_id);
  perform private.require_active_trip(v_e.trip_id, v_user);
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
