alter table public.invoices
  add column if not exists e_invoice_pdf_bucket text,
  add column if not exists e_invoice_pdf_path text,
  add column if not exists e_invoice_pdf_sha256 text,
  add column if not exists e_invoice_pdf_created_at timestamptz;

comment on column public.invoices.e_invoice_pdf_path is
  'Maliye API arşiv verisi ve UBL kaydından üretilen PDF nesne yolu';
