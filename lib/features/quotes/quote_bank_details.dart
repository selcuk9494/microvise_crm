import 'package:flutter/services.dart';

/// IBAN girişini büyük harfe çevirip dörtlü gruplara ayırır.
String formatQuoteIban(String value) {
  final raw = value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
  if (raw.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

class QuoteBankDetailsInputFormatter extends TextInputFormatter {
  const QuoteBankDetailsInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = formatQuoteIban(newValue.text);
    final typedBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9]'), '')
        .length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < typedBeforeCursor) {
      if (formatted[offset] != ' ') seen += 1;
      offset += 1;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
  }
}

typedef ParsedQuoteBankDetails = ({
  String bankName,
  String accountName,
  String ibanTl,
  String ibanUsd,
  String extraLines,
});

ParsedQuoteBankDetails parseQuoteBankDetails(String raw) {
  final lines = raw
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);

  var ibanTl = '';
  var ibanUsd = '';
  final others = <String>[];
  for (final line in lines) {
    final tlMatch = RegExp(
      r'^TL\s*IBAN\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (tlMatch != null) {
      ibanTl = tlMatch.group(1)!.trim();
      continue;
    }
    final usdMatch = RegExp(
      r'^USD\s*IBAN\s*:\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(line);
    if (usdMatch != null) {
      ibanUsd = usdMatch.group(1)!.trim();
      continue;
    }
    if (line.toLowerCase() == 'banka hesap bilgileri') continue;
    others.add(line);
  }

  final bankName = others.isNotEmpty ? others.first : '';
  final accountName = others.length > 1 ? others[1] : '';
  final extraStart = others.length > 2 ? 2 : others.length;
  final extraLines = extraStart < others.length
      ? others.sublist(extraStart).join('\n')
      : '';

  return (
    bankName: bankName,
    accountName: accountName,
    ibanTl: ibanTl,
    ibanUsd: ibanUsd,
    extraLines: extraLines,
  );
}

String composeQuoteBankDetails({
  required String bankName,
  required String accountName,
  required String ibanTl,
  required String ibanUsd,
  String extraLines = '',
}) {
  final tl = formatQuoteIban(ibanTl);
  final usd = formatQuoteIban(ibanUsd);
  final extra = extraLines
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
  final lines = <String>[
    if (bankName.isNotEmpty ||
        accountName.isNotEmpty ||
        tl.isNotEmpty ||
        usd.isNotEmpty ||
        extra.isNotEmpty)
      'Banka Hesap Bilgileri',
    if (bankName.isNotEmpty) bankName,
    if (accountName.isNotEmpty) accountName,
    if (tl.isNotEmpty) 'TL IBAN: $tl',
    if (usd.isNotEmpty) 'USD IBAN: $usd',
    ...extra,
  ];
  return lines.join('\n');
}
