import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final reportsFiltersProvider =
    NotifierProvider<ReportsFiltersNotifier, ReportsFilters>(
  ReportsFiltersNotifier.new,
);

class ReportsFiltersNotifier extends Notifier<ReportsFilters> {
  @override
  ReportsFilters build() => ReportsFilters.last30Days();

  void setPreset(ReportsPreset preset) {
    state = state.copyWith(preset: preset);
  }

  void setUser(String? userId) {
    state = state.copyWith(userId: userId?.trim().isEmpty ?? true ? null : userId);
  }
}

enum ReportsPreset { last7Days, last30Days, thisMonth }

class ReportsFilters {
  const ReportsFilters({required this.preset, required this.userId});

  final ReportsPreset preset;
  final String? userId;

  factory ReportsFilters.last30Days() =>
      const ReportsFilters(preset: ReportsPreset.last30Days, userId: null);

  ReportsFilters copyWith({ReportsPreset? preset, String? userId}) {
    return ReportsFilters(preset: preset ?? this.preset, userId: userId);
  }

  DateTime get from {
    final now = DateTime.now();
    return switch (preset) {
      ReportsPreset.last7Days => now.subtract(const Duration(days: 7)),
      ReportsPreset.last30Days => now.subtract(const Duration(days: 30)),
      ReportsPreset.thisMonth => DateTime(now.year, now.month, 1),
    };
  }
}

final reportsUsersProvider = FutureProvider<List<ReportUser>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'reports_users'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ReportUser.fromJson)
      .toList(growable: false);
});

