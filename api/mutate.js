const crypto = require('crypto');

const {
  getAuthenticatedUser,
  hasPageAccess,
  isBankLikeUser,
  resolvePublicUserAuthId,
} = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  ensureSerialTrackingTable,
  ensureRegionColorsTable,
  ensureWorkOrderCloseNotesTable,
  ensureInvoiceItemsTable,
  ensureFaultFormsTable,
  ensureFormDocumentColumns,
  ensureDeviceRegistriesTable,
  ensureBusinessActivityTypesTable,
  ensureSoftwareCompaniesTable,
  ensureLicensesSoftwareCompanyColumn,
  ensureLicensesRegistryNumberColumn,
  ensureLinesOperatorColumn,
  ensureLineStockTable,
  ensureWorkOrderSignaturesTable,
  ensureServiceFaultTypesTable,
  ensureServiceAccessoryTypesTable,
  ensureServiceRecordsColumns,
  ensureServiceRecordsExtendedColumns,
  ensureServiceRecordsStatusCheckConstraint,
  ensureServiceActivityLogsTable,
  ensureFinanceTables,
  ensureApplicationFormsApprovalColumns,
  ensureApplicationFormActivityLogsTable,
  ensureInvoicePricesIncludeVatColumn,
} = require('./_lib/schema');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (!chunks.length) return {};
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) {
    return {};
  }
}

const serviceImageBucket = 'service-images';
const serviceImageMaxBytes = 5 * 1024 * 1024;
const approvalDocumentMaxBytes = 10 * 1024 * 1024;
const allowedServiceImageContentTypes = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
]);

function safeStorageSegment(value, fallback) {
  const cleaned = String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  return cleaned || fallback;
}

function serviceImageExtension(contentType, filename) {
  const ext = String(filename || '').toLowerCase().match(/\.([a-z0-9]+)$/)?.[1];
  if (['jpg', 'jpeg', 'png', 'webp', 'pdf'].includes(ext)) {
    return ext === 'jpeg' ? 'jpg' : ext;
  }
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/webp') return 'webp';
  if (contentType === 'application/pdf') return 'pdf';
  return 'jpg';
}

function storageFilenameStem(filename, fallback) {
  const withoutExt = String(filename || '')
    .trim()
    .replace(/\.[a-z0-9]+$/i, '');
  return safeStorageSegment(withoutExt, fallback);
}

function getSupabaseStorageConfig() {
  const supabaseUrl = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const serviceRoleKey = String(
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  ).trim();
  if (!supabaseUrl || !serviceRoleKey) {
    throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.');
  }
  return { supabaseUrl, serviceRoleKey };
}

function supabaseAdminHeaders(serviceRoleKey) {
  const headers = { apikey: serviceRoleKey };
  if (serviceRoleKey.startsWith('sb_')) {
    headers.authorization = serviceRoleKey;
  } else {
    headers.authorization = `Bearer ${serviceRoleKey}`;
  }
  return headers;
}

async function uploadStorageObject({
  folder,
  filename,
  contentType,
  data,
  maxBytes,
  emptyMessage,
  tooLargeMessage,
}) {
  const { supabaseUrl, serviceRoleKey } = getSupabaseStorageConfig();

  const base64 = String(data || '').replace(/^data:[^;]+;base64,/i, '').trim();
  if (!base64) {
    const error = new Error(emptyMessage);
    error.statusCode = 400;
    throw error;
  }

  const bytes = Buffer.from(base64, 'base64');
  if (!bytes.length) {
    const error = new Error(emptyMessage);
    error.statusCode = 400;
    throw error;
  }
  if (bytes.length > maxBytes) {
    const error = new Error(tooLargeMessage);
    error.statusCode = 400;
    throw error;
  }

  const ext = serviceImageExtension(contentType, filename);
  const random =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString('hex');
  const name = storageFilenameStem(filename, 'dosya');
  const objectPath = `${safeStorageSegment(folder, 'uploads')}/${name}-${Date.now()}-${random}.${ext}`;
  const uploadUrl = `${supabaseUrl}/storage/v1/object/${serviceImageBucket}/${encodeURIComponent(
    objectPath,
  ).replace(/%2F/g, '/')}`;

  let response;
  try {
    response = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        ...supabaseAdminHeaders(serviceRoleKey),
        'cache-control': '3600',
        'content-type': contentType,
        'x-upsert': 'false',
      },
      body: bytes,
    });
  } catch (error) {
    const cause = error?.cause;
    const host = (() => {
      try {
        return new URL(uploadUrl).hostname;
      } catch (_) {
        return 'invalid-url';
      }
    })();
    throw new Error(
      `Supabase Storage fetch failed: host=${host} code=${cause?.code || error?.code || 'unknown'} message=${cause?.message || error?.message || 'unknown'}`,
    );
  }

  if (!response.ok) {
    const text = await response.text().catch(() => '');
    throw new Error(`Supabase Storage upload failed: ${response.status} ${text}`);
  }

  return {
    bucket: serviceImageBucket,
    path: objectPath,
    url: `${supabaseUrl}/storage/v1/object/public/${serviceImageBucket}/${objectPath}`,
    contentType,
    size: bytes.length,
  };
}

