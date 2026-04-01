import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart' if (dart.library.io) 'io_download_helper.dart';

class CustomerCompactViewNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final customerCompactViewProvider =
    NotifierProvider<CustomerCompactViewNotifier, bool>(
  CustomerCompactViewNotifier.new,
);

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportCustomers() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışarı aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final response = await apiClient.getJson(
      '/customers',
      queryParameters: {'export': 'true', 'showPassive': 'true'},
    );
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    final book = excel.Excel.createExcel();
    final sheet = book.tables[book.getDefaultSheet()]!;

    excel.CellValue textCell(Object? value) =>
        excel.TextCellValue((value ?? '').toString());

    sheet.appendRow([
      textCell('id'),
      textCell('name'),
      textCell('city'),
      textCell('address'),
      textCell('director_name'),
      textCell('email'),
      textCell('vkn'),
      textCell('tckn_ms'),
      textCell('phone_1_title'),
      textCell('phone_1'),
      textCell('phone_2_title'),
      textCell('phone_2'),
      textCell('phone_3_title'),
      textCell('phone_3'),
      textCell('notes'),
      textCell('is_active'),
      textCell('created_at'),
    ]);

    for (final row in items) {
      sheet.appendRow([
        textCell(row['id']),
        textCell(row['name']),
        textCell(row['city']),
        textCell(row['address']),
        textCell(row['director_name']),
        textCell(row['email']),
        textCell(row['vkn']),
        textCell(row['tckn_ms']),
        textCell(row['phone_1_title']),
        textCell(row['phone_1']),
        textCell(row['phone_2_title']),
        textCell(row['phone_2']),
        textCell(row['phone_3_title']),
        textCell(row['phone_3']),
        textCell(row['notes']),
        textCell(row['is_active']),
        textCell(row['created_at']),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'musteriler.xlsx');
  }

  Future<void> _importCustomers() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final book = excel.Excel.decodeBytes(bytes);
    final sheetName = book.tables.keys.isEmpty ? null : book.tables.keys.first;
    if (sheetName == null) return;
    final table = book.tables[sheetName];
    final rows = table?.rows ?? const [];
    if (rows.length < 2) return;

    final header = rows.first
        .map((c) => (c?.value ?? '').toString().trim().toLowerCase())
        .toList(growable: false);
    int indexOf(String key) => header.indexOf(key);
    String cellString(List<excel.Data?> row, String key) {
      final idx = indexOf(key);
      if (idx < 0 || idx >= row.length) return '';
      return (row[idx]?.value ?? '').toString().trim();
    }

    bool cellBool(List<excel.Data?> row, String key) {
      final raw = cellString(row, key).toLowerCase();
      if (raw == 'true' || raw == '1' || raw == 'aktif') return true;
      if (raw == 'false' || raw == '0' || raw == 'pasif') return false;
      return true;
    }

    int imported = 0;
    for (final row in rows.skip(1)) {
      final id = cellString(row, 'id');
      final name = cellString(row, 'name');
      if (name.isEmpty) continue;
      final values = <String, dynamic>{
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'city': cellString(row, 'city').isEmpty ? null : cellString(row, 'city'),
        'address':
            cellString(row, 'address').isEmpty ? null : cellString(row, 'address'),
        'director_name': cellString(row, 'director_name').isEmpty
            ? null
            : cellString(row, 'director_name'),
        'email': cellString(row, 'email').isEmpty ? null : cellString(row, 'email'),
        'vkn': cellString(row, 'vkn').isEmpty ? null : cellString(row, 'vkn'),
        'tckn_ms':
            cellString(row, 'tckn_ms').isEmpty ? null : cellString(row, 'tckn_ms'),
        'phone_1_title': cellString(row, 'phone_1_title').isEmpty
            ? null
            : cellString(row, 'phone_1_title'),
        'phone_1':
            cellString(row, 'phone_1').isEmpty ? null : cellString(row, 'phone_1'),
        'phone_2_title': cellString(row, 'phone_2_title').isEmpty
            ? null
            : cellString(row, 'phone_2_title'),
        'phone_2':
            cellString(row, 'phone_2').isEmpty ? null : cellString(row, 'phone_2'),
        'phone_3_title': cellString(row, 'phone_3_title').isEmpty
            ? null
            : cellString(row, 'phone_3_title'),
        'phone_3':
            cellString(row, 'phone_3').isEmpty ? null : cellString(row, 'phone_3'),
        'notes': cellString(row, 'notes').isEmpty ? null : cellString(row, 'notes'),
        'is_active': cellBool(row, 'is_active'),
      };

      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'customers',
          'values': values,
        },
      );
      imported += 1;
    }

    ref.invalidate(customersProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('İçe aktarıldı: $imported')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive =
        ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDelete =
        ref.watch(hasActionAccessProvider(kActionDeleteRecords));

    final filters = ref.watch(customerFiltersProvider);
    final pageDataAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);
    final page = ref.watch(customerPageProvider);
    final sort = ref.watch(customerSortProvider);
    final showPassive = ref.watch(customerShowPassiveProvider);
    final compactView = ref.watch(customerCompactViewProvider);

    final nextSearch = filters.search;
    if (_searchController.text != nextSearch) {
      _searchController.text = nextSearch;
      _searchController.selection =
          TextSelection.collapsed(offset: nextSearch.length);
    }

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Müşteri kayıtlarını filtreleyin, görüntüleyin ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(customersProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        PopupMenuButton<String>(
          tooltip: 'Aktar',
          onSelected: (value) async {
            switch (value) {
              case 'export':
                await _exportCustomers();
                break;
              case 'import':
                await _importCustomers();
                break;
              default:
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'export', child: Text('Dışarı Aktar (Excel)')),
            PopupMenuItem(value: 'import', child: Text('İçeri Aktar (Excel)')),
          ],
          child: const SizedBox(
            width: 44,
            height: 40,
            child: Center(child: Icon(Icons.swap_vert_rounded)),
          ),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: canEdit
              ? () async {
                  final id = await showCreateCustomerDialog(context);
                  if (id == null || !context.mounted) return;
                  ref.invalidate(customersProvider);
                  context.go('/musteriler/$id');
                }
              : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton.tonalIcon(
                  onPressed: () =>
                      ref.read(customerCompactViewProvider.notifier).toggle(),
                  icon: Icon(
                    compactView
                        ? Icons.view_agenda_rounded
                        : Icons.view_compact_alt_rounded,
                    size: 18,
                  ),
                  label: Text(compactView ? 'Geniş Görünüm' : 'Sık Görünüm'),
                  style: FilledButton.styleFrom(
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.12),
                    foregroundColor: AppTheme.primaryDark,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) {
                      ref.read(customerFiltersProvider.notifier).setSearch(value);
                      ref.read(customerPageProvider.notifier).reset();
                    },
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Ara',
                    ),
                  ),
                ),
                citiesAsync.when(
                  data: (cities) => _PillDropdown<String?>(
                    value: filters.city,
                    items: [
                      const DropdownMenuItem(value: null, child: Text('Şehir: Tümü')),
                      for (final c in cities)
                        DropdownMenuItem(value: c, child: Text(c)),
                    ],
                    onChanged: (value) {
                      ref.read(customerFiltersProvider.notifier).setCity(value);
                      ref.read(customerPageProvider.notifier).reset();
                    },
                    backgroundColor:
                        const Color(0xFF16A34A).withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFF14532D),
                    icon: Icons.location_city_rounded,
                    labelBuilder: (value) => Text(
                      'Şehir: ${value?.trim().isNotEmpty ?? false ? value!.trim() : 'Tümü'}',
                    ),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (_, _) => const SizedBox.shrink(),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref
                        .read(customerShowPassiveProvider.notifier)
                        .set(!showPassive);
                    ref.read(customerPageProvider.notifier).reset();
                  },
                  icon: const Icon(Icons.circle_rounded, size: 12),
                  label: Text(showPassive ? 'Durum: Tümü' : 'Durum: Aktif'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFF4C1D95),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
                _PillDropdown<CustomerSortOption>(
                  value: sort,
                  items: const [
                    DropdownMenuItem(
                      value: CustomerSortOption.id,
                      child: Text('Sıralama: En eski'),
                    ),
                    DropdownMenuItem(
                      value: CustomerSortOption.nameAsc,
                      child: Text('Sıralama: A-Z'),
                    ),
                    DropdownMenuItem(
                      value: CustomerSortOption.nameDesc,
                      child: Text('Sıralama: Z-A'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ref.read(customerSortProvider.notifier).set(value);
                  },
                  backgroundColor:
                      const Color(0xFFF59E0B).withValues(alpha: 0.12),
                  foregroundColor: const Color(0xFF7C2D12),
                  icon: Icons.sort_rounded,
                  labelBuilder: (value) => Text(
                    switch (value ?? CustomerSortOption.id) {
                      CustomerSortOption.id => 'Sıralama: En eski',
                      CustomerSortOption.nameAsc => 'Sıralama: A-Z',
                      CustomerSortOption.nameDesc => 'Sıralama: Z-A',
                    },
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () {
                    ref.read(customerFiltersProvider.notifier).setSearch('');
                    ref.read(customerFiltersProvider.notifier).setCity(null);
                    ref.read(customerShowPassiveProvider.notifier).set(false);
                    ref.read(customerSortProvider.notifier).set(
                          CustomerSortOption.id,
                        );
                    ref.read(customerPageProvider.notifier).reset();
                    ref.invalidate(customersProvider);
                  },
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: const Text('Temizle'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFFEF4444).withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFF7F1D1D),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          Expanded(
            child: pageDataAsync.when(
              data: (pageData) {
                if (pageData.items.isEmpty) {
                  return const EmptyStateCard(
                    icon: Icons.people_alt_rounded,
                    title: 'Müşteri yok',
                    message: 'Filtrelere uygun müşteri bulunamadı.',
                  );
                }

                return _CustomersTable(
                  items: pageData.items,
                  isAdmin: isAdmin,
                  canEdit: canEdit,
                  canArchive: canArchive,
                  canDelete: canDelete,
                  compact: compactView,
                  page: pageData.page,
                  totalPages: pageData.totalPages,
                  totalCount: pageData.totalCount,
                  hasNextPage: pageData.hasNextPage,
                  onPrevious: page <= 1
                      ? null
                      : () => ref.read(customerPageProvider.notifier).previous(),
                  onNext: pageData.hasNextPage
                      ? () => ref.read(customerPageProvider.notifier).next()
                      : null,
                  onChanged: () => ref.invalidate(customersProvider),
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (error, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Müşteri listesi yüklenemedi: $error',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PillDropdown<T> extends StatelessWidget {
  const _PillDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.labelBuilder,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final Widget Function(T? value) labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          isDense: true,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: foregroundColor),
          dropdownColor: AppTheme.surface,
          selectedItemBuilder: (context) {
            return items
                .map(
                  (item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: foregroundColor),
                      const Gap(8),
                      DefaultTextStyle(
                        style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: foregroundColor) ??
                            const TextStyle(),
                        child: labelBuilder(item.value),
                      ),
                    ],
                  ),
                )
                .toList(growable: false);
          },
        ),
      ),
    );
  }
}

