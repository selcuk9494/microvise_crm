import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import '../../design_system/ds_kpi_tile.dart';
import 'reports_models.dart';
import 'reports_providers.dart';
import 'reports_widgets.dart';

class ReportsScreen extends ConsumerWidget {
  const ReportsScreen({super.key, this.section = ReportsSection.overview});

  final ReportsSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(reportsFiltersProvider);
    final usersAsync = ref.watch(reportsUsersProvider);
    final dataAsync = ref.watch(reportsDataProvider);
    final rangeLabel =
        '${DateFormat('dd.MM.yyyy').format(filters.from)} – ${DateFormat('dd.MM.yyyy').format(filters.to)}';

    return AppPageLayout(
      title: 'Raporlar',
      subtitle: 'Tüm CRM modülleri · $rangeLabel',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(reportsDataProvider);
            ref.invalidate(reportsUsersProvider);
          },
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.only(bottom: 108),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppCard(
            padding: const EdgeInsets.all(14),
            child: _FiltersBar(filters: filters, usersAsync: usersAsync),
          ),
          const Gap(12),
          _SectionNav(section: section),
          const Gap(14),
          dataAsync.when(
            data: (data) => _ReportsBody(section: section, data: data),
            loading: () => Skeletonizer(
              enabled: true,
              child: Column(
                children: [
                  ReportKpiGrid(
                    items: List.generate(
                      4,
                      (_) => DsKpiTile(
                        label: 'Yükleniyor',
                        value: '—',
                        icon: LucideIcons.loader,
                        accentColor: AppTheme.primary,
                      ),
                    ),
                  ),
                  const Gap(14),
                  const AppCard(child: SizedBox(height: 240)),
                ],
              ),
            ),
            error: (error, _) => EmptyStateCard(
              icon: LucideIcons.cloudOff,
              title: 'Raporlar yüklenemedi',
              message: error.toString().replaceFirst('Exception: ', ''),
              action: OutlinedButton.icon(
                onPressed: () => ref.invalidate(reportsDataProvider),
                icon: const Icon(LucideIcons.refreshCw, size: 16),
                label: const Text('Tekrar Dene'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FiltersBar extends ConsumerWidget {
  const _FiltersBar({required this.filters, required this.usersAsync});

  final ReportsFilters filters;
  final AsyncValue<List<ReportUser>> usersAsync;

  Future<void> _pickCustom(BuildContext context, WidgetRef ref) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      initialDateRange: DateTimeRange(start: filters.from, end: filters.to),
      locale: const Locale('tr', 'TR'),
    );
    if (range == null) return;
    ref.read(reportsFiltersProvider.notifier).setCustomRange(range.start, range.end);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wrap = constraints.maxWidth < 900;
        final dateField = SizedBox(
          width: wrap ? double.infinity : 220,
          child: DropdownButtonFormField<ReportsPreset>(
            initialValue: filters.preset,
            items: const [
              DropdownMenuItem(
                value: ReportsPreset.last7Days,
                child: Text('Son 7 gün'),
              ),
              DropdownMenuItem(
                value: ReportsPreset.last30Days,
                child: Text('Son 30 gün'),
              ),
              DropdownMenuItem(
                value: ReportsPreset.thisMonth,
                child: Text('Bu ay'),
              ),
              DropdownMenuItem(
                value: ReportsPreset.lastMonth,
                child: Text('Geçen ay'),
              ),
              DropdownMenuItem(
                value: ReportsPreset.thisYear,
                child: Text('Bu yıl'),
              ),
              DropdownMenuItem(
                value: ReportsPreset.custom,
                child: Text('Özel aralık'),
              ),
            ],
            onChanged: (v) async {
              if (v == null) return;
              if (v == ReportsPreset.custom) {
                await _pickCustom(context, ref);
                return;
              }
              ref.read(reportsFiltersProvider.notifier).setPreset(v);
            },
            decoration: const InputDecoration(labelText: 'Tarih aralığı'),
          ),
        );
        final userField = SizedBox(
          width: wrap ? double.infinity : 260,
          child: usersAsync.when(
            data: (users) => DropdownButtonFormField<String>(
              initialValue: filters.userId,
              items: [
                const DropdownMenuItem<String>(
                  value: null,
                  child: Text('Tüm personel'),
                ),
                ...users
                    .where((u) => u.role != 'admin' && u.role != 'bank' && u.role != 'bank_admin')
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
            loading: () => const Skeletonizer(
              enabled: true,
              child: InputDecorator(
                decoration: InputDecoration(labelText: 'Personel'),
                child: Text('Yükleniyor'),
              ),
            ),
            error: (_, _) => DropdownButtonFormField<String>(
              initialValue: filters.userId,
              items: const [
                DropdownMenuItem<String>(
                  value: null,
                  child: Text('Tüm personel'),
                ),
              ],
              onChanged: (v) =>
                  ref.read(reportsFiltersProvider.notifier).setUser(v),
              decoration: const InputDecoration(labelText: 'Personel'),
            ),
          ),
        );

        if (wrap) {
          return Column(
            children: [
              dateField,
              const Gap(10),
              userField,
              if (filters.preset == ReportsPreset.custom) ...[
                const Gap(10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () => _pickCustom(context, ref),
                    icon: const Icon(LucideIcons.calendar, size: 16),
                    label: Text(
                      '${DateFormat('dd.MM.yyyy').format(filters.from)} – ${DateFormat('dd.MM.yyyy').format(filters.to)}',
                    ),
                  ),
                ),
              ],
            ],
          );
        }

        return Row(
          children: [
            dateField,
            const Gap(12),
            userField,
            if (filters.preset == ReportsPreset.custom) ...[
              const Gap(12),
              TextButton.icon(
                onPressed: () => _pickCustom(context, ref),
                icon: const Icon(LucideIcons.calendar, size: 16),
                label: Text(
                  '${DateFormat('dd.MM.yyyy').format(filters.from)} – ${DateFormat('dd.MM.yyyy').format(filters.to)}',
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

class _SectionNav extends StatelessWidget {
  const _SectionNav({required this.section});

  final ReportsSection section;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final item in ReportsSection.values)
          FilterChip(
            selected: item == section,
            avatar: Icon(reportsSectionIcon(item), size: 16),
            label: Text(item.label),
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => context.go('/raporlar/${item.path}'),
          ),
      ],
    );
  }
}

class _ReportsBody extends StatelessWidget {
  const _ReportsBody({required this.section, required this.data});

  final ReportsSection section;
  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    return switch (section) {
      ReportsSection.overview => _OverviewSection(data: data),
      ReportsSection.invoices => _InvoicesSection(data: data),
      ReportsSection.collections => _CollectionsSection(data: data),
      ReportsSection.quotes => _QuotesSection(data: data),
      ReportsSection.customers => _CustomersSection(data: data),
      ReportsSection.stock => _StockSection(data: data),
      ReportsSection.workOrders => _WorkOrdersSection(data: data),
      ReportsSection.service => _ServiceSection(data: data),
      ReportsSection.forms => _FormsSection(data: data),
      ReportsSection.finance => _FinanceSection(data: data),
      ReportsSection.personnel => _PersonnelSection(data: data),
    };
  }
}

class _OverviewSection extends StatelessWidget {
  const _OverviewSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    final sales = fillDailySeries(
      from: data.from,
      to: data.to,
      raw: data.salesSeries,
    );
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Satış cirosu',
              value: reportMoney.format(k.salesAmount),
              icon: LucideIcons.trendingUp,
              accentColor: AppTheme.primary,
              subtitle: '${k.salesCount} fatura',
              sparkline: null,
              trendPercent: reportTrend(k.salesAmount, k.prevSalesAmount),
            ),
            DsKpiTile(
              label: 'Cari tahsilat',
              value: reportMoney.format(k.collectionsAmount),
              icon: LucideIcons.banknote,
              accentColor: AppTheme.success,
              subtitle: '${k.collectionsCount} hareket',
              trendPercent: reportTrend(
                k.collectionsAmount,
                k.prevCollectionsAmount,
              ),
            ),
            DsKpiTile(
              label: 'Açık alacak',
              value: reportMoney.format(k.receivableAmount),
              icon: LucideIcons.circleAlert,
              accentColor: AppTheme.warning,
              subtitle: '${k.receivableCount} fatura',
            ),
            DsKpiTile(
              label: 'Teklif dönüşümü',
              value: '%${k.quoteConversionRate.toStringAsFixed(0)}',
              icon: LucideIcons.fileCheck,
              accentColor: AppTheme.accent,
              subtitle: '${k.quoteWonCount}/${k.quoteCount} onay',
            ),
            DsKpiTile(
              label: 'Yeni cari',
              value: '${k.customersNew}',
              icon: LucideIcons.userPlus,
              accentColor: AppTheme.primary,
              subtitle: '${k.customersActive} aktif',
            ),
            DsKpiTile(
              label: 'İş emri',
              value: '${k.workOrdersCreated}',
              icon: LucideIcons.clipboardList,
              accentColor: AppTheme.primaryDark,
              subtitle: '${k.workOrdersDone} tamam',
              trendPercent: reportTrend(
                k.workOrdersCreated,
                k.prevWorkOrdersCreated,
              ),
            ),
            DsKpiTile(
              label: 'Servis',
              value: '${k.serviceCount}',
              icon: LucideIcons.wrench,
              accentColor: AppTheme.warning,
              subtitle: reportMoney.format(k.serviceAmount),
            ),
            DsKpiTile(
              label: 'Sanal POS',
              value: reportMoney.format(k.posCollected),
              icon: LucideIcons.creditCard,
              accentColor: AppTheme.success,
              subtitle: '${k.posPendingCount} bekleyen',
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Günlük satış cirosu',
            subtitle: 'Dönem içi satış faturaları (iptal/taslak hariç).',
            child: ReportTrendChart(
              points: sales,
              color: AppTheme.primary,
              emptyLabel: 'Bu aralıkta satış faturası yok.',
            ),
          ),
          right: ReportSectionCard(
            title: 'Günlük tahsilat',
            subtitle: 'Cari tahsilat hareketleri.',
            child: ReportTrendChart(
              points: fillDailySeries(
                from: data.from,
                to: data.to,
                raw: data.collectionsSeries,
              ),
              color: AppTheme.success,
              emptyLabel: 'Bu aralıkta tahsilat yok.',
            ),
          ),
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'En yüksek ciro cariler',
            subtitle: 'Satış faturalarına göre.',
            child: ReportRankedList(
              items: data.invoiceTopCustomers,
              empty: 'Bu aralıkta satış yok.',
            ),
          ),
          right: ReportSectionCard(
            title: 'Modül özeti',
            child: _ModuleSnapshot(kpis: k),
          ),
        ),
      ],
    );
  }
}

