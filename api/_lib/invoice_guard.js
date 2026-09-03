const { query } = require('./db');

const PROTECTED_E_INVOICE_STATUSES = new Set([
  'sent',
  'received',
  'manual',
  'manual_sent',
  'prepared',
]);

const PROTECTED_UPDATE_ALLOWLIST = new Set([
  'notes',
  'akinsoft_sync_status',
  'akinsoft_synced_at',
  'akinsoft_sync_error',
  'erp_invoice_number',
  'e_invoice_status',
  'e_invoice_number',
  'e_invoice_uuid',
  'e_invoice_environment',
  'e_invoice_sent_at',
  'e_invoice_archived_at',
  'e_invoice_pdf_path',
  'customer_sent_at',
  'customer_sent_via',
  'is_active',
]);

function looksLikeAkinsoftInvoiceNumber(value) {
  const no = String(value || '').trim().toUpperCase();
  if (!no) return false;
  return (
    no.startsWith('DA') ||
    no.startsWith('SF') ||
    no.startsWith('AKN-') ||
    no.startsWith('MSF')
  );
}

function isTruthyFlag(value) {
  return value === true || value === 'true';
}

function isFalsyFlag(value) {
  return value === false || value === 'false';
}

function invoiceProtectionReason(row, { includeCustomerSent = true } = {}) {
  if (!row) return null;
  const eStatus = String(row.e_invoice_status || '').trim().toLowerCase();
  if (PROTECTED_E_INVOICE_STATUSES.has(eStatus)) {
    return 'Maliye / e-fatura kaydı var';
  }
  if (String(row.e_invoice_uuid || '').trim()) return 'Maliye UUID kaydı var';
  if (String(row.e_invoice_number || '').trim()) return 'E-fatura numarası var';
  if (String(row.akinsoft_sync_status || '').trim().toLowerCase() === 'synced') {
    return 'SAP kaydı var';
  }
  if (looksLikeAkinsoftInvoiceNumber(row.erp_invoice_number)) {
    return 'SAP fatura numarası var';
  }
  if (looksLikeAkinsoftInvoiceNumber(row.invoice_number)) {
    return 'SAP fatura numarası var';
  }
  if (Number(row.paid_amount || 0) > 0.009) return 'Tahsilat kaydı var';
  const status = String(row.status || '').trim().toLowerCase();
  if (status === 'paid' || status === 'partial') return 'Tahsilat kaydı var';
  if (includeCustomerSent && row.customer_sent_at) return 'Müşteriye iletilmiş';
  return null;
}

function isProtectedInvoice(row, options) {
  return Boolean(invoiceProtectionReason(row, options));
}

function uniqueIds(values) {
  const seen = new Set();
  const ids = [];
  const list = Array.isArray(values) ? values : [values];
  for (const value of list) {
    const id = String(value || '').trim();
    if (
      !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(
        id,
      )
    ) {
      continue;
    }
    const key = id.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    ids.push(id);
  }
  return ids;
}

function idsFromFilterList(filters, col = 'id') {
  const list = Array.isArray(filters) ? filters : [];
  const found = list.find((f) => f && String(f.col || '').trim() === col);
  if (!found) return [];
  const op = String(found.op || '').trim();
  if (op === 'eq') return uniqueIds([found.value]);
  if (op === 'in') return uniqueIds(found.value);
  return [];
}

function guardError(message) {
  const error = new Error(message);
  error.statusCode = 400;
  return error;
}

function assertInvoiceIdFilters(filters, { max = 200 } = {}) {
  const list = Array.isArray(filters) ? filters : [];
  if (!list.length) {
    throw guardError('Fatura işlemi için id filtresi zorunludur.');
  }
  const onlyId = list.every((f) => {
    const col = String(f?.col || '').trim();
    const op = String(f?.op || '').trim();
    return col === 'id' && (op === 'eq' || op === 'in');
  });
  if (!onlyId) {
    throw guardError(
      'Fatura güncelleme/silme yalnızca fatura id’si ile yapılabilir. Toplu kayıp riski engellendi.',
    );
  }
  const ids = idsFromFilterList(list, 'id');
  if (!ids.length) {
    throw guardError('Geçerli fatura id’si yok.');
  }
  if (ids.length > max) {
    throw guardError(`Tek seferde en fazla ${max} fatura işlenebilir.`);
  }
  return ids;
}

