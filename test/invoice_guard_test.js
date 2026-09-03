const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  isProtectedInvoice,
  invoiceProtectionReason,
  blockedProtectedUpdateKeys,
  assertInvoiceIdFilters,
} = require('../api/_lib/invoice_guard');

test('Maliye, SAP ve tahsilatlı faturalar korunur', () => {
  assert.equal(
    invoiceProtectionReason({ e_invoice_status: 'sent' }),
    'Maliye / e-fatura kaydı var',
  );
  assert.equal(
    invoiceProtectionReason({ e_invoice_uuid: 'abc' }),
    'Maliye UUID kaydı var',
  );
  assert.equal(
    invoiceProtectionReason({ akinsoft_sync_status: 'synced' }),
    'SAP kaydı var',
  );
  assert.equal(
    invoiceProtectionReason({ paid_amount: 10 }),
    'Tahsilat kaydı var',
  );
  assert.equal(
    invoiceProtectionReason({ customer_sent_at: '2026-09-03' }),
    'Müşteriye iletilmiş',
  );
  assert.equal(isProtectedInvoice({ status: 'open', paid_amount: 0 }), false);
});

test('korunan faturada yalnızca izinli alanlar güncellenir', () => {
  assert.deepEqual(
    blockedProtectedUpdateKeys({
      e_invoice_status: 'sent',
      customer_sent_at: '2026-09-03',
      is_active: true,
    }),
    [],
  );
  assert.deepEqual(
    blockedProtectedUpdateKeys({
      invoice_number: '2026-1-70',
      customer_id: 'x',
    }).sort(),
    ['customer_id', 'invoice_number'],
  );
});

test('fatura filtresi yalnızca id kabul eder', () => {
  const ids = assertInvoiceIdFilters([
    {
      col: 'id',
      op: 'in',
      value: ['11111111-1111-1111-1111-111111111111'],
    },
  ]);
  assert.equal(ids.length, 1);
  assert.throws(
    () =>
      assertInvoiceIdFilters([{ col: 'status', op: 'eq', value: 'open' }]),
    /id/,
  );
});
