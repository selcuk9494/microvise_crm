alter table public.e_invoice_settings
  add column if not exists pos_valor_days integer not null default 1;

alter table public.invoice_payment_links
  add column if not exists valor_days integer;

update public.e_invoice_settings
set pos_valor_days = 1
where pos_valor_days is null;
