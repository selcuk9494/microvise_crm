function textOrEmpty(value) {
  return String(value ?? '').trim();
}

function posListStatus(row) {
  const status = textOrEmpty(row?.status).toLowerCase();
  if (status === 'refunded') return 'refunded';
  if (status === 'paid' && row?.settled_at) return 'settled';
  if (status === 'paid') return 'paid';
  return 'pending';
}

function canDismissPosCollection(row) {
  return posListStatus(row) === 'pending';
}

function posCollectionVisible(row) {
  if (row?.dismissed_at) return false;
  const status = textOrEmpty(row?.status).toLowerCase();
  if (status === 'paid' || status === 'refunded') return true;
  if (status && status !== 'pending' && status !== 'failed') return false;

  const invoices = Array.isArray(row?.invoices)
    ? row.invoices
    : Array.isArray(row?.invoice_list)
      ? row.invoice_list
      : row?.invoices && typeof row.invoices === 'object'
        ? [row.invoices]
        : [];
  if (!invoices.length) return true;

  return invoices.some((invoice) => {
    const invoiceStatus = textOrEmpty(invoice?.status).toLowerCase();
    if (
      invoiceStatus === 'paid' ||
      invoiceStatus === 'cancelled' ||
      invoiceStatus === 'canceled' ||
      invoiceStatus === 'void' ||
      invoiceStatus === 'refunded'
    ) {
      return false;
    }
    const remaining =
      Number(invoice?.grand_total || 0) - Number(invoice?.paid_amount || 0);
    return remaining > 0.009;
  });
}

function posListStatusLabel(status) {
  switch (textOrEmpty(status).toLowerCase()) {
    case 'paid':
      return 'Ödendi';
    case 'settled':
      return 'Hesaba yattı';
    case 'refunded':
      return 'İade edildi';
    default:
      return 'Ödeme bekleniyor';
  }
}

function invoicePaymentAwaiting(row) {
  const status = textOrEmpty(row?.payment_link_status || row?.status).toLowerCase();
  if (status === 'paid' || status === 'refunded') return false;
  return Boolean(row?.payment_link_emailed_at || row?.emailed_at);
}

const POS_REMINDER_DAYS = 7;

function posLinkSentAt(row) {
  return row?.emailed_at || row?.created_at || null;
}

function posDaysSinceSent(row, now = new Date()) {
  const sent = posLinkSentAt(row);
  if (!sent) return null;
  const sentDate = sent instanceof Date ? sent : new Date(sent);
  if (Number.isNaN(sentDate.getTime())) return null;
  const current = now instanceof Date ? now : new Date(now);
  if (Number.isNaN(current.getTime())) return null;
  return Math.floor((current.getTime() - sentDate.getTime()) / 86400000);
}

function posPaymentOverdue(row, { now = new Date(), days = POS_REMINDER_DAYS } = {}) {
  if (posListStatus(row) !== 'pending') return false;
  if (row?.dismissed_at) return false;
  const elapsed = posDaysSinceSent(row, now);
  return elapsed != null && elapsed >= days;
}

function posNeedsAutoReminder(row, opts = {}) {
  if (row?.reminded_at) return false;
  return posPaymentOverdue(row, opts);
}

