const AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN = 20;
const AKINSOFT_SERIAL_PAD_WIDTHS = [6, 8, 9, 10, 11, 12];

const AKINSOFT_CLOSED_FLAG_FIELDS = [
  'KF_DURUMU',
  'KF_DURUM',
  'KAPALI_DURUMU',
  'KAPALI_FATURA_DURUMU',
  'KAPALI_FATURA',
  'FATURA_KAPALI',
  'KAPALI_MI',
  'KAPALI',
  'KAPANDI',
  'ODENDI',
  'ODEME_DURUMU',
  'DURUMU',
  'STATU',
  'STATUS',
];

function textOrNull(value) {
  const text = String(value ?? '').trim();
  return text ? text : null;
}

function akinsoftInvoiceSerialCore(value) {
  const no = textOrNull(value);
  if (!no) return null;
  const lastDash = no.lastIndexOf('-');
  if (lastDash < 0) return no.toLocaleUpperCase('tr-TR');
  const prefix = no.slice(0, lastDash + 1);
  const serial = no.slice(lastDash + 1);
  if (!/^\d+$/.test(serial)) return no.toLocaleUpperCase('tr-TR');
  return `${prefix}${Number(serial)}`.toLocaleUpperCase('tr-TR');
}

function akinsoftCariHrEvrakVariants(invoiceNumber) {
  const no = textOrNull(invoiceNumber);
  if (!no) return [];
  const variants = [];
  const seen = new Set();
  const push = (value) => {
    const text = textOrNull(value);
    if (!text) return;
    const key = text.toLocaleUpperCase('tr-TR');
    if (seen.has(key)) return;
    seen.add(key);
    variants.push(text);
  };

  push(no);
  if (no.length > AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN) {
    push(no.slice(0, AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN));
  }

  const lastDash = no.lastIndexOf('-');
  if (lastDash >= 0) {
    const prefix = no.slice(0, lastDash + 1);
    const serial = no.slice(lastDash + 1);
    if (/^\d+$/.test(serial)) {
      const unpadded = String(Number(serial));
      push(prefix + unpadded);
      for (const width of AKINSOFT_SERIAL_PAD_WIDTHS) {
        push(prefix + unpadded.padStart(width, '0'));
      }
    }
  }

  for (const current of [...variants]) {
    if (current.length > AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN) {
      push(current.slice(0, AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN));
    }
  }
  return variants;
}

function resolveAkinsoftCariHrInvoiceNumber(evrakNo, invoiceNumbers) {
  const key = textOrNull(evrakNo);
  if (!key) return null;
  const list = (Array.isArray(invoiceNumbers) ? invoiceNumbers : [])
    .map((no) => textOrNull(no))
    .filter(Boolean);
  if (list.includes(key)) return key;

  const core = akinsoftInvoiceSerialCore(key);
  const coreMatches = list.filter((no) => akinsoftInvoiceSerialCore(no) === core);
  if (coreMatches.length === 1) return coreMatches[0];

  const prefixMatches = list.filter(
    (no) => no.length > key.length && no.startsWith(key),
  );
  if (prefixMatches.length === 1) return prefixMatches[0];
  return prefixMatches.length === 0 && coreMatches.length === 0 ? key : null;
}

function mapCariHrRowToInvoiceNumber(row, invoiceNumbers, invoiceNoBySourceId) {
  const entegrasyon = textOrNull(row?.ENTEGRASYON ?? row?.entegrasyon);
  const fto = entegrasyon ? /^FTO_(\d+)$/i.exec(entegrasyon) : null;
  if (fto && invoiceNoBySourceId instanceof Map) {
    const mapped = invoiceNoBySourceId.get(fto[1]);
    if (mapped) return mapped;
  }
  const blft = row?.BLFTKODU ?? row?.blftkodu;
  if (blft != null && invoiceNoBySourceId instanceof Map) {
    const mapped = invoiceNoBySourceId.get(String(blft));
    if (mapped) return mapped;
  }
  return resolveAkinsoftCariHrInvoiceNumber(
    row?.EVRAK_NO ?? row?.evrak_no,
    invoiceNumbers,
  );
}

