// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:convert';
import 'dart:html' as html;
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class EInvoicePdfDownload {
  const EInvoicePdfDownload({
    required this.url,
    required this.fileName,
    this.localPath,
    this.pdfBase64,
  });

  final String url;
  final String fileName;

  /// Electron/yerel API: disk üzerindeki mutlak PDF yolu.
  final String? localPath;

  /// CRM oturumuyla üretilen PDF; imzalı URL gerekmez.
  final String? pdfBase64;
}

Uri _resolvePdfUri(String url) {
  final trimmed = url.trim();
  final parsed = Uri.parse(trimmed);
  if (parsed.hasScheme) return parsed;
  return Uri.base.resolve(trimmed);
}

String? _localPathFromOpenPdfUrl(String url) {
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final path = uri.path;
  if (!path.contains('/api/_local/open-pdf')) return null;
  final filePath = uri.queryParameters['path']?.trim();
  return (filePath != null && filePath.isNotEmpty) ? filePath : null;
}

/// Web'de tek fatura için sekmede açmak daha doğal olduğundan paylaşım
/// devre dışı; çağıran taraf bağlantıyı açmaya geri düşer.
Future<bool> shareEInvoicePdf({
  required String url,
  required String fileName,
  required String shareText,
  String? pdfBase64,
}) async {
  final inline = pdfBase64?.trim();
  if (inline != null && inline.isNotEmpty) {
    try {
      final bytes = base64Decode(inline);
      final safeName = _safeFilename(fileName);
      if (_triggerBlobDownload(
        Uint8List.fromList(bytes),
        safeName,
        'application/pdf',
      )) {
        return true;
      }
    } catch (_) {
      // URL yedeğine düşülür.
    }
  }
  return false;
}

/// Toplu indirmede her PDF ayrı dosya olarak kaydedilir.
Future<bool> shareEInvoicePdfBundle({
  required List<EInvoicePdfDownload> files,
  required String shareText,
}) async {
  return downloadEInvoicePdfs(files: files);
}

/// Seçilen PDF'leri tek tek ayrı dosya olarak indirir (ZIP yok).
Future<bool> downloadEInvoicePdfs({
  required List<EInvoicePdfDownload> files,
}) async {
  if (files.isEmpty) return false;

  var saved = 0;
  final usedNames = <String>{};

  for (final item in files) {
    try {
      final safeName = _uniqueFilename(
        _safeFilename(item.fileName),
        usedNames,
      );
      usedNames.add(safeName.toLowerCase());

      final local =
          (item.localPath?.trim().isNotEmpty ?? false)
          ? item.localPath!.trim()
          : _localPathFromOpenPdfUrl(item.url);

      // Electron: yerel PDF'i Downloads'a kopyala (download=1).
      if (local != null && local.isNotEmpty) {
        final downloadUri = Uri.base
            .resolve('/api/_local/open-pdf')
            .replace(
              queryParameters: {
                'path': local,
                'download': '1',
                'name': safeName,
              },
            );
        if (_openDownloadUrl(downloadUri.toString())) {
          saved += 1;
          await Future<void>.delayed(const Duration(milliseconds: 350));
          continue;
        }
      }

      Uint8List? bytes;
      final inline = item.pdfBase64?.trim();
      if (inline != null && inline.isNotEmpty) {
        try {
          bytes = Uint8List.fromList(base64Decode(inline));
        } catch (_) {
          bytes = null;
        }
      }
      if (bytes == null || bytes.isEmpty) {
        final url = item.url.trim();
        if (url.isEmpty) continue;
        final response = await http
            .get(_resolvePdfUri(url))
            .timeout(const Duration(seconds: 60));
        if (response.statusCode < 200 || response.statusCode >= 300) continue;
        bytes = response.bodyBytes;
      }
      final savedLocal = await _saveExportViaLocalApi(
        bytes: bytes,
        fileName: safeName,
      );
      if (savedLocal) {
        saved += 1;
      } else if (_triggerBlobDownload(bytes, safeName, 'application/pdf')) {
        saved += 1;
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    } catch (_) {
      // Tek bir dosya indirilemezse diğerlerine devam edilir.
    }
  }
  return saved > 0;
}

Future<bool> _saveExportViaLocalApi({
  required Uint8List bytes,
  required String fileName,
}) async {
  try {
    final response = await http
        .post(
          Uri.base.resolve('/api/_local/save-export'),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode({
            'fileName': fileName,
            'base64': base64Encode(bytes),
          }),
        )
        .timeout(const Duration(seconds: 120));
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return false;
    if (decoded['ok'] != true) return false;
    final url = decoded['url']?.toString().trim() ?? '';
    if (url.isEmpty) return false;
    return _openDownloadUrl(url);
  } catch (_) {
    return false;
  }
}

bool _openDownloadUrl(String url) {
  final resolved = _resolvePdfUri(url).toString();
  // Electron open-pdf'i yakalayıp pencereyi deny eder; dosya yine teslim edilir.
  html.window.open(resolved, '_blank');
  return true;
}

bool _triggerBlobDownload(Uint8List bytes, String fileName, String mimeType) {
  final blob = html.Blob([bytes], mimeType);
  final objectUrl = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: objectUrl)
    ..setAttribute('download', fileName)
    ..click();
  Future<void>.delayed(const Duration(seconds: 2), () {
    html.Url.revokeObjectUrl(objectUrl);
  });
  return true;
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
