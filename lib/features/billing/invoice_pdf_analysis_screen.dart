import 'package:flutter/material.dart';

import '../../core/ui/app_page_layout.dart';
import 'invoice_pdf_analysis_section.dart';

class InvoicePdfAnalysisScreen extends StatelessWidget {
  const InvoicePdfAnalysisScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppPageLayout(
      title: 'KDV Analizi',
      subtitle: 'PDF faturalardan musteri, fatura no, tarife ve oran bazli KDV dagilimini analiz edin.',
      body: InvoicePdfAnalysisSection(),
    );
  }
}
