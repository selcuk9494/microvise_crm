import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

Future<void> shareMobileFormPdf({
  required String title,
  required String filename,
  required List<(String, String)> rows,
}) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final doc = pw.Document(
    title: title,
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );
  final theme = pw.ThemeData.withFont(base: regularFont, bold: regularFont);
  final dateFormat = DateFormat('dd.MM.yyyy HH:mm', 'tr_TR');

  doc.addPage(
    pw.MultiPage(
      pageTheme: pw.PageTheme(
        margin: const pw.EdgeInsets.all(28),
        theme: theme,
      ),
      build: (context) => [
        pw.Text(
          title,
          style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Text(
          'Microvise CRM - ${dateFormat.format(DateTime.now())}',
          style: const pw.TextStyle(fontSize: 8),
        ),
        pw.SizedBox(height: 14),
        pw.Table(
          border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
          columnWidths: const {
            0: pw.FlexColumnWidth(1.4),
            1: pw.FlexColumnWidth(2.8),
          },
          children: [
            for (final row in rows)
              if (row.$2.trim().isNotEmpty)
                pw.TableRow(
                  children: [
                    pw.Container(
                      padding: const pw.EdgeInsets.all(6),
                      color: PdfColors.grey100,
                      child: pw.Text(
                        row.$1,
                        style: pw.TextStyle(
                          fontSize: 8,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                    ),
                    pw.Padding(
                      padding: const pw.EdgeInsets.all(6),
                      child: pw.Text(
                        row.$2,
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                  ],
                ),
          ],
        ),
      ],
    ),
  );

  final bytes = await doc.save();
  final dir = await getTemporaryDirectory();
  final safeName = _safeFilename(filename);
  final file = File('${dir.path}/$safeName');
  await file.writeAsBytes(bytes, flush: true);

  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final dpr = view?.devicePixelRatio ?? 1.0;
  final size = view == null
      ? const Size(1, 1)
      : Size(view.physicalSize.width / dpr, view.physicalSize.height / dpr);
  final maxX = math.max<double>(size.width - 20, 0);
  final maxY = math.max<double>(size.height - 20, 0);
  final origin = Rect.fromLTWH(
    (size.width / 2 - 10).clamp(0.0, maxX),
    (size.height / 2 - 10).clamp(0.0, maxY),
    20,
    20,
  );

  await Share.shareXFiles([
    XFile(file.path, mimeType: 'application/pdf', name: safeName),
  ], sharePositionOrigin: origin);
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'form.pdf' : input.trim();
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
