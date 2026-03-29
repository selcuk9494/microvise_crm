import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/supabase/supabase_providers.dart';
import '../work_orders/currency_service.dart';
import 'invoice_model.dart';

// Fatura listesi provider
final invoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, InvoiceFilter>((ref, filter) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  var query = client
      .from('invoices')
      .select('*, customers(name), invoice_items(*)')
      .eq('is_active', true);

  if (filter.invoiceType != null) {
    query = query.eq('invoice_type', filter.invoiceType!);
  }
  if (filter.status != null) {
    query = query.eq('status', filter.status!);
  }
  if (filter.customerId != null) {
    query = query.eq('customer_id', filter.customerId!);
  }
  if (filter.startDate != null) {
    query = query.gte('invoice_date', filter.startDate!.toIso8601String().substring(0, 10));
  }
  if (filter.endDate != null) {
    query = query.lte('invoice_date', filter.endDate!.toIso8601String().substring(0, 10));
  }

  final rows = await query.order('invoice_date', ascending: false).limit(500);
  return (rows as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
});

// Tek fatura detay
final invoiceDetailProvider = FutureProvider.autoDispose.family<Invoice?, String>((ref, invoiceId) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return null;

  final row = await client
      .from('invoices')
      .select('*, customers(name), invoice_items(*)')
      .eq('id', invoiceId)
      .maybeSingle();

  if (row == null) return null;
  return Invoice.fromJson(row);
});

// Cari hesap bakiyeleri
final accountBalancesProvider = FutureProvider.autoDispose<List<AccountBalance>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client.from('account_balances').select().order('name');
  return (rows as List).map((e) => AccountBalance.fromJson(e as Map<String, dynamic>)).toList();
});

// Cari hesap işlemleri (tahsilat/ödeme)
final transactionsProvider = FutureProvider.autoDispose.family<List<Transaction>, TransactionFilter>((ref, filter) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  var query = client
      .from('transactions')
      .select('*, customers(name), invoices(invoice_number)');

  if (!filter.includePassive) {
    query = query.eq('is_active', true);
  }

  if (filter.customerId != null) {
    query = query.eq('customer_id', filter.customerId!);
  }
  if (filter.transactionType != null) {
    query = query.eq('transaction_type', filter.transactionType!);
  }
  if (filter.invoiceId != null) {
    query = query.eq('invoice_id', filter.invoiceId!);
  }
  if (filter.startDate != null) {
    query = query.gte(
      'transaction_date',
      filter.startDate!.toIso8601String().substring(0, 10),
    );
  }
  if (filter.endDate != null) {
    query = query.lte(
      'transaction_date',
      filter.endDate!.toIso8601String().substring(0, 10),
    );
  }

  final rows = await query.order('transaction_date', ascending: false).limit(500);
  return (rows as List).map((e) => Transaction.fromJson(e as Map<String, dynamic>)).toList();
});

final exchangeRatesProvider =
    FutureProvider.autoDispose.family<Map<String, ExchangeRate>, DateTime?>((ref, date) async {
      final client = ref.read(supabaseClientProvider);
      final targetDate = DateTime(
        (date ?? DateTime.now()).year,
        (date ?? DateTime.now()).month,
        (date ?? DateTime.now()).day,
      );

      if (client == null) {
        return _fallbackRates(targetDate);
      }

      try {
        final rows = await client
            .from('exchange_rates')
            .select('currency,rate_to_try,effective_date,source,is_manual,created_at')
            .lte('effective_date', targetDate.toIso8601String().substring(0, 10))
            .order('effective_date', ascending: false)
            .order('created_at', ascending: false)
            .limit(64);

        final map = <String, ExchangeRate>{};
        for (final row in rows as List) {
          final rate = ExchangeRate.fromJson(row as Map<String, dynamic>);
          map.putIfAbsent(rate.currency, () => rate);
        }
        if (map.isNotEmpty) {
          map.putIfAbsent(
            'TRY',
            () => ExchangeRate(
              currency: 'TRY',
              rateToTry: 1.0,
              effectiveDate: targetDate,
              source: 'system',
              isManual: false,
              createdAt: DateTime.now(),
            ),
          );
          return map;
        }
      } catch (_) {
        // Fallback to network/default rates below.
      }

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
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  var query = client.from('products').select().eq('is_active', true);
  if (category != null && category.isNotEmpty) {
    query = query.eq('category', category);
  }

  final rows = await query.order('name').limit(500);
  return (rows as List).map((e) => Product.fromJson(e as Map<String, dynamic>)).toList();
});

// Stok seviyeleri
final stockLevelsProvider = FutureProvider.autoDispose<List<Product>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client.from('stock_levels').select();
  return (rows as List).map((e) {
    return Product(
      id: e['product_id'].toString(),
      code: e['code']?.toString(),
      name: e['name']?.toString() ?? '',
      category: e['category']?.toString(),
      minStock: (e['min_stock'] as num?)?.toDouble() ?? 0,
      currentStock: (e['current_stock'] as num?)?.toDouble() ?? 0,
      trackStock: true,
    );
  }).toList();
});

// Müşteri açık faturaları
final customerOpenInvoicesProvider = FutureProvider.autoDispose.family<List<Invoice>, String>((ref, customerId) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client
      .from('invoices')
      .select('*, customers(name)')
      .eq('customer_id', customerId)
      .eq('is_active', true)
      .inFilter('status', ['open', 'partial'])
      .order('invoice_date', ascending: false);

  return (rows as List).map((e) => Invoice.fromJson(e as Map<String, dynamic>)).toList();
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
  final client = ref.read(supabaseClientProvider);
  if (client == null) return '';

  final result = await client.rpc('generate_invoice_number', params: {'p_invoice_type': invoiceType});
  return result?.toString() ?? '';
});
