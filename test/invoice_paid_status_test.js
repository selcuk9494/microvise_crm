const assert = require('node:assert/strict');
const test = require('node:test');

const { invoiceStatusAfterPayment } = require('../api/_lib/invoice_paid_status');

test('Maliye gönderilmeden POS tahsilatı faturayı kapatmaz', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 1250,
      grandTotal: 1250,
      invoiceType: 'sales',
      eInvoiceStatus: 'not_sent',
    }),
    'open',
  );
});

test('Maliye gönderildikten sonra tam tahsilat faturayı kapatır', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 1250,
      grandTotal: 1250,
      invoiceType: 'sales',
      eInvoiceStatus: 'sent',
    }),
    'paid',
  );
});

test('Manuel gönderildi işaretinden sonra tam tahsilat kapatır', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 1250,
      grandTotal: 1250,
      invoiceType: 'sales',
      eInvoiceStatus: 'manual_sent',
    }),
    'paid',
  );
});

test('Manuel kesildi de kapatmaya izin verir', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 1250,
      grandTotal: 1250,
      invoiceType: 'sales',
      eInvoiceStatus: 'manual',
    }),
    'paid',
  );
});

test('Kısmi tahsilat Maliye beklerken partial kalır', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 400,
      grandTotal: 1250,
      invoiceType: 'sales',
      eInvoiceStatus: 'not_sent',
    }),
    'partial',
  );
});

test('Alış faturası Maliye şartı olmadan kapanır', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'open',
      paidAmount: 100,
      grandTotal: 100,
      invoiceType: 'purchase',
      eInvoiceStatus: 'not_sent',
    }),
    'paid',
  );
});

test('taslak ve iptal durumunu korur', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'draft',
      paidAmount: 100,
      grandTotal: 100,
      invoiceType: 'sales',
      eInvoiceStatus: 'not_sent',
    }),
    'draft',
  );
});

test('Hat & Lisans taslağı ödenince satış faturası olur, Maliye olmadan kapanmaz', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'draft',
      paidAmount: 100,
      grandTotal: 100,
      invoiceType: 'sales',
      eInvoiceStatus: 'not_sent',
      billingSource: 'hat_lisans',
    }),
    'open',
  );
});

test('Hat & Lisans taslağı ödenip Maliye gönderilince kapanır', () => {
  assert.equal(
    invoiceStatusAfterPayment({
      currentStatus: 'draft',
      paidAmount: 100,
      grandTotal: 100,
      invoiceType: 'sales',
      eInvoiceStatus: 'sent',
      billingSource: 'hat_lisans',
    }),
    'paid',
  );
});
