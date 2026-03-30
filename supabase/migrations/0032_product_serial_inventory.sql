create table if not exists public.product_serial_inventory (
  id uuid primary key default gen_random_uuid(),
  product_id uuid not null references public.products(id) on delete cascade,
  serial_number text not null,
  notes text,
  is_active boolean not null default true,
  consumed_by_application_form_id uuid references public.application_forms(id) on delete set null,
  consumed_at timestamptz,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_product_serial_inventory_unique
on public.product_serial_inventory (product_id, upper(btrim(serial_number)));

create index if not exists idx_product_serial_inventory_available
on public.product_serial_inventory (product_id, is_active, consumed_at);

alter table public.product_serial_inventory enable row level security;

drop policy if exists "product_serial_inventory_select" on public.product_serial_inventory;
create policy "product_serial_inventory_select"
on public.product_serial_inventory
for select
to authenticated
using (true);

drop policy if exists "product_serial_inventory_insert" on public.product_serial_inventory;
create policy "product_serial_inventory_insert"
on public.product_serial_inventory
for insert
to authenticated
with check (auth.uid() is not null);

drop policy if exists "product_serial_inventory_update" on public.product_serial_inventory;
create policy "product_serial_inventory_update"
on public.product_serial_inventory
for update
to authenticated
using (auth.uid() is not null)
with check (auth.uid() is not null);

drop policy if exists "product_serial_inventory_delete" on public.product_serial_inventory;
create policy "product_serial_inventory_delete"
on public.product_serial_inventory
for delete
to authenticated
using (public.is_admin());

create or replace function public.product_serial_inventory_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_product_serial_inventory_updated_at on public.product_serial_inventory;
create trigger set_product_serial_inventory_updated_at
before update on public.product_serial_inventory
for each row
execute function public.product_serial_inventory_set_updated_at();
