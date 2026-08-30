const { query } = require('./db');
const {
  ensureInvoiceItemsTable,
  ensureInvoicesBillingSourceColumn,
  ensureInvoicePricesIncludeVatColumn,
  ensureLicensesSoftwareCompanyColumn,
  ensureLicensesRegistryNumberColumn,
  ensureLinesOperatorColumn,
} = require('./schema');

const BILLING_SOURCE = 'hat_lisans';
const GPRS_NAME = 'Gprs Data';
const GMP3_NAME = 'Gmp3 Yazarkasa Entegrasyonu';
const IRESTO_NAME = 'iResto Yazarkasa Entegrasyonu';

function round2(value) {
  return Math.round((Number(value) || 0) * 100) / 100;
}

function round4(value) {
  return Math.round((Number(value) || 0) * 10000) / 10000;
}

function foldName(value) {
  return String(value || '')
    .trim()
    .toLocaleLowerCase('tr-TR')
    .replaceAll('\u0307', '')
    .replaceAll('ı', 'i')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

function parsePrice(value, fallback = 0) {
  if (value == null || value === '') return fallback;
  const n = Number(String(value).replace(',', '.'));
  return Number.isFinite(n) && n >= 0 ? n : fallback;
}

async function ensureHatLisansInvoiceSchema() {
  await ensureInvoiceItemsTable();
  await ensureInvoicePricesIncludeVatColumn();
  await ensureInvoicesBillingSourceColumn();
  await ensureLinesOperatorColumn();
  await ensureLicensesSoftwareCompanyColumn();
  await ensureLicensesRegistryNumberColumn();
}

async function findOrCreateProduct({ name, aliases }) {
  const wanted = [name, ...(aliases || [])].map(foldName).filter(Boolean);
  const rows = await query(
    `
      select id, name, sale_price, tax_rate, unit, currency
      from public.products
      where coalesce(is_active, true) = true
      order by name asc
      limit 5000
    `,
  );
  for (const row of rows.rows) {
    const folded = foldName(row.name);
    if (wanted.includes(folded)) return row;
    const compact = folded.replace(/\s+/g, '');
    if (wanted.some((alias) => alias.replace(/\s+/g, '') === compact)) {
      return row;
    }
  }
  const inserted = await query(
    `
      insert into public.products (
        name, product_type, unit, sale_price, tax_rate, currency, is_active
      )
      values ($1, 'service', 'Adet', 0, 20, 'TRY', true)
      returning id, name, sale_price, tax_rate, unit, currency
    `,
    [name],
  );
  return inserted.rows[0];
}

async function loadBillingCatalog() {
  await ensureHatLisansInvoiceSchema();
  const gprs = await findOrCreateProduct({
    name: GPRS_NAME,
    aliases: ['gprs data', 'gpras data'],
  });
  const gmp3 = await findOrCreateProduct({
    name: GMP3_NAME,
    aliases: ['gmp3 yazarkasa entegrasyonu'],
  });
  return {
    gprs,
    gmp3,
    irestoName: IRESTO_NAME,
  };
}

async function loadCustomerCounts(customerIds) {
  const ids = Array.from(
    new Set((customerIds || []).map((id) => String(id || '').trim()).filter(Boolean)),
  );
  if (!ids.length) return [];
  const result = await query(
    `
      with line_counts as (
        select customer_id, count(*)::int as lines_total
        from public.lines
        where is_active = true
          and customer_id = any($1::uuid[])
        group by customer_id
      ),
      gmp3_counts as (
        select customer_id, count(*)::int as gmp3_total
        from public.licenses
        where is_active = true
          and lower(coalesce(license_type, '')) = 'gmp3'
          and customer_id = any($1::uuid[])
        group by customer_id
      ),
      iresto_counts as (
        select customer_id, count(*)::int as iresto_total
        from public.licenses
        where is_active = true
          and lower(coalesce(license_type, '')) = 'iresto'
          and customer_id = any($1::uuid[])
        group by customer_id
      )
      select
        c.id as customer_id,
        c.name as customer_name,
        coalesce(lc.lines_total, 0)::int as lines_total,
        coalesce(gc.gmp3_total, 0)::int as gmp3_total,
        coalesce(ic.iresto_total, 0)::int as iresto_total
      from public.customers c
      left join line_counts lc on lc.customer_id = c.id
      left join gmp3_counts gc on gc.customer_id = c.id
      left join iresto_counts ic on ic.customer_id = c.id
      where c.id = any($1::uuid[])
      order by c.name asc
    `,
    [ids],
  );
  return result.rows;
}

async function hasOpenHatLisansInvoice(customerId) {
  const existing = await query(
    `
      select id
      from public.invoices
      where customer_id = $1::uuid
        and coalesce(billing_source, '') = $2
        and coalesce(is_active, true) = true
        and status in ('draft', 'open', 'partial')
        and (coalesce(grand_total, 0) - coalesce(paid_amount, 0)) > 0.009
      limit 1
    `,
    [customerId, BILLING_SOURCE],
  );
  return Boolean(existing.rows[0]);
}

async function nextSalesInvoiceNumber() {
  try {
    const numberResult = await query(
      `select public.generate_invoice_number('sales') as value`,
    );
    const value = String(numberResult.rows?.[0]?.value || '').trim();
    if (value) return value;
  } catch (_) {}
  return `STŞ-${Date.now()}`;
}

function lineParts({ quantity, unitPrice, taxRate }) {
  const qty = Math.max(0, Number(quantity) || 0);
  const price = round4(unitPrice);
  const rate = Number.isFinite(Number(taxRate)) ? Number(taxRate) : 20;
  const subtotal = round2(qty * price);
  const taxAmount = round2(subtotal * (rate / 100));
  const lineTotal = round2(subtotal + taxAmount);
  return { qty, price, rate, subtotal, taxAmount, lineTotal };
}

async function insertInvoiceItem({
  invoiceId,
  customerId,
  productId,
  description,
  quantity,
  unit,
  unitPrice,
  taxRate,
  taxAmount,
  lineTotal,
  sortOrder,
}) {
  await query(
    `
      insert into public.invoice_items (
        invoice_id,
        product_id,
        customer_id,
        item_type,
        source_table,
        source_id,
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
        is_active
      )
      values (
        $1::uuid, $2::uuid, $3::uuid, 'hat_lisans_fee', 'invoices', $1::uuid, $4, $4,
        $5, $6, $7, $8, $9, 0, 0, $10, $11, true
      )
    `,
    [
      invoiceId,
      productId || null,
      customerId,
      description,
      quantity,
      unit || 'Adet',
      unitPrice,
      taxRate,
      taxAmount,
      lineTotal,
      sortOrder,
    ],
  );
}

async function createHatLisansInvoices({ customerIds, prices, user }) {
  await ensureHatLisansInvoiceSchema();
  const catalog = await loadBillingCatalog();
  const rows = await loadCustomerCounts(customerIds);
  const taxRate = parsePrice(prices?.taxRate, Number(catalog.gprs?.tax_rate) || 20);
  const linePrice = parsePrice(
    prices?.lineUnitPrice,
    Number(catalog.gprs?.sale_price) || 0,
  );
  const gmp3Price = parsePrice(
    prices?.gmp3UnitPrice,
    Number(catalog.gmp3?.sale_price) || 0,
  );
  const irestoPrice = parsePrice(prices?.irestoUnitPrice, gmp3Price);
  const currency = String(prices?.currency || catalog.gprs?.currency || 'TRY')
    .trim()
    .toUpperCase() || 'TRY';

  const created = [];
  const skipped = [];

  for (const row of rows) {
    const linesTotal = Number(row.lines_total) || 0;
    const gmp3Total = Number(row.gmp3_total) || 0;
    const irestoTotal = Number(row.iresto_total) || 0;
    if (linesTotal + gmp3Total + irestoTotal <= 0) {
      skipped.push({
        customerId: row.customer_id,
        customerName: row.customer_name,
        reason: 'Hat / GMP3 / iResto yok',
      });
      continue;
    }
    if (await hasOpenHatLisansInvoice(row.customer_id)) {
      skipped.push({
        customerId: row.customer_id,
        customerName: row.customer_name,
        reason: 'Ödenmemiş taslak zaten var',
      });
      continue;
    }

    const items = [];
    if (linesTotal > 0) {
      items.push({
        productId: catalog.gprs?.id,
        description: GPRS_NAME,
        unit: catalog.gprs?.unit || 'Adet',
        ...lineParts({
          quantity: linesTotal,
          unitPrice: linePrice,
          taxRate,
        }),
      });
    }
    if (gmp3Total > 0) {
      items.push({
        productId: catalog.gmp3?.id,
        description: GMP3_NAME,
        unit: catalog.gmp3?.unit || 'Adet',
        ...lineParts({
          quantity: gmp3Total,
          unitPrice: gmp3Price,
          taxRate,
        }),
      });
    }
    if (irestoTotal > 0) {
      items.push({
        productId: catalog.gmp3?.id,
        description: IRESTO_NAME,
        unit: catalog.gmp3?.unit || 'Adet',
        ...lineParts({
          quantity: irestoTotal,
          unitPrice: irestoPrice,
          taxRate,
        }),
      });
    }
    if (!items.length) continue;

    const subtotal = round2(items.reduce((sum, item) => sum + item.subtotal, 0));
    const taxTotal = round2(items.reduce((sum, item) => sum + item.taxAmount, 0));
    const grandTotal = round2(items.reduce((sum, item) => sum + item.lineTotal, 0));
    if (grandTotal <= 0.009) {
      skipped.push({
        customerId: row.customer_id,
        customerName: row.customer_name,
        reason: 'Birim fiyat girilmedi',
      });
      continue;
    }
    const invoiceNumber = await nextSalesInvoiceNumber();
    const invoiceDate = new Date().toISOString().slice(0, 10);

    const inserted = await query(
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
          billing_source,
          is_active,
          created_by
        )
        values (
          $1, 'sales', $2::uuid, $3::date, $4, 1, false,
          $5, $6, 0, $7, 0, 'draft', $8, $9, true, $10
        )
        returning id, invoice_number, status, grand_total
      `,
      [
        invoiceNumber,
        row.customer_id,
        invoiceDate,
        currency,
        subtotal,
        taxTotal,
        grandTotal,
        `Hat & Lisans tahsilatı · Hat ${linesTotal} · GMP3 ${gmp3Total} · iResto ${irestoTotal}`,
        BILLING_SOURCE,
        user?.id || null,
      ],
    );
    const invoice = inserted.rows[0];
    if (!invoice?.id) {
      skipped.push({
        customerId: row.customer_id,
        customerName: row.customer_name,
        reason: 'Fatura yazılamadı',
      });
      continue;
    }
    for (let i = 0; i < items.length; i += 1) {
      const item = items[i];
      await insertInvoiceItem({
        invoiceId: invoice.id,
        customerId: row.customer_id,
        productId: item.productId,
        description: item.description,
        quantity: item.qty,
        unit: item.unit,
        unitPrice: item.price,
        taxRate: item.rate,
        taxAmount: item.taxAmount,
        lineTotal: item.lineTotal,
        sortOrder: i,
      });
    }
    created.push({
      id: invoice.id,
      invoiceNumber: invoice.invoice_number,
      customerId: row.customer_id,
      customerName: row.customer_name,
      grandTotal,
      linesTotal,
      gmp3Total,
      irestoTotal,
    });
  }

  return { created, skipped, createdCount: created.length, skippedCount: skipped.length };
}

async function listHatLisansInvoices({ payment = '' } = {}) {
  await ensureHatLisansInvoiceSchema();
  const paymentFilter = String(payment || '').trim().toLowerCase();
  let extra = '';
  if (paymentFilter === 'pending') {
    extra = `and (coalesce(i.grand_total, 0) - coalesce(i.paid_amount, 0)) > 0.009
             and i.status in ('draft', 'open', 'partial')`;
  } else if (paymentFilter === 'paid') {
    extra = `and (
               i.status = 'paid'
               or (coalesce(i.grand_total, 0) - coalesce(i.paid_amount, 0)) <= 0.009
             )`;
  }

  const result = await query(
    `
      select
        i.*,
        c.name as customer_name,
        c.email as customer_email,
        json_build_object('name', c.name, 'email', c.email) as customers,
        pl.status as payment_link_status,
        pl.emailed_at as payment_link_emailed_at,
        pl.settled_at as payment_link_settled_at,
        coalesce((
          select json_agg(item order by item.sort_order)
          from (
            select
              ii.id,
              ii.invoice_id,
              ii.description,
              ii.quantity,
              ii.unit_price,
              ii.tax_rate,
              ii.line_total,
              ii.sort_order
            from public.invoice_items ii
            where ii.invoice_id = i.id
            order by ii.sort_order
          ) item
        ), '[]'::json) as invoice_items
      from public.invoices i
      left join public.customers c on c.id = i.customer_id
      left join lateral (
        select l.status, l.emailed_at, l.settled_at
        from public.invoice_payment_links l
        where i.id = any(l.invoice_ids)
        order by l.created_at desc
        limit 1
      ) pl on true
      where coalesce(i.billing_source, '') = $1
        and coalesce(i.is_active, true) = true
        ${extra}
      order by i.created_at desc
      limit 800
    `,
    [BILLING_SOURCE],
  );
  return result.rows;
}

module.exports = {
  BILLING_SOURCE,
  loadBillingCatalog,
  createHatLisansInvoices,
  listHatLisansInvoices,
};
