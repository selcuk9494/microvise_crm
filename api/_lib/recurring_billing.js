const { query } = require('./db');
const { ensureInvoiceItemsTable } = require('./schema');
const { sendInvoicePaymentLinkEmail } = require('./invoice_mail');
const {
  dueDayInMonth,
  isPlanDueOn,
  localToday,
  periodKeyForDate,
} = require('./pos_status');

let tablesReady = false;

const FX_FALLBACK = { USD: 49, EUR: 56.5, GBP: 66 };

function textOrEmpty(value) {
  return String(value ?? '').trim();
}

function round2(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round((n + Number.EPSILON) * 100) / 100;
}

function round4(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round((n + Number.EPSILON) * 10000) / 10000;
}

async function ensureRecurringBillingTables() {
  if (tablesReady) return;
  await query(`
    create table if not exists public.recurring_billing_plans (
      id uuid primary key default gen_random_uuid(),
      customer_id uuid not null references public.customers(id) on delete cascade,
      title text not null,
      description text,
      amount numeric(14,2) not null,
      tax_rate numeric(8,2) not null default 20,
      currency text not null default 'TRY',
      billing_day integer not null default 1,
      email text,
      is_active boolean not null default true,
      last_run_on date,
      last_invoice_id uuid,
      created_by uuid,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      constraint recurring_billing_plans_day_chk
        check (billing_day >= 1 and billing_day <= 31)
    )
  `);
  await query(`
    create index if not exists idx_recurring_billing_plans_active
    on public.recurring_billing_plans (is_active, billing_day)
  `);
  await query(`
    create table if not exists public.recurring_billing_runs (
      id uuid primary key default gen_random_uuid(),
      plan_id uuid not null references public.recurring_billing_plans(id) on delete cascade,
      period_key text not null,
      invoice_id uuid,
      payment_link_id uuid,
      emailed_to text,
      status text not null default 'created',
      error_message text,
      created_at timestamptz not null default now(),
      unique (plan_id, period_key)
    )
  `);
  await query(`
    create index if not exists idx_recurring_billing_runs_plan
    on public.recurring_billing_runs (plan_id, created_at desc)
  `);
  tablesReady = true;
}

async function exchangeRateFor(currency) {
  const code = String(currency || 'TRY').trim().toUpperCase();
  if (!code || code === 'TRY' || code === 'TL') return 1;
  try {
    const result = await query(
      `
        select rate_to_try
        from public.exchange_rates
        where currency = $1
        order by effective_date desc, created_at desc
        limit 1
      `,
      [code],
    );
    const rate = Number(result.rows[0]?.rate_to_try);
    if (Number.isFinite(rate) && rate > 0) return round4(rate);
  } catch (_) {
    // ignored
  }
  return round4(FX_FALLBACK[code] || 1);
}

async function listRecurringBillingPlans() {
  await ensureRecurringBillingTables();
  const today = localToday();
  const periodKey = periodKeyForDate(today);
  const result = await query(
    `
      select
        p.*,
        json_build_object(
          'name', c.name,
          'email', c.email
        ) as customers,
        i.invoice_number as last_invoice_number,
        r.status as current_period_status,
        r.invoice_id as current_period_invoice_id,
        r.emailed_to as current_period_emailed_to,
        r.error_message as current_period_error
      from public.recurring_billing_plans p
      left join public.customers c on c.id = p.customer_id
      left join public.invoices i on i.id = p.last_invoice_id
      left join public.recurring_billing_runs r
        on r.plan_id = p.id and r.period_key = $1
      order by p.is_active desc, c.name asc, p.title asc
    `,
    [periodKey],
  );
  return result.rows.map((row) => ({
    ...row,
    dueToday: isPlanDueOn(row, today),
    periodKey,
  }));
}