async function deleteStorageObject(body) {
  const { supabaseUrl, serviceRoleKey } = getSupabaseStorageConfig();
  const bucket = safeStorageSegment(body.bucket, serviceImageBucket);
  const objectPath = String(body.path || '').trim();
  if (!objectPath) {
    const error = new Error('Silinecek dosya yolu eksik.');
    error.statusCode = 400;
    throw error;
  }
  const deleteUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${encodeURIComponent(
    objectPath,
  ).replace(/%2F/g, '/')}`;
  let response;
  try {
    response = await fetch(deleteUrl, {
      method: 'DELETE',
      headers: supabaseAdminHeaders(serviceRoleKey),
    });
  } catch (error) {
    const cause = error?.cause;
    throw new Error(
      `Supabase Storage delete failed: code=${cause?.code || error?.code || 'unknown'} message=${cause?.message || error?.message || 'unknown'}`,
    );
  }
  if (!response.ok && response.status !== 404) {
    const text = await response.text().catch(() => '');
    throw new Error(`Supabase Storage delete failed: ${response.status} ${text}`);
  }
  return { deleted: response.status !== 404 };
}

async function uploadServiceImage(body) {
  const filename = safeStorageSegment(body.filename, 'image');
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (!allowedServiceImageContentTypes.has(contentType)) {
    const error = new Error('Sadece JPG, PNG veya WEBP görsel yüklenebilir.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: safeStorageSegment(body.serviceId, 'service'),
    filename,
    contentType,
    data: body.data,
    maxBytes: serviceImageMaxBytes,
    emptyMessage: 'Görsel verisi eksik.',
    tooLargeMessage: 'Görsel 5 MB sınırını aşıyor.',
  });
}

async function uploadApplicationApprovalDocument(body) {
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (contentType !== 'application/pdf') {
    const error = new Error('Onay belgesi PDF olarak yüklenmelidir.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: `application-approval-documents/${safeStorageSegment(body.applicationFormId, 'form')}`,
    filename: safeStorageSegment(body.filename, 'onay-belgesi.pdf'),
    contentType,
    data: body.data,
    maxBytes: approvalDocumentMaxBytes,
    emptyMessage: 'PDF verisi eksik.',
    tooLargeMessage: 'PDF 10 MB sınırını aşıyor.',
  });
}

async function uploadTaxpayerRegistrationDocument(body) {
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(contentType)) {
    const error = new Error('Yükümlü belgesi PDF, JPG veya PNG olmalıdır.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: `taxpayer-registration-documents/${safeStorageSegment(body.applicationFormId, 'form')}`,
    filename: safeStorageSegment(body.filename, 'yukumlu-kayit-belgesi'),
    contentType,
    data: body.data,
    maxBytes: approvalDocumentMaxBytes,
    emptyMessage: 'Belge verisi eksik.',
    tooLargeMessage: 'Belge 10 MB sınırını aşıyor.',
  });
}

async function uploadFormDocument(body) {
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (!['application/pdf', 'image/jpeg', 'image/png'].includes(contentType)) {
    const error = new Error('Form belgesi PDF, JPG veya PNG olmalıdır.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: `form-documents/${safeStorageSegment(body.table, 'forms')}/${safeStorageSegment(body.recordId, 'record')}`,
    filename: safeStorageSegment(body.filename, 'form-belgesi'),
    contentType,
    data: body.data,
    maxBytes: approvalDocumentMaxBytes,
    emptyMessage: 'Belge verisi eksik.',
    tooLargeMessage: 'Belge 10 MB sınırını aşıyor.',
  });
}

async function materializeTaxpayerRegistrationDocument(values, formIdHint) {
  if (!values || typeof values !== 'object') return values;
  const data = String(values.taxpayer_registration_document_data || '').trim();
  const existingUrl = String(values.taxpayer_registration_document_url || '').trim();
  if (!data || existingUrl) return values;

  const next = { ...values };
  const formId =
    String(formIdHint || next.id || '').trim() ||
    (typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString('hex'));
  if (!next.id) next.id = formId;

  const uploaded = await uploadTaxpayerRegistrationDocument({
    applicationFormId: formId,
    filename: next.taxpayer_registration_document_name || 'yukumlu-kayit-belgesi',
    contentType:
      next.taxpayer_registration_document_mime_type || 'application/octet-stream',
    data,
  });

  next.taxpayer_registration_document_data = null;
  next.taxpayer_registration_document_storage_bucket = uploaded.bucket;
  next.taxpayer_registration_document_storage_path = uploaded.path;
  next.taxpayer_registration_document_url = uploaded.url;
  next.taxpayer_registration_document_uploaded_at =
    next.taxpayer_registration_document_uploaded_at || new Date().toISOString();
  return next;
}

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

const FX_FALLBACK = { USD: 49, EUR: 56.5, GBP: 66 };
let mutateHalkbankRatesCache = { fetchedAtMs: 0, rates: null };

function parseTrNumber(input) {
  const v = String(input || '').trim();
  if (!v) return null;
  const normalized = v.replace(/\./g, '').replace(',', '.');
  const n = Number.parseFloat(normalized);
  return Number.isFinite(n) ? n : null;
}

function parseHalkbankSelling(html, slug) {
  const idx = html.indexOf(`/halkbank/${slug}`);
  if (idx < 0) return null;
  const slice = html.substring(idx, Math.min(html.length, idx + 1000));
  const bold = [...slice.matchAll(/<td class="text-bold"[^>]*>([^<]+)<\/td>/g)].map(
    (m) => String(m[1] || '').trim(),
  );
  return parseTrNumber(bold[1]);
}

async function fetchHalkbankSellingRates() {
  const nowMs = Date.now();
  if (
    mutateHalkbankRatesCache.rates &&
    nowMs - mutateHalkbankRatesCache.fetchedAtMs < 60 * 1000
  ) {
    return mutateHalkbankRatesCache.rates;
  }
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), 9000);
    const response = await fetch('https://kur.doviz.com/halkbank', {
      signal: controller.signal,
      headers: { 'user-agent': 'microvise-crm/1.0' },
    });
    clearTimeout(timer);
    if (!response.ok) throw new Error(`halkbank http ${response.status}`);
    const html = await response.text();
    if (!html || html.length < 1000) throw new Error('halkbank empty');
    const rates = {
      USD: parseHalkbankSelling(html, 'amerikan-dolari') || FX_FALLBACK.USD,
      EUR: parseHalkbankSelling(html, 'euro') || FX_FALLBACK.EUR,
      GBP: parseHalkbankSelling(html, 'sterlin') || FX_FALLBACK.GBP,
    };
    mutateHalkbankRatesCache = { fetchedAtMs: nowMs, rates };
    return rates;
  } catch (_) {
    return { ...FX_FALLBACK };
  }
}

async function resolveProductForApplicationForm(form) {
  const productId = textOrEmpty(form.stock_product_id);
  if (productId) {
    const byId = await query(
      `
        select id, name, code, sale_price, tax_rate, currency, unit
        from public.products
        where id = $1::uuid
          and coalesce(is_active, true) = true
        limit 1
      `,
      [productId],
    );
    if (byId.rows?.[0]) return byId.rows[0];
  }

  const model = textOrEmpty(form.model_name);
  const brand = textOrEmpty(form.brand_name);
  const stockName = textOrEmpty(form.stock_product_name);
  if (!model && !brand && !stockName) return null;

  const result = await query(
    `
      select id, name, code, sale_price, tax_rate, currency, unit,
        (
          case
            when $1::text <> '' and lower(name) = lower($1) then 100
            when $1::text <> '' and name ilike $1 then 90
            when $1::text <> '' and name ilike '%' || $1 || '%' then 70
            else 0
          end
          + case
              when $2::text <> '' and $1::text <> ''
                and name ilike '%' || $2 || '%' || $1 || '%'
              then 40
              when $2::text <> '' and name ilike '%' || $2 || '%' then 15
              else 0
            end
          + case
              when $3::text <> '' and lower(name) = lower($3) then 50
              when $3::text <> '' and name ilike '%' || $3 || '%' then 25
              else 0
            end
        )::int as score
      from public.products
      where coalesce(is_active, true) = true
        and (
          ($1::text <> '' and name ilike '%' || $1 || '%')
          or ($2::text <> '' and name ilike '%' || $2 || '%')
          or ($3::text <> '' and name ilike '%' || $3 || '%')
        )
      order by score desc, sale_price desc nulls last, name asc
      limit 1
    `,
    [model, brand, stockName],
  );
  const row = result.rows?.[0];
  return row && row.score > 0 ? row : null;
}

async function setApplicationFormInvoiceNumber(formId, invoiceNumber) {
  const number = textOrEmpty(invoiceNumber);
  if (!number) return;
  await query(
    `
      update public.application_forms
      set invoice_number = $2
      where id = $1::uuid
        and (
          invoice_number is null
          or btrim(invoice_number) = ''
          or invoice_number = $2
        )
    `,
    [formId, number],
  );
}

async function markApplicationFormBillingQueueInvoiced(formId) {
  try {
    await query(
      `
        update public.invoice_items
        set
          status = 'invoiced',
          invoiced_at = coalesce(invoiced_at, now())
        where source_table = 'application_forms'
          and source_id = $1::uuid
          and invoice_id is null
          and coalesce(status, 'pending') = 'pending'
      `,
      [formId],
    );
  } catch (_) {
    // Eski şemada source/status kolonları yoksa sessiz geç.
  }
}

async function findExistingSalesInvoiceForForm(form, formId, customerId) {
  const explicitInvoice = textOrEmpty(form.invoice_number);
  if (explicitInvoice) {
    const byNumber = await query(
      `
        select i.id, i.invoice_number
        from public.invoices i
        where coalesce(i.invoice_type, 'sales') = 'sales'
          and coalesce(i.is_active, true) = true
          and coalesce(i.status, '') <> 'cancelled'
          and (
            i.invoice_number = $1
            or i.invoice_number ilike '%' || $1
            or regexp_replace(i.invoice_number, '^\\d{9}-', '') = $1
          )
          and (
            i.customer_id = $2::uuid
            or $2::text = ''
          )
        order by i.invoice_date desc nulls last
        limit 1
      `,
      [explicitInvoice, customerId],
    );
    if (byNumber.rows?.[0]) return byNumber.rows[0];
  }

  const byNotes = await query(
    `
      select i.id, i.invoice_number
      from public.invoices i
      where i.customer_id = $1::uuid
        and coalesce(i.invoice_type, 'sales') = 'sales'
        and coalesce(i.is_active, true) = true
        and coalesce(i.status, '') <> 'cancelled'
        and coalesce(i.notes, '') ilike '%' || $2 || '%'
      order by i.created_at desc nulls last
      limit 1
    `,
    [customerId, formId],
  );
  return byNotes.rows?.[0] || null;
}

async function ensureInvoiceLineNotes(invoiceId, registry) {
  const note = textOrEmpty(registry).toUpperCase();
  if (!note) {
    const anyLine = await query(
      `
        select id
        from public.invoice_items
        where invoice_id = $1::uuid
        order by coalesce(sort_order, 0), created_at nulls last
        limit 1
      `,
      [invoiceId],
    );
    return anyLine.rows?.[0]?.id || null;
  }

  const existing = await query(
    `
      select id
      from public.invoice_items
      where invoice_id = $1::uuid
        and upper(btrim(coalesce(notes, ''))) = $2
      order by coalesce(sort_order, 0), created_at nulls last
      limit 1
    `,
    [invoiceId, note],
  );
  if (existing.rows?.[0]?.id) return existing.rows[0].id;

  const empty = await query(
    `
      select id
      from public.invoice_items
      where invoice_id = $1::uuid
        and nullif(btrim(coalesce(notes, '')), '') is null
      order by coalesce(sort_order, 0), created_at nulls last
      limit 1
    `,
    [invoiceId],
  );
  const itemId = empty.rows?.[0]?.id;
  if (!itemId) return null;

  await query(
    `
      update public.invoice_items
      set notes = $2
      where id = $1::uuid
    `,
    [itemId, note],
  );
  return itemId;
}

async function createSalesInvoiceForApplicationForm(form, formId, customerId) {
  const product = await resolveProductForApplicationForm(form);
  const brand = textOrEmpty(form.brand_name);
  const model = textOrEmpty(form.model_name);
  const stockName = textOrEmpty(form.stock_product_name);
  const description =
    textOrEmpty(product?.name) ||
    [brand, model].filter(Boolean).join(' ').trim() ||
    stockName ||
    'ÖKC';
  const unit = textOrEmpty(product?.unit) || 'Adet';
  const taxRate = Number(product?.tax_rate);
  const safeTaxRate = Number.isFinite(taxRate) ? taxRate : 20;
  // Satış birim fiyatı KDV hariç; KDV ürün oranıyla ayrıca hesaplanır.
  const unitPrice = round4(Number(product?.sale_price) || 0);
  const taxAmount = round2(unitPrice * (safeTaxRate / 100));
  const lineTotal = round2(unitPrice + taxAmount);
  // Yalnızca yeni başvuru formu taslakları için varsayılan: KDV hariç + USD.
  // Mevcut / WOLVOX'tan gelen faturaları güncellemez; sync import ayrı yoldan gider.
  const currency = 'USD';
  const rates = await fetchHalkbankSellingRates();
  const exchangeRate = round4(rates.USD || FX_FALLBACK.USD || 1);

  const numberResult = await query(
    `select public.generate_invoice_number('sales') as value`,
  );
  const invoiceNumber =
    textOrEmpty(numberResult.rows?.[0]?.value) ||
    `STŞ-${Date.now()}`;

  const registry = textOrEmpty(form.stock_registry_number).toUpperCase();
  const invoiceDate =
    form.application_date || new Date().toISOString().slice(0, 10);

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
        status,
        notes,
        is_active
      )
      values (
        $1, 'sales', $2::uuid, $3::date, $4, $5, false, 'draft', null, true
      )
      returning id, invoice_number
    `,
    [invoiceNumber, customerId, invoiceDate, currency, exchangeRate],
  );
  const invoice = invoiceInsert.rows?.[0];
  if (!invoice?.id) {
    const err = new Error('Satış faturası oluşturulamadı.');
    err.statusCode = 500;
    throw err;
  }

  const itemInsert = await query(
    `
      insert into public.invoice_items (
        invoice_id,
        product_id,
        customer_id,
        item_type,
        source_table,
        source_id,
        source_event,
        source_label,
        description,
        notes,
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
        $3::uuid,
        'application_form',
        'application_forms',
        $4::uuid,
        'application_form_sales_invoice',
        'Başvuru Formu',
        $5,
        $6,
        1,
        $7,
        $8,
        $9,
        $10,
        0,
        0,
        $11,
        0,
        'invoiced',
        true
      )
      returning id
    `,
    [
      invoice.id,
      product?.id || null,
      customerId,
      formId,
      description,
      registry || null,
      unit,
      unitPrice,
      safeTaxRate,
      taxAmount,
      lineTotal,
    ],
  );

  await setApplicationFormInvoiceNumber(formId, invoice.invoice_number);
  await markApplicationFormBillingQueueInvoiced(formId);

  return {
    created: true,
    linked: true,
    registry: registry || null,
    invoiceId: invoice.id,
    invoiceNumber: invoice.invoice_number,
    invoiceItemId: itemInsert.rows?.[0]?.id || null,
    status: 'draft',
    currency,
    exchangeRate,
    unitPrice,
    taxRate: safeTaxRate,
    productId: product?.id || null,
    productName: description,
    reason: product ? null : 'product_not_found_zero_price',
  };
}

