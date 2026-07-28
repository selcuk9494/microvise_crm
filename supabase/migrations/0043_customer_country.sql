alter table public.customers
  add column if not exists country_code text not null default 'XCT',
  add column if not exists country text not null default 'Kuzey Kıbrıs Türk Cumhuriyeti';

update public.customers
set country_code = 'XCT',
    country = 'Kuzey Kıbrıs Türk Cumhuriyeti'
where nullif(trim(country_code), '') is null
   or nullif(trim(country), '') is null;

alter table public.customers
  drop constraint if exists customers_country_code_iso3_check;

alter table public.customers
  add constraint customers_country_code_iso3_check
  check (country_code ~ '^[A-Z]{3}$');