async function upsertRecurringBillingPlan(body, user) {
  await ensureRecurringBillingTables();
  const id = textOrEmpty(body.id);
  const customerId = textOrEmpty(body.customerId || body.customer_id);
  const title = textOrEmpty(body.title);
  const description = textOrEmpty(body.description) || title;
  const amount = round2(body.amount);
  const taxRate = Number.isFinite(Number(body.taxRate ?? body.tax_rate))
    ? Number(body.taxRate ?? body.tax_rate)
    : 20;
  const currency = textOrEmpty(body.currency).toUpperCase() || 'TRY';
  const billingDay = Math.min(
    31,
    Math.max(1, Math.trunc(Number(body.billingDay ?? body.billing_day) || 1)),
  );
  const email = textOrEmpty(body.email) || null;
  const isActive =
    body.isActive !== false &&
    body.is_active !== false &&
    body.isActive !== 'false' &&
    body.is_active !== 'false';

  if (!customerId) {
    const error = new Error('Cari seçilmelidir.');
    error.statusCode = 400;
    throw error;
  }
  if (!title) {
    const error = new Error('Plan adı zorunludur.');
    error.statusCode = 400;
    throw error;
  }
  if (!(amount > 0)) {
    const error = new Error('Tutar sıfırdan büyük olmalıdır.');
    error.statusCode = 400;
    throw error;
  }

  if (id) {
    const updated = await query(
      `
        update public.recurring_billing_plans
        set customer_id = $2::uuid,
            title = $3,
            description = $4,
            amount = $5,
            tax_rate = $6,
            currency = $7,
            billing_day = $8,
            email = $9,
            is_active = $10,
            updated_at = now()
        where id = $1::uuid
        returning *
      `,
      [
        id,
        customerId,
        title,
        description,
        amount,
        taxRate,
        currency,
        billingDay,
        email,
        isActive,
      ],
    );
    if (!updated.rows[0]) {
      const error = new Error('Plan bulunamadı.');
      error.statusCode = 400;
      throw error;
    }
    return updated.rows[0];
  }

  const inserted = await query(
    `
      insert into public.recurring_billing_plans (
        customer_id,
        title,
        description,
        amount,
        tax_rate,
        currency,
        billing_day,
        email,
        is_active,
        created_by
      ) values (
        $1::uuid, $2, $3, $4, $5, $6, $7, $8, $9, $10
      )
      returning *
    `,
    [
      customerId,
      title,
      description,
      amount,
      taxRate,
      currency,
      billingDay,
      email,
      isActive,
      user?.id || null,
    ],
  );
  return inserted.rows[0];
}

