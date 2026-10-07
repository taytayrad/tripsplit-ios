-- Net model (TRIP-10, docs/money-rules.md › Balances, Payments): one net per member per trip, suggested
-- payments that settle a trip in the fewest payments, and payments that each belong to one trip.

-- Each member's net on each live trip. Positive = owed. The nets on a trip add up to $0.
create view private.member_nets as
select x.trip_id, x.user_id, sum(x.cents)::bigint as cents
from (
  select e.trip_id, e.payer_id as user_id, e.amount_cents as cents from public.expenses e
  union all
  select e.trip_id, s.user_id, -s.share_cents from public.expenses e join public.expense_shares s on s.expense_id = e.id
  union all
  select p.trip_id, p.payer_id, p.amount_cents from public.payments p where p.deleted_at is null
  union all
  select p.trip_id, p.payee_id, -p.amount_cents from public.payments p where p.deleted_at is null
) x
join public.trips t on t.id = x.trip_id and t.deleted_at is null
group by x.trip_id, x.user_id;

-- One member's net on one trip (0 when they have no rows).
create function private.member_net(p_trip uuid, p_user uuid)
returns bigint
language sql
stable
set search_path = ''
as $$
  select coalesce((select cents from private.member_nets where trip_id = p_trip and user_id = p_user), 0);
$$;

-- The fewest payments that bring every member of a trip to $0: the largest debtor pays the largest creditor
-- the smaller amount, repeated. Ties go to the lower user id, so every client gets the same list.
create function private.suggested_payments(p_trip uuid)
returns table (seq integer, payer_id uuid, payee_id uuid, cents bigint)
language plpgsql
stable
set search_path = ''
as $$
declare
  v_users uuid[];
  v_nets bigint[];
  v_n integer;
  v_d integer;
  v_c integer;
  v_amount bigint;
  v_step integer := 0;
  i integer;
begin
  select array_agg(n.user_id order by n.user_id), array_agg(n.cents order by n.user_id) into v_users, v_nets
  from private.member_nets n where n.trip_id = p_trip and n.cents <> 0;
  v_n := coalesce(array_length(v_users, 1), 0);
  loop
    v_d := null; v_c := null;
    for i in 1..v_n loop
      if v_nets[i] < 0 and (v_d is null or v_nets[i] < v_nets[v_d]) then v_d := i; end if;
      if v_nets[i] > 0 and (v_c is null or v_nets[i] > v_nets[v_c]) then v_c := i; end if;
    end loop;
    exit when v_d is null or v_c is null;
    v_amount := least(-v_nets[v_d], v_nets[v_c]);
    v_nets[v_d] := v_nets[v_d] + v_amount;
    v_nets[v_c] := v_nets[v_c] - v_amount;
    v_step := v_step + 1;
    seq := v_step; payer_id := v_users[v_d]; payee_id := v_users[v_c]; cents := v_amount;
    return next;
  end loop;
end;
$$;

-- Your net per trip, on every live trip you have money on (including one you were removed from with a kept balance).
create or replace function public.my_trip_nets()
returns table (trip_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select n.trip_id, n.cents from private.member_nets n where n.user_id = (select auth.uid()) and n.cents <> 0;
$$;

-- Every suggested payment on the trips you're an active member of (members can see each other's nets), plus
-- any that involve you on a trip you were removed from.
create function public.my_trip_settlements()
returns table (trip_id uuid, seq integer, payer_id uuid, payee_id uuid, cents bigint)
language sql
stable
security definer
set search_path = ''
as $$
  select m.trip_id, s.seq, s.payer_id, s.payee_id, s.cents
  from public.trip_members m
  join public.trips t on t.id = m.trip_id and t.deleted_at is null
  cross join lateral private.suggested_payments(m.trip_id) s
  where m.user_id = (select auth.uid())
    and (m.removed_at is null or (select auth.uid()) in (s.payer_id, s.payee_id));
$$;

-- Each trip's nets for activity deltas, from the new view.
create or replace function private.trip_nets(p_trip uuid)
returns jsonb
language sql
stable
set search_path = ''
as $$
  select coalesce(jsonb_object_agg(user_id, cents) filter (where cents <> 0), '{}')
  from private.member_nets where trip_id = p_trip;
