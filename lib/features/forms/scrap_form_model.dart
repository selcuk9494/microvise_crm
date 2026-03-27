class ScrapFormRecord {
  const ScrapFormRecord({
    required this.id,
    required this.formDate,
    required this.rowNumber,
    required this.customerId,
    required this.customerName,
    required this.customerAddress,
    required this.customerTaxOfficeAndNumber,
    required this.deviceBrandModelRegistry,
    required this.okcStartDate,
    required this.lastUsedDate,
    required this.zReportCount,
    required this.totalVatCollection,
    required this.totalCollection,
    required this.interventionPurpose,
    required this.otherFindings,
    required this.createdAt,
  });

  final String id;
  final DateTime formDate;
  final String? rowNumber;
  final String? customerId;
  final String customerName;
  final String? customerAddress;
  final String? customerTaxOfficeAndNumber;
  final String? deviceBrandModelRegistry;
  final DateTime? okcStartDate;
  final DateTime? lastUsedDate;
  final String? zReportCount;
  final String? totalVatCollection;
  final String? totalCollection;
  final String? interventionPurpose;
  final String? otherFindings;
  final DateTime? createdAt;

  factory ScrapFormRecord.fromJson(Map<String, dynamic> json) {
    return ScrapFormRecord(
      id: json['id'].toString(),
      formDate:
          DateTime.tryParse(json['form_date']?.toString() ?? '') ??
          DateTime.now(),
      rowNumber: json['row_number']?.toString(),
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString() ?? '—',
      customerAddress: json['customer_address']?.toString(),
      customerTaxOfficeAndNumber: json['customer_tax_office_and_number']
          ?.toString(),
      deviceBrandModelRegistry: json['device_brand_model_registry']?.toString(),
      okcStartDate: DateTime.tryParse(json['okc_start_date']?.toString() ?? ''),
      lastUsedDate: DateTime.tryParse(json['last_used_date']?.toString() ?? ''),
      zReportCount: json['z_report_count']?.toString(),
      totalVatCollection: json['total_vat_collection']?.toString(),
      totalCollection: json['total_collection']?.toString(),
      interventionPurpose: json['intervention_purpose']?.toString(),
      otherFindings: json['other_findings']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

class ScrapFormPrintSettings {
  const ScrapFormPrintSettings({
    required this.id,
    required this.formCode,
    required this.title,
    required this.dateLabel,
    required this.rowNumberLabel,
    required this.serviceSectionTitle,
    required this.serviceCompanyLabel,
    required this.serviceIdentityLabel,
    required this.serviceAddressLabel,
    required this.serviceTaxLabel,
    required this.serviceCompanyValue,
    required this.serviceIdentityValue,
    required this.serviceAddressValue,
    required this.serviceTaxValue,
    required this.ownerSectionTitle,
    required this.ownerNameLabel,
    required this.ownerAddressLabel,
    required this.ownerTaxLabel,
    required this.deviceSectionTitle,
    required this.startDateLabel,
    required this.lastUsedDateLabel,
    required this.summaryTitle,
    required this.zReportLabel,
    required this.vatTotalLabel,
    required this.grossTotalLabel,
    required this.purposeLabel,
    required this.otherFindingsLabel,
    required this.ownerSignatureTitle,
    required this.serviceSignatureTitle,
  });

  final String id;
  final String formCode;
  final String title;
  final String dateLabel;
  final String rowNumberLabel;
  final String serviceSectionTitle;
  final String serviceCompanyLabel;
  final String serviceIdentityLabel;
  final String serviceAddressLabel;
  final String serviceTaxLabel;
  final String serviceCompanyValue;
  final String serviceIdentityValue;
  final String serviceAddressValue;
  final String serviceTaxValue;
  final String ownerSectionTitle;
  final String ownerNameLabel;
  final String ownerAddressLabel;
  final String ownerTaxLabel;
  final String deviceSectionTitle;
  final String startDateLabel;
  final String lastUsedDateLabel;
  final String summaryTitle;
  final String zReportLabel;
  final String vatTotalLabel;
  final String grossTotalLabel;
  final String purposeLabel;
  final String otherFindingsLabel;
  final String ownerSignatureTitle;
  final String serviceSignatureTitle;

  static const defaults = ScrapFormPrintSettings(
    id: 'default',
    formCode: '(Forma. KDV 15 b)',
    title: 'HURDAYA AYRILAN\nÖDEME KAYDEDİCİ CİHAZLARA AİT\nTUTANAK',
    dateLabel: 'TARİH',
    rowNumberLabel: 'SIRA NO',
    serviceSectionTitle: '1- YETKİLİ SERVİSİN',
    serviceCompanyLabel: '- Servisliğini Yaptığı Firma',
    serviceIdentityLabel: '- Adı, Soyadı veya Ünvanı ve Sicil No',
    serviceAddressLabel: '- Adresi',
    serviceTaxLabel: '- Vergi Dairesi ve Numarası',
    serviceCompanyValue: 'Ingenico',
    serviceIdentityValue: 'Microvise Innovation Ltd',
    serviceAddressValue: 'Atatürk Cad Emek 2 No:1 Yenişehir',
    serviceTaxValue: '19660',
    ownerSectionTitle: '2- CİHAZIN SAHİBİ MÜKELLEFİN',
    ownerNameLabel: '- Adı, Soyadı veya Ünvanı',
    ownerAddressLabel: '- Adresi',
    ownerTaxLabel: '- Vergi Dairesi ve Numarası',
    deviceSectionTitle: '3- CİHAZIN MARKA MODEL VE SİCİL NO',
    startDateLabel: '4- CİHAZIN KULLANILMAYA BAŞLANDIĞI TARİH',
    lastUsedDateLabel: '5- CİHAZIN EN SON KULLANILDIĞI TARİH',
    summaryTitle: '6- CİHAZIN SON KULLANIM TARİHİ İTİBARİYLE',
    zReportLabel: "- Z' Rapor Sayısı",
    vatTotalLabel: '- Toplam Katma Değer Vergisi Tahsilatı',
    grossTotalLabel: '- Toplam Hasılat',
    purposeLabel: '7- MÜDAHALENİN AMACI',
    otherFindingsLabel: '8- VARSA DİĞER TESPİTLER',
    ownerSignatureTitle: 'CİHAZ SAHİBİ MÜKELLEFİN\nİMZASI',
    serviceSignatureTitle: 'YETKİLİ SERVİS ELEMANININ\nİMZASI',
  );

  factory ScrapFormPrintSettings.fromJson(Map<String, dynamic> json) {
    return ScrapFormPrintSettings(
      id: json['id']?.toString() ?? 'default',
      formCode: json['form_code']?.toString() ?? defaults.formCode,
      title: json['title']?.toString() ?? defaults.title,
      dateLabel: json['date_label']?.toString() ?? defaults.dateLabel,
      rowNumberLabel:
          json['row_number_label']?.toString() ?? defaults.rowNumberLabel,
      serviceSectionTitle:
          json['service_section_title']?.toString() ??
          defaults.serviceSectionTitle,
      serviceCompanyLabel:
          json['service_company_label']?.toString() ??
          defaults.serviceCompanyLabel,
      serviceIdentityLabel:
          json['service_identity_label']?.toString() ??
          defaults.serviceIdentityLabel,
      serviceAddressLabel:
          json['service_address_label']?.toString() ??
          defaults.serviceAddressLabel,
      serviceTaxLabel:
          json['service_tax_label']?.toString() ?? defaults.serviceTaxLabel,
      serviceCompanyValue:
          json['service_company_value']?.toString() ??
          defaults.serviceCompanyValue,
      serviceIdentityValue:
          json['service_identity_value']?.toString() ??
          defaults.serviceIdentityValue,
      serviceAddressValue:
          json['service_address_value']?.toString() ??
          defaults.serviceAddressValue,
      serviceTaxValue:
          json['service_tax_value']?.toString() ?? defaults.serviceTaxValue,
      ownerSectionTitle:
          json['owner_section_title']?.toString() ?? defaults.ownerSectionTitle,
      ownerNameLabel:
          json['owner_name_label']?.toString() ?? defaults.ownerNameLabel,
      ownerAddressLabel:
          json['owner_address_label']?.toString() ?? defaults.ownerAddressLabel,
      ownerTaxLabel:
          json['owner_tax_label']?.toString() ?? defaults.ownerTaxLabel,
      deviceSectionTitle:
          json['device_section_title']?.toString() ??
          defaults.deviceSectionTitle,
      startDateLabel:
          json['start_date_label']?.toString() ?? defaults.startDateLabel,
      lastUsedDateLabel:
          json['last_used_date_label']?.toString() ??
          defaults.lastUsedDateLabel,
      summaryTitle: json['summary_title']?.toString() ?? defaults.summaryTitle,
      zReportLabel: json['z_report_label']?.toString() ?? defaults.zReportLabel,
      vatTotalLabel:
          json['vat_total_label']?.toString() ?? defaults.vatTotalLabel,
      grossTotalLabel:
          json['gross_total_label']?.toString() ?? defaults.grossTotalLabel,
      purposeLabel: json['purpose_label']?.toString() ?? defaults.purposeLabel,
      otherFindingsLabel:
          json['other_findings_label']?.toString() ??
          defaults.otherFindingsLabel,
      ownerSignatureTitle:
          json['owner_signature_title']?.toString() ??
          defaults.ownerSignatureTitle,
      serviceSignatureTitle:
          json['service_signature_title']?.toString() ??
          defaults.serviceSignatureTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'form_code': formCode,
    'title': title,
    'date_label': dateLabel,
    'row_number_label': rowNumberLabel,
    'service_section_title': serviceSectionTitle,
    'service_company_label': serviceCompanyLabel,
    'service_identity_label': serviceIdentityLabel,
    'service_address_label': serviceAddressLabel,
    'service_tax_label': serviceTaxLabel,
    'service_company_value': serviceCompanyValue,
    'service_identity_value': serviceIdentityValue,
    'service_address_value': serviceAddressValue,
    'service_tax_value': serviceTaxValue,
    'owner_section_title': ownerSectionTitle,
    'owner_name_label': ownerNameLabel,
    'owner_address_label': ownerAddressLabel,
    'owner_tax_label': ownerTaxLabel,
    'device_section_title': deviceSectionTitle,
    'start_date_label': startDateLabel,
    'last_used_date_label': lastUsedDateLabel,
    'summary_title': summaryTitle,
    'z_report_label': zReportLabel,
    'vat_total_label': vatTotalLabel,
    'gross_total_label': grossTotalLabel,
    'purpose_label': purposeLabel,
    'other_findings_label': otherFindingsLabel,
    'owner_signature_title': ownerSignatureTitle,
    'service_signature_title': serviceSignatureTitle,
  };
}
