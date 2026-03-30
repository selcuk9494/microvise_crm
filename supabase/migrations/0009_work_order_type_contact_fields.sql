alter table if exists public.work_order_types
  add column if not exists location_info text,
  add column if not exists contact_name text,
  add column if not exists contact_phone text;
