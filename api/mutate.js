const crypto = require('crypto');

const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
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
} = require('./_lib/schema');
const {
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
  products: 'urunler',
  stock_movements: ['urunler', 'formlar'],
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
  tax_rates: 'tanimlamalar',
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
  invoices: 'faturalama',
  invoice_items: ['faturalama', 'urunler', 'formlar', 'is_emirleri'],
  transactions: 'faturalama',
  users: 'personel',
};

const columnsCache = new Map();
const columnsMetaCache = new Map();

function requireAnyPage(user, pageKeys, res) {
  const keys = Array.isArray(pageKeys)
    ? pageKeys
    : [String(pageKeys || '').trim()].filter((k) => k.length > 0);
  if (!keys.length) return true;
  for (const key of keys) {
    if (hasPageAccess(user, key)) return true;
  }
  forbidden(res, 'Erişim yetkiniz yok.');
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

async function upsertRow({ table, values, returningRow }) {
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const picked = pickValues(values, columns);

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

async function updateWhere({ table, values, filters }) {
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const picked = pickValues(values, columns);
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

async function insertMany({ table, rows }) {
  if (!Array.isArray(rows) || rows.length === 0) return { inserted: 0 };
  const columns = await getColumns(table);
  const meta = await getColumnMeta(table);
  const hasIdColumn = columns.includes('id');

  for (const row of rows) {
    const values = pickValues(row, columns);
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

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return methodNotAllowed(res, 'POST');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);

    const body = await readJson(req);
    const op = String(body.op || '').trim();
    const table = String(body.table || '').trim();

    if (!op) return badRequest(res, 'op zorunludur.');
    if (!table) return badRequest(res, 'table zorunludur.');
    if (!allowedTables.has(table)) return badRequest(res, 'table desteklenmiyor.');

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

    const requiredPage = tablePermissions[table] || null;
    if (requiredPage && !requireAnyPage(user, requiredPage, res)) return;

    if (op === 'upsert') {
      const values = body.values;
      const returningRow = body.returning === 'row';
      const result = await upsertRow({ table, values, returningRow });
      return ok(res, { ok: true, ...result });
    }

    if (op === 'delete') {
      const id = String(body.id || '').trim();
      if (!id) return badRequest(res, 'id zorunludur.');
      await deleteRow({ table, id });
      return ok(res, { ok: true });
    }

    if (op === 'insertMany') {
      const rows = body.rows;
      const result = await insertMany({ table, rows });
      return ok(res, { ok: true, ...result });
    }

    if (op === 'updateWhere') {
      const values = body.values;
      const filters = body.filters;
      await updateWhere({ table, values, filters });
      return ok(res, { ok: true });
    }

    if (op === 'deleteWhere') {
      const filters = body.filters;
      await deleteWhere({ table, filters });
      return ok(res, { ok: true });
    }

    return badRequest(res, `Bilinmeyen op: ${op}`);
  } catch (error) {
    return serverError(res, error);
  }
};