/**
 * Başvuru formu için satış e-faturası oluşturur / bağlar.
 * 1) Formda invoice_number veya form notu ile mevcut fatura varsa tekrar oluşturmaz
 * 2) Uygun açık kalem varsa sicili notes'a yazar
 * 3) Yoksa E-Fatura listesinde görünen taslak satış faturası + kalem oluşturur
 */
async function linkApplicationFormDeviceToInvoice(body) {
  await ensureInvoiceItemsTable();
  await ensureInvoicePricesIncludeVatColumn();

  const formId = textOrEmpty(body.applicationFormId || body.formId || body.id);
  if (!formId) {
    const err = new Error('applicationFormId zorunludur.');
    err.statusCode = 400;
    throw err;
  }

  const formResult = await query(
    `
      select
        id,
        customer_id,
        model_name,
        brand_name,
        stock_product_id,
        stock_product_name,
        stock_registry_number,
        invoice_number,
        application_date::date as application_date
      from public.application_forms
      where id = $1::uuid
      limit 1
    `,
    [formId],
  );
  const form = formResult.rows?.[0];
  if (!form) {
    const err = new Error('Başvuru formu bulunamadı.');
    err.statusCode = 400;
    throw err;
  }

  const registry = textOrEmpty(form.stock_registry_number).toUpperCase();
  const customerId = textOrEmpty(form.customer_id);
  if (!customerId) {
    return {
      created: false,
      linked: false,
      reason: 'missing_customer',
    };
  }

  // 1) Bu başvuruya zaten bağlı fatura varsa tekrar oluşturma.
  const existing = await findExistingSalesInvoiceForForm(
    form,
    formId,
    customerId,
  );
  if (existing?.id) {
    const itemId = await ensureInvoiceLineNotes(existing.id, registry);
    // Eski taslaklarda header notuna yazılmış başvuru id'sini temizle
    await query(
      `
        update public.invoices
        set notes = null
        where id = $1::uuid
          and status = 'draft'
          and notes ~* '^Başvuru formu:\\s*[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\\s*$'
      `,
      [existing.id],
    );
    await setApplicationFormInvoiceNumber(formId, existing.invoice_number);
    await markApplicationFormBillingQueueInvoiced(formId);
    return {
      created: false,
      linked: true,
      reason: 'already_linked',
      registry: registry || null,
      invoiceId: existing.id,
      invoiceNumber: existing.invoice_number,
      invoiceItemId: itemId,
    };
  }

  const model = textOrEmpty(form.model_name);
  const explicitInvoice = textOrEmpty(form.invoice_number);

  // 2) Müşteri + model / numara ile uygun mevcut kaleme bağlan.
  if (registry || model || explicitInvoice) {
    const match = await query(
      `
        with candidates as (
          select
            ii.id as item_id,
            i.id as invoice_id,
            i.invoice_number,
            i.invoice_date,
            (
              case
                when $4::text <> ''
                  and (
                    i.invoice_number = $4
                    or i.invoice_number ilike '%' || $4
                    or regexp_replace(i.invoice_number, '^\\d{9}-', '') = $4
                  )
                then 100
                else 0
              end
              + case
                  when $3::text <> ''
                    and (
                      ii.description ilike '%' || $3 || '%'
                      or coalesce(p.name, '') ilike '%' || $3 || '%'
                    )
                  then 50
                  else 0
                end
              + case
                  when $2::text = '' then 0
                  when nullif(btrim(coalesce(ii.notes, '')), '') is null then 10
                  when upper(btrim(ii.notes)) = $2 then 5
                  else -100
                end
              - least(
                  abs(
                    extract(
                      epoch from (
                        i.invoice_date::timestamp
                        - coalesce($5::date, current_date)::timestamp
                      )
                    ) / 86400.0
                  ),
                  45
                )::int
            )::int as score
          from public.invoices i
          join public.invoice_items ii
            on ii.invoice_id = i.id
          left join public.products p
            on p.id = ii.product_id
          where i.customer_id = $1::uuid
            and coalesce(i.invoice_type, 'sales') = 'sales'
            and coalesce(i.is_active, true) = true
            and coalesce(i.status, '') <> 'cancelled'
            and (
              (
                $4::text <> ''
                and (
                  i.invoice_number = $4
                  or i.invoice_number ilike '%' || $4
                  or regexp_replace(i.invoice_number, '^\\d{9}-', '') = $4
                )
              )
              or (
                $3::text <> ''
                and (
                  ii.description ilike '%' || $3 || '%'
                  or coalesce(p.name, '') ilike '%' || $3 || '%'
                )
                and i.invoice_date between
                  coalesce($5::date, current_date) - 45
                  and coalesce($5::date, current_date) + 45
              )
            )
            and (
              $2::text = ''
              or nullif(btrim(coalesce(ii.notes, '')), '') is null
              or upper(btrim(ii.notes)) = $2
            )
        )
        select item_id, invoice_id, invoice_number, score
        from candidates
        where score > 0
        order by score desc, invoice_date desc nulls last
        limit 1
      `,
      [
        customerId,
        registry,
        model,
        explicitInvoice,
        form.application_date || null,
      ],
    );

    const row = match.rows?.[0];
    if (row?.item_id) {
      if (registry) {
        await query(
          `
            update public.invoice_items
            set notes = $2
            where id = $1::uuid
          `,
          [row.item_id, registry],
        );
      }
      await setApplicationFormInvoiceNumber(formId, row.invoice_number);
      await markApplicationFormBillingQueueInvoiced(formId);
      return {
        created: false,
        linked: true,
        reason: 'matched_existing_line',
        registry: registry || null,
        invoiceId: row.invoice_id,
        invoiceNumber: row.invoice_number,
        invoiceItemId: row.item_id,
      };
    }
  }

  // 3) Uygun fatura yoksa E-Fatura taslağı oluştur.
  return createSalesInvoiceForApplicationForm(form, formId, customerId);
}

