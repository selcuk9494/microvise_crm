import 'dart:io';
import 'dart:typed_data';

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
}) async {
  final bytes = await buildWorkOrderPdfBytes(
    order: order,
    customer: customer,
    closeNotes: closeNotes,
    payments: payments,
    signaturePngBytes: signaturePngBytes,
  );

  final dir = await getTemporaryDirectory();
  final filename = _safeFilename(
    'is_emri_${order.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
  );
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  await Share.shareXFiles(
    [XFile(file.path, mimeType: 'application/pdf', name: filename)],
  );
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}

