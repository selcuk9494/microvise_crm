import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'invoice_model.dart';

Future<Uint8List> buildInvoiceStatementPdfBytes({
  required String title,
  required String customerName,
  required List<Invoice> invoices,
  DateTime? generatedAt,
}) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final theme = pw.ThemeData.withFont(base: regularFont, bold: regularFont);
  final doc = pw.Document(
    title: title,
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );

  final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '',
    decimalDigits: 2,
  );
  final created = generatedAt ?? DateTime.now();
  final ordered = [...invoices]
    ..sort((a, b) => a.invoiceDate.compareTo(b.invoiceDate));

  String amount(Invoice invoice, double value) {
    final symbol = switch (invoice.currency) {
      'USD' => 'USD ',
      'EUR' => 'EUR ',
      'GBP' => 'GBP ',
      _ => 'TRY ',
    };
    return '$symbol${money.format(value)}';
  }

  final totalsByCurrency =
      <String, ({double total, double paid, double remaining})>{};
  for (final invoice in ordered) {
    final current =
        totalsByCurrency[invoice.currency] ?? (total: 0, paid: 0, remaining: 0);
    totalsByCurrency[invoice.currency] = (
      total: current.total + invoice.grandTotal,
      paid: current.paid + invoice.paidAmount,
      remaining: current.remaining + invoice.remainingAmount,
    );
  }

  pw.TextStyle labelStyle() =>
      pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  pw.TextStyle valueStyle() => const pw.TextStyle(fontSize: 8);
  pw.TextStyle smallStyle() => const pw.TextStyle(fontSize: 7);

  pw.Widget cell(
    String text, {
    double fontSize = 8,
    bool bold = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
  }) {
    return pw.Container(
      alignment: alignment,
      padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 5),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: fontSize,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget invoiceRows() {
    if (ordered.isEmpty) {
      return pw.Container(
        padding: const pw.EdgeInsets.all(14),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey300),
        ),
        child: pw.Text('Ekstreye dahil edilecek fatura bulunmuyor.'),
      );
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.2),
        1: pw.FlexColumnWidth(1.6),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(1.1),
        4: pw.FlexColumnWidth(1.25),
        5: pw.FlexColumnWidth(1.25),
        6: pw.FlexColumnWidth(1.25),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EFF6FF')),
          children: [
            cell('Tarih', bold: true),
            cell('Fatura No', bold: true),
            cell('Tür', bold: true),
            cell('Durum', bold: true),
            cell('Toplam', bold: true, alignment: pw.Alignment.centerRight),
            cell('Ödenen', bold: true, alignment: pw.Alignment.centerRight),
            cell('Kalan', bold: true, alignment: pw.Alignment.centerRight),
          ],
        ),
        for (final invoice in ordered)
          pw.TableRow(
            children: [
              cell(dateFormat.format(invoice.invoiceDate)),
              cell(invoice.invoiceNumber),
              cell(invoice.invoiceType == 'sales' ? 'Satış' : 'Alış'),
              cell(_statusLabel(invoice.status)),
              cell(
                amount(invoice, invoice.grandTotal),
                alignment: pw.Alignment.centerRight,
              ),
              cell(
                amount(invoice, invoice.paidAmount),
                alignment: pw.Alignment.centerRight,
              ),
              cell(
                amount(invoice, invoice.remainingAmount),
                alignment: pw.Alignment.centerRight,
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget totals() {
    final keys = totalsByCurrency.keys.toList()..sort();
    if (keys.isEmpty) return pw.SizedBox();
    return pw.Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final key in keys)
          pw.Container(
            width: 170,
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              color: PdfColors.grey100,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(key, style: labelStyle()),
                pw.SizedBox(height: 4),
                pw.Text(
                  'Toplam: ${money.format(totalsByCurrency[key]!.total)}',
                  style: valueStyle(),
                ),
                pw.Text(
                  'Ödenen: ${money.format(totalsByCurrency[key]!.paid)}',
                  style: valueStyle(),
                ),
                pw.Text(
                  'Kalan: ${money.format(totalsByCurrency[key]!.remaining)}',
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
      ),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Sayfa ${context.pageNumber}/${context.pagesCount}',
          style: smallStyle(),
        ),
      ),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    title,
                    style: pw.TextStyle(
                      fontSize: 18,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    customerName,
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                ],
              ),
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text('Microvise CRM', style: labelStyle()),
                pw.SizedBox(height: 3),
                pw.Text(dateFormat.format(created), style: valueStyle()),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 14),
        totals(),
        pw.SizedBox(height: 14),
        invoiceRows(),
      ],
    ),
  );

  return doc.save();
}

String _statusLabel(String status) {
  return switch (status) {
    'draft' => 'Taslak',
    'open' => 'Açık',
    'partial' => 'Kısmi',
    'paid' => 'Kapalı',
    'cancelled' => 'İptal',
    _ => status,
  };
}
