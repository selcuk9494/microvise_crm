const { query } = require('./db');

const EINVOICE_CLOSE_STATUSES = new Set([
  'sent',
  'manual',
  'manual_sent',
  'received',
]);

function invoiceStatusAfterPayment({
  currentStatus,
  paidAmount,
  grandTotal,
  invoiceType,
  eInvoiceStatus,
}) {
  const current = String(currentStatus || 'open');
  if (current === 'draft' || current === 'cancelled') return current;
  const paid = Number(paidAmount) || 0;
  const total = Number(grandTotal) || 0;
  if (paid + 0.009 >= total && total > 0) {
    const type = String(invoiceType || 'sales');
    const eStatus = String(eInvoiceStatus || 'not_sent');
    if (type === 'purchase' || EINVOICE_CLOSE_STATUSES.has(eStatus)) {
      return 'paid';
    }
    return 'open';
  }
  if (paid > 0.009) return 'partial';
  return 'open';
}

const REFRESH_SQL = `
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
`;

let ensured = false;

async function ensureInvoicePaidCloseRule() {
  if (ensured) return;
  await query(REFRESH_SQL);
  await query(
    `drop trigger if exists trigger_update_invoice_status on public.transactions`,
  );
  await query(`
    create trigger trigger_update_invoice_status
    after insert or update or delete on public.transactions
    for each row execute procedure public.update_invoice_status()
  `);
  await query(
    `drop trigger if exists trigger_refresh_invoice_paid_on_einvoice on public.invoices`,
  );
  await query(`
    create trigger trigger_refresh_invoice_paid_on_einvoice
    after update of e_invoice_status on public.invoices
    for each row
    when (old.e_invoice_status is distinct from new.e_invoice_status)
    execute procedure public.refresh_invoice_paid_status_from_row()
  `);
  ensured = true;
}

async function applyInvoicePaidStatus(invoiceId, txQuery = query) {
  const id = String(invoiceId || '').trim();
  if (!id) return;
  await txQuery(`select public.refresh_invoice_paid_status($1::uuid)`, [id]);
}

module.exports = {
  invoiceStatusAfterPayment,
  ensureInvoicePaidCloseRule,
  applyInvoicePaidStatus,
  EINVOICE_CLOSE_STATUSES,
};