/**
 * Başvuru kaydı sonrası: müşteri varsa taslak satış e-faturası oluştur / bağla.
 * Form kaydını bozmamak için hata fırlatmaz; sonucu döner.
 */
async function maybeLinkApplicationFormInvoice(formId) {
  const id = textOrEmpty(formId);
  if (!id) return null;
  try {
    return await linkApplicationFormDeviceToInvoice({ applicationFormId: id });
  } catch (error) {
    return {
      created: false,
      linked: false,
      reason: 'error',
      error: error?.message || String(error),
    };
  }
}

/**
 * Satış faturası kaydından sonra: boş kalem açıklamalarına, aynı müşteriye ait
 * eşleşen başvuru formu cihaz sicillerini yazar.
 */
async function fillInvoiceDeviceNotesFromApplicationForms(body) {
  const invoiceId = textOrEmpty(body.invoiceId);
  if (!invoiceId) {
    const err = new Error('invoiceId zorunludur.');
    err.statusCode = 400;
    throw err;
  }

  const invoiceResult = await query(
    `
      select id, customer_id, invoice_number, invoice_date::date as invoice_date,
             coalesce(invoice_type, 'sales') as invoice_type
      from public.invoices
      where id = $1::uuid
      limit 1
    `,
    [invoiceId],
  );
  const invoice = invoiceResult.rows?.[0];
  if (!invoice) {
    const err = new Error('Fatura bulunamadı.');
    err.statusCode = 400;
    throw err;
  }
  if (invoice.invoice_type !== 'sales') {
    return { updated: 0, reason: 'not_sales' };
  }
  const customerId = textOrEmpty(invoice.customer_id);
  if (!customerId) {
    return { updated: 0, reason: 'missing_customer' };
  }

  const lines = await query(
    `
      select
        ii.id,
        ii.description,
        ii.notes,
        coalesce(p.name, '') as product_name
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      where ii.invoice_id = $1::uuid
        and nullif(btrim(coalesce(ii.notes, '')), '') is null
      order by coalesce(ii.sort_order, 0), ii.created_at nulls last
    `,
    [invoiceId],
  );

  const usedRegistries = new Set();
  let updated = 0;
  const links = [];

  for (const line of lines.rows || []) {
    const haystack = `${line.description || ''} ${line.product_name || ''}`
      .trim()
      .toLocaleLowerCase('tr-TR');
    if (!haystack) continue;

    const forms = await query(
      `
        select
          id,
          model_name,
          stock_registry_number,
          application_date::date as application_date
        from public.application_forms
        where customer_id = $1::uuid
          and coalesce(is_active, true) = true
          and nullif(btrim(coalesce(stock_registry_number, '')), '') is not null
          and application_date between
            coalesce($2::date, current_date) - 45
            and coalesce($2::date, current_date) + 45
        order by application_date desc nulls last, created_at desc nulls last
      `,
      [customerId, invoice.invoice_date || null],
    );

    let best = null;
    for (const form of forms.rows || []) {
      const registry = textOrEmpty(form.stock_registry_number).toUpperCase();
      if (!registry || usedRegistries.has(registry)) continue;
      const model = textOrEmpty(form.model_name).toLocaleLowerCase('tr-TR');
      if (!model || !haystack.includes(model)) continue;

      // Sicil başka bir fatura kaleminde kullanılıyorsa atla.
      const taken = await query(
        `
          select 1
          from public.invoice_items ii
          join public.invoices i on i.id = ii.invoice_id
          where upper(btrim(coalesce(ii.notes, ''))) = $1
            and ii.invoice_id is not null
            and coalesce(i.is_active, true) = true
            and coalesce(i.status, '') <> 'cancelled'
          limit 1
        `,
        [registry],
      );
      if (taken.rows?.length) continue;

      best = { form, registry };
      break;
    }

    if (!best) continue;

    await query(
      `
        update public.invoice_items
        set notes = $2
        where id = $1::uuid
          and nullif(btrim(coalesce(notes, '')), '') is null
      `,
      [line.id, best.registry],
    );
    usedRegistries.add(best.registry);

    const invoiceNumber = textOrEmpty(invoice.invoice_number);
    if (invoiceNumber) {
      await query(
        `
          update public.application_forms
          set invoice_number = $2
          where id = $1::uuid
            and (
              invoice_number is null
              or btrim(invoice_number) = ''
              or invoice_number = $2
            )
        `,
        [best.form.id, invoiceNumber],
      );
    }

    updated += 1;
    links.push({
      invoiceItemId: line.id,
      applicationFormId: best.form.id,
      registry: best.registry,
    });
  }

  return { updated, links, invoiceNumber: invoice.invoice_number };
}

