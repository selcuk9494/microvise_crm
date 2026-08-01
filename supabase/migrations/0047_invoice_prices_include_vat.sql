-- Fatura seviyesinde KDV dahil birim fiyat girişi.
-- true iken formdaki birim fiyatlar KDV dahil kabul edilir;
-- kayıtta kalem tutarları KDV hariç matrah + KDV olarak saklanır.
alter table public.invoices
  add column if not exists prices_include_vat boolean not null default false;
