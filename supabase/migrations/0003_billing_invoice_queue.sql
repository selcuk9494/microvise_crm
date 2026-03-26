create table if not exists public.invoice_items (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid references public.customers (id) on delete set null,
  item_type text not null check (item_type in ('line_renewal', 'gmp3_renewal')),
  source_table text not null check (source_table in ('lines', 'licenses')),
  source_id uuid not null,
  description text not null,
  amount numeric(12,2),
  currency text not null default 'TRY',
  status text not null default 'pending' check (status in ('pending', 'invoiced')),
  invoiced_at timestamptz,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now()
);

create index if not exists idx_invoice_items_status on public.invoice_items using btree (status, created_at desc);
create index if not exists idx_invoice_items_customer on public.invoice_items using btree (customer_id, created_at desc);

alter table public.invoice_items enable row level security;

drop policy if exists "invoice_items_select_admin" on public.invoice_items;
create policy "invoice_items_select_admin"
on public.invoice_items
for select
to authenticated
using (public.is_admin());

drop policy if exists "invoice_items_write_admin" on public.invoice_items;
create policy "invoice_items_write_admin"
on public.invoice_items
for all
to authenticated
using (public.is_admin())
with check (public.is_admin());

