import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/format/app_date_time.dart';
import '../../core/supabase/supabase_providers.dart';

final dashboardMetricsProvider = FutureProvider<DashboardMetrics>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson('/dashboard/summary');
    return DashboardMetrics(
      totalCustomers: _intValue(row['total_customers']),
      openWorkOrders: _intValue(row['open_work_orders']),
      inProgressWorkOrders: _intValue(row['in_progress_work_orders']),
      completedWorkOrders: _intValue(row['completed_work_orders']),
      todayWorkOrders: _intValue(row['today_work_orders']),
      expiringSoon: _intValue(row['expiring_soon']),
      totalProducts: _intValue(row['total_products']),
      lowStockProducts: _intValue(row['low_stock_products']),
      revenue: _doubleValue(row['revenue']),
      lastMonthRevenue: _doubleValue(row['last_month_revenue']),
      todayCollections: _doubleValue(row['today_collections']),
      totalReceivable: _doubleValue(row['total_receivable']),
      totalPayable: _doubleValue(row['total_payable']),
      openInvoices: _intValue(row['open_invoices']),
      totalInvoiceAmount: _doubleValue(row['total_invoice_amount']),
      invoiceQueuePending: _intValue(row['invoice_queue_pending']),
    );
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return DashboardMetrics.zero();

  final snapshot = await _fetchDashboardSnapshot(client);
  if (snapshot != null) {
    return snapshot;
  }

  final totalCustomers = await _count(client, 'customers', filters: {
    'is_active': true,
  });

  final openWorkOrders = await _count(client, 'work_orders', filters: {
    'status': 'open',
    'is_active': true,
  });

  final inProgressWorkOrders = await _count(client, 'work_orders', filters: {
    'status': 'in_progress',
    'is_active': true,
  });

  final completedWorkOrders = await _count(client, 'work_orders', filters: {
    'status': 'done',
    'is_active': true,
  });

  final todayWorkOrders = await _count(client, 'work_orders', filters: {
    'scheduled_date': appNow().toIso8601String().substring(0, 10),
    'is_active': true,
  });

  final expiring = await _count(client, 'licenses', filters: {
    'is_active': true,
  }, extra: (q) {
    final now = appNow();
    final in30 = now.add(const Duration(days: 30));
    return q
        .lte('expires_at', in30.toIso8601String())
        .gte('expires_at', now.toIso8601String());
  });

  final expiringLines = await _count(client, 'lines', filters: {
    'is_active': true,
  }, extra: (q) {
    final now = appNow();
    final in30 = now.add(const Duration(days: 30));
    return q
        .lte('expires_at', in30.toIso8601String())
        .gte('expires_at', now.toIso8601String());
  });

  final totalProducts = await _count(client, 'products', filters: {
    'is_active': true,
  });

  final lowStockProducts = await _lowStockCount(client);
  final receivablePayable = await _accountingSnapshot(client);
  final revenue = await _sumTransactions(client, type: 'collection');
  final lastMonthRevenue = await _sumTransactions(
    client,
    type: 'collection',
    lastMonth: true,
  );
  final todayCollections = await _sumTodayCollections(client);

  final openInvoices = await _count(client, 'invoices', filters: {
    'is_active': true,
  }, extra: (q) {
    return q.inFilter('status', ['open', 'partial']);
  });

  final totalInvoiceAmount = await _sumOutstandingInvoices(client);

  int invoiceQueuePending = 0;
  try {
    invoiceQueuePending = await _count(client, 'invoice_items', filters: {
      'status': 'pending',
      'is_active': true,
    });
  } catch (_) {
    invoiceQueuePending = 0;
  }

  return DashboardMetrics(
    totalCustomers: totalCustomers,
    openWorkOrders: openWorkOrders,
    inProgressWorkOrders: inProgressWorkOrders,
    completedWorkOrders: completedWorkOrders,
    todayWorkOrders: todayWorkOrders,
    expiringSoon: expiring + expiringLines,
    totalProducts: totalProducts,
    lowStockProducts: lowStockProducts,
    revenue: revenue,
    lastMonthRevenue: lastMonthRevenue,
    todayCollections: todayCollections,
    totalReceivable: receivablePayable.receivable,
    totalPayable: receivablePayable.payable,
    openInvoices: openInvoices,
    totalInvoiceAmount: totalInvoiceAmount,
    invoiceQueuePending: invoiceQueuePending,
  );
});

