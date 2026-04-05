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

  pw.Widget sigBox(String title, Uint8List? bytes) {
    final img = bytes == null || bytes.isEmpty ? null : pw.MemoryImage(bytes);
    return pw.Container(
      padding: const pw.EdgeInsets.all(10),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey300),
        borderRadius: pw.BorderRadius.circular(8),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(title, style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 8),
          pw.Container(
            height: 80,
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
                      style: const pw.TextStyle(color: PdfColors.grey600),
                    ),
                  )
                : pw.Image(img, fit: pw.BoxFit.contain),
          ),
        ],
      ),
    );
  }

  pw.Widget sectionTitle(String text) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 12, bottom: 6),
        child: pw.Text(text, style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
      );

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) {
        final imageWidgets = <pw.Widget>[];
        for (final url in detail.deviceImageDataUrls) {
          final bytes = _decodeDataUrl(url);
          if (bytes == null || bytes.isEmpty) continue;
          imageWidgets.add(
            pw.Container(
              padding: const pw.EdgeInsets.all(6),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey300),
                borderRadius: pw.BorderRadius.circular(8),
              ),
              child: pw.Image(pw.MemoryImage(bytes), fit: pw.BoxFit.cover),
            ),
          );
        }

        return [
          pw.Text(
            'SERVİS FORMU',
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Text('Tarih: $createdAtText'),
          pw.Text('Durum: $statusLabel'),
          pw.SizedBox(height: 12),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey300),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  detail.customerName ?? '—',
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
                pw.SizedBox(height: 4),
                pw.Text(detail.title),
                if (registry.isNotEmpty) pw.Text('Sicil No: $registry'),
                if (fault.isNotEmpty) pw.Text('Arıza Tipi: $fault'),
                if (detail.accessoriesReceived && accessoryNames.isNotEmpty)
                  pw.Text('Aksesuar: ${accessoryNames.join(', ')}'),
              ],
            ),
          ),
          if (notes.isNotEmpty) ...[
            sectionTitle('Not'),
            pw.Text(notes),
          ],
          if (detail.steps.isNotEmpty) ...[
            sectionTitle('Yapılan İşlemler'),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final s in detail.steps)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 4),
                    child: pw.Bullet(text: s),
                  ),
              ],
            ),
          ],
          if (detail.parts.isNotEmpty) ...[
            sectionTitle('Parçalar'),
            pw.TableHelper.fromTextArray(
              border: null,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
              },
              data: [
                ['Parça', 'Adet', 'Birim'],
                for (final p in detail.parts)
                  [
                    (p['name'] ?? '').toString(),
                    (p['qty'] ?? '').toString(),
                    (p['unit_price'] ?? '').toString(),
                  ],
              ],
            ),
          ],
          if (detail.labor.isNotEmpty) ...[
            sectionTitle('İşçilik'),
            pw.TableHelper.fromTextArray(
              border: null,
              headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.grey200),
              cellAlignment: pw.Alignment.centerLeft,
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FlexColumnWidth(1),
                2: pw.FlexColumnWidth(1),
              },
              data: [
                ['İşçilik', 'Adet', 'Birim'],
                for (final p in detail.labor)
                  [
                    (p['name'] ?? '').toString(),
                    (p['qty'] ?? '').toString(),
                    (p['unit_price'] ?? '').toString(),
                  ],
              ],
            ),
          ],
          if (imageWidgets.isNotEmpty) ...[
            sectionTitle('Cihaz Fotoğrafları'),
            pw.Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final w in imageWidgets)
                  pw.SizedBox(width: 240, height: 180, child: w),
              ],
            ),
          ],
          sectionTitle('İmzalar (Teslim Alma)'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: sigBox('Teslim Eden', _decodeDataUrl(detail.intakeCustomerSignatureDataUrl))),
              pw.SizedBox(width: 10),
              pw.Expanded(child: sigBox('Teslim Alan', _decodeDataUrl(detail.intakePersonnelSignatureDataUrl))),
            ],
          ),
          sectionTitle('İmzalar (Teslim)'),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: sigBox('Teslim Eden', _decodeDataUrl(detail.deliveryPersonnelSignatureDataUrl))),
              pw.SizedBox(width: 10),
              pw.Expanded(child: sigBox('Teslim Alan', _decodeDataUrl(detail.deliveryCustomerSignatureDataUrl))),
            ],
          ),
        ];
      },
    ),
  );

  return doc.save();
}
