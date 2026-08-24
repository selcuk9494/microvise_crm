import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:intl/date_symbol_data_local.dart';
import 'package:microvise_crm/features/quotes/quote_model.dart';
import 'package:microvise_crm/features/quotes/quote_pdf.dart';

String _thumbDataUrl({
  required int r,
  required int g,
  required int b,
}) {
  final canvas = img.Image(width: 96, height: 96);
  img.fill(canvas, color: img.ColorRgb8(245, 247, 250));
  img.drawRect(
    canvas,
    x1: 8,
    y1: 8,
    x2: 87,
    y2: 87,
    color: img.ColorRgb8(r, g, b),
  );
  img.drawRect(
    canvas,
    x1: 8,
    y1: 8,
    x2: 87,
    y2: 87,
    color: img.ColorRgb8(30, 58, 95),
    thickness: 2,
  );
  final png = img.encodePng(canvas);
  return 'data:image/png;base64,${base64Encode(png)}';
}

Quote _sampleQuote({
  required String number,
  required String currency,
  required double exchangeRate,
  required String customerName,
  required List<QuoteItem> items,
  required double subtotal,
  required double taxTotal,
  required double grandTotal,
  bool pricesIncludeVat = false,
  String? notes,
}) {
  return Quote(
    id: 'sample-$number',
    quoteNumber: number,
    customerId: 'sample-customer',
    customerName: customerName,
    quoteDate: DateTime(2026, 8, 24),
    validUntil: DateTime(2026, 9, 7),
    currency: currency,
    exchangeRate: exchangeRate,
    pricesIncludeVat: pricesIncludeVat,
    subtotal: subtotal,
    taxTotal: taxTotal,
    discountTotal: 0,
    grandTotal: grandTotal,
    status: 'draft',
    notes: notes,
    isActive: true,
    createdAt: DateTime(2026, 8, 24),
    items: items,
  );
}

