import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_export.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_fx.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_model.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });
  group('resolveInvoicePdfFxRate', () {
    test('exact range match uses that rate', () {
      final rules = [
        InvoicePdfFxRateRule(
          id: 'june',
          currency: 'USD',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
          rateToTry: 39.0,
        ),
        InvoicePdfFxRateRule(
          id: 'july',
          currency: 'USD',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 31),
          rateToTry: 40.5,
        ),
      ];
      final rate = resolveInvoicePdfFxRate(
        currency: 'USD',
        invoiceDate: DateTime(2026, 7, 15),
        fxRules: rules,
      );
      expect(rate, 40.5);
    });

    test('July invoice with only June end 30.06 still converts', () {
      // Previous bug: multiple non-matching rules or out-of-range single
      // leave TL karşılığı at 0.00.
      final rules = [
        InvoicePdfFxRateRule(
          id: 'june',
          currency: 'USD',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
          rateToTry: 40.5,
        ),
        InvoicePdfFxRateRule(
          id: 'may',
          currency: 'USD',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 31),
          rateToTry: 38.0,
        ),
      ];
      final rate = resolveInvoicePdfFxRate(
        currency: 'USD',
        invoiceDate: DateTime(2026, 7, 10),
        fxRules: rules,
      );
      expect(rate, 40.5);
    });

    test('currency match is case-insensitive and ignores spaces', () {
      final rules = [
        InvoicePdfFxRateRule(
          id: 'usd',
          currency: 'usd',
          startDate: DateTime(2026, 7, 1),
          endDate: DateTime(2026, 7, 31),
          rateToTry: 41.25,
        ),
      ];
      expect(
        resolveInvoicePdfFxRate(
          currency: ' USD ',
          invoiceDate: DateTime(2026, 7, 1),
          fxRules: rules,
        ),
        41.25,
      );
    });

    test('date-only JSON roundtrip keeps calendar day', () {
      final rule = InvoicePdfFxRateRule(
        id: 'usd',
        currency: 'USD',
        startDate: DateTime(2026, 6, 30),
        endDate: DateTime(2026, 7, 31),
        rateToTry: 40.5,
      );
      final restored = InvoicePdfFxRateRule.fromJson(rule.toJson());
      expect(restored.startDate, DateTime(2026, 6, 30));
      expect(restored.endDate, DateTime(2026, 7, 31));
      expect(restored.toJson()['startDate'], '2026-06-30');
    });

    test('legacy ISO datetime JSON still parses', () {
      final restored = InvoicePdfFxRateRule.fromJson({
        'id': 'legacy',
        'currency': 'USD',
        'startDate': '2026-06-30T00:00:00.000',
        'endDate': '2026-07-31T21:00:00.000Z',
        'rateToTry': 40.5,
      });
      expect(restored.startDate, DateTime(2026, 6, 30));
      expect(restored.endDate.year, 2026);
      expect(restored.endDate.month, 7);
      expect(restored.endDate.day, 31);
    });
  });

  group('Excel dip TL karşılığı', () {
    test('USD buckets convert and Totals include USD TL', () async {
      final rows = [
        InvoicePdfAnalysisListRow(
          customerName: 'TRY Musteri',
          invoiceNumber: 'T1',
          invoiceDate: DateTime(2026, 7, 5),
          currency: 'TRY',
          invoiceTotal: 116,
          vatBreakdowns: const [
            InvoicePdfAnalysisVatBreakdown(
              baseAmount: 100,
              taxRate: 16,
              taxAmount: 16,
              grandTotal: 116,
            ),
          ],
        ),
        InvoicePdfAnalysisListRow(
          customerName: 'USD Musteri',
          invoiceNumber: 'U1',
          invoiceDate: DateTime(2026, 7, 12),
          currency: 'USD',
          invoiceTotal: 105,
          vatBreakdowns: const [
            InvoicePdfAnalysisVatBreakdown(
              baseAmount: 100,
              taxRate: 5,
              taxAmount: 5,
              grandTotal: 105,
            ),
          ],
        ),
      ];
      // Out-of-range end date (30.06) with a second older rule — must still convert.
      final fx = [
        InvoicePdfFxRateRule(
          id: 'may',
          currency: 'USD',
          startDate: DateTime(2026, 5, 1),
          endDate: DateTime(2026, 5, 31),
          rateToTry: 38,
        ),
        InvoicePdfFxRateRule(
          id: 'june',
          currency: 'USD',
          startDate: DateTime(2026, 6, 1),
          endDate: DateTime(2026, 6, 30),
          rateToTry: 40.5,
        ),
      ];

      expect(
        computeInvoicePdfTlEquivalent(
          currency: 'USD',
          amount: 100,
          invoiceDate: DateTime(2026, 7, 12),
          fxRules: fx,
        ),
        closeTo(4050, 0.01),
      );

      final bytes = await buildInvoicePdfAnalysisExcelBytes(rows, fx);
      expect(bytes.length, greaterThan(100));
      final archive = ZipDecoder().decodeBytes(bytes);
      final texts = <String>[];
      for (final file in archive) {
        if (!file.isFile) continue;
        if (!file.name.contains('sharedStrings') &&
            !file.name.contains('sheet')) {
          continue;
        }
        texts.add(utf8.decode(file.content as List<int>, allowMalformed: true));
      }
      final blob = texts.join('\n');
      expect(blob, contains('4050.00'));
      expect(blob, contains('202.50')); // 5 USD * 40.5
      expect(blob, contains('4252.50')); // 105 * 40.5
      // Totals: matrah TL = 100 TRY + 4050 = 4150; vergi TL = 16 + 202.5 = 218.5
      expect(blob, contains('4150.00'));
      expect(blob, contains('218.50'));
    });
  });
}
