// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:share_plus/share_plus.dart';

import '../../core/format/search_normalize.dart';
import 'invoice_model.dart';
import 'invoice_statement_pdf.dart';

Future<void> shareInvoiceStatementPdf({
  required String title,
  required String customerName,
  required List<Invoice> invoices,
  required String filename,
  String? bankDetails,
}) async {
  final bytes = await buildInvoiceStatementPdfBytes(
    title: title,
    customerName: customerName,
    invoices: invoices,
    bankDetails: bankDetails,
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
  final dot = trimmed.lastIndexOf('.');
  final stem = dot > 0 ? trimmed.substring(0, dot) : trimmed;
  final ext = dot > 0 ? trimmed.substring(dot) : '';
  final safeStem = normalizeSearchText(stem)
      .replaceAll(RegExp(r'[^a-z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  final safeExt = ext
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9.]'), '');
  return '${safeStem.isEmpty ? 'ekstre' : safeStem}${safeExt.isEmpty ? '.pdf' : safeExt}';
}
