import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/app_time.dart';
import 'service_detail_screen.dart';

Uint8List? _decodeDataUrl(String? dataUrl) {
  final raw = (dataUrl ?? '').trim();
  if (raw.isEmpty) return null;
  final prefix = 'base64,';
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

Future<Uint8List> buildServicePdfBytes({
  required ServiceDetail detail,
  required List<String> accessoryNames,
}) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final theme = pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
  );

  final doc = pw.Document(
    title: 'Servis - ${detail.title}',
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );

  final dateTimeFormat = DateFormat('d MMMM y HH:mm', 'tr_TR');
  final createdAtText = dateTimeFormat.format(AppTime.toTr(detail.createdAt));

  final currencyCode = (detail.currency ?? 'TRY').toUpperCase();
  final currencySymbol = switch (currencyCode) {
    'USD' => r'$',
    'EUR' => '€',
    _ => '₺',
  };
  final moneyFormat = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: currencySymbol,
    decimalDigits: 2,
  );

  final statusLabel = switch (detail.status) {
    'waiting' || 'open' => 'Bekliyor',
    'approval' || 'in_progress' => 'Onayda',
    'ready' => 'Hazır',
    'done' => 'Teslim',
    _ => detail.status,
  };

  final registry = (detail.registryNumber ?? '').trim();
  final fault = (detail.faultTypeName ?? '').trim();
  final notes = (detail.notes ?? '').trim();
  final serviceNoText =
      detail.serviceNo == null ? 'SRV' : 'SRV-${detail.serviceNo}';

  pw.Widget sigBox(String title, Uint8List? bytes) {
    final img = bytes == null || bytes.isEmpty ? null : pw.MemoryImage(bytes);
    return pw.Container(
      padding: const pw.EdgeInsets.all(6),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 4),
          pw.Container(
            height: 55,
            width: double.infinity,
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(6),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: img == null
                ? pw.Center(
                    child: pw.Text(
                      '—',
                      style: const pw.TextStyle(
                        color: PdfColors.grey600,
                        fontSize: 10,
                      ),
                    ),
                  )
                : pw.Image(img, fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );
  }

  doc.addPage(
    pw.Page(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(18),
      build: (context) {
        final imageWidgets = <pw.Widget>[];
        for (final url in detail.deviceImageDataUrls.take(4)) {
          final bytes = _decodeDataUrl(url);
          if (bytes == null || bytes.isEmpty) continue;
          imageWidgets.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(3),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
            ),
          );
        }

        String clip(String v, int max) {
          final t = v.trim();
          if (t.length <= max) return t;
          return '${t.substring(0, max).trimRight()}…';
        }

        pw.Widget titleText(String v) => pw.Text(
              v,
              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
            );

        pw.Widget kv(String k, String v) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.SizedBox(
                    width: 64,
                    child: pw.Text(
                      k,
                      style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                    ),
                  ),
                  pw.Expanded(
                    child: pw.Text(
                      v,
                      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                    ),
                  ),
                ],
              ),
            );

        pw.Widget section(String title, pw.Widget child) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(8),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 6),
                child,
              ],
            ),
          );
        }

        pw.Widget compactTable({
          required String header0,
          required List<Map<String, dynamic>> rows,
          required int maxRows,
        }) {
          final visible = rows.take(maxRows).toList(growable: false);
          final hiddenCount = rows.length - visible.length;
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.TableHelper.fromTextArray(
                border: null,
                headerStyle: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
                headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
                cellStyle: const pw.TextStyle(fontSize: 9),
                cellAlignment: pw.Alignment.centerLeft,
                columnWidths: const {
                  0: pw.FlexColumnWidth(3.5),
                  1: pw.FlexColumnWidth(0.9),
                  2: pw.FlexColumnWidth(1.1),
                  3: pw.FlexColumnWidth(1.2),
                },
                data: [
                  [header0, 'Adet', 'Birim', 'Tutar'],
                  for (final r in visible)
                    [
                      clip((r['name'] ?? '').toString(), 34),
                      (r['qty'] ?? '').toString(),
                      moneyFormat.format((r['unit_price'] as num?) ?? double.tryParse((r['unit_price'] ?? '').toString()) ?? 0),
                      moneyFormat.format(
                        ((r['qty'] as num?) ?? double.tryParse((r['qty'] ?? '').toString()) ?? 0) *
                            ((r['unit_price'] as num?) ?? double.tryParse((r['unit_price'] ?? '').toString()) ?? 0),
                      ),
                    ],
                ],
              ),
              if (hiddenCount > 0)
                pw.Padding(
                  padding: const pw.EdgeInsets.only(top: 4),
                  child: pw.Text(
                    '+$hiddenCount satır daha',
                    style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                  ),
                ),
            ],
          );
        }

        final accessoryText = accessoryNames.join(', ');
        final clippedAccessory = clip(accessoryText, 72);

        final clippedNotes = clip(notes, 220);
        final visibleSteps = detail.steps.take(6).toList(growable: false);
        final hiddenSteps = detail.steps.length - visibleSteps.length;

        final totalText = moneyFormat.format(detail.totalAmount ?? 0);

        return pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'SERVİS FORMU',
                        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                      ),
                      pw.SizedBox(height: 2),
                      titleText('$serviceNoText • $statusLabel • $createdAtText'),
                    ],
                  ),
                ),
                pw.Container(
                  padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: pw.BoxDecoration(
                    color: PdfColors.grey200,
                    borderRadius: pw.BorderRadius.circular(10),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text(
                        'TOPLAM',
                        style: pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
                      ),
                      pw.Text(
                        totalText,
                        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: section(
                    'Müşteri & Cihaz',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          clip(detail.customerName ?? '—', 48),
                          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
                        ),
                        pw.SizedBox(height: 4),
                        kv('Başlık', clip(detail.title, 70)),
                        if (registry.isNotEmpty) kv('Sicil', clip(registry, 40)),
                        if (fault.isNotEmpty) kv('Arıza', clip(fault, 40)),
                        if (detail.accessoriesReceived && accessoryNames.isNotEmpty)
                          kv('Aksesuar', clippedAccessory),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: section(
                    'İşlem Özeti',
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        if (clippedNotes.isNotEmpty) ...[
                          pw.Text(
                            clip(clippedNotes, 220),
                            style: const pw.TextStyle(fontSize: 9),
                          ),
                          pw.SizedBox(height: 6),
                        ],
                        if (visibleSteps.isNotEmpty) ...[
                          for (final s in visibleSteps)
                            pw.Padding(
                              padding: const pw.EdgeInsets.only(bottom: 2),
                              child: pw.Bullet(
                                text: clip(s, 52),
                                style: const pw.TextStyle(fontSize: 9),
                              ),
                            ),
                          if (hiddenSteps > 0)
                            pw.Text(
                              '+$hiddenSteps adım daha',
                              style: pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
                            ),
                        ] else
                          pw.Text(
                            '—',
                            style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: section(
                    'Parça',
                    detail.parts.isEmpty
                        ? pw.Text('—', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
                        : compactTable(
                            header0: 'Parça',
                            rows: detail.parts,
                            maxRows: 6,
                          ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: section(
                    'İşçilik',
                    detail.labor.isEmpty
                        ? pw.Text('—', style: pw.TextStyle(fontSize: 10, color: PdfColors.grey600))
                        : compactTable(
                            header0: 'İşçilik',
                            rows: detail.labor,
                            maxRows: 6,
                          ),
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
            if (imageWidgets.isNotEmpty)
              section(
                'Fotoğraflar',
                pw.Row(
                  children: [
                    for (final w in imageWidgets)
                      pw.Padding(
                        padding: const pw.EdgeInsets.only(right: 6),
                        child: pw.SizedBox(width: 96, height: 72, child: w),
                      ),
                  ],
                ),
              ),
            if (imageWidgets.isNotEmpty) pw.SizedBox(height: 10),
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Expanded(
                  child: section(
                    'İmzalar (Teslim Alma)',
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: sigBox(
                            'Teslim Eden',
                            _decodeDataUrl(detail.intakeCustomerSignatureDataUrl),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: sigBox(
                            'Teslim Alan',
                            _decodeDataUrl(detail.intakePersonnelSignatureDataUrl),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                pw.SizedBox(width: 10),
                pw.Expanded(
                  child: section(
                    'İmzalar (Teslim)',
                    pw.Row(
                      children: [
                        pw.Expanded(
                          child: sigBox(
                            'Teslim Eden',
                            _decodeDataUrl(detail.deliveryPersonnelSignatureDataUrl),
                          ),
                        ),
                        pw.SizedBox(width: 8),
                        pw.Expanded(
                          child: sigBox(
                            'Teslim Alan',
                            _decodeDataUrl(detail.deliveryCustomerSignatureDataUrl),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    ),
  );

  return doc.save();
}
