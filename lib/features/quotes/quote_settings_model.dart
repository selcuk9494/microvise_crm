import '../invoices/invoice_statement_pdf.dart';

class QuoteDocumentSettings {
  const QuoteDocumentSettings({
    required this.logoUrl,
    required this.companyTitle,
    required this.companySubtitle,
    required this.bankDetails,
    required this.termsAndConditions,
  });

  final String? logoUrl;
  final String companyTitle;
  final String companySubtitle;
  final String bankDetails;
  final String termsAndConditions;

  static QuoteDocumentSettings defaults() => const QuoteDocumentSettings(
    logoUrl: null,
    companyTitle: 'MICROVISE',
    companySubtitle: 'Innovation Ltd',
    bankDetails: kDefaultSellerBankDetails,
    termsAndConditions: '',
  );

  factory QuoteDocumentSettings.fromJson(Map<String, dynamic> json) {
    final defaults = QuoteDocumentSettings.defaults();
    return QuoteDocumentSettings(
      logoUrl: _nullable(json['logo_url']),
      companyTitle: _text(json['company_title'], defaults.companyTitle),
      companySubtitle: _text(json['company_subtitle'], defaults.companySubtitle),
      bankDetails: _text(json['bank_details'], defaults.bankDetails),
      termsAndConditions: _text(json['terms_and_conditions'], ''),
    );
  }

  Map<String, dynamic> toUpsertJson() => {
    'id': 1,
    'company_title': companyTitle.trim(),
    'company_subtitle': companySubtitle.trim(),
    'bank_details': bankDetails.trim().isEmpty ? null : bankDetails.trim(),
    'terms_and_conditions': termsAndConditions.trim().isEmpty
        ? null
        : termsAndConditions.trim(),
    if (logoUrl != null && logoUrl!.trim().isNotEmpty)
      'logo_url': logoUrl!.trim(),
  };

  static String? _nullable(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static String _text(dynamic value, String fallback) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return fallback;
    return raw;
  }
}
