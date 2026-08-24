import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../app/app_config.dart';
import 'quote_model.dart';
import 'quote_settings_model.dart';

const _thumbSize = 42.0;
const _thumbPadding = 3.0;
const _productCellPadding = pw.EdgeInsets.symmetric(horizontal: 6, vertical: 6);

String _pdfCurrencySymbol(String currency) {
  switch (currency) {
    case 'TRY':
      return '₺';
    case 'USD':
      return r'$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    default:
      return '$currency ';
  }
}

NumberFormat _pdfMoneyFormat(String currency) {
  return NumberFormat.currency(
    locale: 'tr_TR',
    symbol: _pdfCurrencySymbol(currency),
    decimalDigits: 2,
  );
}

Uint8List? _decodeDataUrl(String? dataUrl) {
  final raw = (dataUrl ?? '').trim();
  if (raw.isEmpty) return null;
  const prefix = 'base64,';
  final idx = raw.indexOf(prefix);
  if (idx < 0) return null;
  final b64 = raw.substring(idx + prefix.length).trim();
  if (b64.isEmpty) return null;
  try {
    return base64Decode(b64);
  } catch (_) {
    return null;
  }
}

Uri? _resolveImageUri(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;

  if (trimmed.startsWith('/')) {
    final base = (AppConfig.apiBaseUrl ?? 'https://crm.microvise.net/api').trim();
    if (base.startsWith('http://') || base.startsWith('https://')) {
      final baseUri = Uri.parse(base.endsWith('/') ? base : '$base/');
      if (trimmed.startsWith('/api/')) {
        return Uri.parse('${baseUri.origin}$trimmed');
      }
      return baseUri.resolve(trimmed.substring(1));
    }
    return null;
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null || !uri.hasScheme) return null;

  if ((uri.host == '127.0.0.1' || uri.host == 'localhost') &&
      uri.path.startsWith('/api/')) {
    final base = (AppConfig.apiBaseUrl ?? 'https://crm.microvise.net/api').trim();
    if (base.startsWith('http://') || base.startsWith('https://')) {
      return Uri.parse('${Uri.parse(base).origin}${uri.path}');
    }
  }

  return uri;
}