$$;

-- The day a payment happened (the Payment page's Date row). Existing payments take their logging day.
alter table public.payments add column paid_on date;
update public.payments set paid_on = created_at::date;
alter table public.payments alter column paid_on set not null, alter column paid_on set default current_date;

-- log_payment: one payment per trip in p_parts ([{trip_id, cents}]), each within what both sides allow on that
-- trip. `pay`: you paid p_other. `record`: p_other paid you. Retrying a request_id returns the stored rows.
drop function public.log_payment(uuid, integer, text, text, uuid);
create function public.log_payment(
  p_other uuid, p_direction text, p_method text, p_request_id uuid, p_paid_on date, p_parts jsonb)
returns table (payment_id uuid, trip_id uuid, amount_cents integer)
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_user uuid := private.current_user_id();
  v_payer uuid;
  v_payee uuid;
  v_trip uuid;
  v_cents bigint;
  v_cap bigint;
  v_payment uuid;
  r record;
begin
  if p_direction not in ('pay', 'record') then
    raise exception 'direction must be pay or record';
  end if;
  if p_other = v_user then
    raise exception 'a payment needs another person';
  end if;
  if p_parts is null or jsonb_typeof(p_parts) <> 'array' or jsonb_array_length(p_parts) = 0 then
    raise exception 'a payment needs a trip';
  end if;
  if p_direction = 'pay' then v_payer := v_user; v_payee := p_other;
  else v_payer := p_other; v_payee := v_user; end if;

  -- Lock the trips first (in id order), so nets can't change between the checks and the inserts, and two quick
  -- taps of the same log wait for each other.
  perform 1 from public.trips t
  where t.id in (select (e ->> 'trip_id')::uuid from jsonb_array_elements(p_parts) e)
  order by t.id for update;

  if exists (select 1 from public.payments p where p.request_id = p_request_id) then
    if not exists (select 1 from public.payments p where p.request_id = p_request_id and p.logged_by = v_user) then
      raise exception 'request id already used';
    end if;
    return query select p.id, p.trip_id, p.amount_cents from public.payments p where p.request_id = p_request_id;
    return;
  end if;

  for r in select e from jsonb_array_elements(p_parts) e loop
    v_trip := (r.e ->> 'trip_id')::uuid;
    v_cents := (r.e ->> 'cents')::bigint;
    if v_cents is null or v_cents <= 0 then
      raise exception 'amount must be more than $0';
    end if;
    if not exists (select 1 from public.trips t where t.id = v_trip and t.deleted_at is null) then
      raise exception 'trip not found';
    end if;
    if not exists (select 1 from public.trip_members m where m.trip_id = v_trip and m.user_id = v_user)
       or not exists (select 1 from public.trip_members m where m.trip_id = v_trip and m.user_id = p_other) then
      raise exception 'you both need to be on the trip';
    end if;
    v_cap := least(-private.member_net(v_trip, v_payer), private.member_net(v_trip, v_payee));
    if v_cap <= 0 then
      raise exception 'nothing is owed';
    end if;
    if v_cents > v_cap then
      raise exception 'amount is more than what is owed';
    end if;
    insert into public.payments (trip_id, payer_id, payee_id, amount_cents, method, logged_by, request_id, paid_on)
    values (v_trip, v_payer, v_payee, v_cents, p_method, v_user, p_request_id, coalesce(p_paid_on, current_date))
    returning id into v_payment;
    insert into public.activity_events (trip_id, actor_id, kind, payment_id, deltas)
    values (v_trip, v_user, 'payment_logged', v_payment, jsonb_build_object(v_payer, v_cents, v_payee, -v_cents));
    payment_id := v_payment; trip_id := v_trip; amount_cents := v_cents;
    return next;
  end loop;
end;
$$;

revoke execute on function public.my_trip_settlements() from public, anon;
revoke execute on function public.log_payment(uuid, text, text, uuid, date, jsonb) from public, anon;
grant execute on function public.my_trip_settlements() to authenticated;
grant execute on function public.log_payment(uuid, text, text, uuid, date, jsonb) to authenticated;
