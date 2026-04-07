import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
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
import 'dashboard_providers.dart';

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
    final canSeeTileTotalCustomers =
        ref.watch(hasActionAccessProvider(kActionDashboardTotalCustomers));
    final canSeeTileOpenWorkOrders =
        ref.watch(hasActionAccessProvider(kActionDashboardOpenWorkOrders));
    final canSeeTileInProgressWorkOrders =
        ref.watch(hasActionAccessProvider(kActionDashboardInProgressWorkOrders));
    final canSeeTileTodayWorkOrders =
        ref.watch(hasActionAccessProvider(kActionDashboardTodayWorkOrders));
    final canSeeTileExpiringSoon =
        ref.watch(hasActionAccessProvider(kActionDashboardExpiringSoon));
    final canSeeTileRevenue =
        ref.watch(hasActionAccessProvider(kActionDashboardRevenue));
    final canSeeTileOpenInvoices =
        ref.watch(hasActionAccessProvider(kActionDashboardOpenInvoices));
    final canSeeTileInvoiceQueue =
        ref.watch(hasActionAccessProvider(kActionDashboardInvoiceQueue));
    final canSeeTileLowStock =
        ref.watch(hasActionAccessProvider(kActionDashboardLowStock));

    final seriesAsync = canSeeReports
        ? ref.watch(dashboardRevenueSeriesProvider)
        : const AsyncValue<List<DashboardDailyPoint>>.data([]);
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 0);

    return AppPageLayout(
      title: 'Panel',
      subtitle: 'Genel görünüm, bugün ve yaklaşan işler.',
      body: Stack(
        children: [
          const Positioned.fill(child: IgnorePointer(child: _DashboardBackground())),
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
              child: _MetricsGrid(
                money: money,
                metrics: metricsAsync.value ?? DashboardMetrics.zero(),
                canSeeCustomers: canSeeCustomers,
                canSeeWorkOrders: canSeeWorkOrders,
                canSeeProducts: canSeeProducts,
                canSeeBilling: canSeeBilling,
                canSeeReports: canSeeReports,
                canSeeTileTotalCustomers: canSeeTileTotalCustomers,
                canSeeTileOpenWorkOrders: canSeeTileOpenWorkOrders,
                canSeeTileInProgressWorkOrders: canSeeTileInProgressWorkOrders,
                canSeeTileTodayWorkOrders: canSeeTileTodayWorkOrders,
                canSeeTileExpiringSoon: canSeeTileExpiringSoon,
                canSeeTileRevenue: canSeeTileRevenue,
                canSeeTileOpenInvoices: canSeeTileOpenInvoices,
                canSeeTileInvoiceQueue: canSeeTileInvoiceQueue,
                canSeeTileLowStock: canSeeTileLowStock,
              ),
            ),
            const Gap(12),
            const _BankPasswordsCard(),
            const Gap(12),
            const _ExchangeRatesCard(),
            const Gap(16),
            LayoutBuilder(
              builder: (context, constraints) {
                final twoCols = constraints.maxWidth >= 980;

              final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
              final revenueBgTop =
                  Color.alphaBlend(AppTheme.success.withValues(alpha: 0.14), surface);
              final revenueBgBottom =
                  Color.alphaBlend(AppTheme.success.withValues(alpha: 0.06), surface);

              final revenueCard = AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppTheme.radiusMd),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [revenueBgTop, revenueBgBottom],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.success.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppTheme.success.withValues(alpha: 0.26),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.show_chart_rounded,
                                  size: 18,
                                  color: AppTheme.success,
                                ),
                              ),
                              const Gap(10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Gelir (Son 14 Gün)',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Gap(2),
                                    Text(
                                      'Ödemeler üzerinden günlük toplam.',
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
                          const Gap(16),
                          SizedBox(
                            height: 240,
                            child: seriesAsync.when(
                              data: (points) => _RevenueChart(points: points),
                              loading: () => const _ChartSkeleton(),
                              error: (_, _) => const _ChartError(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              final statusBgTop =
                  Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.14), surface);
              final statusBgBottom =
                  Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.06), surface);

              final workOrderStatusCard = AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppTheme.radiusMd),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [statusBgTop, statusBgBottom],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.primary.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppTheme.primary.withValues(alpha: 0.26),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.assignment_rounded,
                                  size: 18,
                                  color: AppTheme.primary,
                                ),
                              ),
                              const Gap(10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'İş Emri Durumu',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Gap(2),
                                    Text(
                                      'Açık, devam eden ve tamamlanan işler.',
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
                          const Gap(16),
                          SizedBox(
                            height: 160,
                            child: metricsAsync.when(
                              data: (m) => _WorkOrderPieChart(metrics: m),
                              loading: () => const _ChartSkeleton(),
                              error: (_, _) => const _ChartError(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );

              final activityBgTop =
                  Color.alphaBlend(AppTheme.warning.withValues(alpha: 0.12), surface);
              final activityBgBottom =
                  Color.alphaBlend(AppTheme.warning.withValues(alpha: 0.05), surface);

              final activityCard = AppCard(
                padding: EdgeInsets.zero,
                child: ClipRRect(
                  borderRadius: const BorderRadius.all(
                    Radius.circular(AppTheme.radiusMd),
                  ),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [activityBgTop, activityBgBottom],
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: AppTheme.warning.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: AppTheme.warning.withValues(alpha: 0.26),
                                  ),
                                ),
                                child: const Icon(
                                  Icons.bolt_rounded,
                                  size: 18,
                                  color: AppTheme.warning,
                                ),
                              ),
                              const Gap(10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'Son Aktiviteler',
                                      style: Theme.of(context).textTheme.titleMedium,
                                    ),
                                    const Gap(2),
                                    Text(
                                      'İş emirleri ve servis kayıtları.',
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
                          const Gap(14),
                          const _ActivityTimeline(),
                        ],
                      ),
                    ),
                  ),
                ),
              );

                if (!twoCols) {
                  return Column(
                    children: [
                      if (canSeeReports) revenueCard,
                      if (canSeeReports && canSeeWorkOrders) const Gap(16),
                      if (canSeeWorkOrders) workOrderStatusCard,
                      if ((canSeeWorkOrders || canSeeService) &&
                          (canSeeReports || canSeeWorkOrders)) const Gap(16),
                      if (canSeeWorkOrders || canSeeService) activityCard,
                    ],
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child:
                          canSeeReports ? revenueCard : const SizedBox.shrink(),
                    ),
                    const Gap(16),
                    Expanded(
                      flex: 2,
                      child: Column(
                        children: [
                          if (canSeeWorkOrders) workOrderStatusCard,
                          if (canSeeWorkOrders &&
                              (canSeeWorkOrders || canSeeService))
                            const Gap(16),
                          if (canSeeWorkOrders || canSeeService) activityCard,
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
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
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 980;
    return Stack(
      children: [
        Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppTheme.backgroundAlt.withValues(alpha: 0.92),
                  AppTheme.background,
                  AppTheme.background,
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: -180,
          right: isWide ? -120 : -160,
          child: Container(
            width: isWide ? 520 : 420,
            height: isWide ? 520 : 420,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.primary.withValues(alpha: 0.22),
                  AppTheme.primary.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          top: 120,
          left: isWide ? -140 : -180,
          child: Container(
            width: isWide ? 520 : 440,
            height: isWide ? 520 : 440,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.accent.withValues(alpha: 0.18),
                  AppTheme.accent.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          bottom: -220,
          left: isWide ? 180 : 40,
          child: Container(
            width: isWide ? 620 : 520,
            height: isWide ? 620 : 520,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  AppTheme.warning.withValues(alpha: 0.12),
                  AppTheme.warning.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ExchangeRatesCard extends ConsumerWidget {
  const _ExchangeRatesCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(dashboardHalkbankRatesProvider);
    final format = NumberFormat('#,##0.0000', 'tr_TR');
    final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
    final bgTop = Color.alphaBlend(AppTheme.warning.withValues(alpha: 0.14), surface);
    final bgBottom = Color.alphaBlend(AppTheme.warning.withValues(alpha: 0.06), surface);

    String subtitleFromRates(DashboardExchangeRates rates) {
      if (rates.items.isEmpty) return 'Halkbank • USD, EUR, GBP';
      final parts = rates.items.map((r) {
        final value = format.format(r.selling);
        return '${r.code}: $value';
      }).join(' • ');
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
                              : DateFormat('d MMM y HH:mm', 'tr_TR')
                                  .format(AppTime.toTr(rates.fetchedAt!));
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Güncelleme: $updatedText',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                              const Gap(12),
                              if (rates.items.isEmpty)
                                const Text('Kur bilgisi alınamadı.')
                              else
                                Column(
                                  children: [
                                    for (final r in rates.items)
                                      Padding(
                                        padding: const EdgeInsets.only(bottom: 8),
                                        child: Row(
                                          children: [
                                            SizedBox(
                                              width: 56,
                                              child: Text(
                                                r.code,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleSmall,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                'Alış: ${format.format(r.buying)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium,
                                              ),
                                            ),
                                            Expanded(
                                              child: Text(
                                                'Satış: ${format.format(r.selling)}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyMedium
                                                    ?.copyWith(fontWeight: FontWeight.w700),
                                              ),
                                            ),
                                            SizedBox(
                                              width: 52,
                                              child: Text(
                                                (r.time ?? '').trim().isEmpty ? '—' : r.time!,
                                                textAlign: TextAlign.end,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(color: const Color(0xFF64748B)),
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
                        error: (err, st) => const Text('Kur bilgisi alınamadı.'),
                      );
                    },
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () async {
                      final url = ratesAsync.value?.sourceUrl ?? 'https://kur.doviz.com/halkbank';
                      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
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
        child: ClipRRect(
          borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusMd)),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [bgTop, bgBottom],
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AppTheme.warning.withValues(alpha: 0.26)),
                    ),
                    child: const Icon(
                      Icons.currency_exchange_rounded,
                      size: 18,
                      color: AppTheme.warning,
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Döviz Kurları',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(2),
                        Text(
                          ratesAsync.when(
                            data: subtitleFromRates,
                            loading: () => 'Halkbank • yükleniyor…',
                            error: (err, st) => 'Halkbank • USD, EUR, GBP',
                          ),
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.open_in_new_rounded, color: Color(0xFF94A3B8)),
                ],
              ),
            ),
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
    final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
    final bgTop = Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.14), surface);
    final bgMid = Color.alphaBlend(AppTheme.accent.withValues(alpha: 0.08), surface);
    final bgBottom = Color.alphaBlend(AppTheme.primary.withValues(alpha: 0.06), surface);
    return AppCard(
      padding: EdgeInsets.zero,
      onTap: () => _showBankPicker(context),
      child: ClipRRect(
        borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusMd)),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [bgTop, bgMid, bgBottom],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.primary.withValues(alpha: 0.26)),
                  ),
                  child: const Icon(
                    Icons.lock_rounded,
                    size: 18,
                    color: AppTheme.primary,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Banka Şifreleri',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Gap(2),
                      Text(
                        'İş Bankası / Garanti Bankası',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: Color(0xFF94A3B8)),
              ],
            ),
          ),
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
                leading: const Icon(Icons.account_balance_rounded),
                title: const Text('İş Bankası'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showPassword(context, _BankPasswordType.isbank);
                },
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_rounded),
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
    final title = type == _BankPasswordType.isbank ? 'İş Bankası' : 'Garanti Bankası';
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
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                password,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.2,
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
  final raw = '$sum' '00';
  return raw.padLeft(4, '0');
}

class _MetricsGrid extends StatelessWidget {
  const _MetricsGrid({
    required this.metrics,
    required this.money,
    required this.canSeeCustomers,
    required this.canSeeWorkOrders,
    required this.canSeeProducts,
    required this.canSeeBilling,
    required this.canSeeReports,
    required this.canSeeTileTotalCustomers,
    required this.canSeeTileOpenWorkOrders,
    required this.canSeeTileInProgressWorkOrders,
    required this.canSeeTileTodayWorkOrders,
    required this.canSeeTileExpiringSoon,
    required this.canSeeTileRevenue,
    required this.canSeeTileOpenInvoices,
    required this.canSeeTileInvoiceQueue,
    required this.canSeeTileLowStock,
  });

  final DashboardMetrics metrics;
  final NumberFormat money;
  final bool canSeeCustomers;
  final bool canSeeWorkOrders;
  final bool canSeeProducts;
  final bool canSeeBilling;
  final bool canSeeReports;
  final bool canSeeTileTotalCustomers;
  final bool canSeeTileOpenWorkOrders;
  final bool canSeeTileInProgressWorkOrders;
  final bool canSeeTileTodayWorkOrders;
  final bool canSeeTileExpiringSoon;
  final bool canSeeTileRevenue;
  final bool canSeeTileOpenInvoices;
  final bool canSeeTileInvoiceQueue;
  final bool canSeeTileLowStock;

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
        final spacing = 12.0;
        final itemWidth = (width - (columns - 1) * spacing) / columns;

        final items = <_MetricTile>[
          if (canSeeCustomers && canSeeTileTotalCustomers)
            _MetricTile(
              title: 'Toplam Müşteri',
              value: metrics.totalCustomers.toString(),
              icon: Icons.people_alt_rounded,
              onTap: () => context.go('/musteriler'),
            ),
          if (canSeeWorkOrders && canSeeTileOpenWorkOrders)
            _MetricTile(
              title: 'Açık İş Emirleri',
              value: metrics.openWorkOrders.toString(),
              icon: Icons.assignment_rounded,
              tone: metrics.openWorkOrders > 0
                  ? _MetricTone.warning
                  : _MetricTone.neutral,
              onTap: () => context.go('/is-emirleri'),
            ),
          if (canSeeWorkOrders && canSeeTileInProgressWorkOrders)
            _MetricTile(
              title: 'Devam Eden',
              value: metrics.inProgressWorkOrders.toString(),
              icon: Icons.timelapse_rounded,
              tone: _MetricTone.primary,
              onTap: () => context.go('/is-emirleri'),
            ),
          if (canSeeWorkOrders && canSeeTileTodayWorkOrders)
            _MetricTile(
              title: 'Bugünkü İşler',
              value: metrics.todayWorkOrders.toString(),
              icon: Icons.today_rounded,
              onTap: () => context.go('/is-emirleri'),
            ),
          if (canSeeProducts && canSeeTileExpiringSoon)
            _MetricTile(
              title: 'Süresi Dolanlar',
              value: metrics.expiringSoon.toString(),
              icon: Icons.warning_rounded,
              tone: metrics.expiringSoon > 0
                  ? _MetricTone.warning
                  : _MetricTone.neutral,
              onTap: () => context.go('/urunler'),
            ),
          if (canSeeReports && canSeeTileRevenue)
            _MetricTile(
              title: 'Gelir (Bu Ay)',
              value: money.format(metrics.revenue),
              icon: Icons.payments_rounded,
              tone: _MetricTone.success,
              subtitle: revenueChangeText,
              subtitleColor:
                  revenueChange >= 0 ? AppTheme.success : AppTheme.error,
              onTap: () => context.go('/raporlar'),
            ),
          if (canSeeBilling && canSeeTileOpenInvoices)
            _MetricTile(
              title: 'Açık Faturalar',
              value: metrics.openInvoices.toString(),
              icon: Icons.receipt_long_rounded,
              subtitle: money.format(metrics.totalInvoiceAmount),
              onTap: () => context.go('/faturalama'),
            ),
          if (canSeeBilling && canSeeTileInvoiceQueue)
            _MetricTile(
              title: 'Fatura Kuyruğu',
              value: metrics.invoiceQueuePending.toString(),
              icon: Icons.receipt_rounded,
              tone: metrics.invoiceQueuePending > 0
                  ? _MetricTone.warning
                  : _MetricTone.neutral,
              onTap: () => context.go('/faturalama'),
            ),
          if (canSeeProducts && canSeeTileLowStock)
            _MetricTile(
              title: 'Düşük Stok',
              value: metrics.lowStockProducts.toString(),
              icon: Icons.inventory_2_rounded,
              tone: metrics.lowStockProducts > 0
                  ? _MetricTone.warning
                  : _MetricTone.success,
              onTap: () => context.go('/urunler'),
            ),
        ];

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: AppCard(
                  padding: EdgeInsets.zero,
                  onTap: item.onTap,
                  child: item,
                ),
              ),
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
    this.onTap,
  });

  final String title;
  final String value;
  final IconData icon;
  final _MetricTone tone;
  final String? subtitle;
  final Color? subtitleColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final accent = switch (tone) {
      _MetricTone.primary => AppTheme.primary,
      _MetricTone.warning => AppTheme.warning,
      _MetricTone.success => AppTheme.success,
      _MetricTone.neutral => const Color(0xFF0F172A),
    };

    final surface = Theme.of(context).cardTheme.color ?? AppTheme.surface;
    final bgTop = Color.alphaBlend(accent.withValues(alpha: 0.16), surface);
    final bgBottom = Color.alphaBlend(accent.withValues(alpha: 0.08), surface);

    return ClipRRect(
      borderRadius: const BorderRadius.all(Radius.circular(AppTheme.radiusMd)),
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [bgTop, bgBottom],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: accent.withValues(alpha: 0.26)),
                    ),
                    child: Icon(icon, size: 18, color: accent),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ),
                  if (onTap != null)
                    const Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: Color(0xFF94A3B8),
                    ),
                ],
              ),
              const Gap(12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    value,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontSize: 24,
                          letterSpacing: -0.4,
                        ),
                  ),
                  if (subtitle != null) ...[
                    const Gap(8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: (subtitleColor ?? const Color(0xFF64748B))
                            .withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: (subtitleColor ?? const Color(0xFF64748B))
                              .withValues(alpha: 0.18),
                        ),
                      ),
                      child: Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: subtitleColor ?? const Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _MetricTone { primary, warning, success, neutral }

