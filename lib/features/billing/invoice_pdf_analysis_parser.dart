import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import 'invoice_pdf_analysis_model.dart';

class InvoicePdfAnalysisParser {
  static final RegExp _itemPattern = RegExp(
    r'(\d+)\s+(.+?)\s+(\d+[\.,]\d+)\s+(\S+)\s+([0-9\.,]+)\s*(TL|TRY|USD|EUR|GBP)\s+%([0-9\.,]+)\s+([0-9\.,]+)\s*(TL|TRY|USD|EUR|GBP)(?:\s+%([0-9\.,]+)\s+([0-9\.,]+)\s*(TL|TRY|USD|EUR|GBP))?\s+([0-9\.,]+)\s*(TL|TRY|USD|EUR|GBP)(?=\s+\d+\s+|\s+Mal Hizmet Toplam Tutarı|$)',
    caseSensitive: false,
  );

  static final RegExp _invoiceNumberPattern = RegExp(
    r'Fatura\s*No\s*:\s*([A-Z0-9./-]+?)(?=\s*Fatura\s*Tarihi|\s*Damga|\s*Belge|\s*Tedarikçi|\s*Tedarikci|\s*Müşteri|\s*Musteri|\s*FATURA\s*TARİHİ|\s*FATURA\s*TARIHI|$)',
    caseSensitive: false,
  );
  static final RegExp _invoiceDatePattern = RegExp(
    r'Fatura\s*Tarihi\s*:\s*([0-9]{2}-[0-9]{2}-[0-9]{4}\s+[0-9]{2}:[0-9]{2})',
    caseSensitive: false,
  );

  /// Microvise / KKTC Maliye e-Fatura satır kuyruğu:
  /// miktar birim | birim fiyat | [indirim] | KDV% | KDV tutarı | toplam
  static final RegExp _microviseRowTail = RegExp(
    r'(\d+(?:[.,]\d+)?)\s+'
    r'(Adet|Kg|Lt|Mt|Saat|ADET\s*\(\s*UNIT\s*\)|KG\s*\(\s*KILOGRAM\s*\)|'
    r'LT\s*\(\s*LITRE\s*\)|MT\s*\(\s*METRE\s*\)|SAAT\s*\(\s*HOUR\s*\))\s+'
    r'(-?[₺\$€£]?[0-9.,]+)\s+'
    r'(?:(-[₺\$€£]?[0-9.,]+|-)\s+)?'
    r'(\d+(?:[.,]\d+)?)\s*%\s+'
    r'(-?[₺\$€£]?[0-9.,]+)\s+'
    r'(-?[₺\$€£]?[0-9.,]+)',
    caseSensitive: false,
  );

  static final RegExp _microviseUnitOnly = RegExp(
    r'^(Adet|Kg|Lt|Mt|Saat|ADET\s*\(\s*UNIT\s*\)|KG\s*\(\s*KILOGRAM\s*\)|'
    r'LT\s*\(\s*LITRE\s*\)|MT\s*\(\s*METRE\s*\)|SAAT\s*\(\s*HOUR\s*\))$',
    caseSensitive: false,
  );

