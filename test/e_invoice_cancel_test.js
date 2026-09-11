const test = require('node:test');
const assert = require('node:assert/strict');
const { testUtils } = require('../api/e-invoice');

test('gönderilmiş tahsilatsız satış Maliye’den iptal edilebilir', () => {
  assert.equal(
    testUtils.canCancelInvoiceOnMaliye({
      is_active: true,
      status: 'open',
      invoice_type: 'sales',
      e_invoice_status: 'sent',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
      paid_amount: 0,
    }),
    true,
  );
});

test('tahsilatlı veya gelen fatura Maliye iptaline kapalıdır', () => {
  assert.equal(
    testUtils.canCancelInvoiceOnMaliye({
      is_active: true,
      status: 'open',
      invoice_type: 'sales',
      e_invoice_status: 'sent',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
      paid_amount: 10,
    }),
    false,
  );
  assert.equal(
    testUtils.canCancelInvoiceOnMaliye({
      is_active: true,
      status: 'open',
      invoice_type: 'purchase',
      e_invoice_status: 'sent',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
    }),
    false,
  );
  assert.equal(
    testUtils.canCancelInvoiceInCrm({
      is_active: true,
      status: 'open',
      invoice_type: 'sales',
      e_invoice_status: 'received',
    }),
    false,
  );
});

test('gönderilmemiş açık satış CRM’den iptal edilebilir', () => {
  assert.equal(
    testUtils.canCancelInvoiceInCrm({
      is_active: true,
      status: 'open',
      invoice_type: 'sales',
      e_invoice_status: 'not_sent',
      paid_amount: 0,
    }),
    true,
  );
  assert.equal(
    testUtils.canCancelInvoiceOnMaliye({
      is_active: true,
      status: 'open',
      invoice_type: 'sales',
      e_invoice_status: 'not_sent',
      paid_amount: 0,
    }),
    false,
  );
});

test('iptal edilmiş fatura tekrar gönderilmez', () => {
  assert.equal(
    testUtils.canSendInvoiceToEnvironment(
      { invoice_type: 'sales', status: 'cancelled', e_invoice_status: 'cancelled' },
      'production',
    ),
    false,
  );
});

test('Maliye zaten iptal mesajı tanınır', () => {
  assert.equal(
    testUtils.looksLikeAlreadyCancelledError({
      message: 'Bu fatura zaten iptal edilmiştir.',
    }),
    true,
  );
  assert.equal(
    testUtils.looksLikeAlreadyCancelledError({
      message: 'Fatura bulunamadı',
    }),
    false,
  );
});
