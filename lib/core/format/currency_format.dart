import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

final NumberFormat _currencyFormatter = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '',
  decimalDigits: 2,
);

String formatCurrencyDisplay(String? value) {
  final parsed = parseCurrencyValue(value);
  if (parsed == null) return '';
  return _currencyFormatter.format(parsed).trim();
}

String formatMoneyInput(double value, {int fractionDigits = 2}) {
  if (value.isNaN || value.isInfinite) return '';
  return value.toStringAsFixed(fractionDigits).replaceAll('.', ',');
}

double? parseCurrencyValue(String? value) {
  final source = (value ?? '').trim();
  if (source.isEmpty) return null;

  final cleaned = source.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (cleaned.isEmpty || cleaned == '-' || cleaned == ',' || cleaned == '.') {
    return null;
  }

  final lastComma = cleaned.lastIndexOf(',');
  final lastDot = cleaned.lastIndexOf('.');
  final commaCount = ','.allMatches(cleaned).length;
  final dotCount = '.'.allMatches(cleaned).length;

  var decimalIndex = -1;
  var stripped = cleaned;

  if (lastComma >= 0 && lastDot >= 0) {
    decimalIndex = lastComma > lastDot ? lastComma : lastDot;
  } else if (lastComma >= 0) {
    decimalIndex = _decimalIndexForSingleSeparator(
      cleaned,
      lastComma,
      commaCount,
    );
    if (decimalIndex < 0) stripped = cleaned.replaceAll(',', '');
  } else if (lastDot >= 0) {
    decimalIndex = _decimalIndexForSingleSeparator(cleaned, lastDot, dotCount);
    if (decimalIndex < 0) stripped = cleaned.replaceAll('.', '');
  }

  if (decimalIndex >= 0) {
    final integerPart = cleaned
        .substring(0, decimalIndex)
        .replaceAll(RegExp(r'[^0-9\-]'), '');
    final decimalPart = cleaned
        .substring(decimalIndex + 1)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = decimalPart.isEmpty
        ? integerPart
        : '$integerPart.$decimalPart';
    return _moneyNumber(normalized);
  }

  final digits = stripped.replaceAll(RegExp(r'[^0-9\-]'), '');
  if (digits.isEmpty || digits == '-') return null;
  return _moneyNumber(digits);
}

int _decimalIndexForSingleSeparator(String cleaned, int lastIndex, int count) {
  final fraction = cleaned
      .substring(lastIndex + 1)
      .replaceAll(RegExp(r'[^0-9]'), '');
  final integerRaw = cleaned
      .substring(0, lastIndex)
      .replaceAll(RegExp(r'[^0-9\-]'), '');
  final integerIsZero = integerRaw.isEmpty || integerRaw.replaceAll('-', '') == '0';

  if (fraction.length <= 2) return lastIndex;
  if (integerIsZero) return lastIndex;
  if (count == 1 && fraction.length == 3) return -1;
  if (count > 1 && fraction.length == 3) return -1;
  return lastIndex;
}

double? _moneyNumber(String normalized) {
  final value = double.tryParse(normalized);
  if (value == null || value.isNaN || value.isInfinite) return null;
  return (value * 100).round() / 100;
}

class CurrencyTextInputFormatter extends TextInputFormatter {
  const CurrencyTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    final amount = double.parse(digits) / 100;
    final formatted = _currencyFormatter.format(amount).trim();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

/// Converts `.` to `,` while typing and keeps a single 2-digit decimal.
class MoneyDecimalInputFormatter extends TextInputFormatter {
  const MoneyDecimalInputFormatter({this.fractionDigits = 2});

  final int fractionDigits;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final raw = newValue.text;
    if (raw.trim().isEmpty) {
      return const TextEditingValue(text: '');
    }

    if (raw.contains('.') && raw.contains(',')) {
      final parsed = parseCurrencyValue(raw);
      if (parsed == null) return oldValue;
      final formatted = formatMoneyInput(
        parsed,
        fractionDigits: fractionDigits,
      );
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    final negative = raw.trimLeft().startsWith('-');
    var body = raw.replaceAll(RegExp(r'[^0-9,.]'), '').replaceAll('.', ',');
    final comma = body.indexOf(',');
    var integer = comma >= 0 ? body.substring(0, comma) : body;
    var fraction = comma >= 0 ? body.substring(comma + 1) : null;
    integer = integer.replaceAll(',', '');
    if (fraction != null) {
      fraction = fraction.replaceAll(',', '');
      if (fraction.length > fractionDigits) {
        fraction = fraction.substring(0, fractionDigits);
      }
    }

    integer = integer.replaceFirst(RegExp(r'^0+(?=\d)'), '');
    if (integer.isEmpty && (fraction != null || negative)) integer = '0';

    final formatted =
        '${negative ? '-' : ''}$integer${fraction == null ? '' : ',$fraction'}';
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

const moneyDecimalInputFormatters = <TextInputFormatter>[
  MoneyDecimalInputFormatter(),
];
