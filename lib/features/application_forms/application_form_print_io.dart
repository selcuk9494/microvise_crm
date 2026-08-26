import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'application_form_model.dart';

enum ApplicationPrintKind { kdv, kdv4a }

extension ApplicationPrintKindLabel on ApplicationPrintKind {
  String get label => this == ApplicationPrintKind.kdv ? 'KDV4' : 'KDV4A';
}

Future<bool> printApplicationForm(
  ApplicationFormRecord record, {
  required ApplicationPrintKind kind,
  ApplicationFormPrintSettings? settings,
}) async {
  final resolved = settings ?? ApplicationFormPrintSettings.defaults;
  final bytes = await _buildPdfBytes(
    [record],
    kind: kind,
    settings: resolved,
  );
  final filename = _safeFilename(
    '${kind.label.toLowerCase()}_${_filePart(record.customerName)}_'
    '${_filePart(record.stockRegistryNumber ?? record.id)}.pdf',
  );
  await _sharePdfBytes(bytes, filename: filename);
  return true;
}

Future<bool> printApplicationFormsBulk(
  List<ApplicationFormRecord> records, {
  required ApplicationPrintKind kind,
  ApplicationFormPrintSettings? settings,
}) async {
  if (records.isEmpty) return false;
  final resolved = settings ?? ApplicationFormPrintSettings.defaults;
  final bytes = await _buildPdfBytes(
    records,
    kind: kind,
    settings: resolved,
  );
  final filename = _safeFilename(
    '${kind.label.toLowerCase()}_toplu_${records.length}_'
    '${DateTime.now().millisecondsSinceEpoch}.pdf',
  );
  await _sharePdfBytes(bytes, filename: filename);
  return true;
}

Future<Uint8List> _buildPdfBytes(
  List<ApplicationFormRecord> records, {
  required ApplicationPrintKind kind,
  required ApplicationFormPrintSettings settings,
}) async {
  final regularFont = pw.Font.ttf(
    await rootBundle.load('assets/fonts/noto_sans/NotoSans-Regular.ttf'),
  );
  final doc = pw.Document(
    title: kind.label,
    author: 'Microvise CRM',
    creator: 'Microvise CRM',
  );
  final theme = pw.ThemeData.withFont(base: regularFont, bold: regularFont);

  for (final record in records) {
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        theme: theme,
        build: (context) => kind == ApplicationPrintKind.kdv
            ? _buildKdvPage(record, settings)
            : _buildKdv4aPage(record, settings),
      ),
    );
  }

  return doc.save();
}

pw.Widget _buildKdvPage(
  ApplicationFormRecord record,
  ApplicationFormPrintSettings settings,
) {
  final ownerName = (record.director ?? '').trim().isNotEmpty
      ? record.director!.trim()
      : record.customerName.trim();
  final directorName = (record.director ?? '').trim().isNotEmpty
      ? record.director!.trim()
      : ownerName;
  final okcDate = _formatDate(record.okcStartDate, fallback: '[1]');

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Align(
        alignment: pw.Alignment.topRight,
        child: pw.Text(
          '(Forma. KDV 4)',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'ÖDEME KAYDEDİCİ CİHAZ ONAY TALEP FORMU',
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        settings.officeTitle,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 8),
      pw.Text(settings.introText, style: const pw.TextStyle(fontSize: 9)),
      pw.SizedBox(height: 10),
      _line('1-İşletmenin Ünvanı', record.customerName),
      _line('a) İşletmenin Sahibi', ownerName, indent: 1),
      _line('b) İşletmenin Direktörü', directorName, indent: 1),
      _line('2-İşletmenin Merkez Adresi', record.workAddress),
      _line('Varsa Şubelerinin Adresi', '', indent: 1),
      _line('3-İşletmenin Muhasip - Murakkıbı', record.accountingOffice),
      _line(
        '4-Ödeme Kaydedici Cihaz Kullanmaya Başlama Tarihi',
        okcDate,
      ),
      _line('5-Ticari Faaliyet / Meslek Türü', record.businessActivityName),
      _line('6-Kullanılacak Ödeme Kaydedici Cihazın', null),
      _line('a) Markası', record.brandName, indent: 1),
      _lineWithExtra(
        'b) Modeli',
        record.modelName,
        extraLabel: 'Sicil No',
        extraValue: record.stockRegistryNumber,
        indent: 1,
      ),
      _line(
        'c) Güç Kaynağı ile ilgili Önlemler',
        settings.optionalPowerPrecautionText,
        indent: 1,
      ),
      _line('7-Ekte Sunulacak Evraklar', null),
      _line(
        'X  a) Genel Kullanım Kılavuzu',
        settings.manualIncludedText,
        indent: 1,
      ),
      _line(
        'b) Satıcı ile Bakım ve Onarım işlemlerini yapmayı taahhüt eden firmanın :',
        null,
        indent: 1,
      ),
      _line('Adı - Soyadı', settings.serviceCompanyName, indent: 2),
      _line('Adresi', settings.serviceCompanyAddress, indent: 2),
      pw.SizedBox(height: 16),
      pw.Text(
        'BAŞVURU SAHİBİNİN :',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      _line('Adı - Soyadı', ownerName),
      _line('İmzası', ''),
      _line('Statüsü', settings.applicantStatus),
    ],
  );
}

