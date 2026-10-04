-- Removing members (keep or wipe) and deleting expenses.

-- Each person's net on one trip, as jsonb user_id -> cents.
create function private.trip_nets(p_trip uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(user_a, cents) filter (where cents <> 0), '{}')
  from (select user_a, sum(cents) as cents from private.pair_balances where trip_id = p_trip group by user_a) n;
$$;

create function public.delete_expense(p_expense uuid)
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
  v_old := private.expense_effect(p_expense);
  delete from public.expenses where id = p_expense;  -- shares cascade
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_deleted', p_expense, v_e.description, private.jsonb_delta(v_old, '{}'));
end;
$$;

-- Wipe (docs/money-rules.md › Wipe, accepted for the MVP):
-- 1. Expenses R didn't pay: R's share moves to the other people in that expense in proportion to their
--    shares (remainder rule; equally if theirs are all $0). R was alone in it: it moves to the payer.
-- 2. Expenses R paid: R absorbs the whole amount (everyone else's share goes to $0).
-- 3. Payments involving R stay as recorded.
create function private.wipe_member(p_trip uuid, p_user uuid)
returns void
language plpgsql
set search_path = ''
as $$
declare
  e record;
  v_r bigint;
  v_users uuid[];
  v_shares bigint[];
  v_n integer;
  v_s numeric;
  v_add bigint[];
  i integer;
begin
  for e in
    select x.id, x.payer_id, s.share_cents
    from public.expenses x join public.expense_shares s on s.expense_id = x.id and s.user_id = p_user
    where x.trip_id = p_trip and x.payer_id <> p_user and s.share_cents > 0
  loop
    v_r := e.share_cents;
    select array_agg(s.user_id order by m.position), array_agg(s.share_cents::bigint order by m.position)
      into v_users, v_shares
    from public.expense_shares s join public.trip_members m on m.trip_id = p_trip and m.user_id = s.user_id
    where s.expense_id = e.id and s.user_id <> p_user;
    v_n := coalesce(array_length(v_users, 1), 0);
    delete from public.expense_shares where expense_id = e.id and user_id = p_user;
    if v_n = 0 then
      insert into public.expense_shares (expense_id, user_id, share_cents) values (e.id, e.payer_id, v_r);
      continue;
    end if;
    v_s := (select sum(x) from unnest(v_shares) x);
    v_add := array_fill(0::bigint, array[v_n]);
    for i in 1..v_n loop
      v_add[i] := case when v_s = 0 then v_r / v_n else floor(v_r * v_shares[i] / v_s) end;
    end loop;
    v_add[v_n] := v_add[v_n] + (v_r - (select sum(x) from unnest(v_add) x));
    for i in 1..v_n loop
      update public.expense_shares set share_cents = share_cents + v_add[i], split_input = null
      where expense_id = e.id and user_id = v_users[i];
    end loop;
  end loop;

  for e in select x.id, x.amount_cents from public.expenses x where x.trip_id = p_trip and x.payer_id = p_user loop
    delete from public.expense_shares where expense_id = e.id;
    insert into public.expense_shares (expense_id, user_id, share_cents) values (e.id, p_user, e.amount_cents);
  end loop;
end;
$$;

create function public.remove_member(p_trip uuid, p_user uuid, p_mode text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_before jsonb;
begin
  perform private.require_active_trip(p_trip, v_user);
  if p_mode not in ('keep', 'wipe') then
    raise exception 'removal must be keep or wipe';
  end if;
  if not private.is_active_member(p_trip, p_user) then
    raise exception 'that person is not on this trip';
  end if;
  v_before := private.trip_nets(p_trip);
  update public.trip_members set removed_at = now(), removed_by = v_user, removal = p_mode
  where trip_id = p_trip and user_id = p_user;
  if p_mode = 'wipe' then
    perform private.wipe_member(p_trip, p_user);
  end if;
  insert into public.activity_events (trip_id, actor_id, kind, subject, deltas)
  select p_trip, v_user, 'member_removed', p.display_name, private.jsonb_delta(v_before, private.trip_nets(p_trip))
  from public.profiles p where p.id = p_user;
end;
$$;

grant execute on function public.delete_expense(uuid) to authenticated;
grant execute on function public.remove_member(uuid, uuid, text) to authenticated;
