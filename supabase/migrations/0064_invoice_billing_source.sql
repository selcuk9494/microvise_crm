alter table public.invoices
  add column if not exists billing_source text;

create index if not exists idx_invoices_billing_source
on public.invoices (billing_source)
where billing_source is not null;
