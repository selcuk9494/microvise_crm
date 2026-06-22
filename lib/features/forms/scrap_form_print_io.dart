import 'scrap_form_model.dart';
import 'mobile_form_pdf.dart';

Future<bool> printScrapForm(
  ScrapFormRecord record, {
  ScrapFormPrintSettings? settings,
}) async {
  await shareMobileFormPdf(
    title: settings?.title.replaceAll('\n', ' ') ?? 'Hurda Formu',
    filename: 'hurda_formu_${record.id}.pdf',
    rows: [
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
    ],
  );
  return true;
}

String _dateOrEmpty(DateTime? date) => date == null ? '' : _date(date);
String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
