import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_section_card.dart';
import '../../design_system/ds_tokens.dart';
import 'reports_models.dart';

final reportMoney = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 0,
);

final reportMoneyExact = NumberFormat.currency(
  locale: 'tr_TR',
  symbol: '₺',
  decimalDigits: 2,
);

double? reportTrend(num current, num previous) {
  if (previous == 0) return current == 0 ? null : 100;
  return ((current - previous) / previous) * 100;
}

List<ReportPoint> fillDailySeries({
  required DateTime from,
  required DateTime to,
  required List<ReportPoint> raw,
}) {
  final map = <DateTime, double>{};
  for (final point in raw) {
    final day = DateTime(point.day.year, point.day.month, point.day.day);
    map.update(day, (v) => v + point.value, ifAbsent: () => point.value);
  }
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  final points = <ReportPoint>[];
  for (var d = start; !d.isAfter(end); d = d.add(const Duration(days: 1))) {
    points.add(ReportPoint(day: d, value: map[d] ?? 0));
  }
  return points;
}

class ReportKpiGrid extends StatelessWidget {
  const ReportKpiGrid({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cols = width >= 1280
            ? 4
            : width >= 900
            ? 3
            : width >= 560
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: cols,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: DsSpace.md,
          crossAxisSpacing: DsSpace.md,
          childAspectRatio: width >= 560 ? 2.85 : 2.55,
          children: items,
        );
      },
    );
  }
}

class ReportTrendChart extends StatelessWidget {
  const ReportTrendChart({
    super.key,
    required this.points,
    required this.color,
    this.emptyLabel = 'Bu aralıkta kayıt yok.',
  });

