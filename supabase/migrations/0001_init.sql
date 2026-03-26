create extension if not exists "pgcrypto";

create table if not exists public.users (
  id uuid primary key references auth.users (id) on delete cascade,
  full_name text,
  role text not null default 'personel' check (role in ('admin', 'personel')),
  created_at timestamptz not null default now()
);

create or replace function public.is_admin()
returns boolean
language sql
stable
as $$
  select exists (
    select 1 from public.users u
    where u.id = auth.uid() and u.role = 'admin'
  );
$$;

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id, full_name, role)
  values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''), 'personel')
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row execute procedure public.handle_new_auth_user();

create table if not exists public.customers (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  city text,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.branches (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  name text not null,
  city text,
  address text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.lines (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  branch_id uuid references public.branches (id) on delete set null,
  label text,
  number text,
  expires_at date,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.licenses (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  name text not null,
  expires_at date,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.work_orders (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  title text not null,
  description text,
  status text not null default 'open' check (status in ('open', 'in_progress', 'done')),
  scheduled_date date,
  assigned_to uuid references auth.users (id),
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create table if not exists public.payments (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  work_order_id uuid references public.work_orders (id) on delete set null,
  amount numeric(12,2) not null,
  currency text not null default 'TRY',
  paid_at timestamptz not null default now(),
  created_by uuid references auth.users (id),
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.service_records (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  work_order_id uuid references public.work_orders (id) on delete set null,
  title text not null,
  status text not null default 'open' check (status in ('open', 'in_progress', 'done')),
  parts jsonb not null default '[]'::jsonb,
  labor jsonb not null default '[]'::jsonb,
  notes text,
  currency text not null default 'TRY',
  total_amount numeric(12,2),
  location_lat double precision,
  location_lng double precision,
  signature_url text,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create index if not exists idx_customers_name on public.customers using btree (name);
create index if not exists idx_lines_expires on public.lines using btree (expires_at);
create index if not exists idx_licenses_expires on public.licenses using btree (expires_at);
create index if not exists idx_work_orders_status on public.work_orders using btree (status);
create index if not exists idx_payments_paid_at on public.payments using btree (paid_at);
create index if not exists idx_service_created_at on public.service_records using btree (created_at);

alter table public.users enable row level security;
alter table public.customers enable row level security;
alter table public.branches enable row level security;
alter table public.lines enable row level security;
alter table public.licenses enable row level security;
alter table public.work_orders enable row level security;
alter table public.payments enable row level security;
alter table public.service_records enable row level security;

drop policy if exists "users_select_self_or_admin" on public.users;
create policy "users_select_self_or_admin"
on public.users
for select
to authenticated
using (auth.uid() = id or public.is_admin());

drop policy if exists "users_update_self_or_admin" on public.users;
create policy "users_update_self_or_admin"
on public.users
for update
to authenticated
using (auth.uid() = id or public.is_admin())
with check (auth.uid() = id or public.is_admin());

drop policy if exists "customers_select_active_or_admin" on public.customers;
create policy "customers_select_active_or_admin"
on public.customers
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "customers_write_authenticated" on public.customers;
create policy "customers_write_authenticated"
on public.customers
for insert
to authenticated
with check (true);

drop policy if exists "customers_update_authenticated" on public.customers;
create policy "customers_update_authenticated"
on public.customers
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "branches_select_active_or_admin" on public.branches;
create policy "branches_select_active_or_admin"
on public.branches
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "branches_write_authenticated" on public.branches;
create policy "branches_write_authenticated"
on public.branches
for insert
to authenticated
with check (true);

drop policy if exists "branches_update_authenticated" on public.branches;
create policy "branches_update_authenticated"
on public.branches
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "lines_select_active_or_admin" on public.lines;
create policy "lines_select_active_or_admin"
on public.lines
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "lines_write_authenticated" on public.lines;
create policy "lines_write_authenticated"
on public.lines
for insert
to authenticated
with check (true);

drop policy if exists "lines_update_authenticated" on public.lines;
create policy "lines_update_authenticated"
on public.lines
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "licenses_select_active_or_admin" on public.licenses;
create policy "licenses_select_active_or_admin"
on public.licenses
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "licenses_write_authenticated" on public.licenses;
create policy "licenses_write_authenticated"
on public.licenses
for insert
to authenticated
with check (true);

drop policy if exists "licenses_update_authenticated" on public.licenses;
create policy "licenses_update_authenticated"
on public.licenses
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "work_orders_select_active_or_admin" on public.work_orders;
create policy "work_orders_select_active_or_admin"
on public.work_orders
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "work_orders_write_authenticated" on public.work_orders;
create policy "work_orders_write_authenticated"
on public.work_orders
for insert
to authenticated
with check (true);

drop policy if exists "work_orders_update_authenticated" on public.work_orders;
create policy "work_orders_update_authenticated"
on public.work_orders
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "payments_select_active_or_admin" on public.payments;
create policy "payments_select_active_or_admin"
on public.payments
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "payments_write_authenticated" on public.payments;
create policy "payments_write_authenticated"
on public.payments
for insert
to authenticated
with check (true);

drop policy if exists "payments_update_authenticated" on public.payments;
create policy "payments_update_authenticated"
on public.payments
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "service_select_active_or_admin" on public.service_records;
create policy "service_select_active_or_admin"
on public.service_records
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "service_write_authenticated" on public.service_records;
create policy "service_write_authenticated"
on public.service_records
for insert
to authenticated
with check (true);

drop policy if exists "service_update_authenticated" on public.service_records;
create policy "service_update_authenticated"
on public.service_records
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

