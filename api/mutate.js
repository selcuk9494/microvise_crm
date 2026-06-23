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
  const objectPath = `${safeStorageSegment(folder, 'uploads')}/${Date.now()}-${random}.${ext}`;
  const uploadUrl = `${supabaseUrl}/storage/v1/object/${serviceImageBucket}/${encodeURIComponent(
    objectPath,
  ).replace(/%2F/g, '/')}`;

  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      'cache-control': '3600',
      'content-type': contentType,
      'x-upsert': 'false',
    },
    body: bytes,
  });

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
    }
    if (table === 'fault_forms') {
      await ensureFaultFormsTable();
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
      if (table === 'application_forms' && result.id) {
        const after = await selectApplicationFormAuditRow(result.id);
        await insertApplicationFormLog({
          formId: result.id,
          action: before ? 'update' : 'create',
          before,
          after,
          user,
        });
      }
      return ok(req, res, { ok: true, ...result });
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
      }
      return ok(req, res, { ok: true });
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
