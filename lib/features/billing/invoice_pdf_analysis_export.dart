import 'package:excel/excel.dart' as excel;
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_pdf_analysis_model.dart';

Future<Uint8List> buildInvoicePdfAnalysisExcelBytes(
  List<InvoicePdfAnalysisListRow> rows,
  List<InvoicePdfFxRateRule> fxRules,
) async {
  final file = excel.Excel.createExcel();
  final sheet = file.tables[file.getDefaultSheet()]!;
  final vatRates = _collectVatRates(rows);
  var rowIndex = 0;
  final boldStyle = excel.CellStyle(bold: true);
  final tlHighlightStyle = excel.CellStyle(
    bold: true,
    fontColorHex: excel.ExcelColor.fromHexString('FF0F172A'),
  );
  sheet.appendRow([
    excel.TextCellValue('Fatura No'),
    excel.TextCellValue('Tarih'),
    excel.TextCellValue('Para Birimi'),
    excel.TextCellValue('Fatura Tutari'),
    ...vatRates.map(
      (rate) => excel.TextCellValue('KDV ${_formatPercentValue(rate)}'),
    ),
    excel.TextCellValue('Toplam KDV'),
  ]);
  _applyRowStyle(
    sheet,
    rowIndex: rowIndex,
    columnCount: 5 + vatRates.length,
    style: boldStyle,
  );
  rowIndex += 1;

  final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  for (final row in rows) {
    sheet.appendRow([
      excel.TextCellValue(row.invoiceNumber),
      excel.TextCellValue(
        row.invoiceDate == null ? '' : dateFormat.format(row.invoiceDate!),
      ),
      excel.TextCellValue(row.currency),
      excel.TextCellValue(row.invoiceTotal.toStringAsFixed(2)),
      ...vatRates.map(
        (rate) => excel.TextCellValue(row.taxAmountForRate(rate).toStringAsFixed(2)),
      ),
      excel.TextCellValue(row.totalTaxAmount.toStringAsFixed(2)),
    ]);
    rowIndex += 1;
  }

  final summaries = _buildRateSummaries(rows, fxRules);
  if (rows.isNotEmpty) {
    sheet.appendRow([excel.TextCellValue('')]);
    rowIndex += 1;
    sheet.appendRow([
      excel.TextCellValue('Dip Toplam - KDV Oranina Gore'),
    ]);
    _applyRowStyle(
      sheet,
      rowIndex: rowIndex,
      columnCount: 1,
      style: boldStyle,
    );
    rowIndex += 1;
    sheet.appendRow([
      excel.TextCellValue('Para Birimi'),
      excel.TextCellValue('KDV Orani'),
      excel.TextCellValue('Matrah Toplami'),
      excel.TextCellValue('Matrah TL Karsiligi'),
      excel.TextCellValue('KDV Toplami'),
      excel.TextCellValue('KDV TL Karsiligi'),
      excel.TextCellValue('Vergili Toplam'),
      excel.TextCellValue('TL Karsiligi'),
    ]);
    _applyRowStyle(
      sheet,
      rowIndex: rowIndex,
      columnCount: 8,
      style: boldStyle,
    );
    rowIndex += 1;
    for (final summary in summaries) {
      sheet.appendRow([
        excel.TextCellValue(summary.currency),
        excel.TextCellValue(_formatPercentValue(summary.taxRate)),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.baseAmount, summary.currency),
        ),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.baseTlEquivalent, 'TRY'),
        ),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.taxAmount, summary.currency),
        ),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.taxTlEquivalent, 'TRY'),
        ),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.grandTotal, summary.currency),
        ),
        excel.TextCellValue(
          _formatAmountWithCurrency(summary.tlEquivalent, 'TRY'),
        ),
      ]);
      final current = rowIndex;
      sheet
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: current))
          .cellStyle = tlHighlightStyle;
      sheet
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 5, rowIndex: current))
          .cellStyle = tlHighlightStyle;
      sheet
          .cell(excel.CellIndex.indexByColumnRow(columnIndex: 7, rowIndex: current))
          .cellStyle = tlHighlightStyle;
      rowIndex += 1;
    }
  }


  final bytes = file.encode();
  return Uint8List.fromList(bytes ?? const <int>[]);
}