class _ModuleSnapshot extends StatelessWidget {
  const _ModuleSnapshot({required this.kpis});

  final ReportsKpis kpis;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('Alış faturaları', '${kpis.purchaseCount} · ${reportMoney.format(kpis.purchaseAmount)}'),
      ('İş emri tahsilatı', '${kpis.paymentsCount} · ${reportMoney.format(kpis.paymentsAmount)}'),
      ('KDV (satış / alış)', '${reportMoney.format(kpis.salesVat)} / ${reportMoney.format(kpis.purchaseVat)}'),
      ('Açık borç', '${kpis.payableCount} · ${reportMoney.format(kpis.payableAmount)}'),
      ('Teklif tutarı', reportMoney.format(kpis.quoteAmount)),
      ('Stok / düşük stok', '${kpis.products} / ${kpis.lowStock}'),
      ('Hat stoğu (boş / çıkan)', '${kpis.linesAvailable} / ${kpis.linesConsumed}'),
      ('Süresi dolacak hat / lisans', '${kpis.linesExpiring} / ${kpis.licensesExpiring}'),
      ('Tekrarlayan plan', '${kpis.recurringPlans} · ${reportMoney.format(kpis.recurringMonthly)}/ay'),
      ('Başvuru / hurda / arıza / devir', '${kpis.applications} / ${kpis.scraps} / ${kpis.faults} / ${kpis.transfers}'),
      ('Mutabakat kaydı', '${kpis.mutakabat}'),
      ('Finans giriş / çıkış', '${reportMoney.format(kpis.financeIn)} / ${reportMoney.format(kpis.financeOut)}'),
    ];
    return Column(
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    row.$1,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Flexible(
                  child: Text(
                    row.$2,
                    textAlign: TextAlign.right,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
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

class _InvoicesSection extends StatelessWidget {
  const _InvoicesSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Satış',
              value: reportMoney.format(k.salesAmount),
              icon: LucideIcons.arrowUpRight,
              accentColor: AppTheme.success,
              subtitle: '${k.salesCount} fatura',
              trendPercent: reportTrend(k.salesAmount, k.prevSalesAmount),
            ),
            DsKpiTile(
              label: 'Alış',
              value: reportMoney.format(k.purchaseAmount),
              icon: LucideIcons.arrowDownLeft,
              accentColor: AppTheme.warning,
              subtitle: '${k.purchaseCount} fatura',
            ),
            DsKpiTile(
              label: 'Hesaplanan KDV',
              value: reportMoney.format(k.salesVat),
              icon: LucideIcons.percent,
              accentColor: AppTheme.primary,
              subtitle: 'Satış faturaları',
            ),
            DsKpiTile(
              label: 'İndirilecek KDV',
              value: reportMoney.format(k.purchaseVat),
              icon: LucideIcons.percent,
              accentColor: AppTheme.primaryDark,
              subtitle: 'Alış faturaları',
            ),
            DsKpiTile(
              label: 'Tahsil edilen',
              value: reportMoney.format(k.salesPaid),
              icon: LucideIcons.circleCheck,
              accentColor: AppTheme.success,
              subtitle: 'Satış faturaları üzerinde',
            ),
            DsKpiTile(
              label: 'Kalan alacak',
              value: reportMoney.format(k.receivableAmount),
              icon: LucideIcons.clock,
              accentColor: AppTheme.warning,
              subtitle: '${k.receivableCount} açık/kısmi',
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Satış faturası durumu',
            child: ReportStatusBars(
              items: data.invoiceByStatus,
              colorOf: (e) => statusColor(e.key),
              labelOf: (e) => invoiceStatusLabel(e.key),
            ),
          ),
          right: ReportSectionCard(
            title: 'E-fatura durumu',
            child: ReportBreakdownTable(
              rows: data.invoiceByEStatus,
              labelOf: (e) => eInvoiceStatusLabel(e.key),
            ),
          ),
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Ciroya göre cariler',
            child: ReportRankedList(items: data.invoiceTopCustomers),
          ),
          right: ReportSectionCard(
            title: 'En çok satılan kalemler',
            child: ReportRankedList(
              items: data.invoiceTopProducts,
              valueBuilder: (e) =>
                  '${e.qty.toStringAsFixed(e.qty % 1 == 0 ? 0 : 1)} · ${reportMoney.format(e.amount)}',
              empty: 'Fatura kalemi yok.',
            ),
          ),
        ),
        const Gap(14),
        ReportSectionCard(
          title: 'Satış / alış kırılımı',
          child: ReportBreakdownTable(
            rows: data.invoiceByType,
            labelOf: (e) => invoiceTypeLabel(e.key),
          ),
        ),
      ],
    );
  }
}

