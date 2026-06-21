-- =====================================================
-- E-FATURA ENTEGRASYON ALTYAPISI
-- KKTC Maliye test/canli REST API ayarlari ve gonderim durumu
-- =====================================================

create table if not exists public.e_invoice_settings (
  id uuid primary key default gen_random_uuid(),
  environment text not null default 'test' check (environment in ('test', 'production')),
  api_base_url text not null default 'https://test-efatura.maliye.gov.ct.tr/api',
  token_url text not null default 'https://keycloak.maliye.gov.ct.tr/realms/vergi-stage/protocol/openid-connect/token',
  client_id text not null default 'efatura-frontend',
  username text,
  password text,
  seller_vkn text not null default '620009058',
  seller_title text not null default 'MICROVISE INNOVATION LTD',
  seller_branch_code text not null default '1',
  seller_tax_office text default 'Lefkoşa',
  seller_city text default 'LEFKOŞA',
  seller_country_code text not null default 'XCT',
  seller_country text default 'Kuzey Kıbrıs Türk Cumhuriyeti',
  seller_address_line1 text,
  seller_address_line2 text,
  seller_phone text,
  seller_email text,
  seller_website text,
  akinsoft_sync_enabled text default 'false',
  akinsoft_vpn_name text,
  akinsoft_vpn_host text,
  akinsoft_vpn_username text,
  akinsoft_vpn_password text,
  akinsoft_mssql_host text,
  akinsoft_mssql_port text default '1433',
  akinsoft_mssql_database text,
  akinsoft_database_year text,
  akinsoft_database_pattern text,
  akinsoft_mssql_username text,
  akinsoft_mssql_password text,
  akinsoft_sync_notes text,
  next_sales_number bigint not null default 1,
  next_purchase_number bigint not null default 1,
  last_token_at timestamptz,
  last_sync_at timestamptz,
  is_active boolean not null default true,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.e_invoice_settings (
  environment,
  api_base_url,
  token_url,
  client_id,
  seller_vkn,
  seller_title,
  seller_branch_code,
  seller_tax_office,
  seller_city,
  seller_country_code,
  seller_country,
  seller_address_line1
)
values (
  'test',
  'https://test-efatura.maliye.gov.ct.tr/api',
  'https://keycloak.maliye.gov.ct.tr/realms/vergi-stage/protocol/openid-connect/token',
  'efatura-frontend',
  '620009058',
  'MICROVISE INNOVATION LTD',
  '1',
  'Lefkoşa',
  'LEFKOŞA',
  'XCT',
  'Kuzey Kıbrıs Türk Cumhuriyeti',
  'ATATÜRK CAD YENİŞEHİR EMEK 2 APT. DIŞ KAPI NO:1'
)
on conflict do nothing;

alter table public.e_invoice_settings
  add column if not exists akinsoft_sync_enabled text default 'false',
  add column if not exists akinsoft_vpn_name text,
  add column if not exists akinsoft_vpn_host text,
  add column if not exists akinsoft_vpn_username text,
  add column if not exists akinsoft_vpn_password text,
  add column if not exists akinsoft_mssql_host text,
  add column if not exists akinsoft_mssql_port text default '1433',
  add column if not exists akinsoft_mssql_database text,
  add column if not exists akinsoft_database_year text,
  add column if not exists akinsoft_database_pattern text,
  add column if not exists akinsoft_mssql_username text,
  add column if not exists akinsoft_mssql_password text,
  add column if not exists akinsoft_sync_notes text;

alter table public.invoices
  add column if not exists e_invoice_number text,
  add column if not exists e_invoice_uuid uuid,
  add column if not exists e_invoice_status text not null default 'not_sent'
    check (e_invoice_status in ('not_sent', 'prepared', 'sent', 'failed', 'cancelled')),
  add column if not exists e_invoice_environment text check (e_invoice_environment in ('test', 'production')),
  add column if not exists e_invoice_payload jsonb,
  add column if not exists e_invoice_response jsonb,
  add column if not exists e_invoice_error text,
  add column if not exists e_invoice_sent_at timestamptz;

alter table public.products
  add column if not exists akinsoft_group text,
  add column if not exists akinsoft_sub_group text,
  add column if not exists akinsoft_source_id text;

create table if not exists public.akinsoft_sync_map (
  id uuid primary key default gen_random_uuid(),
  source_system text not null default 'akinsoft',
  source_type text not null,
  source_id text not null,
  source_code text,
  source_name text,
  local_table text not null,
  local_id uuid not null,
  matched_manually boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (source_system, source_type, source_id)
);

create index if not exists idx_akinsoft_sync_map_code
on public.akinsoft_sync_map (source_system, source_type, source_code);

insert into public.tax_rates (name, rate, is_default, sort_order)
select 'KDV %5', 5, false, 5
where exists (
  select 1 from information_schema.tables
  where table_schema = 'public' and table_name = 'tax_rates'
)
and not exists (select 1 from public.tax_rates where rate = 5);

insert into public.tax_rates (name, rate, is_default, sort_order)
select 'KDV %16', 16, false, 16
where exists (
  select 1 from information_schema.tables
  where table_schema = 'public' and table_name = 'tax_rates'
)
and not exists (select 1 from public.tax_rates where rate = 16);

create index if not exists idx_invoices_e_invoice_status
on public.invoices (e_invoice_status, invoice_date desc);

alter table public.e_invoice_settings enable row level security;

drop policy if exists "e_invoice_settings_select" on public.e_invoice_settings;
create policy "e_invoice_settings_select"
on public.e_invoice_settings
for select to authenticated
using (true);

drop policy if exists "e_invoice_settings_write" on public.e_invoice_settings;
create policy "e_invoice_settings_write"
on public.e_invoice_settings
for all to authenticated
using (public.is_admin())
with check (public.is_admin());
