-- ERP (Akınsoft) orijinal fatura numarasını saklar; canlı e-fatura
-- gönderiminde invoice_number Maliye numarasına güncellenir.
alter table public.invoices
  add column if not exists erp_invoice_number text,
  add column if not exists erp_invoice_number_synced_at timestamptz;

create index if not exists idx_invoices_erp_invoice_number
  on public.invoices (erp_invoice_number)
  where erp_invoice_number is not null;
