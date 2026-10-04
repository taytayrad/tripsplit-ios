-- Trip and expense write paths (docs/data-model.md › Write paths; split math in docs/money-rules.md).

create schema private;
grant usage on schema private to authenticated;

-- True when the user is on the trip and hasn't been removed.
create function private.is_active_member(p_trip uuid, p_user uuid)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1 from public.trip_members
    where trip_id = p_trip and user_id = p_user and removed_at is null
  );
$$;
grant execute on function private.is_active_member(uuid, uuid) to authenticated;

-- The caller, or an error when signed out.
create function private.current_user_id()
returns uuid
language plpgsql
stable
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'not signed in';
  end if;
  return auth.uid();
end;
$$;

-- Raises unless the caller is an active member of a trip that isn't deleted.
create function private.require_active_trip(p_trip uuid, p_user uuid)
returns void
language plpgsql
stable
set search_path = ''
as $$
begin
  if not private.is_active_member(p_trip, p_user) then
    raise exception 'not a member of this trip';
  end if;
  if exists (select 1 from public.trips where id = p_trip and deleted_at is not null) then
    raise exception 'this trip is deleted';
  end if;
end;
$$;

-- An expense's effect on each person's trip net: payer +amount, everyone −share.
create function private.expense_effect(p_expense uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(user_id, cents) filter (where cents <> 0), '{}')
  from (
    select user_id, sum(cents) as cents
    from (
      select payer_id as user_id, amount_cents::bigint as cents from public.expenses where id = p_expense
      union all
      select user_id, -share_cents from public.expense_shares where expense_id = p_expense
    ) parts
    group by user_id
  ) totals;
$$;

-- new − old, per person, dropping zeros.
create function private.jsonb_delta(p_old jsonb, p_new jsonb)
returns jsonb
language sql
immutable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(k, d) filter (where d <> 0), '{}')
  from (
    select k, coalesce((p_new ->> k)::bigint, 0) - coalesce((p_old ->> k)::bigint, 0) as d
    from (select jsonb_object_keys(p_old) as k union select jsonb_object_keys(p_new)) keys
  ) diffs;
$$;

