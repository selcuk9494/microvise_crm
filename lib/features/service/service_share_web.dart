import 'dart:js_interop';

import 'package:share_plus/share_plus.dart';
import 'package:web/web.dart' as web;

import 'service_detail_screen.dart';
import 'service_pdf.dart';

Future<void> shareServicePdf({
  required ServiceDetail detail,
  required List<String> accessoryNames,
}) async {
  final bytes = await buildServicePdfBytes(detail: detail, accessoryNames: accessoryNames);

  final filename = _safeFilename(
    'servis_${detail.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
  );

  try {
    await Share.shareXFiles(
      [
        XFile.fromData(
          bytes,
          mimeType: 'application/pdf',
          name: filename,
        ),
      ],
    );
    return;
  } catch (_) {}

  final blob = web.Blob(
    [bytes.toJS].toJS,
    web.BlobPropertyBag(type: 'application/pdf'),
  );
  final url = web.URL.createObjectURL(blob);
  final a = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  a.click();
  web.URL.revokeObjectURL(url);
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
