alter table public.hat_lisans_billing_settings
  add column if not exists line_price_month_try numeric(14, 4) not null default 0,
  add column if not exists line_price_month_usd numeric(14, 4) not null default 0,
  add column if not exists gmp3_price_month_try numeric(14, 4) not null default 0,
  add column if not exists gmp3_price_month_usd numeric(14, 4) not null default 0,
  add column if not exists iresto_price_month_try numeric(14, 4) not null default 0,
  add column if not exists iresto_price_month_usd numeric(14, 4) not null default 0,
  add column if not exists line_tax_rate numeric(6, 2) not null default 20,
  add column if not exists gmp3_tax_rate numeric(6, 2) not null default 20,
  add column if not exists iresto_tax_rate numeric(6, 2) not null default 20,
  add column if not exists default_period text not null default 'yearly';