class _CollectionsSection extends StatelessWidget {
  const _CollectionsSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Cari tahsilat',
              value: reportMoney.format(k.collectionsAmount),
              icon: LucideIcons.wallet,
              accentColor: AppTheme.success,
              subtitle: '${k.collectionsCount} hareket',
              trendPercent: reportTrend(
                k.collectionsAmount,
                k.prevCollectionsAmount,
              ),
            ),
            DsKpiTile(
              label: 'İş emri tahsilatı',
              value: reportMoney.format(k.paymentsAmount),
              icon: LucideIcons.banknote,
              accentColor: AppTheme.primary,
              subtitle: '${k.paymentsCount} kayıt',
              trendPercent: reportTrend(k.paymentsAmount, k.prevPaymentsAmount),
            ),
            DsKpiTile(
              label: 'POS tahsil',
              value: reportMoney.format(k.posCollected),
              icon: LucideIcons.creditCard,
              accentColor: AppTheme.accent,
              subtitle: '${k.posCount} link',
            ),
            DsKpiTile(
              label: 'POS bekleyen',
              value: reportMoney.format(k.posPending),
              icon: LucideIcons.clock,
              accentColor: AppTheme.warning,
              subtitle: '${k.posPendingCount} adet',
            ),
            DsKpiTile(
              label: 'Tekrarlayan plan',
              value: '${k.recurringPlans}',
              icon: LucideIcons.repeat,
              accentColor: AppTheme.primaryDark,
              subtitle: '${reportMoney.format(k.recurringMonthly)} / ay',
            ),
            DsKpiTile(
              label: 'Dönem koşuları',
              value: '${k.recurringRuns}',
              icon: LucideIcons.play,
              accentColor: AppTheme.success,
              subtitle: 'Tekrarlayan faturalar',
            ),
          ],
        ),
        const Gap(14),
        ReportSectionCard(
          title: 'Günlük tahsilat eğrisi',
          child: ReportTrendChart(
            points: fillDailySeries(
              from: data.from,
              to: data.to,
              raw: data.collectionsSeries.isNotEmpty
                  ? data.collectionsSeries
                  : data.paymentsSeries,
            ),
            color: AppTheme.success,
          ),
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Ödeme yöntemi',
            subtitle: 'İş emri tahsilatları.',
            child: ReportBreakdownTable(
              rows: data.paymentByMethod,
              labelOf: (e) => paymentMethodLabel(e.key),
            ),
          ),
          right: ReportSectionCard(
            title: 'En çok tahsil edilen cariler',
            child: ReportRankedList(items: data.paymentTopCustomers),
          ),
        ),
      ],
    );
  }
}

