import 'invoice_pdf_analysis_model.dart';

/// Calendar-day normalizer (ignores time-of-day / UTC vs local clock).
DateTime invoicePdfNormalizeDate(DateTime value) =>
    DateTime(value.year, value.month, value.day);

bool _sameCurrency(String a, String b) =>
    a.trim().toUpperCase() == b.trim().toUpperCase();

bool _isTry(String currency) {
  final c = currency.trim().toUpperCase();
  return c == 'TRY' || c == 'TL' || c == 'TRYL';
}

bool _ruleCoversDay(InvoicePdfFxRateRule rule, DateTime day) {
  final start = invoicePdfNormalizeDate(rule.startDate);
  final end = invoicePdfNormalizeDate(rule.endDate);
  return !day.isBefore(start) && !day.isAfter(end);
}

/// Resolve TRY rate for [currency] using kur definitions.
///
/// Order:
/// 1. Exact date-range match for invoice day
/// 2. Latest rule that starts on/before invoice day (handles Temmuz
///    invoices when bitiş accidentally ends at 30.06, etc.)
/// 3. Earliest upcoming rule
/// 4. Most recently ending rule (no invoice date, or no better match)
double? resolveInvoicePdfFxRate({
  required String currency,
  required DateTime? invoiceDate,
  required List<InvoicePdfFxRateRule> fxRules,
}) {
  if (_isTry(currency)) return 1;
  final matches = fxRules
      .where(
        (rule) =>
            _sameCurrency(rule.currency, currency) && rule.rateToTry > 0,
      )
      .toList(growable: false);
  if (matches.isEmpty) return null;

  if (invoiceDate != null) {
    final day = invoicePdfNormalizeDate(invoiceDate);
    for (final rule in matches) {
      if (_ruleCoversDay(rule, day)) return rule.rateToTry;
    }

    final startedOnOrBefore = matches
        .where(
          (rule) =>
              !invoicePdfNormalizeDate(rule.startDate).isAfter(day),
        )
        .toList(growable: false)
      ..sort(
        (a, b) => invoicePdfNormalizeDate(b.startDate).compareTo(
          invoicePdfNormalizeDate(a.startDate),
        ),
      );
    if (startedOnOrBefore.isNotEmpty) {
      return startedOnOrBefore.first.rateToTry;
    }

    final upcoming = [...matches]..sort(
        (a, b) => invoicePdfNormalizeDate(a.startDate).compareTo(
          invoicePdfNormalizeDate(b.startDate),
        ),
      );
    return upcoming.first.rateToTry;
  }

  if (matches.length == 1) return matches.first.rateToTry;

  final byEnd = [...matches]..sort(
      (a, b) => invoicePdfNormalizeDate(b.endDate).compareTo(
        invoicePdfNormalizeDate(a.endDate),
      ),
    );
  return byEnd.first.rateToTry;
}

double computeInvoicePdfTlEquivalent({
  required String currency,
  required double amount,
  required DateTime? invoiceDate,
  required List<InvoicePdfFxRateRule> fxRules,
}) {
  if (_isTry(currency)) return amount;
  final rate = resolveInvoicePdfFxRate(
    currency: currency,
    invoiceDate: invoiceDate,
    fxRules: fxRules,
  );
  if (rate == null) return 0;
  return amount * rate;
}