function readAkinsoftClosedFlag(row, pick, parseAkinsoftBool) {
  if (!row || typeof pick !== 'function' || typeof parseAkinsoftBool !== 'function') {
    return null;
  }
  for (const name of AKINSOFT_CLOSED_FLAG_FIELDS) {
    const raw = pick(row, [name]);
    if (raw == null || String(raw).trim() === '') continue;
    const flag = parseAkinsoftBool(raw);
    if (flag === true) return true;
  }
  for (const name of ['KAPALI', 'KAPANDI', 'KAPALI_FATURA']) {
    const flag = parseAkinsoftBool(pick(row, [name]));
    if (flag === false) return false;
  }
  return null;
}

function resolveAkinsoftInvoicePayment(
  row,
  currency,
  grandTotal,
  { pick, numberOrZero, parseAkinsoftBool, tolerance = 0.02 } = {},
) {
  if (typeof pick !== 'function' || typeof numberOrZero !== 'function') {
    return { paidAmount: 0, status: 'open', reliable: false, source: 'invoice' };
  }
  const parseBool =
    typeof parseAkinsoftBool === 'function'
      ? parseAkinsoftBool
      : () => null;
  const remainingRaw = pick(
    row,
    currency === 'TRY'
      ? [
          'KPB_BAKIYE',
          'KPB_KALAN',
          'KPB_ACIK_TUTAR',
          'KPB_KALAN_TUTAR',
          'BAKIYE',
          'KALAN',
          'ACIK_TUTAR',
          'DVZ_BAKIYE',
        ]
      : [
          'DVZ_BAKIYE',
          'DVZ_KALAN',
          'DVZ_ACIK_TUTAR',
          'DVZ_KALAN_TUTAR',
          'DOVIZ_BAKIYE',
          'KPB_BAKIYE',
          'BAKIYE',
        ],
  );
  const remainingAmount = numberOrZero(remainingRaw);
  const paidRaw = pick(
    row,
    currency === 'TRY'
      ? [
          'KPB_TAHSILAT_TOPLAMI',
          'TAHSILAT_TOPLAMI',
          'TAHSIL_EDILEN',
          'ODEME_TOPLAMI',
          'KAPANAN_TUTAR',
          'KPB_KAPANAN',
          'DVZ_TAHSILAT_TOPLAMI',
        ]
      : [
          'DVZ_TAHSILAT_TOPLAMI',
          'DOVIZ_TAHSILAT_TOPLAMI',
          'KAPANAN_TUTAR',
          'KPB_TAHSILAT_TOPLAMI',
          'TAHSILAT_TOPLAMI',
        ],
  );
  const paidAmount = numberOrZero(paidRaw);
  const closedFlag = readAkinsoftClosedFlag(row, pick, parseBool);
  if (closedFlag === true) {
    return {
      paidAmount: grandTotal,
      status: 'paid',
      reliable: true,
      source: 'invoice',
    };
  }
  if (remainingRaw != null) {
    if (remainingAmount <= tolerance && grandTotal > 0) {
      return {
        paidAmount: grandTotal,
        status: 'paid',
        reliable: true,
        source: 'invoice',
      };
    }
    if (remainingAmount > 0 && grandTotal > 0) {
      const paid = Math.max(0, grandTotal - remainingAmount);
      return {
        paidAmount: paid,
        status: paid > 0 ? 'partial' : 'open',
        reliable: true,
        source: 'invoice',
      };
    }
  }
  if (paidRaw != null && paidAmount > 0 && paidAmount < grandTotal) {
    return {
      paidAmount,
      status: 'partial',
      reliable: true,
      source: 'invoice',
    };
  }
  if (
    paidRaw != null &&
    paidAmount >= grandTotal - tolerance &&
    grandTotal > 0
  ) {
    return {
      paidAmount: grandTotal,
      status: 'paid',
      reliable: true,
      source: 'invoice',
    };
  }
  return { paidAmount: 0, status: 'open', reliable: false, source: 'invoice' };
}

module.exports = {
  AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN,
  AKINSOFT_CLOSED_FLAG_FIELDS,
  akinsoftCariHrEvrakVariants,
  akinsoftInvoiceSerialCore,
  mapCariHrRowToInvoiceNumber,
  readAkinsoftClosedFlag,
  resolveAkinsoftCariHrInvoiceNumber,
  resolveAkinsoftInvoicePayment,
};
