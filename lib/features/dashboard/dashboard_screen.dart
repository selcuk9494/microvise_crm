import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/utils/app_time.dart';
import '../../design_system/ds_kpi_tile.dart';
import '../../design_system/ds_tokens.dart';
import '../../design_system/status_tone.dart';
import 'dashboard_providers.dart';

/// Dashboard v2 (Microvise Design System v2, Faz 1).
///
/// Bilgi mimarisi iki bölüme ayrılmıştır: "Bugün" (günlük operasyon) ve
/// "Genel Bakış" (finans/müşteri özeti). KPI kartları `DsKpiTile`
/// (design_system) ile, iş emri durum dağılımı `status_tone` tonlarıyla
/// boyanan bir stacked bar ile gösterilir. Hiçbir KPI'da sahte/dekoratif
/// sparkline kullanılmaz — sparkline yalnızca gerçek bir zaman serisi
/// varsa (bu ekranda yalnızca 14 günlük gelir serisi, büyük grafikte)
/// gösterilir.
///
/// Business logic, provider'lar ve veri modeli değişmedi; yalnızca bu
/// dosyanın UI/UX katmanı yeniden düzenlendi. Bkz.
/// docs/design-system/dashboard-critique-and-concepts.md
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metricsAsync = ref.watch(dashboardMetricsProvider);
    final canSeeCustomers = ref.watch(hasPageAccessProvider(kPageCustomers));
    final canSeeWorkOrders = ref.watch(hasPageAccessProvider(kPageWorkOrders));
    final canSeeService = ref.watch(hasPageAccessProvider(kPageService));
    final canSeeProducts = ref.watch(hasPageAccessProvider(kPageProducts));
    final canSeeBilling = ref.watch(hasPageAccessProvider(kPageBilling));
    final canSeeReports = ref.watch(hasPageAccessProvider(kPageReports));

    final canSeeTileTotalCustomers = ref.watch(
      hasActionAccessProvider(kActionDashboardTotalCustomers),
    );
    final canSeeTileOpenWorkOrders = ref.watch(
      hasActionAccessProvider(kActionDashboardOpenWorkOrders),
    );
    final canSeeTileInProgressWorkOrders = ref.watch(
      hasActionAccessProvider(kActionDashboardInProgressWorkOrders),
    );
    final canSeeTileTodayWorkOrders = ref.watch(
      hasActionAccessProvider(kActionDashboardTodayWorkOrders),
    );
    final canSeeTileExpiringSoon = ref.watch(
      hasActionAccessProvider(kActionDashboardExpiringSoon),
    );
    final canSeeTileRevenue = ref.watch(
      hasActionAccessProvider(kActionDashboardRevenue),
    );
    final canSeeTileOpenInvoices = ref.watch(
      hasActionAccessProvider(kActionDashboardOpenInvoices),
    );

    final seriesAsync = canSeeReports
        ? ref.watch(dashboardRevenueSeriesProvider)
        : const AsyncValue<List<DashboardDailyPoint>>.data([]);
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 0,
    );

    final metrics = metricsAsync.value ?? DashboardMetrics.zero();

    final todayItems = _buildTodayItems(
      context: context,
      metrics: metrics,
      canSeeWorkOrders: canSeeWorkOrders,
      canSeeProducts: canSeeProducts,
      canSeeTileOpenWorkOrders: canSeeTileOpenWorkOrders,
      canSeeTileTodayWorkOrders: canSeeTileTodayWorkOrders,
      canSeeTileInProgressWorkOrders: canSeeTileInProgressWorkOrders,
      canSeeTileExpiringSoon: canSeeTileExpiringSoon,
    );
    final overviewItems = _buildOverviewItems(
      context: context,
      metrics: metrics,
      money: money,
      canSeeBilling: canSeeBilling,
      canSeeReports: canSeeReports,
      canSeeCustomers: canSeeCustomers,
      canSeeTileOpenInvoices: canSeeTileOpenInvoices,
      canSeeTileRevenue: canSeeTileRevenue,
      canSeeTileTotalCustomers: canSeeTileTotalCustomers,
    );

    return AppPageLayout(
      title: 'Panel',
      subtitle: 'Bugün ve genel görünüm.',
      compactHeader: true,
      body: Stack(
        children: [
          const Positioned.fill(
            child: IgnorePointer(child: _DashboardBackground()),
          ),
          RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(dashboardMetricsProvider);
              ref.invalidate(dashboardRevenueSeriesProvider);
              ref.invalidate(dashboardActivitiesProvider);
              await ref.read(dashboardMetricsProvider.future);
            },
            child: ListView(
              padding: const EdgeInsets.only(bottom: 120),
              children: [
                Skeletonizer(
                  enabled: metricsAsync.isLoading,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (todayItems.isNotEmpty) ...[
                        const _DashboardSectionHeader(title: 'Bugün'),
                        _KpiGrid(items: todayItems),
                        const Gap(DsSpace.xl2),
                      ],
                      if (overviewItems.isNotEmpty) ...[
                        const _DashboardSectionHeader(title: 'Genel Bakış'),
                        _KpiGrid(items: overviewItems),
                      ],
                    ],
                  ),
                ),
                const Gap(DsSpace.xl2),
                _InsightsSection(
                  seriesAsync: seriesAsync,
                  metricsAsync: metricsAsync,
                  canSeeReports: canSeeReports,
                  canSeeWorkOrders: canSeeWorkOrders,
                  canSeeService: canSeeService,
                ),
                const Gap(DsSpace.xl3),
                const _DashboardSectionHeader(title: 'Yardımcı Bilgiler'),
                const _BankPasswordsCard(),
                const Gap(DsSpace.md),
                const _ExchangeRatesCard(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBackground extends StatelessWidget {
  const _DashboardBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(decoration: AppTheme.pageCanvas);
  }
}

/// Bölüm başlığı ("Bugün" / "Genel Bakış" / "Yardımcı Bilgiler") — tüm KPI
/// grupları ve yardımcı kartlar bir başlığın altında gruplanır; eskiden
/// olduğu gibi birbirinden kopuk, başlıksız kart yığını oluşturulmaz.
class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: DsSpace.sm, left: 2),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w800,
          // textMuted doğrudan sayfa zemininde (kart içi değil) WCAG AA
          // eşiğinin az altında kalıyordu (~4.46:1, hesaplandı); textSoft
          // aynı "ikincil" hissi verirken ~9.5:1 kontrast sağlıyor.
          color: AppTheme.textSoft,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Bir KPI kartının içerik tanımı — görsel üretim `_KpiGrid` + `DsKpiTile`
/// tarafından yapılır, burada yalnızca veri/tone eşlemesi tutulur.
class _KpiItem {
  const _KpiItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.subtitle,
    this.subtitleColor,
    this.trendPercent,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final DsStatusTone tone;
  final String? subtitle;
  final Color? subtitleColor;
  final double? trendPercent;
  final VoidCallback? onTap;
}

/// Masaüstünde satır başına en fazla 4, mobilde sabit 2 sütunlu KPI grid'i.
class _KpiGrid extends StatelessWidget {
  const _KpiGrid({required this.items});

  final List<_KpiItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final cap = width >= DsBreakpoints.desktop ? 4 : 2;
        final columns = items.length < cap ? items.length : cap;
        final spacing = width < DsBreakpoints.mobile ? 8.0 : 12.0;
        final itemWidth = (width - (columns - 1) * spacing) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: DsKpiTile(
                  label: item.label,
                  value: item.value,
                  icon: item.icon,
                  accentColor: dsStatusToneColor(item.tone),
                  subtitle: item.subtitle,
                  subtitleColor: item.subtitleColor,
                  trendPercent: item.trendPercent,
                  onTap: item.onTap,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// "Bugün" bölümü: Açık İş Emirleri, Bugünkü İşler, Devam Eden, Yakında
/// Süresi Dolacaklar. Tamamı `DashboardMetrics`'te bugün de var olan gerçek
/// alanlardır; yeni alan üretilmedi.
List<_KpiItem> _buildTodayItems({
  required BuildContext context,
  required DashboardMetrics metrics,
  required bool canSeeWorkOrders,
  required bool canSeeProducts,
  required bool canSeeTileOpenWorkOrders,
  required bool canSeeTileTodayWorkOrders,
  required bool canSeeTileInProgressWorkOrders,
  required bool canSeeTileExpiringSoon,
}) {
  return [
    if (canSeeWorkOrders && canSeeTileOpenWorkOrders)
      _KpiItem(
        label: 'Açık İş Emirleri',
        value: metrics.openWorkOrders.toString(),
        icon: LucideIcons.columns3,
        tone: DsStatusTone.info,
        onTap: () => context.go('/is-emirleri'),
      ),
    if (canSeeWorkOrders && canSeeTileTodayWorkOrders)
      _KpiItem(
        label: 'Bugünkü İşler',
        value: metrics.todayWorkOrders.toString(),
        icon: LucideIcons.calendarDays,
        tone: DsStatusTone.info,
        onTap: () => context.go('/is-emirleri'),
      ),
    if (canSeeWorkOrders && canSeeTileInProgressWorkOrders)
      _KpiItem(
        label: 'Devam Eden',
        value: metrics.inProgressWorkOrders.toString(),
        icon: LucideIcons.timer,
        tone: DsStatusTone.info,
        onTap: () => context.go('/is-emirleri'),
      ),
    if (canSeeProducts && canSeeTileExpiringSoon)
      _KpiItem(
        label: 'Yakında Süresi Dolacaklar',
        value: metrics.expiringSoon.toString(),
        icon: LucideIcons.triangleAlert,
        tone: metrics.expiringSoon > 0
            ? DsStatusTone.warning
            : DsStatusTone.neutral,
        onTap: () => context.go('/urunler'),
      ),
  ];
}

/// "Genel Bakış" bölümü: Açık Faturalar, Gelir (Bu Ay), Toplam Müşteri.
List<_KpiItem> _buildOverviewItems({
  required BuildContext context,
  required DashboardMetrics metrics,
  required NumberFormat money,
  required bool canSeeBilling,
  required bool canSeeReports,
  required bool canSeeCustomers,
  required bool canSeeTileOpenInvoices,
  required bool canSeeTileRevenue,
  required bool canSeeTileTotalCustomers,
}) {
  return [
    if (canSeeBilling && canSeeTileOpenInvoices)
      _KpiItem(
        label: 'Açık Faturalar',
        value: metrics.openInvoices.toString(),
        icon: LucideIcons.receiptText,
        tone: DsStatusTone.info,
        subtitle: money.format(metrics.totalInvoiceAmount),
        onTap: () => context.go('/faturalama'),
      ),
    if (canSeeReports && canSeeTileRevenue)
      _KpiItem(
        label: 'Gelir (Bu Ay)',
        value: money.format(metrics.revenue),
        icon: LucideIcons.banknote,
        tone: DsStatusTone.info,
        trendPercent: metrics.revenueChangePercent,
        onTap: () => context.go('/raporlar'),
      ),
    if (canSeeCustomers && canSeeTileTotalCustomers)
      _KpiItem(
        label: 'Toplam Müşteri',
        value: metrics.totalCustomers.toString(),
        icon: LucideIcons.usersRound,
        tone: DsStatusTone.info,
        onTap: () => context.go('/musteriler'),
      ),
  ];
}

/// Ortak kart başlığı (ikon well + başlık + açıklama) — eskiden 3 grafik
/// kartında neredeyse birebir kopyalanan blok tek yerde toplandı.
class _InsightCardHeader extends StatelessWidget {
  const _InsightCardHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final color = dsStatusToneColor(DsStatusTone.info);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: AppTheme.categoryIconWell(color),
          child: Icon(icon, size: 18, color: AppTheme.categoryIconFg(color)),
        ),
        const Gap(10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleMedium),
              const Gap(2),
              Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Ana içgörü alanı: gelir grafiği + iş emri durum dağılımı (sol/üst),
/// son aktiviteler (sağ/alt). ≥980px'te iki sütun, altında tek sütun —
/// mobilde aktivite listesi grafiklerden sonra gelir (yatay taşma yok).
class _InsightsSection extends StatelessWidget {
  const _InsightsSection({
    required this.seriesAsync,
    required this.metricsAsync,
    required this.canSeeReports,
    required this.canSeeWorkOrders,
    required this.canSeeService,
  });

  final AsyncValue<List<DashboardDailyPoint>> seriesAsync;
  final AsyncValue<DashboardMetrics> metricsAsync;
  final bool canSeeReports;
  final bool canSeeWorkOrders;
  final bool canSeeService;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final twoCols = constraints.maxWidth >= DsBreakpoints.filterBarWide;

        final revenueCard = AppCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InsightCardHeader(
                  icon: LucideIcons.chartNoAxesCombined,
                  title: 'Gelir (Son 14 Gün)',
                  subtitle: 'Ödemeler üzerinden günlük toplam.',
                ),
                const Gap(16),
                SizedBox(
                  height: 220,
                  child: seriesAsync.when(
                    data: (points) => _RevenueChart(points: points),
                    loading: () => const _ChartSkeleton(),
                    error: (_, _) => const _ChartError(),
                  ),
                ),
              ],
            ),
          ),
        );

        final workOrderStatusCard = AppCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InsightCardHeader(
                  icon: LucideIcons.clipboardList,
                  title: 'İş Emri Durumu',
                  subtitle: 'Açık, devam eden ve tamamlanan işler.',
                ),
                const Gap(16),
                metricsAsync.when(
                  data: (m) => _WorkOrderStatusBar(metrics: m),
                  loading: () =>
                      const SizedBox(height: 48, child: _ChartSkeleton()),
                  error: (_, _) =>
                      const SizedBox(height: 48, child: _ChartError()),
                ),
              ],
            ),
          ),
        );

        final activityCard = AppCard(
          padding: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _InsightCardHeader(
                  icon: LucideIcons.zap,
                  title: 'Son Aktiviteler',
                  subtitle: 'İş emirleri ve servis kayıtları.',
                ),
                const Gap(14),
                const _ActivityTimeline(),
              ],
            ),
          ),
        );

        if (!twoCols) {
          // Mobil/dar ekran: tek sütun, aktivite listesi grafiklerden sonra.
          return Column(
            children: [
              if (canSeeReports) revenueCard,
              if (canSeeReports && canSeeWorkOrders) const Gap(16),
              if (canSeeWorkOrders) workOrderStatusCard,
              if ((canSeeWorkOrders || canSeeService) &&
                  (canSeeReports || canSeeWorkOrders))
                const Gap(16),
              if (canSeeWorkOrders || canSeeService) activityCard,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 3,
              child: Column(
                children: [
                  if (canSeeReports) revenueCard,
                  if (canSeeReports && canSeeWorkOrders) const Gap(16),
                  if (canSeeWorkOrders) workOrderStatusCard,
                ],
              ),
            ),
            const Gap(16),
            Expanded(
              flex: 2,
              child: (canSeeWorkOrders || canSeeService)
                  ? activityCard
                  : const SizedBox.shrink(),
            ),
          ],
        );
      },
    );
  }
}

