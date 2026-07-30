-- Müşteri sipariş (PO) numarası; faturada banka bilgilerinin altında gösterilir.
alter table public.invoices
  add column if not exists po_number text;
