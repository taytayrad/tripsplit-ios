-- Core schema (docs/data-model.md). Money is integer cents. Balances are calculated, never stored.
-- Clients never write money tables directly: all writes go through security-definer functions.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default '',
  venmo_username text,
  has_zelle boolean not null default false,
  has_apple_cash boolean not null default false,
  notify_paid boolean not null default true,
  notify_expense boolean not null default true,
  notify_join boolean not null default true,
  notify_trip_deleted boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.trips (
  id uuid primary key default gen_random_uuid(),
  name text not null check (length(trim(name)) > 0),
  image_path text,
  stamp jsonb not null,
  start_date date,
  end_date date,
  invite_token text not null unique default replace(gen_random_uuid()::text, '-', ''),
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references public.profiles (id),
  constraint trip_dates_both_or_neither check ((start_date is null) = (end_date is null)),
  constraint trip_dates_ordered check (end_date >= start_date)
);

create table public.trip_members (
  trip_id uuid not null references public.trips (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  -- Member order: the remainder rule gives leftover cents to the last included person in this order.
  position bigint generated always as identity,
  joined_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by uuid references public.profiles (id),
  removal text check (removal in ('keep', 'wipe')),
  primary key (trip_id, user_id),
  constraint removal_set_with_removed_at check ((removed_at is null) = (removal is null))
);

create table public.expenses (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  description text not null,
  icon text not null default 'general',
  amount_cents integer not null check (amount_cents > 0),
  payer_id uuid not null references public.profiles (id),
  split_kind text not null check (split_kind in ('equal', 'exact', 'percent', 'shares')),
  spent_on date not null default current_date,
  created_by uuid not null references public.profiles (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table public.expense_shares (
  expense_id uuid not null references public.expenses (id) on delete cascade,
  user_id uuid not null references public.profiles (id),
  share_cents integer not null check (share_cents >= 0),
  -- The raw input (percent or share count) so the form can be re-edited; null for equal and exact.
  split_input numeric,
  primary key (expense_id, user_id)
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  payer_id uuid not null references public.profiles (id),
  payee_id uuid not null references public.profiles (id),
  amount_cents integer not null check (amount_cents > 0),
  method text not null check (method in ('venmo', 'zelle', 'apple_cash', 'cash', 'recorded')),
  logged_by uuid not null references public.profiles (id),
  request_id uuid not null,
  created_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid references public.profiles (id),
  constraint payment_between_two_people check (payer_id <> payee_id),
  constraint payment_logged_by_a_party check (logged_by in (payer_id, payee_id)),
  unique (request_id, trip_id)
);

create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  trip_id uuid not null references public.trips (id) on delete cascade,
  actor_id uuid not null references public.profiles (id),
  kind text not null check (kind in (
    'trip_created', 'trip_deleted', 'trip_undeleted', 'member_joined', 'member_removed',
    'expense_added', 'expense_updated', 'expense_deleted', 'payment_logged', 'payment_deleted')),
  expense_id uuid,  -- no FK: the expense may be deleted
  payment_id uuid references public.payments (id),
  subject text,     -- title snapshot, e.g. 'Costco'
  deltas jsonb not null default '{}',  -- user_id -> cents: the event's effect on each person's trip net
  created_at timestamptz not null default clock_timestamp()
);

create table public.device_tokens (
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

create index on public.trip_members (user_id);
create index on public.expenses (trip_id);
create index on public.expense_shares (user_id);
create index on public.payments (trip_id);
create index on public.payments (payer_id);
create index on public.payments (payee_id);
create index on public.activity_events (trip_id, created_at desc);

-- At most 20 active members per trip.
create function public.enforce_member_limit()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (select count(*) from public.trip_members
      where trip_id = new.trip_id and removed_at is null) >= 20 then
    raise exception 'a trip can have at most 20 members';
  end if;
  return new;
end;
$$;

create trigger trip_members_limit before insert on public.trip_members
  for each row execute function public.enforce_member_limit();

-- Every expense's shares add up to its amount (checked at commit, after all shares are written).
create function public.check_share_sum()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_expense uuid := coalesce(new.expense_id, old.expense_id);
  v_amount integer;
  v_sum bigint;
begin
  select amount_cents into v_amount from public.expenses where id = v_expense;
  if v_amount is null then return null; end if;  -- expense deleted
  select coalesce(sum(share_cents), 0) into v_sum from public.expense_shares where expense_id = v_expense;
  if v_sum <> v_amount then
    raise exception 'shares (%) do not add up to the expense (%)', v_sum, v_amount;
  end if;
  return null;
end;
$$;

create constraint trigger expense_shares_sum
  after insert or update or delete on public.expense_shares
  deferrable initially deferred
  for each row execute function public.check_share_sum();

-- A profile for every new auth user.
create function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'name', new.raw_user_meta_data ->> 'full_name', ''));
  return new;
end;
$$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row-level security on everything; policies come with each feature. Clients get read access only,
-- except their own profile and device tokens.
alter table public.profiles enable row level security;
alter table public.trips enable row level security;
alter table public.trip_members enable row level security;
alter table public.expenses enable row level security;
alter table public.expense_shares enable row level security;
alter table public.payments enable row level security;
alter table public.activity_events enable row level security;
alter table public.device_tokens enable row level security;

revoke all on all tables in schema public from anon, authenticated;
grant select on all tables in schema public to authenticated;
grant update (display_name, venmo_username, has_zelle, has_apple_cash,
              notify_paid, notify_expense, notify_join, notify_trip_deleted) on public.profiles to authenticated;
grant update (name, image_path, start_date, end_date) on public.trips to authenticated;
grant insert, update, delete on public.device_tokens to authenticated;
revoke execute on all functions in schema public from anon, authenticated, public;
alter default privileges in schema public revoke execute on functions from anon, authenticated, public;
