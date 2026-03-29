import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/smart_filter_bar.dart';
import '../billing/billing_screen.dart';
import '../billing/invoice_queue_helper.dart';

final productSearchProvider = NotifierProvider<ProductSearchNotifier, String>(
  ProductSearchNotifier.new,
);
final showPassiveProvider = NotifierProvider<ShowPassiveNotifier, bool>(
  ShowPassiveNotifier.new,
);
final productCustomerFilterProvider =
    NotifierProvider<ProductCustomerFilterNotifier, String?>(
      ProductCustomerFilterNotifier.new,
    );
final productSortProvider =
    NotifierProvider<ProductSortNotifier, ProductListSort>(
      ProductSortNotifier.new,
    );
final productQuickFilterProvider =
    NotifierProvider<ProductQuickFilterNotifier, ProductQuickFilter>(
      ProductQuickFilterNotifier.new,
    );
final selectedLineIdsProvider =
    NotifierProvider<SelectedLineIdsNotifier, Set<String>>(
      SelectedLineIdsNotifier.new,
    );
final selectedLicenseIdsProvider =
    NotifierProvider<SelectedLicenseIdsNotifier, Set<String>>(
      SelectedLicenseIdsNotifier.new,
    );

class ProductSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class ShowPassiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class ProductCustomerFilterNotifier extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? value) => state = value;
}

enum ProductListSort { customerName, nearestEndDate, latestEndDate }

enum ProductQuickFilter {
  all,
  expiringSoon,
  expired,
  endingThisMonth,
  noEndDate,
}

class ProductSortNotifier extends Notifier<ProductListSort> {
  @override
  ProductListSort build() => ProductListSort.nearestEndDate;

  void set(ProductListSort value) => state = value;
}

class ProductQuickFilterNotifier extends Notifier<ProductQuickFilter> {
  @override
  ProductQuickFilter build() => ProductQuickFilter.all;

  void set(ProductQuickFilter value) => state = value;
}

class SelectedLineIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id) {
    final next = {...state};
    if (!next.add(id)) {
      next.remove(id);
    }
    state = next;
  }

  void replace(Iterable<String> ids) => state = ids.toSet();

  void clear() => state = <String>{};
}

class SelectedLicenseIdsNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() => <String>{};

  void toggle(String id) {
    final next = {...state};
    if (!next.add(id)) {
      next.remove(id);
    }
    state = next;
  }

  void replace(Iterable<String> ids) => state = ids.toSet();

  void clear() => state = <String>{};
}

final issuedLinesProvider = FutureProvider<List<IssuedLine>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final selectedCustomerId = ref.watch(productCustomerFilterProvider);
  final isAdmin = ref.watch(isAdminProvider);

  var q = client
      .from('lines')
      .select(
        'id,label,number,sim_number,starts_at,ends_at,is_active,customer_id,branch_id,customers(name),branches(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if ((selectedCustomerId ?? '').isNotEmpty) {
    q = q.eq('customer_id', selectedCustomerId!);
  }

  if (search.isNotEmpty) {
    q = q.or('number.ilike.%$search%,sim_number.ilike.%$search%');
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);

  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        final branch = map['branches'] as Map<String, dynamic>?;
        return IssuedLine.fromJson({
          ...map,
          'customer_name': customer?['name'],
          'branch_name': branch?['name'],
        });
      })
      .toList(growable: false);
});

final issuedLicensesProvider = FutureProvider<List<IssuedLicense>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final selectedCustomerId = ref.watch(productCustomerFilterProvider);
  final isAdmin = ref.watch(isAdminProvider);

  var q = client
      .from('licenses')
      .select(
        'id,name,license_type,starts_at,ends_at,is_active,customer_id,customers(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if ((selectedCustomerId ?? '').isNotEmpty) {
    q = q.eq('customer_id', selectedCustomerId!);
  }

  if (search.isNotEmpty) {
    q = q.ilike('name', '%$search%');
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);
  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        return IssuedLicense.fromJson({
          ...map,
          'customer_name': customer?['name'],
        });
      })
      .toList(growable: false);
});