pw.Widget _buildKdv4aPage(
  ApplicationFormRecord record,
  ApplicationFormPrintSettings settings,
) {
  final applicationDate = _formatDate(record.applicationDate);
  final okcDate = _formatDate(record.okcStartDate, fallback: '[1]');
  final buyerTaxRegistry =
      '${record.taxOfficeCityName ?? ''} ${record.documentType}: ${record.fileRegistryNumber ?? ''}'
          .trim();
  final invoiceRef = (record.invoiceNumber?.trim().isNotEmpty ?? false)
      ? '$applicationDate / ${record.invoiceNumber!.trim()}'
      : applicationDate;

  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      pw.Align(
        alignment: pw.Alignment.topRight,
        child: pw.Text(
          '(Forma. KDV 4A)',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        settings.kdv4aTitle,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Align(
        alignment: pw.Alignment.centerRight,
        child: _inlinePair('Sıra No.', settings.kdv4aSerialNumber),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        settings.officeTitle4a,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 10),
      _section('1- CİHAZI SATAN KİŞİ VEYA İŞLETMENİN'),
      _line('-- Adı - Soyadı / Ünvanı', settings.kdv4aSellerCompanyName, indent: 1),
      _line('-- İşyeri Adresi', settings.kdv4aSellerAddress, indent: 1),
      _line(
        '-- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
        settings.kdv4aSellerTaxOfficeAndRegistry,
        indent: 1,
      ),
      _line('-- Ruhsatname No', settings.kdv4aSellerLicenseNumber, indent: 1),
      _line('-- Satışa Ait faturanın Tarih ve No\' su', invoiceRef, indent: 1),
      _line('-- Cihazın Garanti Süresi', settings.kdv4aWarrantyPeriod, indent: 1),
      _line('-- Firmanın Kaşesi ve Yetkilinin İmzası', '', indent: 1),
      pw.SizedBox(height: 6),
      _section('2- CİHAZI SATIN ALAN KİŞİ VEYA İŞLETMENİN'),
      _line('-- Adı - Soyadı / Ünvanı', record.customerName, indent: 1),
      _line('-- İşyeri Adresi', record.workAddress, indent: 1),
      _line(
        '-- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
        buyerTaxRegistry,
        indent: 1,
      ),
      _line('-- Cihazın çalıştırılma Tarihi', okcDate, indent: 1),
      pw.SizedBox(height: 6),
      _section('3- SATIŞI YAPILAN CİHAZIN ÖZELLİKLERİ'),
      _line('-- Markası ve Modeli', record.brandModel, indent: 1),
      _line('-- Cihaz Sicil No', record.stockRegistryNumber, indent: 1),
      _line('-- Mali Sembol ve Firma Kodu', record.fiscalSymbolName, indent: 1),
      _line(
        '-- Cihazın Departman Sayısı',
        settings.kdv4aDepartmentCount,
        indent: 1,
      ),
      pw.SizedBox(height: 6),
      _section('4- YETKİLİ BAKIM ONARIM SERVİSİNİN'),
      _line(
        '-- Adı - Soyadı / Ünvanı',
        settings.kdv4aServiceCompanyName,
        indent: 1,
      ),
      _line('-- İşyeri Adresi', settings.kdv4aServiceCompanyAddress, indent: 1),
      pw.SizedBox(height: 6),
      _section('5- CİHAZA MALİ MÜHÜRÜ TATBİK EDENİN'),
      pw.Padding(
        padding: const pw.EdgeInsets.only(left: 12, top: 2, bottom: 2),
        child: pw.Row(
          children: [
            pw.Text('İmzası', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(width: 6),
            pw.Expanded(child: _dots('')),
            pw.SizedBox(width: 8),
            pw.Text('Açık İsmi :', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(width: 4),
            pw.Expanded(child: _dots(settings.kdv4aSealApplicantName)),
            pw.SizedBox(width: 8),
            pw.Text('Makamı :', style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(width: 4),
            pw.Expanded(child: _dots(settings.kdv4aSealApplicantTitle)),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Container(
        padding: const pw.EdgeInsets.all(8),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: PdfColors.grey700, width: 0.7),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              'ÖDEME KAYDEDİCİ CİHAZ KULLANIMINA AİT',
              style: pw.TextStyle(
                fontSize: 9,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.SizedBox(height: 4),
            pw.Row(
              children: [
                pw.Text(
                  'Onay Belgesi Tarihi :',
                  style: const pw.TextStyle(fontSize: 9),
                ),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _dots(settings.kdv4aApprovalDocumentDate)),
                pw.SizedBox(width: 10),
                pw.Text('Sayısı :', style: const pw.TextStyle(fontSize: 9)),
                pw.SizedBox(width: 4),
                pw.Expanded(child: _dots(settings.kdv4aApprovalDocumentNumber)),
              ],
            ),
          ],
        ),
      ),
      pw.SizedBox(height: 8),
      pw.Text(
        'Mali mühürü bozulmamış olarak Ödeme Kaydedici Cihazın, Ödeme Kaydedici Cihaz Kullanımına ait '
        'Onay Belgesi (Forma. KDV 5) ile birlikte alıcıya teslim edildiği ve teslim alındığı beyan olunur.',
        style: const pw.TextStyle(fontSize: 8),
      ),
      pw.SizedBox(height: 12),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TESLİM EDENİN',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                _line('İmzası', ''),
                _line('Açık İsmi', ''),
                _line('Makamı', ''),
                pw.SizedBox(height: 16),
                _line('Tarih', ''),
              ],
            ),
          ),
          pw.SizedBox(width: 16),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TESLİM ALANIN /\nYETKİLİ SATICININ',
                  style: pw.TextStyle(
                    fontSize: 9,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 6),
                _line('İmzası', ''),
                _line('Açık İsmi', settings.kdv4aDeliveryReceiverName),
                _line('Makamı', settings.kdv4aDeliveryReceiverTitle),
                pw.Padding(
                  padding: const pw.EdgeInsets.only(left: 12, top: 4),
                  child: pw.Text(
                    '(Firma Kaşesi)',
                    style: const pw.TextStyle(fontSize: 8),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _section(String title) {
  return pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2, bottom: 2),
    child: pw.Text(
      title,
      style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
    ),
  );
}

pw.Widget _line(String label, String? value, {int indent = 0}) {
  final left = indent == 0
      ? 0.0
      : indent == 1
          ? 12.0
          : 24.0;
  final text = (value ?? '').trim();
  if (value == null) {
    return pw.Padding(
      padding: pw.EdgeInsets.only(left: left, top: 2, bottom: 2),
      child: pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
    );
  }
  return pw.Padding(
    padding: pw.EdgeInsets.only(left: left, top: 2, bottom: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Text(':', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Expanded(child: _dots(text)),
      ],
    ),
  );
}

pw.Widget _lineWithExtra(
  String label,
  String? value, {
  required String extraLabel,
  required String? extraValue,
  int indent = 0,
}) {
  final left = indent == 0
      ? 0.0
      : indent == 1
          ? 12.0
          : 24.0;
  return pw.Padding(
    padding: pw.EdgeInsets.only(left: left, top: 2, bottom: 2),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.end,
      children: [
        pw.Text(label, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Text(':', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Expanded(child: _dots((value ?? '').trim())),
        pw.SizedBox(width: 8),
        pw.Text(extraLabel, style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Text(':', style: const pw.TextStyle(fontSize: 9)),
        pw.SizedBox(width: 4),
        pw.Expanded(flex: 2, child: _dots((extraValue ?? '').trim())),
      ],
    ),
  );
}

pw.Widget _inlinePair(String label, String? value) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    children: [
      pw.Text(
        '$label :',
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(width: 6),
      pw.SizedBox(width: 120, child: _dots((value ?? '').trim())),
    ],
  );
}

pw.Widget _dots(String value) {
  final text = value.trim();
  return pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        bottom: pw.BorderSide(color: PdfColors.grey600, width: 0.6),
      ),
    ),
    padding: const pw.EdgeInsets.only(bottom: 1),
    child: pw.Text(
      text.isEmpty ? ' ' : text,
      style: const pw.TextStyle(fontSize: 9),
    ),
  );
}

String _formatDate(DateTime? value, {String fallback = ''}) {
  if (value == null) return fallback;
  final d = value.day.toString().padLeft(2, '0');
  final m = value.month.toString().padLeft(2, '0');
  return '$d.$m.${value.year}';
}

Future<void> _sharePdfBytes(
  Uint8List bytes, {
  required String filename,
}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsBytes(bytes, flush: true);

  final view = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
  final dpr = view?.devicePixelRatio ?? 1.0;
  final size = view == null
      ? const Size(1, 1)
      : Size(view.physicalSize.width / dpr, view.physicalSize.height / dpr);
  final maxX = math.max<double>(size.width - 20, 0);
  final maxY = math.max<double>(size.height - 20, 0);
  final origin = Rect.fromLTWH(
    (size.width / 2 - 10).clamp(0.0, maxX),
    (size.height / 2 - 10).clamp(0.0, maxY),
    20,
    20,
  );

  await Share.shareXFiles([
    XFile(file.path, mimeType: 'application/pdf', name: filename),
  ], sharePositionOrigin: origin);
}

String _filePart(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return 'form';
  return trimmed
      .replaceAll(RegExp(r'\s+'), '_')
      .replaceAll(RegExp(r'[^a-zA-Z0-9._\-ğüşıöçĞÜŞİÖÇ]+'), '');
}

String _safeFilename(String input) {
  final trimmed = input.trim().isEmpty ? 'form.pdf' : input.trim();
  return trimmed.replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_');
}
