-- Phase 3: fixes from the architectural review, stamps only (no trip photos), and realtime.

-- Removed members can't rejoin by link. An active member can add them back with add_member.
create or replace function public.join_trip(p_invite_token text)
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
  if exists (select 1 from public.trip_members where trip_id = v_trip and user_id = v_user and removed_at is not null) then
    raise exception 'you were removed from this trip';
  end if;
  insert into public.trip_members (trip_id, user_id) values (v_trip, v_user);
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select v_trip, v_user, 'member_joined', name from public.trips where id = v_trip;
  return v_trip;
end;
$$;

-- member_joined has one shape everywhere: actor is the person who joined, subject is the trip name.
create or replace function public.add_member(p_trip uuid, p_user uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
begin
  perform private.require_active_trip(p_trip, v_user);
  if private.is_active_member(p_trip, p_user) then
    return;
  end if;
  if not private.shares_a_trip(v_user, p_user) then
    raise exception 'you can only add people you already share a trip with';
  end if;
  insert into public.trip_members (trip_id, user_id) values (p_trip, p_user)
  on conflict (trip_id, user_id) do update set removed_at = null, removed_by = null, removal = null;
  insert into public.activity_events (trip_id, actor_id, kind, subject)
  select p_trip, p_user, 'member_joined', name from public.trips where id = p_trip;
end;
$$;

-- The 20-member cap holds under concurrent joins: lock the trip row before counting.
create or replace function public.enforce_member_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  perform 1 from public.trips where id = new.trip_id for update;
  if (select count(*) from public.trip_members
      where trip_id = new.trip_id and removed_at is null) >= 20 then
    raise exception 'a trip can have at most 20 members';
  end if;
  return new;
end;
$$;

-- Balance-changing writes serialize per trip: every function that adds, removes, or rewrites money on a trip
-- locks the trip row first, and log_payment locks the trips it allocates across, so its cap check and
-- inserts see one consistent set of balances.
create function private.lock_trip(p_trip uuid)
returns void
language sql
set search_path = ''
as $$
  select 1 from public.trips where id = p_trip for update;
$$;

-- log_payment: idempotency is bound to the caller, and a short allocation (balances changed under us) fails.
create or replace function public.log_payment(
  p_other uuid, p_amount_cents integer, p_direction text, p_method text, p_request_id uuid)
returns table (payment_id uuid, trip_id uuid, amount_cents integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_payer uuid;
  v_payee uuid;
  v_owed bigint;
  v_left bigint := p_amount_cents;
  v_take bigint;
  v_payment uuid;
  r record;
begin
  if p_direction not in ('pay', 'record') then
    raise exception 'direction must be pay or record';
  end if;
  if p_other = v_user then
    raise exception 'a payment needs another person';
  end if;
  if p_amount_cents is null or p_amount_cents <= 0 then
    raise exception 'amount must be more than $0';
  end if;
  if p_direction = 'pay' then v_payer := v_user; v_payee := p_other;
  else v_payer := p_other; v_payee := v_user; end if;

  -- One log at a time per pair of people, so two quick taps can't both pass the cap.
  perform pg_advisory_xact_lock(hashtextextended(least(v_user, p_other)::text || greatest(v_user, p_other)::text, 0));

  -- Lock the trips this pair has open balances on, so an expense, delete, or wipe can't change what's owed
  -- between the cap check and the inserts (those functions lock the trip row too; see private.lock_trip).
  perform 1 from public.trips t
  where t.id in (select b.trip_id from private.pair_balances b where b.user_a = v_payee and b.user_b = v_payer and b.cents > 0)
  order by t.id for update;

  if exists (select 1 from public.payments p where p.request_id = p_request_id) then
    if not exists (select 1 from public.payments p where p.request_id = p_request_id and p.logged_by = v_user) then
      raise exception 'request id already used';
    end if;
    return query select p.id, p.trip_id, p.amount_cents from public.payments p where p.request_id = p_request_id;
    return;
  end if;

  select coalesce(sum(b.cents), 0) into v_owed
  from private.pair_balances b where b.user_a = v_payee and b.user_b = v_payer and b.cents > 0;
  if v_owed = 0 then
    raise exception 'nothing is owed';
  end if;
  if p_amount_cents > v_owed then
    raise exception 'amount is more than what is owed';
  end if;

  for r in
    select b.trip_id as t, b.cents as owed
    from private.pair_balances b join public.trips tr on tr.id = b.trip_id
    where b.user_a = v_payee and b.user_b = v_payer and b.cents > 0
    order by coalesce(tr.start_date, tr.created_at::date), tr.created_at
  loop
    exit when v_left = 0;
    v_take := least(v_left, r.owed);
    insert into public.payments (trip_id, payer_id, payee_id, amount_cents, method, logged_by, request_id)
    values (r.t, v_payer, v_payee, v_take, p_method, v_user, p_request_id)
    returning id into v_payment;
    insert into public.activity_events (trip_id, actor_id, kind, payment_id, deltas)
    values (r.t, v_user, 'payment_logged', v_payment, jsonb_build_object(v_payer, v_take, v_payee, -v_take));
    payment_id := v_payment; trip_id := r.t; amount_cents := v_take;
    return next;
    v_left := v_left - v_take;
  end loop;
  if v_left <> 0 then
    raise exception 'balances changed while logging, try again';
  end if;
end;
$$;

-- delete_payment: not on a deleted trip, so undelete restores the trip exactly. (The party check stays, so
-- a removed-with-keep payer or payee can still delete a payment on a live trip.)
create or replace function public.delete_payment(p_payment uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_p public.payments;
begin
  select * into v_p from public.payments where id = p_payment and deleted_at is null;
  if v_p.id is null then
    raise exception 'payment not found';
  end if;
  if v_user not in (v_p.payer_id, v_p.payee_id) then
    raise exception 'only the two people on a payment can delete it';
  end if;
  if exists (select 1 from public.trips where id = v_p.trip_id and deleted_at is not null) then
    raise exception 'this trip is deleted';
  end if;
  perform private.lock_trip(v_p.trip_id);
  update public.payments set deleted_at = now(), deleted_by = v_user where id = p_payment;
  insert into public.activity_events (trip_id, actor_id, kind, payment_id, deltas)
  values (v_p.trip_id, v_user, 'payment_deleted', p_payment,
          jsonb_build_object(v_p.payer_id, -v_p.amount_cents, v_p.payee_id, v_p.amount_cents));
end;
$$;

create or replace function public.save_expense(
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
  perform private.lock_trip(p_trip);
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
  delete from public.expenses where id = p_expense;  -- shares cascade
  insert into public.activity_events (trip_id, actor_id, kind, expense_id, subject, deltas)
  values (v_e.trip_id, v_user, 'expense_deleted', p_expense, v_e.description, private.jsonb_delta(v_old, '{}'));
end;
$$;

create or replace function public.remove_member(p_trip uuid, p_user uuid, p_mode text)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_before jsonb;
begin
  perform private.lock_trip(p_trip);
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

-- Wipe: a rewritten expense becomes an exact split, so editing it shows the stored shares instead of
-- recomputing the pre-wipe split. (Exact splits read share_cents; split_input is only for percent and shares.)
create or replace function private.wipe_member(p_trip uuid, p_user uuid)
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
    update public.expenses set split_kind = 'exact' where id = e.id;
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
    update public.expenses set split_kind = 'exact' where id = e.id;
  end loop;
end;
$$;

-- Stamps only: no trip photos (prd.md › Build decisions). Tears down what the Phase 2 migration created.
drop policy if exists "trip photos: members read" on storage.objects;
drop policy if exists "trip photos: members upload" on storage.objects;
drop policy if exists "trip photos: members replace" on storage.objects;
drop policy if exists "trip photos: members delete" on storage.objects;
drop function if exists private.is_member_of_folder(text);
-- The bucket itself stays: Supabase refuses deletes on storage tables from SQL. It is empty, private, and
-- has no policies, so nothing can read or write it. Remove it from the dashboard if it bothers you.
alter table public.trips drop column if exists image_path;

-- Realtime: clients subscribe to their trips' rows and re-query on change. RLS still applies.
alter publication supabase_realtime add table
  public.trips, public.trip_members, public.expenses, public.expense_shares, public.payments, public.activity_events;
