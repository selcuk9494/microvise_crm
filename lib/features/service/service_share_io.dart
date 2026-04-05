import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import 'service_detail_screen.dart';
import 'service_pdf.dart';

Future<void> shareServicePdf({
  required ServiceDetail detail,
  required List<String> accessoryNames,
}) async {
  final bytes = await buildServicePdfBytes(detail: detail, accessoryNames: accessoryNames);

  final dir = await getTemporaryDirectory();
  final filename = _safeFilename(
    'servis_${detail.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
  );
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final dpr = view?.devicePixelRatio ?? 1.0;
  final size = view == null
      ? const Size(1, 1)
      : Size(
          view.physicalSize.width / dpr,
          view.physicalSize.height / dpr,
        );
  final maxX = math.max<double>(size.width - 20, 0);
  final maxY = math.max<double>(size.height - 20, 0);
  final origin = Rect.fromLTWH(
    (size.width / 2 - 10).clamp(0.0, maxX),
    (size.height / 2 - 10).clamp(0.0, maxY),
    20,
    20,
  );

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf', name: filename)],
    sharePositionOrigin: origin,
  );
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}