final reportsDataProvider = FutureProvider<ReportsData>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return ReportsData.empty();

  final filters = ref.watch(reportsFiltersProvider);
  final from = filters.from;

  final paymentsResponse = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'reports_payments',
      'from': from.toIso8601String(),
      if (filters.userId != null) 'userId': filters.userId!,
    },
  );
  final payments = (paymentsResponse['items'] as List?) ?? const [];

  final revenueByDay = <DateTime, double>{};
  final revenueByCustomer = <String, double>{};
  for (final row in payments.whereType<Map<String, dynamic>>()) {
    final paidAt = DateTime.tryParse(row['paid_at']?.toString() ?? '')?.toLocal();
    final amountRaw = row['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '');
    if (paidAt == null || amount == null) continue;
    final day = DateTime(paidAt.year, paidAt.month, paidAt.day);
    revenueByDay.update(day, (v) => v + amount, ifAbsent: () => amount);
    final customer = (row['customers'] as Map<String, dynamic>?)?['name']?.toString();
    if (customer != null && customer.trim().isNotEmpty) {
      revenueByCustomer.update(customer, (v) => v + amount, ifAbsent: () => amount);
    }
  }

  final workOrdersResponse = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'reports_work_orders',
      'from': from.toIso8601String(),
      if (filters.userId != null) 'userId': filters.userId!,
    },
  );
  final workOrders = (workOrdersResponse['items'] as List?) ?? const [];
  int open = 0, inProgress = 0, done = 0;
  for (final row in workOrders.whereType<Map<String, dynamic>>()) {
    final status = row['status']?.toString();
    if (status == 'open') open++;
    if (status == 'in_progress') inProgress++;
    if (status == 'done') done++;
  }

  final now = DateTime.now();
  final points = <ReportPoint>[];
  final days = switch (filters.preset) {
    ReportsPreset.last7Days => 7,
    ReportsPreset.last30Days => 30,
    ReportsPreset.thisMonth => now.day,
  };
  for (int i = days - 1; i >= 0; i--) {
    final day = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
    points.add(ReportPoint(day: day, value: revenueByDay[day] ?? 0));
  }

  final topCustomers = revenueByCustomer.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));

  return ReportsData(
    revenueTrend: points,
    workOrderStatus: WorkOrderStatusReport(open: open, inProgress: inProgress, done: done),
    topCustomers: topCustomers.take(6).toList(growable: false),
  );
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(reportsFiltersProvider);
    final usersAsync = ref.watch(reportsUsersProvider);
    final dataAsync = ref.watch(reportsDataProvider);
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return AppPageLayout(
      title: 'Raporlar',
      subtitle: 'Gelir ve iş emri performansı.',
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                SizedBox(
                  width: 220,
                  child: DropdownButtonFormField<ReportsPreset>(
                    initialValue: filters.preset,
                    items: const [
                      DropdownMenuItem(
                        value: ReportsPreset.last7Days,
                        child: Text('Son 7 Gün'),
                      ),
                      DropdownMenuItem(
                        value: ReportsPreset.last30Days,
                        child: Text('Son 30 Gün'),
                      ),
                      DropdownMenuItem(
                        value: ReportsPreset.thisMonth,
                        child: Text('Bu Ay'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(reportsFiltersProvider.notifier).setPreset(v);
                    },
                    decoration: const InputDecoration(labelText: 'Tarih'),
                  ),
                ),
                const Gap(12),
                SizedBox(
                  width: 260,
                  child: usersAsync.when(
                    data: (users) => DropdownButtonFormField<String>(
                      initialValue: filters.userId,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Personel'),
                        ),
                        ...users
                            .where((u) => u.role != 'admin')
                            .map(
                              (u) => DropdownMenuItem<String>(
                                value: u.id,
                                child: Text(u.fullName ?? 'Personel'),
                              ),
                            ),
                      ],
                      onChanged: (v) =>
                          ref.read(reportsFiltersProvider.notifier).setUser(v),
                      decoration: const InputDecoration(labelText: 'Personel'),
                    ),
                    loading: () => const _DropdownLoading(),
                    error: (_, _) => DropdownButtonFormField<String>(
                      initialValue: filters.userId,
                      items: const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Personel'),
                        ),
                      ],
                      onChanged: (v) =>
                          ref.read(reportsFiltersProvider.notifier).setUser(v),
                      decoration: const InputDecoration(labelText: 'Personel'),
                    ),
                  ),
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(reportsDataProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yenile'),
                ),
              ],
            ),
          ),
          const Gap(14),
          dataAsync.when(
            data: (data) => LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 980;
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Gelir Trend', style: Theme.of(context).textTheme.titleMedium),
                            const Gap(6),
                            Text(
                              'Seçilen tarih aralığında günlük toplam.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                            const Gap(16),
                            SizedBox(
                              height: 260,
                              child: _TrendChart(points: data.revenueTrend),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (twoCols) const Gap(16),
                    if (twoCols)
                      Expanded(
                        flex: 2,
                        child: Column(
                          children: [
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'İş Emri Durumu',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const Gap(12),
                                  _StatusBars(status: data.workOrderStatus),
                                ],
                              ),
                            ),
                            const Gap(16),
                            AppCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'En Çok Gelir Getirenler',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const Gap(12),
                                  if (data.topCustomers.isEmpty)
                                    Text(
                                      'Bu aralıkta gelir kaydı yok.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: const Color(0xFF64748B)),
                                    )
                                  else
                                    for (final e in data.topCustomers)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 10),
                                        child: Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                e.key,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                                      fontWeight: FontWeight.w600,
                                                    ),
                                              ),
                                            ),
                                            Text(
                                              money.format(e.value),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(color: const Color(0xFF64748B)),
                                            ),
                                          ],
                                        ),
                                      ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
            loading: () => Skeletonizer(
              enabled: true,
              child: AppCard(
                child: SizedBox(height: 320),
              ),
            ),
            error: (_, _) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Raporlar yüklenemedi.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.points});

  final List<ReportPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    if (maxY == 0) {
      return Center(
        child: Text(
          'Bu aralıkta gelir kaydı yok.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: const Color(0xFF64748B)),
        ),
      );
    }

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY * 1.15,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: const FlTitlesData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            curveSmoothness: 0.15,
            dotData: const FlDotData(show: false),
            barWidth: 3,
            color: AppTheme.primary,
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.primary.withValues(alpha: 0.10),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusBars extends StatelessWidget {
  const _StatusBars({required this.status});

  final WorkOrderStatusReport status;

  @override
  Widget build(BuildContext context) {
    final total = (status.open + status.inProgress + status.done).clamp(1, 1 << 30);
    return Column(
      children: [
        _StatusRow(
          label: 'Açık',
          count: status.open,
          color: AppTheme.warning,
          ratio: status.open / total,
        ),
        const Gap(10),
        _StatusRow(
          label: 'Devam',
          count: status.inProgress,
          color: AppTheme.primary,
          ratio: status.inProgress / total,
        ),
        const Gap(10),
        _StatusRow(
          label: 'Tamam',
          count: status.done,
          color: AppTheme.success,
          ratio: status.done / total,
        ),
      ],
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.label,
    required this.count,
    required this.color,
    required this.ratio,
  });

  final String label;
  final int count;
  final Color color;
  final double ratio;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 56,
          child: Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF64748B), fontWeight: FontWeight.w600),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: ratio.isNaN ? 0 : ratio,
              minHeight: 10,
              backgroundColor: const Color(0xFFF1F5F9),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ),
        const Gap(10),
        SizedBox(
          width: 36,
          child: Text(
            '$count',
            textAlign: TextAlign.right,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF0F172A),
                ),
          ),
        ),
      ],
    );
  }
}

class _DropdownLoading extends StatelessWidget {
  const _DropdownLoading();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: DropdownButtonFormField<String>(
        initialValue: null,
        items: const [
          DropdownMenuItem<String>(value: null, child: Text('Tüm Personel')),
        ],
        onChanged: (_) {},
        decoration: const InputDecoration(labelText: 'Personel'),
      ),
    );
  }
}

class ReportsData {
  const ReportsData({
    required this.revenueTrend,
    required this.workOrderStatus,
    required this.topCustomers,
  });

  final List<ReportPoint> revenueTrend;
  final WorkOrderStatusReport workOrderStatus;
  final List<MapEntry<String, double>> topCustomers;

  factory ReportsData.empty() => const ReportsData(
        revenueTrend: [],
        workOrderStatus: WorkOrderStatusReport(open: 0, inProgress: 0, done: 0),
        topCustomers: [],
      );
}

class ReportPoint {
  const ReportPoint({required this.day, required this.value});

  final DateTime day;
  final double value;
}

class WorkOrderStatusReport {
  const WorkOrderStatusReport({
    required this.open,
    required this.inProgress,
    required this.done,
  });

  final int open;
  final int inProgress;
  final int done;
}

class ReportUser {
  const ReportUser({required this.id, required this.fullName, required this.role});

  final String id;
  final String? fullName;
  final String? role;

  factory ReportUser.fromJson(Map<String, dynamic> json) {
    return ReportUser(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
    );
  }
}