const allowedTables = new Set([
  'application_forms',
  'branches',
  'cities',
  'customer_devices',
  'customer_locations',
  'customers',
  'device_brands',
  'device_models',
  'fiscal_symbols',
  'business_activity_types',
  'software_companies',
  'region_colors',
  'work_order_signatures',
  'invoices',
  'invoice_items',
  'licenses',
  'line_transfers',
  'lines',
  'line_stock',
  'payments',
  'products',
  'product_serial_inventory',
  'scrap_forms',
  'service_records',
  'service_activity_logs',
  'service_fault_types',
  'service_accessory_types',
  'serial_tracking',
  'stock_movements',
  'tax_rates',
  'transactions',
  'finance_accounts',
  'finance_transactions',
  'transfer_forms',
  'fault_forms',
  'device_registries',
  'users',
  'work_orders',
  'work_order_types',
  'work_order_close_notes',
]);

const tablePermissions = {
  customers: 'musteriler',
  customer_locations: 'musteriler',
  branches: ['musteriler', 'is_emirleri'],
  lines: ['urunler', 'is_emirleri', 'musteriler'],
  line_stock: ['urunler', 'is_emirleri'],
  licenses: ['urunler', 'is_emirleri', 'musteriler'],
  line_transfers: ['urunler', 'is_emirleri', 'musteriler'],
  products: ['urunler', 'e_fatura'],
  stock_movements: ['urunler', 'formlar', 'e_fatura'],
  product_serial_inventory: ['urunler', 'formlar'],
  serial_tracking: 'formlar',
  work_orders: 'is_emirleri',
  payments: ['is_emirleri', 'servis'],
  service_records: 'servis',
  service_activity_logs: 'servis',
  service_fault_types: 'tanimlamalar',
  service_accessory_types: 'tanimlamalar',
  customer_devices: 'servis',
  device_brands: 'tanimlamalar',
  device_models: 'tanimlamalar',
  work_order_types: 'tanimlamalar',
  work_order_close_notes: ['tanimlamalar', 'is_emirleri'],
  tax_rates: ['tanimlamalar', 'e_fatura', 'faturalama'],
  cities: 'tanimlamalar',
  fiscal_symbols: 'tanimlamalar',
  business_activity_types: 'tanimlamalar',
  software_companies: 'tanimlamalar',
  region_colors: 'tanimlamalar',
  work_order_signatures: 'is_emirleri',
  application_forms: 'formlar',
  scrap_forms: 'formlar',
  transfer_forms: 'formlar',
  fault_forms: 'formlar',
  device_registries: ['musteriler', 'formlar'],
  invoices: ['faturalama', 'e_fatura'],
  invoice_items: ['faturalama', 'e_fatura', 'urunler', 'formlar', 'is_emirleri'],
  transactions: ['faturalama', 'e_fatura'],
  finance_accounts: 'finans',
  finance_transactions: 'finans',
  users: 'personel',
};

const columnsCache = new Map();
const columnsMetaCache = new Map();

function requireAnyPage(req, user, pageKeys, res) {
  const keys = Array.isArray(pageKeys)
    ? pageKeys
    : [String(pageKeys || '').trim()].filter((k) => k.length > 0);
  if (!keys.length) return true;
  for (const key of keys) {
    if (hasPageAccess(user, key)) return true;
  }
  forbidden(req, res, 'Erişim yetkiniz yok.');
  return false;
}

async function getColumns(table) {
  if (columnsCache.has(table)) return columnsCache.get(table);
  const result = await query(
    `
      select column_name
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
      order by ordinal_position asc
    `,
    [table],
  );
  const columns = result.rows
    .map((r) => r.column_name)
    .filter((c) => typeof c === 'string' && c.length > 0);
  columnsCache.set(table, columns);
  return columns;
}

async function getColumnMeta(table) {
  if (columnsMetaCache.has(table)) return columnsMetaCache.get(table);
  const result = await query(
    `
      select column_name, data_type
      from information_schema.columns
      where table_schema = 'public'
        and table_name = $1
      order by ordinal_position asc
    `,
    [table],
  );
  const map = new Map();
  for (const row of result.rows) {
    const name = row.column_name;
    const type = row.data_type;
    if (typeof name === 'string' && name.length > 0) {
      map.set(name, String(type || '').toLowerCase());
    }
  }
  columnsMetaCache.set(table, map);
  return map;
}

function quoteIdent(name) {
  return `"${String(name).replace(/"/g, '""')}"`;
}

function pickValues(values, allowedColumns) {
  if (!values || typeof values !== 'object') return {};
  const out = {};
  for (const key of Object.keys(values)) {
    if (!allowedColumns.includes(key)) continue;
    const value = values[key];
    out[key] = value === undefined ? null : value;
  }
  return out;
}

async function sanitizeWorkOrderValues(values, user) {
  if (!values || typeof values !== 'object') return values;
  const next = { ...values };
  const actorUserId = user?.auth_user_id || user?.id || null;

  if (Object.prototype.hasOwnProperty.call(next, 'closed_by')) {
    const rawClosedBy = String(next.closed_by || '').trim();
    if (!rawClosedBy) {
      next.closed_by = actorUserId;
    } else {
      next.closed_by =
        (await resolvePublicUserAuthId(rawClosedBy)) ||
        (rawClosedBy === String(actorUserId || '') ? actorUserId : null);
    }
  }

  if (Object.prototype.hasOwnProperty.call(next, 'created_by')) {
    const rawCreatedBy = String(next.created_by || '').trim();
    if (!rawCreatedBy) {
      next.created_by = actorUserId;
    } else {
      next.created_by =
        (await resolvePublicUserAuthId(rawCreatedBy)) ||
        (rawCreatedBy === String(actorUserId || '') ? actorUserId : null);
    }
  }

  if (Object.prototype.hasOwnProperty.call(next, 'assigned_to')) {
    const rawAssignedTo = String(next.assigned_to || '').trim();
    next.assigned_to = rawAssignedTo
      ? await resolvePublicUserAuthId(rawAssignedTo)
      : null;
  }

  return next;
}

async function sanitizeValuesForTable({ table, values, user }) {
  if (table === 'customers' && isBankLikeUser(user)) {
    const next = {};
    const source = values || {};
    for (const key of ['name', 'vkn', 'address', 'director_name', 'city', 'email', 'phone_1', 'is_active']) {
      if (Object.prototype.hasOwnProperty.call(source, key)) {
        next[key] = source[key];
      }
    }
    next.is_active = true;
    if (source.vkn != null) {
      next.vkn = String(source.vkn || '').replace(/\D/g, '');
    }
    if (source.name != null) {
      next.name = String(source.name || '').trim();
    }
    if (source.address != null) {
      next.address = String(source.address || '').trim();
    }
    if (source.director_name != null) {
      next.director_name = String(source.director_name || '').trim();
    }
    if (source.city != null) {
      next.city = String(source.city || '').trim();
    }
    if (source.email != null) {
      next.email = String(source.email || '').trim();
    }
    if (source.phone_1 != null) {
      next.phone_1 = String(source.phone_1 || '').trim();
      next.phone_1_title = 'Telefon';
    }
    return next;
  }
  if (table === 'business_activity_types' && isBankLikeUser(user)) {
    const source = values || {};
    return {
      name: String(source.name || '').trim(),
      is_active: true,
    };
  }
  if (table === 'application_forms') {
    const next = { ...(values || {}) };
    if (!next.created_by) {
      next.created_by = user?.auth_user_id || user?.id || null;
    }
    return next;
  }
  if (table === 'work_orders') {
    return sanitizeWorkOrderValues(values, user);
  }
  return values;
}

