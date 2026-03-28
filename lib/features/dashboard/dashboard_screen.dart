import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/compact_stat_card.dart';
import 'dashboard_providers.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final seriesAsync = ref.watch(dashboardRevenueSeriesProvider);
    final activitiesAsync = ref.watch(dashboardActivitiesProvider);
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    return AppPageLayout(
      title: 'Panel',
      subtitle: 'Genel görünüm, bugün ve yaklaşan işler.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(dashboardMetricsProvider);
            ref.invalidate(dashboardRevenueSeriesProvider);
            ref.invalidate(dashboardActivitiesProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        children: [
          Skeletonizer(
            enabled: metricsAsync.isLoading,
            child: _MetricsGrid(
              money: money,
              metrics: metricsAsync.value ?? DashboardMetrics.zero(),
            ),
          ),
          const Gap(16),
          metricsAsync.when(
            data: (metrics) =>
                _DashboardHighlights(metrics: metrics, money: money),
            loading: () => const AppSectionCard(child: SizedBox(height: 90)),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const Gap(12),
          LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 980;
              final sidePanel = Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'İş Emri Durumu',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(6),
                        Text(
                          'Açık, devam eden ve tamamlanan işler.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        const Gap(12),
                        SizedBox(
                          height: 160,
                          child: metricsAsync.when(
                            data: (metrics) =>
                                _WorkOrderPieChart(metrics: metrics),
                            loading: () => const _ChartSkeleton(),
                            error: (error, stackTrace) => const _ChartError(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(16),
                  AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Son Aktiviteler',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(6),
                        Text(
                          'İş emirleri ve servis kayıtları.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        const Gap(8),
                        activitiesAsync.when(
                          data: (items) => _ActivitySummary(items: items),
                          loading: () => const SizedBox.shrink(),
                          error: (error, stackTrace) => const SizedBox.shrink(),
                        ),
                        const Gap(12),
                        const _ActivityTimeline(),
                      ],
                    ),
                  ),
                ],
              );

              return twoCols
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: _RevenuePanel(seriesAsync: seriesAsync),
                        ),
                        const Gap(16),
                        Expanded(flex: 2, child: sidePanel),
                      ],
                    )
                  : Column(
                      children: [
                        _RevenuePanel(seriesAsync: seriesAsync),
                        const Gap(16),
                        sidePanel,
                      ],
                    );
            },
          ),
        ],
      ),
    );
  }
}

class _RevenuePanel extends StatelessWidget {
  const _RevenuePanel({required this.seriesAsync});