final dashboardRevenueSeriesProvider =
    FutureProvider<List<DashboardDailyPoint>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final now = appNow();
  final from = now.subtract(const Duration(days: 14));
  final rows = await client
      .from('transactions')
      .select('transaction_date,amount,transaction_type,is_active')
      .gte('transaction_date', from.toIso8601String().substring(0, 10))
      .eq('transaction_type', 'collection')
      .eq('is_active', true);

  final buckets = <DateTime, double>{};
  for (final row in (rows as List)) {
    final paidAtRaw = row['transaction_date'];
    final amountRaw = row['amount'];
    if (paidAtRaw == null || amountRaw == null) continue;
    final paidAt = parseAppDateTime(paidAtRaw.toString());
    if (paidAt == null) continue;
    final key = normalizeAppDate(paidAt);
    final amount = amountRaw is num ? amountRaw.toDouble() : double.tryParse(amountRaw.toString());
    if (amount == null) continue;
    buckets.update(key, (v) => v + amount, ifAbsent: () => amount);
  }

  final points = <DashboardDailyPoint>[];
  for (int i = 13; i >= 0; i--) {
    final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    points.add(DashboardDailyPoint(day: day, value: buckets[day] ?? 0));
  }
  return points;
});

final dashboardActivitiesProvider =
    FutureProvider<List<DashboardActivity>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final workRows = await client
      .from('work_orders')
      .select('id,title,created_at,customers(name)')
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(6);

  final serviceRows = await client
      .from('service_records')
      .select('id,title,created_at,customers(name)')
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(6);

  final activities = <DashboardActivity>[
    for (final row in (workRows as List))
      DashboardActivity.fromJoinRow(
        type: DashboardActivityType.workOrder,
        row: row as Map<String, dynamic>,
      ),
    for (final row in (serviceRows as List))
      DashboardActivity.fromJoinRow(
        type: DashboardActivityType.service,
        row: row as Map<String, dynamic>,
      ),
  ];

  activities.sort((a, b) => b.createdAt.compareTo(a.createdAt));
  return activities.take(8).toList(growable: false);
});

Future<int> _count(
  SupabaseClient client,
  String table, {
  Map<String, Object?> filters = const {},
  dynamic Function(dynamic q)? extra,
}) async {
  dynamic q = client.from(table).count();
  for (final entry in filters.entries) {
    final value = entry.value;
    if (value == null) continue;
    q = q.eq(entry.key, value);
  }
  final finalQ = extra == null ? q : extra(q);
  final response = await finalQ;
  return response as int;
}

Future<double> _sumTransactions(
  SupabaseClient client, {
  required String type,
  bool lastMonth = false,
}) async {
  final now = appNow();
  final from = lastMonth
      ? DateTime(now.year, now.month - 1, 1)
      : DateTime(now.year, now.month, 1);
  final to = lastMonth
      ? DateTime(now.year, now.month, 1)
      : null;
  var query = client
      .from('transactions')
      .select('amount')
      .eq('transaction_type', type)
      .eq('is_active', true)
      .gte('transaction_date', from.toIso8601String().substring(0, 10));
  if (to != null) {
    query = query.lt('transaction_date', to.toIso8601String().substring(0, 10));
  }
  final rows = await query;

  double sum = 0;
  for (final row in (rows as List)) {
    final amount = row['amount'];
    if (amount is num) sum += amount.toDouble();
  }
  return sum;
}

Future<double> _sumTodayCollections(SupabaseClient client) async {
  final now = appNow();
  final rows = await client
      .from('transactions')
      .select('amount')
      .eq('transaction_type', 'collection')
      .eq('transaction_date', DateTime(now.year, now.month, now.day).toIso8601String().substring(0, 10))
      .eq('is_active', true);

  double sum = 0;
  for (final row in (rows as List)) {
    final amount = row['amount'];
    if (amount is num) sum += amount.toDouble();
  }
  return sum;
}

Future<int> _lowStockCount(SupabaseClient client) async {
  try {
    final rows = await client
        .from('stock_levels')
        .select('product_id,current_stock,min_stock');

    int count = 0;
    for (final row in (rows as List)) {
      final current = (row['current_stock'] as num?)?.toInt() ?? 0;
      final min = (row['min_stock'] as num?)?.toInt() ?? 0;
      if (current <= min) count++;
    }
    return count;
  } catch (_) {
    return 0;
  }
}

Future<double> _sumOutstandingInvoices(SupabaseClient client) async {
  try {
    final rows = await client
        .from('invoices')
        .select('grand_total,paid_amount,status,is_active')
        .eq('is_active', true)
        .inFilter('status', ['open', 'partial']);

    double sum = 0;
    for (final row in (rows as List)) {
      final total = (row['grand_total'] as num?)?.toDouble() ?? 0;
      final paid = (row['paid_amount'] as num?)?.toDouble() ?? 0;
      sum += (total - paid);
    }
    return sum;
  } catch (_) {
    return 0;
  }
}

