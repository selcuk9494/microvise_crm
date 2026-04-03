import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';
import 'work_order_pdf.dart';

Future<void> shareWorkOrderPdf({
  required WorkOrder order,
  required CustomerDetail customer,
  required String? closeNotes,
  required List<WorkOrderPayment> payments,
  Uint8List? signaturePngBytes,
  Uint8List? personnelSignaturePngBytes,
}) async {
  final bytes = await buildWorkOrderPdfBytes(
    order: order,
    customer: customer,
    closeNotes: closeNotes,
    payments: payments,
    signaturePngBytes: signaturePngBytes,
    personnelSignaturePngBytes: personnelSignaturePngBytes,
  );

  final dir = await getTemporaryDirectory();
  final filename = _safeFilename(
    'is_emri_${order.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
  );
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  try {
    final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
    final dpr = view?.devicePixelRatio ?? 1.0;
    final size = view == null
        ? const Size(1, 1)
        : Size(
            view.physicalSize.width / dpr,
            view.physicalSize.height / dpr,
          );
    final origin = Rect.fromLTWH(
      (size.width / 2 - 10).clamp(0.0, size.width - 20),
      (size.height / 2 - 10).clamp(0.0, size.height - 20),
      20,
      20,
    );
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf', name: filename)],
      sharePositionOrigin: origin,
    );
  } catch (e) {
    throw Exception(
      'WhatsApp paylaşımı açılamadı. WhatsApp yüklü mü? Hata: $e',
    );
  }
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