class _QuotesSection extends StatelessWidget {
  const _QuotesSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Teklif tutarı',
              value: reportMoney.format(k.quoteAmount),
              icon: LucideIcons.fileText,
              accentColor: AppTheme.primary,
              subtitle: '${k.quoteCount} teklif',
              trendPercent: reportTrend(k.quoteAmount, k.prevQuoteAmount),
            ),
            DsKpiTile(
              label: 'Onaylanan',
              value: reportMoney.format(k.quoteWonAmount),
              icon: LucideIcons.badgeCheck,
              accentColor: AppTheme.success,
              subtitle: '${k.quoteWonCount} adet',
            ),
            DsKpiTile(
              label: 'Dönüşüm',
              value: '%${k.quoteConversionRate.toStringAsFixed(1).replaceAll('.', ',')}',
              icon: LucideIcons.percent,
              accentColor: AppTheme.accent,
              subtitle: '${k.quoteConvertedCount} faturaya döndü',
            ),
            DsKpiTile(
              label: 'Reddedilen',
              value: '${k.quoteLostCount}',
              icon: LucideIcons.fileX,
              accentColor: AppTheme.error,
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Teklif durumu',
            child: ReportStatusBars(
              items: data.quoteByStatus,
              colorOf: (e) => statusColor(e.key),
              labelOf: (e) => quoteStatusLabel(e.key),
            ),
          ),
          right: ReportSectionCard(
            title: 'Teklif tutarına göre cariler',
            child: ReportRankedList(items: data.quoteTopCustomers),
          ),
        ),
      ],
    );
  }
}

