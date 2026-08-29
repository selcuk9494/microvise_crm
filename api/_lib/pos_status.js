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

module.exports = {
  posListStatus,
  posListStatusLabel,
  posCollectionVisible,
  invoicePaymentAwaiting,
  periodKeyForDate,
  dueDayInMonth,
  isPlanDueOn,
  localToday,
};
