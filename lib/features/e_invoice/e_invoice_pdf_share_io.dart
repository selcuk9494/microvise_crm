import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

class EInvoicePdfDownload {
  const EInvoicePdfDownload({
    required this.url,
    required this.fileName,
    this.localPath,
    this.pdfBase64,
  });

  final String url;
  final String fileName;
  final String? localPath;

  /// CRM oturumuyla üretilen PDF; imzalı URL gerekmez.
  final String? pdfBase64;
}

/// İmzalı depolama bağlantısını paylaşmak yerine PDF'i indirip dosya olarak
/// paylaşır; böylece paylaşım metninde uzun URL değil fatura bilgisi görünür.
Future<bool> shareEInvoicePdf({
  required String url,
  required String fileName,
  required String shareText,
  String? pdfBase64,
}) async {
  return shareEInvoicePdfBundle(
    files: [
      EInvoicePdfDownload(
        url: url,
        fileName: fileName,
        pdfBase64: pdfBase64,
      ),
    ],
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
  final usedNames = <String>{};
  for (final item in files) {
    final bytes = await _resolvePdfBytes(item);
    if (bytes == null || bytes.isEmpty) continue;
    final safeName = _uniqueFilename(_safeFilename(item.fileName), usedNames);
    usedNames.add(safeName.toLowerCase());
    final file = File('${dir.path}/$safeName');
    await file.writeAsBytes(bytes, flush: true);
    attachments.add(
      XFile(file.path, mimeType: 'application/pdf', name: safeName),
    );
  }
  if (attachments.isEmpty) return false;

  await _shareFiles(attachments, shareText);
  return true;
}

/// Seçilen PDF'leri tek tek ayrı dosya olarak kaydeder/paylaşır (ZIP yok).
Future<bool> downloadEInvoicePdfs({
  required List<EInvoicePdfDownload> files,
}) async {
  return shareEInvoicePdfBundle(
    files: files,
    shareText: 'E-faturalar',
  );
}

Future<Uint8List?> _resolvePdfBytes(EInvoicePdfDownload item) async {
  final inline = item.pdfBase64?.trim();
  if (inline != null && inline.isNotEmpty) {
    try {
      return Uint8List.fromList(base64Decode(inline));
    } catch (_) {
      // URL yedeğine düş.
    }
  }

  final url = item.url.trim();
  if (url.isEmpty) return null;
  try {
    final response = await http
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 60));
    if (response.statusCode < 200 || response.statusCode >= 300) return null;
    return response.bodyBytes;
  } catch (_) {
    return null;
  }
}

Future<void> _shareFiles(List<XFile> attachments, String shareText) async {
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
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'e_fatura.pdf' : input.trim();
  final cleaned = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
}

String _uniqueFilename(String name, Set<String> usedLower) {
  if (!usedLower.contains(name.toLowerCase())) return name;
  final dot = name.lastIndexOf('.');
  final stem = dot > 0 ? name.substring(0, dot) : name;
  final ext = dot > 0 ? name.substring(dot) : '';
  var i = 2;
  while (true) {
    final candidate = '${stem}_$i$ext';
    if (!usedLower.contains(candidate.toLowerCase())) return candidate;
    i += 1;
  }
}
