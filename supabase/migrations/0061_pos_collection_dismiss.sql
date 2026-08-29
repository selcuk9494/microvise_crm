alter table public.invoice_payment_links
  add column if not exists dismissed_at timestamptz,
  add column if not exists dismissed_by uuid;