async function upsertRow({ table, values, returningRow, user }) {
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const sanitizedValues = await sanitizeValuesForTable({ table, values, user });
  const picked = pickValues(sanitizedValues, columns);

  const hasIdColumn = columns.includes('id');
  const hasRegistryNormColumn =
    table === 'device_registries' && columns.includes('registry_number_norm');
  const hasLineNormColumn =
    table === 'line_stock' && columns.includes('line_number_norm');
  const hasSimNormColumn = table === 'line_stock' && columns.includes('sim_number_norm');
  if (
    table === 'device_registries' &&
    hasRegistryNormColumn &&
    picked.registry_number != null
  ) {
    picked.registry_number_norm = String(picked.registry_number || '')
      .trim()
      .toUpperCase();
  }
  if (table === 'line_stock' && hasLineNormColumn && picked.line_number != null) {
    picked.line_number_norm = String(picked.line_number || '').trim().toUpperCase();
  }
  if (table === 'line_stock' && hasSimNormColumn) {
    const sim = String(picked.sim_number || '').trim();
    picked.sim_number_norm = sim ? sim.toUpperCase() : null;
  }
  if (hasIdColumn) {
    if (!picked.id) {
      picked.id = crypto.randomUUID();
    }
  }

  const keys = Object.keys(picked);
  if (keys.length === 0) {
    throw new Error('values boş.');
  }

  const colSql = keys.map(quoteIdent).join(', ');
  const placeholders = keys
    .map((k, i) => {
      const t = meta.get(k);
      if (t === 'jsonb') return `$${i + 1}::jsonb`;
      if (t === 'json') return `$${i + 1}::json`;
      return `$${i + 1}`;
    })
    .join(', ');
  const insertValues = keys.map((k) => {
    const t = meta.get(k);
    const v = picked[k];
    if ((t === 'jsonb' || t === 'json') && v != null) {
      if (typeof v === 'string') return v;
      return JSON.stringify(v);
    }
    return v;
  });

  const updateKeys = keys.filter((k) => k !== 'id');
  const updateSql = updateKeys
    .map((k) => `${quoteIdent(k)} = excluded.${quoteIdent(k)}`)
    .join(', ');

  const conflict =
    table === 'device_registries' && hasRegistryNormColumn
      ? ' on conflict (registry_number_norm) do update set ' + updateSql
      : table === 'line_stock' && hasLineNormColumn
        ? ' on conflict (line_number_norm) do update set ' + updateSql
      : hasIdColumn
        ? ' on conflict (id) do update set ' + updateSql
        : '';
  const returning = hasIdColumn
    ? returningRow
      ? ' returning *'
      : ' returning id'
    : '';

  const sql = `
    insert into public.${quoteIdent(table)} (${colSql})
    values (${placeholders})
    ${conflict}
    ${returning}
  `;

  const result = await query(sql, insertValues);
  const row = result.rows[0] || null;
  return { id: row?.id ?? picked.id ?? null, row };
}

async function deleteRow({ table, id }) {
  await query(`delete from public.${quoteIdent(table)} where id = $1`, [id]);
}

async function updateWhere({ table, values, filters, user }) {
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const sanitizedValues = await sanitizeValuesForTable({ table, values, user });
  const picked = pickValues(sanitizedValues, columns);
  const keys = Object.keys(picked).filter((k) => k !== 'id');
  if (keys.length === 0) throw new Error('values boş.');

  const normalizedFilters = Array.isArray(filters) ? filters : [];
  if (normalizedFilters.length === 0) throw new Error('filters boş.');
  if (normalizedFilters.length > 5) throw new Error('filters çok fazla.');

  const whereParts = [];
  const params = [];

  for (const f of normalizedFilters) {
    if (!f || typeof f !== 'object') continue;
    const col = String(f.col || '').trim();
    const op = String(f.op || '').trim();
    const value = f.value;
    if (!col || !columns.includes(col)) throw new Error('Geçersiz filter col.');
    const colSql = quoteIdent(col);

    if (op === 'eq') {
      params.push(value);
      whereParts.push(`${colSql} = $${params.length}`);
      continue;
    }
    if (op === 'ilike') {
      params.push(String(value || ''));
      whereParts.push(`${colSql} ilike $${params.length}`);
      continue;
    }
    if (op === 'in') {
      const arr = Array.isArray(value) ? value : [];
      params.push(arr);
      whereParts.push(`${colSql} = any($${params.length})`);
      continue;
    }
    if (op === 'gte') {
      params.push(value);
      whereParts.push(`${colSql} >= $${params.length}`);
      continue;
    }
    if (op === 'lte') {
      params.push(value);
      whereParts.push(`${colSql} <= $${params.length}`);
      continue;
    }
    if (op === 'gt') {
      params.push(value);
      whereParts.push(`${colSql} > $${params.length}`);
      continue;
    }
    if (op === 'lt') {
      params.push(value);
      whereParts.push(`${colSql} < $${params.length}`);
      continue;
    }

    throw new Error('Geçersiz filter op.');
  }

  if (whereParts.length === 0) throw new Error('filters boş.');

  const setParts = [];
  for (const k of keys) {
    const t = meta.get(k);
    const v = picked[k];
    if ((t === 'jsonb' || t === 'json') && v != null) {
      params.push(typeof v === 'string' ? v : JSON.stringify(v));
      setParts.push(`${quoteIdent(k)} = $${params.length}::${t}`);
    } else {
      params.push(v);
      setParts.push(`${quoteIdent(k)} = $${params.length}`);
    }
  }

  const sql = `
    update public.${quoteIdent(table)}
    set ${setParts.join(', ')}
    where ${whereParts.join(' and ')}
  `;

  await query(sql, params);
}

async function deleteWhere({ table, filters }) {
  const columns = await getColumns(table);
  const normalizedFilters = Array.isArray(filters) ? filters : [];
  if (normalizedFilters.length === 0) throw new Error('filters boş.');
  if (normalizedFilters.length > 5) throw new Error('filters çok fazla.');

  const whereParts = [];
  const params = [];

  for (const f of normalizedFilters) {
    if (!f || typeof f !== 'object') continue;
    const col = String(f.col || '').trim();
    const op = String(f.op || '').trim();
    const value = f.value;
    if (!col || !columns.includes(col)) throw new Error('Geçersiz filter col.');
    const colSql = quoteIdent(col);

    if (op === 'eq') {
      params.push(value);
      whereParts.push(`${colSql} = $${params.length}`);
      continue;
    }
    if (op === 'in') {
      const arr = Array.isArray(value) ? value : [];
      params.push(arr);
      whereParts.push(`${colSql} = any($${params.length})`);
      continue;
    }
    throw new Error('Geçersiz filter op.');
  }

  if (whereParts.length === 0) throw new Error('filters boş.');
  await query(
    `delete from public.${quoteIdent(table)} where ${whereParts.join(' and ')}`,
    params,
  );
}

const applicationFormAuditLabels = {
  application_date: 'Başvuru tarihi',
  customer_id: 'Müşteri',
  customer_name: 'Ünvan',
  customer_tckn_ms: 'VKN/TCKN',
  work_address: 'İş yeri adresi',
  tax_office_city_id: 'Vergi dairesi id',
  tax_office_city_name: 'Vergi dairesi',
  document_type: 'Belge tipi',
  file_registry_number: 'Dosya no',
  director: 'Yetkili / Direktör',
  brand_id: 'Marka id',
  brand_name: 'Marka',
  model_id: 'Model id',
  model_name: 'Model',
  fiscal_symbol_id: 'Mali sembol id',
  fiscal_symbol_name: 'Mali sembol',
  stock_product_id: 'Ürün id',
  stock_product_name: 'Ürün',
  stock_registry_number: 'Sicil no',
  accounting_office: 'Muhasebe ofisi',
  okc_start_date: 'ÖKC başlama tarihi',
  business_activity_type_id: 'Faaliyet türü id',
  business_activity_name: 'Faaliyet türü',
  invoice_number: 'Fatura no',
  customer_phone: 'Telefon',
  customer_email: 'E-posta',
  taxpayer_registration_document_name: 'Yükümlü belgesi',
  taxpayer_registration_document_mime_type: 'Belge tipi',
  taxpayer_registration_document_data: 'Yükümlü belgesi içeriği',
  taxpayer_registration_document_storage_bucket: 'Yükümlü belge bucket',
  taxpayer_registration_document_storage_path: 'Yükümlü belge yolu',
  taxpayer_registration_document_url: 'Yükümlü belge URL',
  taxpayer_registration_document_uploaded_at: 'Belge yükleme tarihi',
  approval_document_name: 'Onay belgesi',
  approval_document_mime_type: 'Onay belge tipi',
  approval_document_storage_bucket: 'Onay belge bucket',
  approval_document_storage_path: 'Onay belge yolu',
  approval_document_url: 'Onay belge URL',
  approval_document_uploaded_at: 'Onay belge yükleme tarihi',
  approval_status: 'Onay durumu',
  approved_at: 'Onay tarihi',
  approved_by: 'Onaylayan',
  created_by: 'Kaydı giren',
  is_active: 'Aktiflik',
};

