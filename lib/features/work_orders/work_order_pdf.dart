import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';

Future<Uint8List> buildWorkOrderPdfBytes({
  required WorkOrder order,
  required CustomerDetail customer,
  required String? closeNotes,
  required List<WorkOrderPayment> payments,
  Uint8List? signaturePngBytes,
}) async {
  final doc = pw.Document(
    title: 'Is Emri - ${order.title}',
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );

  final dateFormat = DateFormat('d MMMM y HH:mm', 'tr_TR');
  final scheduled = order.scheduledDate == null
      ? null
      : dateFormat.format(order.scheduledDate!);
  final created = order.createdAt == null ? null : dateFormat.format(order.createdAt!);
  final closed = order.closedAt == null ? null : dateFormat.format(order.closedAt!);

  final address = (order.address ?? '').trim();
  final city = (order.city ?? '').trim();
  final addressText = [
    if (address.isNotEmpty) address,
    if (city.isNotEmpty) city,
  ].join(' • ');

  final money = NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2);

  double totalTry = 0;
  for (final p in payments) {
    if (p.currency == 'TRY') {
      totalTry += p.amount;
    }
  }

  pw.Widget infoRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 120,
            child: pw.Text(
              '$label:',
              style: pw.TextStyle(
                fontSize: 10,
                color: PdfColors.grey700,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Expanded(
            child: pw.Text(
              value,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget sectionTitle(String text) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.grey200,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Text(
        text,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    );
  }

  pw.Widget paymentTable() {
    if (payments.isEmpty) {
      return pw.Text('Ödeme yok', style: const pw.TextStyle(fontSize: 10));
    }

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.2),
        1: pw.FlexColumnWidth(1.2),
        2: pw.FlexColumnWidth(1.2),
        3: pw.FlexColumnWidth(3.0),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey100),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Tarih', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Tutar', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Döviz', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(6),
              child: pw.Text('Açıklama', style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            ),
          ],
        ),
        for (final p in payments)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  p.paidAt == null ? '' : dateFormat.format(p.paidAt!),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  money.format(p.amount),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(p.currency, style: const pw.TextStyle(fontSize: 9)),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(
                  (p.description ?? '').trim(),
                  style: const pw.TextStyle(fontSize: 9),
                ),
              ),
            ],
          ),
      ],
    );
  }

  final signature = signaturePngBytes == null || signaturePngBytes.isEmpty
      ? null
      : pw.MemoryImage(signaturePngBytes);

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(24),
      build: (context) => [
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'İş Emri Kapanış Raporu',
                    style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
                  ),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    order.title.trim(),
                    style: pw.TextStyle(fontSize: 12, color: PdfColors.grey700),
                  ),
                ],
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: pw.BoxDecoration(
                color: PdfColors.blue50,
                borderRadius: pw.BorderRadius.circular(999),
                border: pw.Border.all(color: PdfColors.blue200),
              ),
              child: pw.Text(
                order.status == 'done' ? 'Kapalı' : order.status,
                style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.blue900,
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        sectionTitle('Genel Bilgiler'),
        pw.SizedBox(height: 8),
        infoRow('Müşteri', customer.name),
        if ((customer.phone1 ?? '').trim().isNotEmpty) infoRow('Telefon', customer.phone1!.trim()),
        if ((customer.email ?? '').trim().isNotEmpty) infoRow('E-posta', customer.email!.trim()),
        if (addressText.isNotEmpty) infoRow('Adres', addressText),
        if ((order.branchName ?? '').trim().isNotEmpty) infoRow('Şube', order.branchName!.trim()),
        if ((order.assignedPersonnelName ?? '').trim().isNotEmpty)
          infoRow('Atanan', order.assignedPersonnelName!.trim()),
        if ((order.workOrderTypeName ?? '').trim().isNotEmpty)
          infoRow('Tip', order.workOrderTypeName!.trim()),
        if (scheduled != null) infoRow('Plan', scheduled),
        if (created != null) infoRow('Oluşturma', created),
        if (closed != null) infoRow('Kapanış', closed),
        pw.SizedBox(height: 14),
        sectionTitle('Yapılan İşlem / Detay'),
        pw.SizedBox(height: 8),
        pw.Text(
          (closeNotes ?? '').trim().isEmpty ? '—' : closeNotes!.trim(),
          style: const pw.TextStyle(fontSize: 10),
        ),
        if ((order.description ?? '').trim().isNotEmpty) ...[
          pw.SizedBox(height: 8),
          pw.Container(
            padding: const pw.EdgeInsets.all(10),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
              border: pw.Border.all(color: PdfColors.grey300),
            ),
            child: pw.Text(
              (order.description ?? '').trim(),
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
        pw.SizedBox(height: 14),
        sectionTitle('Ödemeler'),
        pw.SizedBox(height: 8),
        paymentTable(),
        if (payments.isNotEmpty) ...[
          pw.SizedBox(height: 10),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              'Toplam (TRY): ${money.format(totalTry)}',
              style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
            ),
          ),
        ],
        pw.SizedBox(height: 14),
        sectionTitle('Müşteri İmzası'),
        pw.SizedBox(height: 8),
        signature == null
            ? pw.Container(
                padding: const pw.EdgeInsets.all(14),
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                child: pw.Text(
                  'İmza kaydı yok.',
                  style: pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
                ),
              )
            : pw.Container(
                height: 140,
                decoration: pw.BoxDecoration(
                  borderRadius: pw.BorderRadius.circular(8),
                  border: pw.Border.all(color: PdfColors.grey300),
                ),
                padding: const pw.EdgeInsets.all(8),
                child: pw.Image(signature, fit: pw.BoxFit.contain),
              ),
      ],
    ),
  );

  return doc.save();
}
