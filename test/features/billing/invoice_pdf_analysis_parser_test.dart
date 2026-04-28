import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/billing/invoice_pdf_analysis_parser.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

void main() {
  group('InvoicePdfAnalysisParser', () {
    test('TL ornek faturayi ayrisir', () async {
      final file = File('dokuman/fatura/TL.pdf');
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await file.readAsBytes(),
        fileName: file.path.split(Platform.pathSeparator).last,
      );

      expect(entry, isNotNull);
      expect(entry!.customerName, 'Worldline POS Teknoloji Çözüm ve Servisleri A.Ş.');
      expect(entry.invoiceNumber, '620009058.01.2026.DA.0000001819');
      expect(entry.currency, 'TRY');
      expect(entry.subtotal, closeTo(34046.10, 0.01));
      expect(entry.taxTotal, closeTo(0, 0.01));
      expect(entry.items.length, 2);
      expect(entry.items.first.description, 'INGENICO BANKA UYGULAMASI');
      expect(entry.items.first.taxRate, 0);
    });

    test('USD ornek faturayi ayrisir', () async {
      final file = File('dokuman/fatura/usd.pdf');
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await file.readAsBytes(),
        fileName: file.path.split(Platform.pathSeparator).last,
      );

      expect(entry, isNotNull);
      expect(entry!.customerName, 'ALİ ERTAN & CO LTD');
      expect(entry.invoiceNumber, '620009058.01.2026.DA.0000001915');
      expect(entry.currency, 'USD');
      expect(entry.subtotal, closeTo(658.96, 0.01));
      expect(entry.taxTotal, closeTo(105.43, 0.01));
      expect(entry.grandTotal, closeTo(764.39, 0.01));
      expect(entry.items.length, 2);
      expect(entry.items.first.taxRate, 16);
      expect(entry.items.first.taxAmount, closeTo(14.40, 0.01));
    });

    test('ALACAK ile baslayan belgeyi dikkate almaz', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'e-Arsiv Fatura ALACAK Fatura No : A-1 Fatura Tarihi : 27-04-2026 10:00',
        ),
        fileName: 'alacak.pdf',
      );

      expect(entry, isNull);
    });

    test('ALACAK harfleri aralikli gelse de belgeyi dikkate almaz', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'e Arsiv Fatura A L A C A K Fatura No : A-2 Fatura Tarihi : 27-04-2026 10:00',
        ),
        fileName: 'alacak_aralikli.pdf',
      );

      expect(entry, isNull);
    });

    test('ALACAK metni fatura no oncesinde daha ileride gelse de belgeyi dikkate almaz', () async {
      final filler = List.filled(180, 'X').join(' ');
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'e Arsiv Fatura $filler ALACAK Fatura No : A-3 Fatura Tarihi : 27-04-2026 10:00',
        ),
        fileName: 'alacak_uzun_baslik.pdf',
      );

      expect(entry, isNull);
    });

    test('dosya adinda ALACAK geciyorsa belgeyi dikkate almaz', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'Fatura No : A-4 Fatura Tarihi : 27-04-2026 10:00',
        ),
        fileName: '2026-03-26_ALACAK_fatura.pdf',
      );

      expect(entry, isNull);
    });

    test('IPTAL ile baslayan belge tutarlari sifirlar', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'Ticari e-Arsiv Fatura IPTAL '
          'Fatura No : I-1 '
          'Fatura Tarihi : 27-04-2026 10:00 '
          'ALICININ ADI / UNVANI : ORNEK LTD ADRESI '
          'Sira No '
          '1 HIZMET 1,00 ADET 100,00 TL %0 0,00 TL %16 16,00 TL 100,00 TL '
          'Mal Hizmet Toplam Tutari 100,00 TL '
          'Hesaplanan KDV 16,00 TL '
          'Vergiler Dahil Toplam Tutar 116,00 TL',
        ),
        fileName: 'iptal.pdf',
      );

      expect(entry, isNotNull);
      expect(entry!.subtotal, 0);
      expect(entry.taxTotal, 0);
      expect(entry.grandTotal, 0);
      expect(entry.invoiceNumber, 'I-1');
    });

    test('IPTAL harfleri aralikli gelse de tutarlari sifirlar', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'Ticari e Arsiv Fatura I P T A L '
          'Fatura No : I-2 '
          'Fatura Tarihi : 27-04-2026 10:00 '
          'ALICININ ADI / UNVANI : ORNEK LTD ADRESI '
          'Mal Hizmet Toplam Tutari 200,00 TL '
          'Hesaplanan KDV 32,00 TL '
          'Vergiler Dahil Toplam Tutar 232,00 TL',
        ),
        fileName: 'iptal_aralikli.pdf',
      );

      expect(entry, isNotNull);
      expect(entry!.subtotal, 0);
      expect(entry.taxTotal, 0);
      expect(entry.grandTotal, 0);
    });

    test('IPTAL metni fatura no oncesinde daha ileride gelse de tutarlari sifirlar', () async {
      final filler = List.filled(180, 'Y').join(' ');
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'Ticari e Arsiv Fatura $filler IPTAL '
          'Fatura No : I-3 '
          'Fatura Tarihi : 27-04-2026 10:00 '
          'ALICININ ADI / UNVANI : ORNEK LTD ADRESI '
          'Mal Hizmet Toplam Tutari 200,00 TL '
          'Hesaplanan KDV 32,00 TL '
          'Vergiler Dahil Toplam Tutar 232,00 TL',
        ),
        fileName: 'iptal_uzun_baslik.pdf',
      );

      expect(entry, isNotNull);
      expect(entry!.subtotal, 0);
      expect(entry.taxTotal, 0);
      expect(entry.grandTotal, 0);
    });

    test('dosya adinda IPTAL geciyorsa belge tutarlari sifirlar', () async {
      final entry = await InvoicePdfAnalysisParser.parse(
        bytes: await _buildSamplePdf(
          'Fatura No : I-4 '
          'Fatura Tarihi : 27-04-2026 10:00 '
          'ALICININ ADI / UNVANI : ORNEK LTD ADRESI '
          'Mal Hizmet Toplam Tutari 200,00 TL '
          'Hesaplanan KDV 32,00 TL '
          'Vergiler Dahil Toplam Tutar 232,00 TL',
        ),
        fileName: '2026-03-26_IPTAL_fatura.pdf',
      );

      expect(entry, isNotNull);
      expect(entry!.subtotal, 0);
      expect(entry.taxTotal, 0);
      expect(entry.grandTotal, 0);
    });
  });
}

Future<Uint8List> _buildSamplePdf(String text) async {
  final document = PdfDocument();
  final page = document.pages.add();
  page.graphics.drawString(
    text,
    PdfStandardFont(PdfFontFamily.helvetica, 12),
    bounds: const Rect.fromLTWH(0, 0, 500, 700),
    format: PdfStringFormat(wordWrap: PdfWordWrapType.word),
  );
  final bytes = document.saveSync();
  document.dispose();
  return Uint8List.fromList(bytes);
}