final customersLookupProvider = FutureProvider<List<CustomerLookup>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('customers')
      .select('id,name,is_active')
      .order('name');
  return (rows as List)
      .map((e) => CustomerLookup.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final showPassive = ref.watch(showPassiveProvider);
    final customersAsync = ref.watch(customersLookupProvider);
    final sort = ref.watch(productSortProvider);
    final quickFilter = ref.watch(productQuickFilterProvider);
    final selectedCustomerId = ref.watch(productCustomerFilterProvider);
    final linesAsync = ref.watch(issuedLinesProvider);
    final licensesAsync = ref.watch(issuedLicensesProvider);

    return DefaultTabController(
      length: 2,
      child: AppPageLayout(
        title: 'Hat & Lisanslar',
        subtitle: 'Hat, lisans, bitiş takibi ve toplu yenileme yönetimi.',
        body: Column(
          children: [
            SmartFilterBar(
              title: 'Filtreler',
              subtitle: null,
              children: [
                SizedBox(
                  width: 300,
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ara',
                      hintText: 'Hat numarası / SIM / Lisans adı',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) =>
                        ref.read(productSearchProvider.notifier).set(v),
                  ),
                ),
                customersAsync.when(
                  data: (customers) => SizedBox(
                    width: 240,
                    child: DropdownButtonFormField<String?>(
                      initialValue: selectedCustomerId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Tüm müşteriler'),
                        ),
                        ...customers
                            .where((customer) => customer.isActive || isAdmin)
                            .map(
                              (customer) => DropdownMenuItem<String?>(
                                value: customer.id,
                                child: Text(customer.name),
                              ),
                            ),
                      ],
                      onChanged: (value) => ref
                          .read(productCustomerFilterProvider.notifier)
                          .set(value),
                      decoration: const InputDecoration(labelText: 'Müşteri'),
                    ),
                  ),
                  loading: () => const SizedBox(
                    width: 280,
                    child: LinearProgressIndicator(minHeight: 2),
                  ),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<ProductListSort>(
                    initialValue: sort,
                    items: const [
                      DropdownMenuItem(
                        value: ProductListSort.nearestEndDate,
                        child: Text('Bitiş: yakın önce'),
                      ),
                      DropdownMenuItem(
                        value: ProductListSort.latestEndDate,
                        child: Text('Bitiş: uzak önce'),
                      ),
                      DropdownMenuItem(
                        value: ProductListSort.customerName,
                        child: Text('Müşteri adına göre'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      ref.read(productSortProvider.notifier).set(value);
                    },
                    decoration: const InputDecoration(labelText: 'Listeleme'),
                  ),
                ),
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<ProductQuickFilter>(
                    initialValue: quickFilter,
                    items: const [
                      DropdownMenuItem(
                        value: ProductQuickFilter.all,
                        child: Text('Tüm kayıtlar'),
                      ),
                      DropdownMenuItem(
                        value: ProductQuickFilter.expiringSoon,
                        child: Text('Yakında bitecek'),
                      ),
                      DropdownMenuItem(
                        value: ProductQuickFilter.expired,
                        child: Text('Bitenler'),
                      ),
                      DropdownMenuItem(
                        value: ProductQuickFilter.endingThisMonth,
                        child: Text('Bu ay bitecek'),
                      ),
                      DropdownMenuItem(
                        value: ProductQuickFilter.noEndDate,
                        child: Text('Tarihsiz'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      ref.read(productQuickFilterProvider.notifier).set(value);
                    },
                    decoration: const InputDecoration(
                      labelText: 'Hızlı Filtre',
                    ),
                  ),
                ),
                if (isAdmin)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch.adaptive(
                        value: showPassive,
                        onChanged: (v) =>
                            ref.read(showPassiveProvider.notifier).set(v),
                      ),
                      const Gap(6),
                      Text(
                        'Pasif',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF475569),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const Gap(6),
            linesAsync.when(
              data: (lines) => licensesAsync.when(
                data: (licenses) => _ProductsSummarySection(
                  summary: _buildProductsSummary(
                    lines: lines,
                    licenses: licenses,
                  ),
                ),
                loading: () => const _ProductsSummaryLoading(),
                error: (error, stackTrace) => const SizedBox.shrink(),
              ),
              loading: () => const _ProductsSummaryLoading(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
            const Gap(6),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: EdgeInsets.symmetric(horizontal: 10),
                    tabs: [
                      Tab(text: 'Hatlar'),
                      Tab(text: 'Lisanslar (GMP3)'),
                    ],
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 680,
                    child: TabBarView(
                      children: [
                        _LinesTab(isAdmin: isAdmin),
                        _LicensesTab(isAdmin: isAdmin),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LinesTab extends ConsumerWidget {
  const _LinesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(issuedLinesProvider);
    final licensesAsync = ref.watch(issuedLicensesProvider);
    final selectedIds = ref.watch(selectedLineIdsProvider);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: linesAsync.when(
        data: (items) => licensesAsync.when(
          data: (licenses) {
            final licensedCustomerIds = licenses
                .where((license) => license.licenseType == 'gmp3')
                .map((license) => license.customerId)
                .toSet();
            final lineOnlyItems = items
                .where((line) => !licensedCustomerIds.contains(line.customerId))
                .toList(growable: false);
            final sortedItems = _sortLines(
              lineOnlyItems,
              ref.watch(productSortProvider),
            );
            final filteredItems = _filterByQuickRule(
              sortedItems,
              ref.watch(productQuickFilterProvider),
              (item) => item.endsAt,
            );
            final visibleIds = filteredItems.map((item) => item.id).toSet();
            final selectedVisibleIds = selectedIds
                .where(visibleIds.contains)
                .toSet();

            if (filteredItems.isEmpty) {
              return const _Empty(
                text:
                    'Seçili filtrede sadece hattı olan müşteri kaydı bulunmuyor.',
              );
            }
            return Column(
              children: [
                if (isAdmin)
                  _BulkActionBar(
                    title: '${filteredItems.length} hat listeleniyor',
                    selectedCount: selectedVisibleIds.length,
                    onToggleAll: () {
                      final notifier = ref.read(
                        selectedLineIdsProvider.notifier,
                      );
                      if (selectedVisibleIds.length == filteredItems.length) {
                        notifier.clear();
                      } else {
                        notifier.replace(filteredItems.map((item) => item.id));
                      }
                    },
                    onExtend: selectedVisibleIds.isEmpty
                        ? null
                        : () async {
                            await _extendLinesInBulk(
                              context,
                              ref,
                              lines: filteredItems
                                  .where(
                                    (item) =>
                                        selectedVisibleIds.contains(item.id),
                                  )
                                  .toList(growable: false),
                            );
                            ref.invalidate(issuedLinesProvider);
                            ref.invalidate(invoiceItemsProvider);
                            ref.read(selectedLineIdsProvider.notifier).clear();
                          },
                  ),
                if (isAdmin) const Gap(6),
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredItems.length,
                    separatorBuilder: (context, index) => const Gap(4),
                    itemBuilder: (context, index) => _LineRow(
                      item: filteredItems[index],
                      isAdmin: isAdmin,
                      selected: selectedVisibleIds.contains(
                        filteredItems[index].id,
                      ),
                      onSelectedChanged: isAdmin
                          ? (_) => ref
                                .read(selectedLineIdsProvider.notifier)
                                .toggle(filteredItems[index].id)
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const _Empty(text: 'Lisanslar yuklenemedi.'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Hatlar yuklenemedi.'),
      ),
    );
  }
}

class _LicensesTab extends ConsumerWidget {
  const _LicensesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licensesAsync = ref.watch(issuedLicensesProvider);
    final linesAsync = ref.watch(issuedLinesProvider);
    final selectedIds = ref.watch(selectedLicenseIdsProvider);
    return Padding(
      padding: const EdgeInsets.all(10),
      child: licensesAsync.when(
        data: (items) => linesAsync.when(
          data: (lines) {
            final gmp3 = _sortLicenses(
              items.where((e) => e.licenseType == 'gmp3').toList(),
              ref.watch(productSortProvider),
            );
            final filteredLicenses = _filterByQuickRule(
              gmp3,
              ref.watch(productQuickFilterProvider),
              (item) => item.endsAt,
            );
            final lineCustomerIds = lines
                .map((line) => line.customerId)
                .toSet();
            final visibleIds = filteredLicenses.map((item) => item.id).toSet();
            final selectedVisibleIds = selectedIds
                .where(visibleIds.contains)
                .toSet();
            if (filteredLicenses.isEmpty) {
              return const _Empty(text: 'Seçili filtrede kayıt yok.');
            }
            return Column(
              children: [
                if (isAdmin)
                  _BulkActionBar(
                    title: '${filteredLicenses.length} lisans listeleniyor',
                    selectedCount: selectedVisibleIds.length,
                    onToggleAll: () {
                      final notifier = ref.read(
                        selectedLicenseIdsProvider.notifier,
                      );
                      if (selectedVisibleIds.length ==
                          filteredLicenses.length) {
                        notifier.clear();
                      } else {
                        notifier.replace(
                          filteredLicenses.map((item) => item.id),
                        );
                      }
                    },
                    onExtend: selectedVisibleIds.isEmpty
                        ? null
                        : () async {
                            await _extendLicensesInBulk(
                              context,
                              ref,
                              licenses: filteredLicenses
                                  .where(
                                    (item) =>
                                        selectedVisibleIds.contains(item.id),
                                  )
                                  .toList(growable: false),
                            );
                            ref.invalidate(issuedLicensesProvider);
                            ref.invalidate(invoiceItemsProvider);
                            ref
                                .read(selectedLicenseIdsProvider.notifier)
                                .clear();
                          },
                  ),
                if (isAdmin) const Gap(6),
                Expanded(
                  child: ListView.separated(
                    itemCount: filteredLicenses.length,
                    separatorBuilder: (context, index) => const Gap(4),
                    itemBuilder: (context, index) => _LicenseRow(
                      item: filteredLicenses[index],
                      isAdmin: isAdmin,
                      hasLine: lineCustomerIds.contains(
                        filteredLicenses[index].customerId,
                      ),
                      selected: selectedVisibleIds.contains(
                        filteredLicenses[index].id,
                      ),
                      onSelectedChanged: isAdmin
                          ? (_) => ref
                                .read(selectedLicenseIdsProvider.notifier)
                                .toggle(filteredLicenses[index].id)
                          : null,
                    ),
                  ),
                ),
              ],
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) =>
              const _Empty(text: 'Hatlar yüklenemedi.'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const _Empty(text: 'Lisanslar yüklenemedi.'),
      ),
    );
  }
}

class _LineRow extends ConsumerStatefulWidget {
  const _LineRow({
    required this.item,
    required this.isAdmin,
    required this.selected,
    required this.onSelectedChanged,
  });

  final IssuedLine item;
  final bool isAdmin;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;

  @override
  ConsumerState<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends ConsumerState<_LineRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          if (widget.onSelectedChanged != null) ...[
            Checkbox.adaptive(
              value: widget.selected,
              onChanged: widget.onSelectedChanged,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            const Gap(4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.number ?? 'Hat',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    decoration: item.isActive
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                const Gap(2),
                Text(
                  [
                    item.customerName ?? '—',
                    if (item.branchName?.trim().isNotEmpty ?? false)
                      item.branchName!,
                    if (item.simNumber?.trim().isNotEmpty ?? false)
                      'SIM: ${item.simNumber}',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
                const Gap(2),
                Text(
                  'Bitiş: $dateText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          AppBadge(label: statusLabel, tone: tone),
          if (widget.isAdmin) ...[
            const Gap(8),
            MenuAnchor(
              builder: (context, controller, _) => OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 34),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                onPressed: _busy
                    ? null
                    : () => controller.isOpen
                          ? controller.close()
                          : controller.open(),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('İşlem'),
              ),
              menuChildren: [
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _showEditLineDialog(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Düzenle'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _extendLineAndQueueInvoice(
                        context,
                        ref,
                        line: item,
                      );
                      ref.invalidate(issuedLinesProvider);
                      ref.invalidate(invoiceItemsProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Süre Uzat'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _transferLine(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Devir Et'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LicenseRow extends ConsumerStatefulWidget {
  const _LicenseRow({
    required this.item,
    required this.isAdmin,
    required this.hasLine,
    required this.selected,
    required this.onSelectedChanged,
  });

  final IssuedLicense item;
  final bool isAdmin;
  final bool hasLine;
  final bool selected;
  final ValueChanged<bool?>? onSelectedChanged;

  @override
  ConsumerState<_LicenseRow> createState() => _LicenseRowState();
}

class _LicenseRowState extends ConsumerState<_LicenseRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          if (widget.onSelectedChanged != null) ...[
            Checkbox.adaptive(
              value: widget.selected,
              onChanged: widget.onSelectedChanged,
              visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
            ),
            const Gap(4),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.hasLine ? 'GMP + Hat' : item.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    decoration: item.isActive
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                const Gap(2),
                Text(
                  [
                    if (widget.hasLine) item.name,
                    item.customerName ?? '—',
                  ].join(' • '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                    fontSize: 11,
                  ),
                ),
                const Gap(2),
                Text(
                  'Bitiş: $dateText',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF94A3B8),
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          if (widget.hasLine) ...[
            const AppBadge(label: 'Hatlı', tone: AppBadgeTone.primary),
            const Gap(8),
          ],
          AppBadge(label: statusLabel, tone: tone),
          if (widget.isAdmin) ...[
            const Gap(8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 34),
                padding: const EdgeInsets.symmetric(horizontal: 10),
                textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await _extendLicenseAndQueueInvoice(
                          context,
                          ref,
                          license: item,
                        );
                        ref.invalidate(issuedLicensesProvider);
                        ref.invalidate(invoiceItemsProvider);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Süre Uzat'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showEditLineDialog(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final labelController = TextEditingController(text: line.label ?? '');
  final numberController = TextEditingController(text: line.number ?? '');
  final simController = TextEditingController(text: line.simNumber ?? '');
  DateTime? startsAt = line.startsAt;
  DateTime? endsAt = line.endsAt;
  bool saving = false;

  Future<void> pickStart(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => startsAt = picked);
  }

  Future<void> pickEnd(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => endsAt = picked);
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hat Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(labelText: 'Hat Numarası'),
                ),
                const Gap(12),
                TextField(
                  controller: simController,
                  decoration: const InputDecoration(labelText: 'SIM Numarası'),
                ),
                const Gap(12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(labelText: 'Etiket'),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickStart(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Başlangıç',
                          ),
                          child: Text(
                            startsAt == null
                                ? '—'
                                : DateFormat(
                                    'd MMM y',
                                    'tr_TR',
                                  ).format(startsAt!),
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickEnd(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Bitiş'),
                          child: Text(
                            endsAt == null
                                ? '—'
                                : DateFormat(
                                    'd MMM y',
                                    'tr_TR',
                                  ).format(endsAt!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final number = numberController.text.trim();
                                if (number.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final endStr = endsAt
                                      ?.toIso8601String()
                                      .substring(0, 10);
                                  await client
                                      .from('lines')
                                      .update({
                                        'number': number,
                                        'sim_number':
                                            simController.text.trim().isEmpty
                                            ? null
                                            : simController.text.trim(),
                                        'label':
                                            labelController.text.trim().isEmpty
                                            ? null
                                            : labelController.text.trim(),
                                        'starts_at': startsAt
                                            ?.toIso8601String()
                                            .substring(0, 10),
                                        'ends_at': endStr,
                                        'expires_at': endStr,
                                      })
                                      .eq('id', line.id);

                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Hat güncellendi.'),
                                    ),
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content: Text('Hat güncellenemedi.'),
                                    ),
                                  );
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  labelController.dispose();
  numberController.dispose();
  simController.dispose();
}

Future<void> _extendLineAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final newEnd = _nextRenewalEndDate(line.endsAt);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);
  final request = await _showRenewDialog(
    context,
    title: 'Hat Süre Uzat',
    message:
        'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
  );
  if (request == null) return;

  try {
    await client
        .from('lines')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', line.id);

    try {
      await enqueueInvoiceItem(
        client,
        customerId: line.customerId,
        itemType: 'line_renewal',
        sourceTable: 'lines',
        sourceId: line.id,
        description:
            'Hat uzatma (${line.number ?? ''}) (yeni bitiş: $newEndStr)',
        amount: request.amount,
        currency: request.currency,
        sourceEvent: 'line_renewed',
        sourceLabel: 'Hat Uzatma',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hat uzatıldı; faturalama listesine eklenemedi.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hat uzatıldı ve faturalama listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    }
  }
}

Future<void> _transferLine(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final customers = await ref.read(customersLookupProvider.future);
  if (!context.mounted) return;

  final selected = await showDialog<CustomerLookup?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransferDialog(
      customers: customers
          .where((c) => c.id != line.customerId)
          .toList(growable: false),
    ),
  );
  if (!context.mounted) return;
  if (selected == null) return;

  try {
    await client.from('line_transfers').insert({
      'line_id': line.id,
      'from_customer_id': line.customerId,
      'to_customer_id': selected.id,
      'transferred_by': client.auth.currentUser?.id,
    });

    await client
        .from('lines')
        .update({
          'customer_id': selected.id,
          'branch_id': null,
          'transferred_at': DateTime.now().toIso8601String(),
          'transferred_by': client.auth.currentUser?.id,
        })
        .eq('id', line.id);

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat devredildi.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat devredilemedi.')));
    }
  }
}

Future<void> _extendLicenseAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLicense license,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final newEnd = _nextRenewalEndDate(license.endsAt);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);
  final request = await _showRenewDialog(
    context,
    title: 'Lisans Süre Uzat',
    message:
        'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
  );
  if (request == null) return;

  try {
    await client
        .from('licenses')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', license.id);

    try {
      await enqueueInvoiceItem(
        client,
        customerId: license.customerId,
        itemType: 'gmp3_renewal',
        sourceTable: 'licenses',
        sourceId: license.id,
        description: 'GMP3 uzatma (${license.name}) (yeni bitiş: $newEndStr)',
        amount: request.amount,
        currency: request.currency,
        sourceEvent: 'gmp3_renewed',
        sourceLabel: 'GMP3 Uzatma',
      );
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Lisans uzatıldı; faturalama listesine eklenemedi.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lisans uzatıldı ve faturalama listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İşlem başarısız.')));
    }
  }
}

Future<void> _extendLinesInBulk(
  BuildContext context,
  WidgetRef ref, {
  required List<IssuedLine> lines,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null || lines.isEmpty) return;

  final request = await _showRenewDialog(
    context,
    title: 'Toplu Hat Süre Uzat',
    message: '${lines.length} seçili hattın süresi bir yıl uzatılacak.',
  );
  if (request == null) return;

  try {
    for (final line in lines) {
      final newEndStr = _nextRenewalEndDate(
        line.endsAt,
      ).toIso8601String().substring(0, 10);
      await client
          .from('lines')
          .update({'ends_at': newEndStr, 'expires_at': newEndStr})
          .eq('id', line.id);
      try {
        await enqueueInvoiceItem(
          client,
          customerId: line.customerId,
          itemType: 'line_renewal',
          sourceTable: 'lines',
          sourceId: line.id,
          description:
              'Hat uzatma (${line.number ?? ''}) (yeni bitiş: $newEndStr)',
          amount: request.amount,
          currency: request.currency,
          sourceEvent: 'line_renewed',
          sourceLabel: 'Hat Uzatma',
        );
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${lines.length} hat uzatıldı.')));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toplu hat uzatma başarısız.')),
      );
    }
  }
}

Future<void> _extendLicensesInBulk(
  BuildContext context,
  WidgetRef ref, {
  required List<IssuedLicense> licenses,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null || licenses.isEmpty) return;

  final request = await _showRenewDialog(
    context,
    title: 'Toplu Lisans Süre Uzat',
    message: '${licenses.length} seçili lisansın süresi bir yıl uzatılacak.',
  );
  if (request == null) return;

  try {
    for (final license in licenses) {
      final newEndStr = _nextRenewalEndDate(
        license.endsAt,
      ).toIso8601String().substring(0, 10);
      await client
          .from('licenses')
          .update({'ends_at': newEndStr, 'expires_at': newEndStr})
          .eq('id', license.id);
      try {
        await enqueueInvoiceItem(
          client,
          customerId: license.customerId,
          itemType: 'gmp3_renewal',
          sourceTable: 'licenses',
          sourceId: license.id,
          description:
              'GMP3 uzatma (${license.name}) (yeni bitiş: $newEndStr)',
          amount: request.amount,
          currency: request.currency,
          sourceEvent: 'gmp3_renewed',
          sourceLabel: 'GMP3 Uzatma',
        );
      } catch (_) {}
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${licenses.length} lisans uzatıldı.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Toplu lisans uzatma başarısız.')),
      );
    }
  }
}

DateTime _nextRenewalEndDate(DateTime? endsAt) {
  final now = DateTime.now();
  final baseYear = (endsAt != null && endsAt.isAfter(now))
      ? endsAt.year
      : now.year;
  return DateTime(baseYear + 1, 12, 31);
}

Future<_RenewalRequest?> _showRenewDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  final amountController = TextEditingController();
  String currency = 'TRY';

  final request = await showDialog<_RenewalRequest>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  message,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (opsiyonel)',
                    hintText: '0.00',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (value) =>
                      setState(() => currency = value ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          final amountRaw = amountController.text
                              .trim()
                              .replaceAll(',', '.');
                          Navigator.of(context).pop(
                            _RenewalRequest(
                              amount: amountRaw.isEmpty
                                  ? null
                                  : double.tryParse(amountRaw),
                              currency: currency,
                            ),
                          );
                        },
                        child: const Text('Uzat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  amountController.dispose();
  return request;
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.customers});

  final List<CustomerLookup> customers;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  CustomerLookup? _selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hat Devir',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(12),
              Autocomplete<CustomerLookup>(
                optionsBuilder: (text) {
                  final q = text.text.trim().toLowerCase();
                  final list = widget.customers
                      .where((c) => c.isActive)
                      .toList(growable: false);
                  if (q.isEmpty) return list.take(20);
                  return list
                      .where((c) => c.name.toLowerCase().contains(q))
                      .take(20);
                },
                displayStringForOption: (o) => o.name,
                onSelected: (o) => setState(() => _selected = o),
                fieldViewBuilder: (context, controller, focusNode, _) =>
                    TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Yeni Müşteri',
                        hintText: 'Firma adı yazın ve seçin',
                      ),
                      onChanged: (_) => setState(() => _selected = null),
                    ),
              ),
              const Gap(18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      child: const Text('Devir Et'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class _ProductsSummarySection extends StatelessWidget {
  const _ProductsSummarySection({required this.summary});

  final _ProductsSummary summary;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SummaryMetricChip(
            title: 'Toplam',
            value: summary.total.toString(),
            tone: AppBadgeTone.primary,
          ),
          _SummaryMetricChip(
            title: 'Bu Ay Bitecek',
            value: summary.endingThisMonth.toString(),
            tone: AppBadgeTone.warning,
          ),
          _SummaryMetricChip(
            title: 'Süresi Dolmuş',
            value: summary.expired.toString(),
            tone: AppBadgeTone.error,
          ),
          _SummaryMetricChip(
            title: 'Tarihsiz',
            value: summary.noEndDate.toString(),
            tone: AppBadgeTone.neutral,
          ),
        ],
      ),
    );
  }
}

class _ProductsSummaryLoading extends StatelessWidget {
  const _ProductsSummaryLoading();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      padding: EdgeInsets.all(16),
      child: LinearProgressIndicator(minHeight: 2),
    );
  }
}

class _SummaryMetricChip extends StatelessWidget {
  const _SummaryMetricChip({
    required this.title,
    required this.value,
    required this.tone,
  });

  final String title;
  final String value;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBadge(label: title, tone: tone),
          const Gap(8),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ],
      ),
    );
  }
}

class _RenewalRequest {
  const _RenewalRequest({required this.amount, required this.currency});

  final double? amount;
  final String currency;
}

class _BulkActionBar extends StatelessWidget {
  const _BulkActionBar({
    required this.title,
    required this.selectedCount,
    required this.onToggleAll,
    required this.onExtend,
  });

  final String title;
  final int selectedCount;
  final VoidCallback onToggleAll;
  final VoidCallback? onExtend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              selectedCount > 0 ? '$title • $selectedCount seçili' : title,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          OutlinedButton(
            onPressed: onToggleAll,
            child: Text(selectedCount > 0 ? 'Seçimi Temizle' : 'Tümünü Seç'),
          ),
          const Gap(8),
          FilledButton.icon(
            onPressed: onExtend,
            icon: const Icon(Icons.schedule_rounded, size: 16),
            label: const Text('Toplu Süre Uzat'),
          ),
        ],
      ),
    );
  }
}

class _ProductsSummary {
  const _ProductsSummary({
    required this.total,
    required this.endingThisMonth,
    required this.expired,
    required this.noEndDate,
  });

  final int total;
  final int endingThisMonth;
  final int expired;
  final int noEndDate;
}

List<IssuedLine> _sortLines(List<IssuedLine> items, ProductListSort sort) {
  final sorted = [...items];
  sorted.sort(
    (a, b) => _compareItems(
      sort,
      customerA: a.customerName,
      customerB: b.customerName,
      endsAtA: a.endsAt,
      endsAtB: b.endsAt,
    ),
  );
  return sorted;
}

List<IssuedLicense> _sortLicenses(
  List<IssuedLicense> items,
  ProductListSort sort,
) {
  final sorted = [...items];
  sorted.sort(
    (a, b) => _compareItems(
      sort,
      customerA: a.customerName,
      customerB: b.customerName,
      endsAtA: a.endsAt,
      endsAtB: b.endsAt,
    ),
  );
  return sorted;
}

int _compareItems(
  ProductListSort sort, {
  required String? customerA,
  required String? customerB,
  required DateTime? endsAtA,
  required DateTime? endsAtB,
}) {
  switch (sort) {
    case ProductListSort.customerName:
      return (customerA ?? '').toLowerCase().compareTo(
        (customerB ?? '').toLowerCase(),
      );
    case ProductListSort.latestEndDate:
      return _compareDates(endsAtB, endsAtA);
    case ProductListSort.nearestEndDate:
      return _compareDates(endsAtA, endsAtB);
  }
}

int _compareDates(DateTime? a, DateTime? b) {
  if (a == null && b == null) return 0;
  if (a == null) return 1;
  if (b == null) return -1;
  return a.compareTo(b);
}

_ProductsSummary _buildProductsSummary({
  required List<IssuedLine> lines,
  required List<IssuedLicense> licenses,
}) {
  final lineOnlyCustomerIds = licenses
      .where((license) => license.licenseType == 'gmp3')
      .map((license) => license.customerId)
      .toSet();
  final visibleLines = lines
      .where((line) => !lineOnlyCustomerIds.contains(line.customerId))
      .toList(growable: false);
  final visibleLicenses = licenses
      .where((license) => license.licenseType == 'gmp3')
      .toList(growable: false);
  final allDates = [
    ...visibleLines.map((line) => line.endsAt),
    ...visibleLicenses.map((license) => license.endsAt),
  ];
  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final nextMonthStart = DateTime(now.year, now.month + 1, 1);

  return _ProductsSummary(
    total: visibleLines.length + visibleLicenses.length,
    endingThisMonth: allDates
        .where(
          (date) =>
              date != null &&
              !date.isBefore(monthStart) &&
              date.isBefore(nextMonthStart),
        )
        .length,
    expired: allDates
        .where((date) => date != null && date.isBefore(now))
        .length,
    noEndDate: allDates.where((date) => date == null).length,
  );
}

List<T> _filterByQuickRule<T>(
  List<T> items,
  ProductQuickFilter filter,
  DateTime? Function(T item) endsAtSelector,
) {
  if (filter == ProductQuickFilter.all) return items;

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final nextMonthStart = DateTime(now.year, now.month + 1, 1);
  final soonThreshold = now.add(const Duration(days: 30));

  return items
      .where((item) {
        final endsAt = endsAtSelector(item);
        switch (filter) {
          case ProductQuickFilter.all:
            return true;
          case ProductQuickFilter.expiringSoon:
            return endsAt != null &&
                !endsAt.isBefore(now) &&
                !endsAt.isAfter(soonThreshold);
          case ProductQuickFilter.expired:
            return endsAt != null && endsAt.isBefore(now);
          case ProductQuickFilter.endingThisMonth:
            return endsAt != null &&
                !endsAt.isBefore(monthStart) &&
                endsAt.isBefore(nextMonthStart);
          case ProductQuickFilter.noEndDate:
            return endsAt == null;
        }
      })
      .toList(growable: false);
}

class IssuedLine {
  const IssuedLine({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.branchId,
    required this.branchName,
    required this.label,
    required this.number,
    required this.simNumber,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String? branchId;
  final String? branchName;
  final String? label;
  final String? number;
  final String? simNumber;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLine.fromJson(Map<String, dynamic> json) {
    return IssuedLine(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      label: json['label']?.toString(),
      number: json['number']?.toString(),
      simNumber: json['sim_number']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class IssuedLicense {
  const IssuedLicense({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.name,
    required this.licenseType,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String name;
  final String licenseType;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLicense.fromJson(Map<String, dynamic> json) {
    return IssuedLicense(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      name: (json['name'] ?? '').toString(),
      licenseType: (json['license_type'] ?? 'gmp3').toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerLookup {
  const CustomerLookup({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory CustomerLookup.fromJson(Map<String, dynamic> json) {
    return CustomerLookup(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
