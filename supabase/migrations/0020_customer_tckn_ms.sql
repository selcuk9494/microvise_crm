alter table public.customers
add column if not exists tckn_ms text;

alter table public.application_forms
add column if not exists customer_tckn_ms text;