create function public.create_trip(p_name text, p_stamp jsonb, p_start_date date, p_end_date date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_trip uuid;
begin
  insert into public.trips (name, stamp, start_date, end_date, created_by)
  values (p_name, p_stamp, p_start_date, p_end_date, v_user)
  returning id into v_trip;
  insert into public.trip_members (trip_id, user_id) values (v_trip, v_user);
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  values (v_trip, v_user, 'trip_created', p_name);
  return v_trip;
end;
$$;

-- Joins by invite token. Already a member: no-op. Removed earlier: rejoins.
create function public.join_trip(p_invite_token text)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_trip uuid;
begin
  select id into v_trip from public.trips where invite_token = p_invite_token and deleted_at is null;
  if v_trip is null then
    raise exception 'invite link not found';
  end if;
  if private.is_active_member(v_trip, v_user) then
    return v_trip;
  end if;
  insert into public.trip_members (trip_id, user_id) values (v_trip, v_user)
  on conflict (trip_id, user_id) do update set removed_at = null, removed_by = null, removal = null;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select v_trip, v_user, 'member_joined', name from public.trips where id = v_trip;
  return v_trip;
end;
$$;

-- Creates (p_expense_id null) or replaces an expense. p_inputs: [{user_id, value}], where value is
-- 1/0 for equal, cents for exact, a percent for percent, a share count for shares. Value 0 = not in it.
-- Shares follow the remainder rule: floor each, leftover cents to the last included person in member order.
create function public.save_expense(
  p_trip uuid, p_expense_id uuid, p_description text, p_icon text, p_amount_cents integer,
  p_payer uuid, p_split_kind text, p_inputs jsonb, p_spent_on date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_expense uuid := p_expense_id;
  v_old jsonb := '{}';
  v_users uuid[];
  v_values numeric[];
  v_shares bigint[];
  v_given integer;
  v_n integer;
  v_total numeric;
  v_sum bigint;
  i integer;
begin
  perform private.require_active_trip(p_trip, v_user);
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'amount must be more than $0';
  end if;
  if not private.is_active_member(p_trip, p_payer) then
    raise exception 'the payer must be on the trip';
  end if;
  if p_split_kind not in ('equal', 'exact', 'percent', 'shares') then
    raise exception 'unknown split kind %', p_split_kind;
  end if;

  -- Included people (value > 0), in member order.
  select count(*) into v_given
  from jsonb_to_recordset(p_inputs) as x(user_id uuid, value numeric) where x.value > 0;
  select array_agg(x.user_id order by m.position), array_agg(x.value order by m.position)
    into v_users, v_values
  from jsonb_to_recordset(p_inputs) as x(user_id uuid, value numeric)
  join public.trip_members m on m.trip_id = p_trip and m.user_id = x.user_id and m.removed_at is null
  where x.value > 0;
  v_n := coalesce(array_length(v_users, 1), 0);
  if v_n <> v_given then
    raise exception 'everyone in the split must be on the trip';
  end if;
  if v_n = 0 then
    raise exception 'at least one person must be in the split';
  end if;
  if (select count(distinct u) from unnest(v_users) u) <> v_n then
    raise exception 'a person appears twice in the split';
  end if;

  v_shares := array_fill(0::bigint, array[v_n]);
  case p_split_kind
    when 'equal' then
      for i in 1..v_n loop v_shares[i] := p_amount_cents / v_n; end loop;
    when 'exact' then
      for i in 1..v_n loop
        if v_values[i] <> trunc(v_values[i]) then raise exception 'exact amounts must be whole cents'; end if;
        v_shares[i] := v_values[i]::bigint;
      end loop;
      if (select sum(s) from unnest(v_shares) s) <> p_amount_cents then
        raise exception 'amounts must add up to the expense';
      end if;
    when 'percent' then
      if (select sum(v) from unnest(v_values) v) <> 100 then
        raise exception 'percentages must add up to 100';
      end if;
      for i in 1..v_n loop v_shares[i] := floor(p_amount_cents * v_values[i] / 100); end loop;
    when 'shares' then
      for i in 1..v_n loop
        if v_values[i] <> trunc(v_values[i]) then raise exception 'shares must be whole numbers'; end if;
      end loop;
      v_total := (select sum(v) from unnest(v_values) v);
      for i in 1..v_n loop v_shares[i] := floor(p_amount_cents * v_values[i] / v_total); end loop;
  end case;
  v_sum := (select sum(s) from unnest(v_shares) s);
  v_shares[v_n] := v_shares[v_n] + (p_amount_cents - v_sum);

  if v_expense is null then
    insert into public.expenses (trip_id, description, icon, amount_cents, payer_id, split_kind, spent_on, created_by)
    values (p_trip, p_description, coalesce(p_icon, 'general'), p_amount_cents, p_payer, p_split_kind,
            coalesce(p_spent_on, current_date), v_user)
    returning id into v_expense;
  else
    if not exists (select 1 from public.expenses where id = v_expense and trip_id = p_trip) then
      raise exception 'expense not found on this trip';
    end if;
    v_old := private.expense_effect(v_expense);
    update public.expenses
    set description = p_description, icon = coalesce(p_icon, 'general'), amount_cents = p_amount_cents,
        payer_id = p_payer, split_kind = p_split_kind, spent_on = coalesce(p_spent_on, spent_on), updated_at = now()
    where id = v_expense;
    delete from public.expense_shares where expense_id = v_expense;
  end if;

  insert into public.expense_shares (expense_id, user_id, share_cents, split_input)
  select v_expense, v_users[k], v_shares[k],
         case when p_split_kind in ('percent', 'shares') then v_values[k] end
  from generate_subscripts(v_users, 1) as k;

  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (p_trip, v_user, case when p_expense_id is null then 'expense_added' else 'expense_updated' end,
          v_expense, p_description, private.jsonb_delta(v_old, private.expense_effect(v_expense)));
  return v_expense;
end;
$$;

grant execute on function public.create_trip(text, jsonb, date, date) to authenticated;
grant execute on function public.join_trip(text) to authenticated;
grant execute on function public.save_expense(uuid, uuid, text, text, integer, uuid, text, jsonb, date) to authenticated;
