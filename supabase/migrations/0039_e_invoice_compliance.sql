alter table public.invoices
  add column if not exists irsaliye_no text,
  add column if not exists irsaliye_tarihi date;

alter table public.invoice_items
  add column if not exists special_matrah boolean not null default false,
  add column if not exists tax_exemption_code text,
  add column if not exists tax_exemption_description text;

update public.e_invoice_settings
set seller_vkn = '0' || seller_vkn,
    updated_at = now()
where seller_vkn ~ '^[0-9]{9}$';

alter table public.customers
  drop constraint if exists customers_vkn_10_digits_check;

alter table public.customers
  add constraint customers_vkn_10_digits_check
  check (vkn is null or vkn = '' or vkn ~ '^[0-9]{10}$')
  not valid;
