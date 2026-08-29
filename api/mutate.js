const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

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
  ensureBkmAcquirersTable,
  ensureLicensesSoftwareCompanyColumn,
  ensureLicensesRegistryNumberColumn,
  ensureLinesOperatorColumn,
  ensureIssuedSourceInvoiceColumns,
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
  ensureApplicationFormsCreatedByRepair,
  ensureApplicationFormActivityLogsTable,
  ensureInvoicePricesIncludeVatColumn,
  ensureMutakabatRecordsTable,
  ensureMutakabatPriceSettingsTable,
  ensureQuotesTables,
} = require('./_lib/schema');
const {
  processMutakabat,
  recalculateSummary,
  ensureBrandIntegrations,
  exportMutakabatExcel,
  decodeBase64File,
} = require('./_lib/mutakabat_processor');
const {
  createInvoicePaymentLink,
  refundInvoicePosPayment,
  markPosPaymentSettled,
  dismissPosCollection,
} = require('./_lib/invoice_payment');
const { sendInvoicePaymentLinkEmail } = require('./_lib/invoice_mail');
const {
  upsertRecurringBillingPlan,
  setRecurringBillingPlanActive,
  runRecurringBilling,
} = require('./_lib/recurring_billing');
const { parseTsmLogRequestBody } = require('./_lib/tsm_log');
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
const mutakabatFileMaxBytes = 12 * 1024 * 1024;
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

function preferLocalStorage() {
  if (String(process.env.DISABLE_SUPABASE || '').trim().toLowerCase() === 'true') {
    return true;
  }
  const supabaseUrl = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const serviceRoleKey = String(
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  ).trim();
  return !supabaseUrl || !serviceRoleKey;
}

function localUploadsRoot() {
  return path.join(process.cwd(), '.local', 'uploads');
}

function buildLocalUploadPublicUrl(objectPath) {
  const localOrigin = String(process.env.MICROVISE_LOCAL_ORIGIN || '').trim();
  const port = Number(process.env.PORT || 4000);
  const base = localOrigin || `http://127.0.0.1:${port}`;
  const encoded = String(objectPath || '')
    .split('/')
    .filter(Boolean)
    .map((part) => encodeURIComponent(part))
    .join('/');
  return `${base.replace(/\/+$/, '')}/api/_local/uploads/${encoded}`;
}

function decodeUploadBytes(data, maxBytes, emptyMessage, tooLargeMessage) {
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
  return bytes;
}

