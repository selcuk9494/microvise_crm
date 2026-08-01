-- Akınsoft push outcome on CRM invoices (distinct from Maliye e_invoice_status).
alter table public.invoices
  add column if not exists akinsoft_sync_status text,
  add column if not exists akinsoft_synced_at timestamptz,
  add column if not exists akinsoft_sync_error text;

comment on column public.invoices.akinsoft_sync_status is
  'synced | error | pending — Akınsoft ERP push state';

-- Backfill: already mapped invoices count as synced.
update public.invoices i
set
  akinsoft_sync_status = 'synced',
  akinsoft_synced_at = coalesce(i.akinsoft_synced_at, m.updated_at, m.created_at, now())
from public.akinsoft_sync_map m
where m.source_system = 'akinsoft'
  and m.source_type = 'invoice'
  and m.local_id = i.id
  and (
    i.akinsoft_sync_status is null
    or i.akinsoft_sync_status = ''
    or i.akinsoft_sync_status = 'pending'
  );

create index if not exists idx_invoices_akinsoft_sync_status
  on public.invoices (akinsoft_sync_status)
  where akinsoft_sync_status is not null;
