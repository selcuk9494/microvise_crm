create extension if not exists pgcrypto;

create table if not exists public.mutakabat_price_settings (
  id uuid primary key default gen_random_uuid(),
  name text not null default 'Aktif Fiyatlar',
  unit_prices jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_mutakabat_price_settings_created_at
  on public.mutakabat_price_settings (created_at desc);

alter table public.mutakabat_price_settings enable row level security;

drop policy if exists mutakabat_price_settings_select on public.mutakabat_price_settings;
create policy mutakabat_price_settings_select
  on public.mutakabat_price_settings
  for select
  to authenticated
  using (true);

drop policy if exists mutakabat_price_settings_insert on public.mutakabat_price_settings;
create policy mutakabat_price_settings_insert
  on public.mutakabat_price_settings
  for insert
  to authenticated
  with check (true);

drop policy if exists mutakabat_price_settings_update on public.mutakabat_price_settings;
create policy mutakabat_price_settings_update
  on public.mutakabat_price_settings
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists mutakabat_price_settings_delete on public.mutakabat_price_settings;
create policy mutakabat_price_settings_delete
  on public.mutakabat_price_settings
  for delete
  to authenticated
  using (public.is_admin());