  static Future<InvoicePdfAnalysisEntry?> parse({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    final leadingMarker = detectDocumentMarker(
      text,
      fileName: fileName,
    );
    if (leadingMarker == 'ALACAK') return null;

    final isCancelled = leadingMarker == 'IPTAL';
    if (isMicroviseEInvoice(text)) {
      return _parseMicrovise(
        text: text,
        fileName: fileName,
        zeroAmounts: isCancelled,
      );
    }
    return _parseLegacy(
      text: text,
      fileName: fileName,
      zeroAmounts: isCancelled,
    );
  }

  /// CRM/Maliye şablonu: "KKTC E-Fatura Sistemi", taraf kutuları, Ara/Ödenecek Toplam.
  static bool isMicroviseEInvoice(String rawText) {
    final normalized = _normalizeText(rawText);
    final hasSystem = RegExp(
      r'KKTC\s*E-?Fatura\s*Sistemi|K\.?\s*K\.?\s*T\.?\s*C\.?\s*Maliye',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasParty = RegExp(
      r'Müşteri\s*Bilgileri|Musteri\s*Bilgileri',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasTotals = RegExp(
      r'Ara\s*Toplam\s*:.*(?:KDV\s*Toplam[ıi]\s*:|Ödenecek\s*Toplam\s*:|Odenecek\s*Toplam\s*:)',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasOldTotals = RegExp(
      r'Mal\s*Hizmet\s*Toplam\s*Tutarı|Vergiler\s*Dahil\s*Toplam\s*Tutar|ALICININ',
      caseSensitive: false,
    ).hasMatch(normalized);

    if (hasSystem && hasTotals) return true;
    if (hasParty && hasTotals && !hasOldTotals) return true;
    return false;
  }

  static InvoicePdfAnalysisEntry _parseMicrovise({
    required String text,
    required String fileName,
    required bool zeroAmounts,
  }) {
    final normalized = _normalizeText(text);
    final items = _parseMicroviseItems(text, zeroAmounts: zeroAmounts);
    final subtotal = _extractMicroviseLabeledAmount(normalized, 'Ara Toplam');
    final taxTotal = _extractFirstMicroviseLabeledAmount(normalized, const [
      'KDV Toplamı',
      'KDV Toplami',
    ]);
    final grandTotal = _extractFirstMicroviseLabeledAmount(normalized, const [
      'Ödenecek Toplam',
      'Odenecek Toplam',
    ]);

    final currency =
        _extractMicroviseCurrency(normalized) ??
        _currencyFromMoneySymbol(normalized) ??
        items.firstWhere(
          (item) => item.currency.trim().isNotEmpty,
          orElse: () => const InvoicePdfLineItem(
            rowNo: 0,
            description: '',
            quantity: 0,
            unit: '',
            unitPrice: 0,
            currency: 'TRY',
            discountRate: 0,
            discountAmount: 0,
            taxRate: 0,
            taxAmount: 0,
            lineBaseAmount: 0,
          ),
        ).currency;

    return InvoicePdfAnalysisEntry(
      fileName: fileName,
      customerName: _extractMicroviseCustomerName(text, normalized),
      invoiceNumber:
          _invoiceNumberPattern.firstMatch(normalized)?.group(1)?.trim() ??
          fileName,
      invoiceDate: _extractMicroviseInvoiceDate(normalized),
      currency: _normalizeCurrency(currency),
      subtotal: zeroAmounts ? 0 : subtotal,
      taxTotal: zeroAmounts ? 0 : taxTotal,
      grandTotal: zeroAmounts ? 0 : grandTotal,
      items: items,
      rawText: text,
    );
  }

  static InvoicePdfAnalysisEntry _parseLegacy({
    required String text,
    required String fileName,
    required bool zeroAmounts,
  }) {
    final normalized = _normalizeText(text);
    final items = _parseItems(text, zeroAmounts: zeroAmounts);
    final subtotal = _extractLabeledAmount(
      normalized,
      'Mal Hizmet Toplam Tutarı',
    );
    final taxTotal = _extractLabeledAmount(normalized, 'Hesaplanan KDV');
    final grandTotal = _extractLabeledAmount(
      normalized,
      'Vergiler Dahil Toplam Tutar',
    );

    final currency =
        _extractCurrency(normalized) ??
        items.firstWhere(
          (item) => item.currency.trim().isNotEmpty,
          orElse: () => const InvoicePdfLineItem(
            rowNo: 0,
            description: '',
            quantity: 0,
            unit: '',
            unitPrice: 0,
            currency: 'TRY',
            discountRate: 0,
            discountAmount: 0,
            taxRate: 0,
            taxAmount: 0,
            lineBaseAmount: 0,
          ),
        ).currency;

    return InvoicePdfAnalysisEntry(
      fileName: fileName,
      customerName: _extractCustomerName(normalized),
      invoiceNumber:
          _invoiceNumberPattern.firstMatch(normalized)?.group(1)?.trim() ??
          fileName,
      invoiceDate: _extractInvoiceDate(normalized),
      currency: _normalizeCurrency(currency),
      subtotal: zeroAmounts ? 0 : subtotal,
      taxTotal: zeroAmounts ? 0 : taxTotal,
      grandTotal: zeroAmounts ? 0 : grandTotal,
      items: items,
      rawText: text,
    );
  }

  static List<InvoicePdfLineItem> _parseMicroviseItems(
    String rawText, {
    bool zeroAmounts = false,
  }) {
    final itemBlock = _extractMicroviseItemBlock(rawText);
    if (itemBlock.isEmpty) return const [];

    final normalizedBlock = _normalizeText(itemBlock);
    final currencyHint =
        _extractMicroviseCurrency(_normalizeText(rawText)) ??
        _currencyFromMoneySymbol(normalizedBlock) ??
        'TRY';

    final items = <InvoicePdfLineItem>[];
    var cursor = 0;
    var rowNo = 1;
    for (final match in _microviseRowTail.allMatches(normalizedBlock)) {
      final description = normalizedBlock.substring(cursor, match.start).trim();
      cursor = match.end;

      final quantity = _parseAmount(match.group(1));
      final unit = (match.group(2) ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();
      final unitPrice = _parseMoney(match.group(3));
      final discountRaw = (match.group(4) ?? '').trim();
      final discountAmount = discountRaw.isEmpty || discountRaw == '-'
          ? 0.0
          : _parseMoney(discountRaw).abs();
      final taxRate = _parsePercent(match.group(5));
      final taxAmount = _parseMoney(match.group(6));
      final lineTotal = _parseMoney(match.group(7));
      final lineBase = lineTotal > 0 && lineTotal >= taxAmount
          ? (lineTotal - taxAmount)
          : (quantity * unitPrice - discountAmount).clamp(0, double.infinity);

      final cleanedDescription = _cleanMicroviseDescription(description);
      if (cleanedDescription.isEmpty && quantity == 0 && unitPrice == 0) {
        continue;
      }

      items.add(
        InvoicePdfLineItem(
          rowNo: rowNo++,
          description: cleanedDescription.isEmpty
              ? 'Kalem ${rowNo - 1}'
              : cleanedDescription,
          quantity: quantity,
          unit: unit,
          unitPrice: zeroAmounts ? 0 : unitPrice,
          currency: _normalizeCurrency(currencyHint),
          discountRate: 0,
          discountAmount: zeroAmounts ? 0 : discountAmount,
          taxRate: taxRate,
          taxAmount: zeroAmounts ? 0 : taxAmount,
          lineBaseAmount: zeroAmounts ? 0 : lineBase.toDouble(),
        ),
      );
    }
    return items;
  }

  static String _extractMicroviseItemBlock(String rawText) {
    final headerMatch = RegExp(
      r'KDV\s*\(%\)\s*(?:İndirim\s*)?KDV\s*Tutarı\s*Toplam|'
      r'KDV\s*\(%\)\s*KDV\s*Tutarı\s*Toplam|'
      r'İndirim\s*KDV\s*\(%\)\s*KDV\s*Tutarı\s*Toplam',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawText);
    final endMatch = RegExp(
      r'Ara\s*Toplam\s*:',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawText);

    if (endMatch == null) return '';

    if (headerMatch != null && headerMatch.end < endMatch.start) {
      return rawText.substring(headerMatch.end, endMatch.start);
    }

    // Başlık farklı sıradaysa Mal/Hizmet Listesi sonrası dene.
    final listMatch = RegExp(
      r'Mal\s*/\s*Hizmet\s*Listesi(?:\s*\(devam\))?',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawText);
    if (listMatch == null || listMatch.end >= endMatch.start) return '';
    return rawText.substring(listMatch.end, endMatch.start);
  }

  static String _cleanMicroviseDescription(String raw) {
    var text = raw.trim();
    if (text.isEmpty) return '';
    // Tablo başlığı artıkları.
    text = text
        .replaceFirst(
          RegExp(
            r'^(?:Mal\s*/\s*Hizmet\s*)?(?:Açıklama\s*)?(?:Miktar\s*)?'
            r'(?:Birim\s*Fiyat\s*)?(?:İndirim\s*)?(?:KDV\s*\(%\)\s*)?'
            r'(?:KDV\s*Tutarı\s*)?(?:Toplam\s*)?',
            caseSensitive: false,
          ),
          '',
        )
        .trim();
    // Satır başındaki yalnız birim satırlarını at.
    text = text
        .split(RegExp(r'\s+'))
        .where((token) => !_microviseUnitOnly.hasMatch(token))
        .join(' ')
        .trim();
    return text;
  }

  static double _extractFirstMicroviseLabeledAmount(
    String text,
    List<String> labels,
  ) {
    for (final label in labels) {
      final match = RegExp(
        '${RegExp.escape(label)}\\s*:?\\s*-?\\s*[₺\$€£]?\\s*([0-9\\.,]+)',
        caseSensitive: false,
      ).firstMatch(text);
      if (match != null) return _parseAmount(match.group(1));
    }
    return 0;
  }

  static double _extractMicroviseLabeledAmount(String text, String label) {
    return _extractFirstMicroviseLabeledAmount(text, [label]);
  }

  static String? _extractMicroviseCurrency(String text) {
    final match = RegExp(
      r'PARA\s*BİRİMİ\s*(TRY|USD|EUR|GBP|TL)|'
      r'PARA\s*BIRIMI\s*(TRY|USD|EUR|GBP|TL)',
      caseSensitive: false,
    ).firstMatch(text);
    final value = match?.group(1) ?? match?.group(2);
    if (value != null && value.trim().isNotEmpty) {
      return _normalizeCurrency(value);
    }
    return null;
  }

  static String? _currencyFromMoneySymbol(String text) {
    if (text.contains('₺')) return 'TRY';
    if (text.contains('\$')) return 'USD';
    if (text.contains('€')) return 'EUR';
    if (text.contains('£')) return 'GBP';
    return null;
  }

  static String _extractMicroviseCustomerName(
    String rawText,
    String normalized,
  ) {
    final lineMatch = RegExp(
      r'Müşteri\s*Bilgileri\s*[\r\n]+\s*(.+)',
      caseSensitive: false,
    ).firstMatch(rawText);
    final line = lineMatch?.group(1)?.trim() ?? '';
    if (line.isNotEmpty &&
        !RegExp(r'^(Tel:|E-posta:|Web:|VKN:|FATURA)', caseSensitive: false)
            .hasMatch(line)) {
      return line;
    }

    final patterns = [
      RegExp(
        r'Müşteri\s*Bilgileri\s+(.+?)\s+(?:Tel:|E-posta:|Web:|VKN:|Yabancı|Vergi|Kimlik|FATURA\s*TARİHİ)',
        caseSensitive: false,
      ),
      RegExp(
        r'Musteri\s*Bilgileri\s+(.+?)\s+(?:Tel:|E-posta:|Web:|VKN:|Yabanci|Vergi|Kimlik|FATURA\s*TARIHI)',
        caseSensitive: false,
      ),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(normalized);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) {
        // Adres satırını kes: unvan genelde virgüllü şehirden önce biter.
        final cut = RegExp(
          r'^(.+?(?:LTD\.?|LIMITED|A\.?\s*Ş\.?|AŞ|ŞTİ\.?|CO(?:\s|&)|INC\.?))(?:\s+|$)',
          caseSensitive: false,
        ).firstMatch(value);
        if (cut != null) return cut.group(1)!.trim();
        return value.split(RegExp(r'\s{2,}|\s+(?=[A-ZÇĞİÖŞÜ][a-zçğıöşü])')).first.trim();
      }
    }
    return 'Bilinmeyen Müşteri';
  }

  static DateTime? _extractMicroviseInvoiceDate(String text) {
    final match = RegExp(
      r'FATURA\s*TAR[İI]H[İI]\s*([0-9]{2}[./][0-9]{2}[./][0-9]{4}(?:\s+[0-9]{2}:[0-9]{2})?)',
      caseSensitive: false,
    ).firstMatch(text);
    final raw = match?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final normalized = raw.replaceAll('.', '-');
    for (final pattern in ['dd-MM-yyyy HH:mm', 'dd-MM-yyyy']) {
      try {
        return DateFormat(pattern).parseStrict(normalized);
      } catch (_) {
        // try next
      }
    }
    return null;
  }

  static List<InvoicePdfLineItem> _parseItems(
    String rawText, {
    bool zeroAmounts = false,
  }) {
    final itemBlock = _extractItemBlock(rawText);
    if (itemBlock.isEmpty) return const [];

    final normalizedBlock = _normalizeText(itemBlock);
    final items = <InvoicePdfLineItem>[];
    for (final match in _itemPattern.allMatches(normalizedBlock)) {
      items.add(
        InvoicePdfLineItem(
          rowNo: int.tryParse(match.group(1) ?? '') ?? 0,
          description: (match.group(2) ?? '').trim(),
          quantity: _parseAmount(match.group(3)),
          unit: (match.group(4) ?? '').trim(),
          unitPrice: zeroAmounts ? 0 : _parseAmount(match.group(5)),
          currency: _normalizeCurrency(match.group(6)),
          discountRate: _parsePercent(match.group(7)),
          discountAmount: zeroAmounts ? 0 : _parseAmount(match.group(8)),
          taxRate: _parsePercent(match.group(10)),
          taxAmount: zeroAmounts ? 0 : _parseAmount(match.group(11)),
          lineBaseAmount: zeroAmounts ? 0 : _parseAmount(match.group(13)),
        ),
      );
    }
    return items;
  }

  static String _extractItemBlock(String rawText) {
    final startMatch = RegExp(r'Sıra\s*No', caseSensitive: false, dotAll: true)
        .firstMatch(rawText);
    final endMatch = RegExp(
      r'Mal\s*Hizmet\s*Toplam\s*Tutarı',
      caseSensitive: false,
      dotAll: true,
    ).firstMatch(rawText);
    if (startMatch == null || endMatch == null) return '';
    if (endMatch.start <= startMatch.start) return '';
    return rawText.substring(startMatch.end, endMatch.start);
  }

  static double _extractLabeledAmount(String text, String label) {
    final match = RegExp(
      '${RegExp.escape(label)}\\s*([0-9\\.,]+)\\s*(TL|TRY|USD|EUR|GBP)',
      caseSensitive: false,
    ).firstMatch(text);
    return _parseAmount(match?.group(1));
  }

  static String? _extractCurrency(String text) {
    final labels = [
      'Vergiler Dahil Toplam Tutar',
      'Ödenecek Tutar',
      'Mal Hizmet Toplam Tutarı',
    ];
    for (final label in labels) {
      final match = RegExp(
        '${RegExp.escape(label)}\\s*[0-9\\.,]+\\s*(TL|TRY|USD|EUR|GBP)',
        caseSensitive: false,
      ).firstMatch(text);
      final currency = match?.group(1);
      if (currency != null && currency.trim().isNotEmpty) {
        return _normalizeCurrency(currency);
      }
    }
    return null;
  }

  static String _extractCustomerName(String text) {
    final patterns = [
      RegExp(
        r'ALICININ\s*ADI\s*/\s*ÜNVANI\s*:?\s*(.+?)\s+ADRESİ',
        caseSensitive: false,
      ),
      RegExp(
        r'ALICININADI\s*/\s*ÜNVANI\s*:?\s*(.+?)\s+ADRESİ',
        caseSensitive: false,
      ),
      RegExp(r'^(.+?)\s+ADRESİ\s*:', caseSensitive: false),
    ];
    for (final pattern in patterns) {
      final match = pattern.firstMatch(text);
      final value = match?.group(1)?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return 'Bilinmeyen Müşteri';
  }

  static DateTime? _extractInvoiceDate(String text) {
    final raw = _invoiceDatePattern.firstMatch(text)?.group(1)?.trim();
    if (raw == null || raw.isEmpty) return null;
    try {
      return DateFormat('dd-MM-yyyy HH:mm').parseStrict(raw);
    } catch (_) {
      return null;
    }
  }

  static String _normalizeText(String raw) {
    return raw
        .replaceAll('\u00A0', ' ')
        .replaceAll('Sıra\nNo', 'Sıra No')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAllMapped(RegExp(r'\s+'), (_) => ' ')
        .trim();
  }

  static String detectDocumentMarker(String rawText, {String? fileName}) {
    final normalizedFileName = (fileName ?? '').trim().toUpperCase();
    final fileNameMatch = RegExp(r'\b(ALACAK|IPTAL)\b', caseSensitive: false)
        .firstMatch(normalizedFileName);
    if (fileNameMatch != null) {
      return fileNameMatch.group(1)?.trim().toUpperCase() ?? '';
    }

    final compactFileName = normalizedFileName.replaceAll(RegExp(r'[^A-Z]'), '');
    if (compactFileName.contains('ALACAK')) return 'ALACAK';
    if (compactFileName.contains('IPTAL')) return 'IPTAL';

    final normalized = _normalizeText(rawText).toUpperCase();
    final invoiceNoIndex = normalized.indexOf('FATURA NO');
    final headerEnd = invoiceNoIndex != -1
        ? (invoiceNoIndex + 400).clamp(0, normalized.length)
        : normalized.length.clamp(0, 4000);
    final headerWindow = normalized.substring(0, headerEnd);

    final tokenMatch = RegExp(r'\b(ALACAK|IPTAL)\b', caseSensitive: false)
        .firstMatch(headerWindow);
    if (tokenMatch != null) {
      return tokenMatch.group(1)?.trim().toUpperCase() ?? '';
    }

    final compact = headerWindow.replaceAll(RegExp(r'[^A-Z]'), '');
    final alacakIndex = compact.indexOf('ALACAK');
    final iptalIndex = compact.indexOf('IPTAL');
    if (alacakIndex != -1 && alacakIndex <= 240) return 'ALACAK';
    if (iptalIndex != -1 && iptalIndex <= 240) return 'IPTAL';
    return '';
  }

  static String _normalizeCurrency(String? value) {
    final text = (value ?? '').trim().toUpperCase();
    if (text == 'TL') return 'TRY';
    return text.isEmpty ? 'TRY' : text;
  }

  static double _parsePercent(String? raw) => _parseAmount(raw);

  static double _parseMoney(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty || text == '-') return 0;
    final stripped = text.replaceAll(RegExp(r'[₺\$€£]'), '');
    return _parseAmount(stripped);
  }

  static double _parseAmount(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 0;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }
}