Future<({double receivable, double payable})> _accountingSnapshot(
  SupabaseClient client,
) async {
  try {
    final rows = await client.from('account_balances').select('balance');
    double receivable = 0;
    double payable = 0;
    for (final row in rows as List) {
      final balance = (row['balance'] as num?)?.toDouble() ?? 0;
      if (balance > 0) {
        receivable += balance;
      } else if (balance < 0) {
        payable += balance.abs();
      }
    }
    return (receivable: receivable, payable: payable);
  } catch (_) {
    return (receivable: 0.0, payable: 0.0);
  }
}

Future<DashboardMetrics?> _fetchDashboardSnapshot(SupabaseClient client) async {
  try {
    final rows = await client.rpc('dashboard_snapshot');
    if (rows is! List || rows.isEmpty) return null;
    final row = rows.first as Map<String, dynamic>;
    return DashboardMetrics(
      totalCustomers: _intValue(row['total_customers']),
      openWorkOrders: _intValue(row['open_work_orders']),
      inProgressWorkOrders: _intValue(row['in_progress_work_orders']),
      completedWorkOrders: _intValue(row['completed_work_orders']),
      todayWorkOrders: _intValue(row['today_work_orders']),
      expiringSoon: _intValue(row['expiring_soon']),
      totalProducts: _intValue(row['total_products']),
      lowStockProducts: _intValue(row['low_stock_products']),
      revenue: _doubleValue(row['revenue']),
      lastMonthRevenue: _doubleValue(row['last_month_revenue']),
      todayCollections: _doubleValue(row['today_collections']),
      totalReceivable: _doubleValue(row['total_receivable']),
      totalPayable: _doubleValue(row['total_payable']),
      openInvoices: _intValue(row['open_invoices']),
      totalInvoiceAmount: _doubleValue(row['total_invoice_amount']),
      invoiceQueuePending: _intValue(row['invoice_queue_pending']),
    );
  } catch (_) {
    return null;
  }
}

int _intValue(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double _doubleValue(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalCustomers,
    required this.openWorkOrders,
    required this.inProgressWorkOrders,
    required this.completedWorkOrders,
    required this.todayWorkOrders,
    required this.expiringSoon,
    required this.totalProducts,
    required this.lowStockProducts,
    required this.revenue,
    required this.lastMonthRevenue,
    required this.todayCollections,
    required this.totalReceivable,
    required this.totalPayable,
    required this.openInvoices,
    required this.totalInvoiceAmount,
    required this.invoiceQueuePending,
  });

  final int totalCustomers;
  final int openWorkOrders;
  final int inProgressWorkOrders;
  final int completedWorkOrders;
  final int todayWorkOrders;
  final int expiringSoon;
  final int totalProducts;
  final int lowStockProducts;
  final double revenue;
  final double lastMonthRevenue;
  final double todayCollections;
  final double totalReceivable;
  final double totalPayable;
  final int openInvoices;
  final double totalInvoiceAmount;
  final int invoiceQueuePending;

  double get revenueChangePercent {
    if (lastMonthRevenue == 0) return revenue > 0 ? 100 : 0;
    return ((revenue - lastMonthRevenue) / lastMonthRevenue) * 100;
  }

  factory DashboardMetrics.zero() => const DashboardMetrics(
        totalCustomers: 0,
        openWorkOrders: 0,
        inProgressWorkOrders: 0,
        completedWorkOrders: 0,
        todayWorkOrders: 0,
        expiringSoon: 0,
        totalProducts: 0,
        lowStockProducts: 0,
        revenue: 0,
        lastMonthRevenue: 0,
        todayCollections: 0,
        totalReceivable: 0,
        totalPayable: 0,
        openInvoices: 0,
        totalInvoiceAmount: 0,
        invoiceQueuePending: 0,
      );
}

class DashboardDailyPoint {
  const DashboardDailyPoint({required this.day, required this.value});

  final DateTime day;
  final double value;
}

enum DashboardActivityType { workOrder, service }

class DashboardActivity {
  const DashboardActivity({
    required this.type,
    required this.title,
    required this.customerName,
    required this.createdAt,
  });

  final DashboardActivityType type;
  final String title;
  final String? customerName;
  final DateTime createdAt;

  factory DashboardActivity.fromJoinRow({
    required DashboardActivityType type,
    required Map<String, dynamic> row,
  }) {
    final customers = row['customers'] as Map<String, dynamic>?;
    return DashboardActivity(
      type: type,
      title: (row['title'] ?? '').toString(),
      customerName: customers?['name']?.toString(),
      createdAt:
          parseAppDateTime(row['created_at']?.toString()) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
