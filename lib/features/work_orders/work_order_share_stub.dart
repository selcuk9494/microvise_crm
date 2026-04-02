import 'dart:typed_data';

import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';

Future<void> shareWorkOrderPdf({
  required WorkOrder order,
  required CustomerDetail customer,
  required String? closeNotes,
  required List<WorkOrderPayment> payments,
  Uint8List? signaturePngBytes,
}) async {
  throw UnsupportedError('PDF paylaşımı bu platformda desteklenmiyor.');
}