class _CustomersTable extends StatelessWidget {
  const _CustomersTable({
    required this.items,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.compact,
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.hasNextPage,
    required this.onPrevious,
    required this.onNext,
    required this.onChanged,
  });

  final List<Customer> items;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final bool compact;
  final int page;
  final int totalPages;
  final int totalCount;
  final bool hasNextPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 54.0 : 62.0;

    return Column(
      children: [
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusMd),
                    ),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 36, child: _TableHeaderCheckbox()),
                      const SizedBox(width: 360, child: _TableHeaderCell('Ad')),
                      const SizedBox(width: 140, child: _TableHeaderCell('VKN')),
                      const SizedBox(width: 140, child: _TableHeaderCell('Şehir')),
                      const SizedBox(width: 90, child: _TableHeaderCell('Hat')),
                      const SizedBox(width: 90, child: _TableHeaderCell('Lisans')),
                      const SizedBox(width: 120, child: _TableHeaderCell('Durum')),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      return _CustomerTableRow(
                        height: rowHeight,
                        customer: items[index],
                        isAdmin: isAdmin,
                        canEdit: canEdit,
                        canArchive: canArchive,
                        canDelete: canDelete,
                        onChanged: onChanged,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(
                'Toplam $totalCount kayıt',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Önceki'),
              ),
              const Gap(10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '$page / $totalPages',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Gap(10),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Sonraki'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
          ),
    );
  }
}

