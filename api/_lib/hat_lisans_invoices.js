const { query } = require('./db');
const {
  ensureInvoiceItemsTable,
  ensureInvoicesBillingSourceColumn,
  ensureInvoicePricesIncludeVatColumn,
  ensureLicensesSoftwareCompanyColumn,
  ensureLicensesRegistryNumberColumn,
  ensureLinesOperatorColumn,
  ensureHatLisansBillingSettingsTable,
} = require('./schema');

const BILLING_SOURCE = 'hat_lisans';
const GPRS_NAME = 'Gprs Data';
const GMP3_NAME = 'Gmp3 Yazarkasa Entegrasyonu';
const IRESTO_NAME = 'iResto Yazarkasa Entegrasyonu';
const LINE_PAYMENT_TITLE = 'Yazar kasa İnternet hattı Yıllık kullanım';
const GMP3_PAYMENT_TITLE = 'Yazar Kasa Entegrasyon ödemesi';
const IRESTO_PAYMENT_TITLE = 'iResto Yazarkasa Entegrasyon ödemesi';

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

function normalizeInvoiceCurrency(value) {
  const raw = String(value || 'TRY').trim().toUpperCase();
  if (raw === 'USD' || raw === 'US$' || raw === '$') return 'USD';
  return 'TRY';
}

function parseTitle(value, fallback) {
  const text = String(value == null ? '' : value).trim();
  return text || fallback;
}

function mapSettings(row = {}) {
  return {
    lineProductId: row.line_product_id || null,
    gmp3ProductId: row.gmp3_product_id || null,
    irestoProductId: row.iresto_product_id || null,
    linePriceTry: Number(row.line_price_try) || 0,
    linePriceUsd: Number(row.line_price_usd) || 0,
    gmp3PriceTry: Number(row.gmp3_price_try) || 0,
    gmp3PriceUsd: Number(row.gmp3_price_usd) || 0,
    irestoPriceTry: Number(row.iresto_price_try) || 0,
    irestoPriceUsd: Number(row.iresto_price_usd) || 0,
    defaultCurrency: normalizeInvoiceCurrency(row.default_currency),
    linePaymentTitle: parseTitle(row.line_payment_title, LINE_PAYMENT_TITLE),
    gmp3PaymentTitle: parseTitle(row.gmp3_payment_title, GMP3_PAYMENT_TITLE),
    irestoPaymentTitle: parseTitle(row.iresto_payment_title, IRESTO_PAYMENT_TITLE),
  };
}

async function ensureHatLisansInvoiceSchema() {
  await ensureInvoiceItemsTable();
  await ensureInvoicePricesIncludeVatColumn();
  await ensureInvoicesBillingSourceColumn();
  await ensureHatLisansBillingSettingsTable();
  await ensureLinesOperatorColumn();
  await ensureLicensesSoftwareCompanyColumn();
  await ensureLicensesRegistryNumberColumn();
}

async function loadProductById(id) {
  const productId = String(id || '').trim();
  if (!productId) return null;
  const result = await query(
    `
      select id, name, sale_price, tax_rate, unit, currency, is_active
      from public.products
      where id = $1::uuid
      limit 1
    `,
    [productId],
  );
  return result.rows[0] || null;
}