function normalizeAuditValue(key, value) {
  if (value == null) return null;
  if (
    key === 'taxpayer_registration_document_data' ||
    key === 'taxpayer_registration_document_url' ||
    key === 'approval_document_url'
  ) {
    return String(value || '').trim() ? '[belge var]' : null;
  }
  if (value instanceof Date) return value.toISOString();
  if (typeof value === 'object') return JSON.stringify(value);
  return String(value);
}

function buildApplicationFormChanges(before, after) {
  const keys = new Set([
    ...Object.keys(before || {}),
    ...Object.keys(after || {}),
  ]);
  const changes = [];
  for (const key of keys) {
    if (['id', 'created_at'].includes(key)) continue;
    const oldValue = normalizeAuditValue(key, before?.[key]);
    const newValue = normalizeAuditValue(key, after?.[key]);
    if (oldValue === newValue) continue;
    changes.push({
      field: key,
      label: applicationFormAuditLabels[key] || key,
      old: oldValue,
      new: newValue,
    });
  }
  return changes;
}

async function selectApplicationFormAuditRow(id) {
  const rowId = String(id || '').trim();
  if (!rowId) return null;
  const result = await query(
    `select * from public.application_forms where id = $1 limit 1`,
    [rowId],
  );
  return result.rows[0] || null;
}

async function insertApplicationFormLog({ formId, action, before, after, user }) {
  const changes = buildApplicationFormChanges(before, after);
  if (action === 'update' && changes.length === 0) return;
  await ensureApplicationFormActivityLogsTable();
  await query(
    `
      insert into public.application_form_activity_logs (
        application_form_id,
        action,
        actor_id,
        actor_name,
        changes,
        old_values,
        new_values
      )
      values ($1,$2,$3,$4,$5::jsonb,$6::jsonb,$7::jsonb)
    `,
    [
      formId,
      action,
      user?.auth_user_id || user?.id || null,
      user?.full_name || user?.email || null,
      JSON.stringify(changes),
      before ? JSON.stringify(before) : null,
      after ? JSON.stringify(after) : null,
    ],
  );
}

function applicationFormIdFilter(filters) {
  const idFilter = Array.isArray(filters)
    ? filters.find((f) => f?.col === 'id' && f?.op === 'eq')
    : null;
  return String(idFilter?.value || '').trim();
}

async function insertMany({ table, rows, user }) {
  if (!Array.isArray(rows) || rows.length === 0) return { inserted: 0 };
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const hasIdColumn = columns.includes('id');

  for (const row of rows) {
    const sanitizedRow = await sanitizeValuesForTable({
      table,
      values: row,
      user,
    });
    const values = pickValues(sanitizedRow, columns);
    if (hasIdColumn && !values.id) values.id = crypto.randomUUID();
    const keys = Object.keys(values);
    if (keys.length === 0) continue;
    const colSql = keys.map(quoteIdent).join(', ');
    const placeholders = keys
      .map((k, i) => {
        const t = meta.get(k);
        if (t === 'jsonb') return `$${i + 1}::jsonb`;
        if (t === 'json') return `$${i + 1}::json`;
        return `$${i + 1}`;
      })
      .join(', ');
    const insertValues = keys.map((k) => {
      const t = meta.get(k);
      const v = values[k];
      if ((t === 'jsonb' || t === 'json') && v != null) {
        if (typeof v === 'string') return v;
        return JSON.stringify(v);
      }
      return v;
    });
    await query(
      `
        insert into public.${quoteIdent(table)} (${colSql})
        values (${placeholders})
      `,
      insertValues,
    );
  }

  return { inserted: rows.length };
}

async function assertApplicationFormsMutable({ op, values, filters, id }) {
  if (op === 'upsert') {
    const rowId = String(values?.id || '').trim();
    if (!rowId) return;
    const current = await query(
      `select approval_status from public.application_forms where id = $1 limit 1`,
      [rowId],
    );
    if (current.rows[0]?.approval_status !== 'approved') return;
    throw new Error('Onaylanan başvuru düzenlenemez.');
  }

  if (op === 'delete') {
    const rowId = String(id || '').trim();
    if (!rowId) return;
    const current = await query(
      `select approval_status from public.application_forms where id = $1 limit 1`,
      [rowId],
    );
    if (current.rows[0]?.approval_status === 'approved') {
      throw new Error('Onaylanan başvuru silinemez.');
    }
    return;
  }

  if (op !== 'updateWhere') return;

  const nextStatus = String(values?.approval_status || '').trim();
  const onlyApprovalUpdate =
    nextStatus === 'approved' &&
    Object.keys(values || {}).every((key) =>
      ['approval_status', 'approved_at', 'approved_by', 'stock_registry_number'].includes(key),
    );
  const onlyApprovalReset =
    nextStatus === 'pending' &&
    Object.keys(values || {}).every((key) =>
      ['approval_status', 'approved_at', 'approved_by'].includes(key),
    );
  const onlyApprovalDocumentUpdate =
    Object.keys(values || {}).length > 0 &&
    Object.keys(values || {}).every((key) =>
      [
        'taxpayer_registration_document_name',
        'taxpayer_registration_document_mime_type',
        'taxpayer_registration_document_data',
        'taxpayer_registration_document_storage_bucket',
        'taxpayer_registration_document_storage_path',
        'taxpayer_registration_document_url',
        'taxpayer_registration_document_uploaded_at',
        'approval_document_name',
        'approval_document_mime_type',
        'approval_document_storage_bucket',
        'approval_document_storage_path',
        'approval_document_url',
        'approval_document_uploaded_at',
      ].includes(key),
    );
  if (onlyApprovalUpdate || onlyApprovalReset || onlyApprovalDocumentUpdate) return;

  const idFilter = Array.isArray(filters)
    ? filters.find((f) => f?.col === 'id' && f?.op === 'eq')
    : null;
  const rowId = String(idFilter?.value || '').trim();
  if (!rowId) return;
  const current = await query(
    `select approval_status from public.application_forms where id = $1 limit 1`,
    [rowId],
  );
  if (current.rows[0]?.approval_status === 'approved') {
    throw new Error('Onaylanan başvuru değiştirilemez.');
  }
}

