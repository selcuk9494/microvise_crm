class ApplicationFormRecord {
  const ApplicationFormRecord({
    required this.id,
    required this.applicationDate,
    required this.customerId,
    required this.customerName,
    required this.workAddress,
    required this.taxOfficeCityName,
    required this.documentType,
    required this.fileRegistryNumber,
    required this.director,
    required this.brandName,
    required this.modelName,
    required this.fiscalSymbolName,
    required this.stockProductName,
    required this.stockRegistryNumber,
    required this.accountingOffice,
    required this.okcStartDate,
    required this.businessActivityName,
    required this.invoiceNumber,
    required this.createdAt,
  });

  final String id;
  final DateTime applicationDate;
  final String? customerId;
  final String customerName;
  final String? workAddress;
  final String? taxOfficeCityName;
  final String documentType;
  final String? fileRegistryNumber;
  final String? director;
  final String? brandName;
  final String? modelName;
  final String? fiscalSymbolName;
  final String? stockProductName;
  final String? stockRegistryNumber;
  final String? accountingOffice;
  final DateTime? okcStartDate;
  final String? businessActivityName;
  final String? invoiceNumber;
  final DateTime? createdAt;

  String get brandModel {
    final parts = [
      if (brandName?.trim().isNotEmpty ?? false) brandName!.trim(),
      if (modelName?.trim().isNotEmpty ?? false) modelName!.trim(),
    ];
    return parts.join(' / ');
  }

  factory ApplicationFormRecord.fromJson(Map<String, dynamic> json) {
    return ApplicationFormRecord(
      id: json['id'].toString(),
      applicationDate:
          DateTime.tryParse(json['application_date']?.toString() ?? '') ??
          DateTime.now(),
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString() ?? '—',
      workAddress: json['work_address']?.toString(),
      taxOfficeCityName: json['tax_office_city_name']?.toString(),
      documentType: json['document_type']?.toString() ?? 'VKN',
      fileRegistryNumber: json['file_registry_number']?.toString(),
      director: json['director']?.toString(),
      brandName: json['brand_name']?.toString(),
      modelName: json['model_name']?.toString(),
      fiscalSymbolName: json['fiscal_symbol_name']?.toString(),
      stockProductName: json['stock_product_name']?.toString(),
      stockRegistryNumber: json['stock_registry_number']?.toString(),
      accountingOffice: json['accounting_office']?.toString(),
      okcStartDate: DateTime.tryParse(json['okc_start_date']?.toString() ?? ''),
      businessActivityName: json['business_activity_name']?.toString(),
      invoiceNumber: json['invoice_number']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}