function buildStorageObjectPath(folder, filename, contentType) {
  const ext = serviceImageExtension(contentType, filename);
  const random =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString('hex');
  const name = storageFilenameStem(filename, 'dosya');
  return `${safeStorageSegment(folder, 'uploads')}/${name}-${Date.now()}-${random}.${ext}`;
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

async function uploadLocalStorageObject({
  folder,
  filename,
  contentType,
  data,
  maxBytes,
  emptyMessage,
  tooLargeMessage,
}) {
  const bytes = decodeUploadBytes(data, maxBytes, emptyMessage, tooLargeMessage);
  const objectPath = buildStorageObjectPath(folder, filename, contentType);
  const uploadsRoot = localUploadsRoot();
  const absolutePath = path.join(uploadsRoot, ...objectPath.split('/'));
  fs.mkdirSync(path.dirname(absolutePath), { recursive: true });
  fs.writeFileSync(absolutePath, bytes);
  return {
    bucket: 'local',
    path: objectPath,
    url: buildLocalUploadPublicUrl(objectPath),
    contentType,
    size: bytes.length,
  };
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
  if (preferLocalStorage()) {
    return uploadLocalStorageObject({
      folder,
      filename,
      contentType,
      data,
      maxBytes,
      emptyMessage,
      tooLargeMessage,
    });
  }

  const { supabaseUrl, serviceRoleKey } = getSupabaseStorageConfig();
  const bytes = decodeUploadBytes(data, maxBytes, emptyMessage, tooLargeMessage);
  const objectPath = buildStorageObjectPath(folder, filename, contentType);
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
  const bucket = safeStorageSegment(body.bucket, serviceImageBucket);
  const objectPath = String(body.path || '').trim();
  if (!objectPath) {
    const error = new Error('Silinecek dosya yolu eksik.');
    error.statusCode = 400;
    throw error;
  }
  if (bucket === 'local' || preferLocalStorage()) {
    const absolutePath = path.join(localUploadsRoot(), ...objectPath.split('/'));
    const uploadsRoot = path.resolve(localUploadsRoot());
    const resolved = path.resolve(absolutePath);
    if (
      resolved.startsWith(`${uploadsRoot}${path.sep}`) &&
      fs.existsSync(resolved) &&
      fs.statSync(resolved).isFile()
    ) {
      fs.unlinkSync(resolved);
    }
    return { ok: true };
  }

  const { supabaseUrl, serviceRoleKey } = getSupabaseStorageConfig();
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

async function uploadProductImage(body) {
  const filename = safeStorageSegment(body.filename, 'image');
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (!allowedServiceImageContentTypes.has(contentType)) {
    const error = new Error('Sadece JPG, PNG veya WEBP görsel yüklenebilir.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: `products/${safeStorageSegment(body.productId, 'product')}`,
    filename,
    contentType,
    data: body.data,
    maxBytes: serviceImageMaxBytes,
    emptyMessage: 'Görsel verisi eksik.',
    tooLargeMessage: 'Görsel 5 MB sınırını aşıyor.',
  });
}

async function uploadQuoteLogo(body) {
  const filename = safeStorageSegment(body.filename, 'logo');
  const contentType = String(body.contentType || '').trim().toLowerCase();
  if (!allowedServiceImageContentTypes.has(contentType)) {
    const error = new Error('Sadece JPG, PNG veya WEBP logo yüklenebilir.');
    error.statusCode = 400;
    throw error;
  }

  return uploadStorageObject({
    folder: 'quote-branding',
    filename,
    contentType,
    data: body.data,
    maxBytes: serviceImageMaxBytes,
    emptyMessage: 'Logo verisi eksik.',
    tooLargeMessage: 'Logo 5 MB sınırını aşıyor.',
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

function decodeMutakabatFileField(body, key) {
  const buffer = decodeBase64File(body[key]);
  if (!buffer) return null;
  if (buffer.length > mutakabatFileMaxBytes) {
    const error = new Error(`${key} dosyası 12 MB sınırını aşıyor.`);
    error.statusCode = 400;
    throw error;
  }
  return buffer;
}

async function runProcessMutakabat(body) {
  const unitPrices = body.unitPrices || {};
  if (!body.bankFileBase64 && body.summary) {
    const enriched = ensureBrandIntegrations(
      body.summary,
      body.detailSheets || {},
      unitPrices,
    );
    const recalculated = recalculateSummary(enriched, unitPrices);
    return {
      summary: recalculated.summary,
      detailSheets: body.detailSheets || {},
      unitPrices: recalculated.unitPrices,
      sourceFiles: body.sourceFiles || {},
    };
  }

  const bankBuffer = decodeMutakabatFileField(body, 'bankFileBase64');
  if (!bankBuffer) {
    const error = new Error('Banka Excel dosyası zorunludur.');
    error.statusCode = 400;
    throw error;
  }
  const gmp3Buffer = decodeMutakabatFileField(body, 'gmp3FileBase64');
  const tsmBuffer = decodeMutakabatFileField(body, 'tsmFileBase64');
  const result = processMutakabat({
    bankBuffer,
    gmp3Buffer,
    tsmBuffer,
    unitPrices: body.unitPrices || {},
  });
  return {
    summary: result.summary,
    detailSheets: result.detailSheets,
    unitPrices: result.unitPrices,
    sourceFiles: body.sourceFiles || {},
  };
}

async function runExportMutakabatExcel(body) {
  const id = String(body.id || '').trim();
  if (id) {
    await ensureMutakabatRecordsTable();
    const result = await query(
      `
        select period_year, period_month, unit_prices, summary, detail_sheets
        from public.mutakabat_records
        where id = $1 and is_active = true
        limit 1
      `,
      [id],
    );
    const row = result.rows[0];
    if (!row) {
      const error = new Error('Mutakabat kaydı bulunamadı.');
      error.statusCode = 400;
      throw error;
    }
    const monthNames = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    const periodLabel = `${monthNames[row.period_month - 1] || row.period_month} ${row.period_year}`;
    const buffer = exportMutakabatExcel({
      summary: row.summary,
      detailSheets: row.detail_sheets,
      unitPrices: row.unit_prices,
      periodLabel,
    });
    return {
      filename: `mutakabat_${row.period_year}_${String(row.period_month).padStart(2, '0')}.xlsx`,
      mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      dataBase64: buffer.toString('base64'),
    };
  }

  if (!body.summary || !body.detailSheets) {
    const error = new Error('Excel dışa aktarımı için kayıt id veya özet verisi gerekli.');
    error.statusCode = 400;
    throw error;
  }
  const buffer = exportMutakabatExcel({
    summary: body.summary,
    detailSheets: body.detailSheets,
    unitPrices: body.unitPrices || {},
    periodLabel: body.periodLabel || '',
  });
  return {
    filename: body.filename || `mutakabat_${Date.now()}.xlsx`,
    mimeType:
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    dataBase64: buffer.toString('base64'),
  };
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
    `,
    [formId, number],
  );
}

async function markApplicationFormBillingQueueInvoiced(formId) {
  return markBillingQueueInvoiced('application_forms', formId);
}

async function markBillingQueueInvoiced(sourceTable, sourceId) {
  const table = textOrEmpty(sourceTable);
  const id = textOrEmpty(sourceId);
  if (!table || !id) return;
  try {
    await query(
      `
        update public.invoice_items
        set
          status = 'invoiced',
          invoiced_at = coalesce(invoiced_at, now())
        where source_table = $1
          and source_id = $2::uuid
          and invoice_id is null
          and coalesce(status, 'pending') = 'pending'
      `,
      [table, id],
    );
  } catch (_) {
    // Eski şemada source/status kolonları yoksa sessiz geç.
  }
}

const SERVICE_FORM_INVOICE_CONFIG = {
  scrap_forms: {
    itemType: 'scrap_form',
    sourceLabel: 'Hurda Formu',
    sourceEvent: 'scrap_form_sales_invoice',
    productHints: ['Hurda Formu', 'Hurda'],
    customerField: 'customer_id',
    dateField: 'form_date',
    selectColumns: `
      id, customer_id, customer_name, device_brand_model_registry,
      form_date::date as form_date
    `,
    notes: (row) => textOrEmpty(row.device_brand_model_registry).toUpperCase(),
    description: (row) => {
      const name = textOrEmpty(row.customer_name) || 'Müşteri';
      const device = textOrEmpty(row.device_brand_model_registry);
      return device ? `Hurda Formu - ${name} / ${device}` : `Hurda Formu - ${name}`;
    },
  },
  fault_forms: {
    itemType: 'fault_form',
    sourceLabel: 'Arıza Formu',
    sourceEvent: 'fault_form_sales_invoice',
    productHints: ['Arıza Formu', 'Arıza'],
    customerField: 'customer_id',
    dateField: 'form_date',
    selectColumns: `
      id, customer_id, customer_name, device_brand_model, company_code_and_registry,
      form_date::date as form_date
    `,
    notes: (row) =>
      textOrEmpty(row.company_code_and_registry).toUpperCase() ||
      textOrEmpty(row.device_brand_model).toUpperCase(),
    description: (row) => {
      const name = textOrEmpty(row.customer_name) || 'Müşteri';
      const device = textOrEmpty(row.device_brand_model);
      const registry = textOrEmpty(row.company_code_and_registry);
      const suffix = [device, registry].filter(Boolean).join(' / ');
      return suffix ? `Arıza Formu - ${name} / ${suffix}` : `Arıza Formu - ${name}`;
    },
  },
  transfer_forms: {
    itemType: 'transfer_form',
    sourceLabel: 'Devir Formu',
    sourceEvent: 'transfer_form_sales_invoice',
    productHints: ['Devir Formu', 'Devir'],
    customerField: 'transferor_customer_id',
    dateField: 'transfer_date',
    selectColumns: `
      id, transferor_customer_id, transferor_name, transferee_name,
      brand_model, device_serial_no, transfer_date::date as transfer_date
    `,
    notes: (row) => textOrEmpty(row.device_serial_no).toUpperCase(),
    description: (row) => {
      const from = textOrEmpty(row.transferor_name) || 'Devreden';
      const to = textOrEmpty(row.transferee_name) || 'Devralan';
      const serial = textOrEmpty(row.device_serial_no);
      const base = `Devir Formu - ${from} → ${to}`;
      return serial ? `${base} / ${serial}` : base;
    },
  },
};

async function resolveProductByHints(hints) {
  const list = (Array.isArray(hints) ? hints : [])
    .map((item) => textOrEmpty(item))
    .filter(Boolean);
  for (const hint of list) {
    const exact = await query(
      `
        select id, name, code, sale_price, tax_rate, currency, unit
        from public.products
        where coalesce(is_active, true) = true
          and lower(name) = lower($1)
        order by sale_price desc nulls last, name asc
        limit 1
      `,
      [hint],
    );
    if (exact.rows?.[0]) return exact.rows[0];
  }
  for (const hint of list) {
    const fuzzy = await query(
      `
        select id, name, code, sale_price, tax_rate, currency, unit
        from public.products
        where coalesce(is_active, true) = true
          and name ilike '%' || $1 || '%'
        order by
          case when lower(name) like lower($1) || '%' then 0 else 1 end,
          sale_price desc nulls last,
          name asc
        limit 1
      `,
      [hint],
    );
    if (fuzzy.rows?.[0]) return fuzzy.rows[0];
  }
  return null;
}

async function findExistingSalesInvoiceForSource(sourceTable, sourceId) {
  const result = await query(
    `
      select i.id, i.invoice_number
      from public.invoice_items ii
      join public.invoices i
        on i.id = ii.invoice_id
      where ii.source_table = $1
        and ii.source_id = $2::uuid
        and coalesce(i.invoice_type, 'sales') = 'sales'
        and coalesce(i.is_active, true) = true
        and coalesce(i.status, '') <> 'cancelled'
      order by i.created_at desc nulls last
      limit 1
    `,
    [sourceTable, sourceId],
  );
  return result.rows?.[0] || null;
}

/**
 * Hurda / Arıza / Devir formu için açık satış e-faturası oluşturur.
 */
async function createSalesInvoiceForServiceForm(sourceTable, formId) {
  const config = SERVICE_FORM_INVOICE_CONFIG[sourceTable];
  if (!config) {
    return { created: false, linked: false, reason: 'unsupported_table' };
  }
  const id = textOrEmpty(formId);
  if (!id) {
    const err = new Error('formId zorunludur.');
    err.statusCode = 400;
    throw err;
  }

  const existing = await findExistingSalesInvoiceForSource(sourceTable, id);
  if (existing?.id) {
    await markBillingQueueInvoiced(sourceTable, id);
    return {
      created: false,
      linked: true,
      reason: 'already_linked',
      invoiceId: existing.id,
      invoiceNumber: existing.invoice_number,
    };
  }

  const formResult = await query(
    `
      select ${config.selectColumns}
      from public.${sourceTable}
      where id = $1::uuid
      limit 1
    `,
    [id],
  );
  const form = formResult.rows?.[0];
  if (!form) {
    const err = new Error('Form kaydı bulunamadı.');
    err.statusCode = 400;
    throw err;
  }

  const customerId = textOrEmpty(form[config.customerField]);
  if (!customerId) {
    return { created: false, linked: false, reason: 'missing_customer' };
  }

  const product = await resolveProductByHints(config.productHints);
  const unit = textOrEmpty(product?.unit) || 'Adet';
  const taxRate = Number(product?.tax_rate);
  const safeTaxRate = Number.isFinite(taxRate) ? taxRate : 20;
  const unitPrice = round4(Number(product?.sale_price) || 0);
  const taxAmount = round2(unitPrice * (safeTaxRate / 100));
  const lineTotal = round2(unitPrice + taxAmount);
  const description = config.description(form) || config.sourceLabel;
  const registry = config.notes(form) || null;

  const currency = 'USD';
  const rates = await fetchHalkbankSellingRates();
  const exchangeRate = round4(rates.USD || FX_FALLBACK.USD || 1);

  const numberResult = await query(
    `select public.generate_invoice_number('sales') as value`,
  );
  const invoiceNumber =
    textOrEmpty(numberResult.rows?.[0]?.value) || `STŞ-${Date.now()}`;

  const rawDate = form[config.dateField];
  const invoiceDate =
    (rawDate && String(rawDate).slice(0, 10)) ||
    new Date().toISOString().slice(0, 10);

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
        $6, $7, 0, $8, 0, 'open', null, true
      )
      returning id, invoice_number
    `,
    [
      invoiceNumber,
      customerId,
      invoiceDate,
      currency,
      exchangeRate,
      unitPrice,
      taxAmount,
      lineTotal,
    ],
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
        $4,
        $5,
        $6::uuid,
        $7,
        $8,
        $9,
        $10,
        1,
        $11,
        $12,
        $13,
        $14,
        0,
        0,
        $15,
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
      config.itemType,
      sourceTable,
      id,
      config.sourceEvent,
      config.sourceLabel,
      description,
      registry,
      unit,
      unitPrice,
      safeTaxRate,
      taxAmount,
      lineTotal,
    ],
  );

  await markBillingQueueInvoiced(sourceTable, id);

  return {
    created: true,
    linked: true,
    registry,
    invoiceId: invoice.id,
    invoiceNumber: invoice.invoice_number,
    invoiceItemId: itemInsert.rows?.[0]?.id || null,
    status: 'open',
    currency,
    exchangeRate,
    unitPrice,
    taxRate: safeTaxRate,
    productId: product?.id || null,
    productName: product?.name || description,
    reason: product ? null : 'product_not_found_zero_price',
    sourceTable,
    sourceId: id,
  };
}

async function maybeLinkServiceFormInvoice(sourceTable, formId) {
  const table = textOrEmpty(sourceTable);
  const id = textOrEmpty(formId);
  if (!table || !id || !SERVICE_FORM_INVOICE_CONFIG[table]) return null;
  try {
    return await createSalesInvoiceForServiceForm(table, id);
  } catch (error) {
    return {
      created: false,
      linked: false,
      reason: 'error',
      error: error?.message || String(error),
    };
  }
}

async function findExistingSalesInvoiceForForm(form, formId, customerId) {
  // Bu forma ait kalem (source_id) varsa onu kullan.
  const bySource = await query(
    `
      select i.id, i.invoice_number
      from public.invoice_items ii
      join public.invoices i
        on i.id = ii.invoice_id
      where ii.source_table = 'application_forms'
        and ii.source_id = $1::uuid
        and coalesce(i.invoice_type, 'sales') = 'sales'
        and coalesce(i.is_active, true) = true
        and coalesce(i.status, '') <> 'cancelled'
      order by i.created_at desc nulls last
      limit 1
    `,
    [formId],
  );
  if (bySource.rows?.[0]) return bySource.rows[0];

  // Eski taslaklarda header notuna yazılmış başvuru id'si.
  const byNotes = await query(
    `
      select i.id, i.invoice_number
      from public.invoices i
      where coalesce(i.invoice_type, 'sales') = 'sales'
        and coalesce(i.is_active, true) = true
        and coalesce(i.status, '') <> 'cancelled'
        and coalesce(i.notes, '') ilike '%' || $1 || '%'
        and (
          i.customer_id = $2::uuid
          or $2::text = ''
        )
      order by i.created_at desc nulls last
      limit 1
    `,
    [formId, customerId],
  );
  if (byNotes.rows?.[0]) return byNotes.rows[0];

  // Formdaki invoice_number yalnız bu forma ait kalemle doğrulanırsa "zaten bağlı".
  // Başka başvurunun numarası kopyalandıysa yeni fatura açılsın diye burada eşleşmeyiz.
  const explicitInvoice = textOrEmpty(form.invoice_number);
  if (!explicitInvoice) return null;

  const byNumberOwned = await query(
    `
      select i.id, i.invoice_number
      from public.invoices i
      join public.invoice_items ii
        on ii.invoice_id = i.id
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
        and (
          (ii.source_table = 'application_forms' and ii.source_id = $3::uuid)
          or coalesce(i.notes, '') ilike '%' || $3 || '%'
        )
      order by i.invoice_date desc nulls last
      limit 1
    `,
    [explicitInvoice, customerId, formId],
  );
  return byNumberOwned.rows?.[0] || null;
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

function buildApplicationFormInvoiceLineMeta(form, product) {
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
  const registry = textOrEmpty(form.stock_registry_number).toUpperCase();
  return {
    description,
    unit,
    safeTaxRate,
    unitPrice,
    taxAmount,
    lineTotal,
    registry,
    productId: product?.id || null,
    productName: description,
    reason: product ? null : 'product_not_found_zero_price',
  };
}

/**
 * Birden fazla başvuru formu için TEK satış faturası + her sicil için ayrı kalem.
 */
async function createSalesInvoiceForApplicationForms(formRows) {
  const rows = (Array.isArray(formRows) ? formRows : []).filter(
    (row) => row?.form && row?.formId && row?.customerId,
  );
  if (!rows.length) {
    const err = new Error('Fatura için başvuru formu bulunamadı.');
    err.statusCode = 400;
    throw err;
  }

  const customerId = textOrEmpty(rows[0].customerId);
  if (!customerId) {
    const err = new Error('E-Fatura için müşteri zorunludur.');
    err.statusCode = 400;
    throw err;
  }
  for (const row of rows) {
    if (textOrEmpty(row.customerId) !== customerId) {
      const err = new Error(
        'Tek faturada tüm başvurular aynı müşteriye ait olmalı.',
      );
      err.statusCode = 400;
      throw err;
    }
  }

  // Yalnızca yeni başvuru formu taslakları için varsayılan: KDV hariç + USD.
  const currency = 'USD';
  const rates = await fetchHalkbankSellingRates();
  const exchangeRate = round4(rates.USD || FX_FALLBACK.USD || 1);

  const numberResult = await query(
    `select public.generate_invoice_number('sales') as value`,
  );
  const invoiceNumber =
    textOrEmpty(numberResult.rows?.[0]?.value) || `STŞ-${Date.now()}`;

  const invoiceDate =
    rows[0].form.application_date || new Date().toISOString().slice(0, 10);

  const lineMetas = [];
  for (const row of rows) {
    const product = await resolveProductForApplicationForm(row.form);
    lineMetas.push({
      formId: row.formId,
      ...buildApplicationFormInvoiceLineMeta(row.form, product),
    });
  }

  const subtotal = round2(
    lineMetas.reduce((sum, line) => sum + Number(line.unitPrice || 0), 0),
  );
  const taxTotal = round2(
    lineMetas.reduce((sum, line) => sum + Number(line.taxAmount || 0), 0),
  );
  const grandTotal = round2(subtotal + taxTotal);

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
        $6, $7, 0, $8, 0, 'open', null, true
      )
      returning id, invoice_number
    `,
    [
      invoiceNumber,
      customerId,
      invoiceDate,
      currency,
      exchangeRate,
      subtotal,
      taxTotal,
      grandTotal,
    ],
  );
  const invoice = invoiceInsert.rows?.[0];
  if (!invoice?.id) {
    const err = new Error('Satış faturası oluşturulamadı.');
    err.statusCode = 500;
    throw err;
  }

  const itemIds = [];
  for (let i = 0; i < lineMetas.length; i += 1) {
    const line = lineMetas[i];
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
          $12,
          'invoiced',
          true
        )
        returning id
      `,
      [
        invoice.id,
        line.productId,
        customerId,
        line.formId,
        line.description,
        line.registry || null,
        line.unit,
        line.unitPrice,
        line.safeTaxRate,
        line.taxAmount,
        line.lineTotal,
        i,
      ],
    );
    itemIds.push(itemInsert.rows?.[0]?.id || null);
    await setApplicationFormInvoiceNumber(line.formId, invoice.invoice_number);
    await markApplicationFormBillingQueueInvoiced(line.formId);
  }

  const first = lineMetas[0];
  return {
    created: true,
    linked: true,
    shared: lineMetas.length > 1,
    formCount: lineMetas.length,
    registry: first.registry || null,
    registries: lineMetas.map((line) => line.registry || null),
    invoiceId: invoice.id,
    invoiceNumber: invoice.invoice_number,
    invoiceItemId: itemIds[0] || null,
    invoiceItemIds: itemIds,
    applicationFormIds: lineMetas.map((line) => line.formId),
    status: 'open',
    currency,
    exchangeRate,
    unitPrice: first.unitPrice,
    taxRate: first.safeTaxRate,
    subtotal,
    taxTotal,
    grandTotal,
    productId: first.productId,
    productName: first.productName,
    reason: lineMetas.some((line) => line.reason) ? 'product_not_found_zero_price' : null,
  };
}

async function createSalesInvoiceForApplicationForm(form, formId, customerId) {
  return createSalesInvoiceForApplicationForms([
    { form, formId, customerId },
  ]);
}

/**
 * Başvuru formu için satış e-faturası oluşturur / bağlar.
 * 1) Bu forma ait fatura zaten varsa (invoice_number / form notu) tekrar oluşturmaz
 * 2) Kullanıcı formda fatura no yazdıysa mevcut kaleme sicil bağlar
 * 3) Yoksa E-Fatura listesinde (Açık) görünen yeni satış faturası + kalem oluşturur
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

  const explicitInvoice = textOrEmpty(form.invoice_number);

  // 2) Yalnızca kullanıcı formda fatura no yazdıysa VE bu numara başka
  //    başvuruya ait değilse mevcut faturaya bağlan.
  //    Müşteri+model ile otomatik eşleştirme kaldırıldı (eski ödenmiş faturaya
  //    yapışıp yeni fatura açılmıyordu).
  let canMatchExplicit = Boolean(explicitInvoice);
  if (canMatchExplicit) {
    const claimedByOther = await query(
      `
        select id
        from public.application_forms
        where id <> $1::uuid
          and invoice_number is not null
          and btrim(invoice_number) <> ''
          and (
            invoice_number = $2
            or invoice_number ilike '%' || $2
            or $2 ilike '%' || invoice_number
          )
        limit 1
      `,
      [formId, explicitInvoice],
    );
    if (claimedByOther.rows?.[0]) {
      canMatchExplicit = false;
    }
  }

  if (canMatchExplicit) {
    const match = await query(
      `
        select
          ii.id as item_id,
          i.id as invoice_id,
          i.invoice_number
        from public.invoices i
        join public.invoice_items ii
          on ii.invoice_id = i.id
        where i.customer_id = $1::uuid
          and coalesce(i.invoice_type, 'sales') = 'sales'
          and coalesce(i.is_active, true) = true
          and coalesce(i.status, '') <> 'cancelled'
          and (
            i.invoice_number = $2
            or i.invoice_number ilike '%' || $2
            or regexp_replace(i.invoice_number, '^\\d{9}-', '') = $2
          )
          and (
            $3::text = ''
            or nullif(btrim(coalesce(ii.notes, '')), '') is null
            or upper(btrim(ii.notes)) = $3
          )
        order by
          case
            when $3::text <> '' and upper(btrim(coalesce(ii.notes, ''))) = $3 then 0
            when nullif(btrim(coalesce(ii.notes, '')), '') is null then 1
            else 2
          end,
          i.invoice_date desc nulls last,
          coalesce(ii.sort_order, 0)
        limit 1
      `,
      [customerId, explicitInvoice, registry],
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

  // 3) Uygun fatura yoksa E-Fatura (Açık) satış faturası oluştur.
  return createSalesInvoiceForApplicationForm(form, formId, customerId);
}

/**
 * Başvuru kaydı sonrası: müşteri varsa açık satış e-faturası oluştur / bağla.
 * Form kaydını bozmamak için hata fırlatmaz; sonucu döner (UI popup gösterir).
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
 * Birden fazla başvuru (her cihaz sicili) için TEK satış faturası oluşturur.
 * Zaten faturalı formlar atlanır; hepsi aynı faturadaysa tekrar oluşturmaz.
 */
async function linkApplicationFormsBatchToInvoice(body) {
  await ensureInvoiceItemsTable();
  await ensureInvoicePricesIncludeVatColumn();

  const rawIds = Array.isArray(body.applicationFormIds)
    ? body.applicationFormIds
    : Array.isArray(body.formIds)
      ? body.formIds
      : [];
  const formIds = [
    ...new Set(
      rawIds.map((id) => textOrEmpty(id)).filter(Boolean),
    ),
  ];
  if (!formIds.length) {
    const single = textOrEmpty(body.applicationFormId || body.formId || body.id);
    if (single) formIds.push(single);
  }
  if (!formIds.length) {
    const err = new Error('applicationFormIds zorunludur.');
    err.statusCode = 400;
    throw err;
  }
  if (formIds.length === 1) {
    return linkApplicationFormDeviceToInvoice({
      applicationFormId: formIds[0],
    });
  }

  const formsResult = await query(
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
      where id = any($1::uuid[])
    `,
    [formIds],
  );
  const byId = new Map(
    (formsResult.rows || []).map((row) => [String(row.id), row]),
  );
  const missing = formIds.filter((id) => !byId.has(id));
  if (missing.length) {
    const err = new Error(
      `Başvuru formu bulunamadı: ${missing.slice(0, 3).join(', ')}`,
    );
    err.statusCode = 400;
    throw err;
  }

  const forms = formIds.map((id) => byId.get(id));
  const customerId = textOrEmpty(forms[0].customer_id);
  if (!customerId) {
    return {
      created: false,
      linked: false,
      reason: 'missing_customer',
    };
  }
  for (const form of forms) {
    if (textOrEmpty(form.customer_id) !== customerId) {
      const err = new Error(
        'Tek faturada tüm başvurular aynı müşteriye ait olmalı.',
      );
      err.statusCode = 400;
      throw err;
    }
  }

  const already = [];
  const pending = [];
  for (const form of forms) {
    const existing = await findExistingSalesInvoiceForForm(
      form,
      form.id,
      customerId,
    );
    if (existing?.id) {
      already.push({ form, existing });
    } else {
      pending.push(form);
    }
  }

  if (!pending.length) {
    const invoiceIds = [
      ...new Set(already.map((item) => String(item.existing.id))),
    ];
    if (invoiceIds.length === 1) {
      const inv = already[0].existing;
      for (const item of already) {
        await ensureInvoiceLineNotes(
          inv.id,
          textOrEmpty(item.form.stock_registry_number).toUpperCase(),
        );
        await setApplicationFormInvoiceNumber(item.form.id, inv.invoice_number);
        await markApplicationFormBillingQueueInvoiced(item.form.id);
      }
      return {
        created: false,
        linked: true,
        shared: true,
        reason: 'already_linked',
        formCount: forms.length,
        invoiceId: inv.id,
        invoiceNumber: inv.invoice_number,
        applicationFormIds: formIds,
      };
    }
    // Farklı faturalara dağılmışsa dokunma; her biri kendi faturasında kalsın.
    return {
      created: false,
      linked: true,
      shared: false,
      reason: 'already_linked_separate',
      formCount: forms.length,
      invoiceIds,
      applicationFormIds: formIds,
    };
  }

  // Kısmen bağlıysa: kalan başvuruları yeni paylaşılan faturaya koy
  // (mevcut ayrı faturaları birleştirme).
  const created = await createSalesInvoiceForApplicationForms(
    pending.map((form) => ({
      form,
      formId: form.id,
      customerId,
    })),
  );

  return {
    ...created,
    skippedAlreadyLinked: already.length,
    pendingCount: pending.length,
  };
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

async function convertQuoteToInvoice(body, user) {
  const quoteId = String(body.quoteId || '').trim();
  if (!quoteId) {
    const error = new Error('quoteId zorunludur.');
    error.statusCode = 400;
    throw error;
  }

  await ensureQuotesTables();

  const quoteResult = await query(
    `
      select q.*, c.name as customer_name
      from public.quotes q
      left join public.customers c on c.id = q.customer_id
      where q.id = $1
      limit 1
    `,
    [quoteId],
  );
  const quote = quoteResult.rows[0];
  if (!quote) {
    const error = new Error('Teklif bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  if (!quote.is_active) {
    const error = new Error('Pasif teklif faturaya dönüştürülemez.');
    error.statusCode = 400;
    throw error;
  }
  if (quote.status === 'converted' && quote.converted_invoice_id) {
    return {
      invoiceId: quote.converted_invoice_id,
      alreadyConverted: true,
    };
  }

  const itemsResult = await query(
    `
      select *
      from public.quote_items
      where quote_id = $1
      order by sort_order asc, created_at asc
    `,
    [quoteId],
  );
  const items = itemsResult.rows;
  if (!items.length) {
    const error = new Error('Teklif kalemi bulunamadı.');
    error.statusCode = 400;
    throw error;
  }

  const numberResult = await query(
    `select public.generate_invoice_number('sales') as value`,
  );
  const invoiceNumber = numberResult.rows[0]?.value || '';
  if (!invoiceNumber) {
    const error = new Error('Satış fatura numarası üretilemedi.');
    error.statusCode = 400;
    throw error;
  }

  const invoiceInsert = await query(
    `
      insert into public.invoices (
        invoice_number,
        invoice_type,
        customer_id,
        invoice_date,
        due_date,
        currency,
        exchange_rate,
        prices_include_vat,
        subtotal,
        tax_total,
        discount_total,
        grand_total,
        status,
        notes,
        created_by
      )
      values (
        $1, 'sales', $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 'open', $12, $13
      )
      returning id, invoice_number
    `,
    [
      invoiceNumber,
      quote.customer_id,
      quote.quote_date,
      quote.valid_until,
      quote.currency,
      quote.exchange_rate,
      quote.prices_include_vat,
      quote.subtotal,
      quote.tax_total,
      quote.discount_total,
      quote.grand_total,
      quote.notes,
      user?.id || quote.created_by || null,
    ],
  );
  const invoice = invoiceInsert.rows[0];

  for (const item of items) {
    await query(
      `
        insert into public.invoice_items (
          invoice_id,
          product_id,
          description,
          quantity,
          unit,
          unit_price,
          tax_rate,
          tax_amount,
          discount_rate,
          discount_amount,
          line_total,
          sort_order
        )
        values ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12)
      `,
      [
        invoice.id,
        item.product_id,
        item.description,
        item.quantity,
        item.unit,
        item.unit_price,
        item.tax_rate,
        item.tax_amount,
        item.discount_rate,
        item.discount_amount,
        item.line_total,
        item.sort_order,
      ],
    );
  }

  await query(
    `
      update public.quotes
      set status = 'converted',
          converted_invoice_id = $2,
          updated_at = now()
      where id = $1
    `,
    [quoteId, invoice.id],
  );

  return {
    invoiceId: invoice.id,
    invoiceNumber: invoice.invoice_number,
    quoteId,
  };
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
  'bkm_acquirers',
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
  'mutakabat_records',
  'mutakabat_price_settings',
  'quotes',
  'quote_items',
  'quote_document_settings',
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
  bkm_acquirers: ['tanimlamalar', 'tsm_log'],
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
  mutakabat_records: 'mutakabat',
  mutakabat_price_settings: 'mutakabat',
  quotes: 'teklif',
  quote_items: 'teklif',
  quote_document_settings: 'teklif',
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
    for (const key of [
      'name',
      'vkn',
      'tckn_ms',
      'address',
      'director_name',
      'city',
      'email',
      'phone_1',
      'is_active',
    ]) {
      if (Object.prototype.hasOwnProperty.call(source, key)) {
        next[key] = source[key];
      }
    }
    next.is_active = true;
    if (source.vkn != null) {
      let vkn = String(source.vkn || '').replace(/\D/g, '');
      // KKTC 8–9 hane → CRM’de soldan 0 ile 10 hane.
      if (vkn.length >= 8 && vkn.length < 10) {
        vkn = vkn.padStart(10, '0');
      } else if (vkn.length > 10) {
        vkn = vkn.slice(0, 10);
      }
      next.vkn = vkn;
    }
    if (source.tckn_ms != null) {
      next.tckn_ms = String(source.tckn_ms || '')
        .trim()
        .replace(/[\s\-_.]/g, '')
        .toLocaleUpperCase('tr-TR');
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
    const source = values || {};
    const next = { ...source };
    // Partial update (banka/normal onay vb.) created_by göndermez.
    // Burada enjekte edersek sahiplik personele geçer ve banka listeden kaybolur.
    if (Object.prototype.hasOwnProperty.call(source, 'created_by')) {
      if (!String(next.created_by || '').trim()) {
        next.created_by = user?.auth_user_id || user?.id || null;
      }
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
  bank_approval_status: 'Banka onay durumu',
  bank_approved_at: 'Banka onay tarihi',
  bank_approved_by: 'Banka onaylayan',
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

function idsFromFilters(filters, col = 'id') {
  const list = Array.isArray(filters) ? filters : [];
  const found = list.find((f) => f && String(f.col || '').trim() === col);
  if (!found) return [];
  if (found.op === 'eq') {
    const id = String(found.value || '').trim();
    return id ? [id] : [];
  }
  if (found.op === 'in') {
    return (Array.isArray(found.value) ? found.value : [])
      .map((v) => String(v || '').trim())
      .filter(Boolean);
  }
  return [];
}

function normalizeIssuedKindText(value) {
  return String(value || '')
    .toLowerCase()
    .replace(/ı/g, 'i')
    .replace(/\s+/g, ' ')
    .trim();
}

function issuedKindFromItemType(itemType) {
  const t = String(itemType || '').trim();
  if (t === 'line_sale') return 'line';
  if (t === 'gmp3_sale') return 'gmp3';
  return null;
}

function invoicePeriodDates(invoiceDate) {
  const raw = String(invoiceDate || '').slice(0, 10);
  const start = /^\d{4}-\d{2}-\d{2}$/.test(raw)
    ? raw
    : new Date().toISOString().slice(0, 10);
  const year = Number(start.slice(0, 4));
  const end = `${Number.isFinite(year) ? year : new Date().getFullYear()}-12-31`;
  return { start, end };
}

function digitsOnly(value) {
  return String(value || '').replace(/[^0-9]/g, '');
}

function unitCountFromQuantity(quantity) {
  const n = Number(quantity);
  if (!Number.isFinite(n) || n <= 0) return 1;
  return Math.max(1, Math.round(n));
}

async function matchSoftwareCompanyId(text) {
  const hay = normalizeIssuedKindText(text);
  if (!hay) return null;
  try {
    await ensureSoftwareCompaniesTable();
    const result = await query(
      `
        select id, name
        from public.software_companies
        where coalesce(is_active, true) = true
        order by name asc
      `,
    );
    for (const row of result.rows) {
      const name = normalizeIssuedKindText(row.name);
      if (name && hay.includes(name)) return row.id;
    }
    const pax = result.rows.find((r) => /pax/.test(normalizeIssuedKindText(r.name)));
    if (pax && /\bpax\b/.test(hay)) return pax.id;
    const ingenico = result.rows.find((r) =>
      /ingenico/.test(normalizeIssuedKindText(r.name)),
    );
    if (ingenico && /ingenico/.test(hay)) return ingenico.id;
  } catch (_) {}
  return null;
}

async function consumeMatchingLineStock({ customerId, lineId, number, user }) {
  const digits = digitsOnly(number);
  if (digits.length < 10 || !lineId) return;
  try {
    await ensureLineStockTable();
    await query(
      `
        update public.line_stock
        set
          consumed_at = now(),
          consumed_by = $3,
          consumed_customer_id = $1::uuid,
          consumed_line_id = $2::uuid
        where consumed_at is null
          and coalesce(is_active, true) = true
          and regexp_replace(coalesce(line_number, ''), '[^0-9]', '', 'g') = $4
      `,
      [customerId, lineId, user?.auth_user_id || user?.id || null, digits],
    );
  } catch (_) {}
}

async function insertIssuedRow(table, values) {
  const columns = await getColumns(table);
  const picked = pickValues(values, columns);
  if (!picked.id) picked.id = crypto.randomUUID();
  const keys = Object.keys(picked);
  if (!keys.length) return null;
  const colSql = keys.map(quoteIdent).join(', ');
  const placeholders = keys.map((_, i) => `$${i + 1}`).join(', ');
  const result = await query(
    `
      insert into public.${quoteIdent(table)} (${colSql})
      values (${placeholders})
      returning id
    `,
    keys.map((k) => picked[k]),
  );
  return result.rows[0]?.id || picked.id;
}

async function setIssuedHatGmp3ActiveForInvoices(invoiceIds, isActive) {
  const ids = (invoiceIds || []).map((v) => String(v || '').trim()).filter(Boolean);
  if (!ids.length) return;
  await ensureIssuedSourceInvoiceColumns();
  await query(
    `
      update public.lines
      set is_active = $2
      where source_invoice_id = any($1::uuid[])
    `,
    [ids, isActive === true],
  );
  await query(
    `
      update public.licenses
      set is_active = $2
      where source_invoice_id = any($1::uuid[])
    `,
    [ids, isActive === true],
  );
}

async function deleteIssuedHatGmp3ForInvoices(invoiceIds) {
  const ids = (invoiceIds || []).map((v) => String(v || '').trim()).filter(Boolean);
  if (!ids.length) return;
  await ensureIssuedSourceInvoiceColumns();
  try {
    await query(
      `
        delete from public.invoice_items
        where source_table in ('lines', 'licenses')
          and source_id in (
            select id from public.lines where source_invoice_id = any($1::uuid[])
            union all
            select id from public.licenses where source_invoice_id = any($1::uuid[])
          )
      `,
      [ids],
    );
  } catch (_) {}
  await query(`delete from public.lines where source_invoice_id = any($1::uuid[])`, [
    ids,
  ]);
  await query(`delete from public.licenses where source_invoice_id = any($1::uuid[])`, [
    ids,
  ]);
}

async function syncIssuedHatGmp3FromInvoice(invoiceId, user) {
  const id = textOrEmpty(invoiceId);
  if (!id) return { lines: 0, licenses: 0 };
  await ensureInvoiceItemsTable();
  await ensureIssuedSourceInvoiceColumns();
  await ensureLicensesSoftwareCompanyColumn();
  await ensureLicensesRegistryNumberColumn();
  await ensureLinesOperatorColumn();
  columnsCache.delete('lines');
  columnsCache.delete('licenses');

  const invoiceResult = await query(
    `
      select id, customer_id, invoice_type, invoice_date, is_active, status, invoice_number
      from public.invoices
      where id = $1
      limit 1
    `,
    [id],
  );
  const invoice = invoiceResult.rows[0];
  if (!invoice) return { lines: 0, licenses: 0 };
  if (String(invoice.invoice_type || 'sales') !== 'sales') {
    return { lines: 0, licenses: 0 };
  }

  const invoiceActive =
    invoice.is_active !== false && String(invoice.status || '') !== 'cancelled';
  if (!invoiceActive) {
    await setIssuedHatGmp3ActiveForInvoices([id], false);
    return { lines: 0, licenses: 0, deactivated: true };
  }

  const customerId = textOrEmpty(invoice.customer_id);
  if (!customerId) return { lines: 0, licenses: 0 };

  const itemsResult = await query(
    `
      select
        ii.item_type,
        ii.description,
        ii.notes,
        ii.quantity,
        p.name as product_name,
        p.code as product_code,
        p.category as product_category
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      where ii.invoice_id = $1
      order by coalesce(ii.sort_order, 0) asc, ii.id asc
    `,
    [id],
  );

  const lineUnits = [];
  const gmp3Units = [];
  for (const item of itemsResult.rows) {
    const kind = issuedKindFromItemType(item.item_type);
    if (!kind) continue;
    const qty = unitCountFromQuantity(item.quantity);
    const description =
      textOrEmpty(item.description) || textOrEmpty(item.product_name);
    const notes = textOrEmpty(item.notes);
    const hay = [
      description,
      notes,
      item.product_name,
      item.product_code,
      item.product_category,
    ]
      .filter(Boolean)
      .join(' ');
    for (let i = 0; i < qty; i += 1) {
      const unit = { description, notes, hay };
      if (kind === 'line') lineUnits.push(unit);
      else gmp3Units.push(unit);
    }
  }

  const { start, end } = invoicePeriodDates(invoice.invoice_date);
  const createdBy = user?.auth_user_id || user?.id || null;

  const existingLines = await query(
    `
      select id, number
      from public.lines
      where source_invoice_id = $1
      order by created_at asc, id asc
    `,
    [id],
  );
  const existingLicenses = await query(
    `
      select id, registry_number
      from public.licenses
      where source_invoice_id = $1
      order by created_at asc, id asc
    `,
    [id],
  );

  let linesCreated = 0;
  for (let i = 0; i < lineUnits.length; i += 1) {
    const unit = lineUnits[i];
    const existing = existingLines.rows[i];
    const noteDigits = digitsOnly(unit.notes);
    const number =
      noteDigits.length >= 10 && noteDigits.length <= 15 ? noteDigits : null;
    const label = textOrEmpty(unit.description) || 'Hat Satışı';
    if (existing?.id) {
      await query(
        `
          update public.lines
          set
            is_active = true,
            label = coalesce(nullif($2, ''), label),
            number = coalesce(nullif($3, ''), number),
            starts_at = $4::date,
            ends_at = $5::date,
            expires_at = $5::date
          where id = $1
        `,
        [existing.id, label, number, start, end],
      );
      continue;
    }
    if (number) {
      const dup = await query(
        `
          select id
          from public.lines
          where customer_id = $1
            and regexp_replace(coalesce(number, ''), '[^0-9]', '', 'g') = $2
            and coalesce($2, '') <> ''
          limit 1
        `,
        [customerId, digitsOnly(number)],
      );
      if (dup.rows[0]?.id) {
        await query(
          `
            update public.lines
            set source_invoice_id = coalesce(source_invoice_id, $2::uuid), is_active = true
            where id = $1
          `,
          [dup.rows[0].id, id],
        );
        continue;
      }
    }
    const lineId = await insertIssuedRow('lines', {
      customer_id: customerId,
      label,
      number,
      sim_number: number && String(number).startsWith('89') ? number : null,
      starts_at: start,
      ends_at: end,
      expires_at: end,
      is_active: true,
      created_by: createdBy,
      source_invoice_id: id,
    });
    if (lineId) {
      linesCreated += 1;
      await consumeMatchingLineStock({
        customerId,
        lineId,
        number,
        user,
      });
    }
  }
  const extraLineIds = existingLines.rows.slice(lineUnits.length).map((r) => r.id);
  if (extraLineIds.length) {
    await query(
      `update public.lines set is_active = false where id = any($1::uuid[])`,
      [extraLineIds],
    );
  }
  if (!lineUnits.length && existingLines.rows.length) {
    await query(
      `update public.lines set is_active = false where source_invoice_id = $1`,
      [id],
    );
  }

  let licensesCreated = 0;
  for (let i = 0; i < gmp3Units.length; i += 1) {
    const unit = gmp3Units[i];
    const existing = existingLicenses.rows[i];
    const name = textOrEmpty(unit.description) || 'GMP3 Lisansı';
    const registryRaw = textOrEmpty(unit.notes);
    const registry = registryRaw && registryRaw.length <= 40 ? registryRaw : null;
    const companyId = await matchSoftwareCompanyId(unit.hay);
    if (existing?.id) {
      await query(
        `
          update public.licenses
          set
            is_active = true,
            name = coalesce(nullif($2, ''), name),
            registry_number = coalesce(nullif($3, ''), registry_number),
            software_company_id = coalesce($4::uuid, software_company_id),
            starts_at = $5::date,
            ends_at = $6::date,
            expires_at = $6::date
          where id = $1
        `,
        [existing.id, name, registry, companyId, start, end],
      );
      continue;
    }
    if (registry) {
      const dup = await query(
        `
          select id
          from public.licenses
          where customer_id = $1
            and lower(coalesce(registry_number, '')) = lower($2)
            and coalesce($2, '') <> ''
          limit 1
        `,
        [customerId, registry],
      );
      if (dup.rows[0]?.id) {
        await query(
          `
            update public.licenses
            set source_invoice_id = coalesce(source_invoice_id, $2::uuid), is_active = true
            where id = $1
          `,
          [dup.rows[0].id, id],
        );
        continue;
      }
    }
    const licenseId = await insertIssuedRow('licenses', {
      customer_id: customerId,
      name,
      license_type: 'gmp3',
      software_company_id: companyId,
      registry_number: registry,
      starts_at: start,
      ends_at: end,
      expires_at: end,
      is_active: true,
      created_by: createdBy,
      source_invoice_id: id,
    });
    if (licenseId) licensesCreated += 1;
  }
  const extraLicenseIds = existingLicenses.rows
    .slice(gmp3Units.length)
    .map((r) => r.id);
  if (extraLicenseIds.length) {
    await query(
      `update public.licenses set is_active = false where id = any($1::uuid[])`,
      [extraLicenseIds],
    );
  }
  if (!gmp3Units.length && existingLicenses.rows.length) {
    await query(
      `update public.licenses set is_active = false where source_invoice_id = $1`,
      [id],
    );
  }

  return {
    lines: lineUnits.length,
    licenses: gmp3Units.length,
    linesCreated,
    licensesCreated,
  };
}

async function syncIssuedHatGmp3FromInvoiceItems(rows, user) {
  const ids = [
    ...new Set(
      (Array.isArray(rows) ? rows : [])
        .map((row) => String(row?.invoice_id || '').trim())
        .filter(Boolean),
    ),
  ];
  const summary = { lines: 0, licenses: 0 };
  for (const invoiceId of ids) {
    const result = await syncIssuedHatGmp3FromInvoice(invoiceId, user);
    summary.lines += Number(result.lines || 0);
    summary.licenses += Number(result.licenses || 0);
  }
  return summary;
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
  const nextBankStatus = String(values?.bank_approval_status || '').trim();
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
  const onlyBankApprovalUpdate =
    nextBankStatus === 'approved' &&
    Object.keys(values || {}).every((key) =>
      [
        'bank_approval_status',
        'bank_approved_at',
        'bank_approved_by',
        'stock_registry_number',
      ].includes(key),
    );
  const onlyBankApprovalReset =
    nextBankStatus === 'pending' &&
    Object.keys(values || {}).every((key) =>
      ['bank_approval_status', 'bank_approved_at', 'bank_approved_by'].includes(key),
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
  if (
    onlyApprovalUpdate ||
    onlyApprovalReset ||
    onlyBankApprovalUpdate ||
    onlyBankApprovalReset ||
    onlyApprovalDocumentUpdate
  ) {
    return;
  }

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
    const op = String(body.op || req.query?.op || '').trim();
    const table = String(body.table || '').trim();

    if (!op) return badRequest(req, res, 'op zorunludur.');
    if (op === 'clearIssuedLinesAndLicenses') {
      if (user.role !== 'admin') {
        return forbidden(req, res, 'Yalnızca yönetici hat ve GMP3 listesini temizleyebilir.');
      }
      if (!hasPageAccess(user, 'urunler') && !hasPageAccess(user, 'musteriler')) {
        return forbidden(req, res);
      }
      const confirm = String(body.confirm || '').trim();
      if (confirm !== 'SİL') {
        return badRequest(req, res, 'Onay metni hatalı. SİL yazın.');
      }

      try {
        const okTable = await ensureInvoiceItemsTable();
        if (okTable) {
          await query(
            `
              delete from public.invoice_items
              where source_table in ('lines', 'licenses')
            `,
          );
        }
      } catch (_) {}

      try {
        await query(`delete from public.line_transfers`);
      } catch (_) {}
      await query(`delete from public.lines`);
      await query(`delete from public.licenses`);
      return ok(req, res, { ok: true });
    }

    if (op === 'parseTsmLog') {
      if (!hasPageAccess(user, 'tsm_log') && !hasPageAccess(user, 'formlar')) {
        return forbidden(req, res, 'TSM Log için yetkiniz yok.');
      }
      try {
        return ok(req, res, parseTsmLogRequestBody(body));
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Excel okunamadı.';
        if (error?.statusCode === 400 || /Excel|sayfa|format|Unsupported/i.test(message)) {
          return badRequest(req, res, message.startsWith('Excel') ? message : `Excel okunamadı: ${message}`);
        }
        throw error;
      }
    }
    if (op === 'uploadServiceImage') {
      if (!hasPageAccess(user, 'servis')) return forbidden(req, res);
      try {
        return ok(req, res, await uploadServiceImage(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'uploadProductImage') {
      if (
        !hasPageAccess(user, 'e_fatura') &&
        !hasPageAccess(user, 'urunler') &&
        !hasPageAccess(user, 'teklif')
      ) {
        return forbidden(req, res);
      }
      try {
        return ok(req, res, await uploadProductImage(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'uploadQuoteLogo') {
      if (!hasPageAccess(user, 'teklif') && !hasPageAccess(user, 'e_fatura')) {
        return forbidden(req, res);
      }
      try {
        return ok(req, res, await uploadQuoteLogo(body));
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
      op === 'ensureApplicationFormSalesInvoice' ||
      op === 'linkApplicationFormsBatchToInvoice'
    ) {
      if (
        !hasPageAccess(user, 'formlar') &&
        !hasPageAccess(user, 'e_fatura') &&
        !hasPageAccess(user, 'faturalama')
      ) {
        return forbidden(req, res);
      }
      try {
        if (op === 'linkApplicationFormsBatchToInvoice') {
          return ok(req, res, await linkApplicationFormsBatchToInvoice(body));
        }
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
    if (op === 'processMutakabat') {
      if (!hasPageAccess(user, 'mutakabat')) return forbidden(req, res);
      try {
        return ok(req, res, await runProcessMutakabat(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'exportMutakabatExcel') {
      if (!hasPageAccess(user, 'mutakabat')) return forbidden(req, res);
      try {
        return ok(req, res, await runExportMutakabatExcel(body));
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'createInvoicePaymentLink') {
      if (
        !hasPageAccess(user, 'faturalama') &&
        !hasPageAccess(user, 'e_fatura')
      ) {
        return forbidden(req, res);
      }
      try {
        const invoiceIds = Array.isArray(body.invoiceIds)
          ? body.invoiceIds
          : body.invoiceId
            ? [body.invoiceId]
            : [];
        return ok(
          req,
          res,
          await createInvoicePaymentLink({
            invoiceIds,
            createdBy: user?.id || null,
            req,
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'sendInvoicePaymentLinkEmail') {
      if (
        !hasPageAccess(user, 'faturalama') &&
        !hasPageAccess(user, 'e_fatura')
      ) {
        return forbidden(req, res);
      }
      try {
        const invoiceIds = Array.isArray(body.invoiceIds)
          ? body.invoiceIds
          : body.invoiceId
            ? [body.invoiceId]
            : [];
        return ok(
          req,
          res,
          await sendInvoicePaymentLinkEmail({
            invoiceIds,
            email: body.email,
            createdBy: user?.id || null,
            req,
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400 || error?.statusCode === 502) {
          return badRequest(req, res, error.message);
        }
        throw error;
      }
    }
    if (op === 'markPosPaymentSettled') {
      if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await markPosPaymentSettled({
            linkId: body.linkId || body.id,
            settled: body.settled !== false && body.settled !== 'false',
            createdBy: user?.id || null,
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'dismissPosCollection') {
      if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await dismissPosCollection({
            linkId: body.linkId || body.id,
            dismissed: body.dismissed !== false && body.dismissed !== 'false',
            createdBy: user?.id || null,
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'upsertRecurringBillingPlan') {
      if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await upsertRecurringBillingPlan(body, user),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'setRecurringBillingPlanActive') {
      if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await setRecurringBillingPlanActive({
            id: body.id,
            isActive: body.isActive !== false && body.isActive !== 'false',
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'runRecurringBilling') {
      if (!requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await runRecurringBilling({
            planId: body.planId || body.id || null,
            force: body.force === true || body.force === 'true',
            createdBy: user?.id || null,
            req,
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'refundInvoicePosPayment') {
      if (
        !requireAnyPage(req, user, ['faturalama', 'e_fatura'], res)
      ) {
        return;
      }
      try {
        return ok(
          req,
          res,
          await refundInvoicePosPayment({
            invoiceId: body.invoiceId,
            transactionId: body.transactionId || null,
            amount: body.amount != null ? Number(body.amount) : null,
            createdBy: user?.id || null,
            crmOnly: body.crmOnly === true || body.crmOnly === 'true',
          }),
        );
      } catch (error) {
        if (error?.statusCode === 400) return badRequest(req, res, error.message);
        throw error;
      }
    }
    if (op === 'convertQuoteToInvoice') {
      if (!hasPageAccess(user, 'teklif')) return forbidden(req, res);
      try {
        return ok(req, res, await convertQuoteToInvoice(body, user));
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

    if (table === 'mutakabat_records') {
      await ensureMutakabatRecordsTable();
    }
    if (table === 'mutakabat_price_settings') {
      await ensureMutakabatPriceSettingsTable();
    }
    if (table === 'quotes' || table === 'quote_items') {
      await ensureQuotesTables();
    }
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
      await ensureApplicationFormsCreatedByRepair();
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
    if (table === 'bkm_acquirers') {
      await ensureBkmAcquirersTable();
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
      await ensureIssuedSourceInvoiceColumns();
      columnsCache.delete('lines');
    }
    if (table === 'licenses') {
      await ensureIssuedSourceInvoiceColumns();
      columnsCache.delete('licenses');
    }
    if (table === 'work_order_signatures') {
      await ensureWorkOrderSignaturesTable();
    }
    if (table === 'finance_accounts' || table === 'finance_transactions') {
      await ensureFinanceTables();
    }
    if (table === 'invoices') {
      await ensureInvoicePricesIncludeVatColumn();
      await ensureIssuedSourceInvoiceColumns();
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
          if (body.skipInvoiceLink === true || body.skipInvoiceLink === 'true') {
            invoiceLink = {
              created: false,
              linked: false,
              reason: 'skipped',
            };
          } else {
            invoiceLink = await maybeLinkApplicationFormInvoice(result.id);
          }
        } else {
          invoiceLink = {
            created: false,
            linked: false,
            reason: 'missing_customer',
          };
        }
      } else if (
        ['scrap_forms', 'fault_forms', 'transfer_forms'].includes(table) &&
        result.id &&
        !textOrEmpty(values?.id)
      ) {
        // Yalnızca yeni kayıt: açık satış e-faturası oluştur.
        if (body.skipInvoiceLink === true || body.skipInvoiceLink === 'true') {
          invoiceLink = {
            created: false,
            linked: false,
            reason: 'skipped',
          };
        } else {
          invoiceLink = await maybeLinkServiceFormInvoice(table, result.id);
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
      let issued = null;
      if (table === 'invoice_items') {
        try {
          issued = await syncIssuedHatGmp3FromInvoiceItems(rows, user);
        } catch (_) {
          issued = null;
        }
      }
      return ok(req, res, { ok: true, ...result, ...(issued ? { issued } : {}) });
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
      if (table === 'invoices' && Object.prototype.hasOwnProperty.call(values || {}, 'is_active')) {
        const invoiceIds = idsFromFilters(filters, 'id');
        const nextActive = values.is_active === true || values.is_active === 'true';
        try {
          await setIssuedHatGmp3ActiveForInvoices(invoiceIds, nextActive);
          if (nextActive) {
            for (const invoiceId of invoiceIds) {
              await syncIssuedHatGmp3FromInvoice(invoiceId, user);
            }
          }
        } catch (_) {}
      }
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
      if (table === 'invoices') {
        try {
          await deleteIssuedHatGmp3ForInvoices(idsFromFilters(filters, 'id'));
        } catch (_) {}
      }
      await deleteWhere({ table, filters });
      return ok(req, res, { ok: true });
    }

    return badRequest(req, res, `Bilinmeyen op: ${op}`);
  } catch (error) {
    return serverError(req, res, error);
  }
};

module.exports.linkApplicationFormDeviceToInvoice =
  linkApplicationFormDeviceToInvoice;
module.exports.linkApplicationFormsBatchToInvoice =
  linkApplicationFormsBatchToInvoice;
module.exports.createSalesInvoiceForServiceForm =
  createSalesInvoiceForServiceForm;
