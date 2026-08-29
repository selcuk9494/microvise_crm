const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  posListStatus,
  posListStatusLabel,
  posCollectionVisible,
  invoicePaymentAwaiting,
  periodKeyForDate,
  dueDayInMonth,
  isPlanDueOn,
} = require('../api/_lib/pos_status');

test('posListStatus maps paid / settled / pending', () => {
  assert.equal(posListStatus({ status: 'pending' }), 'pending');
  assert.equal(posListStatus({ status: 'paid' }), 'paid');
  assert.equal(
    posListStatus({ status: 'paid', settled_at: '2026-08-29' }),
    'settled',
  );
  assert.equal(posListStatus({ status: 'refunded' }), 'refunded');
  assert.equal(posListStatusLabel('pending'), 'Ödeme bekleniyor');
  assert.equal(posListStatusLabel('paid'), 'Ödendi');
  assert.equal(posListStatusLabel('settled'), 'Hesaba yattı');
});

test('bekleyen POS kaydı nakit kapanınca listeden düşer', () => {
  assert.equal(
    posCollectionVisible({
      status: 'pending',
      invoices: [
        { status: 'open', grand_total: 100, paid_amount: 0 },
      ],
    }),
    true,
  );
  assert.equal(
    posCollectionVisible({
      status: 'pending',
      invoices: [
        { status: 'open', grand_total: 100, paid_amount: 100 },
      ],
    }),
    false,
  );
  assert.equal(
    posCollectionVisible({
      status: 'pending',
      invoices: [{ status: 'paid', grand_total: 100, paid_amount: 100 }],
    }),
    false,
  );
  assert.equal(
    posCollectionVisible({
      status: 'paid',
      invoices: [{ status: 'paid', grand_total: 100, paid_amount: 100 }],
    }),
    true,
  );
  assert.equal(
    posCollectionVisible({
      status: 'pending',
      dismissed_at: '2026-08-29T10:00:00Z',
      invoices: [{ status: 'open', grand_total: 100, paid_amount: 0 }],
    }),
    false,
  );
});

test('invoicePaymentAwaiting is true after mail until paid', () => {
  assert.equal(
    invoicePaymentAwaiting({
      payment_link_status: 'pending',
      payment_link_emailed_at: '2026-08-29T10:00:00Z',
    }),
    true,
  );
  assert.equal(
    invoicePaymentAwaiting({
      payment_link_status: 'paid',
      payment_link_emailed_at: '2026-08-29T10:00:00Z',
    }),
    false,
  );
  assert.equal(
    invoicePaymentAwaiting({ payment_link_status: 'pending' }),
    false,
  );
});

test('recurring billing day clamps to month length', () => {
  assert.equal(dueDayInMonth(31, 2026, 1), 28);
  assert.equal(dueDayInMonth(31, 2026, 0), 31);
  assert.equal(periodKeyForDate(new Date(2026, 7, 29)), '2026-08');
  assert.equal(
    isPlanDueOn({ is_active: true, billing_day: 29 }, new Date(2026, 7, 29)),
    true,
  );
  assert.equal(
    isPlanDueOn({ is_active: true, billing_day: 30 }, new Date(2026, 7, 29)),
    false,
  );
  assert.equal(
    isPlanDueOn({ is_active: false, billing_day: 1 }, new Date(2026, 7, 29)),
    false,
  );
});