class _WorkOrderPieChart extends StatelessWidget {
  const _WorkOrderPieChart({required this.metrics});

  final DashboardMetrics metrics;

  @override
  Widget build(BuildContext context) {
    final total = metrics.openWorkOrders + metrics.inProgressWorkOrders + metrics.completedWorkOrders;
    
    if (total == 0) {
      return Center(
        child: Text(
          'İş emri kaydı yok.',
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: const Color(0xFF64748B)),
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
            _LegendItem(color: AppTheme.warning, label: 'Açık', value: metrics.openWorkOrders),
            const Gap(8),
            _LegendItem(color: AppTheme.primary, label: 'Devam', value: metrics.inProgressWorkOrders),
            const Gap(8),
            _LegendItem(color: AppTheme.success, label: 'Tamamlanan', value: metrics.completedWorkOrders),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label, required this.value});

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
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
              ),
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
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF64748B)),
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
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF64748B)),
          );
        }

        return Column(
          children: [
            for (int i = 0; i < items.length; i++)
              Padding(
                padding: EdgeInsets.only(bottom: i == items.length - 1 ? 0 : 12),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
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
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF64748B),
                                        ),
                                  ),
                                ),
                                Text(
                                  _relativeTime(items[i].createdAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: const Color(0xFF94A3B8)),
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
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
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
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: const Color(0xFF64748B)),
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
