alter table public.work_orders
  add column if not exists contact_phone text,
  add column if not exists location_link text;
