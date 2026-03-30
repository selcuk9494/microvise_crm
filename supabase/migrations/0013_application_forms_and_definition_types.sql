create table if not exists public.fiscal_symbols (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists idx_fiscal_symbols_name_lower
on public.fiscal_symbols (lower(name));

alter table public.fiscal_symbols enable row level security;

drop policy if exists "fiscal_symbols_select" on public.fiscal_symbols;
create policy "fiscal_symbols_select"
on public.fiscal_symbols
for select
to authenticated
using (true);

drop policy if exists "fiscal_symbols_insert" on public.fiscal_symbols;
create policy "fiscal_symbols_insert"
on public.fiscal_symbols
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "fiscal_symbols_update" on public.fiscal_symbols;
create policy "fiscal_symbols_update"
on public.fiscal_symbols
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.business_activity_types (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create unique index if not exists idx_business_activity_types_name_lower
on public.business_activity_types (lower(name));

alter table public.business_activity_types enable row level security;

drop policy if exists "business_activity_types_select" on public.business_activity_types;
create policy "business_activity_types_select"
on public.business_activity_types
for select
to authenticated
using (true);

drop policy if exists "business_activity_types_insert" on public.business_activity_types;
create policy "business_activity_types_insert"
on public.business_activity_types
for insert
to authenticated
with check (public.is_admin());

drop policy if exists "business_activity_types_update" on public.business_activity_types;
create policy "business_activity_types_update"
on public.business_activity_types
for update
to authenticated
using (public.is_admin())
with check (public.is_admin());

create table if not exists public.application_forms (
  id uuid primary key default gen_random_uuid(),
  application_date date not null default current_date,
  customer_id uuid references public.customers(id) on delete set null,
  customer_name text not null,
  work_address text,
  tax_office_city_id uuid references public.cities(id) on delete set null,
  tax_office_city_name text,
  document_type text not null default 'VKN',
  file_registry_number text,
  director text,
  brand_id uuid references public.device_brands(id) on delete set null,
  brand_name text,
  model_id uuid references public.device_models(id) on delete set null,
  model_name text,
  fiscal_symbol_id uuid references public.fiscal_symbols(id) on delete set null,
  fiscal_symbol_name text,
  accounting_office text,
  okc_start_date date not null default current_date,
  business_activity_type_id uuid references public.business_activity_types(id) on delete set null,
  business_activity_name text,
  invoice_number text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists idx_application_forms_created_at
on public.application_forms (created_at desc);

create index if not exists idx_application_forms_customer
on public.application_forms (customer_id, created_at desc);

alter table public.application_forms enable row level security;

drop policy if exists "application_forms_select" on public.application_forms;
create policy "application_forms_select"
on public.application_forms
for select
to authenticated
using (true);

drop policy if exists "application_forms_insert" on public.application_forms;
create policy "application_forms_insert"
on public.application_forms
for insert
to authenticated
with check (true);

drop policy if exists "application_forms_update" on public.application_forms;
create policy "application_forms_update"
on public.application_forms
for update
to authenticated
using (true)
with check (true);

create or replace function public.application_forms_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_application_forms_updated_at on public.application_forms;
create trigger set_application_forms_updated_at
before update on public.application_forms
for each row
execute function public.application_forms_set_updated_at();