async function setRecurringBillingPlanActive({ id, isActive }) {
  await ensureRecurringBillingTables();
  const planId = textOrEmpty(id);
  if (!planId) {
    const error = new Error('Plan id zorunludur.');
    error.statusCode = 400;
    throw error;
  }
  const updated = await query(
    `
      update public.recurring_billing_plans
      set is_active = $2,
          updated_at = now()
      where id = $1::uuid
      returning id, is_active
    `,
    [planId, isActive !== false],
  );
  if (!updated.rows[0]) {
    const error = new Error('Plan bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  return updated.rows[0];
}

async function createInvoiceForPlan(plan) {
  await ensureInvoiceItemsTable();
  const unitPrice = round2(plan.amount);
  const taxRate = Number(plan.tax_rate);
  const safeTaxRate = Number.isFinite(taxRate) ? taxRate : 20;
  const taxAmount = round2(unitPrice * (safeTaxRate / 100));
  const lineTotal = round2(unitPrice + taxAmount);
  const currency = textOrEmpty(plan.currency).toUpperCase() || 'TRY';
  const exchangeRate = await exchangeRateFor(currency);
  const invoiceDate = new Date().toISOString().slice(0, 10);
  const numberResult = await query(
    `select public.generate_invoice_number('sales') as value`,
  );
  const invoiceNumber =
    textOrEmpty(numberResult.rows?.[0]?.value) || `STŞ-${Date.now()}`;
  const description =
    textOrEmpty(plan.description) || textOrEmpty(plan.title) || 'Tekrarlayan ödeme';

  const invoiceInsert = await query(
    `
      insert into public.invoices (
        invoice_number,
        invoice_type,
        customer_id,
        invoice_date,
        currency,
        exchange_rate,
        prices_include_vat,
        subtotal,
        tax_total,
        discount_total,
        grand_total,
        paid_amount,
        status,
        notes,
        is_active
      )
      values (
        $1, 'sales', $2::uuid, $3::date, $4, $5, false,
        $6, $7, 0, $8, 0, 'open', $9, true
      )
      returning id, invoice_number
    `,
    [
      invoiceNumber,
      plan.customer_id,
      invoiceDate,
      currency,
      exchangeRate,
      unitPrice,
      taxAmount,
      lineTotal,
      `Tekrarlayan ödeme: ${plan.title}`,
    ],
  );
  const invoice = invoiceInsert.rows?.[0];
  if (!invoice?.id) {
    const error = new Error('Satış faturası oluşturulamadı.');
    error.statusCode = 500;
    throw error;
  }

  await query(
    `
      insert into public.invoice_items (
        invoice_id,
        customer_id,
        item_type,
        source_table,
        source_id,
        source_event,
        source_label,
        description,
        quantity,
        unit,
        unit_price,
        tax_rate,
        tax_amount,
        discount_rate,
        discount_amount,
        line_total,
        sort_order,
        status,
        is_active
      )
      values (
        $1::uuid,
        $2::uuid,
        'recurring_billing',
        'recurring_billing_plans',
        $3::uuid,
        'recurring_run',
        $4,
        $5,
        1,
        'Adet',
        $6,
        $7,
        $8,
        0,
        0,
        $9,
        0,
        'invoiced',
        true
      )
    `,
    [
      invoice.id,
      plan.customer_id,
      plan.id,
      plan.title,
      description,
      unitPrice,
      safeTaxRate,
      taxAmount,
      lineTotal,
    ],
  );

  return invoice;
}

async function runOnePlan({ plan, force, createdBy, req }) {
  const today = localToday();
  const periodKey = periodKeyForDate(today);
  if (!force && !isPlanDueOn(plan, today)) {
    return {
      planId: plan.id,
      skipped: true,
      reason: 'not_due',
    };
  }

  const existing = await query(
    `
      select id, status, invoice_id, error_message
      from public.recurring_billing_runs
      where plan_id = $1::uuid and period_key = $2
      limit 1
    `,
    [plan.id, periodKey],
  );
  const prior = existing.rows[0];
  if (prior && prior.status === 'emailed' && !force) {
    return {
      planId: plan.id,
      skipped: true,
      reason: 'already_run',
      invoiceId: prior.invoice_id,
    };
  }

  let invoice;
  try {
    invoice = await createInvoiceForPlan(plan);
    const mail = await sendInvoicePaymentLinkEmail({
      invoiceIds: [invoice.id],
      email: plan.email,
      createdBy,
      req,
    });
    await query(
      `
        insert into public.recurring_billing_runs (
          plan_id, period_key, invoice_id, emailed_to, status
        ) values ($1::uuid, $2, $3::uuid, $4, 'emailed')
        on conflict (plan_id, period_key) do update
          set invoice_id = excluded.invoice_id,
              emailed_to = excluded.emailed_to,
              status = 'emailed',
              error_message = null
      `,
      [plan.id, periodKey, invoice.id, mail.emailedTo],
    );
    await query(
      `
        update public.recurring_billing_plans
        set last_run_on = $2::date,
            last_invoice_id = $3::uuid,
            updated_at = now()
        where id = $1::uuid
      `,
      [plan.id, today.toISOString().slice(0, 10), invoice.id],
    );
    return {
      planId: plan.id,
      ok: true,
      invoiceId: invoice.id,
      invoiceNumber: invoice.invoice_number,
      emailedTo: mail.emailedTo,
      paymentUrl: mail.paymentUrl,
    };
  } catch (error) {
    await query(
      `
        insert into public.recurring_billing_runs (
          plan_id, period_key, invoice_id, status, error_message
        ) values ($1::uuid, $2, $3, 'failed', $4)
        on conflict (plan_id, period_key) do update
          set invoice_id = coalesce(excluded.invoice_id, public.recurring_billing_runs.invoice_id),
              status = 'failed',
              error_message = excluded.error_message
      `,
      [
        plan.id,
        periodKey,
        invoice?.id || null,
        error?.message || String(error),
      ],
    );
    return {
      planId: plan.id,
      ok: false,
      error: error?.message || String(error),
    };
  }
}

async function runRecurringBilling({ planId, force, createdBy, req }) {
  await ensureRecurringBillingTables();
  const today = localToday();
  const values = [];
  let whereSql = 'where p.is_active = true';
  if (planId) {
    values.push(planId);
    whereSql = `where p.id = $${values.length}::uuid`;
  }
  const result = await query(
    `
      select p.*, c.email as customer_email
      from public.recurring_billing_plans p
      left join public.customers c on c.id = p.customer_id
      ${whereSql}
      order by c.name asc
    `,
    values,
  );
  const plans = result.rows;
  if (!plans.length) {
    const error = new Error(
      planId ? 'Plan bulunamadı.' : 'Aktif tekrarlayan ödeme planı yok.',
    );
    error.statusCode = 400;
    throw error;
  }

  const results = [];
  for (const plan of plans) {
    const due = isPlanDueOn(plan, today);
    if (!planId && !due && !force) {
      results.push({ planId: plan.id, skipped: true, reason: 'not_due' });
      continue;
    }
    results.push(
      await runOnePlan({
        plan,
        force: Boolean(force || planId),
        createdBy,
        req,
      }),
    );
  }

  const created = results.filter((row) => row.ok).length;
  const failed = results.filter((row) => row.ok === false).length;
  const skipped = results.filter((row) => row.skipped).length;
  return {
    ok: failed === 0,
    created,
    failed,
    skipped,
    results,
    message:
      created || failed
        ? `${created} fatura kesilip mail gönderildi${
            failed ? `, ${failed} hata` : ''
          }.`
        : skipped
          ? 'Bugün kesilecek plan yok veya bu dönem zaten işlendi.'
          : 'İşlenecek plan yok.',
  };
}

module.exports = {
  ensureRecurringBillingTables,
  listRecurringBillingPlans,
  upsertRecurringBillingPlan,
  setRecurringBillingPlanActive,
  runRecurringBilling,
};
