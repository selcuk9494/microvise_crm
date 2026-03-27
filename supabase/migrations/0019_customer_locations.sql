create table if not exists public.customer_locations (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  title text not null default 'Konum',
  description text,
  address text,
  location_lat double precision,
  location_lng double precision,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_customer_locations_customer
on public.customer_locations(customer_id, created_at desc);

alter table public.customer_locations enable row level security;

drop policy if exists "customer_locations_select" on public.customer_locations;
create policy "customer_locations_select"
on public.customer_locations
for select
to authenticated
using (true);

drop policy if exists "customer_locations_insert" on public.customer_locations;
create policy "customer_locations_insert"
on public.customer_locations
for insert
to authenticated
with check (true);

drop policy if exists "customer_locations_update" on public.customer_locations;
create policy "customer_locations_update"
on public.customer_locations
for update
to authenticated
using (true)
with check (true);

drop policy if exists "customer_locations_delete" on public.customer_locations;
create policy "customer_locations_delete"
on public.customer_locations
for delete
to authenticated
using (true);
