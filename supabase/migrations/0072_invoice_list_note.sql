-- Liste ekranı hatırlatıcı notu (cari ve resmi fatura notundan bağımsız).
-- Maliye / SAP payload’ına gitmez.

alter table public.invoices
  add column if not exists list_note text,
  add column if not exists list_note_color text;

comment on column public.invoices.list_note is
  'E-fatura listesinde cari adının yanında gösterilen hatırlatıcı not. Resmi notes alanından ayrıdır.';
comment on column public.invoices.list_note_color is
  'Liste notu rengi: orange, blue, purple, green, pink, teal.';
