-- Sanal POS: mail gönderimi ve hesaba yatma takibi
alter table public.invoice_payment_links
  add column if not exists emailed_at timestamptz,
  add column if not exists emailed_to text,
  add column if not exists settled_at timestamptz,
  add column if not exists settled_by uuid;

-- Tekrarlayan fatura / ödeme linki planları
create table if not exists public.recurring_billing_plans (
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.customers(id) on delete cascade,
  title text not null,
  description text,
  amount numeric(14,2) not null,
  tax_rate numeric(8,2) not null default 20,
  currency text not null default 'TRY',
  billing_day integer not null default 1,
  email text,
  is_active boolean not null default true,
  last_run_on date,
  last_invoice_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint recurring_billing_plans_day_chk
    check (billing_day >= 1 and billing_day <= 31)
);

create index if not exists idx_recurring_billing_plans_active
  on public.recurring_billing_plans (is_active, billing_day);

create table if not exists public.recurring_billing_runs (
  id uuid primary key default gen_random_uuid(),
  plan_id uuid not null references public.recurring_billing_plans(id) on delete cascade,
  period_key text not null,
  invoice_id uuid,
  payment_link_id uuid,
  emailed_to text,
  status text not null default 'created',
  error_message text,
  created_at timestamptz not null default now(),
  unique (plan_id, period_key)
);

create index if not exists idx_recurring_billing_runs_plan
  on public.recurring_billing_runs (plan_id, created_at desc);
