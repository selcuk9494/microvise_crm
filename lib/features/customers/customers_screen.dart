import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/ui/smart_filter_bar.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart'
    if (dart.library.io) 'io_download_helper.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  bool _handledCreateQuery = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_handledCreateQuery) return;
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['yeni'] != '1') return;

    _handledCreateQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.go('/musteriler');
      await _showCustomerForm(context, ref, openDetail: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final customersAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);
    final filters = ref.watch(customerFiltersProvider);
    final currentPage = ref.watch(customerPageProvider);
    final sort = ref.watch(customerSortProvider);
    final showPassive = ref.watch(customerShowPassiveProvider);
    final headerSummary = !isMobile
        ? customersAsync.whenOrNull(
            data: (pageData) =>
                _SummaryRow(customers: pageData.items, compact: true),
          )
        : null;

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle:
          'Müşteri kayıtlarını yönetin, filtreleyin ve yeni müşteri ekleyin.',
      actions: [
        ...(headerSummary != null ? [headerSummary] : const <Widget>[]),
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(customersProvider);
            ref.invalidate(customerCitiesProvider);
            ref.read(customerPageProvider.notifier).reset();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: () => _showCustomerForm(context, ref, openDetail: true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          SmartFilterBar(
            title: 'Filtreler',
            subtitle: isMobile
                ? null
                : 'Müşteri arayın, şehir kırılımı seçin ve veri işlemlerine erişin.',
            trailing: !isMobile
                ? PopupMenuButton<_CustomerDataAction>(
                    tooltip: 'Veri işlemleri',
                    onSelected: (action) {
                      switch (action) {
                        case _CustomerDataAction.template:
                          _downloadCustomerImportTemplate(context);
                        case _CustomerDataAction.export:
                          _exportCustomersToExcel(context, ref);
                        case _CustomerDataAction.import:
                          _importExcel(context, ref);
                      }
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(
                        value: _CustomerDataAction.template,
                        child: Text('Şablon İndir'),
                      ),
                      PopupMenuItem(
                        value: _CustomerDataAction.export,
                        child: Text('Dışa Aktar'),
                      ),
                      PopupMenuItem(
                        value: _CustomerDataAction.import,
                        child: Text('İçe Aktar'),
                      ),
                    ],
                    child: OutlinedButton.icon(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 38),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      icon: const Icon(Icons.unfold_more_rounded, size: 16),
                      label: const Text('Veri'),
                    ),
                  )
                : null,
            footer:
                filters.search.isNotEmpty || filters.city != null || showPassive
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (filters.search.isNotEmpty)
                          AppBadge(
                            label: 'Arama: ${filters.search}',
                            tone: AppBadgeTone.primary,
                          ),
                        if (filters.city != null)
                          AppBadge(
                            label: 'Şehir: ${filters.city}',
                            tone: AppBadgeTone.neutral,
                          ),
                        if (showPassive)
                          const AppBadge(
                            label: 'Pasifler açık',
                            tone: AppBadgeTone.warning,
                          ),
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setSearch('');
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setCity(null);
                            ref
                                .read(customerShowPassiveProvider.notifier)
                                .set(false);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          icon: const Icon(Icons.clear_rounded, size: 16),
                          label: const Text('Temizle'),
                        ),
                      ],
                    ),
                  )
                : null,
            children: [
              if (!isMobile) ...[const SizedBox.shrink()],
              SizedBox(
                width: isMobile ? double.infinity : width * 0.34,
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) {
                    ref.read(customerFiltersProvider.notifier).setSearch(value);
                    ref.read(customerPageProvider.notifier).reset();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Müşteri Ara',
                    hintText: 'Firma adına göre arayın',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                ),
              ),
              SizedBox(
                width: isMobile ? double.infinity : width * 0.19,
                child: citiesAsync.when(
                  data: (cities) => DropdownButtonFormField<String?>(
                    initialValue: filters.city,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Tüm Şehirler'),
                      ),
                      ...cities.map(
                        (city) => DropdownMenuItem<String?>(
                          value: city,
                          child: Text(city),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      ref.read(customerFiltersProvider.notifier).setCity(value);
                      ref.read(customerPageProvider.notifier).reset();
                    },
                    decoration: const InputDecoration(
                      labelText: 'Şehir',
                      prefixIcon: Icon(Icons.location_city_rounded),
                    ),
                  ),
                  loading: () => const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Şehir',
                      prefixIcon: Icon(Icons.location_city_rounded),
                    ),
                  ),
                  error: (error, stackTrace) => const TextField(
                    enabled: false,
                    decoration: InputDecoration(
                      labelText: 'Şehir yüklenemedi',
                      prefixIcon: Icon(Icons.error_outline_rounded),
                    ),
                  ),
                ),
              ),
              SizedBox(
                width: isMobile ? double.infinity : 178,
                child: DropdownButtonFormField<CustomerSortOption>(
                  initialValue: sort,
                  items: const [
                    DropdownMenuItem(
                      value: CustomerSortOption.id,
                      child: Text('ID Numarası'),
                    ),
                    DropdownMenuItem(
                      value: CustomerSortOption.nameAsc,
                      child: Text('A - Z'),
                    ),
                    DropdownMenuItem(
                      value: CustomerSortOption.nameDesc,
                      child: Text('Z - A'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(customerSortProvider.notifier).set(value);
                    ref.read(customerPageProvider.notifier).reset();
                  },
                  decoration: const InputDecoration(
                    labelText: 'Sıralama',
                    prefixIcon: Icon(Icons.sort_by_alpha_rounded),
                  ),
                ),
              ),
              FilterChip(
                selected: showPassive,
                onSelected: (value) {
                  ref.read(customerShowPassiveProvider.notifier).set(value);
                  ref.read(customerPageProvider.notifier).reset();
                },
                label: const Text('Pasifleri Göster'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Gap(10),
          customersAsync.when(
            data: (pageData) {
              final customers = pageData.items;
              if (customers.isEmpty) {
                return EmptyStateCard(
                  icon: Icons.groups_2_rounded,
                  title: 'Henüz müşteri kaydı yok',
                  message:
                      'Yeni müşteri ekleyerek listeyi oluşturmaya başlayın.',
                  action: FilledButton.icon(
                    onPressed: () =>
                        _showCustomerForm(context, ref, openDetail: true),
                    icon: const Icon(Icons.add_rounded, size: 16),
                    label: const Text('İlk Müşteriyi Ekle'),
                  ),
                );
              }

              final totalPages = pageData.totalPages;
              final startPage = (currentPage - 2).clamp(1, totalPages);
              final endPage = (startPage + 4).clamp(1, totalPages);

              return Column(
                children: [
                  if (isMobile) ...[
                    _SummaryRow(customers: customers),
                    const Gap(8),
                  ],
                  AppSectionCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final isCompact = constraints.maxWidth < 980;
                        final summaryText =
                            'Toplam ${pageData.totalCount} müşteri • Sayfa $currentPage / $totalPages • ${customers.length} kayıt gösteriliyor';
                        final pageButtons = Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            OutlinedButton.icon(
                              onPressed: currentPage > 1
                                  ? () => ref
                                        .read(customerPageProvider.notifier)
                                        .previous()
                                  : null,
                              icon: const Icon(
                                Icons.chevron_left_rounded,
                                size: 18,
                              ),
                              label: const Text('Önceki'),
                            ),
                            for (var page = startPage; page <= endPage; page++)
                              page == currentPage
                                  ? FilledButton(
                                      onPressed: null,
                                      child: Text(page.toString()),
                                    )
                                  : OutlinedButton(
                                      onPressed: () => ref
                                          .read(customerPageProvider.notifier)
                                          .set(page),
                                      child: Text(page.toString()),
                                    ),
                            OutlinedButton.icon(
                              onPressed: pageData.hasNextPage
                                  ? () => ref
                                        .read(customerPageProvider.notifier)
                                        .next()
                                  : null,
                              icon: const Icon(
                                Icons.chevron_right_rounded,
                                size: 18,
                              ),
                              label: const Text('Sonraki'),
                            ),
                          ],
                        );

                        if (isCompact) {
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                summaryText,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                              const Gap(6),
                              pageButtons,
                              const Gap(2),
                              TextButton.icon(
                                onPressed: () => _showCustomerForm(
                                  context,
                                  ref,
                                  openDetail: false,
                                ),
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('Hızlı Ekle'),
                              ),
                            ],
                          );
                        }

                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                summaryText,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ),
                            const Gap(10),
                            Flexible(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  pageButtons,
                                  const Gap(2),
                                  TextButton.icon(
                                    onPressed: () => _showCustomerForm(
                                      context,
                                      ref,
                                      openDetail: false,
                                    ),
                                    icon: const Icon(
                                      Icons.add_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Hızlı Ekle'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                  const Gap(4),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const Gap(6),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return _CustomerCard(
                        customer: customer,
                        onChanged: () => _refreshCustomerData(ref),
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Müşteriler yüklenemedi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CustomerDataAction { template, export, import }

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.customers, this.compact = false});

  final List<Customer> customers;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final active = customers.where((customer) => customer.isActive).length;
    final passive = customers.length - active;
    final totalLines = customers.fold<int>(
      0,
      (sum, customer) => sum + customer.activeLineCount,
    );

    final stats = [
      (
        'Toplam',
        customers.length.toString(),
        Icons.groups_2_rounded,
        AppBadgeTone.primary,
      ),
      (
        'Aktif',
        active.toString(),
        Icons.check_circle_outline_rounded,
        AppBadgeTone.success,
      ),
      (
        'Pasif',
        passive.toString(),
        Icons.pause_circle_outline_rounded,
        AppBadgeTone.neutral,
      ),
      (
        'Aktif Hat',
        totalLines.toString(),
        Icons.sim_card_outlined,
        AppBadgeTone.warning,
      ),
    ];

    final content = Wrap(
      spacing: compact ? 6 : 8,
      runSpacing: compact ? 6 : 8,
      children: [
        for (final stat in stats)
          _SummaryStat(
            label: stat.$1,
            value: stat.$2,
            icon: stat.$3,
            tone: stat.$4,
            compact: compact,
          ),
      ],
    );

    if (compact) return content;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: content,
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
    this.compact = false,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.primary => AppTheme.primary,
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => const Color(0xFF64748B),
    };

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 8,
        vertical: compact ? 5 : 6,
      ),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(compact ? 12 : 14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 22 : 26,
            height: compact ? 22 : 26,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(compact ? 7 : 8),
            ),
            child: Icon(icon, color: color, size: compact ? 12 : 14),
          ),
          Gap(compact ? 5 : 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontSize: compact ? 10 : 11,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: compact ? 15 : 16,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.onChanged});

  final Customer customer;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return AppCard(
      padding: const EdgeInsets.all(10),
      onTap: () => context.go('/musteriler/${customer.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppTheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.business_rounded,
                  color: AppTheme.primary,
                  size: 17,
                ),
              ),
              const Gap(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(
                              context,
                            ).textTheme.titleMedium?.copyWith(fontSize: 15),
                          ),
                        ),
                        const Gap(6),
                        AppBadge(
                          label: customer.isActive ? 'Aktif' : 'Pasif',
                          tone: customer.isActive
                              ? AppBadgeTone.success
                              : AppBadgeTone.neutral,
                        ),
                      ],
                    ),
                    const Gap(4),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        if ((customer.city ?? '').trim().isNotEmpty)
                          _MetaChip(
                            icon: Icons.location_on_outlined,
                            label: customer.city!,
                          ),
                        _MetaChip(
                          icon: Icons.sim_card_outlined,
                          label: '${customer.activeLineCount} aktif hat',
                        ),
                        _MetaChip(
                          icon: Icons.verified_outlined,
                          label: '${customer.activeGmp3Count} GMP3',
                        ),
                        if ((customer.phone1 ?? '').trim().isNotEmpty)
                          _MetaChip(
                            icon: Icons.phone_outlined,
                            label: customer.phone1!,
                          ),
                        if (!isMobile &&
                            (customer.email ?? '').trim().isNotEmpty)
                          _MetaChip(
                            icon: Icons.alternate_email_rounded,
                            label: customer.email!,
                          ),
                        if (!isMobile && (customer.vkn ?? '').trim().isNotEmpty)
                          _MetaChip(
                            icon: Icons.badge_outlined,
                            label: 'VKN: ${customer.vkn}',
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_CustomerAction>(
                tooltip: 'Müşteri işlemleri',
                onSelected: (action) async {
                  switch (action) {
                    case _CustomerAction.edit:
                      final updated = await showEditCustomerDialog(
                        context,
                        initialData: CustomerFormData(
                          id: customer.id,
                          name: customer.name,
                          city: customer.city,
                          address: customer.address,
                          directorName: customer.directorName,
                          email: customer.email,
                          vkn: customer.vkn,
                          tcknMs: customer.tcknMs,
                          phone1Title: customer.phone1Title,
                          phone1: customer.phone1,
                          phone2Title: customer.phone2Title,
                          phone2: customer.phone2,
                          phone3Title: customer.phone3Title,
                          phone3: customer.phone3,
                          notes: customer.notes,
                          isActive: customer.isActive,
                        ),
                      );
                      if (updated) {
                        await onChanged();
                      }
                    case _CustomerAction.toggleActive:
                      await _toggleCustomerActive(
                        context,
                        ref,
                        customer: customer,
                      );
                      await onChanged();
                    case _CustomerAction.open:
                      if (context.mounted) {
                        context.go('/musteriler/${customer.id}');
                      }
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: _CustomerAction.open,
                    child: Text('Detaya Git'),
                  ),
                  const PopupMenuItem(
                    value: _CustomerAction.edit,
                    child: Text('Düzenle'),
                  ),
                  PopupMenuItem(
                    value: _CustomerAction.toggleActive,
                    child: Text(customer.isActive ? 'Sil' : 'Aktifleştir'),
                  ),
                ],
                child: const Padding(
                  padding: EdgeInsets.only(left: 2),
                  child: Icon(
                    Icons.more_vert_rounded,
                    color: Color(0xFF94A3B8),
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          if (isMobile &&
              (((customer.email ?? '').trim().isNotEmpty) ||
                  ((customer.vkn ?? '').trim().isNotEmpty))) ...[
            const Gap(6),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if ((customer.email ?? '').trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.alternate_email_rounded,
                    label: customer.email!,
                  ),
                if ((customer.vkn ?? '').trim().isNotEmpty)
                  _MetaChip(
                    icon: Icons.badge_outlined,
                    label: 'VKN: ${customer.vkn}',
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

enum _CustomerAction { open, edit, toggleActive }

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: const Color(0xFF64748B)),
          const Gap(3),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
              fontSize: 10.5,
              height: 1,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCustomerForm(
  BuildContext context,
  WidgetRef ref, {
  required bool openDetail,
}) async {
  final result = await showCreateCustomerDialog(context);

  if (result == null || !context.mounted) return;
  _refreshCustomerData(ref);
  if (openDetail) {
    context.go('/musteriler/$result');
  }
}

Future<void> _refreshCustomerData(WidgetRef ref) async {
  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
}

Future<void> _downloadCustomerImportTemplate(BuildContext context) async {
  try {
    final file = excel.Excel.createExcel();
    final sheet = file['Müşteri Şablonu'];

    sheet.appendRow([
      excel.TextCellValue('Müşteri ID'),
      excel.TextCellValue('Firma Adı'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('Adres'),
      excel.TextCellValue('E-posta'),
      excel.TextCellValue('VKN'),
      excel.TextCellValue('TCKN-MŞ'),
      excel.TextCellValue('Telefon 1 Başlığı'),
      excel.TextCellValue('Telefon 1'),
      excel.TextCellValue('Telefon 2 Başlığı'),
      excel.TextCellValue('Telefon 2'),
      excel.TextCellValue('Telefon 3 Başlığı'),
      excel.TextCellValue('Telefon 3'),
      excel.TextCellValue('Aktif Müşteri'),
      excel.TextCellValue('Notlar'),
    ]);

    sheet.appendRow([
      excel.TextCellValue(''),
      excel.TextCellValue('Microvise Teknoloji'),
      excel.TextCellValue('Istanbul'),
      excel.TextCellValue('Ornek Mah. Ornek Cad. No:1'),
      excel.TextCellValue('info@microvise.com'),
      excel.TextCellValue('1234567890'),
      excel.TextCellValue('MS-1001'),
      excel.TextCellValue('Yetkili'),
      excel.TextCellValue('05551234567'),
      excel.TextCellValue('Muhasebe'),
      excel.TextCellValue('02121234567'),
      excel.TextCellValue('Destek'),
      excel.TextCellValue('08501234567'),
      excel.TextCellValue('Evet'),
      excel.TextCellValue('Ornek musteri kaydi'),
    ]);

    file.delete('Sheet1');

    final bytes = file.encode();
    if (bytes == null) throw Exception('Excel hata');

    downloadExcelFile(bytes, 'musteri_import_sablonu.xlsx');

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Müşteri import şablonu indirildi.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Şablon indirilemedi: $e')));
  }
}

Future<void> _toggleCustomerActive(
  BuildContext context,
  WidgetRef ref, {
  required Customer customer,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final messenger = ScaffoldMessenger.of(context);

  try {
    await client
        .from('customers')
        .update({'is_active': !customer.isActive})
        .eq('id', customer.id);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          customer.isActive
              ? 'Müşteri pasif duruma alındı.'
              : 'Müşteri yeniden aktif edildi.',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
  }
}

// ================= EXPORT =================
Future<void> _exportCustomersToExcel(
  BuildContext context,
  WidgetRef ref,
) async {
  final client = ref.read(supabaseClientProvider);

  if (client == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Supabase bağlantısı yok')));
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final rows = await client.from('customers').select();
    final customers = rows as List;

    final file = excel.Excel.createExcel();
    final sheet = file['Müşteriler'];

    sheet.appendRow([
      excel.TextCellValue('Müşteri ID'),
      excel.TextCellValue('Firma Adı'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('Adres'),
      excel.TextCellValue('E-posta'),
      excel.TextCellValue('VKN'),
      excel.TextCellValue('TCKN-MŞ'),
      excel.TextCellValue('Telefon 1 Başlığı'),
      excel.TextCellValue('Telefon 1'),
      excel.TextCellValue('Telefon 2 Başlığı'),
      excel.TextCellValue('Telefon 2'),
      excel.TextCellValue('Telefon 3 Başlığı'),
      excel.TextCellValue('Telefon 3'),
      excel.TextCellValue('Aktif Müşteri'),
      excel.TextCellValue('Notlar'),
    ]);

    for (final c in customers) {
      sheet.appendRow([
        excel.TextCellValue((c['id'] ?? '').toString()),
        excel.TextCellValue((c['name'] ?? '').toString()),
        excel.TextCellValue((c['city'] ?? '').toString()),
        excel.TextCellValue((c['address'] ?? '').toString()),
        excel.TextCellValue((c['email'] ?? '').toString()),
        excel.TextCellValue((c['vkn'] ?? '').toString()),
        excel.TextCellValue((c['tckn_ms'] ?? '').toString()),
        excel.TextCellValue((c['phone_1_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_1'] ?? '').toString()),
        excel.TextCellValue((c['phone_2_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_2'] ?? '').toString()),
        excel.TextCellValue((c['phone_3_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_3'] ?? '').toString()),
        excel.TextCellValue(
          ((c['is_active'] as bool?) ?? true) ? 'Evet' : 'Hayır',
        ),
        excel.TextCellValue((c['notes'] ?? '').toString()),
      ]);
    }

    file.delete('Sheet1');

    final bytes = file.encode();
    if (bytes == null) throw Exception('Excel hata');

    downloadExcelFile(bytes, 'musteriler.xlsx');

    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${customers.length} kayıt indirildi')),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Hata: $e')));
  }
}

// ================= IMPORT =================
Future<void> _importExcel(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );

  if (result == null) return;

  final bytes = result.files.first.bytes!;
  final excelFile = excel.Excel.decodeBytes(bytes);
  final sheet = excelFile.tables.values.first;
  if (sheet.rows.isEmpty) return;

  final headers = sheet.rows.first
      .map((cell) => cell?.value?.toString().trim().toLowerCase() ?? '')
      .toList(growable: false);

  int columnOf(List<String> keys) {
    for (final key in keys) {
      final index = headers.indexOf(key.toLowerCase());
      if (index != -1) return index;
    }
    return -1;
  }

  String? readText(List<excel.Data?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    final value = row[index]?.value?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool readBool(List<excel.Data?> row, int index) {
    final raw = readText(row, index)?.toLowerCase();
    if (raw == null) return true;
    return raw == 'evet' ||
        raw == 'true' ||
        raw == '1' ||
        raw == 'aktif' ||
        raw == 'yes';
  }

  final nameIndex = columnOf(['firma adı', 'firma', 'name']);
  final idIndex = columnOf(['müşteri id', 'musteri id', 'customer id', 'id']);
  final cityIndex = columnOf(['şehir', 'city']);
  final addressIndex = columnOf(['adres', 'address']);
  final emailIndex = columnOf(['e-posta', 'email']);
  final vknIndex = columnOf(['vkn']);
  final tcknMsIndex = columnOf(['tckn-mş', 'tckn-ms', 'tckn mş', 'tckn ms']);
  final phone1TitleIndex = columnOf(['telefon 1 başlığı', 'phone 1 title']);
  final phone1Index = columnOf(['telefon 1', 'telefon', 'phone 1']);
  final phone2TitleIndex = columnOf(['telefon 2 başlığı', 'phone 2 title']);
  final phone2Index = columnOf(['telefon 2', 'phone 2']);
  final phone3TitleIndex = columnOf(['telefon 3 başlığı', 'phone 3 title']);
  final phone3Index = columnOf(['telefon 3', 'phone 3']);
  final isActiveIndex = columnOf(['aktif müşteri', 'aktif', 'is_active']);
  final notesIndex = columnOf(['notlar', 'not', 'notes']);

  if (nameIndex == -1) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Excel dosyasında Firma Adı kolonu yok.')),
    );
    return;
  }

  String normalize(String? value) => (value ?? '').trim().toLowerCase();

  final existingRows = await client
      .from('customers')
      .select('id,name,city,address,email,vkn,tckn_ms');

  final existingByVkn = <String, String>{};
  final existingByEmail = <String, String>{};
  final existingIds = <String>{};

  for (final row in (existingRows as List)) {
    final map = row as Map<String, dynamic>;
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) continue;
    existingIds.add(id);

    final normalizedVkn = normalize(map['vkn']?.toString());
    final normalizedTcknMs = normalize(map['tckn_ms']?.toString());
    final normalizedEmail = normalize(map['email']?.toString());
    if (normalizedVkn.isNotEmpty) existingByVkn[normalizedVkn] = id;
    if (normalizedTcknMs.isNotEmpty) existingByVkn[normalizedTcknMs] = id;
    if (normalizedEmail.isNotEmpty) existingByEmail[normalizedEmail] = id;
  }

  var createdCount = 0;
  var updatedCount = 0;
  var skippedCount = 0;
  final seenImportKeys = <String>{};

  for (int i = 1; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    final importedId = readText(row, idIndex);
    final name = readText(row, nameIndex);
    if (name == null) {
      skippedCount++;
      continue;
    }

    final city = readText(row, cityIndex);
    final address = readText(row, addressIndex);
    final email = readText(row, emailIndex);
    final vkn = readText(row, vknIndex);
    final tcknMs = readText(row, tcknMsIndex);
    final payload = {
      'name': name,
      'city': city,
      'address': address,
      'email': email,
      'vkn': vkn,
      'tckn_ms': tcknMs,
      'phone_1_title': readText(row, phone1TitleIndex),
      'phone_1': readText(row, phone1Index),
      'phone_2_title': readText(row, phone2TitleIndex),
      'phone_2': readText(row, phone2Index),
      'phone_3_title': readText(row, phone3TitleIndex),
      'phone_3': readText(row, phone3Index),
      'notes': readText(row, notesIndex),
      'is_active': readBool(row, isActiveIndex),
    };

    final normalizedEmail = normalize(email);
    final normalizedVkn = normalize(vkn);
    final normalizedTcknMs = normalize(tcknMs);
    final importKey = importedId != null && importedId.isNotEmpty
        ? 'id:$importedId'
        : normalizedVkn.isNotEmpty
        ? 'vkn:$normalizedVkn'
        : normalizedTcknMs.isNotEmpty
        ? 'tcknms:$normalizedTcknMs'
        : normalizedEmail.isNotEmpty
        ? 'email:$normalizedEmail'
        : 'row:$i';

    if (!seenImportKeys.add(importKey)) {
      skippedCount++;
      continue;
    }

    final existingId =
        (importedId != null && existingIds.contains(importedId)
            ? importedId
            : null) ??
        (normalizedVkn.isNotEmpty ? existingByVkn[normalizedVkn] : null) ??
        (normalizedTcknMs.isNotEmpty
            ? existingByVkn[normalizedTcknMs]
            : null) ??
        (normalizedEmail.isNotEmpty ? existingByEmail[normalizedEmail] : null);

    if (existingId != null) {
      await client.from('customers').update(payload).eq('id', existingId);
      updatedCount++;
      continue;
    }

    final inserted = await client
        .from('customers')
        .insert(payload)
        .select('id')
        .single();
    final insertedId = inserted['id']?.toString();
    if (insertedId == null || insertedId.isEmpty) {
      skippedCount++;
      continue;
    }

    existingIds.add(insertedId);
    if (normalizedVkn.isNotEmpty) {
      existingByVkn[normalizedVkn] = insertedId;
    }
    if (normalizedTcknMs.isNotEmpty) {
      existingByVkn[normalizedTcknMs] = insertedId;
    }
    if (normalizedEmail.isNotEmpty) {
      existingByEmail[normalizedEmail] = insertedId;
    }
    createdCount++;
  }

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$createdCount yeni, $updatedCount güncellendi, $skippedCount atlandı.',
      ),
    ),
  );
}
