const { query } = require('./db');

function toNumber(value, fallback = 0) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const parsed = Number(value);
  return Number.isFinite(parsed) ? parsed : fallback;
}

function toIsoDate(value, fallback) {
  const raw = String(value || '').trim();
  if (/^\d{4}-\d{2}-\d{2}/.test(raw)) return raw.slice(0, 10);
  const parsed = Date.parse(raw);
  if (Number.isFinite(parsed)) {
    return new Date(parsed).toISOString().slice(0, 10);
  }
  return fallback;
}

function shiftDate(isoDate, days) {
  const dt = new Date(`${isoDate}T12:00:00.000Z`);
  dt.setUTCDate(dt.getUTCDate() + days);
  return dt.toISOString().slice(0, 10);
}

function dayCount(fromDate, toDate) {
  const a = Date.parse(`${fromDate}T00:00:00.000Z`);
  const b = Date.parse(`${toDate}T00:00:00.000Z`);
  if (!Number.isFinite(a) || !Number.isFinite(b) || b < a) return 1;
  return Math.max(1, Math.round((b - a) / 86400000) + 1);
}

async function rows(sql, params = []) {
  try {
    const result = await query(sql, params);
    return Array.isArray(result.rows) ? result.rows : [];
  } catch (_) {
    return [];
  }
}

async function first(sql, params = []) {
  const list = await rows(sql, params);
  return list[0] || {};
}

function mapCountAmount(list) {
  return list.map((row) => ({
    key: String(row.key || row.status || row.method || row.type || '—'),
    label: String(row.label || row.key || row.status || row.method || row.type || '—'),
    count: toNumber(row.count),
    amount: toNumber(row.amount),
  }));
}

function mapNamed(list) {
  return list.map((row) => ({
    name: String(row.name || '—').trim() || '—',
    count: toNumber(row.count),
    amount: toNumber(row.amount),
    qty: toNumber(row.qty),
  }));
}

function userClause(column, userId, params) {
  if (!userId) return '';
  params.push(userId);
  return ` and ${column} = $${params.length}`;
}

