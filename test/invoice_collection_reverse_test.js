const assert = require('node:assert/strict');
const test = require('node:test');

const {
  isPosCollectionTransaction,
  selectCollectionsToReverse,
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

test('payment_method=pos tek başına sanal POS sayılmaz', () => {
  assert.equal(
    isPosCollectionTransaction({
      payment_method: 'pos',
      description: 'E-Fatura tahsilatı: 2026-1-24 · POS komisyon 12.00 TL',
    }),
    false,
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

test('Tek nakit satırı silinince yalnızca o kayıt düşer', () => {
  const rows = [
    { id: 'cash-1', payment_method: 'cash', description: 'E-Fatura tahsilatı' },
    { id: 'bank-1', payment_method: 'bank', description: 'Havale' },
  ];
  const selected = selectCollectionsToReverse(rows, { transactionId: 'cash-1' });
  assert.deepEqual(
    selected.toReverse.map((row) => row.id),
    ['cash-1'],
  );
  assert.equal(selected.posRows.length, 0);
});

test('Sanal POS satırı allowPos olmadan CRM geri almaya girmez', () => {
  const rows = [
    {
      id: 'pos-1',
      payment_method: 'credit_card',
      description: 'Sanal POS ödeme linki: 2026-1-24',
    },
  ];
  const selected = selectCollectionsToReverse(rows, { transactionId: 'pos-1' });
  assert.equal(selected.toReverse.length, 0);
  assert.equal(selected.posRows.length, 1);
});

test('Sanal POS satırı allowPos ile silinebilir', () => {
  const rows = [
    {
      id: 'pos-1',
      payment_method: 'credit_card',
      description: 'Sanal POS ödeme linki: 2026-1-24',
    },
  ];
  const selected = selectCollectionsToReverse(rows, {
    transactionId: 'pos-1',
    allowPos: true,
  });
  assert.deepEqual(
    selected.toReverse.map((row) => row.id),
    ['pos-1'],
  );
});

test('Fatura genel geri almada nakit düşer POS kalır', () => {
  const rows = [
    { id: 'cash-1', payment_method: 'cash', description: 'Nakit tahsilat' },
    {
      id: 'pos-1',
      payment_method: 'credit_card',
      description: 'Sanal POS ödeme linki: 2026-1-24',
    },
  ];
  const selected = selectCollectionsToReverse(rows);
  assert.deepEqual(
    selected.toReverse.map((row) => row.id),
    ['cash-1'],
  );
  assert.equal(selected.posRows.length, 1);
});
