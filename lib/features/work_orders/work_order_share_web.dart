// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:typed_data';

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

  final filename = _safeFilename(
    'is_emri_${order.id}_${DateTime.now().toIso8601String().substring(0, 10)}.pdf',
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

  final blob = html.Blob([bytes], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..setAttribute('download', filename)
    ..click();
  html.Url.revokeObjectUrl(url);
}

String _safeFilename(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}

