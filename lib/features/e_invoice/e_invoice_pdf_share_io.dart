import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class EInvoicePdfDownload {
  const EInvoicePdfDownload({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

/// İmzalı depolama bağlantısını paylaşmak yerine PDF'i indirip dosya olarak
/// paylaşır; böylece paylaşım metninde uzun URL değil fatura bilgisi görünür.
Future<bool> shareEInvoicePdf({
  required String url,
  required String fileName,
  required String shareText,
}) async {
  return shareEInvoicePdfBundle(
    files: [EInvoicePdfDownload(url: url, fileName: fileName)],
    shareText: shareText,
  );
}

Future<bool> shareEInvoicePdfBundle({
  required List<EInvoicePdfDownload> files,
  required String shareText,
}) async {
  if (files.isEmpty) return false;

  final dir = await getTemporaryDirectory();
  final attachments = <XFile>[];
  for (final item in files) {
    final response = await http
        .get(Uri.parse(item.url))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) continue;
    final safeName = _safeFilename(item.fileName);
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(response.bodyBytes, flush: true);
    attachments.add(
      XFile(file.path, mimeType: 'application/pdf', name: safeName),
    );
  }
  if (attachments.isEmpty) return false;

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

  await Share.shareXFiles(
    attachments,
    text: shareText,
    subject: shareText,
    sharePositionOrigin: origin,
  );
  return true;
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'e_fatura.pdf' : input.trim();
  final cleaned = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
}
