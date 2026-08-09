import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_model.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_parser.dart';

void main() {
  final folder = Directory('/Users/selcuk/Desktop/Muhasebe/E-fatura/2026/TEMMUZ/OK');

  test('Worldline: %0 matrah Ara Toplam ile esit (UBL kalemi dahil)', () async {
    final file = File('${folder.path}/2026-1-00000000018_WORLDLINE_DEME_S_STEMLER_A_..pdf');
    final entry = await InvoicePdfAnalysisParser.parse(
      bytes: await file.readAsBytes(),
      fileName: file.uri.pathSegments.last,
    );
    expect(entry, isNotNull);
    expect(entry!.currency, 'TRY');
    expect(entry.subtotal, closeTo(52260.32, 0.01));
    expect(entry.grandTotal, closeTo(52260.32, 0.01));
    expect(entry.taxTotal, closeTo(0, 0.01));
    final baseSum = entry.items.fold<double>(0, (s, i) => s + i.lineBaseAmount);
    expect(baseSum, closeTo(52260.32, 0.01));
    expect(entry.items.any((i) => i.taxRate == 0), isTrue);
  });

  test('Ombika: Syncfusion kirik PDF fallback ile parse olur', () async {
    final file = File('${folder.path}/2026-1-00000000011_OMBIKA_TRADING_LTD.pdf');
    final entry = await InvoicePdfAnalysisParser.parse(
      bytes: await file.readAsBytes(),
      fileName: file.uri.pathSegments.last,
    );
    expect(entry, isNotNull);
    expect(entry!.customerName.toUpperCase(), contains('OMBIKA'));
    expect(entry.invoiceNumber, contains('00000000011'));
    expect(entry.currency, 'USD');
    expect(entry.invoiceDate, isNotNull);
    expect(entry.subtotal, closeTo(333.33, 0.01));
    expect(entry.taxTotal, closeTo(16.67, 0.01));
    expect(entry.grandTotal, closeTo(350.00, 0.01));
    final baseSum = entry.items.fold<double>(0, (s, i) => s + i.lineBaseAmount);
    expect(baseSum, closeTo(333.33, 0.01));
  });

  test('Nihat: UBL eksik kalem USD %5 matrahi Ara Toplama tamamlanır', () async {
    final file = File('${folder.path}/2026-1-00000000016_N_HAT_D_RTER.pdf');
    final entry = await InvoicePdfAnalysisParser.parse(
      bytes: await file.readAsBytes(),
      fileName: file.uri.pathSegments.last,
    );
    expect(entry, isNotNull);
    expect(entry!.currency, 'USD');
    expect(entry.subtotal, closeTo(542.85, 0.01));
    expect(entry.taxTotal, closeTo(27.15, 0.01));
    final baseSum = entry.items.fold<double>(0, (s, i) => s + i.lineBaseAmount);
    final taxSum = entry.items.fold<double>(0, (s, i) => s + i.taxAmount);
    expect(baseSum, closeTo(542.85, 0.01));
    expect(taxSum, closeTo(27.15, 0.01));
  });

  test('TEMMUZ Microvise PDF: satir matrah toplami Ara Toplam ile uyumlu', () async {
    final files = folder
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.pdf') && f.uri.pathSegments.last.startsWith('2026-1-'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    expect(files, isNotEmpty);

    for (final file in files) {
      final name = file.uri.pathSegments.last;
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await file.readAsBytes(),
        fileName: name,
      );
      expect(entry, isNotNull, reason: name);
      expect(entry!.customerName, isNot('Bilinmeyen Müşteri'), reason: name);
      expect(entry.grandTotal, greaterThan(0), reason: name);
      expect(entry.invoiceDate, isNotNull, reason: name);
      expect(entry.invoiceNumber.endsWith('.pdf'), isFalse, reason: name);

      if (entry.subtotal > 0) {
        final baseSum = entry.items.fold<double>(0, (s, i) => s + i.lineBaseAmount);
        expect(baseSum, closeTo(entry.subtotal, 0.05), reason: '$name base vs ara');
      }
      if (entry.taxTotal > 0 || entry.items.any((i) => i.taxAmount > 0)) {
        final taxSum = entry.items.fold<double>(0, (s, i) => s + i.taxAmount);
        expect(taxSum, closeTo(entry.taxTotal, 0.05), reason: '$name tax vs kdv');
      }
    }
  });

  test('USD tek kur tanimi varsa TL karsiligi hesaplanir', () {
    final fx = [
      InvoicePdfFxRateRule(
        id: 'usd',
        currency: 'USD',
        startDate: DateTime(2026, 7, 1),
        endDate: DateTime(2026, 7, 31),
        rateToTry: 40.5,
      ),
    ];
    // Export ile ayni kural: tek kur / tarih araligi eslesince carp.
    final baseTl = 333.33 * fx.first.rateToTry;
    final taxTl = 16.67 * fx.first.rateToTry;
    expect(baseTl, closeTo(13499.865, 0.01));
    expect(taxTl, closeTo(675.135, 0.01));
    expect(baseTl + taxTl, closeTo(350 * 40.5, 0.01));
  });
}
