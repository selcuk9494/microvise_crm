// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

import 'package:http/http.dart' as http;

class EInvoicePdfDownload {
  const EInvoicePdfDownload({required this.url, required this.fileName});

  final String url;
  final String fileName;
}

/// Web'de tek fatura için sekmede açmak daha doğal olduğundan paylaşım
/// devre dışı; çağıran taraf bağlantıyı açmaya geri düşer.
Future<bool> shareEInvoicePdf({
  required String url,
  required String fileName,
  required String shareText,
}) async {
  return false;
}

/// Toplu indirmede her PDF ayrı dosya olarak kaydedilir.
Future<bool> shareEInvoicePdfBundle({
  required List<EInvoicePdfDownload> files,
  required String shareText,
}) async {
  var saved = 0;
  for (final item in files) {
    try {
      final response = await http
          .get(Uri.parse(item.url))
          .timeout(const Duration(seconds: 60));
      if (response.statusCode < 200 || response.statusCode >= 300) continue;
      final blob = html.Blob([response.bodyBytes], 'application/pdf');
      final objectUrl = html.Url.createObjectUrlFromBlob(blob);
      html.AnchorElement(href: objectUrl)
        ..setAttribute('download', _safeFilename(item.fileName))
        ..click();
      html.Url.revokeObjectUrl(objectUrl);
      saved += 1;
    } catch (_) {
      // Tek bir dosya indirilemezse diğerlerine devam edilir.
    }
  }
  return saved > 0;
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'e_fatura.pdf' : input.trim();
  final cleaned = trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
  return cleaned.toLowerCase().endsWith('.pdf') ? cleaned : '$cleaned.pdf';
}
