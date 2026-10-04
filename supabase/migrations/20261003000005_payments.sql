-- Payments (docs/money-rules.md › Payments). One logged amount with a person is allocated across shared
-- trips oldest first, one payment row per trip touched. Capped at what's owed. Idempotent by request id.

-- p_direction: 'pay' (you pay them, they're owed) or 'record' (they paid you, you're owed).
create function public.log_payment(
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
    return query select p.id, p.trip_id, p.amount_cents from public.payments p where p.request_id = p_request_id;
    return;
  end if;

  -- What the payee is owed by the payer, per open trip (pair_balances is from user_a's side).
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
end;
$$;

-- Either person on a payment can delete it. Soft delete, so Activity history stays intact.
create function public.delete_payment(p_payment uuid)
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
  update public.payments set deleted_at = now(), deleted_by = v_user where id = p_payment;
  insert into public.activity_events (trip_id, actor_id, kind, payment_id, deltas)
  values (v_p.trip_id, v_user, 'payment_deleted', p_payment,
          jsonb_build_object(v_p.payer_id, -v_p.amount_cents, v_p.payee_id, v_p.amount_cents));
end;
$$;

grant execute on function public.log_payment(uuid, integer, text, text, uuid) to authenticated;
grant execute on function public.delete_payment(uuid) to authenticated;
