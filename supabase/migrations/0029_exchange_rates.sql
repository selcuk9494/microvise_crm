create table if not exists public.exchange_rates (
  id uuid primary key default gen_random_uuid(),
  currency text not null check (currency in ('TRY', 'USD', 'EUR', 'GBP')),
  rate_to_try numeric(12,6) not null default 1,
  effective_date date not null default current_date,
  source text not null default 'manual',
  is_manual boolean not null default false,
  created_by uuid references auth.users (id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (currency, effective_date)
);

create index if not exists idx_exchange_rates_effective_date
on public.exchange_rates (effective_date desc, currency);

alter table public.exchange_rates enable row level security;

drop policy if exists "exchange_rates_select" on public.exchange_rates;
create policy "exchange_rates_select"
on public.exchange_rates
for select
to authenticated
using (true);

drop policy if exists "exchange_rates_insert" on public.exchange_rates;
create policy "exchange_rates_insert"
on public.exchange_rates
for insert
to authenticated
with check (true);

drop policy if exists "exchange_rates_update" on public.exchange_rates;
create policy "exchange_rates_update"
on public.exchange_rates
for update
to authenticated
using (true);

create or replace function public.set_exchange_rate_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists trigger_exchange_rates_updated_at on public.exchange_rates;
create trigger trigger_exchange_rates_updated_at
before update on public.exchange_rates
for each row
execute procedure public.set_exchange_rate_updated_at();

insert into public.exchange_rates (
  currency,
  rate_to_try,
  effective_date,
  source,
  is_manual
)
values
  ('TRY', 1, current_date, 'system', false)
on conflict (currency, effective_date) do nothing;
