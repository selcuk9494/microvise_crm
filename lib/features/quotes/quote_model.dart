import 'dart:convert';

import 'package:intl/intl.dart';

import '../../core/format/app_date_time.dart';

/// Teklif para birimi etiketleri ve tutar formatlama.
class QuoteMoney {
  QuoteMoney._();

  static const currencies = ['TRY', 'USD', 'EUR', 'GBP'];

  static String label(String code) {
    switch (code.toUpperCase()) {
      case 'TRY':
        return 'TL';
      case 'USD':
        return 'USD';
      case 'EUR':
        return 'EUR';
      case 'GBP':
        return 'GBP';
      default:
        return code.toUpperCase();
    }
  }

  static String symbol(String currency) {
    switch (currency.toUpperCase()) {
      case 'TRY':
        return '₺';
      case 'USD':
        return '\$';
      case 'EUR':
        return '€';
      case 'GBP':
        return '£';
      default:
        return '$currency ';
    }
  }

  static NumberFormat format(String currency) {
    return NumberFormat.currency(
      locale: 'tr_TR',
      symbol: symbol(currency),
    );
  }

  static String formatAmount(double amount, String currency) =>
      format(currency).format(amount);
}

double _n(dynamic value, {double fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? fallback;
}

int _i(dynamic value, {int fallback = 0}) {
  if (value == null) return fallback;
  if (value is num) return value.toInt();
  return int.tryParse(value.toString()) ?? fallback;
}

class QuoteItem {
  const QuoteItem({
    required this.id,
    required this.quoteId,
    this.productId,
    this.imageUrl,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.taxRate,
    required this.taxAmount,
    required this.discountRate,
    required this.discountAmount,
    required this.lineTotal,
    required this.sortOrder,
  });

  final String id;
  final String quoteId;
  final String? productId;
  final String? imageUrl;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double taxRate;
  final double taxAmount;
  final double discountRate;
  final double discountAmount;
  final double lineTotal;
  final int sortOrder;

  factory QuoteItem.fromJson(Map<String, dynamic> json) {
    final productRaw = json['products'];
    final imageFromProduct = productRaw is Map
        ? productRaw['image_url']?.toString()
        : null;
    return QuoteItem(
      id: json['id']?.toString() ?? '',
      quoteId: json['quote_id']?.toString() ?? '',
      productId: _nullableId(json['product_id']),
      imageUrl: (imageFromProduct ?? '').trim().isEmpty
          ? null
          : imageFromProduct!.trim(),
      description: json['description']?.toString() ?? '',
      quantity: _n(json['quantity'], fallback: 1),
      unit: json['unit']?.toString() ?? 'Adet',
      unitPrice: _n(json['unit_price']),
      taxRate: _n(json['tax_rate'], fallback: 20),
      taxAmount: _n(json['tax_amount']),
      discountRate: _n(json['discount_rate']),
      discountAmount: _n(json['discount_amount']),
      lineTotal: _n(json['line_total']),
      sortOrder: _i(json['sort_order']),
    );
  }

  static String? _nullableId(dynamic value) {
    final raw = value?.toString().trim();
    if (raw == null || raw.isEmpty) return null;
    return raw;
  }

  static List<QuoteItem> parseItems(dynamic raw) {
    if (raw == null) return const [];
    dynamic decoded = raw;
    if (raw is String && raw.trim().isNotEmpty) {
      try {
        decoded = jsonDecode(raw);
      } catch (_) {
        return const [];
      }
    }
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => QuoteItem.fromJson(Map<String, dynamic>.from(item)))
        .toList(growable: false);
  }

  Map<String, dynamic> toInsertJson(String quoteId, int sortOrder) => {
    'quote_id': quoteId,
    if (productId != null && productId!.isNotEmpty) 'product_id': productId,
    'description': description,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'tax_rate': taxRate,
    'tax_amount': taxAmount,
    'discount_rate': discountRate,
    'discount_amount': discountAmount,
    'line_total': lineTotal,
    'sort_order': sortOrder,
  };
}

class Quote {
  const Quote({
    required this.id,
    required this.quoteNumber,
    required this.customerId,
    this.customerName,
    required this.quoteDate,
    this.validUntil,
    required this.currency,
    required this.exchangeRate,
    required this.pricesIncludeVat,
    required this.subtotal,
    required this.taxTotal,
    required this.discountTotal,
    required this.grandTotal,
    required this.status,
    this.notes,
    this.convertedInvoiceId,
    required this.isActive,
    required this.createdAt,
    required this.items,
  });

  final String id;
  final String quoteNumber;
  final String customerId;
  final String? customerName;
  final DateTime quoteDate;
  final DateTime? validUntil;
  final String currency;
  final double exchangeRate;
  final bool pricesIncludeVat;
  final double subtotal;
  final double taxTotal;
  final double discountTotal;
  final double grandTotal;
  final String status;
  final String? notes;
  final String? convertedInvoiceId;
  final bool isActive;
  final DateTime? createdAt;
  final List<QuoteItem> items;

  bool get isConverted => status == 'converted';
  bool get canEdit => isActive && !isConverted;
  bool get canApprove => isActive && !isConverted && status != 'rejected';

  factory Quote.fromJson(Map<String, dynamic> json) {
    final customerRaw = json['customers'];
    final customerName = customerRaw is Map
        ? customerRaw['name']?.toString()
        : json['customer_name']?.toString();

    final items = QuoteItem.parseItems(json['quote_items']);

    return Quote(
      id: json['id']?.toString() ?? '',
      quoteNumber: json['quote_number']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      customerName: customerName,
      quoteDate: parseAppDateTime(json['quote_date']?.toString()) ?? DateTime.now(),
      validUntil: parseAppDateTime(json['valid_until']?.toString()),
      currency: json['currency']?.toString().trim().toUpperCase().isNotEmpty == true
          ? json['currency'].toString().trim().toUpperCase()
          : 'TRY',
      exchangeRate: _n(json['exchange_rate'], fallback: 1),
      pricesIncludeVat: json['prices_include_vat'] == true,
      subtotal: _n(json['subtotal']),
      taxTotal: _n(json['tax_total']),
      discountTotal: _n(json['discount_total']),
      grandTotal: _n(json['grand_total']),
      status: json['status']?.toString() ?? 'draft',
      notes: json['notes']?.toString(),
      convertedInvoiceId: json['converted_invoice_id']?.toString(),
      isActive: json['is_active'] != false,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      items: items,
    );
  }

  static String statusLabel(String status) => switch (status) {
    'sent' => 'Gönderildi',
    'accepted' => 'Onaylandı',
    'rejected' => 'Reddedildi',
    'expired' => 'Süresi doldu',
    'converted' => 'Faturaya dönüştürüldü',
    _ => 'Taslak',
  };
}

class QuoteFilter {
  const QuoteFilter({
    this.status,
    this.activeFilter = 'active',
    this.customerId,
  });

  final String? status;
  final String activeFilter;
  final String? customerId;
}
