const assert = require('node:assert/strict');
const test = require('node:test');

const {
  isPosCollectionTransaction,
} = require('../api/_lib/invoice_payment');

test('Nakit tahsilat POS sayılmaz', () => {
  assert.equal(
    isPosCollectionTransaction({
      payment_method: 'cash',
      description: 'E-Fatura tahsilatı: 2026-1-24',
    }),
    false,
  );
});

test('Havale tahsilat POS sayılmaz', () => {
  assert.equal(
    isPosCollectionTransaction({
      payment_method: 'bank',
      description: 'CRM tahsilat 2026-1-24',
    }),
    false,
  );
});

test('payment_method=pos sanal POS sayılır', () => {
  assert.equal(
    isPosCollectionTransaction({
      payment_method: 'pos',
      description: 'Kart ödemesi',
    }),
    true,
  );
});

test('Açıklamada sanal POS geçen kayıt iade akışına gider', () => {
  assert.equal(
    isPosCollectionTransaction({
      payment_method: 'credit_card',
      description: 'Sanal POS ödeme linki: 2026-1-24',
    }),
    true,
  );
});
