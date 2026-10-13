-- Cari listesi / açık fatura ekranı hatırlatıcı etiketi.
-- Resmi müşteri notes alanından ayrıdır; Maliye / SAP’a gitmez.

alter table public.customers
  add column if not exists list_note text,
  add column if not exists list_note_color text;

comment on column public.customers.list_note is
  'Açık fatura ve cari listelerinde ismin yanında gösterilen hatırlatıcı etiket.';
comment on column public.customers.list_note_color is
  'Cari etiket rengi: orange, blue, purple, green, pink, teal.';
