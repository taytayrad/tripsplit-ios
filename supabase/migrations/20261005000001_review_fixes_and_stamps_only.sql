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
  update public.payments set deleted_at = now(), deleted_by = v_user where id = p_payment;
  insert into public.activity_events (trip_id, actor_id, kind, payment_id, deltas)
  values (v_p.trip_id, v_user, 'payment_deleted', p_payment,
          jsonb_build_object(v_p.payer_id, -v_p.amount_cents, v_p.payee_id, v_p.amount_cents));
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

-- Stamps only: no trip photos (prd.md › Build decisions).
alter table public.trips drop column if exists image_path;

-- Realtime: clients subscribe to their trips' rows and re-query on change. RLS still applies.
alter publication supabase_realtime add table
  public.trips, public.trip_members, public.expenses, public.expense_shares, public.payments, public.activity_events;
