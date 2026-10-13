-- Açık fatura listesinde cari sürükle-bırak sırası.
alter table public.customers
  add column if not exists list_sort integer not null default 0;

comment on column public.customers.list_sort is
  'Açık fatura listesindeki cari sırası. 0 = henüz sürüklenmedi.';
