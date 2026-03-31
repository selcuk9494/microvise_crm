import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api/api_client.dart';
import '../work_orders/currency_service.dart';
import 'invoice_model.dart';

// Fatura listesi provider
final invoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, InvoiceFilter>((ref, filter) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];

  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'invoices_list',
      if (filter.invoiceType != null) 'invoiceType': filter.invoiceType!,
      if (filter.status != null) 'status': filter.status!,
      if (filter.customerId != null) 'customerId': filter.customerId!,
      if (filter.startDate != null)
        'startDate': filter.startDate!.toIso8601String().substring(0, 10),
      if (filter.endDate != null)
        'endDate': filter.endDate!.toIso8601String().substring(0, 10),
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Invoice.fromJson)
      .toList(growable: false);
});

// Tek fatura detay
final invoiceDetailProvider = FutureProvider.autoDispose.family<Invoice?, String>((ref, invoiceId) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return null;
  final row = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'invoice_detail', 'invoiceId': invoiceId},
  );
  if (row.isEmpty) return null;
  return Invoice.fromJson(row);
});

// Cari hesap bakiyeleri
final accountBalancesProvider = FutureProvider.autoDispose<List<AccountBalance>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'account_balances'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(AccountBalance.fromJson)
      .toList(growable: false);
});

// Cari hesap işlemleri (tahsilat/ödeme)
final transactionsProvider = FutureProvider.autoDispose.family<List<Transaction>, TransactionFilter>((ref, filter) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'transactions_list',
      if (filter.customerId != null) 'customerId': filter.customerId!,
      if (filter.transactionType != null)
        'transactionType': filter.transactionType!,
      if (filter.invoiceId != null) 'invoiceId': filter.invoiceId!,
      if (filter.startDate != null)
        'startDate': filter.startDate!.toIso8601String().substring(0, 10),
      if (filter.endDate != null)
        'endDate': filter.endDate!.toIso8601String().substring(0, 10),
      'includePassive': filter.includePassive.toString(),
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Transaction.fromJson)
      .toList(growable: false);
});

final exchangeRatesProvider =
    FutureProvider.autoDispose.family<Map<String, ExchangeRate>, DateTime?>((ref, date) async {
      final targetDate = DateTime(
        (date ?? DateTime.now()).year,
        (date ?? DateTime.now()).month,
        (date ?? DateTime.now()).day,
      );

      return _fallbackRates(targetDate);
    });

Future<Map<String, ExchangeRate>> _fallbackRates(DateTime date) async {
  final fetched = await CurrencyService.getExchangeRates();
  return {
    'TRY': ExchangeRate(
      currency: 'TRY',
      rateToTry: 1.0,
      effectiveDate: date,
      source: 'fallback',
      isManual: false,
      createdAt: DateTime.now(),
    ),
    for (final entry in fetched.entries)
      entry.key: ExchangeRate(
        currency: entry.key,
        rateToTry: entry.value,
        effectiveDate: date,
        source: 'fallback',
        isManual: false,
        createdAt: DateTime.now(),
      ),
  };
}

// Ürün/Hizmet listesi
final productsProvider = FutureProvider.autoDispose.family<List<Product>, String?>((ref, category) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'products_list',
      if ((category ?? '').trim().isNotEmpty) 'category': category!.trim(),
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Product.fromJson)
      .toList(growable: false);
});

// Stok seviyeleri
final stockLevelsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'stock_levels'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map((e) {
        return Product(
          id: e['product_id'].toString(),
          code: e['code']?.toString(),
          name: e['name']?.toString() ?? '',
          category: e['category']?.toString(),
          minStock: (e['min_stock'] as num?)?.toDouble() ?? 0,
          currentStock: (e['current_stock'] as num?)?.toDouble() ?? 0,
          trackStock: true,
        );
      })
      .toList(growable: false);
});

// Müşteri açık faturaları
final customerOpenInvoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, String>((ref, customerId) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'customer_open_invoices', 'customerId': customerId},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Invoice.fromJson)
      .toList(growable: false);
});

// Filter sınıfları
class InvoiceFilter {
  final String? invoiceType;
  final String? status;
  final String? customerId;
  final DateTime? startDate;
  final DateTime? endDate;

  const InvoiceFilter({
    this.invoiceType,
    this.status,
    this.customerId,
    this.startDate,
    this.endDate,
  });

  InvoiceFilter copyWith({
    String? invoiceType,
    String? status,
    String? customerId,
    DateTime? startDate,
    DateTime? endDate,
    bool clearInvoiceType = false,
    bool clearStatus = false,
    bool clearCustomerId = false,
  }) {
    return InvoiceFilter(
      invoiceType: clearInvoiceType ? null : (invoiceType ?? this.invoiceType),
      status: clearStatus ? null : (status ?? this.status),
      customerId: clearCustomerId ? null : (customerId ?? this.customerId),
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
    );
  }
}

class TransactionFilter {
  final String? customerId;
  final String? transactionType;
  final String? invoiceId;
  final DateTime? startDate;
  final DateTime? endDate;
  final bool includePassive;

  const TransactionFilter({
    this.customerId,
    this.transactionType,
    this.invoiceId,
    this.startDate,
    this.endDate,
    this.includePassive = false,
  });
}

// Fatura numarası üretimi
final invoiceNumberProvider = FutureProvider.autoDispose.family<String, String>((ref, invoiceType) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return '';
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'invoice_number', 'invoiceType': invoiceType},
  );
  return (response['value'] ?? '').toString();
});