async function buildSystemReports({ from, to, userId }) {
  const today = new Date().toISOString().slice(0, 10);
  const fromDate = toIsoDate(from, shiftDate(today, -29));
  const toDate = toIsoDate(to, today);
  const days = dayCount(fromDate, toDate);
  const prevTo = shiftDate(fromDate, -1);
  const prevFrom = shiftDate(prevTo, -(days - 1));
  const uid = String(userId || '').trim();

  const rangeParams = [fromDate, toDate];
  const prevParams = [prevFrom, prevTo];
  const rangeUser = [...rangeParams];
  const prevUser = [...prevParams];
  const createdBy = userClause('created_by', uid, rangeUser);
  const createdByPrev = userClause('created_by', uid, prevUser);

  const woParams = [...rangeParams];
  const woPrevParams = [...prevParams];
  const woUser = uid
    ? userClause('assigned_to', uid, woParams)
    : '';
  const woUserPrev = uid
    ? userClause('assigned_to', uid, woPrevParams)
    : '';

  const svcParams = [...rangeParams];
  const svcUser = uid
    ? userClause('coalesce(technician_id, created_by)', uid, svcParams)
    : '';

  const [
    salesKpi,
    prevSalesKpi,
    purchaseKpi,
    collectionsKpi,
    prevCollectionsKpi,
    paymentKpi,
    prevPaymentKpi,
    receivableKpi,
    payableKpi,
    quoteKpi,
    prevQuoteKpi,
    customerKpi,
    workOrderKpi,
    prevWorkOrderKpi,
    serviceKpi,
    stockKpi,
    lineStockKpi,
    posKpi,
    recurringKpi,
    financeKpi,
    formKpi,
    mutakabatKpi,
    dailySales,
    dailyCollections,
    dailyPayments,
    invoiceByStatus,
    invoiceByType,
    invoiceByEStatus,
    invoiceTopCustomers,
    invoiceTopProducts,
    paymentByMethod,
    paymentTopCustomers,
    quoteByStatus,
    quoteTopCustomers,
    customersByCity,
    workOrderByStatus,
    workOrderByUser,
    serviceByStatus,
    serviceByPriority,
    applicationByBrand,
    applicationByApproval,
    financeAccounts,
    financeByType,
    personnelRows,
    lowStock,
    licensesExpiring,
  ] = await Promise.all([
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount,
          coalesce(sum(tax_total), 0)::float as vat,
          coalesce(sum(paid_amount), 0)::float as paid
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and coalesce(status, 'open') not in ('cancelled', 'draft')
          and invoice_date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and coalesce(status, 'open') not in ('cancelled', 'draft')
          and invoice_date between $1::date and $2::date
          ${createdByPrev}
      `,
      prevUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount,
          coalesce(sum(tax_total), 0)::float as vat
        from public.invoices
        where coalesce(is_active, true) = true
          and invoice_type = 'purchase'
          and coalesce(status, 'open') not in ('cancelled', 'draft')
          and invoice_date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(amount), 0)::float as amount
        from public.transactions
        where coalesce(is_active, true) = true
          and transaction_type = 'collection'
          and transaction_date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select coalesce(sum(amount), 0)::float as amount
        from public.transactions
        where coalesce(is_active, true) = true
          and transaction_type = 'collection'
          and transaction_date between $1::date and $2::date
          ${createdByPrev}
      `,
      prevUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(amount), 0)::float as amount
        from public.payments
        where coalesce(is_active, true) = true
          and paid_at::date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select coalesce(sum(amount), 0)::float as amount
        from public.payments
        where coalesce(is_active, true) = true
          and paid_at::date between $1::date and $2::date
          ${createdByPrev}
      `,
      prevUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(greatest(grand_total - coalesce(paid_amount, 0), 0)), 0)::float as amount
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and status in ('open', 'partial')
      `,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(greatest(grand_total - coalesce(paid_amount, 0), 0)), 0)::float as amount
        from public.invoices
        where coalesce(is_active, true) = true
          and invoice_type = 'purchase'
          and status in ('open', 'partial')
      `,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount,
          count(*) filter (where status in ('accepted', 'converted'))::int as won_count,
          coalesce(sum(grand_total) filter (where status in ('accepted', 'converted')), 0)::float as won_amount,
          count(*) filter (where status = 'rejected')::int as lost_count,
          count(*) filter (where converted_invoice_id is not null)::int as converted_count
        from public.quotes
        where coalesce(is_active, true) = true
          and quote_date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount
        from public.quotes
        where coalesce(is_active, true) = true
          and quote_date between $1::date and $2::date
          ${createdByPrev}
      `,
      prevUser,
    ),
    first(
      `
        select
          count(*) filter (where is_active = true)::int as active,
          count(*)::int as total,
          count(*) filter (
            where created_at::date between $1::date and $2::date
          )::int as new_count
        from public.customers
      `,
      rangeParams,
    ),
    first(
      `
        select
          count(*)::int as created,
          count(*) filter (where status = 'open')::int as open,
          count(*) filter (where status = 'in_progress')::int as in_progress,
          count(*) filter (where status = 'done')::int as done
        from public.work_orders
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${woUser}
      `,
      woParams,
    ),
    first(
      `
        select count(*)::int as created
        from public.work_orders
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${woUserPrev}
      `,
      woPrevParams,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(coalesce(total_amount, 0)), 0)::float as amount
        from public.service_records
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${svcUser}
      `,
      svcParams,
    ),
    first(
      `
        select
          count(*) filter (where is_active = true)::int as products,
          (
            select count(*)::int
            from public.stock_levels
            where current_stock <= min_stock
          ) as low_stock
        from public.products
      `,
    ),
    first(
      `
        select
          count(*) filter (where coalesce(is_active, true) = true and consumed_at is null)::int as available,
          count(*) filter (
            where consumed_at is not null
              and consumed_at::date between $1::date and $2::date
          )::int as consumed
        from public.line_stock
      `,
      rangeParams,
    ),
    first(
      `
        select
          count(*)::int as count,
          coalesce(sum(amount) filter (where coalesce(status, '') in ('paid', 'settled')), 0)::float as collected,
          coalesce(sum(amount) filter (where coalesce(status, 'pending') in ('pending', 'sent')), 0)::float as pending,
          count(*) filter (where coalesce(status, 'pending') in ('pending', 'sent'))::int as pending_count
        from public.invoice_payment_links
        where dismissed_at is null
          and coalesce(paid_at, created_at)::date between $1::date and $2::date
      `,
      rangeParams,
    ),
    first(
      `
        select
          count(*) filter (where is_active = true)::int as active_plans,
          coalesce(sum(amount) filter (where is_active = true), 0)::float as monthly_amount,
          (
            select count(*)::int
            from public.recurring_billing_runs r
            where r.created_at::date between $1::date and $2::date
          ) as runs
        from public.recurring_billing_plans
      `,
      rangeParams,
    ),
    first(
      `
        select
          coalesce(sum(amount) filter (where direction = 'in'), 0)::float as inflow,
          coalesce(sum(amount) filter (where direction = 'out'), 0)::float as outflow,
          count(*)::int as count
        from public.finance_transactions
        where coalesce(is_active, true) = true
          and transaction_date between $1::date and $2::date
          ${createdBy}
      `,
      rangeUser,
    ),
    first(
      `
        select
          (select count(*)::int from public.application_forms
            where created_at::date between $1::date and $2::date) as applications,
          (select count(*)::int from public.scrap_forms
            where coalesce(is_active, true) = true
              and coalesce(form_date, created_at)::date between $1::date and $2::date) as scraps,
          (select count(*)::int from public.fault_forms
            where coalesce(is_active, true) = true
              and created_at::date between $1::date and $2::date) as faults,
          (select count(*)::int from public.transfer_forms
            where coalesce(is_active, true) = true
              and created_at::date between $1::date and $2::date) as transfers
      `,
      rangeParams,
    ),
    first(
      `
        select count(*)::int as count
        from public.mutakabat_records
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
      `,
      rangeParams,
    ),
    rows(
      `
        select invoice_date::text as day, coalesce(sum(grand_total), 0)::float as value
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and coalesce(status, 'open') not in ('cancelled', 'draft')
          and invoice_date between $1::date and $2::date
          ${createdBy}
        group by invoice_date
        order by invoice_date
      `,
      rangeUser,
    ),
    rows(
      `
        select transaction_date::text as day, coalesce(sum(amount), 0)::float as value
        from public.transactions
        where coalesce(is_active, true) = true
          and transaction_type = 'collection'
          and transaction_date between $1::date and $2::date
          ${createdBy}
        group by transaction_date
        order by transaction_date
      `,
      rangeUser,
    ),
    rows(
      `
        select paid_at::date::text as day, coalesce(sum(amount), 0)::float as value
        from public.payments
        where coalesce(is_active, true) = true
          and paid_at::date between $1::date and $2::date
          ${createdBy}
        group by paid_at::date
        order by paid_at::date
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(status, 'open') as key,
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and invoice_date between $1::date and $2::date
          ${createdBy}
        group by coalesce(status, 'open')
        order by amount desc
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(invoice_type, 'sales') as key,
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount,
          coalesce(sum(tax_total), 0)::float as vat
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(status, 'open') not in ('cancelled', 'draft')
          and invoice_date between $1::date and $2::date
          ${createdBy}
        group by coalesce(invoice_type, 'sales')
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(e_invoice_status, ''), 'not_sent') as key,
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount
        from public.invoices
        where coalesce(is_active, true) = true
          and coalesce(invoice_type, 'sales') = 'sales'
          and invoice_date between $1::date and $2::date
          ${createdBy}
        group by coalesce(nullif(e_invoice_status, ''), 'not_sent')
        order by count desc
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(c.name), ''), '—') as name,
          count(*)::int as count,
          coalesce(sum(i.grand_total), 0)::float as amount
        from public.invoices i
        left join public.customers c on c.id = i.customer_id
        where coalesce(i.is_active, true) = true
          and coalesce(i.invoice_type, 'sales') = 'sales'
          and coalesce(i.status, 'open') not in ('cancelled', 'draft')
          and i.invoice_date between $1::date and $2::date
          ${uid ? `and i.created_by = $3` : ''}
        group by coalesce(nullif(trim(c.name), ''), '—')
        order by amount desc
        limit 12
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(
            nullif(trim(p.name), ''),
            nullif(trim(ii.description), ''),
            'Kalem'
          ) as name,
          coalesce(sum(ii.quantity), 0)::float as qty,
          coalesce(sum(
            case
              when coalesce(ii.line_total, 0) <> 0 then ii.line_total
              else coalesce(ii.unit_price, 0) * coalesce(ii.quantity, 0)
            end
          ), 0)::float as amount,
          count(*)::int as count
        from public.invoice_items ii
        join public.invoices i on i.id = ii.invoice_id
        left join public.products p on p.id = ii.product_id
        where coalesce(i.is_active, true) = true
          and coalesce(i.invoice_type, 'sales') = 'sales'
          and coalesce(i.status, 'open') not in ('cancelled', 'draft')
          and i.invoice_date between $1::date and $2::date
          and ii.invoice_id is not null
          ${uid ? `and i.created_by = $3` : ''}
        group by 1
        order by amount desc
        limit 12
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(payment_method, ''), 'other') as key,
          count(*)::int as count,
          coalesce(sum(amount), 0)::float as amount
        from public.payments
        where coalesce(is_active, true) = true
          and paid_at::date between $1::date and $2::date
          ${createdBy}
        group by coalesce(nullif(payment_method, ''), 'other')
        order by amount desc
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(c.name), ''), '—') as name,
          count(*)::int as count,
          coalesce(sum(p.amount), 0)::float as amount
        from public.payments p
        left join public.customers c on c.id = p.customer_id
        where coalesce(p.is_active, true) = true
          and p.paid_at::date between $1::date and $2::date
          ${uid ? `and p.created_by = $3` : ''}
        group by coalesce(nullif(trim(c.name), ''), '—')
        order by amount desc
        limit 12
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(status, 'draft') as key,
          count(*)::int as count,
          coalesce(sum(grand_total), 0)::float as amount
        from public.quotes
        where coalesce(is_active, true) = true
          and quote_date between $1::date and $2::date
          ${createdBy}
        group by coalesce(status, 'draft')
        order by amount desc
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(c.name), ''), '—') as name,
          count(*)::int as count,
          coalesce(sum(q.grand_total), 0)::float as amount
        from public.quotes q
        left join public.customers c on c.id = q.customer_id
        where coalesce(q.is_active, true) = true
          and q.quote_date between $1::date and $2::date
          ${uid ? `and q.created_by = $3` : ''}
        group by coalesce(nullif(trim(c.name), ''), '—')
        order by amount desc
        limit 10
      `,
      rangeUser,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(city), ''), 'Belirtilmemiş') as name,
          count(*)::int as count
        from public.customers
        where coalesce(is_active, true) = true
        group by coalesce(nullif(trim(city), ''), 'Belirtilmemiş')
        order by count desc
        limit 12
      `,
    ),
    rows(
      `
        select
          coalesce(status, 'open') as key,
          count(*)::int as count
        from public.work_orders
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${woUser}
        group by coalesce(status, 'open')
      `,
      woParams,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(u.full_name), ''), 'Atanmamış') as name,
          count(*)::int as count,
          count(*) filter (where w.status = 'open')::int as open,
          count(*) filter (where w.status = 'in_progress')::int as in_progress,
          count(*) filter (where w.status = 'done')::int as done
        from public.work_orders w
        left join public.users u on u.id = w.assigned_to
        where coalesce(w.is_active, true) = true
          and w.created_at::date between $1::date and $2::date
          ${woUser}
        group by coalesce(nullif(trim(u.full_name), ''), 'Atanmamış')
        order by count desc
        limit 16
      `,
      woParams,
    ),
    rows(
      `
        select
          coalesce(status, 'waiting') as key,
          count(*)::int as count,
          coalesce(sum(coalesce(total_amount, 0)), 0)::float as amount
        from public.service_records
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${svcUser}
        group by coalesce(status, 'waiting')
        order by count desc
      `,
      svcParams,
    ),
    rows(
      `
        select
          coalesce(nullif(priority, ''), 'normal') as key,
          count(*)::int as count
        from public.service_records
        where coalesce(is_active, true) = true
          and created_at::date between $1::date and $2::date
          ${svcUser}
        group by coalesce(nullif(priority, ''), 'normal')
      `,
      svcParams,
    ),
    rows(
      `
        select
          coalesce(nullif(trim(brand_name), ''), 'Belirtilmemiş') as name,
          count(*)::int as count
        from public.application_forms
        where created_at::date between $1::date and $2::date
        group by coalesce(nullif(trim(brand_name), ''), 'Belirtilmemiş')
        order by count desc
        limit 10
      `,
      rangeParams,
    ),
    rows(
      `
        select
          coalesce(approval_status, 'pending') as key,
          count(*)::int as count
        from public.application_forms
        where created_at::date between $1::date and $2::date
        group by coalesce(approval_status, 'pending')
      `,
      rangeParams,
    ),
    rows(
      `
        select
          name,
          account_type as type,
          currency,
          coalesce(current_balance, 0)::float as amount
        from public.finance_accounts
        where coalesce(is_active, true) = true
        order by name
        limit 40
      `,
    ),
    rows(
      `
        select
          coalesce(transaction_type, direction) as key,
          count(*)::int as count,
          coalesce(sum(amount), 0)::float as amount
        from public.finance_transactions
        where coalesce(is_active, true) = true
          and transaction_date between $1::date and $2::date
          ${createdBy}
        group by coalesce(transaction_type, direction)
        order by amount desc
      `,
      rangeUser,
    ),
    rows(
      `
        select
          u.id,
          coalesce(nullif(trim(u.full_name), ''), 'Personel') as name,
          u.role,
          (
            select count(*)::int
            from public.work_orders w
            where coalesce(w.is_active, true) = true
              and w.assigned_to = u.id
              and w.created_at::date between $1::date and $2::date
          ) as work_orders,
          (
            select count(*)::int
            from public.work_orders w
            where coalesce(w.is_active, true) = true
              and w.assigned_to = u.id
              and w.status = 'done'
              and w.created_at::date between $1::date and $2::date
          ) as work_orders_done,
          (
            select coalesce(sum(p.amount), 0)::float
            from public.payments p
            where coalesce(p.is_active, true) = true
              and p.created_by = u.id
              and p.paid_at::date between $1::date and $2::date
          ) as payments,
          (
            select count(*)::int
            from public.invoices i
            where coalesce(i.is_active, true) = true
              and i.created_by = u.id
              and i.invoice_date between $1::date and $2::date
          ) as invoices,
          (
            select count(*)::int
            from public.quotes q
            where coalesce(q.is_active, true) = true
              and q.created_by = u.id
              and q.quote_date between $1::date and $2::date
          ) as quotes,
          (
            select count(*)::int
            from public.service_records s
            where coalesce(s.is_active, true) = true
              and coalesce(s.technician_id, s.created_by) = u.id
              and s.created_at::date between $1::date and $2::date
          ) as services
        from public.users u
        where coalesce(u.role, '') not in ('bank', 'bank_admin')
        order by u.full_name asc nulls last
      `,
      rangeParams,
    ),
    rows(
      `
        select
          name,
          coalesce(current_stock, 0)::float as qty,
          coalesce(min_stock, 0)::float as amount
        from public.stock_levels
        where current_stock <= min_stock
        order by (min_stock - current_stock) desc
        limit 12
      `,
    ),
    first(
      `
        select
          (
            select count(*)::int
            from public.licenses
            where is_active = true
              and expires_at is not null
              and expires_at between current_date and current_date + 30
          ) as licenses,
          (
            select count(*)::int
            from public.lines
            where is_active = true
              and expires_at is not null
              and expires_at between current_date and current_date + 30
          ) as lines
      `,
    ),
  ]);

  const quoteCount = toNumber(quoteKpi.count);
  const conversionRate =
    quoteCount > 0 ? (toNumber(quoteKpi.won_count) / quoteCount) * 100 : 0;

  return {
    range: {
      from: fromDate,
      to: toDate,
      prevFrom,
      prevTo,
      days,
    },
    kpis: {
      salesAmount: toNumber(salesKpi.amount),
      prevSalesAmount: toNumber(prevSalesKpi.amount),
      salesCount: toNumber(salesKpi.count),
      salesVat: toNumber(salesKpi.vat),
      salesPaid: toNumber(salesKpi.paid),
      purchaseAmount: toNumber(purchaseKpi.amount),
      purchaseCount: toNumber(purchaseKpi.count),
      purchaseVat: toNumber(purchaseKpi.vat),
      collectionsAmount: toNumber(collectionsKpi.amount),
      prevCollectionsAmount: toNumber(prevCollectionsKpi.amount),
      collectionsCount: toNumber(collectionsKpi.count),
      paymentsAmount: toNumber(paymentKpi.amount),
      prevPaymentsAmount: toNumber(prevPaymentKpi.amount),
      paymentsCount: toNumber(paymentKpi.count),
      receivableAmount: toNumber(receivableKpi.amount),
      receivableCount: toNumber(receivableKpi.count),
      payableAmount: toNumber(payableKpi.amount),
      payableCount: toNumber(payableKpi.count),
      quoteAmount: toNumber(quoteKpi.amount),
      prevQuoteAmount: toNumber(prevQuoteKpi.amount),
      quoteCount,
      quoteWonCount: toNumber(quoteKpi.won_count),
      quoteWonAmount: toNumber(quoteKpi.won_amount),
      quoteLostCount: toNumber(quoteKpi.lost_count),
      quoteConvertedCount: toNumber(quoteKpi.converted_count),
      quoteConversionRate: conversionRate,
      customersActive: toNumber(customerKpi.active),
      customersTotal: toNumber(customerKpi.total),
      customersNew: toNumber(customerKpi.new_count),
      workOrdersCreated: toNumber(workOrderKpi.created),
      prevWorkOrdersCreated: toNumber(prevWorkOrderKpi.created),
      workOrdersOpen: toNumber(workOrderKpi.open),
      workOrdersInProgress: toNumber(workOrderKpi.in_progress),
      workOrdersDone: toNumber(workOrderKpi.done),
      serviceCount: toNumber(serviceKpi.count),
      serviceAmount: toNumber(serviceKpi.amount),
      products: toNumber(stockKpi.products),
      lowStock: toNumber(stockKpi.low_stock),
      linesAvailable: toNumber(lineStockKpi.available),
      linesConsumed: toNumber(lineStockKpi.consumed),
      licensesExpiring: toNumber(licensesExpiring.licenses),
      linesExpiring: toNumber(licensesExpiring.lines),
      posCollected: toNumber(posKpi.collected),
      posPending: toNumber(posKpi.pending),
      posPendingCount: toNumber(posKpi.pending_count),
      posCount: toNumber(posKpi.count),
      recurringPlans: toNumber(recurringKpi.active_plans),
      recurringMonthly: toNumber(recurringKpi.monthly_amount),
      recurringRuns: toNumber(recurringKpi.runs),
      financeIn: toNumber(financeKpi.inflow),
      financeOut: toNumber(financeKpi.outflow),
      financeCount: toNumber(financeKpi.count),
      applications: toNumber(formKpi.applications),
      scraps: toNumber(formKpi.scraps),
      faults: toNumber(formKpi.faults),
      transfers: toNumber(formKpi.transfers),
      mutakabat: toNumber(mutakabatKpi.count),
    },
    series: {
      sales: dailySales.map((row) => ({
        day: String(row.day),
        value: toNumber(row.value),
      })),
      collections: dailyCollections.map((row) => ({
        day: String(row.day),
        value: toNumber(row.value),
      })),
      payments: dailyPayments.map((row) => ({
        day: String(row.day),
        value: toNumber(row.value),
      })),
    },
    invoices: {
      byStatus: mapCountAmount(invoiceByStatus),
      byType: invoiceByType.map((row) => ({
        key: String(row.key),
        count: toNumber(row.count),
        amount: toNumber(row.amount),
        vat: toNumber(row.vat),
      })),
      byEStatus: mapCountAmount(invoiceByEStatus),
      topCustomers: mapNamed(invoiceTopCustomers),
      topProducts: mapNamed(invoiceTopProducts),
    },
    payments: {
      byMethod: mapCountAmount(paymentByMethod),
      topCustomers: mapNamed(paymentTopCustomers),
    },
    quotes: {
      byStatus: mapCountAmount(quoteByStatus),
      topCustomers: mapNamed(quoteTopCustomers),
    },
    customers: {
      byCity: mapNamed(customersByCity),
    },
    workOrders: {
      byStatus: mapCountAmount(workOrderByStatus),
      byUser: workOrderByUser.map((row) => ({
        name: String(row.name || '—'),
        count: toNumber(row.count),
        open: toNumber(row.open),
        inProgress: toNumber(row.in_progress),
        done: toNumber(row.done),
      })),
    },
    service: {
      byStatus: mapCountAmount(serviceByStatus),
      byPriority: mapCountAmount(serviceByPriority),
    },
    forms: {
      byBrand: mapNamed(applicationByBrand),
      byApproval: mapCountAmount(applicationByApproval),
    },
    finance: {
      accounts: (financeAccounts || []).map((row) => ({
        name: String(row.name || '—'),
        type: String(row.type || 'bank'),
        currency: String(row.currency || 'TRY'),
        amount: toNumber(row.amount),
      })),
      byType: mapCountAmount(financeByType),
    },
    stock: {
      lowStock: (lowStock || []).map((row) => ({
        name: String(row.name || '—'),
        qty: toNumber(row.qty),
        amount: toNumber(row.amount),
      })),
    },
    personnel: (personnelRows || []).map((row) => ({
      id: String(row.id || ''),
      name: String(row.name || 'Personel'),
      role: String(row.role || ''),
      workOrders: toNumber(row.work_orders),
      workOrdersDone: toNumber(row.work_orders_done),
      payments: toNumber(row.payments),
      invoices: toNumber(row.invoices),
      quotes: toNumber(row.quotes),
      services: toNumber(row.services),
    })),
  };
}

module.exports = {
  buildSystemReports,
};