async function findProductByName(name, aliases = []) {
  const wanted = [name, ...aliases].map(foldName).filter(Boolean);
  if (!wanted.length) return null;
  const rows = await query(
    `
      select id, name, sale_price, tax_rate, unit, currency, is_active
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
  return null;
}

async function loadBillingCatalog() {
  await ensureHatLisansInvoiceSchema();
  const settingsResult = await query(
    `select * from public.hat_lisans_billing_settings where id = 1 limit 1`,
  );
  const settings = mapSettings(settingsResult.rows[0] || {});
  let gprs = await loadProductById(settings.lineProductId);
  let gmp3 = await loadProductById(settings.gmp3ProductId);
  let iresto = await loadProductById(settings.irestoProductId);
  if (!gprs) {
    gprs = await findProductByName(GPRS_NAME, ['gprs data', 'gpras data']);
  }
  if (!gmp3) {
    gmp3 = await findProductByName(GMP3_NAME, ['gmp3 yazarkasa entegrasyonu']);
  }
  if (!iresto) {
    iresto = await findProductByName(IRESTO_NAME, [
      'iresto yazarkasa entegrasyonu',
    ]);
  }
  const hasPrices =
    settings.linePriceTry > 0 ||
    settings.linePriceUsd > 0 ||
    settings.gmp3PriceTry > 0 ||
    settings.gmp3PriceUsd > 0;
  return {
    configured: hasPrices,
    gprs,
    gmp3,
    iresto,
    settings: {
      ...settings,
      lineProductId: settings.lineProductId || gprs?.id || null,
      gmp3ProductId: settings.gmp3ProductId || gmp3?.id || null,
      irestoProductId: settings.irestoProductId || iresto?.id || null,
    },
  };
}

async function saveHatLisansBillingSettings(input = {}) {
  await ensureHatLisansInvoiceSchema();
  const current = await loadBillingCatalog();
  const lineId =
    String(input.lineProductId ?? current.settings.lineProductId ?? '').trim() ||
    null;
  const gmp3Id =
    String(input.gmp3ProductId ?? current.settings.gmp3ProductId ?? '').trim() ||
    null;
  const irestoId =
    String(input.irestoProductId ?? current.settings.irestoProductId ?? '').trim() ||
    null;
  if (lineId && !(await loadProductById(lineId))) {
    const error = new Error('Seçilen hat ürünü bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  if (gmp3Id && !(await loadProductById(gmp3Id))) {
    const error = new Error('Seçilen GMP3 ürünü bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  if (irestoId && !(await loadProductById(irestoId))) {
    const error = new Error('Seçilen iResto ürünü bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  const currency = normalizeInvoiceCurrency(
    input.defaultCurrency ?? input.currency ?? current.settings.defaultCurrency,
  );
  await query(
    `
      insert into public.hat_lisans_billing_settings (
        id,
        line_product_id,
        gmp3_product_id,
        iresto_product_id,
        line_price_try,
        line_price_usd,
        gmp3_price_try,
        gmp3_price_usd,
        iresto_price_try,
        iresto_price_usd,
        default_currency,
        line_payment_title,
        gmp3_payment_title,
        iresto_payment_title,
        updated_at
      )
      values (
        1, $1::uuid, $2::uuid, $3::uuid,
        $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, now()
      )
      on conflict (id) do update set
        line_product_id = excluded.line_product_id,
        gmp3_product_id = excluded.gmp3_product_id,
        iresto_product_id = excluded.iresto_product_id,
        line_price_try = excluded.line_price_try,
        line_price_usd = excluded.line_price_usd,
        gmp3_price_try = excluded.gmp3_price_try,
        gmp3_price_usd = excluded.gmp3_price_usd,
        iresto_price_try = excluded.iresto_price_try,
        iresto_price_usd = excluded.iresto_price_usd,
        default_currency = excluded.default_currency,
        line_payment_title = excluded.line_payment_title,
        gmp3_payment_title = excluded.gmp3_payment_title,
        iresto_payment_title = excluded.iresto_payment_title,
        updated_at = now()
    `,
    [
      lineId,
      gmp3Id,
      irestoId,
      parsePrice(input.linePriceTry, current.settings.linePriceTry),
      parsePrice(input.linePriceUsd, current.settings.linePriceUsd),
      parsePrice(input.gmp3PriceTry, current.settings.gmp3PriceTry),
      parsePrice(input.gmp3PriceUsd, current.settings.gmp3PriceUsd),
      parsePrice(input.irestoPriceTry, current.settings.irestoPriceTry),
      parsePrice(input.irestoPriceUsd, current.settings.irestoPriceUsd),
      currency,
      parseTitle(
        input.linePaymentTitle,
        current.settings.linePaymentTitle || LINE_PAYMENT_TITLE,
      ),
      parseTitle(
        input.gmp3PaymentTitle,
        current.settings.gmp3PaymentTitle || GMP3_PAYMENT_TITLE,
      ),
      parseTitle(
        input.irestoPaymentTitle,
        current.settings.irestoPaymentTitle || IRESTO_PAYMENT_TITLE,
      ),
    ],
  );
  return loadBillingCatalog();
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
  if (prices && typeof prices === 'object') {
    await saveHatLisansBillingSettings({
      lineProductId: prices.lineProductId,
      gmp3ProductId: prices.gmp3ProductId,
      irestoProductId: prices.irestoProductId,
      linePriceTry: prices.lineUnitPriceTry ?? prices.linePriceTry,
      linePriceUsd: prices.lineUnitPriceUsd ?? prices.linePriceUsd,
      gmp3PriceTry: prices.gmp3UnitPriceTry ?? prices.gmp3PriceTry,
      gmp3PriceUsd: prices.gmp3UnitPriceUsd ?? prices.gmp3PriceUsd,
      irestoPriceTry: prices.irestoUnitPriceTry ?? prices.irestoPriceTry,
      irestoPriceUsd: prices.irestoUnitPriceUsd ?? prices.irestoPriceUsd,
      defaultCurrency: prices.currency,
      linePaymentTitle: prices.linePaymentTitle,
      gmp3PaymentTitle: prices.gmp3PaymentTitle,
      irestoPaymentTitle: prices.irestoPaymentTitle,
    });
  }
  const catalog = await loadBillingCatalog();
  const settings = catalog.settings || {};
  const gprs = catalog.gprs;
  const gmp3 = catalog.gmp3;
  const irestoProduct = catalog.iresto || gmp3;
  const rows = await loadCustomerCounts(customerIds);
  const currency = normalizeInvoiceCurrency(
    prices?.currency || settings.defaultCurrency,
  );
  const taxRate = parsePrice(
    prices?.taxRate,
    Number(gprs?.tax_rate || gmp3?.tax_rate) || 20,
  );
  const linePrice = currency === 'USD'
    ? parsePrice(prices?.lineUnitPriceUsd ?? prices?.lineUnitPrice, settings.linePriceUsd)
    : parsePrice(prices?.lineUnitPriceTry ?? prices?.lineUnitPrice, settings.linePriceTry);
  const gmp3Price = currency === 'USD'
    ? parsePrice(prices?.gmp3UnitPriceUsd ?? prices?.gmp3UnitPrice, settings.gmp3PriceUsd)
    : parsePrice(prices?.gmp3UnitPriceTry ?? prices?.gmp3UnitPrice, settings.gmp3PriceTry);
  const irestoPrice = currency === 'USD'
    ? parsePrice(
        prices?.irestoUnitPriceUsd ?? prices?.irestoUnitPrice,
        settings.irestoPriceUsd || gmp3Price,
      )
    : parsePrice(
        prices?.irestoUnitPriceTry ?? prices?.irestoUnitPrice,
        settings.irestoPriceTry || gmp3Price,
      );
  if (linePrice <= 0 && gmp3Price <= 0 && irestoPrice <= 0) {
    const error = new Error(
      `Seçilen para biriminde (${currency === 'USD' ? 'USD' : 'TL'}) Hat ve GMP3 birim fiyatı girin.`,
    );
    error.statusCode = 400;
    throw error;
  }
  const lineName = parseTitle(
    prices?.linePaymentTitle ?? settings.linePaymentTitle,
    LINE_PAYMENT_TITLE,
  );
  const gmp3Name = parseTitle(
    prices?.gmp3PaymentTitle ?? settings.gmp3PaymentTitle,
    GMP3_PAYMENT_TITLE,
  );
  const irestoName = parseTitle(
    prices?.irestoPaymentTitle ?? settings.irestoPaymentTitle,
    IRESTO_PAYMENT_TITLE,
  );

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
    const currencyLabel = currency === 'USD' ? 'USD' : 'TL';
    if (linesTotal > 0) {
      if (linePrice <= 0) {
        skipped.push({
          customerId: row.customer_id,
          customerName: row.customer_name,
          reason: `Hat birim fiyatı (${currencyLabel}) girilmedi`,
        });
        continue;
      }
      items.push({
        productId: gprs?.id,
        description: lineName,
        unit: gprs?.unit || 'Adet',
        ...lineParts({
          quantity: linesTotal,
          unitPrice: linePrice,
          taxRate,
        }),
      });
    }
    if (gmp3Total > 0) {
      if (gmp3Price <= 0) {
        skipped.push({
          customerId: row.customer_id,
          customerName: row.customer_name,
          reason: `GMP3 birim fiyatı (${currencyLabel}) girilmedi`,
        });
        continue;
      }
      items.push({
        productId: gmp3?.id,
        description: gmp3Name,
        unit: gmp3?.unit || 'Adet',
        ...lineParts({
          quantity: gmp3Total,
          unitPrice: gmp3Price,
          taxRate,
        }),
      });
    }
    if (irestoTotal > 0) {
      if (irestoPrice <= 0) {
        skipped.push({
          customerId: row.customer_id,
          customerName: row.customer_name,
          reason: `iResto birim fiyatı (${currencyLabel}) girilmedi`,
        });
        continue;
      }
      items.push({
        productId: irestoProduct?.id,
        description: irestoName,
        unit: irestoProduct?.unit || 'Adet',
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

    try {
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
    } catch (error) {
      skipped.push({
        customerId: row.customer_id,
        customerName: row.customer_name,
        reason: error instanceof Error ? error.message : 'Fatura yazılamadı',
      });
    }
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
              ii.product_id,
              ii.description,
              ii.quantity,
              ii.unit,
              ii.unit_price,
              ii.tax_rate,
              ii.tax_amount,
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
  saveHatLisansBillingSettings,
  createHatLisansInvoices,
  listHatLisansInvoices,
};
