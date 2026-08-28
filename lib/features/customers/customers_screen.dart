import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart'
    if (dart.library.io) 'io_download_helper.dart';
import '../products/lines_gmp3_excel.dart';
import '../products/products_screen.dart';

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
        const SnackBar(
          content: Text('Dışarı aktarma web üzerinde desteklenir.'),
        ),
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

  Future<void> _downloadLinesGmp3Template() {
    return downloadLinesGmp3Template(context);
  }

  Future<void> _importLinesAndGmp3() {
    return importLinesAndGmp3Excel(
      context: context,
      ref: ref,
      onImported: () {
        ref.invalidate(issuedLinesProvider);
        ref.invalidate(issuedLicensesProvider);
        ref.invalidate(issuedLicensesStatsProvider);
      },
    );
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
        'city': cellString(row, 'city').isEmpty
            ? null
            : cellString(row, 'city'),
        'address': cellString(row, 'address').isEmpty
            ? null
            : cellString(row, 'address'),
        'director_name': cellString(row, 'director_name').isEmpty
            ? null
            : cellString(row, 'director_name'),
        'email': cellString(row, 'email').isEmpty
            ? null
            : cellString(row, 'email'),
        'vkn': cellString(row, 'vkn').isEmpty ? null : cellString(row, 'vkn'),
        'tckn_ms': cellString(row, 'tckn_ms').isEmpty
            ? null
            : cellString(row, 'tckn_ms'),
        'phone_1_title': cellString(row, 'phone_1_title').isEmpty
            ? null
            : cellString(row, 'phone_1_title'),
        'phone_1': cellString(row, 'phone_1').isEmpty
            ? null
            : cellString(row, 'phone_1'),
        'phone_2_title': cellString(row, 'phone_2_title').isEmpty
            ? null
            : cellString(row, 'phone_2_title'),
        'phone_2': cellString(row, 'phone_2').isEmpty
            ? null
            : cellString(row, 'phone_2'),
        'phone_3_title': cellString(row, 'phone_3_title').isEmpty
            ? null
            : cellString(row, 'phone_3_title'),
        'phone_3': cellString(row, 'phone_3').isEmpty
            ? null
            : cellString(row, 'phone_3'),
        'notes': cellString(row, 'notes').isEmpty
            ? null
            : cellString(row, 'notes'),
        'is_active': cellBool(row, 'is_active'),
      };

      await apiClient.postJson(
        '/mutate',
        body: {'op': 'upsert', 'table': 'customers', 'values': values},
      );
      imported += 1;
    }

    ref.invalidate(customersProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('İçe aktarıldı: $imported')));
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(
      hasActionAccessProvider(kActionArchiveRecords),
    );
    final canDelete = ref.watch(hasActionAccessProvider(kActionDeleteRecords));

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
      _searchController.selection = TextSelection.collapsed(
        offset: nextSearch.length,
      );
    }

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Müşteri kayıtlarını filtreleyin, görüntüleyin ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(customersProvider),
          icon: const Icon(LucideIcons.refreshCw, size: 18),
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
              case 'template_lines_gmp3':
                await _downloadLinesGmp3Template();
                break;
              case 'import_lines_gmp3':
                await _importLinesAndGmp3();
                break;
              default:
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'export', child: Text('Dışarı Aktar (Excel)')),
            PopupMenuItem(value: 'import', child: Text('İçeri Aktar (Excel)')),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'template_lines_gmp3',
              child: Text('Hat & GMP3 Şablon İndir'),
            ),
            PopupMenuItem(
              value: 'import_lines_gmp3',
              child: Text('Hat & GMP3 İçeri Aktar (Excel)'),
            ),
          ],
          child: const SizedBox(
            width: 44,
            height: 40,
            child: Center(child: Icon(LucideIcons.arrowUpDown)),
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
          icon: const Icon(LucideIcons.plus, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Builder(
        builder: (context) {
          void clearFilters({bool popSheet = false}) {
            ref.read(customerFiltersProvider.notifier).setSearch('');
            ref.read(customerFiltersProvider.notifier).setCity(null);
            ref.read(customerShowPassiveProvider.notifier).set(false);
            ref.read(customerSortProvider.notifier).set(CustomerSortOption.id);
            ref.read(customerPageProvider.notifier).reset();
            ref.invalidate(customersProvider);
            if (popSheet && context.mounted) {
              Navigator.of(context).pop();
            }
          }

          InputDecoration filterFieldDecoration({
            String? hintText,
            String? labelText,
            Widget? prefixIcon,
          }) {
            return InputDecoration(
              isDense: true,
              hintText: hintText,
              labelText: labelText,
              prefixIcon: prefixIcon,
              filled: true,
              fillColor: AppTheme.filterControlBg,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            );
          }

          final filterCard = AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: isMobile
                ? citiesAsync.when(
                    data: (cities) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  ref
                                      .read(customerFiltersProvider.notifier)
                                      .setSearch(value);
                                  ref
                                      .read(customerPageProvider.notifier)
                                      .reset();
                                },
                                decoration: filterFieldDecoration(
                                  hintText: 'Müşteri, VKN, telefon…',
                                  prefixIcon: const Icon(
                                    LucideIcons.search,
                                    size: 20,
                                  ),
                                ),
                              ),
                            ),
                            const Gap(8),
                            OutlinedButton(
                              onPressed: () async {
                                await showModalBottomSheet<void>(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (sheetContext) => SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Filtreler',
                                            style: Theme.of(
                                              sheetContext,
                                            ).textTheme.titleMedium,
                                          ),
                                          const Gap(12),
                                          DropdownButtonFormField<String?>(
                                            initialValue: filters.city,
                                            items: [
                                              const DropdownMenuItem(
                                                value: null,
                                                child: Text('Tümü'),
                                              ),
                                              for (final c in cities)
                                                DropdownMenuItem(
                                                  value: c,
                                                  child: Text(c),
                                                ),
                                            ],
                                            onChanged: (value) {
                                              ref
                                                  .read(
                                                    customerFiltersProvider
                                                        .notifier,
                                                  )
                                                  .setCity(value);
                                              ref
                                                  .read(
                                                    customerPageProvider
                                                        .notifier,
                                                  )
                                                  .reset();
                                            },
                                            decoration: filterFieldDecoration(
                                              labelText: 'Şehir',
                                            ),
                                          ),
                                          const Gap(10),
                                          DropdownButtonFormField<bool>(
                                            initialValue: showPassive,
                                            items: const [
                                              DropdownMenuItem(
                                                value: false,
                                                child: Text('Aktif'),
                                              ),
                                              DropdownMenuItem(
                                                value: true,
                                                child: Text('Tümü'),
                                              ),
                                            ],
                                            onChanged: (v) {
                                              if (v == null) return;
                                              ref
                                                  .read(
                                                    customerShowPassiveProvider
                                                        .notifier,
                                                  )
                                                  .set(v);
                                              ref
                                                  .read(
                                                    customerPageProvider
                                                        .notifier,
                                                  )
                                                  .reset();
                                            },
                                            decoration: filterFieldDecoration(
                                              labelText: 'Durum',
                                            ),
                                          ),
                                          const Gap(10),
                                          DropdownButtonFormField<
                                            CustomerSortOption
                                          >(
                                            initialValue: sort,
                                            items: const [
                                              DropdownMenuItem(
                                                value: CustomerSortOption.id,
                                                child: Text('En eski'),
                                              ),
                                              DropdownMenuItem(
                                                value:
                                                    CustomerSortOption.nameAsc,
                                                child: Text('A-Z'),
                                              ),
                                              DropdownMenuItem(
                                                value:
                                                    CustomerSortOption.nameDesc,
                                                child: Text('Z-A'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value == null) return;
                                              ref
                                                  .read(
                                                    customerSortProvider
                                                        .notifier,
                                                  )
                                                  .set(value);
                                            },
                                            decoration: filterFieldDecoration(
                                              labelText: 'Sıralama',
                                            ),
                                          ),
                                          const Gap(14),
                                          SizedBox(
                                            width: double.infinity,
                                            child: OutlinedButton.icon(
                                              onPressed: () =>
                                                  clearFilters(popSheet: true),
                                              icon: const Icon(
                                                LucideIcons.filterX,
                                                size: 18,
                                              ),
                                              label: const Text('Temizle'),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(40, 40),
                                padding: EdgeInsets.zero,
                              ),
                              child: const Icon(
                                LucideIcons.settings2,
                                size: 18,
                              ),
                            ),
                          ],
                        ),
                        if (showPassive ||
                            (filters.city ?? '').trim().isNotEmpty) ...[
                          const Gap(8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (showPassive)
                                const AppBadge(
                                  label: 'Durum: Tümü',
                                  tone: AppBadgeTone.neutral,
                                  dense: true,
                                ),
                              if ((filters.city ?? '').trim().isNotEmpty)
                                AppBadge(
                                  label: (filters.city ?? '').trim(),
                                  tone: AppBadgeTone.primary,
                                  dense: true,
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                  )
                : Row(
                    children: [
                      Tooltip(
                        message: compactView
                            ? 'Geniş satırlar'
                            : 'Sıkı satırlar',
                        child: IconButton(
                          onPressed: () => ref
                              .read(customerCompactViewProvider.notifier)
                              .toggle(),
                          style: IconButton.styleFrom(
                            foregroundColor: AppTheme.textSoft,
                            side: BorderSide(
                              color: AppTheme.border.withValues(alpha: 0.9),
                            ),
                            minimumSize: const Size(40, 40),
                          ),
                          icon: Icon(
                            compactView
                                ? LucideIcons.rows3
                                : LucideIcons.layoutList,
                            size: 18,
                          ),
                        ),
                      ),
                      const Gap(8),
                      Expanded(
                        flex: 3,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setSearch(value);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          decoration: filterFieldDecoration(
                            hintText: 'Müşteri, VKN, telefon…',
                            prefixIcon: const Icon(
                              LucideIcons.search,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                      const Gap(8),
                      SizedBox(
                        width: 150,
                        child: citiesAsync.when(
                          data: (cities) => DropdownButtonFormField<String?>(
                            initialValue: filters.city,
                            isExpanded: true,
                            items: [
                              const DropdownMenuItem(
                                value: null,
                                child: Text('Şehir: Tümü'),
                              ),
                              for (final c in cities)
                                DropdownMenuItem(value: c, child: Text(c)),
                            ],
                            onChanged: (value) {
                              ref
                                  .read(customerFiltersProvider.notifier)
                                  .setCity(value);
                              ref.read(customerPageProvider.notifier).reset();
                            },
                            decoration: filterFieldDecoration(),
                          ),
                          loading: () => const SizedBox.shrink(),
                          error: (_, _) => const SizedBox.shrink(),
                        ),
                      ),
                      const Gap(8),
                      SizedBox(
                        width: 130,
                        child: DropdownButtonFormField<bool>(
                          initialValue: showPassive,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: false,
                              child: Text('Aktif'),
                            ),
                            DropdownMenuItem(value: true, child: Text('Tümü')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            ref
                                .read(customerShowPassiveProvider.notifier)
                                .set(v);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          decoration: filterFieldDecoration(),
                        ),
                      ),
                      const Gap(8),
                      SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<CustomerSortOption>(
                          initialValue: sort,
                          isExpanded: true,
                          items: const [
                            DropdownMenuItem(
                              value: CustomerSortOption.id,
                              child: Text('En eski'),
                            ),
                            DropdownMenuItem(
                              value: CustomerSortOption.nameAsc,
                              child: Text('A-Z'),
                            ),
                            DropdownMenuItem(
                              value: CustomerSortOption.nameDesc,
                              child: Text('Z-A'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value == null) return;
                            ref.read(customerSortProvider.notifier).set(value);
                          },
                          decoration: filterFieldDecoration(),
                        ),
                      ),
                      const Gap(8),
                      OutlinedButton.icon(
                        onPressed: clearFilters,
                        icon: const Icon(LucideIcons.filterX, size: 16),
                        label: const Text('Temizle'),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
          );

          Widget buildDesktop() {
            return Column(
              children: [
                filterCard,
                const Gap(12),
                Expanded(
                  child: pageDataAsync.when(
                    data: (pageData) {
                      if (pageData.items.isEmpty) {
                        return const EmptyStateCard(
                          icon: LucideIcons.users,
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
                            : () => ref
                                  .read(customerPageProvider.notifier)
                                  .previous(),
                        onNext: pageData.hasNextPage
                            ? () =>
                                  ref.read(customerPageProvider.notifier).next()
                            : null,
                        onChanged: () => ref.invalidate(customersProvider),
                      );
                    },
                    loading: () => const _CustomersTableSkeleton(),
                    error: (error, _) => EmptyStateCard(
                      icon: LucideIcons.cloudOff,
                      title: 'Müşteri listesi yüklenemedi',
                      message:
                          'Bağlantı sorunu olabilir. Lütfen tekrar deneyin.',
                      action: OutlinedButton.icon(
                        onPressed: () => ref.invalidate(customersProvider),
                        icon: const Icon(LucideIcons.refreshCw, size: 16),
                        label: const Text('Tekrar Dene'),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          Widget buildMobile() {
            return pageDataAsync.when(
              data: (pageData) {
                final items = pageData.items;

                return ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    filterCard,
                    const Gap(12),
                    if (items.isEmpty)
                      const EmptyStateCard(
                        icon: LucideIcons.users,
                        title: 'Müşteri yok',
                        message: 'Filtrelere uygun müşteri bulunamadı.',
                      )
                    else
                      _CustomersListMobile(
                        items: items,
                        isAdmin: isAdmin,
                        canEdit: canEdit,
                        canArchive: canArchive,
                        canDelete: canDelete,
                        onChanged: () => ref.invalidate(customersProvider),
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                      ),
                    const Gap(12),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: page <= 1
                                  ? null
                                  : () => ref
                                        .read(customerPageProvider.notifier)
                                        .previous(),
                              child: const Text('Önceki'),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pageData.hasNextPage
                                  ? () => ref
                                        .read(customerPageProvider.notifier)
                                        .next()
                                  : null,
                              child: const Text('Sonraki'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  filterCard,
                  const Gap(12),
                  const _CustomersListMobileSkeleton(),
                ],
              ),
              error: (error, _) => ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  filterCard,
                  const Gap(12),
                  EmptyStateCard(
                    icon: LucideIcons.cloudOff,
                    title: 'Müşteri listesi yüklenemedi',
                    message: 'Bağlantı sorunu olabilir. Lütfen tekrar deneyin.',
                    action: OutlinedButton.icon(
                      onPressed: () => ref.invalidate(customersProvider),
                      icon: const Icon(LucideIcons.refreshCw, size: 16),
                      label: const Text('Tekrar Dene'),
                    ),
                  ),
                ],
              ),
            );
          }

          return isMobile ? buildMobile() : buildDesktop();
        },
      ),
    );
  }
}

class _CustomersListMobile extends StatelessWidget {
  const _CustomersListMobile({
    required this.items,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 120),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Customer> items;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: items.length,
      separatorBuilder: (context, index) => const Gap(10),
      itemBuilder: (context, index) {
        final customer = items[index];
        final vkn = customer.vkn?.trim();
        final city = customer.city?.trim();

        return AppCard(
          onTap: () => context.go('/musteriler/${customer.id}'),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
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
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (vkn != null && vkn.isNotEmpty)
                          _MobilePill(text: 'VKN: $vkn'),
                        if (city != null && city.isNotEmpty)
                          _MobilePill(text: city.toUpperCase()),
                        _MobilePill(text: 'Hat: ${customer.activeLineCount}'),
                        _MobilePill(
                          text: 'Lisans: ${customer.activeGmp3Count}',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(10),
              customer.isActive
                  ? const AppBadge(label: 'Aktif', tone: AppBadgeTone.success)
                  : const AppBadge(label: 'Pasif', tone: AppBadgeTone.neutral),
              const Gap(6),
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
        );
      },
    );
  }
}

class _MobilePill extends StatelessWidget {
  const _MobilePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
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
    final rowHeight = compact ? 48.0 : 68.0;

    return Column(
      children: [
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.tableHeaderBg,
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusMd),
                    ),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      const Expanded(
                        flex: 5,
                        child: _TableHeaderCell('Müşteri'),
                      ),
                      const Expanded(
                        flex: 3,
                        child: _TableHeaderCell('İletişim'),
                      ),
                      const Expanded(flex: 2, child: _TableHeaderCell('Şehir')),
                      const SizedBox(width: 72, child: _TableHeaderCell('Hat')),
                      const SizedBox(
                        width: 78,
                        child: _TableHeaderCell('Lisans'),
                      ),
                      const SizedBox(
                        width: 104,
                        child: _TableHeaderCell('Durum'),
                      ),
                      const SizedBox(width: 42),
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
                        index: index,
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
        const Gap(8),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Text(
                'Toplam $totalCount kayıt',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(LucideIcons.chevronLeft),
                label: const Text('Önceki'),
              ),
              const Gap(10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
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
                icon: const Icon(LucideIcons.chevronRight),
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
        color: AppTheme.textSoft,
      ),
    );
  }
}

class _CustomerTableRow extends StatelessWidget {
  const _CustomerTableRow({
    required this.height,
    required this.index,
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final double height;
  final int index;
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
    final phone = customer.phone1?.trim();
    final email = customer.email?.trim();

    return InkWell(
      onTap: () => context.go('/musteriler/${customer.id}'),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: AppDenseList.rowFill(index),
          border: Border(
            bottom: BorderSide(color: AppTheme.border.withValues(alpha: 0.7)),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 5,
              child: Row(
                children: [
                  Container(
                    width: height <= 50 ? 32 : 40,
                    height: height <= 50 ? 32 : 40,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Text(
                      initials.isEmpty ? 'M' : initials,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: AppTheme.primary,
                      ),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.text,
                              ),
                        ),
                        if (vkn != null && vkn.isNotEmpty)
                          Text(
                            'VKN: $vkn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 3,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    phone == null || phone.isEmpty ? '-' : phone,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textSoft,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (email != null && email.isNotEmpty)
                    Text(
                      email,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                city == null || city.isEmpty ? '-' : city.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 72,
              child: _CustomerCountChip(
                value: customer.activeLineCount,
                icon: LucideIcons.creditCard,
              ),
            ),
            SizedBox(
              width: 78,
              child: _CustomerCountChip(
                value: customer.activeGmp3Count,
                icon: LucideIcons.badgeCheck,
              ),
            ),
            SizedBox(
              width: 104,
              child: Align(
                alignment: Alignment.centerLeft,
                child: customer.isActive
                    ? const AppBadge(label: 'Aktif', tone: AppBadgeTone.success)
                    : const AppBadge(
                        label: 'Pasif',
                        tone: AppBadgeTone.neutral,
                      ),
              ),
            ),
            SizedBox(
              width: 42,
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

class _CustomerCountChip extends StatelessWidget {
  const _CustomerCountChip({required this.value, required this.icon});

  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final active = value > 0;
    final color = active ? AppTheme.primary : AppTheme.textMuted;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: active ? 0.10 : 0.06),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.14)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color),
            const Gap(4),
            Text(
              value.toString(),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: FontWeight.w800,
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
                taxOffice: customer.taxOffice,
                address: customer.address,
                countryCode: customer.countryCode,
                country: customer.country,
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
      child: const Icon(LucideIcons.ellipsis),
    );
  }
}

/// Masaüstü tablo yüklenirken gösterilen iskelet — önceden boş bir
/// `SizedBox(height: 240)` kartıydı (içerik yokmuş hissi verip liste
/// yapısını hiç ima etmiyordu). Gerçek satır sayısı/verisi bilinmediği için
/// sabit sayıda placeholder satır çizilir; gerçek veri gelince olduğu gibi
/// `_CustomersTable` ile değişir.
class _CustomersTableSkeleton extends StatelessWidget {
  const _CustomersTableSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < 7; i++) ...[
              Row(
                children: [
                  const CircleAvatar(radius: 16),
                  const Gap(12),
                  Expanded(
                    flex: 3,
                    child: Text(
                      'Örnek Müşteri Adı Soyadı',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'İstanbul',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  const Gap(12),
                  const AppBadge(label: 'Aktif', tone: AppBadgeTone.success),
                ],
              ),
              if (i != 6) const Gap(16),
            ],
          ],
        ),
      ),
    );
  }
}

/// Mobil müşteri listesi yüklenirken gösterilen iskelet — `_CustomersListMobile`
/// kartlarının gerçek şekliyle eşleşir, böylece yükleme sırasında düzen
/// zıplaması olmaz.
class _CustomersListMobileSkeleton extends StatelessWidget {
  const _CustomersListMobileSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: Column(
        children: [
          for (var i = 0; i < 5; i++) ...[
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Örnek Müşteri Adı',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const Gap(6),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: const [
                            _MobilePill(text: 'VKN: 0000000000'),
                            _MobilePill(text: 'İSTANBUL'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const Gap(10),
                  const AppBadge(label: 'Aktif', tone: AppBadgeTone.success),
                ],
              ),
            ),
            if (i != 4) const Gap(10),
          ],
        ],
      ),
    );
  }
}
