import 'fault_form_model.dart';
import 'mobile_form_pdf.dart';

Future<bool> printFaultForm(FaultFormRecord record) async {
  await shareMobileFormPdf(
    title: 'Arıza Formu',
    filename: 'ariza_formu_${record.id}.pdf',
    rows: [
      ('Tarih', _date(record.formDate)),
      ('Müşteri', record.customerName),
      ('Adres', record.customerAddress ?? ''),
      ('Vergi Dairesi', record.customerTaxOffice ?? ''),
      ('VKN', record.customerVkn ?? ''),
      ('Cihaz', record.deviceBrandModel ?? ''),
      ('Firma Kodu / Sicil', record.companyCodeAndRegistry ?? ''),
      ('Onay Tarihi / No', record.okcApprovalDateAndNumber ?? ''),
      ('Arıza Tarihi', record.faultDateTimeText ?? ''),
      ('Arıza Açıklaması', record.faultDescription ?? ''),
      ('Son Z Raporu', record.lastZReportDisplay),
      ('Toplam Hasılat', record.totalRevenue ?? ''),
      ('Toplam KDV', record.totalVat ?? ''),
    ],
  );
  return true;
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
