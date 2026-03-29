import '../../core/format/app_date_time.dart';

class TransferFormRecord {
  const TransferFormRecord({
    required this.id,
    required this.rowNumber,
    required this.transferorName,
    required this.transferorAddress,
    required this.transferorTaxOfficeAndRegistry,
    required this.transferorApprovalDateNo,
    required this.transfereeName,
    required this.transfereeAddress,
    required this.transfereeTaxOfficeAndRegistry,
    required this.transfereeApprovalDateNo,
    required this.totalSalesReceipt,
    required this.vatCollected,
    required this.lastReceiptDateNo,
    required this.zReportCount,
    required this.otherDeviceInfo,
    required this.brandModel,
    required this.deviceSerialNo,
    required this.fiscalSymbolCompanyCode,
    required this.departmentCount,
    required this.transferDate,
    required this.transferReason,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String? rowNumber;
  final String transferorName;
  final String? transferorAddress;
  final String? transferorTaxOfficeAndRegistry;
  final String? transferorApprovalDateNo;
  final String transfereeName;
  final String? transfereeAddress;
  final String? transfereeTaxOfficeAndRegistry;
  final String? transfereeApprovalDateNo;
  final String? totalSalesReceipt;
  final String? vatCollected;
  final String? lastReceiptDateNo;
  final String? zReportCount;
  final String? otherDeviceInfo;
  final String? brandModel;
  final String? deviceSerialNo;
  final String? fiscalSymbolCompanyCode;
  final String? departmentCount;
  final DateTime transferDate;
  final String? transferReason;
  final bool isActive;
  final DateTime? createdAt;

  factory TransferFormRecord.fromJson(Map<String, dynamic> json) {
    return TransferFormRecord(
      id: json['id'].toString(),
      rowNumber: json['row_number']?.toString(),
      transferorName: json['transferor_name']?.toString() ?? '—',
      transferorAddress: json['transferor_address']?.toString(),
      transferorTaxOfficeAndRegistry: json['transferor_tax_office_and_registry']
          ?.toString(),
      transferorApprovalDateNo: json['transferor_approval_date_no']?.toString(),
      transfereeName: json['transferee_name']?.toString() ?? '—',
      transfereeAddress: json['transferee_address']?.toString(),
      transfereeTaxOfficeAndRegistry: json['transferee_tax_office_and_registry']
          ?.toString(),
      transfereeApprovalDateNo: json['transferee_approval_date_no']?.toString(),
      totalSalesReceipt: json['total_sales_receipt']?.toString(),
      vatCollected: json['vat_collected']?.toString(),
      lastReceiptDateNo: json['last_receipt_date_no']?.toString(),
      zReportCount: json['z_report_count']?.toString(),
      otherDeviceInfo: json['other_device_info']?.toString(),
      brandModel: json['brand_model']?.toString(),
      deviceSerialNo: json['device_serial_no']?.toString(),
      fiscalSymbolCompanyCode: json['fiscal_symbol_company_code']?.toString(),
      departmentCount: json['department_count']?.toString(),
      transferDate:
          parseAppDateTime(json['transfer_date']?.toString()) ?? appNow(),
      transferReason: json['transfer_reason']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: parseAppDateTime(json['created_at']?.toString()),
    );
  }
}

class TransferFormPrintSettings {
  const TransferFormPrintSettings({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.officeTitle,
    required this.rowNumberLabel,
    required this.transferorSectionTitle,
    required this.transferorNameLabel,
    required this.transferorAddressLabel,
    required this.transferorTaxLabel,
    required this.transferorApprovalLabel,
    required this.transfereeSectionTitle,
    required this.transfereeNameLabel,
    required this.transfereeAddressLabel,
    required this.transfereeTaxLabel,
    required this.transfereeApprovalLabel,
    required this.deviceSummaryTitle,
    required this.totalSalesReceiptLabel,
    required this.vatCollectedLabel,
    required this.lastReceiptDateNoLabel,
    required this.zReportCountLabel,
    required this.otherDeviceInfoLabel,
    required this.deviceInfoTitle,
    required this.brandModelLabel,
    required this.deviceSerialNoLabel,
    required this.fiscalSymbolCompanyCodeLabel,
    required this.departmentCountLabel,
    required this.transferInfoTitle,
    required this.transferDateLabel,
    required this.transferReasonLabel,
    required this.serviceCompanyLabel,
    required this.serviceCompanyValue,
    required this.statementText,
    required this.transferorSignatureTitle,
    required this.transfereeSignatureTitle,
    required this.officeFillTitle,
    required this.officeFillText,
    required this.controllerTitle,
    required this.controllerDateLabel,
  });

  final String id;
  final String title;
  final String subtitle;
  final String officeTitle;
  final String rowNumberLabel;
  final String transferorSectionTitle;
  final String transferorNameLabel;
  final String transferorAddressLabel;
  final String transferorTaxLabel;
  final String transferorApprovalLabel;
  final String transfereeSectionTitle;
  final String transfereeNameLabel;
  final String transfereeAddressLabel;
  final String transfereeTaxLabel;
  final String transfereeApprovalLabel;
  final String deviceSummaryTitle;
  final String totalSalesReceiptLabel;
  final String vatCollectedLabel;
  final String lastReceiptDateNoLabel;
  final String zReportCountLabel;
  final String otherDeviceInfoLabel;
  final String deviceInfoTitle;
  final String brandModelLabel;
  final String deviceSerialNoLabel;
  final String fiscalSymbolCompanyCodeLabel;
  final String departmentCountLabel;
  final String transferInfoTitle;
  final String transferDateLabel;
  final String transferReasonLabel;
  final String serviceCompanyLabel;
  final String serviceCompanyValue;
  final String statementText;
  final String transferorSignatureTitle;
  final String transfereeSignatureTitle;
  final String officeFillTitle;
  final String officeFillText;
  final String controllerTitle;
  final String controllerDateLabel;

  static const defaults = TransferFormPrintSettings(
    id: 'default',
    title: 'KULLANILMIŞ ÖDEME KAYDEDİCİ CİHAZ\nDEVİR TUTANAĞI',
    subtitle: '(Tebliğ No. 14, Madde 11 (1) )',
    officeTitle:
        'Ekonomi ve Maliye Bakanlığı\nGelir ve Vergi Dairesi Müdürlüğü,\nLefkoşa',
    rowNumberLabel: 'Sıra No.',
    transferorSectionTitle: '1- CİHAZI DEVREDECEK OLANIN',
    transferorNameLabel: '- Adı - Soyadı / Ünvanı',
    transferorAddressLabel: '- İşyeri Adresi',
    transferorTaxLabel: '- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
    transferorApprovalLabel:
        '- Cihazın Kullanımı Onay Belgesi Tarih ve No\' su',
    transfereeSectionTitle: '2- CİHAZI DEVRALACAK OLANIN',
    transfereeNameLabel: '- Adı - Soyadı / Ünvanı',
    transfereeAddressLabel: '- İşyeri Adresi',
    transfereeTaxLabel: '- Bağlı olduğu Vergi Dairesi ve Dosya Sicil No',
    transfereeApprovalLabel:
        '- Cihazın Kullanımı Onay Belgesi Tarih ve No\' su',
    deviceSummaryTitle: '3- DEVREDENE AİT CİHAZDA BULUNAN BİLGİLER',
    totalSalesReceiptLabel: '- Toplam Hasılat Tutarı',
    vatCollectedLabel: '- Tahsil Edilen KDV Tutarı',
    lastReceiptDateNoLabel: '- En son verilen fişin Tarih ve No\' su',
    zReportCountLabel: "- 'Z' Raporu Sayısı",
    otherDeviceInfoLabel: '- Varsa Diğer Bilgiler',
    deviceInfoTitle: '4- CİHAZA AİT BİLGİLER',
    brandModelLabel: '- Marka ve Modeli',
    deviceSerialNoLabel: '- Cihaz Sicil No',
    fiscalSymbolCompanyCodeLabel: '- Mali Sembol ve Firma Kodu',
    departmentCountLabel: '- Cihazın Departman Sayısı',
    transferInfoTitle: '5- DEVİRE AİT BİLGİLER',
    transferDateLabel: '- Devir Tarihi',
    transferReasonLabel: '- Devir Nedeni',
    serviceCompanyLabel: '- Cihazın Bakım - Onarımını üstlenen yetkili firma',
    serviceCompanyValue: 'Microvise Innovation Ltd.',
    statementText: 'Yukarıdaki bilgilerin tam ve doğru olduğunu beyan ederiz.',
    transferorSignatureTitle: 'DEVREDENİN',
    transfereeSignatureTitle: 'DEVRALANIN',
    officeFillTitle: 'DAİRE TARAFINDAN DOLDURULACAKTIR',
    officeFillText:
        'Yukarıdaki bilgiler tarafımdan / tarafımızdan kontrol edilmiş olup doğruluğu saptanmıştır.',
    controllerTitle: 'KONTROLÜ YAPANIN / YAPANLARIN',
    controllerDateLabel: 'Tarih',
  );

  factory TransferFormPrintSettings.fromJson(Map<String, dynamic> json) {
    return TransferFormPrintSettings(
      id: json['id']?.toString() ?? 'default',
      title: json['title']?.toString() ?? defaults.title,
      subtitle: json['subtitle']?.toString() ?? defaults.subtitle,
      officeTitle: json['office_title']?.toString() ?? defaults.officeTitle,
      rowNumberLabel:
          json['row_number_label']?.toString() ?? defaults.rowNumberLabel,
      transferorSectionTitle:
          json['transferor_section_title']?.toString() ??
          defaults.transferorSectionTitle,
      transferorNameLabel:
          json['transferor_name_label']?.toString() ??
          defaults.transferorNameLabel,
      transferorAddressLabel:
          json['transferor_address_label']?.toString() ??
          defaults.transferorAddressLabel,
      transferorTaxLabel:
          json['transferor_tax_label']?.toString() ??
          defaults.transferorTaxLabel,
      transferorApprovalLabel:
          json['transferor_approval_label']?.toString() ??
          defaults.transferorApprovalLabel,
      transfereeSectionTitle:
          json['transferee_section_title']?.toString() ??
          defaults.transfereeSectionTitle,
      transfereeNameLabel:
          json['transferee_name_label']?.toString() ??
          defaults.transfereeNameLabel,
      transfereeAddressLabel:
          json['transferee_address_label']?.toString() ??
          defaults.transfereeAddressLabel,
      transfereeTaxLabel:
          json['transferee_tax_label']?.toString() ??
          defaults.transfereeTaxLabel,
      transfereeApprovalLabel:
          json['transferee_approval_label']?.toString() ??
          defaults.transfereeApprovalLabel,
      deviceSummaryTitle:
          json['device_summary_title']?.toString() ??
          defaults.deviceSummaryTitle,
      totalSalesReceiptLabel:
          json['total_sales_receipt_label']?.toString() ??
          defaults.totalSalesReceiptLabel,
      vatCollectedLabel:
          json['vat_collected_label']?.toString() ?? defaults.vatCollectedLabel,
      lastReceiptDateNoLabel:
          json['last_receipt_date_no_label']?.toString() ??
          defaults.lastReceiptDateNoLabel,
      zReportCountLabel:
          json['z_report_count_label']?.toString() ??
          defaults.zReportCountLabel,
      otherDeviceInfoLabel:
          json['other_device_info_label']?.toString() ??
          defaults.otherDeviceInfoLabel,
      deviceInfoTitle:
          json['device_info_title']?.toString() ?? defaults.deviceInfoTitle,
      brandModelLabel:
          json['brand_model_label']?.toString() ?? defaults.brandModelLabel,
      deviceSerialNoLabel:
          json['device_serial_no_label']?.toString() ??
          defaults.deviceSerialNoLabel,
      fiscalSymbolCompanyCodeLabel:
          json['fiscal_symbol_company_code_label']?.toString() ??
          defaults.fiscalSymbolCompanyCodeLabel,
      departmentCountLabel:
          json['department_count_label']?.toString() ??
          defaults.departmentCountLabel,
      transferInfoTitle:
          json['transfer_info_title']?.toString() ?? defaults.transferInfoTitle,
      transferDateLabel:
          json['transfer_date_label']?.toString() ?? defaults.transferDateLabel,
      transferReasonLabel:
          json['transfer_reason_label']?.toString() ??
          defaults.transferReasonLabel,
      serviceCompanyLabel:
          json['service_company_label']?.toString() ??
          defaults.serviceCompanyLabel,
      serviceCompanyValue:
          json['service_company_value']?.toString() ??
          defaults.serviceCompanyValue,
      statementText:
          json['statement_text']?.toString() ?? defaults.statementText,
      transferorSignatureTitle:
          json['transferor_signature_title']?.toString() ??
          defaults.transferorSignatureTitle,
      transfereeSignatureTitle:
          json['transferee_signature_title']?.toString() ??
          defaults.transfereeSignatureTitle,
      officeFillTitle:
          json['office_fill_title']?.toString() ?? defaults.officeFillTitle,
      officeFillText:
          json['office_fill_text']?.toString() ?? defaults.officeFillText,
      controllerTitle:
          json['controller_title']?.toString() ?? defaults.controllerTitle,
      controllerDateLabel:
          json['controller_date_label']?.toString() ??
          defaults.controllerDateLabel,
    );
  }
}
