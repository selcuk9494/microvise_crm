do $$
begin
  if not exists (select 1 from pg_extension where extname = 'pgcrypto') then
    create extension "pgcrypto";
  end if;
end $$;

alter table public.customers
  add column if not exists email text,
  add column if not exists vkn text,
  add column if not exists notes text,
  add column if not exists phone_1 text,
  add column if not exists phone_1_title text,
  add column if not exists phone_2 text,
  add column if not exists phone_2_title text,
  add column if not exists phone_3 text,
  add column if not exists phone_3_title text;

alter table public.branches
  add column if not exists phone text,
  add column if not exists location_lat double precision,
  add column if not exists location_lng double precision;

alter table public.lines
  add column if not exists sim_number text,
  add column if not exists starts_at date not null default current_date,
  add column if not exists ends_at date not null default ((date_trunc('year', current_date)::date + interval '1 year')::date - 1),
  add column if not exists transferred_at timestamptz,
  add column if not exists transferred_by uuid references auth.users (id);

create index if not exists idx_lines_number on public.lines using btree (number);
create index if not exists idx_lines_sim_number on public.lines using btree (sim_number);

alter table public.licenses
  add column if not exists license_type text not null default 'gmp3' check (license_type in ('gmp3')),
  add column if not exists starts_at date not null default current_date,
  add column if not exists ends_at date not null default ((date_trunc('year', current_date)::date + interval '1 year')::date - 1);

create index if not exists idx_licenses_type on public.licenses using btree (license_type);

create table if not exists public.line_transfers (
  id uuid primary key default gen_random_uuid(),
  line_id uuid not null references public.lines (id) on delete cascade,
  from_customer_id uuid references public.customers (id) on delete set null,
  to_customer_id uuid references public.customers (id) on delete set null,
  transferred_by uuid references auth.users (id),
  transferred_at timestamptz not null default now()
);

create index if not exists idx_line_transfers_line on public.line_transfers using btree (line_id, transferred_at desc);

alter table public.work_orders
  add column if not exists branch_id uuid references public.branches (id) on delete set null,
  add column if not exists closed_at timestamptz,
  add column if not exists closed_by uuid references auth.users (id),
  add column if not exists close_notes text;

create table if not exists public.device_brands (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.device_models (
  id uuid primary key default gen_random_uuid(),
  brand_id uuid not null references public.device_brands (id) on delete cascade,
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (brand_id, name)
);

create table if not exists public.customer_devices (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers (id) on delete cascade,
  branch_id uuid references public.branches (id) on delete set null,
  serial_no text not null,
  brand_id uuid references public.device_brands (id) on delete set null,
  model_id uuid references public.device_models (id) on delete set null,
  notes text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  unique (serial_no)
);

alter table public.service_records
  add column if not exists device_id uuid references public.customer_devices (id) on delete set null,
  add column if not exists steps jsonb not null default '[]'::jsonb;

alter table public.device_brands enable row level security;
alter table public.device_models enable row level security;
alter table public.customer_devices enable row level security;
alter table public.line_transfers enable row level security;

drop policy if exists "device_brands_select_active_or_admin" on public.device_brands;
create policy "device_brands_select_active_or_admin"
on public.device_brands
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "device_brands_write_admin" on public.device_brands;
create policy "device_brands_write_admin"
on public.device_brands
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "device_models_select_active_or_admin" on public.device_models;
create policy "device_models_select_active_or_admin"
on public.device_models
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "device_models_write_admin" on public.device_models;
create policy "device_models_write_admin"
on public.device_models
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

drop policy if exists "customer_devices_select_active_or_admin" on public.customer_devices;
create policy "customer_devices_select_active_or_admin"
on public.customer_devices
for select
to authenticated
using (public.is_admin() or is_active = true);

drop policy if exists "customer_devices_write_authenticated" on public.customer_devices;
create policy "customer_devices_write_authenticated"
on public.customer_devices
for insert
to authenticated
with check (true);

drop policy if exists "customer_devices_update_authenticated" on public.customer_devices;
create policy "customer_devices_update_authenticated"
on public.customer_devices
for update
to authenticated
using (public.is_admin() or is_active = true)
with check (public.is_admin() or is_active = true);

drop policy if exists "line_transfers_select_admin" on public.line_transfers;
create policy "line_transfers_select_admin"
on public.line_transfers
for select
to authenticated
using (public.is_admin());

drop policy if exists "line_transfers_insert_admin" on public.line_transfers;
create policy "line_transfers_insert_admin"
on public.line_transfers
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "work_orders_select_active_or_admin" on public.work_orders;
drop policy if exists "work_orders_select_active_or_assigned" on public.work_orders;
create policy "work_orders_select_active_or_assigned"
on public.work_orders
for select
to authenticated
using (
  public.is_admin()
  or (
    is_active = true
    and (
      assigned_to = auth.uid()
      or created_by = auth.uid()
    )
  )
);

drop policy if exists "work_orders_update_authenticated" on public.work_orders;
drop policy if exists "work_orders_update_admin_or_assigned" on public.work_orders;
create policy "work_orders_update_admin_or_assigned"
on public.work_orders
for update
to authenticated
using (
  public.is_admin()
  or assigned_to = auth.uid()
  or created_by = auth.uid()
)
with check (
  public.is_admin()
  or assigned_to = auth.uid()
  or created_by = auth.uid()
);
