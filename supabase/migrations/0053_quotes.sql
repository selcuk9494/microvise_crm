create extension if not exists pgcrypto;

create table if not exists public.quote_settings (
  id uuid primary key default gen_random_uuid(),
  prefix text not null default 'TKL',
  next_number integer not null default 1,
  year integer not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (year)
);

create table if not exists public.quotes (
  id uuid primary key default gen_random_uuid(),
  quote_number text not null unique,
  customer_id uuid not null references public.customers (id) on delete restrict,
  quote_date date not null default current_date,
  valid_until date,
  currency text not null default 'TRY' check (currency in ('TRY', 'USD', 'EUR', 'GBP')),
  exchange_rate numeric(10,4) not null default 1.0,
  prices_include_vat boolean not null default false,
  subtotal numeric(14,2) not null default 0,
  tax_total numeric(14,2) not null default 0,
  discount_total numeric(14,2) not null default 0,
  grand_total numeric(14,2) not null default 0,
  status text not null default 'draft' check (
    status in ('draft', 'sent', 'accepted', 'rejected', 'expired', 'converted')
  ),
  notes text,
  converted_invoice_id uuid references public.invoices (id) on delete set null,
  is_active boolean not null default true,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.quote_items (
  id uuid primary key default gen_random_uuid(),
  quote_id uuid not null references public.quotes (id) on delete cascade,
  product_id uuid references public.products (id) on delete set null,
  description text not null,
  quantity numeric(12,4) not null default 1,
  unit text default 'Adet',
  unit_price numeric(14,4) not null default 0,
  tax_rate numeric(5,2) not null default 20,
  tax_amount numeric(14,2) not null default 0,
  discount_rate numeric(5,2) not null default 0,
  discount_amount numeric(14,2) not null default 0,
  line_total numeric(14,2) not null default 0,
  sort_order integer default 0,
  created_at timestamptz not null default now()
);

create index if not exists idx_quotes_customer_id on public.quotes (customer_id);
create index if not exists idx_quotes_quote_date on public.quotes (quote_date desc);
create index if not exists idx_quotes_status on public.quotes (status);
create index if not exists idx_quotes_is_active on public.quotes (is_active);
create index if not exists idx_quote_items_quote_id on public.quote_items (quote_id);

create or replace function public.quotes_set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_quotes_updated_at on public.quotes;
create trigger set_quotes_updated_at
before update on public.quotes
for each row execute function public.quotes_set_updated_at();

create or replace function public.generate_quote_number()
returns text
language plpgsql
security definer
as $$
declare
  v_prefix text;
  v_next_number integer;
  v_year integer;
begin
  v_year := extract(year from current_date);

  select prefix, next_number into v_prefix, v_next_number
  from public.quote_settings
  where year = v_year
  for update;

  if not found then
    v_prefix := 'TKL';
    v_next_number := 1;
    insert into public.quote_settings (prefix, next_number, year)
    values (v_prefix, v_next_number + 1, v_year);
  else
    update public.quote_settings
    set next_number = next_number + 1
    where year = v_year;
  end if;

  return v_prefix || '-' || v_year || '-' || lpad(v_next_number::text, 6, '0');
end;
$$;

alter table public.quotes enable row level security;
alter table public.quote_items enable row level security;
alter table public.quote_settings enable row level security;

drop policy if exists quotes_select on public.quotes;
create policy quotes_select on public.quotes for select to authenticated using (true);

drop policy if exists quotes_insert on public.quotes;
create policy quotes_insert on public.quotes for insert to authenticated with check (true);

drop policy if exists quotes_update on public.quotes;
create policy quotes_update on public.quotes for update to authenticated using (true) with check (true);

drop policy if exists quotes_delete on public.quotes;
create policy quotes_delete on public.quotes for delete to authenticated using (public.is_admin());

drop policy if exists quote_items_select on public.quote_items;
create policy quote_items_select on public.quote_items for select to authenticated using (true);

drop policy if exists quote_items_insert on public.quote_items;
create policy quote_items_insert on public.quote_items for insert to authenticated with check (true);

drop policy if exists quote_items_update on public.quote_items;
create policy quote_items_update on public.quote_items for update to authenticated using (true) with check (true);

drop policy if exists quote_items_delete on public.quote_items;
create policy quote_items_delete on public.quote_items for delete to authenticated using (true);
