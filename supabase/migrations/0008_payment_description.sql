alter table public.payments
  add column if not exists description text;
