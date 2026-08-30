create table if not exists public.hat_lisans_billing_settings (
  id smallint primary key default 1 check (id = 1),
  line_product_id uuid,
  gmp3_product_id uuid,
  iresto_product_id uuid,
  line_price_try numeric(14, 4) not null default 0,
  line_price_usd numeric(14, 4) not null default 0,
  gmp3_price_try numeric(14, 4) not null default 0,
  gmp3_price_usd numeric(14, 4) not null default 0,
  iresto_price_try numeric(14, 4) not null default 0,
  iresto_price_usd numeric(14, 4) not null default 0,
  default_currency text not null default 'TRY',
  updated_at timestamptz not null default now()
);

alter table public.hat_lisans_billing_settings
  add column if not exists line_product_id uuid,
  add column if not exists gmp3_product_id uuid,
  add column if not exists iresto_product_id uuid,
  add column if not exists line_price_try numeric(14, 4) not null default 0,
  add column if not exists line_price_usd numeric(14, 4) not null default 0,
  add column if not exists gmp3_price_try numeric(14, 4) not null default 0,
  add column if not exists gmp3_price_usd numeric(14, 4) not null default 0,
  add column if not exists iresto_price_try numeric(14, 4) not null default 0,
  add column if not exists iresto_price_usd numeric(14, 4) not null default 0,
  add column if not exists default_currency text not null default 'TRY';

insert into public.hat_lisans_billing_settings (id)
values (1)
on conflict (id) do nothing;
