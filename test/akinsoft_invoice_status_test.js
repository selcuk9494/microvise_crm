const assert = require('node:assert/strict');
const test = require('node:test');

const {
  akinsoftCariHrEvrakVariants,
  akinsoftInvoiceSerialCore,
  mapCariHrRowToInvoiceNumber,
  resolveAkinsoftCariHrInvoiceNumber,
  resolveAkinsoftInvoicePayment,
} = require('../api/_lib/akinsoft_invoice_status');

function pick(row, names, fallback = null) {
  if (!row) return fallback;
  for (const name of names) {
    if (row[name] != null && String(row[name]).trim() !== '') return row[name];
  }
  return fallback;
}

function numberOrZero(value) {
  const n = Number(value);
  return Number.isFinite(n) ? n : 0;
}

function parseAkinsoftBool(value) {
  const text = String(value ?? '').trim().toLocaleLowerCase('tr-TR');
  if (!text) return null;
  if (['1', 'true', 'evet', 'e', 'kapali', 'kapalı', 'odendi', 'ödendi'].includes(text)) {
    return true;
  }
  if (['0', 'false', 'hayir', 'hayır', 'h', 'acik', 'açık', 'odenmedi', 'ödenmedi'].includes(text)) {
    return false;
  }
  return null;
}

function paymentOf(row, currency, grandTotal) {
  return resolveAkinsoftInvoicePayment(row, currency, grandTotal, {
    pick,
    numberOrZero,
    parseAkinsoftBool,
    tolerance: 0.02,
  });
}

test('Wolvox pad’li fatura no aynı çekirdeğe iner', () => {
  assert.equal(
    akinsoftInvoiceSerialCore('2026-1-000000000069'),
    akinsoftInvoiceSerialCore('2026-1-69'),
  );
  assert.equal(akinsoftInvoiceSerialCore('2026-1-69'), '2026-1-69');
});

test('CARIHR EVRAK_NO varyantları kısa ve pad’li numarayı kapsar', () => {
  const variants = akinsoftCariHrEvrakVariants('2026-1-69');
  assert.ok(variants.includes('2026-1-69'));
  assert.ok(variants.includes('2026-1-000000000069'));
  assert.ok(akinsoftCariHrEvrakVariants('2026-1-000000000069').includes('2026-1-69'));
});

test('Pad’li tahsilat EVRAK_NO CRM/SAP kısa faturaya bağlanır', () => {
  assert.equal(
    resolveAkinsoftCariHrInvoiceNumber('2026-1-000000000069', ['2026-1-69']),
    '2026-1-69',
  );
  assert.equal(
    resolveAkinsoftCariHrInvoiceNumber('2026-1-69', ['2026-1-000000000069']),
    '2026-1-000000000069',
  );
});

test('KAPALI=0 olsa bile KF Durumu Kapalı faturayı kapatır', () => {
  const result = paymentOf(
    { KAPALI: 0, KF_DURUMU: 'Kapalı' },
    'USD',
    350,
  );
  assert.equal(result.status, 'paid');
  assert.equal(result.reliable, true);
  assert.equal(result.paidAmount, 350);
});

test('Yalnızca KAPALI=0 ve bakiye yoksa durumu uydurmaz', () => {
  const result = paymentOf({ KAPALI: 0 }, 'USD', 350);
  assert.equal(result.status, 'open');
  assert.equal(result.reliable, false);
});

test('FTO entegrasyonu tahsilatı faturaya bağlar', () => {
  const invoiceNoBySourceId = new Map([['88421', '2026-1-69']]);
  assert.equal(
    mapCariHrRowToInvoiceNumber(
      { EVRAK_NO: 'THS-99', ENTEGRASYON: 'FTO_88421', KPB_ATUT: 350 },
      ['2026-1-69'],
      invoiceNoBySourceId,
    ),
    '2026-1-69',
  );
});

test('Wolvox FTK kapama tahsilatı faturaya bağlanır', () => {
  const invoiceNoBySourceId = new Map([['7770', '2026-1-00000000069']]);
  assert.equal(
    mapCariHrRowToInvoiceNumber(
      {
        EVRAK_NO: 'STŞ-2026-000113',
        ENTEGRASYON: 'FTK_7770',
        KPB_ATUT: 17046.58,
        DVZ_ATUT: 350,
      },
      ['2026-1-00000000069'],
      invoiceNoBySourceId,
    ),
    '2026-1-00000000069',
  );
});
