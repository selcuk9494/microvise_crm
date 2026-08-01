import 'package:intl/intl.dart';

import '../invoices/invoice_model.dart';
import '../invoices/invoice_statement_pdf.dart';
import '../invoices/invoice_statement_share.dart';

Future<bool> printEInvoice(Invoice invoice) async {
  final invoiceNumber = invoice.invoiceNumber.trim().isEmpty
      ? 'fatura'
      : invoice.invoiceNumber.trim();
  final customerName = invoice.customerName?.trim().isNotEmpty == true
      ? invoice.customerName!.trim()
      : 'Cari';

  await shareInvoiceStatementPdf(
    title: invoice.invoiceType == 'sales' ? 'Satış Faturası' : 'Alış Faturası',
    customerName: customerName,
    invoices: [invoice],
    filename:
        'fatura_ekstresi_${safeStatementFilePart(customerName)}_${safeStatementFilePart(invoiceNumber, fallback: 'fatura')}_${DateFormat('yyyyMMdd').format(invoice.invoiceDate)}.pdf',
  );
  return true;
}
