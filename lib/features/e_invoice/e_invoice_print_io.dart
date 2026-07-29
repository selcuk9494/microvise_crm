import 'package:intl/intl.dart';

import '../invoices/invoice_model.dart';
import '../invoices/invoice_statement_share.dart';

Future<bool> printEInvoice(Invoice invoice) async {
  final invoiceNumber = invoice.invoiceNumber.trim().isEmpty
      ? 'fatura'
      : invoice.invoiceNumber.trim();

  await shareInvoiceStatementPdf(
    title: invoice.invoiceType == 'sales' ? 'Satış Faturası' : 'Alış Faturası',
    customerName: invoice.customerName?.trim().isNotEmpty == true
        ? invoice.customerName!.trim()
        : 'Cari',
    invoices: [invoice],
    filename:
        'fatura_${_safeFilePart(invoiceNumber)}_${DateFormat('yyyyMMdd').format(invoice.invoiceDate)}.pdf',
  );
  return true;
}

String _safeFilePart(String input) {
  return input.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