  final List<ReportPoint> points;
  final Color color;
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final maxY = points.fold<double>(0, (m, p) => p.value > m ? p.value : m);
    if (maxY <= 0) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Text(
            emptyLabel,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final showLabels = points.length <= 14;
    return SizedBox(
      height: 240,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY * 1.15,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: AppTheme.border.withValues(alpha: 0.6),
              strokeWidth: 1,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, _) {
                  if (value <= 0 || value == maxY * 1.15) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    NumberFormat.compact(locale: 'tr_TR').format(value),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                      fontSize: 10,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: showLabels,
                interval: (points.length / 6).clamp(1, 10).toDouble(),
                getTitlesWidget: (value, _) {
                  final i = value.round();
                  if (i < 0 || i >= points.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      DateFormat('d MMM', 'tr_TR').format(points[i].day),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                        fontSize: 10,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => AppTheme.surface,
              maxContentWidth: 180,
              getTooltipItems: (spots) => spots
                  .map(
                    (s) => LineTooltipItem(
                      '${DateFormat('dd.MM.yyyy').format(points[s.x.toInt()].day)}\n${reportMoney.format(s.y)}',
                      TextStyle(
                        color: AppTheme.text,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (int i = 0; i < points.length; i++)
                  FlSpot(i.toDouble(), points[i].value),
              ],
              isCurved: true,
              curveSmoothness: 0.16,
              dotData: FlDotData(show: points.length <= 14),
              barWidth: 3,
              color: color,
              belowBarData: BarAreaData(
                show: true,
                color: color.withValues(alpha: 0.10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class ReportRankedList extends StatelessWidget {
  const ReportRankedList({
    super.key,
    required this.items,
    this.valueBuilder,
    this.empty = 'Kayıt yok.',
  });

  final List<ReportBucket> items;
  final String Function(ReportBucket item)? valueBuilder;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Text(
        empty,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
      );
    }
    final maxAmount = items.fold<double>(
      0,
      (m, e) => e.amount > m ? e.amount : m,
    );
    final maxCount = items.fold<int>(0, (m, e) => e.count > m ? e.count : m);
    final useAmount = maxAmount > 0;
    final maxVal = useAmount ? maxAmount : maxCount.toDouble();

    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Text(
                      valueBuilder?.call(item) ??
                          (useAmount
                              ? reportMoney.format(item.amount)
                              : '${item.count}'),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
                const Gap(5),
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: maxVal <= 0
                        ? 0
                        : ((useAmount ? item.amount : item.count.toDouble()) /
                                  maxVal)
                              .clamp(0, 1),
                    minHeight: 7,
                    backgroundColor: AppTheme.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class ReportBreakdownTable extends StatelessWidget {
  const ReportBreakdownTable({
    super.key,
    required this.rows,
    required this.labelOf,
    this.showAmount = true,
    this.showCount = true,
    this.empty = 'Kayıt yok.',
  });

  final List<ReportBucket> rows;
  final String Function(ReportBucket row) labelOf;
  final bool showAmount;
  final bool showCount;
  final String empty;

  @override
  Widget build(BuildContext context) {
    if (rows.isEmpty) {
      return Text(
        empty,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
      );
    }
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 7),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    labelOf(row),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
                if (showCount)
                  SizedBox(
                    width: 64,
                    child: Text(
                      '${row.count}',
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                if (showAmount)
                  SizedBox(
                    width: 110,
                    child: Text(
                      reportMoney.format(row.amount),
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class ReportStatusBars extends StatelessWidget {
  const ReportStatusBars({
    super.key,
    required this.items,
    required this.colorOf,
    required this.labelOf,
  });

  final List<ReportBucket> items;
  final Color Function(ReportBucket item) colorOf;
  final String Function(ReportBucket item) labelOf;

  @override
  Widget build(BuildContext context) {
    final total = items.fold<int>(0, (s, e) => s + e.count).clamp(1, 1 << 30);
    if (items.isEmpty) {
      return Text(
        'Kayıt yok.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
      );
    }
    return Column(
      children: [
        for (final item in items) ...[
          Row(
            children: [
              SizedBox(
                width: 108,
                child: Text(
                  labelOf(item),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: item.count / total,
                    minHeight: 10,
                    backgroundColor: AppTheme.surfaceMuted,
                    valueColor: AlwaysStoppedAnimation(colorOf(item)),
                  ),
                ),
              ),
              const Gap(10),
              SizedBox(
                width: 36,
                child: Text(
                  '${item.count}',
                  textAlign: TextAlign.right,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppTheme.text,
                  ),
                ),
              ),
            ],
          ),
          const Gap(10),
        ],
      ],
    );
  }
}

class ReportTwoCol extends StatelessWidget {
  const ReportTwoCol({super.key, required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          return Column(children: [left, const Gap(14), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const Gap(14),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

AppBadgeTone reportBadgeTone(String key) {
  return switch (key) {
    'paid' ||
    'done' ||
    'accepted' ||
    'converted' ||
    'approved' ||
    'sent' ||
    'ready' => AppBadgeTone.success,
    'open' ||
    'partial' ||
    'in_progress' ||
    'approval' ||
    'pending' ||
    'sent_pending' => AppBadgeTone.warning,
    'cancelled' || 'rejected' || 'expired' || 'not_sent' => AppBadgeTone.error,
    'draft' || 'waiting' => AppBadgeTone.neutral,
    _ => AppBadgeTone.primary,
  };
}

String invoiceStatusLabel(String key) => switch (key) {
  'draft' => 'Taslak',
  'open' => 'Açık',
  'partial' => 'Kısmi',
  'paid' => 'Ödendi',
  'cancelled' => 'İptal',
  _ => key,
};

String invoiceTypeLabel(String key) => switch (key) {
  'purchase' => 'Alış',
  'sales' => 'Satış',
  _ => key,
};

String eInvoiceStatusLabel(String key) => switch (key) {
  'sent' => 'Gönderildi',
  'manual' => 'Manuel',
  'manual_sent' => 'Test / manuel',
  'received' => 'Gelen',
  'not_sent' => 'Gönderilmedi',
  _ => key,
};

String paymentMethodLabel(String key) => switch (key) {
  'cash' => 'Nakit',
  'bank' => 'Banka',
  'credit_card' => 'Kredi kartı',
  'check' => 'Çek',
  'pos' => 'POS',
  'other' => 'Diğer',
  _ => key,
};

String workOrderStatusLabel(String key) => switch (key) {
  'open' => 'Açık',
  'in_progress' => 'Devam',
  'done' => 'Tamam',
  _ => key,
};

String serviceStatusLabel(String key) => switch (key) {
  'open' || 'waiting' => 'Bekliyor',
  'in_progress' || 'approval' => 'Onay / işlem',
  'ready' => 'Hazır',
  'done' => 'Tamamlandı',
  'cancelled' => 'İptal',
  _ => key,
};

String servicePriorityLabel(String key) => switch (key) {
  'low' => 'Düşük',
  'high' => 'Yüksek',
  'urgent' => 'Acil',
  _ => 'Normal',
};

String quoteStatusLabel(String key) => switch (key) {
  'sent' => 'Gönderildi',
  'accepted' => 'Onaylandı',
  'rejected' => 'Reddedildi',
  'expired' => 'Süresi doldu',
  'converted' => 'Faturaya dönüştü',
  _ => 'Taslak',
};

String formApprovalLabel(String key) => switch (key) {
  'approved' => 'Onaylı',
  _ => 'Bekleyen',
};

Color statusColor(String key) {
  return switch (reportBadgeTone(key)) {
    AppBadgeTone.success => AppTheme.success,
    AppBadgeTone.warning => AppTheme.warning,
    AppBadgeTone.error => AppTheme.error,
    AppBadgeTone.neutral => AppTheme.textMuted,
    AppBadgeTone.primary => AppTheme.primary,
  };
}

class ReportSectionCard extends StatelessWidget {
  const ReportSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.child,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return AppSectionCard(
      title: title,
      subtitle: subtitle,
      trailing: trailing,
      child: child,
    );
  }
}

IconData reportsSectionIcon(ReportsSection section) {
  return switch (section) {
    ReportsSection.overview => LucideIcons.layoutDashboard,
    ReportsSection.invoices => LucideIcons.receipt,
    ReportsSection.collections => LucideIcons.wallet,
    ReportsSection.quotes => LucideIcons.fileText,
    ReportsSection.customers => LucideIcons.users,
    ReportsSection.stock => LucideIcons.package,
    ReportsSection.workOrders => LucideIcons.clipboardList,
    ReportsSection.service => LucideIcons.wrench,
    ReportsSection.forms => LucideIcons.files,
    ReportsSection.finance => LucideIcons.landmark,
    ReportsSection.personnel => LucideIcons.users,
  };
}
