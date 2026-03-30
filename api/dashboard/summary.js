const { getAuthenticatedUser, hasPageAccess } = require('../_lib/auth');
const { query } = require('../_lib/db');
const { ok, forbidden, unauthorized, methodNotAllowed, serverError } = require('../_lib/http');

async function scalarNumber(sql, params = [], fallback = 0) {
  try {
    const result = await query(sql, params);
    const value = result.rows[0]?.value;
    if (typeof value === 'number') return value;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : fallback;
  } catch (_) {
    return fallback;
  }
}

async function listRows(sql, params = []) {
  try {
    const result = await query(sql, params);
    return Array.isArray(result.rows) ? result.rows : [];
  } catch (_) {
    return [];
  }
}

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'panel')) {
      return forbidden(res, 'Panele erişim yetkiniz yok.');
    }

    const totalCustomers = await scalarNumber(
      `select count(*)::int as value from public.customers where is_active = true`,
    );
    const openWorkOrders = await scalarNumber(
      `select count(*)::int as value from public.work_orders where is_active = true and status = 'open'`,
    );
    const inProgressWorkOrders = await scalarNumber(
      `select count(*)::int as value from public.work_orders where is_active = true and status = 'in_progress'`,
    );
    const completedWorkOrders = await scalarNumber(
      `select count(*)::int as value from public.work_orders where is_active = true and status = 'done'`,
    );
    const todayWorkOrders = await scalarNumber(
      `select count(*)::int as value
       from public.work_orders
       where is_active = true
         and scheduled_date is not null
         and scheduled_date::date = current_date`,
    );

    const expiringLicenses = await scalarNumber(
      `select count(*)::int as value
       from public.licenses
       where is_active = true
         and expires_at is not null
         and expires_at >= now()
         and expires_at <= now() + interval '30 days'`,
    );
    const expiringLines = await scalarNumber(
      `select count(*)::int as value
       from public.lines
       where is_active = true
         and expires_at is not null
         and expires_at >= now()
         and expires_at <= now() + interval '30 days'`,
    );

    const totalProducts = await scalarNumber(
      `select count(*)::int as value from public.products where is_active = true`,
    );
    const lowStockProducts = await scalarNumber(
      `select count(*)::int as value from public.stock_levels where current_stock <= min_stock`,
      [],
      0,
    );

    const revenue = await scalarNumber(
      `select coalesce(sum(amount), 0)::float as value
       from public.transactions
       where is_active = true and transaction_type = 'collection'`,
      [],
      0,
    );
    const lastMonthRevenue = await scalarNumber(
      `select coalesce(sum(amount), 0)::float as value
       from public.transactions
       where is_active = true
         and transaction_type = 'collection'
         and transaction_date >= (date_trunc('month', current_date) - interval '1 month')::date
         and transaction_date < (date_trunc('month', current_date))::date`,
      [],
      0,
    );
    const todayCollections = await scalarNumber(
      `select coalesce(sum(amount), 0)::float as value
       from public.transactions
       where is_active = true
         and transaction_type = 'collection'
         and transaction_date = current_date`,
      [],
      0,
    );

    const openInvoices = await scalarNumber(
      `select count(*)::int as value
       from public.invoices
       where is_active = true and status in ('open', 'partial')`,
    );
    const totalInvoiceAmount = await scalarNumber(
      `select coalesce(sum(grand_total - paid_amount), 0)::float as value
       from public.invoices
       where is_active = true and status in ('open', 'partial')`,
      [],
      0,
    );

    const balances = await listRows(`select balance from public.account_balances`);
    let totalReceivable = 0;
    let totalPayable = 0;
    for (const row of balances) {
      const raw = row.balance;
      const balance = typeof raw === 'number' ? raw : Number(raw);
      if (!Number.isFinite(balance)) continue;
      if (balance > 0) totalReceivable += balance;
      if (balance < 0) totalPayable += Math.abs(balance);
    }

    return ok(res, {
      total_customers: totalCustomers,
      open_work_orders: openWorkOrders,
      in_progress_work_orders: inProgressWorkOrders,
      completed_work_orders: completedWorkOrders,
      today_work_orders: todayWorkOrders,
      expiring_soon: expiringLicenses + expiringLines,
      total_products: totalProducts,
      low_stock_products: lowStockProducts,
      revenue,
      last_month_revenue: lastMonthRevenue,
      today_collections: todayCollections,
      total_receivable: totalReceivable,
      total_payable: totalPayable,
      open_invoices: openInvoices,
      total_invoice_amount: totalInvoiceAmount,
    });
  } catch (error) {
    return serverError(res, error);
  }
};
