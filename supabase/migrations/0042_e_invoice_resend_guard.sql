alter table public.invoices
  add column if not exists e_invoice_sending_at timestamptz;

create index if not exists invoices_e_invoice_status_idx
  on public.invoices (e_invoice_status);