class _CustomersSection extends StatelessWidget {
  const _CustomersSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Aktif cari',
              value: '${k.customersActive}',
              icon: LucideIcons.users,
              accentColor: AppTheme.primary,
              subtitle: '${k.customersTotal} toplam',
            ),
            DsKpiTile(
              label: 'Yeni cari',
              value: '${k.customersNew}',
              icon: LucideIcons.userPlus,
              accentColor: AppTheme.success,
              subtitle: 'Seçilen aralık',
            ),
            DsKpiTile(
              label: 'Açık alacak',
              value: reportMoney.format(k.receivableAmount),
              icon: LucideIcons.arrowUpCircle,
              accentColor: AppTheme.warning,
              subtitle: '${k.receivableCount} fatura',
            ),
            DsKpiTile(
              label: 'Açık borç',
              value: reportMoney.format(k.payableAmount),
              icon: LucideIcons.arrowDownCircle,
              accentColor: AppTheme.error,
              subtitle: '${k.payableCount} fatura',
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'İllere göre cariler',
            child: ReportRankedList(
              items: data.customersByCity,
              valueBuilder: (e) => '${e.count}',
            ),
          ),
          right: ReportSectionCard(
            title: 'Ciro sıralaması',
            child: ReportRankedList(items: data.invoiceTopCustomers),
          ),
        ),
      ],
    );
  }
}

