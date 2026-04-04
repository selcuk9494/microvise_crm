import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../core/utils/app_time.dart';
import '../customers/customer_detail_screen.dart';
import 'work_order_model.dart';

Future<Uint8List> buildWorkOrderPdfBytes({
  required WorkOrder order,
  required CustomerDetail customer,
  required String? closeNotes,
  required List<WorkOrderPayment> payments,
  Uint8List? signaturePngBytes,
  Uint8List? personnelSignaturePngBytes,
}) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final boldFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final italicFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Italic.ttf'),
  );
  final theme = pw.ThemeData.withFont(
    base: regularFont,
    bold: boldFont,
    italic: italicFont,
  );

  final doc = pw.Document(
    title: 'Servis Formu - ${order.title}',
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );

  final dateTimeFormat = DateFormat('d MMMM y HH:mm', 'tr_TR');
  final dateOnlyFormat = DateFormat('d MMMM y', 'tr_TR');
  final timeOnlyFormat = DateFormat('HH:mm', 'tr_TR');

  final createdAt = order.createdAt;
  final closedAt = order.closedAt;
  final scheduledAt = order.scheduledDate;

  final createdAtText =
      createdAt == null ? null : dateTimeFormat.format(AppTime.toTr(createdAt));
  final closedAtText =
      closedAt == null ? null : dateTimeFormat.format(AppTime.toTr(closedAt));
  final scheduledText = scheduledAt == null
      ? null
      : dateTimeFormat.format(AppTime.toTr(scheduledAt));

  final address = (order.address ?? '').trim();
  final city = (order.city ?? '').trim();
  final addressText = [
    if (address.isNotEmpty) address,
    if (city.isNotEmpty) city,
  ].join(' • ');

  final statusLabel = switch (order.status) {
    'open' => 'Açık',
    'in_progress' => 'Yapılıyor',
    'done' => 'Kapalı',
    'cancelled' => 'İptal',
    _ => order.status,
  };

  final money =
      NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2);

  final totalsByCurrency = <String, double>{};
  for (final p in payments) {
    totalsByCurrency.update(p.currency, (v) => v + p.amount, ifAbsent: () => p.amount);
  }

  final signature = signaturePngBytes == null || signaturePngBytes.isEmpty
      ? null
      : pw.MemoryImage(signaturePngBytes);
  final personnelSignature =
      personnelSignaturePngBytes == null || personnelSignaturePngBytes.isEmpty
          ? null
          : pw.MemoryImage(personnelSignaturePngBytes);

  pw.MemoryImage? logo;
  try {
    final bytes =
        (await rootBundle.load('assets/images/logo.png')).buffer.asUint8List();
    if (bytes.isNotEmpty) {
      logo = pw.MemoryImage(bytes);
    }
  } catch (_) {}

  pw.TextStyle tLabel() =>
      pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold);
  pw.TextStyle tValue() => const pw.TextStyle(fontSize: 8);
  pw.TextStyle tSmall() => const pw.TextStyle(fontSize: 7);

  pw.Widget section(String title, pw.Widget child) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: PdfColors.grey400),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title,
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          child,
        ],
      ),
    );
  }

  pw.Widget kvRow(String label, String value) {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(vertical: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(width: 96, child: pw.Text(label, style: tLabel())),
          pw.SizedBox(width: 8),
          pw.Expanded(child: pw.Text(value, style: tValue())),
        ],
      ),
    );
  }

  pw.Widget serviceInfoTable() {
    final phone = (order.contactPhone ?? '').trim().isNotEmpty
        ? order.contactPhone!.trim()
        : (customer.phone1 ?? '').trim();
    final email = (customer.email ?? '').trim();
    final assigned = (order.assignedPersonnelName ?? '').trim();
    final typeName = (order.workOrderTypeName ?? '').trim();
    final branch = (order.branchName ?? '').trim();

    final registry = RegExp(r'Sicil:\\s*([^•\\s]+)', caseSensitive: false)
        .firstMatch((order.description ?? '').trim())
        ?.group(1)
        ?.trim();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        kvRow('İş Emri No', order.id),
        kvRow('Durum', statusLabel),
        kvRow(
          'Ödeme',
          order.paymentRequired == null
              ? 'Belirsiz'
              : order.paymentRequired!
                  ? 'Alınacak'
                  : 'Alınmayacak',
        ),
        if (createdAtText != null) kvRow('Oluşturma', createdAtText),
        if (scheduledText != null) kvRow('Plan', scheduledText),
        if (closedAtText != null) kvRow('Kapanış', closedAtText),
        if (typeName.isNotEmpty) kvRow('İş Emri Tipi', typeName),
        if (branch.isNotEmpty) kvRow('Şube', branch),
        if (assigned.isNotEmpty) kvRow('Atanan', assigned),
        kvRow('Müşteri', customer.name.trim()),
        if (phone.isNotEmpty) kvRow('Telefon', phone),
        if (email.isNotEmpty) kvRow('E-posta', email),
        if (addressText.isNotEmpty) kvRow('Adres', addressText),
        if (registry != null && registry.isNotEmpty) kvRow('Cihaz Sicil', registry),
      ],
    );
  }

  pw.Widget paymentsTable() {
    if (payments.isEmpty) {
      return pw.Text('Ödeme yok.', style: tValue());
    }

    final rows = payments.length > 3 ? payments.take(3).toList() : payments;
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey300),
      columnWidths: const {
        0: pw.FlexColumnWidth(2.1),
        1: pw.FlexColumnWidth(1.3),
        2: pw.FlexColumnWidth(1.0),
        3: pw.FlexColumnWidth(3.2),
      },
      children: [
        pw.TableRow(
          decoration: pw.BoxDecoration(color: PdfColor.fromHex('#EFF6FF')),
          children: [
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Tarih', style: tLabel()),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Tutar', style: tLabel()),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Döviz', style: tLabel()),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.all(4),
              child: pw.Text('Açıklama', style: tLabel()),
            ),
          ],
        ),
        for (final p in rows)
          pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(
                  p.paidAt == null
                      ? ''
                      : dateTimeFormat.format(AppTime.toTr(p.paidAt!)),
                  style: tSmall(),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(money.format(p.amount), style: tValue()),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text(p.currency, style: tValue()),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.all(4),
                child: pw.Text((p.description ?? '').trim(), style: tSmall()),
              ),
            ],
          ),
      ],
    );
  }

  pw.Widget totalsRow() {
    if (totalsByCurrency.isEmpty) return pw.SizedBox();
    final keys = totalsByCurrency.keys.toList()..sort();
    return pw.Wrap(
      spacing: 10,
      runSpacing: 6,
      children: [
        for (final k in keys)
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey400),
            ),
            child: pw.Text(
              'Toplam $k: ${money.format(totalsByCurrency[k] ?? 0)}',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
            ),
          ),
      ],
    );
  }

  final docNo = _shortId(order.id);
  final headerDate = AppTime.toTr(DateTime.now());

  doc.addPage(
    pw.MultiPage(
      theme: theme,
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(16),
      maxPages: 1,
      header: (context) => pw.Container(
        padding: const pw.EdgeInsets.only(bottom: 8),
        decoration: const pw.BoxDecoration(
          border: pw.Border(bottom: pw.BorderSide(color: PdfColors.grey400)),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            if (logo != null) ...[
              pw.Align(
                alignment: pw.Alignment.center,
                child: pw.SizedBox(
                  width: 220,
                  height: 54,
                  child: pw.Image(logo, fit: pw.BoxFit.contain),
                ),
              ),
              pw.SizedBox(height: 4),
            ],
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Microvise Servis Formu',
                        style: pw.TextStyle(
                          fontSize: 18,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      pw.SizedBox(height: 2),
                      pw.Text(order.title.trim(), style: tSmall()),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    pw.Text('Form No: $docNo', style: tSmall()),
                    pw.Text(
                      '${dateOnlyFormat.format(headerDate)} ${timeOnlyFormat.format(headerDate)}',
                      style: tSmall(),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
      build: (context) => [
        section('İş Emri Bilgileri', serviceInfoTable()),
        pw.SizedBox(height: 6),
        section(
          'Servis Detayı',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              kvRow('Arıza / Talep', order.title.trim()),
              if ((order.description ?? '').trim().isNotEmpty)
                kvRow('Açıklama', (order.description ?? '').trim()),
              kvRow('Yapılan İşlem', (closeNotes ?? '').trim().isEmpty ? '—' : closeNotes!.trim()),
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        section(
          'Ödeme Bilgileri',
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              paymentsTable(),
              if (payments.isNotEmpty) ...[
                pw.SizedBox(height: 6),
                totalsRow(),
                if (payments.length > 3)
                  pw.Padding(
                    padding: const pw.EdgeInsets.only(top: 4),
                    child: pw.Text(
                      'Diğer ödemeler: ${payments.length - 3} kayıt daha',
                      style: tSmall(),
                    ),
                  ),
              ],
            ],
          ),
        ),
        pw.SizedBox(height: 6),
        section(
          'İmzalar',
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Container(
                  height: 110,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Müşteri İmzası', style: tLabel()),
                      pw.SizedBox(height: 6),
                      pw.Expanded(
                        child: signature == null
                            ? pw.Center(
                                child: pw.Text('İmza yok.', style: tSmall()),
                              )
                            : pw.Image(signature, fit: pw.BoxFit.contain),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text('Firma: ${customer.name.trim()}', style: tSmall()),
                      pw.SizedBox(height: 3),
                      pw.Text('Tarih: ${dateOnlyFormat.format(headerDate)}', style: tSmall()),
                    ],
                  ),
                ),
              ),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Container(
                  height: 110,
                  padding: const pw.EdgeInsets.all(6),
                  decoration: pw.BoxDecoration(
                    border: pw.Border.all(color: PdfColors.grey400),
                  ),
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('Servis Personeli', style: tLabel()),
                      pw.SizedBox(height: 6),
                      pw.Expanded(
                        child: personnelSignature == null
                            ? pw.Center(
                                child: pw.Text('İmza yok.', style: tSmall()),
                              )
                            : pw.Image(
                                personnelSignature,
                                fit: pw.BoxFit.contain,
                              ),
                      ),
                      pw.SizedBox(height: 6),
                      pw.Text(
                        'Ad Soyad: ${(order.assignedPersonnelName ?? '').trim().isEmpty ? '—' : (order.assignedPersonnelName ?? '').trim()}',
                        style: tSmall(),
                      ),
                      pw.SizedBox(height: 3),
                      pw.Text('Tarih: ${dateOnlyFormat.format(headerDate)}', style: tSmall()),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );

  return doc.save();
}

String _shortId(String id) {
  final trimmed = id.trim();
  if (trimmed.length <= 6) return trimmed;
  return trimmed.substring(0, 6);
}