async function loadInvoicesForGuard(ids) {
  const list = uniqueIds(ids);
  if (!list.length) return [];
  const result = await query(
    `
      select
        id,
        invoice_number,
        status,
        is_active,
        paid_amount,
        e_invoice_status,
        e_invoice_uuid,
        e_invoice_number,
        akinsoft_sync_status,
        erp_invoice_number,
        customer_sent_at
      from public.invoices
      where id = any($1::uuid[])
    `,
    [list],
  );
  return result.rows;
}

function denyHardDelete() {
  throw guardError(
    'Faturalar kalıcı silinemez. Yanlışlıkla kaybolmayı önlemek için kayıt pasife alınır; Pasif filtresinden geri getirilir.',
  );
}

async function assertInvoicesHardDeleteDenied() {
  denyHardDelete();
}

async function assertInvoicesCanDeactivate(ids) {
  const rows = await loadInvoicesForGuard(ids);
  const blocked = rows.filter(isProtectedInvoice);
  if (!blocked.length) return rows;
  const sample = blocked
    .slice(0, 3)
    .map((row) => row.invoice_number || row.id)
    .join(', ');
  const reason = invoiceProtectionReason(blocked[0]);
  throw guardError(
    blocked.length === 1
      ? `${sample} pasife alınamaz (${reason}). Kayıt korunur.`
      : `${blocked.length} fatura pasife alınamaz (${reason}). Örnek: ${sample}`,
  );
}

function blockedProtectedUpdateKeys(values) {
  return Object.keys(values || {}).filter(
    (key) => key !== 'id' && !PROTECTED_UPDATE_ALLOWLIST.has(key),
  );
}

async function assertInvoiceUpdateAllowed({ ids, values }) {
  const next = values || {};
  const keys = Object.keys(next).filter((key) => key !== 'id');
  if (!keys.length) return;

  const rows = await loadInvoicesForGuard(ids);
  if (isFalsyFlag(next.is_active)) {
    await assertInvoicesCanDeactivate(ids);
  }
  if (String(next.status || '').trim().toLowerCase() === 'cancelled') {
    const blocked = rows.filter(isProtectedInvoice);
    if (blocked.length) {
      throw guardError(
        'Maliye, SAP veya tahsilatı olan fatura iptal edilemez. Kayıt korunur.',
      );
    }
  }

  const identityKeys = blockedProtectedUpdateKeys(next);
  if (!identityKeys.length) return;
  const blocked = rows.filter((row) =>
    isProtectedInvoice(row, { includeCustomerSent: false }),
  );
  if (!blocked.length) return;
  throw guardError(
    'Maliye / SAP / tahsilat kaydı olan fatura içeriği değiştirilemez. Yanlışlıkla kaybolmayı önlemek için kilitlendi.',
  );
}

async function assertInvoiceUpsertAllowed(values) {
  const id = String(values?.id || '').trim();
  if (!id) return;
  await assertInvoiceUpdateAllowed({ ids: [id], values });
}

async function assertInvoiceItemsDeleteAllowed(filters) {
  const invoiceIds = idsFromFilterList(filters, 'invoice_id');
  const itemIds = idsFromFilterList(filters, 'id');
  let ids = invoiceIds;
  if (!ids.length && itemIds.length) {
    const result = await query(
      `
        select distinct invoice_id
        from public.invoice_items
        where id = any($1::uuid[])
      `,
      [itemIds],
    );
    ids = uniqueIds(result.rows.map((row) => row.invoice_id));
  }
  if (!ids.length) {
    throw guardError(
      'Fatura kalemleri yalnızca ilgili fatura id’si ile silinebilir.',
    );
  }
  const rows = await loadInvoicesForGuard(ids);
  const blocked = rows.filter((row) =>
    isProtectedInvoice(row, { includeCustomerSent: false }),
  );
  if (!blocked.length) return;
  throw guardError(
    'Maliye / SAP / tahsilat kaydı olan faturanın kalemleri silinemez. Kayıt korunur.',
  );
}

module.exports = {
  PROTECTED_E_INVOICE_STATUSES,
  PROTECTED_UPDATE_ALLOWLIST,
  isProtectedInvoice,
  invoiceProtectionReason,
  uniqueIds,
  idsFromFilterList,
  assertInvoiceIdFilters,
  assertInvoicesHardDeleteDenied,
  assertInvoicesCanDeactivate,
  assertInvoiceUpdateAllowed,
  assertInvoiceUpsertAllowed,
  assertInvoiceItemsDeleteAllowed,
  blockedProtectedUpdateKeys,
};
