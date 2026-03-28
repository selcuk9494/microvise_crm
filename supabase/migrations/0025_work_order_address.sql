alter table public.work_orders
  add column if not exists address text;