Future<Uint8List?> _loadImageBytes(String? imageRef) async {
  final raw = (imageRef ?? '').trim();
  if (raw.isEmpty) return null;
  if (raw.startsWith('data:')) return _decodeDataUrl(raw);
  final uri = _resolveImageUri(raw);
  if (uri == null) return null;
  try {
    final response = await http.get(uri).timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

Future<Uint8List> buildQuotePdfBytes({
  required Quote quote,
  QuoteDocumentSettings? settings,
  DateTime? generatedAt,
}) async {
  final docSettings = settings ?? QuoteDocumentSettings.defaults();
  final logoBytes = await _loadImageBytes(docSettings.logoUrl);
  final itemImages = <String, Uint8List>{};
  for (final item in quote.items) {
    final bytes = await _loadImageBytes(item.imageUrl);
    if (bytes != null && bytes.isNotEmpty) {
      itemImages[item.id] = bytes;
    }
  }

  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final theme = pw.ThemeData.withFont(base: regularFont, bold: regularFont);
  final doc = pw.Document(
    title: 'Teklif ${quote.quoteNumber}',
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );

  final dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final money = _pdfMoneyFormat(quote.currency);
  final created = generatedAt ?? DateTime.now();
  final navy = PdfColor.fromHex('#1E3A5F');

  String fmt(double value) => money.format(value);

  pw.Widget productCell(String description, Uint8List? imageBytes) {
    pw.Widget thumbBox({Uint8List? bytes}) {
      return pw.Container(
        width: _thumbSize,
        height: _thumbSize,
        decoration: pw.BoxDecoration(
          color: PdfColors.white,
          borderRadius: pw.BorderRadius.circular(4),
          border: pw.Border.all(color: PdfColors.grey300, width: 0.6),
        ),
        padding: const pw.EdgeInsets.all(_thumbPadding),
        child: bytes == null
            ? pw.Center(
                child: pw.Text(
                  '—',
                  style: pw.TextStyle(fontSize: 8, color: PdfColors.grey500),
                ),
              )
            : pw.Center(
                child: pw.Image(
                  pw.MemoryImage(bytes),
                  fit: pw.BoxFit.contain,
                ),
              ),
      );
    }

    return pw.Container(
      padding: _productCellPadding,
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          thumbBox(bytes: imageBytes),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Padding(
              padding: const pw.EdgeInsets.only(top: 2),
              child: pw.Text(
                description,
                style: const pw.TextStyle(fontSize: 9, lineSpacing: 1.2),
              ),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget dataCell(
    String text, {
    bool bold = false,
    pw.Alignment alignment = pw.Alignment.centerLeft,
    PdfColor? bg,
  }) {
    return pw.Container(
      alignment: alignment,
      color: bg,
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(28),
      theme: theme,
      build: (context) {
        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              color: navy,
              padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  if (logoBytes != null)
                    pw.Container(
                      height: 64,
                      constraints: const pw.BoxConstraints(maxWidth: 280),
                      child: pw.Image(
                        pw.MemoryImage(logoBytes),
                        fit: pw.BoxFit.contain,
                      ),
                    )
                  else
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          docSettings.companyTitle,
                          style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        if (docSettings.companySubtitle.trim().isNotEmpty) ...[
                          pw.SizedBox(height: 4),
                          pw.Text(
                            docSettings.companySubtitle,
                            style: const pw.TextStyle(color: PdfColors.white, fontSize: 10),
                          ),
                        ],
                      ],
                    ),
                  pw.Text(
                    'TEKLİF',
                    style: pw.TextStyle(
                      color: PdfColors.white,
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                      letterSpacing: 1.2,
                    ),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 16),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          'Müşteri',
                          style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
                        ),
                        pw.SizedBox(height: 4),
                        pw.Text(quote.customerName ?? '-', style: const pw.TextStyle(fontSize: 11)),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 12),
                pw.Expanded(
                  child: pw.Container(
                    padding: const pw.EdgeInsets.all(10),
                    decoration: pw.BoxDecoration(
                      border: pw.Border.all(color: PdfColors.grey300),
                    ),
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text('Teklif No: ${quote.quoteNumber}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text('Tarih: ${dateFormat.format(quote.quoteDate)}', style: const pw.TextStyle(fontSize: 10)),
                        if (quote.validUntil != null)
                          pw.Text(
                            'Geçerlilik: ${dateFormat.format(quote.validUntil!)}',
                            style: const pw.TextStyle(fontSize: 10),
                          ),
                        pw.Text('Durum: ${Quote.statusLabel(quote.status)}', style: const pw.TextStyle(fontSize: 10)),
                        pw.Text(
                          'Para Birimi: ${QuoteMoney.label(quote.currency)}',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                        pw.Text(
                          quote.pricesIncludeVat
                              ? 'Fiyat girişi: KDV dahil'
                              : 'Fiyat girişi: KDV hariç',
                          style: const pw.TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 16),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
              columnWidths: const {
                0: pw.FlexColumnWidth(3.4),
                1: pw.FlexColumnWidth(0.62),
                2: pw.FlexColumnWidth(0.62),
                3: pw.FlexColumnWidth(0.95),
                4: pw.FlexColumnWidth(0.58),
                5: pw.FlexColumnWidth(1),
              },
              children: [
                pw.TableRow(
                  decoration: pw.BoxDecoration(color: PdfColor.fromHex('#E8EEF5')),
                  children: [
                    dataCell('Ürün / Hizmet', bold: true),
                    dataCell('Miktar', bold: true, alignment: pw.Alignment.center),
                    dataCell('Birim', bold: true, alignment: pw.Alignment.center),
                    dataCell(
                      quote.pricesIncludeVat
                          ? 'Birim Fiyat*'
                          : 'Birim Fiyat',
                      bold: true,
                      alignment: pw.Alignment.centerRight,
                    ),
                    dataCell('KDV', bold: true, alignment: pw.Alignment.centerRight),
                    dataCell('Tutar', bold: true, alignment: pw.Alignment.centerRight),
                  ],
                ),
                for (final item in quote.items)
                  pw.TableRow(
                    children: [
                      productCell(item.description, itemImages[item.id]),
                      dataCell('${item.quantity}', alignment: pw.Alignment.center),
                      dataCell(item.unit, alignment: pw.Alignment.center),
                      dataCell(fmt(item.unitPrice), alignment: pw.Alignment.centerRight),
                      dataCell('${item.taxRate.toStringAsFixed(0)}%', alignment: pw.Alignment.centerRight),
                      dataCell(fmt(item.lineTotal), alignment: pw.Alignment.centerRight),
                    ],
                  ),
              ],
            ),
            if (quote.pricesIncludeVat) ...[
              pw.SizedBox(height: 4),
              pw.Text(
                '* Formda KDV dahil girildi; tablodaki birim fiyatlar KDV hariç (matrah) olarak gösterilir.',
                style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey700),
              ),
            ],
            pw.SizedBox(height: 12),
            pw.Align(
              alignment: pw.Alignment.centerRight,
              child: pw.Container(
                width: 220,
                padding: const pw.EdgeInsets.all(10),
                decoration: pw.BoxDecoration(
                  color: PdfColor.fromHex('#E8EEF5'),
                  border: pw.Border.all(color: navy, width: 0.8),
                ),
                child: pw.Column(
                  children: [
                    _totalRow('Ara Toplam', fmt(quote.subtotal)),
                    _totalRow('KDV', fmt(quote.taxTotal)),
                    if (quote.discountTotal > 0)
                      _totalRow('İndirim', fmt(quote.discountTotal)),
                    pw.Divider(color: navy),
                    pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('Genel Toplam', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: navy)),
                        pw.Text(fmt(quote.grandTotal), style: pw.TextStyle(fontWeight: pw.FontWeight.bold, color: navy)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if ((quote.notes ?? '').trim().isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text('Notlar', style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
              pw.SizedBox(height: 4),
              pw.Text(quote.notes!.trim(), style: const pw.TextStyle(fontSize: 9)),
            ],
            if (docSettings.termsAndConditions.trim().isNotEmpty) ...[
              pw.SizedBox(height: 14),
              pw.Text(
                'Özel Şartlar',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                docSettings.termsAndConditions.trim(),
                style: const pw.TextStyle(fontSize: 8, lineSpacing: 1.3),
              ),
            ],
            pw.Spacer(),
            if (docSettings.bankDetails.trim().isNotEmpty)
              pw.Container(
                color: navy,
                padding: const pw.EdgeInsets.all(10),
                child: pw.Text(
                  docSettings.bankDetails.trim(),
                  style: const pw.TextStyle(color: PdfColors.white, fontSize: 8),
                ),
              ),
            pw.SizedBox(height: 8),
            pw.Text(
              'Oluşturulma: ${dateFormat.format(created)} · '
              '${quote.pricesIncludeVat ? 'Formda KDV dahil girildi; satır birim fiyatları KDV hariçtir.' : 'Tutarlar KDV hariç gösterilmektedir.'}',
              style: const pw.TextStyle(fontSize: 7, color: PdfColors.grey600),
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}

pw.Widget _totalRow(String label, String value) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(vertical: 2),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(value, style: const pw.TextStyle(fontSize: 9)),
      ],
    ),
  );
}
