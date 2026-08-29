-- Satış faturası Maliye’ye gitmeden (veya manuel gönderildi olmadan) ödeme gelse bile kapanmasın.
create or replace function public.refresh_invoice_paid_status(p_invoice_id uuid)
returns void
language plpgsql
security definer
as $$
declare
  v_paid numeric(14,2);
  v_total numeric(14,2);
  v_type text;
  v_e_status text;
  v_current text;
  v_new_status text;
begin
  select
    coalesce(grand_total, 0),
    invoice_type,
    coalesce(e_invoice_status, 'not_sent'),
    status
  into v_total, v_type, v_e_status, v_current
  from public.invoices
  where id = p_invoice_id;

  if not found then
    return;
  end if;
  if v_current in ('draft', 'cancelled') then
    return;
  end if;

  select coalesce(sum(amount), 0) into v_paid
  from public.transactions
  where invoice_id = p_invoice_id and is_active = true;

  if v_paid + 0.009 >= v_total and v_total > 0 then
    if v_type = 'purchase' or v_e_status in ('sent', 'manual', 'manual_sent', 'received') then
      v_new_status := 'paid';
    else
      v_new_status := 'open';
    end if;
  elsif v_paid > 0.009 then
    v_new_status := 'partial';
  else
    v_new_status := 'open';
  end if;

  update public.invoices
  set
    paid_amount = v_paid,
    status = v_new_status,
    updated_at = now()
  where id = p_invoice_id
    and (
      coalesce(paid_amount, 0) is distinct from v_paid
      or coalesce(status, '') is distinct from v_new_status
    );
end;
$$;

create or replace function public.update_invoice_status()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.refresh_invoice_paid_status(coalesce(new.invoice_id, old.invoice_id));
  return coalesce(new, old);
end;
$$;

create or replace function public.refresh_invoice_paid_status_from_row()
returns trigger
language plpgsql
security definer
as $$
begin
  perform public.refresh_invoice_paid_status(new.id);
  return new;
end;
$$;

drop trigger if exists trigger_update_invoice_status on public.transactions;
create trigger trigger_update_invoice_status
after insert or update or delete on public.transactions
for each row execute procedure public.update_invoice_status();

drop trigger if exists trigger_refresh_invoice_paid_on_einvoice on public.invoices;
create trigger trigger_refresh_invoice_paid_on_einvoice
after update of e_invoice_status on public.invoices
for each row
when (old.e_invoice_status is distinct from new.e_invoice_status)
execute procedure public.refresh_invoice_paid_status_from_row();
