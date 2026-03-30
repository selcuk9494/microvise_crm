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

double? parseCurrencyValue(String? value) {
  final source = (value ?? '').trim();
  if (source.isEmpty) return null;

  final cleaned = source.replaceAll(RegExp(r'[^0-9,.\-]'), '');
  if (cleaned.isEmpty) return null;

  final lastComma = cleaned.lastIndexOf(',');
  final lastDot = cleaned.lastIndexOf('.');
  final decimalIndex = lastComma > lastDot ? lastComma : lastDot;

  if (decimalIndex >= 0) {
    final integerPart = cleaned
        .substring(0, decimalIndex)
        .replaceAll(RegExp(r'[^0-9\-]'), '');
    final decimalPart = cleaned
        .substring(decimalIndex + 1)
        .replaceAll(RegExp(r'[^0-9]'), '');
    final normalized = decimalPart.isEmpty
        ? integerPart
        : '$integerPart.${decimalPart.padRight(2, '0').substring(0, 2)}';
    return double.tryParse(normalized);
  }

  final digits = cleaned.replaceAll(RegExp(r'[^0-9\-]'), '');
  if (digits.isEmpty) return null;
  return double.tryParse(digits);
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