Future<Uint8List> buildInvoicePdfAnalysisPdfBytes(
  List<InvoicePdfAnalysisListRow> rows,
  List<InvoicePdfFxRateRule> fxRules,
) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final italicFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Italic.ttf'),
  );
  final theme = pw.ThemeData.withFont(
    base: regularFont,
    bold: regularFont,
    italic: italicFont,
  );

  final doc = pw.Document(
    title: 'KDV Analizi',
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
    theme: theme,
  );
  final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final vatRates = _collectVatRates(rows);
  final summaries = _buildRateSummaries(rows, fxRules);
  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Text(
          'KDV Analizi',
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Olusturma: ${DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 10),
        ),
        pw.SizedBox(height: 16),
        pw.TableHelper.fromTextArray(
          border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
          headerStyle: pw.TextStyle(
            fontWeight: pw.FontWeight.bold,
            fontSize: 10,
          ),
          cellStyle: const pw.TextStyle(fontSize: 9),
          headerDecoration: const pw.BoxDecoration(
            color: PdfColors.grey200,
          ),
          cellAlignment: pw.Alignment.centerLeft,
          headers: [
            'Fatura No',
            'Tarih',
            'PB',
            'Fatura Tutari',
            ...vatRates.map((rate) => 'KDV ${_formatPercentValue(rate)}'),
            'Toplam KDV',
          ],
          data: rows
              .map(
                (row) => [
                  row.invoiceNumber,
                  row.invoiceDate == null ? '' : dateFormat.format(row.invoiceDate!),
                  row.currency,
                  row.invoiceTotal.toStringAsFixed(2),
                  ...vatRates.map(
                    (rate) => row.taxAmountForRate(rate).toStringAsFixed(2),
                  ),
                  row.totalTaxAmount.toStringAsFixed(2),
                ],
              )
              .toList(growable: false),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Dip Toplam - KDV Oranina Gore',
          style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 8),
        _buildPdfRateSummaryTable(summaries),
      ],
    ),
  );

  return doc.save();
}

String _formatPercentValue(double value) {
  if (value % 1 == 0) return '%${value.toStringAsFixed(0)}';
  return '%${value.toStringAsFixed(2)}';
}

String _formatAmountWithCurrency(double amount, String currency) {
  final normalized = currency.trim().toUpperCase();
  final label = normalized == 'TRY' ? 'TL' : normalized;
  return '${amount.toStringAsFixed(2)} $label';
}

List<_RateSummary> _buildRateSummaries(
  List<InvoicePdfAnalysisListRow> rows,
  List<InvoicePdfFxRateRule> fxRules,
) {
  final buckets = <String, _RateSummary>{};
  for (final row in rows) {
    for (final item in row.vatBreakdowns) {
      final key = '${row.currency}|${item.taxRate}';
      final summary = buckets.putIfAbsent(
        key,
        () => _RateSummary(currency: row.currency, taxRate: item.taxRate),
      );
      summary.baseAmount += item.baseAmount;
      summary.taxAmount += item.taxAmount;
      summary.grandTotal += item.grandTotal;
      summary.baseTlEquivalent += _computeTlEquivalent(
        row.currency,
        item.baseAmount,
        row.invoiceDate,
        fxRules,
      );
      summary.taxTlEquivalent += _computeTlEquivalent(
        row.currency,
        item.taxAmount,
        row.invoiceDate,
        fxRules,
      );
      summary.tlEquivalent += _computeTlEquivalent(
        row.currency,
        item.grandTotal,
        row.invoiceDate,
        fxRules,
      );
    }
  }
  final result = buckets.values.toList()
    ..sort((a, b) {
      final currencyCompare = a.currency.compareTo(b.currency);
      if (currencyCompare != 0) return currencyCompare;
      return a.taxRate.compareTo(b.taxRate);
    });
  return result;
}

class _RateSummary {
  _RateSummary({
    required this.currency,
    required this.taxRate,
  });

  final String currency;
  final double taxRate;
  double baseAmount = 0;
  double baseTlEquivalent = 0;
  double taxAmount = 0;
  double taxTlEquivalent = 0;
  double grandTotal = 0;
  double tlEquivalent = 0;
}

