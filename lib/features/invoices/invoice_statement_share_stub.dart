import 'invoice_model.dart';

Future<void> shareInvoiceStatementPdf({
  required String title,
  required String customerName,
  required List<Invoice> invoices,
  required String filename,
}) async {
  throw UnsupportedError('PDF paylaşımı bu platformda desteklenmiyor.');
}
