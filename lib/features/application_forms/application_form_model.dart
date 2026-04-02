import '../../core/format/app_date_time.dart';

class ApplicationFormRecord {
  const ApplicationFormRecord({
    required this.id,
    required this.applicationDate,
    required this.customerId,
    required this.customerName,
    required this.customerTcknMs,
    required this.workAddress,
    required this.taxOfficeCityName,
    required this.documentType,
    required this.fileRegistryNumber,
    required this.director,
    required this.brandName,
    required this.modelName,
    required this.fiscalSymbolName,
    required this.stockProductId,
    required this.stockProductName,
    required this.stockRegistryNumber,
    required this.accountingOffice,
    required this.okcStartDate,
    required this.businessActivityName,
    required this.invoiceNumber,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final DateTime applicationDate;
  final String? customerId;
  final String customerName;
  final String? customerTcknMs;
  final String? workAddress;
  final String? taxOfficeCityName;
  final String documentType;
  final String? fileRegistryNumber;
  final String? director;
  final String? brandName;
  final String? modelName;
  final String? fiscalSymbolName;
  final String? stockProductId;
  final String? stockProductName;
  final String? stockRegistryNumber;
  final String? accountingOffice;
  final DateTime? okcStartDate;
  final String? businessActivityName;
  final String? invoiceNumber;
  final bool isActive;
  final DateTime? createdAt;

  String get brandModel {
    final parts = [
      if (brandName?.trim().isNotEmpty ?? false) brandName!.trim(),
      if (modelName?.trim().isNotEmpty ?? false) modelName!.trim(),
    ];
    return parts.join(' / ');
  }

  factory ApplicationFormRecord.fromJson(Map<String, dynamic> json) {
    final offsetHours = DateTime.now().timeZoneOffset.inHours;
    return ApplicationFormRecord(
      id: json['id'].toString(),
      applicationDate:
          parseAppDateTime(
            json['application_date']?.toString(),
            fixedOffsetHours: offsetHours,
          ) ??
          DateTime.now(),
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString() ?? '—',
      customerTcknMs: json['customer_tckn_ms']?.toString(),
      workAddress: json['work_address']?.toString(),
      taxOfficeCityName: json['tax_office_city_name']?.toString(),
      documentType: json['document_type']?.toString() ?? 'VKN',
      fileRegistryNumber: json['file_registry_number']?.toString(),
      director: json['director']?.toString(),
      brandName: json['brand_name']?.toString(),
      modelName: json['model_name']?.toString(),
      fiscalSymbolName: json['fiscal_symbol_name']?.toString(),
      stockProductId: json['stock_product_id']?.toString(),
      stockProductName: json['stock_product_name']?.toString(),
      stockRegistryNumber: json['stock_registry_number']?.toString(),
      accountingOffice: json['accounting_office']?.toString(),
      okcStartDate: parseAppDateTime(
        json['okc_start_date']?.toString(),
        fixedOffsetHours: offsetHours,
      ),
      businessActivityName: json['business_activity_name']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdAt: parseAppDateTime(
        json['created_at']?.toString(),
        fixedOffsetHours: offsetHours,
      ),
    );
  }
}

class ApplicationFormPrintSettings {
  const ApplicationFormPrintSettings({
    required this.id,
    required this.officeTitle,
    required this.introText,
    required this.optionalPowerPrecautionText,
    required this.manualIncludedText,
    required this.serviceCompanyName,
    required this.serviceCompanyAddress,
    required this.applicantStatus,
    required this.officeTitle4a,
    required this.kdv4aTitle,
    required this.kdv4aSerialNumber,
    required this.kdv4aSellerCompanyName,
    required this.kdv4aSellerAddress,
    required this.kdv4aSellerTaxOfficeAndRegistry,
    required this.kdv4aSellerLicenseNumber,
    required this.kdv4aWarrantyPeriod,
    required this.kdv4aDepartmentCount,
    required this.kdv4aServiceCompanyName,
    required this.kdv4aServiceCompanyAddress,
    required this.kdv4aSealApplicantName,
    required this.kdv4aSealApplicantTitle,
    required this.kdv4aApprovalDocumentDate,
    required this.kdv4aApprovalDocumentNumber,
    required this.kdv4aDeliveryReceiverName,
    required this.kdv4aDeliveryReceiverTitle,
  });

  final String id;
  final String officeTitle;
  final String introText;
  final String optionalPowerPrecautionText;
  final String manualIncludedText;
  final String serviceCompanyName;
  final String serviceCompanyAddress;
  final String applicantStatus;
  final String officeTitle4a;
  final String kdv4aTitle;
  final String kdv4aSerialNumber;
  final String kdv4aSellerCompanyName;
  final String kdv4aSellerAddress;
  final String kdv4aSellerTaxOfficeAndRegistry;
  final String kdv4aSellerLicenseNumber;
  final String kdv4aWarrantyPeriod;
  final String kdv4aDepartmentCount;
  final String kdv4aServiceCompanyName;
  final String kdv4aServiceCompanyAddress;
  final String kdv4aSealApplicantName;
  final String kdv4aSealApplicantTitle;
  final String kdv4aApprovalDocumentDate;
  final String kdv4aApprovalDocumentNumber;
  final String kdv4aDeliveryReceiverName;
  final String kdv4aDeliveryReceiverTitle;

  static const defaults = ApplicationFormPrintSettings(
    id: 'default',
    officeTitle: 'Maliye Bakanlığı\nGelir ve Vergi Dairesi\nLEFKOŞA',
    introText:
        "47/1992 Sayılı Katma Değer Vergisi Yazası' nın 53' üncü maddesi uyarınca işletmemizin "
        "Ödeme Kaydedici Cihaz kullanma zorunluluğunun yerine getirilebilmesi için aşağıdaki hususları "
        "beyan eder, gerekli onayın verilmesini rica ederim.",
    optionalPowerPrecautionText: 'Opsiyonel',
    manualIncludedText: 'Var',
    serviceCompanyName: 'MICROVISE INNOVATION LTD.',
    serviceCompanyAddress: 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa',
    applicantStatus: 'DİREKTÖR',
    officeTitle4a:
        'Maliye Bakanlığı\nGelir ve Vergi Dairesi Müdürlüğü\nLEFKOŞA',
    kdv4aTitle:
        'ÖDEME KAYDEDİCİ CİHAZ KULLANIM ONAYINA\nİLİŞKİN\nMALİ MÜHÜR UYGULAMA TUTANAĞI',
    kdv4aSerialNumber: '',
    kdv4aSellerCompanyName: 'MICROVISE INNOVATION LTD.',
    kdv4aSellerAddress: 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa',
    kdv4aSellerTaxOfficeAndRegistry: 'Lefkoşa Mş:19660',
    kdv4aSellerLicenseNumber: '068',
    kdv4aWarrantyPeriod: '12',
    kdv4aDepartmentCount: '8',
    kdv4aServiceCompanyName: 'MICROVISE INNOVATION LTD.',
    kdv4aServiceCompanyAddress: 'Atatürk Cad Emek 2 No:1 Yenişehir Lefkoşa',
    kdv4aSealApplicantName: '',
    kdv4aSealApplicantTitle: '',
    kdv4aApprovalDocumentDate: '',
    kdv4aApprovalDocumentNumber: '',
    kdv4aDeliveryReceiverName: 'Selçuk Yılmaz',
    kdv4aDeliveryReceiverTitle: 'Direktör',
  );

  factory ApplicationFormPrintSettings.fromJson(Map<String, dynamic> json) {
    return ApplicationFormPrintSettings(
      id: json['id']?.toString() ?? 'default',
      officeTitle: json['office_title']?.toString() ?? defaults.officeTitle,
      introText: json['intro_text']?.toString() ?? defaults.introText,
      optionalPowerPrecautionText:
          json['optional_power_precaution_text']?.toString() ??
          defaults.optionalPowerPrecautionText,
      manualIncludedText:
          json['manual_included_text']?.toString() ??
          defaults.manualIncludedText,
      serviceCompanyName:
          json['service_company_name']?.toString() ??
          defaults.serviceCompanyName,
      serviceCompanyAddress:
          json['service_company_address']?.toString() ??
          defaults.serviceCompanyAddress,
      applicantStatus:
          json['applicant_status']?.toString() ?? defaults.applicantStatus,
      officeTitle4a:
          json['office_title_4a']?.toString() ?? defaults.officeTitle4a,
      kdv4aTitle: json['kdv4a_title']?.toString() ?? defaults.kdv4aTitle,
      kdv4aSerialNumber:
          json['kdv4a_serial_number']?.toString() ?? defaults.kdv4aSerialNumber,
      kdv4aSellerCompanyName:
          json['kdv4a_seller_company_name']?.toString() ??
          defaults.kdv4aSellerCompanyName,
      kdv4aSellerAddress:
          json['kdv4a_seller_address']?.toString() ??
          defaults.kdv4aSellerAddress,
      kdv4aSellerTaxOfficeAndRegistry:
          json['kdv4a_seller_tax_office_and_registry']?.toString() ??
          defaults.kdv4aSellerTaxOfficeAndRegistry,
      kdv4aSellerLicenseNumber:
          json['kdv4a_seller_license_number']?.toString() ??
          defaults.kdv4aSellerLicenseNumber,
      kdv4aWarrantyPeriod:
          json['kdv4a_warranty_period']?.toString() ??
          defaults.kdv4aWarrantyPeriod,
      kdv4aDepartmentCount:
          json['kdv4a_department_count']?.toString() ??
          defaults.kdv4aDepartmentCount,
      kdv4aServiceCompanyName:
          json['kdv4a_service_company_name']?.toString() ??
          defaults.kdv4aServiceCompanyName,
      kdv4aServiceCompanyAddress:
          json['kdv4a_service_company_address']?.toString() ??
          defaults.kdv4aServiceCompanyAddress,
      kdv4aSealApplicantName:
          json['kdv4a_seal_applicant_name']?.toString() ??
          defaults.kdv4aSealApplicantName,
      kdv4aSealApplicantTitle:
          json['kdv4a_seal_applicant_title']?.toString() ??
          defaults.kdv4aSealApplicantTitle,
      kdv4aApprovalDocumentDate:
          json['kdv4a_approval_document_date']?.toString() ??
          defaults.kdv4aApprovalDocumentDate,
      kdv4aApprovalDocumentNumber:
          json['kdv4a_approval_document_number']?.toString() ??
          defaults.kdv4aApprovalDocumentNumber,
      kdv4aDeliveryReceiverName:
          json['kdv4a_delivery_receiver_name']?.toString() ??
          defaults.kdv4aDeliveryReceiverName,
      kdv4aDeliveryReceiverTitle:
          json['kdv4a_delivery_receiver_title']?.toString() ??
          defaults.kdv4aDeliveryReceiverTitle,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'office_title': officeTitle,
    'intro_text': introText,
    'optional_power_precaution_text': optionalPowerPrecautionText,
    'manual_included_text': manualIncludedText,
    'service_company_name': serviceCompanyName,
    'service_company_address': serviceCompanyAddress,
    'applicant_status': applicantStatus,
    'office_title_4a': officeTitle4a,
    'kdv4a_title': kdv4aTitle,
    'kdv4a_serial_number': kdv4aSerialNumber,
    'kdv4a_seller_company_name': kdv4aSellerCompanyName,
    'kdv4a_seller_address': kdv4aSellerAddress,
    'kdv4a_seller_tax_office_and_registry': kdv4aSellerTaxOfficeAndRegistry,
    'kdv4a_seller_license_number': kdv4aSellerLicenseNumber,
    'kdv4a_warranty_period': kdv4aWarrantyPeriod,
    'kdv4a_department_count': kdv4aDepartmentCount,
    'kdv4a_service_company_name': kdv4aServiceCompanyName,
    'kdv4a_service_company_address': kdv4aServiceCompanyAddress,
    'kdv4a_seal_applicant_name': kdv4aSealApplicantName,
    'kdv4a_seal_applicant_title': kdv4aSealApplicantTitle,
    'kdv4a_approval_document_date': kdv4aApprovalDocumentDate,
    'kdv4a_approval_document_number': kdv4aApprovalDocumentNumber,
    'kdv4a_delivery_receiver_name': kdv4aDeliveryReceiverName,
    'kdv4a_delivery_receiver_title': kdv4aDeliveryReceiverTitle,
  };
}
