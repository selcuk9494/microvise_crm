import 'dart:typed_data';

import 'package:printing/printing.dart';

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
  final filename = _safeFilename(
    'is_emri_${order.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
  );
  await Printing.sharePdf(bytes: bytes, filename: filename);
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