/// İş emri durum dağılımı — eski pasta grafiğin yerini alır. Aynı üç
/// durumun KPI kutularında zaten tek tek gösterildiği için pasta grafiğin
/// yarattığı bilgi tekrarı yerine tek bakışta oranı okunan bir stacked bar
/// kullanılır. Renkler `status_tone` tonlarından (`DsStatusTone`) gelir.
class _WorkOrderStatusBar extends StatelessWidget {
  const _WorkOrderStatusBar({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final open = metrics.openWorkOrders;
    final inProgress = metrics.inProgressWorkOrders;
    final done = metrics.completedWorkOrders;
    final total = open + inProgress + done;

    if (total == 0) {
      return SizedBox(
        height: 48,
        child: Center(
          child: Text(
            'İş emri kaydı yok.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
          ),
        ),
      );
    }

    final segments = <_StatusSegment>[
      _StatusSegment(value: open, tone: DsStatusTone.warning, label: 'Açık'),
      _StatusSegment(
        value: inProgress,
        tone: DsStatusTone.info,
        label: 'Devam Eden',
      ),
      _StatusSegment(
        value: done,
        tone: DsStatusTone.success,
        label: 'Tamamlanan',
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: SizedBox(
            height: 10,
            child: Row(
              children: [
                for (final segment in segments)
                  if (segment.value > 0)
                    Expanded(
                      flex: segment.value,
                      child: Container(color: dsStatusToneColor(segment.tone)),
                    ),
              ],
            ),
          ),
        ),
        const Gap(14),
        Wrap(
          spacing: 18,
          runSpacing: 8,
          children: [
            for (final segment in segments)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  DsStatusDot(tone: segment.tone),
                  const Gap(6),
                  Text(
                    '${segment.label}: ${segment.value}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSoft,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}

class _StatusSegment {
  const _StatusSegment({
    required this.value,
    required this.tone,
    required this.label,
  });

  final int value;
  final DsStatusTone tone;
  final String label;
}

class _ExchangeRatesCard extends ConsumerWidget {
  const _ExchangeRatesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(dashboardHalkbankRatesProvider);
    final format = NumberFormat('#,##0.0000', 'tr_TR');

    String subtitleFromRates(DashboardExchangeRates rates) {
      if (rates.items.isEmpty) return 'Halkbank • USD, EUR, GBP';
      final parts = rates.items
          .map((r) {
            final value = format.format(r.selling);
            return '${r.code}: $value';
          })
          .join(' • ');
      return 'Halkbank • $parts';
    }

    return Skeletonizer(
      enabled: ratesAsync.isLoading,
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: () {
          ref.invalidate(dashboardHalkbankRatesProvider);
          showDialog<void>(
            context: context,
            builder: (context) {
              return AlertDialog(
                title: const Text('Döviz Kurları (Halkbank)'),
                content: SizedBox(
                  width: 520,
                  child: Consumer(
                    builder: (context, ref, _) {
                      final async = ref.watch(dashboardHalkbankRatesProvider);
                      return async.when(
                        data: (rates) {
                          final updatedText = rates.fetchedAt == null
                              ? '—'
                              : DateFormat(
                                  'd MMM y HH:mm',
                                  'tr_TR',
                                ).format(AppTime.toTr(rates.fetchedAt!));
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Güncelleme: $updatedText',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: AppTheme.textMuted),
                              ),
                              const Gap(12),
                              if (rates.items.isEmpty)
                                const Text('Kur bilgisi alınamadı.')
                              else
                                Column(
                                  children: [
                                    for (final r in rates.items)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 56,
                                              child: Text(
                                                r.code,
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.titleSmall,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                'Alış: ${format.format(r.buying)}',
                                                style: Theme.of(
                                                  context,
                                                ).textTheme.bodyMedium,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                'Satış: ${format.format(r.selling)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700,
                                                    ),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 52,
                                              child: Text(
                                                (r.time ?? '').trim().isEmpty
                                                    ? '—'
                                                    : r.time!,
                                                textAlign: TextAlign.end,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: AppTheme.textMuted,
                                                    ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          );
                        },
                        loading: () => const SizedBox(
                          height: 140,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                        error: (err, st) =>
                            const Text('Kur bilgisi alınamadı.'),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final url =
                          ratesAsync.value?.sourceUrl ??
                          'https://kur.doviz.com/halkbank';
                      await launchUrl(
                        Uri.parse(url),
                        mode: LaunchMode.externalApplication,
                      );
                    },
                    child: const Text('Kaynak'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Kapat'),
                  ),
                ],
              );
            },
          );
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: AppTheme.categoryIconWell(
                  dsStatusToneColor(DsStatusTone.neutral),
                ),
                child: Icon(
                  LucideIcons.arrowLeftRight,
                  size: 16,
                  color: AppTheme.categoryIconFg(
                    dsStatusToneColor(DsStatusTone.neutral),
                  ),
                ),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Döviz Kurları',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      ratesAsync.when(
                        data: subtitleFromRates,
                        loading: () => 'Halkbank • yükleniyor…',
                        error: (err, st) => 'Halkbank • USD, EUR, GBP',
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                LucideIcons.externalLink,
                size: 18,
                color: AppTheme.textMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BankPasswordsCard extends StatelessWidget {
  const _BankPasswordsCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _showBankPicker(context),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: AppTheme.categoryIconWell(
                dsStatusToneColor(DsStatusTone.neutral),
              ),
              child: Icon(
                LucideIcons.lock,
                size: 16,
                color: AppTheme.categoryIconFg(
                  dsStatusToneColor(DsStatusTone.neutral),
                ),
              ),
            ),
            const Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Banka Şifreleri',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'İş Bankası / Garanti Bankası',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            Icon(LucideIcons.chevronRight, size: 18, color: AppTheme.textMuted),
          ],
        ),
      ),
    );
  }

  void _showBankPicker(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(LucideIcons.landmark),
                title: const Text('İş Bankası'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showPassword(context, _BankPasswordType.isbank);
                },
              ),
              ListTile(
                leading: const Icon(LucideIcons.landmark),
                title: const Text('Garanti Bankası'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showPassword(context, _BankPasswordType.garanti);
                },
              ),
              const Gap(12),
            ],
          ),
        );
      },
    );
  }

  void _showPassword(BuildContext context, _BankPasswordType type) {
    final now = AppTime.toTr(DateTime.now());
    final title = type == _BankPasswordType.isbank
        ? 'İş Bankası'
        : 'Garanti Bankası';
    final password = type == _BankPasswordType.isbank
        ? _isbankPassword(now)
        : _garantiPassword(now);

    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('$title Şifresi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Şifre'),
            const Gap(8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                password,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }
}

enum _BankPasswordType { isbank, garanti }

String _isbankPassword(DateTime nowTr) {
  final startOfYear = DateTime.utc(nowTr.year, 1, 1);
  final dayOfYear = nowTr.difference(startOfYear).inDays + 1;
  return dayOfYear.toString().padLeft(3, '0');
}

String _garantiPassword(DateTime nowTr) {
  final sum = nowTr.day + nowTr.month;
  final raw =
      '$sum'
      '00';
  return raw.padLeft(4, '0');
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
          ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
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
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.45)),
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
        'Grafik yüklenemedi.',
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
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
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
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
                          color: AppTheme.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.45),
                          ),
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
                                        ?.copyWith(color: AppTheme.textMuted),
                                  ),
                                ),
                                Text(
                                  _relativeTime(items[i].createdAt),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(color: AppTheme.textMuted),
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
                          color: AppTheme.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.45),
                          ),
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
      error: (_, _) => Text(
        'Aktivite akışı yüklenemedi.',
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
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
