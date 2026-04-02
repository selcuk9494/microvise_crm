import '../../core/format/app_date_time.dart';

class FaultFormRecord {
  const FaultFormRecord({
    required this.id,
    required this.formDate,
    required this.customerId,
    required this.customerName,
    required this.customerAddress,
    required this.customerTaxOffice,
    required this.customerVkn,
    required this.deviceBrandModel,
    required this.companyCodeAndRegistry,
    required this.okcApprovalDateAndNumber,
    required this.faultDateTimeText,
    required this.faultDescription,
    required this.lastZReportDateAndNumber,
    required this.lastZReportDate,
    required this.lastZReportNo,
    required this.totalRevenue,
    required this.totalVat,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final DateTime formDate;
  final String? customerId;
  final String customerName;
  final String? customerAddress;
  final String? customerTaxOffice;
  final String? customerVkn;
  final String? deviceBrandModel;
  final String? companyCodeAndRegistry;
  final String? okcApprovalDateAndNumber;
  final String? faultDateTimeText;
  final String? faultDescription;
  final String? lastZReportDateAndNumber;
  final DateTime? lastZReportDate;
  final String? lastZReportNo;
  final String? totalRevenue;
  final String? totalVat;
  final bool isActive;
  final DateTime? createdAt;

  String get lastZReportDisplay {
    final d = lastZReportDate;
    final no = (lastZReportNo ?? '').trim();
    if (d != null || no.isNotEmpty) {
      final dateText = d == null
          ? ''
          : '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';
      return [dateText, no].where((e) => e.trim().isNotEmpty).join('   ');
    }
    return (lastZReportDateAndNumber ?? '').trim();
  }

  factory FaultFormRecord.fromJson(Map<String, dynamic> json) {
    return FaultFormRecord(
      id: json['id'].toString(),
      formDate: parseAppDateTime(json['form_date']?.toString()) ?? appNow(),
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString() ?? '—',
      customerAddress: json['customer_address']?.toString(),
      customerTaxOffice: json['customer_tax_office']?.toString(),
      customerVkn: json['customer_vkn']?.toString(),
      deviceBrandModel: json['device_brand_model']?.toString(),
      companyCodeAndRegistry: json['company_code_and_registry']?.toString(),
      okcApprovalDateAndNumber: json['okc_approval_date_and_number']?.toString(),
      faultDateTimeText: json['fault_date_time_text']?.toString(),
      faultDescription: json['fault_description']?.toString(),
      lastZReportDateAndNumber:
          json['last_z_report_date_and_number']?.toString(),
      lastZReportDate: parseAppDateTime(json['last_z_report_date']?.toString()),
      lastZReportNo: json['last_z_report_no']?.toString(),
      totalRevenue: json['total_revenue']?.toString(),
      totalVat: json['total_vat']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: parseAppDateTime(json['created_at']?.toString()),
    );
  }
}

class FaultFormPrintSettings {
  const FaultFormPrintSettings({
    required this.id,
    required this.officeCityText,
    required this.officeTitleText,
    required this.formCodeText,
    required this.serviceSectionTitle,
    required this.licenseNoLabel,
    required this.licenseNoValue,
    required this.serviceNameLabel,
    required this.serviceNameValue,
    required this.serviceAddressLabel,
    required this.serviceAddressValue,
    required this.serviceVknLabel,
    required this.serviceVknValue,
    required this.authorizedServiceLabel,
    required this.authorizedServiceValue,
    required this.sealOfficeLine,
    required this.sealManagerLine,
  });

  final String id;
  final String officeCityText;
  final String officeTitleText;
  final String formCodeText;
  final String serviceSectionTitle;
  final String licenseNoLabel;
  final String licenseNoValue;
  final String serviceNameLabel;
  final String serviceNameValue;
  final String serviceAddressLabel;
  final String serviceAddressValue;
  final String serviceVknLabel;
  final String serviceVknValue;
  final String authorizedServiceLabel;
  final String authorizedServiceValue;
  final String sealOfficeLine;
  final String sealManagerLine;

  static const defaults = FaultFormPrintSettings(
    id: 'default',
    officeCityText: 'LEFKOŞA',
    officeTitleText: 'Gelir ve Vergi Dairesi Müdürlüğüne',
    formCodeText: '(Form. KDV 15A)',
    serviceSectionTitle:
        'Ödeme Kaydedici Cihaz\nSatış ve Bakım - Onarım Ruhsatnamesi Sahibinin :',
    licenseNoLabel: 'Ruhsatname No',
    licenseNoValue: '19',
    serviceNameLabel: 'Adı Soyadı / Ünvanı',
    serviceNameValue: 'Microvise Innovation Ltd.',
    serviceAddressLabel: 'Adresi',
    serviceAddressValue: '',
    serviceVknLabel: 'Vergi Sicil No.',
    serviceVknValue: 'VKN:384003147',
    authorizedServiceLabel: 'Yetkili Bakım - Onarım Servisi',
    authorizedServiceValue: 'Microvise Innovation Ltd.',
    sealOfficeLine: 'Gelir ve Vergi Dairesi',
    sealManagerLine: 'Müdürü (A)',
  );

  factory FaultFormPrintSettings.fromJson(Map<String, dynamic> json) {
    return FaultFormPrintSettings(
      id: json['id']?.toString() ?? defaults.id,
      officeCityText: json['office_city_text']?.toString() ?? defaults.officeCityText,
      officeTitleText:
          json['office_title_text']?.toString() ?? defaults.officeTitleText,
      formCodeText: json['form_code_text']?.toString() ?? defaults.formCodeText,
      serviceSectionTitle: json['service_section_title']?.toString() ??
          defaults.serviceSectionTitle,
      licenseNoLabel:
          json['license_no_label']?.toString() ?? defaults.licenseNoLabel,
      licenseNoValue:
          json['license_no_value']?.toString() ?? defaults.licenseNoValue,
      serviceNameLabel:
          json['service_name_label']?.toString() ?? defaults.serviceNameLabel,
      serviceNameValue:
          json['service_name_value']?.toString() ?? defaults.serviceNameValue,
      serviceAddressLabel: json['service_address_label']?.toString() ??
          defaults.serviceAddressLabel,
      serviceAddressValue: json['service_address_value']?.toString() ??
          defaults.serviceAddressValue,
      serviceVknLabel:
          json['service_vkn_label']?.toString() ?? defaults.serviceVknLabel,
      serviceVknValue:
          json['service_vkn_value']?.toString() ?? defaults.serviceVknValue,
      authorizedServiceLabel: json['authorized_service_label']?.toString() ??
          defaults.authorizedServiceLabel,
      authorizedServiceValue: json['authorized_service_value']?.toString() ??
          defaults.authorizedServiceValue,
      sealOfficeLine:
          json['seal_office_line']?.toString() ?? defaults.sealOfficeLine,
      sealManagerLine:
          json['seal_manager_line']?.toString() ?? defaults.sealManagerLine,
    );
  }
}