pw.Widget _buildPdfRateSummaryTable(List<_RateSummary> summaries) {
  final headerStyle = pw.TextStyle(
    fontSize: 10,
    fontWeight: pw.FontWeight.bold,
  );
  final baseStyle = const pw.TextStyle(fontSize: 9);
  final tlStyle = pw.TextStyle(
    fontSize: 9,
    fontWeight: pw.FontWeight.bold,
    color: PdfColor.fromInt(0xFF0F172A),
    fontNormal: pw.Font.helvetica(),
    fontBold: pw.Font.helveticaBold(),
  );

  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.6),
    columnWidths: const {
      0: pw.FlexColumnWidth(1.1),
      1: pw.FlexColumnWidth(1.1),
      2: pw.FlexColumnWidth(1.3),
      3: pw.FlexColumnWidth(1.3),
      4: pw.FlexColumnWidth(1.3),
      5: pw.FlexColumnWidth(1.3),
      6: pw.FlexColumnWidth(1.3),
      7: pw.FlexColumnWidth(1.3),
    },
    children: [
      pw.TableRow(
        decoration: const pw.BoxDecoration(color: PdfColors.grey200),
        children: [
          _pdfHeaderCell('PB', headerStyle),
          _pdfHeaderCell('KDV Orani', headerStyle),
          _pdfHeaderCell('Matrah Toplami', headerStyle),
          _pdfHeaderCell('Matrah TL Karsiligi', headerStyle),
          _pdfHeaderCell('KDV Toplami', headerStyle),
          _pdfHeaderCell('KDV TL Karsiligi', headerStyle),
          _pdfHeaderCell('Vergili Toplam', headerStyle),
          _pdfHeaderCell('TL Karsiligi', headerStyle),
        ],
      ),
      ...summaries.map(
        (summary) => pw.TableRow(
          children: [
            _pdfBodyCell(summary.currency, baseStyle),
            _pdfBodyCell(_formatPercentValue(summary.taxRate), baseStyle),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.baseAmount, summary.currency),
              baseStyle,
            ),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.baseTlEquivalent, 'TRY'),
              tlStyle,
            ),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.taxAmount, summary.currency),
              baseStyle,
            ),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.taxTlEquivalent, 'TRY'),
              tlStyle,
            ),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.grandTotal, summary.currency),
              baseStyle,
            ),
            _pdfBodyCell(
              _formatAmountWithCurrency(summary.tlEquivalent, 'TRY'),
              tlStyle,
            ),
          ],
        ),
      ),
    ],
  );
}

pw.Widget _pdfHeaderCell(String text, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(text, style: style),
  );
}

pw.Widget _pdfBodyCell(String text, pw.TextStyle style) {
  return pw.Padding(
    padding: const pw.EdgeInsets.all(6),
    child: pw.Text(text, style: style),
  );
}

double _computeTlEquivalent(
  String currency,
  double amount,
  DateTime? invoiceDate,
  List<InvoicePdfFxRateRule> fxRules,
) {
  if (currency == 'TRY') return amount;
  if (invoiceDate == null) return 0;
  for (final rule in fxRules) {
    final sameCurrency = rule.currency.toUpperCase() == currency.toUpperCase();
    final startsOk = !_normalizeDate(invoiceDate).isBefore(_normalizeDate(rule.startDate));
    final endsOk = !_normalizeDate(invoiceDate).isAfter(_normalizeDate(rule.endDate));
    if (sameCurrency && startsOk && endsOk) {
      return amount * rule.rateToTry;
    }
  }
  return 0;
}

DateTime _normalizeDate(DateTime value) => DateTime(value.year, value.month, value.day);

void _applyRowStyle(
  excel.Sheet sheet, {
  required int rowIndex,
  required int columnCount,
  required excel.CellStyle style,
}) {
  for (var columnIndex = 0; columnIndex < columnCount; columnIndex += 1) {
    sheet
        .cell(
          excel.CellIndex.indexByColumnRow(
            columnIndex: columnIndex,
            rowIndex: rowIndex,
          ),
        )
        .cellStyle = style;
  }
}

List<double> _collectVatRates(List<InvoicePdfAnalysisListRow> rows) {
  final rates = <double>{
    for (final row in rows)
      ...row.vatBreakdowns.map((item) => item.taxRate),
  }.toList(growable: false)
    ..sort();
  return rates;
}
