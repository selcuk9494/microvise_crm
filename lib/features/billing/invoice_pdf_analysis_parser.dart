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
    r'Fatura\s*No\s*:\s*([A-Z0-9./-]+?)(?=\s*Fatura\s*Tarihi|\s*Damga|\s*Belge|$)',
    caseSensitive: false,
  );
  static final RegExp _invoiceDatePattern = RegExp(
    r'Fatura\s*Tarihi\s*:\s*([0-9]{2}-[0-9]{2}-[0-9]{4}\s+[0-9]{2}:[0-9]{2})',
    caseSensitive: false,
  );

  static Future<InvoicePdfAnalysisEntry?> parse({
    required Uint8List bytes,
    required String fileName,
  }) async {
    final document = PdfDocument(inputBytes: bytes);
    final text = PdfTextExtractor(document).extractText();
    document.dispose();

    final normalized = _normalizeText(text);
    final leadingMarker = detectDocumentMarker(
      text,
      fileName: fileName,
    );
    if (leadingMarker == 'ALACAK') return null;

    final isCancelled = leadingMarker == 'IPTAL';
    final items = _parseItems(text, zeroAmounts: isCancelled);
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
      subtotal: isCancelled ? 0 : subtotal,
      taxTotal: isCancelled ? 0 : taxTotal,
      grandTotal: isCancelled ? 0 : grandTotal,
      items: items,
      rawText: text,
    );
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

  static double _parseAmount(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return 0;
    final normalized = text.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalized) ?? 0;
  }
}
