import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> downloadExcelFile(List<int> bytes, String filename) async {
  await downloadBinaryFile(
    bytes,
    filename,
    mimeType:
        'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  );
}

Future<void> downloadBinaryFile(
  List<int> bytes,
  String filename, {
  required String mimeType,
}) async {
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
    XFile(file.path, mimeType: mimeType, name: safeName),
  ], sharePositionOrigin: origin);
}

Future<void> reloadCurrentPage() async {}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'export.xlsx' : input.trim();
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