  final AsyncValue<List<DashboardDailyPoint>> seriesAsync;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Gelir (Son 14 Gün)',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Gap(6),
          Text(
            'Ödemeler üzerinden günlük toplam.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const Gap(12),
          SizedBox(
            height: 240,
            child: seriesAsync.when(
              data: (points) => _RevenueChart(points: points),
              loading: () => const _ChartSkeleton(),
              error: (error, stackTrace) => const _ChartError(),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({required this.metrics, required this.money});

  final DashboardMetrics metrics;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final revenueChange = metrics.revenueChangePercent;
    final revenueChangeText = revenueChange >= 0
        ? '+${revenueChange.toStringAsFixed(0)}%'
        : '${revenueChange.toStringAsFixed(0)}%';

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1200
            ? 6
            : width >= 980
            ? 4
            : width >= 720
            ? 3
            : 2;
        final spacing = 10.0;
        final itemWidth = (width - (columns - 1) * spacing) / columns;

        final items = [
          _MetricTile(
            title: 'Toplam Müşteri',
            value: metrics.totalCustomers.toString(),
            icon: Icons.people_alt_rounded,
          ),
          _MetricTile(
            title: 'Açık İş Emirleri',
            value: metrics.openWorkOrders.toString(),
            icon: Icons.assignment_rounded,
            tone: metrics.openWorkOrders > 0
                ? _MetricTone.warning
                : _MetricTone.neutral,
          ),
          _MetricTile(
            title: 'Devam Eden',
            value: metrics.inProgressWorkOrders.toString(),
            icon: Icons.timelapse_rounded,
            tone: _MetricTone.primary,
          ),
          _MetricTile(
            title: 'Bugünkü İşler',
            value: metrics.todayWorkOrders.toString(),
            icon: Icons.today_rounded,
          ),
          _MetricTile(
            title: 'Süresi Dolanlar',
            value: metrics.expiringSoon.toString(),
            icon: Icons.warning_rounded,
            tone: metrics.expiringSoon > 0
                ? _MetricTone.warning
                : _MetricTone.neutral,
          ),
          _MetricTile(
            title: 'Gelir (Bu Ay)',
            value: money.format(metrics.revenue),
            icon: Icons.payments_rounded,
            tone: _MetricTone.success,
            subtitle: revenueChangeText,
            subtitleColor: revenueChange >= 0
                ? AppTheme.success
                : AppTheme.error,
          ),
          _MetricTile(
            title: 'Açık Faturalar',
            value: metrics.openInvoices.toString(),
            icon: Icons.receipt_long_rounded,
            subtitle: money.format(metrics.totalInvoiceAmount),
          ),
          _MetricTile(
            title: 'Düşük Stok',
            value: metrics.lowStockProducts.toString(),
            icon: Icons.inventory_2_rounded,
            tone: metrics.lowStockProducts > 0
                ? _MetricTone.warning
                : _MetricTone.success,
          ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items) SizedBox(width: itemWidth, child: item),
          ],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.icon,
    this.tone = _MetricTone.neutral,
    this.subtitle,
    this.subtitleColor,
  });

  final String title;
  final String value;
  final IconData icon;
  final _MetricTone tone;
  final String? subtitle;
  final Color? subtitleColor;

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      _MetricTone.primary => AppTheme.primary,
      _MetricTone.warning => AppTheme.warning,
      _MetricTone.success => AppTheme.success,
      _MetricTone.neutral => const Color(0xFF0F172A),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CompactStatCard(label: title, value: value, icon: icon, color: accent),
        if (subtitle != null) ...[
          const Gap(4),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              subtitle!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: subtitleColor ?? AppTheme.textMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

enum _MetricTone { primary, warning, success, neutral }

class _DashboardHighlights extends StatelessWidget {
  const _DashboardHighlights({required this.metrics, required this.money});

  final DashboardMetrics metrics;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final cards = <_HighlightData>[
      if (metrics.todayWorkOrders > 0)
        _HighlightData(
          title: 'Bugün planlı işler var',
          description:
              '${metrics.todayWorkOrders} iş emri bugün için planlanmış durumda.',
          icon: Icons.event_note_rounded,
          color: AppTheme.primary,
        ),
      if (metrics.expiringSoon > 0)
        _HighlightData(
          title: 'Yaklaşan yenilemeler',
          description:
              '${metrics.expiringSoon} hat/lisans için bitiş tarihi yaklaşıyor.',
          icon: Icons.schedule_send_rounded,
          color: AppTheme.warning,
        ),
      if (metrics.openInvoices > 0)
        _HighlightData(
          title: 'Tahsilat bekleyen faturalar',
          description:
              '${metrics.openInvoices} açık fatura toplam ${money.format(metrics.totalInvoiceAmount)} tutuyor.',
          icon: Icons.receipt_long_rounded,
          color: AppTheme.error,
        ),
      if (metrics.lowStockProducts > 0)
        _HighlightData(
          title: 'Düşük stok uyarısı',
          description:
              '${metrics.lowStockProducts} ürün minimum stok seviyesinde veya altında.',
          icon: Icons.inventory_2_rounded,
          color: AppTheme.success,
        ),
    ];

    if (cards.isEmpty) {
      return AppSectionCard(
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: AppTheme.success,
              ),
            ),
            const Gap(12),
            Expanded(
              child: Text(
                'Kritik uyarı görünmüyor. Panel genel olarak sağlıklı.',
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        for (int i = 0; i < cards.length; i++) ...[
          _HighlightCard(data: cards[i]),
          if (i != cards.length - 1) const Gap(12),
        ],
      ],
    );
  }
}

class _HighlightData {
  const _HighlightData({
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
}

class _HighlightCard extends StatelessWidget {
  const _HighlightCard({required this.data});

  final _HighlightData data;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: data.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(data.icon, color: data.color),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.title,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Gap(4),
                Text(
                  data.description,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkOrderPieChart extends StatelessWidget {
  const _WorkOrderPieChart({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final total =
        metrics.openWorkOrders +
        metrics.inProgressWorkOrders +
        metrics.completedWorkOrders;

    if (total == 0) {
      return Center(
        child: Text(
          'İş emri kaydı yok.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
      );
    }

    return Row(
      children: [
        Expanded(
          child: PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: 30,
              sections: [
                PieChartSectionData(
                  value: metrics.openWorkOrders.toDouble(),
                  color: AppTheme.warning,
                  radius: 35,
                  title: '',
                ),
                PieChartSectionData(
                  value: metrics.inProgressWorkOrders.toDouble(),
                  color: AppTheme.primary,
                  radius: 35,
                  title: '',
                ),
                PieChartSectionData(
                  value: metrics.completedWorkOrders.toDouble(),
                  color: AppTheme.success,
                  radius: 35,
                  title: '',
                ),
              ],
            ),
          ),
        ),
        const Gap(16),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendItem(
              color: AppTheme.warning,
              label: 'Açık',
              value: metrics.openWorkOrders,
            ),
            const Gap(8),
            _LegendItem(
              color: AppTheme.primary,
              label: 'Devam',
              value: metrics.inProgressWorkOrders,
            ),
            const Gap(8),
            _LegendItem(
              color: AppTheme.success,
              label: 'Tamamlanan',
              value: metrics.completedWorkOrders,
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(3),
          ),
        ),
        const Gap(8),
        Text(
          '$label: $value',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500),
        ),
      ],
    );
  }
}

class _RevenueChart extends StatelessWidget {
  const _RevenueChart({required this.points});

  final List<DashboardDailyPoint> points;

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
        lineTouchData: LineTouchData(
          enabled: true,
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => const Color(0xFF0B1220),
            getTooltipItems: (items) {
              final money = NumberFormat.currency(
                locale: 'tr_TR',
                symbol: '₺',
                decimalDigits: 0,
              );
              return items.map((i) {
                final day = points[i.spotIndex].day;
                final date = DateFormat('d MMM', 'tr_TR').format(day);
                return LineTooltipItem(
                  '$date\n${money.format(i.y)}',
                  const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    height: 1.3,
                  ),
                );
              }).toList();
            },
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < points.length; i++)
                FlSpot(i.toDouble(), points[i].value),
            ],
            isCurved: true,
            curveSmoothness: 0.12,
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

class _ChartSkeleton extends StatelessWidget {
  const _ChartSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
    );
  }
}

class _ChartError extends StatelessWidget {
  const _ChartError();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Gelir grafiği yüklenemedi.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.items});

  final List<DashboardActivity> items;

  @override
  Widget build(BuildContext context) {
    final workOrders = items
        .where((item) => item.type == DashboardActivityType.workOrder)
        .length;
    final services = items.length - workOrders;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _SummaryChip(
          label: 'İş Emri',
          value: '$workOrders',
          color: AppTheme.primary,
        ),
        _SummaryChip(
          label: 'Servis',
          value: '$services',
          color: AppTheme.success,
        ),
      ],
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        '$label: $value',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ActivityTimeline extends ConsumerWidget {
  const _ActivityTimeline();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(dashboardActivitiesProvider);

    return activitiesAsync.when(
      data: (items) {
        if (items.isEmpty) {
          return Text(
            'Henüz aktivite kaydı yok.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          );
        }

        return Column(
          children: [
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(
                  bottom: i == items.length - 1 ? 0 : 12,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              items[i].type == DashboardActivityType.workOrder
                                  ? 'İş emri güncellendi'
                                  : 'Servis kaydı güncellendi',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Gap(2),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    items[i].customerName ?? items[i].title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF64748B),
                                        ),
                                  ),
                                ),
                                Text(
                                  _relativeTime(items[i].createdAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF94A3B8),
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
      loading: () => Skeletonizer(
        enabled: true,
        child: Column(
          children: [
            for (int i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == 2 ? 0 : 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.primary,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'İş emri güncellendi',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const Gap(2),
                            const Row(
                              children: [
                                Expanded(child: Text('ACME Teknoloji')),
                                Text('10 dk önce'),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      error: (error, stackTrace) => Text(
        'Aktivite akışı yüklenemedi.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

String _relativeTime(DateTime dateTime) {
  final diff = DateTime.now().difference(dateTime);
  if (diff.inMinutes < 1) return 'Şimdi';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} saat önce';
  if (diff.inDays == 1) return 'Dün';
  return '${diff.inDays} gün önce';
}
