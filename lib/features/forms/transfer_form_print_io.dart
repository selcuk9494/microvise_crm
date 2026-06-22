import 'mobile_form_pdf.dart';
import 'transfer_form_model.dart';

Future<bool> printTransferForm(
  TransferFormRecord record, {
  TransferFormPrintSettings? settings,
}) async {
  await shareMobileFormPdf(
    title: settings?.title.replaceAll('\n', ' ') ?? 'Devir Formu',
    filename: 'devir_formu_${record.id}.pdf',
    rows: [
      ('Sıra No', record.rowNumber ?? ''),
      ('Devreden', record.transferorName),
      ('Devreden Adres', record.transferorAddress ?? ''),
      ('Devreden Vergi / Sicil', record.transferorTaxOfficeAndRegistry ?? ''),
      ('Devreden Onay', record.transferorApprovalDateNo ?? ''),
      ('Devralan', record.transfereeName),
      ('Devralan Adres', record.transfereeAddress ?? ''),
      ('Devralan Vergi / Sicil', record.transfereeTaxOfficeAndRegistry ?? ''),
      ('Devralan Onay', record.transfereeApprovalDateNo ?? ''),
      ('Toplam Hasılat', record.totalSalesReceipt ?? ''),
      ('KDV', record.vatCollected ?? ''),
      ('Son Fiş', record.lastReceiptDateNo ?? ''),
      ('Z Raporu', record.zReportCount ?? ''),
      ('Cihaz', record.brandModel ?? ''),
      ('Sicil No', record.deviceSerialNo ?? ''),
      ('Mali Sembol / Firma Kodu', record.fiscalSymbolCompanyCode ?? ''),
      ('Departman Sayısı', record.departmentCount ?? ''),
      ('Devir Tarihi', _date(record.transferDate)),
      ('Devir Nedeni', record.transferReason ?? ''),
      ('Diğer Bilgiler', record.otherDeviceInfo ?? ''),
    ],
  );
  return true;
}

String _date(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year}';
