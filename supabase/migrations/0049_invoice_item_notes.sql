-- Kalem açıklaması (PDF / Maliye aciklama / Akınsoft FATURAHR.ACIKLAMA)
alter table public.invoice_items
  add column if not exists notes text;