QuoteItem _item({
  required String id,
  required String description,
  required double qty,
  required double unitPrice,
  required double taxRate,
  required double lineTotal,
  String unit = 'Adet',
  String? imageUrl,
}) {
  final subtotal = qty * unitPrice;
  final tax = subtotal * taxRate / 100;
  return QuoteItem(
    id: id,
    quoteId: 'sample',
    imageUrl: imageUrl,
    description: description,
    quantity: qty,
    unit: unit,
    unitPrice: unitPrice,
    taxRate: taxRate,
    taxAmount: tax,
    discountRate: 0,
    discountAmount: 0,
    lineTotal: lineTotal,
    sortOrder: int.tryParse(id) ?? 0,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await initializeDateFormatting('tr_TR');
  });

  test('generate teklif PDF samples', () async {
    final outDir = Directory('docs/samples/teklif');
    final thumbDir = Directory('docs/samples/teklif/thumbs');
    outDir.createSync(recursive: true);
    thumbDir.createSync(recursive: true);

    final switchThumb = _thumbDataUrl(r: 39, g: 119, b: 119);
    final serviceThumb = _thumbDataUrl(r: 100, g: 116, b: 139);
    final iotThumb = _thumbDataUrl(r: 30, g: 58, b: 95);
    final licenseThumb = _thumbDataUrl(r: 52, g: 152, b: 219);
    final crmThumb = _thumbDataUrl(r: 46, g: 125, b: 50);
    final efaturaThumb = _thumbDataUrl(r: 211, g: 84, b: 0);
    final panelThumb = _thumbDataUrl(r: 142, g: 68, b: 173);
    final cableThumb = _thumbDataUrl(r: 41, g: 128, b: 185);

    await File('${thumbDir.path}/switch.png').writeAsBytes(
      base64Decode(switchThumb.split(',').last),
    );
    await File('${thumbDir.path}/service.png').writeAsBytes(
      base64Decode(serviceThumb.split(',').last),
    );

    final samples = <(String, Quote)>[
      (
        'teklif_try_ornek.pdf',
        _sampleQuote(
          number: 'TKL-2026-TRY-001',
          currency: 'TRY',
          exchangeRate: 1,
          customerName: 'İPEK HÜRDENİZ',
          notes: 'Teslimat süresi 10 iş günüdür. Fiyatlar KDV hariçtir.',
          subtotal: 763.67,
          taxTotal: 152.73,
          grandTotal: 916.40,
          items: [
            _item(
              id: '1',
              description: 'Network Switch 24 Port\nCisco CBS350-24T-4G',
              qty: 2,
              unitPrice: 250,
              taxRate: 20,
              lineTotal: 600,
              imageUrl: switchThumb,
            ),
            _item(
              id: '2',
              description: 'Kurulum ve Devreye Alma Hizmeti',
              qty: 1,
              unitPrice: 263.67,
              taxRate: 20,
              lineTotal: 316.40,
              imageUrl: serviceThumb,
            ),
          ],
        ),
      ),
      (
        'teklif_try_kdv_dahil_ornek.pdf',
        _sampleQuote(
          number: 'TKL-2026-TRY-KDV',
          currency: 'TRY',
          exchangeRate: 1,
          customerName: 'LEFKOŞA TEKNİK LTD.',
          pricesIncludeVat: true,
          notes:
              'Formda birim fiyatlar KDV dahil girildi '
              '(ornek: 300 TL -> matrah 250 TL + %20 KDV).',
          // Giriş: 2×300 + 1×316.40 (KDV dahil) → matrah 763.67
          subtotal: 763.67,
          taxTotal: 152.73,
          grandTotal: 916.40,
          items: [
            _item(
              id: '1',
              description: 'Network Switch 24 Port\nCisco CBS350-24T-4G',
              qty: 2,
              unitPrice: 250, // KDV hariç kayıt; formda 300 girilmişti
              taxRate: 20,
              lineTotal: 600,
              imageUrl: switchThumb,
            ),
            _item(
              id: '2',
              description: 'Kurulum ve Devreye Alma Hizmeti',
              qty: 1,
              unitPrice: 263.67,
              taxRate: 20,
              lineTotal: 316.40,
              imageUrl: serviceThumb,
            ),
          ],
        ),
      ),
      (
        'teklif_usd_ornek.pdf',
        _sampleQuote(
          number: 'TKL-2026-USD-001',
          currency: 'USD',
          exchangeRate: 49.5005,
          customerName: 'A.M.G TRADING LTD.',
          notes: 'Payment terms: 30% advance, 70% before shipment.',
          subtotal: 1250,
          taxTotal: 0,
          grandTotal: 1250,
          items: [
            _item(
              id: '1',
              description: 'Industrial IoT Gateway\n4G / Ethernet / RS485',
              qty: 5,
              unitPrice: 180,
              taxRate: 0,
              lineTotal: 900,
              imageUrl: iotThumb,
            ),
            _item(
              id: '2',
              description: 'Remote Monitoring License (1 year)',
              qty: 5,
              unitPrice: 70,
              taxRate: 0,
              lineTotal: 350,
              imageUrl: licenseThumb,
            ),
          ],
        ),
      ),
      (
        'teklif_eur_ornek.pdf',
        _sampleQuote(
          number: 'TKL-2026-EUR-001',
          currency: 'EUR',
          exchangeRate: 53.25,
          customerName: 'EUROTECH GmbH',
          notes: 'Geçerlilik süresi 21 gündür. EXW Lefkoşa.',
          subtotal: 4800,
          taxTotal: 960,
          grandTotal: 5760,
          items: [
            _item(
              id: '1',
              description: 'CRM Modül Lisansı (50 kullanıcı)',
              qty: 1,
              unitPrice: 3200,
              taxRate: 20,
              lineTotal: 3840,
              imageUrl: crmThumb,
            ),
            _item(
              id: '2',
              description: 'E-Fatura Entegrasyon Paketi',
              qty: 1,
              unitPrice: 1600,
              taxRate: 20,
              lineTotal: 1920,
              imageUrl: efaturaThumb,
            ),
            _item(
              id: '3',
              description: 'Yazılım Danışmanlık (saatlik)',
              qty: 8,
              unit: 'Saat',
              unitPrice: 0,
              taxRate: 20,
              lineTotal: 0,
            ),
          ],
        ),
      ),
      (
        'teklif_gbp_ornek.pdf',
        _sampleQuote(
          number: 'TKL-2026-GBP-001',
          currency: 'GBP',
          exchangeRate: 62.10,
          customerName: 'NORTH CYPRUS ENERGY LTD.',
          notes: 'Quote valid for 14 days. Prices exclude VAT.',
          subtotal: 2150,
          taxTotal: 430,
          grandTotal: 2580,
          items: [
            _item(
              id: '1',
              description: 'Solar Monitoring Panel Kit',
              qty: 3,
              unitPrice: 450,
              taxRate: 20,
              lineTotal: 1620,
              imageUrl: panelThumb,
            ),
            _item(
              id: '2',
              description: 'Cat6 Outdoor Cable (metre)',
              qty: 100,
              unit: 'Mt',
              unitPrice: 8,
              taxRate: 20,
              lineTotal: 960,
              imageUrl: cableThumb,
            ),
          ],
        ),
      ),
    ];

    for (final sample in samples) {
      final bytes = await buildQuotePdfBytes(quote: sample.$2);
      final file = File('${outDir.path}/${sample.$1}');
      await file.writeAsBytes(bytes);
      expect(bytes.isNotEmpty, isTrue);
      expect(await file.length(), greaterThan(1000));
    }
  });
}
