alter table public.customers
  add column if not exists email_2 text,
  add column if not exists email_3 text;