function periodKeyForDate(date) {
  const value = date instanceof Date ? date : new Date(date);
  if (Number.isNaN(value.getTime())) return '';
  const year = value.getFullYear();
  const month = String(value.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

function dueDayInMonth(billingDay, year, monthIndex) {
  const day = Number(billingDay);
  const safeDay = Number.isFinite(day) ? Math.trunc(day) : 1;
  const daysInMonth = new Date(year, monthIndex + 1, 0).getDate();
  return Math.min(Math.max(1, safeDay), daysInMonth);
}

function isPlanDueOn(plan, today) {
  if (!plan || plan.is_active === false) return false;
  const dueDay = dueDayInMonth(
    plan.billing_day,
    today.getFullYear(),
    today.getMonth(),
  );
  return today.getDate() >= dueDay;
}

function localToday() {
  const now = new Date();
  return new Date(now.getFullYear(), now.getMonth(), now.getDate());
}

function calendarDateParts(value, timeZone = 'Asia/Famagusta') {
  const date = value instanceof Date ? value : new Date(value);
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts
      .filter((part) => part.type !== 'literal')
      .map((part) => [part.type, part.value]),
  );
  return {
    year: Number(values.year),
    month: Number(values.month),
    day: Number(values.day),
  };
}

function calendarDateUtc(value) {
  const parts = calendarDateParts(value);
  if (!parts) return null;
  return Date.UTC(parts.year, parts.month - 1, parts.day);
}

function formatCalendarDate(value) {
  const parts = calendarDateParts(value);
  if (!parts) return null;
  return `${parts.year}-${String(parts.month).padStart(2, '0')}-${String(parts.day).padStart(2, '0')}`;
}

function addCalendarDays(value, days) {
  const parts = calendarDateParts(value);
  if (!parts) return null;
  const added = Number(days);
  if (!Number.isFinite(added)) return formatCalendarDate(value);
  const utc = Date.UTC(parts.year, parts.month - 1, parts.day + added);
  const next = new Date(utc);
  return `${next.getUTCFullYear()}-${String(next.getUTCMonth() + 1).padStart(2, '0')}-${String(next.getUTCDate()).padStart(2, '0')}`;
}

function daysBetweenCalendar(from, to) {
  const start = calendarDateUtc(from);
  const end = calendarDateUtc(to);
  if (start == null || end == null) return null;
  return Math.round((end - start) / (24 * 60 * 60 * 1000));
}

function normalizeValorDays(value, fallback = 1) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (!Number.isFinite(parsed)) return fallback;
  return Math.min(30, Math.max(0, parsed));
}

function posValorLabel(daysRemaining) {
  if (daysRemaining == null || !Number.isFinite(daysRemaining)) return '';
  if (daysRemaining > 1) return `Valör: ${daysRemaining} gün kaldı`;
  if (daysRemaining === 1) return 'Valör: yarın yatmalı';
  if (daysRemaining === 0) return 'Valör: bugün yatmalı';
  const late = Math.abs(daysRemaining);
  return late === 1 ? 'Valör: 1 gün gecikti' : `Valör: ${late} gün gecikti`;
}

function posValorInfo(row, { now = new Date(), fallbackValorDays = 1 } = {}) {
  const valorDays = normalizeValorDays(
    row?.valor_days ?? fallbackValorDays,
    fallbackValorDays,
  );
  const status = textOrEmpty(row?.list_status || row?.status).toLowerCase();
  if (row?.settled_at || status === 'settled' || status === 'refunded') {
    return {
      valorDays,
      expectedSettleOn: null,
      daysRemaining: null,
      label: '',
    };
  }
  if (status !== 'paid') {
    return {
      valorDays,
      expectedSettleOn: null,
      daysRemaining: null,
      label: '',
    };
  }
  const paidAt = row?.paid_at || row?.paid_on;
  const expectedSettleOn = addCalendarDays(paidAt, valorDays);
  const daysRemaining = expectedSettleOn
    ? daysBetweenCalendar(now, expectedSettleOn)
    : null;
  return {
    valorDays,
    expectedSettleOn,
    daysRemaining,
    label: posValorLabel(daysRemaining),
  };
}

module.exports = {
  posListStatus,
  posListStatusLabel,
  canDismissPosCollection,
  posCollectionVisible,
  invoicePaymentAwaiting,
  POS_REMINDER_DAYS,
  posLinkSentAt,
  posDaysSinceSent,
  posPaymentOverdue,
  posNeedsAutoReminder,
  periodKeyForDate,
  dueDayInMonth,
  isPlanDueOn,
  localToday,
  normalizeValorDays,
  addCalendarDays,
  daysBetweenCalendar,
  posValorLabel,
  posValorInfo,
};
