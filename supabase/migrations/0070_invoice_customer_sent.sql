alter table public.invoices
  add column if not exists customer_sent_at timestamptz,
  add column if not exists customer_sent_via text;

create index if not exists idx_invoices_customer_sent_at
on public.invoices (customer_sent_at)
where customer_sent_at is not null;

comment on column public.invoices.customer_sent_at is
  'Müşteriye fatura/ödeme linki iletildiği an (mail, WhatsApp veya manuel işaret).';

update public.invoices i
set
  customer_sent_at = src.emailed_at,
  customer_sent_via = coalesce(nullif(btrim(i.customer_sent_via), ''), 'email')
from (
  select invoice_id, min(l.emailed_at) as emailed_at
  from public.invoice_payment_links l
  cross join lateral unnest(l.invoice_ids) as invoice_id
  where l.emailed_at is not null
  group by invoice_id
) src
where i.id = src.invoice_id
  and i.customer_sent_at is null;
