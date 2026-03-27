alter table public.application_forms
add column if not exists stock_product_id uuid references public.products(id) on delete set null;

alter table public.application_forms
add column if not exists stock_product_name text;

alter table public.application_forms
add column if not exists stock_registry_number text;