class _TableHeaderCheckbox extends StatelessWidget {
  const _TableHeaderCheckbox();

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: false,
      onChanged: null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _CustomerTableRow extends StatelessWidget {
  const _CustomerTableRow({
    required this.height,
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final double height;
  final Customer customer;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final initials = customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p.characters.first.toUpperCase())
        .join();

    final vkn = customer.vkn?.trim();
    final city = customer.city?.trim();

    return InkWell(
      onTap: () => context.go('/musteriler/${customer.id}'),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Checkbox(
                value: false,
                onChanged: null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            SizedBox(
              width: 360,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
                    foregroundColor: AppTheme.primaryDark,
                    child: Text(
                      initials.isEmpty ? 'M' : initials,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.text,
                              ),
                        ),
                        if (vkn != null && vkn.isNotEmpty)
                          Text(
                            'VKN: $vkn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                vkn == null || vkn.isEmpty ? '-' : vkn,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                city == null || city.isEmpty ? '-' : city.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                customer.activeLineCount.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                customer.activeGmp3Count.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: customer.isActive
                    ? const AppBadge(
                        label: 'Aktif',
                        tone: AppBadgeTone.success,
                      )
                    : const AppBadge(
                        label: 'Pasif',
                        tone: AppBadgeTone.neutral,
                      ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 44,
              child: _CustomerRowActions(
                customer: customer,
                isAdmin: isAdmin,
                canEdit: canEdit,
                canArchive: canArchive,
                canDelete: canDelete,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRowActions extends ConsumerWidget {
  const _CustomerRowActions({
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final Customer customer;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.watch(apiClientProvider);

    return PopupMenuButton<String>(
      tooltip: 'İşlemler',
      onSelected: (value) async {
        switch (value) {
          case 'open':
            context.go('/musteriler/${customer.id}');
            break;
          case 'edit':
            if (!canEdit) break;
            await showEditCustomerDialog(
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
                locations: const [],
              ),
            );
            onChanged();
            break;
          case 'toggle':
            if (!canArchive || apiClient == null) break;
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'customers',
                'filters': [
                  {'col': 'id', 'op': 'eq', 'value': customer.id},
                ],
                'values': {'is_active': !customer.isActive},
              },
            );
            onChanged();
            break;
          case 'delete':
            if (!canDelete || apiClient == null) break;
            await apiClient.postJson(
              '/mutate',
              body: {'op': 'delete', 'table': 'customers', 'id': customer.id},
            );
            onChanged();
            break;
          default:
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'open', child: Text('Detayı Aç')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
        if (canArchive)
          PopupMenuItem(
            value: 'toggle',
            child: Text(customer.isActive ? 'Pasife Al' : 'Aktifleştir'),
          ),
        if (!customer.isActive && canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Kalıcı Sil')),
      ],
      child: const Icon(Icons.more_horiz_rounded),
    );
  }
}
