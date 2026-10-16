-- Maliye'ye gitmiş satış faturalarının kalem/tutarının SAP çekme veya
-- başka yazımlarla ezilmesini veritabanı seviyesinde engeller.
-- Alış (gelen) e-faturalar ve tahsilat alanları kilit dışındadır.

create or replace function public.prevent_maliye_sales_invoice_content_update()
returns trigger
language plpgsql
as $fn$
begin
  if current_setting('microvise.bypass_maliye_lock', true) = 'on' then
    return new;
  end if;
  if not (
    coalesce(old.invoice_type, 'sales') = 'sales'
    and (
      lower(trim(coalesce(old.e_invoice_status, ''))) in (
        'sent', 'manual', 'manual_sent', 'prepared'
      )
      or coalesce(old.e_invoice_uuid::text, '') <> ''
      or coalesce(nullif(trim(old.e_invoice_number), ''), '') <> ''
    )
  ) then
    return new;
  end if;
  if new.grand_total is distinct from old.grand_total
     or new.subtotal is distinct from old.subtotal
     or new.tax_total is distinct from old.tax_total
     or new.discount_total is distinct from old.discount_total
     or new.currency is distinct from old.currency
     or new.customer_id is distinct from old.customer_id
     or new.invoice_date is distinct from old.invoice_date
     or new.due_date is distinct from old.due_date
     or new.prices_include_vat is distinct from old.prices_include_vat
     or new.invoice_type is distinct from old.invoice_type
  then
    raise exception 'Maliye e-faturası içeriği değiştirilemez.'
      using errcode = 'P0001';
  end if;
  return new;
end;
$fn$;

create or replace function public.prevent_maliye_sales_invoice_item_mutation()
returns trigger
language plpgsql
as $fn$
declare
  inv record;
  locked_invoice_id uuid;
begin
  if current_setting('microvise.bypass_maliye_lock', true) = 'on' then
    return coalesce(new, old);
  end if;
  locked_invoice_id := coalesce(new.invoice_id, old.invoice_id);
  select
    i.invoice_type,
    i.e_invoice_status,
    i.e_invoice_uuid,
    i.e_invoice_number
  into inv
  from public.invoices i
  where i.id = locked_invoice_id;
  if not found then
    return coalesce(new, old);
  end if;
  if coalesce(inv.invoice_type, 'sales') = 'sales'
     and (
       lower(trim(coalesce(inv.e_invoice_status, ''))) in (
         'sent', 'manual', 'manual_sent', 'prepared'
       )
       or coalesce(inv.e_invoice_uuid::text, '') <> ''
       or coalesce(nullif(trim(inv.e_invoice_number), ''), '') <> ''
     )
  then
    raise exception 'Maliye e-faturasının kalemleri değiştirilemez.'
      using errcode = 'P0001';
  end if;
  return coalesce(new, old);
end;
$fn$;

drop trigger if exists trg_prevent_maliye_sales_invoice_content_update
  on public.invoices;
create trigger trg_prevent_maliye_sales_invoice_content_update
  before update on public.invoices
  for each row
  execute procedure public.prevent_maliye_sales_invoice_content_update();

drop trigger if exists trg_prevent_maliye_sales_invoice_item_mutation
  on public.invoice_items;
create trigger trg_prevent_maliye_sales_invoice_item_mutation
  before insert or update or delete on public.invoice_items
  for each row
  execute procedure public.prevent_maliye_sales_invoice_item_mutation();
