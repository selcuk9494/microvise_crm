alter table public.finance_accounts
  add column if not exists akinsoft_source_id text,
  add column if not exists akinsoft_bank_source_id text;

alter table public.finance_transactions
  add column if not exists akinsoft_source_id text;

create table if not exists public.finance_banks (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  branch text,
  phone text,
  address text,
  akinsoft_source_id text,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists idx_finance_banks_akinsoft_source
  on public.finance_banks (akinsoft_source_id)
  where akinsoft_source_id is not null and akinsoft_source_id <> '';

create unique index if not exists idx_finance_accounts_akinsoft_source
  on public.finance_accounts (akinsoft_source_id)
  where akinsoft_source_id is not null and akinsoft_source_id <> '';

create table if not exists public.finance_operation_logs (
  id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null default now(),
  created_by uuid,
  created_by_name text,
  action text not null,
  entity_type text not null,
  entity_id uuid,
  account_id uuid,
  akinsoft_source_id text,
  summary text not null default '',
  payload jsonb not null default '{}'::jsonb,
  is_active boolean not null default true
);

create index if not exists idx_finance_operation_logs_day
  on public.finance_operation_logs (occurred_at desc);
