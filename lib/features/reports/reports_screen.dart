import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/compact_stat_card.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/ui/smart_filter_bar.dart';

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
    state = state.copyWith(
      userId: userId?.trim().isEmpty ?? true ? null : userId,
    );
  }

  void clear() {
    state = ReportsFilters.last30Days();
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
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('users')
      .select('id,full_name,role')
      .order('full_name');
  return (rows as List)
      .map((e) => ReportUser.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final reportsDataProvider = FutureProvider<ReportsData>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return ReportsData.empty();

  final filters = ref.watch(reportsFiltersProvider);
  final from = filters.from;

  var paymentsQ = client
      .from('payments')
      .select('paid_at,amount,currency,payment_method,customers(name)')
      .gte('paid_at', from.toIso8601String())
      .eq('is_active', true);
  if (filters.userId != null) {
    paymentsQ = paymentsQ.eq('created_by', filters.userId!);
  }
  final payments = await paymentsQ;

  final revenueByDay = <DateTime, double>{};
  final revenueByCustomer = <String, double>{};
  final dailyPayments = <DateTime, _DailyPaymentAccumulator>{};
  for (final row in (payments as List)) {
    final paidAt = DateTime.tryParse(row['paid_at']?.toString() ?? '');
    final amountRaw = row['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '');
    if (paidAt == null || amount == null) continue;
    final day = DateTime(paidAt.year, paidAt.month, paidAt.day);
    revenueByDay.update(day, (v) => v + amount, ifAbsent: () => amount);
    dailyPayments
        .putIfAbsent(day, _DailyPaymentAccumulator.new)
        .add(amount, row['payment_method']?.toString());
    final customer = (row['customers'] as Map<String, dynamic>?)?['name']
        ?.toString();
    if (customer != null && customer.trim().isNotEmpty) {
      revenueByCustomer.update(
        customer,
        (v) => v + amount,
        ifAbsent: () => amount,
      );
    }
  }

  var workQ = client
      .from('work_orders')
      .select('status,created_at')
      .gte('created_at', from.toIso8601String())
      .eq('is_active', true);
  if (filters.userId != null) {
    workQ = workQ.eq('assigned_to', filters.userId!);
  }
  final workOrders = await workQ;
  int open = 0, inProgress = 0, done = 0;
  for (final row in (workOrders as List)) {
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
    final day = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: i));
    points.add(ReportPoint(day: day, value: revenueByDay[day] ?? 0));
  }

  final topCustomers = revenueByCustomer.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final totalRevenue = revenueByDay.values.fold<double>(
    0,
    (sum, value) => sum + value,
  );
  final dailyPaymentReports =
      dailyPayments.entries
          .map(
            (entry) => DailyPaymentReport(
              day: entry.key,
              total: entry.value.total,
              count: entry.value.count,
              methodCounts: entry.value.methodCounts,
            ),
          )
          .toList(growable: false)
        ..sort((a, b) => b.day.compareTo(a.day));
  final totalWorkOrders = open + inProgress + done;
  final completedRate = totalWorkOrders == 0 ? 0.0 : done / totalWorkOrders;

  return ReportsData(
    revenueTrend: points,
    workOrderStatus: WorkOrderStatusReport(
      open: open,
      inProgress: inProgress,
      done: done,
    ),
    topCustomers: topCustomers.take(6).toList(growable: false),
    dailyPayments: dailyPaymentReports.take(10).toList(growable: false),
    totalRevenue: totalRevenue,
    totalWorkOrders: totalWorkOrders,
    completedRate: completedRate,
  );
});

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(reportsFiltersProvider);
    final usersAsync = ref.watch(reportsUsersProvider);
    final dataAsync = ref.watch(reportsDataProvider);
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    return AppPageLayout(
      title: 'Raporlar',
      subtitle: 'Gelir, operasyon ve ödeme akışlarını tek bakışta izleyin.',
      body: Column(
        children: [
          SmartFilterBar(
            title: 'Rapor Filtreleri',
            subtitle: 'Tarih aralığı ve personel bazlı görünümü daraltın.',
            trailing: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () => ref.invalidate(reportsDataProvider),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Yenile'),
                ),
                TextButton(
                  onPressed: () =>
                      ref.read(reportsFiltersProvider.notifier).clear(),
                  child: const Text('Sıfırla'),
                ),
              ],
            ),
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
                  decoration: const InputDecoration(
                    hintText: 'Tarih aralığı',
                    prefixIcon: Icon(Icons.date_range_rounded),
                  ),
                ),
              ),
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
                    decoration: const InputDecoration(
                      hintText: 'Personel',
                      prefixIcon: Icon(Icons.person_search_rounded),
                    ),
                  ),
                  loading: () => const _DropdownLoading(),
                  error: (error, stackTrace) => DropdownButtonFormField<String>(
                    initialValue: filters.userId,
                    items: const [
                      DropdownMenuItem<String>(
                        value: null,
                        child: Text('Tüm Personel'),
                      ),
                    ],
                    onChanged: (v) =>
                        ref.read(reportsFiltersProvider.notifier).setUser(v),
                    decoration: const InputDecoration(
                      hintText: 'Personel',
                      prefixIcon: Icon(Icons.person_search_rounded),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const Gap(14),
          dataAsync.when(
            data: (data) => LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 980;
                final sidePanel = Column(
                  children: [
                    AppSectionCard(
                      title: 'İş Emri Durumu',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [_StatusBars(status: data.workOrderStatus)],
                      ),
                    ),
                    const Gap(16),
                    AppSectionCard(
                      title: 'Günlük Ödeme Raporu',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Gap(12),
                          if (data.dailyPayments.isEmpty)
                            Text(
                              'Bu aralıkta ödeme kaydı yok.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            )
                          else
                            for (final item in data.dailyPayments)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            DateFormat(
                                              'd MMMM y',
                                              'tr_TR',
                                            ).format(item.day),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodyMedium
                                                ?.copyWith(
                                                  fontWeight: FontWeight.w700,
                                                ),
                                          ),
                                        ),
                                        Text(
                                          money.format(item.total),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppTheme.success,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ],
                                    ),
                                    const Gap(4),
                                    Text(
                                      '${item.count} ödeme',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF64748B),
                                          ),
                                    ),
                                    if (item.methodCounts.isNotEmpty) ...[
                                      const Gap(6),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: item.methodCounts.entries
                                            .map(
                                              (entry) => _MethodBadge(
                                                label:
                                                    '${_paymentMethodLabel(entry.key)} • ${entry.value}',
                                              ),
                                            )
                                            .toList(growable: false),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                        ],
                      ),
                    ),
                    const Gap(16),
                    AppSectionCard(
                      title: 'En Çok Gelir Getirenler',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Gap(12),
                          if (data.topCustomers.isEmpty)
                            Text(
                              'Bu aralıkta gelir kaydı yok.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            )
                          else
                            for (final entry in data.topCustomers)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 10),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        entry.key,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                    ),
                                    Text(
                                      money.format(entry.value),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: const Color(0xFF64748B),
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

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: CompactStatCard(
                            label: 'Toplam Gelir',
                            value: money.format(data.totalRevenue),
                            icon: Icons.payments_rounded,
                            color: AppTheme.success,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: CompactStatCard(
                            label: 'İş Emirleri',
                            value: '${data.totalWorkOrders}',
                            icon: Icons.assignment_turned_in_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: CompactStatCard(
                            label: 'Tamamlanma',
                            value: '%${(data.completedRate * 100).round()}',
                            icon: Icons.insights_rounded,
                            color: AppTheme.warning,
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    if (twoCols)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            flex: 3,
                            child: AppSectionCard(
                              title: 'Gelir Trend',
                              subtitle:
                                  'Seçilen tarih aralığında günlük toplam.',
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Gap(4),
                                  SizedBox(
                                    height: 260,
                                    child: _TrendChart(
                                      points: data.revenueTrend,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const Gap(16),
                          Expanded(flex: 2, child: sidePanel),
                        ],
                      )
                    else
                      Column(
                        children: [
                          AppSectionCard(
                            title: 'Gelir Trend',
                            subtitle: 'Seçilen tarih aralığında günlük toplam.',
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Gap(4),
                                SizedBox(
                                  height: 260,
                                  child: _TrendChart(points: data.revenueTrend),
                                ),
                              ],
                            ),
                          ),
                          const Gap(16),
                          sidePanel,
                        ],
                      ),
                  ],
                );
              },
            ),
            loading: () => Skeletonizer(
              enabled: true,
              child: AppCard(child: SizedBox(height: 320)),
            ),
            error: (error, stackTrace) => const EmptyStateCard(
              icon: Icons.bar_chart_rounded,
              title: 'Raporlar yüklenemedi',
              message: 'Veri kaynağına ulaşılamadı. Lütfen tekrar deneyin.',
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
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
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
    final total = (status.open + status.inProgress + status.done).clamp(
      1,
      1 << 30,
    );
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
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
        onChanged: (value) {},
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
    required this.dailyPayments,
    required this.totalRevenue,
    required this.totalWorkOrders,
    required this.completedRate,
  });

  final List<ReportPoint> revenueTrend;
  final WorkOrderStatusReport workOrderStatus;
  final List<MapEntry<String, double>> topCustomers;
  final List<DailyPaymentReport> dailyPayments;
  final double totalRevenue;
  final int totalWorkOrders;
  final double completedRate;

  factory ReportsData.empty() => const ReportsData(
    revenueTrend: [],
    workOrderStatus: WorkOrderStatusReport(open: 0, inProgress: 0, done: 0),
    topCustomers: [],
    dailyPayments: [],
    totalRevenue: 0,
    totalWorkOrders: 0,
    completedRate: 0,
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

class DailyPaymentReport {
  const DailyPaymentReport({
    required this.day,
    required this.total,
    required this.count,
    required this.methodCounts,
  });

  final DateTime day;
  final double total;
  final int count;
  final Map<String, int> methodCounts;
}

class _DailyPaymentAccumulator {
  double total = 0;
  int count = 0;
  final Map<String, int> methodCounts = {};

  void add(double amount, String? method) {
    total += amount;
    count += 1;
    if (method == null || method.trim().isEmpty) return;
    methodCounts.update(method, (value) => value + 1, ifAbsent: () => 1);
  }
}

class _MethodBadge extends StatelessWidget {
  const _MethodBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFF475569),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _paymentMethodLabel(String? method) {
  return switch (method) {
    'cash' => 'Nakit',
    'bank' => 'Havale/EFT',
    'pos' => 'POS',
    'credit_card' => 'Kredi Kartı',
    'check' => 'Çek',
    'other' => 'Diğer',
    _ => 'Belirsiz',
  };
}

class ReportUser {
  const ReportUser({
    required this.id,
    required this.fullName,
    required this.role,
  });

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
