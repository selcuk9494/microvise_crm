import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/supabase/supabase_providers.dart';

final dashboardMetricsProvider = FutureProvider<DashboardMetrics>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return DashboardMetrics.zero();

  final totalCustomers = await _count(client, 'customers', filters: {
    'is_active': true,
  });

  final openWorkOrders = await _count(client, 'work_orders', filters: {
    'status': 'open',
    'is_active': true,
  });

  final todayWorkOrders = await _count(client, 'work_orders', filters: {
    'scheduled_date': DateTime.now().toIso8601String().substring(0, 10),
    'is_active': true,
  });

  final expiring = await _count(client, 'licenses', filters: {
    'is_active': true,
  }, extra: (q) {
    final now = DateTime.now();
    final in30 = now.add(const Duration(days: 30));
    return q
        .lte('expires_at', in30.toIso8601String())
        .gte('expires_at', now.toIso8601String());
  });

  final revenue = await _sumPaymentsThisMonth(client);

  return DashboardMetrics(
    totalCustomers: totalCustomers,
    openWorkOrders: openWorkOrders,
    todayWorkOrders: todayWorkOrders,
    expiringSoon: expiring,
    revenue: revenue,
  );
});

final dashboardRevenueSeriesProvider =
    FutureProvider<List<DashboardDailyPoint>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final now = DateTime.now();
  final from = now.subtract(const Duration(days: 14));
  final rows = await client
      .from('payments')
      .select('paid_at,amount')
      .gte('paid_at', from.toIso8601String())
      .eq('is_active', true);

  final buckets = <DateTime, double>{};
  for (final row in (rows as List)) {
    final paidAtRaw = row['paid_at'];
    final amountRaw = row['amount'];
    if (paidAtRaw == null || amountRaw == null) continue;
    final paidAt = DateTime.tryParse(paidAtRaw.toString());
    if (paidAt == null) continue;
    final key = DateTime(paidAt.year, paidAt.month, paidAt.day);
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
  PostgrestFilterBuilder<dynamic> Function(PostgrestFilterBuilder<dynamic> q)?
      extra,
}) async {
  PostgrestFilterBuilder<dynamic> q = client.from(table).select('id');
  for (final entry in filters.entries) {
    final value = entry.value;
    if (value == null) continue;
    q = q.eq(entry.key, value);
  }
  final finalQ = extra == null ? q : extra(q);
  final response = await finalQ;
  return (response as List).length;
}

Future<double> _sumPaymentsThisMonth(SupabaseClient client) async {
  final now = DateTime.now();
  final from = DateTime(now.year, now.month, 1);
  final rows = await client
      .from('payments')
      .select('amount')
      .gte('paid_at', from.toIso8601String())
      .eq('is_active', true);

  double sum = 0;
  for (final row in (rows as List)) {
    final amount = row['amount'];
    if (amount is num) sum += amount.toDouble();
  }
  return sum;
}

class DashboardMetrics {
  const DashboardMetrics({
    required this.totalCustomers,
    required this.openWorkOrders,
    required this.todayWorkOrders,
    required this.expiringSoon,
    required this.revenue,
  });

  final int totalCustomers;
  final int openWorkOrders;
  final int todayWorkOrders;
  final int expiringSoon;
  final double revenue;

  factory DashboardMetrics.zero() => const DashboardMetrics(
        totalCustomers: 0,
        openWorkOrders: 0,
        todayWorkOrders: 0,
        expiringSoon: 0,
        revenue: 0,
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
      createdAt: DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}
