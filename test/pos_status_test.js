const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  posListStatus,
  posListStatusLabel,
  canDismissPosCollection,
  posCollectionVisible,
  invoicePaymentAwaiting,
  POS_REMINDER_DAYS,
  posPaymentOverdue,
  posNeedsAutoReminder,
  periodKeyForDate,
  dueDayInMonth,
  isPlanDueOn,
  posValorInfo,
  normalizeValorDays,
  addCalendarDays,
  daysBetweenCalendar,
  posValorLabel,
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

test('ödenen sanal POS kaydı listeden çıkarılamaz', () => {
  assert.equal(canDismissPosCollection({ status: 'pending' }), true);
  assert.equal(canDismissPosCollection({ status: 'paid' }), false);
  assert.equal(
    canDismissPosCollection({ status: 'paid', settled_at: '2026-08-29' }),
    false,
  );
  assert.equal(canDismissPosCollection({ status: 'refunded' }), false);
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

test('valör tarihi ödeme gününe gün ekler ve kalan günü yazar', () => {
  assert.equal(normalizeValorDays('2'), 2);
  assert.equal(normalizeValorDays(-4), 0);
  assert.equal(addCalendarDays('2026-08-29', 2), '2026-08-31');
  assert.equal(daysBetweenCalendar('2026-08-29', '2026-08-31'), 2);
  assert.equal(posValorLabel(3), 'Valör: 3 gün kaldı');
  assert.equal(posValorLabel(1), 'Valör: yarın yatmalı');
  assert.equal(posValorLabel(0), 'Valör: bugün yatmalı');
  assert.equal(posValorLabel(-2), 'Valör: 2 gün gecikti');
  const info = posValorInfo(
    { status: 'paid', paid_at: '2026-08-29T10:00:00+03:00', valor_days: 2 },
    { now: new Date('2026-08-29T12:00:00+03:00') },
  );
  assert.equal(info.expectedSettleOn, '2026-08-31');
  assert.equal(info.daysRemaining, 2);
  assert.equal(info.label, 'Valör: 2 gün kaldı');
  assert.equal(
    posValorInfo(
      { status: 'paid', paid_at: '2026-08-29', settled_at: '2026-08-30' },
      { now: new Date('2026-08-29') },
    ).label,
    '',
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

test('ödeme linki 7 gün sonra gecikmiş sayılır, hatırlatma bir kez otomatik gider', () => {
  const now = new Date('2026-08-29T12:00:00Z');
  assert.equal(POS_REMINDER_DAYS, 7);
  assert.equal(
    posPaymentOverdue(
      { status: 'pending', emailed_at: '2026-08-22T12:00:00Z' },
      { now },
    ),
    true,
  );
  assert.equal(
    posPaymentOverdue(
      { status: 'pending', created_at: '2026-08-22T12:00:00Z' },
      { now },
    ),
    true,
  );
  assert.equal(
    posPaymentOverdue(
      { status: 'pending', emailed_at: '2026-08-23T12:00:00Z' },
      { now },
    ),
    false,
  );
  assert.equal(
    posPaymentOverdue(
      { status: 'paid', emailed_at: '2026-08-01T12:00:00Z' },
      { now },
    ),
    false,
  );
  assert.equal(
    posNeedsAutoReminder(
      { status: 'pending', emailed_at: '2026-08-22T12:00:00Z' },
      { now },
    ),
    true,
  );
  assert.equal(
    posNeedsAutoReminder(
      {
        status: 'pending',
        emailed_at: '2026-08-22T12:00:00Z',
        reminded_at: '2026-08-29T08:00:00Z',
      },
      { now },
    ),
    false,
  );
});
