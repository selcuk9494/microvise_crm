-- TANIMLAMALAR İÇİN YENİ TABLOLAR

-- 1. İŞ EMRİ TİPLERİ
create table if not exists public.work_order_types (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  description text,
  color text default '#6366F1',
  is_active boolean not null default true,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

-- Default iş emri tipleri
insert into public.work_order_types (name, description, color, sort_order) values
  ('Kurulum', 'Yeni sistem kurulumu', '#10B981', 1),
  ('Arıza', 'Arıza giderme', '#EF4444', 2),
  ('Bakım', 'Periyodik bakım', '#F59E0B', 3),
  ('Revizyon', 'Sistem revizyonu', '#6366F1', 4),
  ('Kontrol', 'Rutin kontrol', '#8B5CF6', 5)
on conflict (name) do nothing;

-- 2. KDV ORANLARI
create table if not exists public.tax_rates (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  rate numeric(5,2) not null,
  is_default boolean default false,
  is_active boolean not null default true,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

-- Default KDV oranları
insert into public.tax_rates (name, rate, is_default, sort_order) values
  ('KDV %0', 0, false, 1),
  ('KDV %1', 1, false, 2),
  ('KDV %10', 10, false, 3),
  ('KDV %20', 20, true, 4)
on conflict do nothing;

-- 3. work_orders tablosuna work_order_type_id ekle
alter table public.work_orders
  add column if not exists work_order_type_id uuid references public.work_order_types (id);

-- 4. RLS Policies
alter table public.work_order_types enable row level security;
alter table public.tax_rates enable row level security;

create policy "work_order_types_select" on public.work_order_types for select to authenticated using (true);
create policy "work_order_types_insert" on public.work_order_types for insert to authenticated with check (true);
create policy "work_order_types_update" on public.work_order_types for update to authenticated using (true);
create policy "work_order_types_delete" on public.work_order_types for delete to authenticated using (true);

create policy "tax_rates_select" on public.tax_rates for select to authenticated using (true);
create policy "tax_rates_insert" on public.tax_rates for insert to authenticated with check (true);
create policy "tax_rates_update" on public.tax_rates for update to authenticated using (true);
create policy "tax_rates_delete" on public.tax_rates for delete to authenticated using (true);