class _StockSection extends StatelessWidget {
  const _StockSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Ürün / hizmet',
              value: '${k.products}',
              icon: LucideIcons.package,
              accentColor: AppTheme.primary,
            ),
            DsKpiTile(
              label: 'Düşük stok',
              value: '${k.lowStock}',
              icon: LucideIcons.triangleAlert,
              accentColor: AppTheme.warning,
            ),
            DsKpiTile(
              label: 'Boş hat stoğu',
              value: '${k.linesAvailable}',
              icon: LucideIcons.smartphone,
              accentColor: AppTheme.success,
              subtitle: '${k.linesConsumed} dönemde çıktı',
            ),
            DsKpiTile(
              label: '30 gün içinde dolacak',
              value: '${k.linesExpiring + k.licensesExpiring}',
              icon: LucideIcons.calendar,
              accentColor: AppTheme.error,
              subtitle: '${k.linesExpiring} hat · ${k.licensesExpiring} lisans',
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Kritik stok',
            subtitle: 'Mevcut / asgari.',
            child: ReportRankedList(
              items: data.lowStock,
              valueBuilder: (e) =>
                  '${e.qty.toStringAsFixed(0)} / ${e.amount.toStringAsFixed(0)}',
              empty: 'Düşük stok yok.',
            ),
          ),
          right: ReportSectionCard(
            title: 'Satılan kalemler',
            child: ReportRankedList(
              items: data.invoiceTopProducts,
              valueBuilder: (e) =>
                  '${e.qty.toStringAsFixed(e.qty % 1 == 0 ? 0 : 1)} adet',
              empty: 'Satış kalemi yok.',
            ),
          ),
        ),
      ],
    );
  }
}

class _WorkOrdersSection extends StatelessWidget {
  const _WorkOrdersSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Açılan',
              value: '${k.workOrdersCreated}',
              icon: LucideIcons.clipboardList,
              accentColor: AppTheme.primary,
              trendPercent: reportTrend(
                k.workOrdersCreated,
                k.prevWorkOrdersCreated,
              ),
            ),
            DsKpiTile(
              label: 'Açık',
              value: '${k.workOrdersOpen}',
              icon: LucideIcons.circle,
              accentColor: AppTheme.warning,
            ),
            DsKpiTile(
              label: 'Devam',
              value: '${k.workOrdersInProgress}',
              icon: LucideIcons.loader,
              accentColor: AppTheme.primaryDark,
            ),
            DsKpiTile(
              label: 'Tamam',
              value: '${k.workOrdersDone}',
              icon: LucideIcons.check,
              accentColor: AppTheme.success,
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Durum dağılımı',
            child: ReportStatusBars(
              items: data.workOrderByStatus,
              colorOf: (e) => statusColor(e.key),
              labelOf: (e) => workOrderStatusLabel(e.key),
            ),
          ),
          right: ReportSectionCard(
            title: 'Personele göre',
            child: Column(
              children: [
                if (data.workOrderByUser.isEmpty)
                  Text(
                    'Kayıt yok.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  )
                else
                  for (final row in data.workOrderByUser)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              row.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${row.open} açık · ${row.inProgress} devam · ${row.done} tamam',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ServiceSection extends StatelessWidget {
  const _ServiceSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Servis kaydı',
              value: '${k.serviceCount}',
              icon: LucideIcons.wrench,
              accentColor: AppTheme.primary,
            ),
            DsKpiTile(
              label: 'Servis tutarı',
              value: reportMoney.format(k.serviceAmount),
              icon: LucideIcons.coins,
              accentColor: AppTheme.success,
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Servis durumu',
            child: ReportStatusBars(
              items: data.serviceByStatus,
              colorOf: (e) => statusColor(e.key),
              labelOf: (e) => serviceStatusLabel(e.key),
            ),
          ),
          right: ReportSectionCard(
            title: 'Öncelik',
            child: ReportBreakdownTable(
              rows: data.serviceByPriority,
              labelOf: (e) => servicePriorityLabel(e.key),
              showAmount: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _FormsSection extends StatelessWidget {
  const _FormsSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Banka başvurusu',
              value: '${k.applications}',
              icon: LucideIcons.filePlus,
              accentColor: AppTheme.primary,
            ),
            DsKpiTile(
              label: 'Hurda',
              value: '${k.scraps}',
              icon: LucideIcons.recycle,
              accentColor: AppTheme.warning,
            ),
            DsKpiTile(
              label: 'Arıza',
              value: '${k.faults}',
              icon: LucideIcons.wrench,
              accentColor: AppTheme.error,
            ),
            DsKpiTile(
              label: 'Devir',
              value: '${k.transfers}',
              icon: LucideIcons.arrowLeftRight,
              accentColor: AppTheme.success,
            ),
            DsKpiTile(
              label: 'Mutabakat',
              value: '${k.mutakabat}',
              icon: LucideIcons.scale,
              accentColor: AppTheme.accent,
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Başvuru markaları',
            child: ReportRankedList(
              items: data.applicationByBrand,
              valueBuilder: (e) => '${e.count}',
            ),
          ),
          right: ReportSectionCard(
            title: 'İç onay durumu',
            child: ReportBreakdownTable(
              rows: data.applicationByApproval,
              labelOf: (e) => formApprovalLabel(e.key),
              showAmount: false,
            ),
          ),
        ),
      ],
    );
  }
}

