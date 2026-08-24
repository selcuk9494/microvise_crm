create extension if not exists pgcrypto;

create table if not exists public.mutakabat_records (
  id uuid primary key default gen_random_uuid(),
  period_year int not null,
  period_month int not null check (period_month between 1 and 12),
  title text not null default '',
  notes text not null default '',
  status text not null default 'draft',
  unit_prices jsonb not null default '{}'::jsonb,
  summary jsonb not null default '{}'::jsonb,
  detail_sheets jsonb not null default '{}'::jsonb,
  source_files jsonb not null default '{}'::jsonb,
  created_by uuid,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_mutakabat_records_active_period
  on public.mutakabat_records (period_year, period_month)
  where is_active = true;

create index if not exists idx_mutakabat_records_created_at
  on public.mutakabat_records (created_at desc);

create or replace function public.mutakabat_records_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_mutakabat_records_updated_at on public.mutakabat_records;
create trigger set_mutakabat_records_updated_at
before update on public.mutakabat_records
for each row execute function public.mutakabat_records_set_updated_at();

alter table public.mutakabat_records enable row level security;

drop policy if exists mutakabat_records_select on public.mutakabat_records;
create policy mutakabat_records_select
  on public.mutakabat_records
  for select
  to authenticated
  using (true);

drop policy if exists mutakabat_records_insert on public.mutakabat_records;
create policy mutakabat_records_insert
  on public.mutakabat_records
  for insert
  to authenticated
  with check (true);

drop policy if exists mutakabat_records_update on public.mutakabat_records;
create policy mutakabat_records_update
  on public.mutakabat_records
  for update
  to authenticated
  using (true)
  with check (true);

drop policy if exists mutakabat_records_delete on public.mutakabat_records;
create policy mutakabat_records_delete
  on public.mutakabat_records
  for delete
  to authenticated
  using (public.is_admin());