module.exports = async (req, res) => {
  if (handleCors(req, res)) return;
  if (req.method !== 'POST') {
    return methodNotAllowed(req, res, 'POST');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);

    const body = await readJson(req);
    const op = String(body.op || '').trim();
    const table = String(body.table || '').trim();

    if (!op) return badRequest(req, res, 'op zorunludur.');
    if (op === 'uploadServiceImage') {
      if (!hasPageAccess(user, 'servis')) return forbidden(req, res);
      try {
        return ok(req, res, await uploadServiceImage(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'uploadApplicationApprovalDocument') {
      if (!hasPageAccess(user, 'formlar')) return forbidden(req, res);
      try {
        return ok(req, res, await uploadApplicationApprovalDocument(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'uploadTaxpayerRegistrationDocument') {
      if (!hasPageAccess(user, 'formlar')) return forbidden(req, res);
      try {
        return ok(req, res, await uploadTaxpayerRegistrationDocument(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (
      op === 'linkApplicationFormDeviceToInvoice' ||
      op === 'ensureApplicationFormSalesInvoice'
    ) {
      if (
        !hasPageAccess(user, 'formlar') &&
        !hasPageAccess(user, 'e_fatura') &&
        !hasPageAccess(user, 'faturalama')
      ) {
        return forbidden(req, res);
      }
      try {
        return ok(req, res, await linkApplicationFormDeviceToInvoice(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'fillInvoiceDeviceNotesFromApplicationForms') {
      if (
        !hasPageAccess(user, 'e_fatura') &&
        !hasPageAccess(user, 'formlar') &&
        !hasPageAccess(user, 'faturalama')
      ) {
        return forbidden(req, res);
      }
      try {
        return ok(
          req,
          res,
          await fillInvoiceDeviceNotesFromApplicationForms(body),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'uploadFormDocument') {
      const uploadTable = String(body.table || '').trim();
      if (!['scrap_forms', 'transfer_forms', 'fault_forms'].includes(uploadTable)) {
        return badRequest(req, res, 'Form tablosu desteklenmiyor.');
      }
      if (!hasPageAccess(user, 'formlar')) return forbidden(req, res);
      await ensureFormDocumentColumns();
      try {
        return ok(req, res, await uploadFormDocument(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'deleteStorageObject') {
      if (!hasPageAccess(user, 'formlar') && !hasPageAccess(user, 'servis')) {
        return forbidden(req, res);
      }
      try {
        return ok(req, res, await deleteStorageObject(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (!table) return badRequest(req, res, 'table zorunludur.');
    if (!allowedTables.has(table)) return badRequest(req, res, 'table desteklenmiyor.');

    if (table === 'serial_tracking') {
      await ensureSerialTrackingTable();
    }
    if (table === 'region_colors') {
      await ensureRegionColorsTable();
    }
    if (table === 'work_order_close_notes') {
      await ensureWorkOrderCloseNotesTable();
    }
    if (table === 'invoice_items') {
      const okTable = await ensureInvoiceItemsTable();
      if (!okTable) {
        throw new Error(
          'invoice_items table is missing. Run migrations (0003/0005/0012) or set ALLOW_SCHEMA_AUTO_CREATE=true in non-production.',
        );
      }
      columnsCache.delete('invoice_items');
      columnsMetaCache.delete('invoice_items');
    }
    if (table === 'fault_forms') {
      await ensureFaultFormsTable();
    }
    if (['scrap_forms', 'transfer_forms', 'fault_forms'].includes(table)) {
      await ensureFormDocumentColumns();
    }
    if (table === 'application_forms') {
      await ensureApplicationFormsApprovalColumns();
      await ensureApplicationFormActivityLogsTable();
    }
    if (table === 'device_registries') {
      await ensureDeviceRegistriesTable();
    }
    if (table === 'business_activity_types') {
      await ensureBusinessActivityTypesTable();
    }
    if (table === 'software_companies') {
      await ensureSoftwareCompaniesTable();
    }
    if (table === 'licenses') {
      await ensureLicensesSoftwareCompanyColumn();
      await ensureLicensesRegistryNumberColumn();
    }
  if (table === 'line_stock') {
    await ensureLineStockTable();
  }
  if (table === 'service_fault_types') {
    await ensureServiceFaultTypesTable();
  }
  if (table === 'service_accessory_types') {
    await ensureServiceAccessoryTypesTable();
  }
  if (table === 'service_records') {
    await ensureServiceRecordsColumns();
    await ensureServiceRecordsExtendedColumns();
    await ensureServiceRecordsStatusCheckConstraint();
  }
  if (table === 'service_activity_logs') {
    await ensureServiceActivityLogsTable();
  }
    if (table === 'lines') {
      await ensureLinesOperatorColumn();
    }
    if (table === 'work_order_signatures') {
      await ensureWorkOrderSignaturesTable();
    }
    if (table === 'finance_accounts' || table === 'finance_transactions') {
      await ensureFinanceTables();
    }
    if (table === 'invoices') {
      await ensureInvoicePricesIncludeVatColumn();
      columnsCache.delete('invoices');
      columnsMetaCache.delete('invoices');
    }

    const bankCustomerCreate =
      isBankLikeUser(user) && table === 'customers' && op === 'upsert';
    const bankBusinessActivityCreate =
      isBankLikeUser(user) &&
      table === 'business_activity_types' &&
      ['upsert', 'insertMany'].includes(op);
    const requiredPage = tablePermissions[table] || null;
    if (
      requiredPage &&
      !bankCustomerCreate &&
      !bankBusinessActivityCreate &&
      !requireAnyPage(req, user, requiredPage, res)
    )
      return;
    if (
      isBankLikeUser(user) &&
      ['scrap_forms', 'transfer_forms', 'fault_forms', 'serial_tracking'].includes(table)
    ) {
      return forbidden(req, res, 'Banka kullanıcısı yalnızca başvuru formu işlemi yapabilir.');
    }

    if (op === 'upsert') {
      let values = body.values;
      if (table === 'application_forms') {
        values = await materializeTaxpayerRegistrationDocument(values);
      }
      const returningRow = body.returning === 'row';
      const before =
        table === 'application_forms' && values?.id
          ? await selectApplicationFormAuditRow(values.id)
          : null;
      if (table === 'application_forms') {
        await assertApplicationFormsMutable({ op, values });
      }
      const result = await upsertRow({ table, values, returningRow, user });
      let invoiceLink = null;
      if (table === 'application_forms' && result.id) {
        const after = await selectApplicationFormAuditRow(result.id);
        await insertApplicationFormLog({
          formId: result.id,
          action: before ? 'update' : 'create',
          before,
          after,
          user,
        });
        if (textOrEmpty(after?.customer_id || values?.customer_id)) {
          invoiceLink = await maybeLinkApplicationFormInvoice(result.id);
        } else {
          invoiceLink = {
            created: false,
            linked: false,
            reason: 'missing_customer',
          };
        }
      }
      return ok(req, res, {
        ok: true,
        ...result,
        ...(invoiceLink ? { invoiceLink } : {}),
      });
    }

    if (op === 'delete') {
      const id = String(body.id || '').trim();
      if (!id) return badRequest(req, res, 'id zorunludur.');
      const before =
        table === 'application_forms'
          ? await selectApplicationFormAuditRow(id)
          : null;
      if (table === 'application_forms') {
        await assertApplicationFormsMutable({ op, id });
      }
      await deleteRow({ table, id });
      if (table === 'application_forms' && before) {
        await insertApplicationFormLog({
          formId: id,
          action: 'delete',
          before,
          after: null,
          user,
        });
      }
      return ok(req, res, { ok: true });
    }

    if (op === 'insertMany') {
      const rows = body.rows;
      const result = await insertMany({ table, rows, user });
      return ok(req, res, { ok: true, ...result });
    }

    if (op === 'updateWhere') {
      let values = body.values;
      const filters = body.filters;
      const formId =
        table === 'application_forms' ? applicationFormIdFilter(filters) : '';
      if (table === 'application_forms') {
        values = await materializeTaxpayerRegistrationDocument(values, formId);
      }
      const before = formId ? await selectApplicationFormAuditRow(formId) : null;
      if (table === 'application_forms') {
        await assertApplicationFormsMutable({ op, values, filters });
      }
      await updateWhere({ table, values, filters, user });
      let invoiceLink = null;
      if (table === 'application_forms' && formId) {
        const after = await selectApplicationFormAuditRow(formId);
        const action =
          values?.approval_status === 'approved'
            ? 'approve'
            : Object.prototype.hasOwnProperty.call(values || {}, 'is_active')
              ? 'status'
              : 'update';
        await insertApplicationFormLog({
          formId,
          action,
          before,
          after,
          user,
        });
        if (textOrEmpty(after?.customer_id)) {
          invoiceLink = await maybeLinkApplicationFormInvoice(formId);
        }
      }
      return ok(req, res, {
        ok: true,
        ...(invoiceLink ? { invoiceLink } : {}),
      });
    }

    if (op === 'deleteWhere') {
      const filters = body.filters;
      await deleteWhere({ table, filters });
      return ok(req, res, { ok: true });
    }

    return badRequest(req, res, `Bilinmeyen op: ${op}`);
  } catch (error) {
    return serverError(req, res, error);
  }
};
