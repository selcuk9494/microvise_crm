// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:share_plus/share_plus.dart';

import 'invoice_model.dart';
import 'invoice_statement_pdf.dart';

Future<void> shareInvoiceStatementPdf({
  required String title,
  required String customerName,
  required List<Invoice> invoices,
  required String filename,
}) async {
  final bytes = await buildInvoiceStatementPdfBytes(
    title: title,
    customerName: customerName,
    invoices: invoices,
  );
  final safeName = _safeFilename(filename);

  try {
    await Share.shareXFiles([
      XFile.fromData(bytes, mimeType: 'application/pdf', name: safeName),
    ]);
    return;
  } catch (_) {}

  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', safeName)
    ..click();
  html.Url.revokeObjectUrl(url);
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'ekstre.pdf' : input.trim();
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
