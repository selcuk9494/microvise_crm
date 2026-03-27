alter table public.customer_locations
  add column if not exists location_link text;
