import 'scrap_form_model.dart';
import 'mobile_form_pdf.dart';

Future<bool> printScrapForm(
  ScrapFormRecord record, {
  ScrapFormPrintSettings? settings,
}) async {
  final title = settings?.title.replaceAll('\n', ' ') ?? 'Hurda Formu';
  await shareMobileFormPdf(
    title: title,
    filename: 'hurda_formu_${record.id}.pdf',
    rows: _scrapFormRows(record),
  );
  return true;
}

Future<bool> printScrapFormsBulk(
  List<ScrapFormRecord> records, {
  ScrapFormPrintSettings? settings,
}) async {
  if (records.isEmpty) return false;
  final title = settings?.title.replaceAll('\n', ' ') ?? 'Hurda Formu';
  if (records.length == 1) {
    return printScrapForm(records.first, settings: settings);
  }
  await shareMobileFormPdfPages(
    documentTitle: title,
    filename: 'hurda_formu_toplu_${records.length}_'
        '${DateTime.now().millisecondsSinceEpoch}.pdf',
    pages: [
      for (final record in records) (title: title, rows: _scrapFormRows(record)),
    ],
  );
  return true;
}

List<(String, String)> _scrapFormRows(ScrapFormRecord record) {
  return [
    ('Tarih', _date(record.formDate)),
    ('Sıra No', record.rowNumber ?? ''),
    ('Müşteri', record.customerName),
    ('Adres', record.customerAddress ?? ''),
    ('Vergi Dairesi / No', record.customerTaxOfficeAndNumber ?? ''),
    ('Cihaz', record.deviceBrandModelRegistry ?? ''),
    ('Başlama Tarihi', _dateOrEmpty(record.okcStartDate)),
    ('Son Kullanım', _dateOrEmpty(record.lastUsedDate)),
    ('Z Rapor Sayısı', record.zReportCount ?? ''),
    ('KDV Tahsilatı', record.totalVatCollection ?? ''),
    ('Toplam Hasılat', record.totalCollection ?? ''),
    ('Müdahale Amacı', record.interventionPurpose ?? ''),
    ('Diğer Tespitler', record.otherFindings ?? ''),
  ];
}

String _dateOrEmpty(DateTime? date) => date == null ? '' : _date(date);
String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