class _FinanceSection extends StatelessWidget {
  const _FinanceSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final k = data.kpis;
    return Column(
      children: [
        ReportKpiGrid(
          items: [
            DsKpiTile(
              label: 'Giriş',
              value: reportMoney.format(k.financeIn),
              icon: LucideIcons.arrowDown,
              accentColor: AppTheme.success,
            ),
            DsKpiTile(
              label: 'Çıkış',
              value: reportMoney.format(k.financeOut),
              icon: LucideIcons.arrowUp,
              accentColor: AppTheme.error,
            ),
            DsKpiTile(
              label: 'Net',
              value: reportMoney.format(k.financeIn - k.financeOut),
              icon: LucideIcons.scale,
              accentColor: AppTheme.primary,
              subtitle: '${k.financeCount} hareket',
            ),
            DsKpiTile(
              label: 'Açık alacak',
              value: reportMoney.format(k.receivableAmount),
              icon: LucideIcons.wallet,
              accentColor: AppTheme.warning,
            ),
          ],
        ),
        const Gap(14),
        ReportTwoCol(
          left: ReportSectionCard(
            title: 'Hesap bakiyeleri',
            child: data.financeAccounts.isEmpty
                ? Text(
                    'CRM finans hesabı yok.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  )
                : Column(
                    children: [
                      for (final a in data.financeAccounts)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      a.label,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(fontWeight: FontWeight.w600),
                                    ),
                                    Text(
                                      a.type == 'cash' ? 'Kasa' : 'Banka',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppTheme.textMuted),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                reportMoneyExact.format(a.amount),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
          ),
          right: ReportSectionCard(
            title: 'Hareket tipi',
            child: ReportBreakdownTable(
              rows: data.financeByType,
              labelOf: (e) => e.key,
            ),
          ),
        ),
      ],
    );
  }
}

class _PersonnelSection extends StatelessWidget {
  const _PersonnelSection({required this.data});

  final SystemReports data;

  @override
  Widget build(BuildContext context) {
    final people = [...data.personnel]
      ..sort((a, b) {
        final scoreA = a.workOrders + a.invoices + a.quotes + a.services;
        final scoreB = b.workOrders + b.invoices + b.quotes + b.services;
        return scoreB.compareTo(scoreA);
      });

    return Column(
      children: [
        ReportSectionCard(
          title: 'Personel performansı',
          subtitle:
              'Seçilen aralıkta atanan iş emirleri, kesilen faturalar, teklifler ve servisler.',
          child: people.isEmpty
              ? Text(
                  'Personel kaydı yok.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                )
              : SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: DataTable(
                    headingTextStyle: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textMuted,
                        ),
                    dataTextStyle: Theme.of(context).textTheme.bodyMedium,
                    columns: const [
                      DataColumn(label: Text('Personel')),
                      DataColumn(label: Text('İş emri'), numeric: true),
                      DataColumn(label: Text('Tamam'), numeric: true),
                      DataColumn(label: Text('Servis'), numeric: true),
                      DataColumn(label: Text('Fatura'), numeric: true),
                      DataColumn(label: Text('Teklif'), numeric: true),
                      DataColumn(label: Text('Tahsilat'), numeric: true),
                    ],
                    rows: [
                      for (final p in people)
                        DataRow(
                          cells: [
                            DataCell(Text(p.name)),
                            DataCell(Text('${p.workOrders}')),
                            DataCell(Text('${p.workOrdersDone}')),
                            DataCell(Text('${p.services}')),
                            DataCell(Text('${p.invoices}')),
                            DataCell(Text('${p.quotes}')),
                            DataCell(Text(reportMoney.format(p.payments))),
                          ],
                        ),
                    ],
                  ),
                ),
        ),
      ],
    );
  }
}
