import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

enum InvoiceDateFilter { today, last7, last30, all }

enum InvoiceStatusFilter { pending, invoiced, all }

enum InvoiceActiveFilter { active, inactive, all }

class InvoiceFilters {
  const InvoiceFilters({
    required this.date,
    required this.status,
    required this.active,
    required this.query,
  });

  final InvoiceDateFilter date;
  final InvoiceStatusFilter status;
  final InvoiceActiveFilter active;
  final String query;

  static const defaults = InvoiceFilters(
    date: InvoiceDateFilter.all,
    status: InvoiceStatusFilter.pending,
    active: InvoiceActiveFilter.active,
    query: '',
  );

  InvoiceFilters copyWith({
    InvoiceDateFilter? date,
    InvoiceStatusFilter? status,
    InvoiceActiveFilter? active,
    String? query,
  }) {
    return InvoiceFilters(
      date: date ?? this.date,
      status: status ?? this.status,
      active: active ?? this.active,
      query: query ?? this.query,
    );
  }
}

final invoiceFiltersProvider =
    NotifierProvider<InvoiceFiltersNotifier, InvoiceFilters>(
      InvoiceFiltersNotifier.new,
    );

class InvoiceFiltersNotifier extends Notifier<InvoiceFilters> {
  @override
  InvoiceFilters build() => InvoiceFilters.defaults;

  void set(InvoiceFilters value) => state = value;

  void reset() => state = InvoiceFilters.defaults;
}

final invoiceItemsProvider = FutureProvider<List<InvoiceItem>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  Object? apiError;
  if (apiClient != null) {
    try {
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'invoice_items_queue'},
      );
      final apiItems = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(InvoiceItem.fromJson)
          .toList(growable: false);
      if (apiItems.isNotEmpty) return apiItems;
    } catch (e) {
      apiError = e;
    }
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    if (apiError != null) throw apiError;
    return const [];
  }
  final rows = await client
      .from('invoice_items')
      .select(
        'id,customer_id,item_type,description,amount,currency,status,is_active,created_at,customers(name)',
      )
      .order('created_at', ascending: false)
      .limit(600);

  return (rows as List)
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .map((row) {
        final customers = row['customers'] as Map<String, dynamic>?;
        return InvoiceItem.fromJson({
          ...row,
          'customer_label': customers?['name'],
        });
      })
      .toList(growable: false);
});

class BillingScreen extends ConsumerStatefulWidget {
  const BillingScreen({super.key});

  @override
  ConsumerState<BillingScreen> createState() => _BillingScreenState();
}

class _BillingScreenState extends ConsumerState<BillingScreen> {
  late final TextEditingController _queryController;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canView = ref.watch(hasPageAccessProvider(kPageBilling));
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(
      hasActionAccessProvider(kActionArchiveRecords),
    );
    final canDeletePermanently = ref.watch(
      hasActionAccessProvider(kActionDeleteRecords),
    );
    final itemsAsync = ref.watch(invoiceItemsProvider);
    final filters = ref.watch(invoiceFiltersProvider);
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    if (_queryController.text != filters.query) {
      _queryController.value = _queryController.value.copyWith(
        text: filters.query,
        selection: TextSelection.collapsed(offset: filters.query.length),
      );
    }

    return AppPageLayout(
      title: 'Faturalama',
      subtitle: 'Uzatmalar için fatura kesilecekler listesi.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(invoiceItemsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: !canView
          ? AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Bu sayfaya erişiminiz yok.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          : itemsAsync.when(
              data: (items) {
                final filtered = _applyFilters(items, filters);
                final counts = _InvoiceCounts.fromItems(items);

                return ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    _BillingFiltersSummaryCard(
                      filters: filters,
                      counts: counts,
                      queryController: _queryController,
                      onChanged: (next) =>
                          ref.read(invoiceFiltersProvider.notifier).set(next),
                      onClear: () =>
                          ref.read(invoiceFiltersProvider.notifier).reset(),
                    ),
                    const Gap(12),
                    _BillingQueueHeader(count: filtered.length),
                    const Gap(8),
                    if (filtered.isEmpty)
                      const AppCard(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Filtreye uygun kayıt yok.'),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Gap(10),
                        itemBuilder: (context, index) => _InvoiceRow(
                          item: filtered[index],
                          money: money,
                          canEdit: canEdit,
                          canArchive: canArchive,
                          canDeletePermanently: canDeletePermanently,
                        ),
                      ),
                  ],
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (e, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Fatura listesi yüklenemedi: $e',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}

List<InvoiceItem> _applyFilters(
  List<InvoiceItem> items,
  InvoiceFilters filters,
) {
  final now = DateTime.now();
  DateTime? start;
  switch (filters.date) {
    case InvoiceDateFilter.today:
      start = DateTime(now.year, now.month, now.day);
    case InvoiceDateFilter.last7:
      start = now.subtract(const Duration(days: 7));
    case InvoiceDateFilter.last30:
      start = now.subtract(const Duration(days: 30));
    case InvoiceDateFilter.all:
      start = null;
  }
  final q = filters.query.trim().toLowerCase();

  bool matchesQuery(InvoiceItem item) {
    if (q.isEmpty) return true;
    final hay = [
      item.description,
      item.customerLabel ?? '',
      item.itemType,
      item.currency,
    ].join(' ').toLowerCase();
    return hay.contains(q);
  }

  return items
      .where((item) {
        if (filters.status != InvoiceStatusFilter.all) {
          if (filters.status == InvoiceStatusFilter.pending &&
              item.status != 'pending') {
            return false;
          }
          if (filters.status == InvoiceStatusFilter.invoiced &&
              item.status == 'pending') {
            return false;
          }
        }
        if (filters.active != InvoiceActiveFilter.all) {
          if (filters.active == InvoiceActiveFilter.active && !item.isActive) {
            return false;
          }
          if (filters.active == InvoiceActiveFilter.inactive && item.isActive) {
            return false;
          }
        }
        if (start != null && item.createdAt != null) {
          if (item.createdAt!.isBefore(start)) {
            return false;
          }
        }
        if (!matchesQuery(item)) return false;
        return true;
      })
      .toList(growable: false);
}

class _InvoiceCounts {
  const _InvoiceCounts({
    required this.total,
    required this.pending,
    required this.invoiced,
    required this.inactive,
    required this.today,
  });

  final int total;
  final int pending;
  final int invoiced;
  final int inactive;
  final int today;

  factory _InvoiceCounts.fromItems(List<InvoiceItem> items) {
    final now = DateTime.now();
    final startToday = DateTime(now.year, now.month, now.day);
    final pending = items.where((e) => e.status == 'pending').length;
    final invoiced = items.where((e) => e.status != 'pending').length;
    final inactive = items.where((e) => !e.isActive).length;
    final today = items
        .where((e) => e.createdAt != null && !e.createdAt!.isBefore(startToday))
        .length;
    return _InvoiceCounts(
      total: items.length,
      pending: pending,
      invoiced: invoiced,
      inactive: inactive,
      today: today,
    );
  }
}

class _BillingFiltersSummaryCard extends StatelessWidget {
  const _BillingFiltersSummaryCard({
    required this.filters,
    required this.counts,
    required this.queryController,
    required this.onChanged,
    required this.onClear,
  });

  final InvoiceFilters filters;
  final _InvoiceCounts counts;
  final TextEditingController queryController;
  final ValueChanged<InvoiceFilters> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 320,
            child: TextField(
              controller: queryController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                labelText: 'Ara',
                hintText: 'Müşteri, açıklama, tip',
              ),
              onChanged: (value) => onChanged(filters.copyWith(query: value)),
            ),
          ),
          _CompactFilterDropdown<InvoiceDateFilter>(
            value: filters.date,
            icon: Icons.date_range_rounded,
            items: InvoiceDateFilter.values,
            label: (value) => switch (value) {
              InvoiceDateFilter.today => 'Bugün',
              InvoiceDateFilter.last7 => 'Son 7 gün',
              InvoiceDateFilter.last30 => 'Son 30 gün',
              InvoiceDateFilter.all => 'Tümü',
            },
            onChanged: (value) => onChanged(filters.copyWith(date: value)),
          ),
          _CompactFilterDropdown<InvoiceStatusFilter>(
            value: filters.status,
            icon: Icons.fact_check_rounded,
            items: InvoiceStatusFilter.values,
            label: (value) => switch (value) {
              InvoiceStatusFilter.pending => 'Bekleyen',
              InvoiceStatusFilter.invoiced => 'Onaylanan',
              InvoiceStatusFilter.all => 'Tümü',
            },
            onChanged: (value) => onChanged(filters.copyWith(status: value)),
          ),
          _CompactFilterDropdown<InvoiceActiveFilter>(
            value: filters.active,
            icon: Icons.toggle_on_rounded,
            items: InvoiceActiveFilter.values,
            label: (value) => switch (value) {
              InvoiceActiveFilter.active => 'Aktif',
              InvoiceActiveFilter.inactive => 'Pasif',
              InvoiceActiveFilter.all => 'Tümü',
            },
            onChanged: (value) => onChanged(filters.copyWith(active: value)),
          ),
          _MiniStat(label: 'Toplam', value: counts.total.toString()),
          _MiniStat(label: 'Bekleyen', value: counts.pending.toString()),
          _MiniStat(label: 'Bugün', value: counts.today.toString()),
          OutlinedButton.icon(
            onPressed: onClear,
            icon: const Icon(Icons.clear_rounded, size: 18),
            label: const Text('Sıfırla'),
          ),
        ],
      ),
    );
  }
}

class _CompactFilterDropdown<T> extends StatelessWidget {
  const _CompactFilterDropdown({
    required this.value,
    required this.items,
    required this.label,
    required this.onChanged,
    required this.icon,
  });

  final T value;
  final List<T> items;
  final String Function(T value) label;
  final ValueChanged<T> onChanged;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: [
            for (final item in items)
              DropdownMenuItem(value: item, child: Text(label(item))),
          ],
          onChanged: (next) {
            if (next != null) onChanged(next);
          },
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          selectedItemBuilder: (context) => [
            for (final item in items)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: AppTheme.textSoft),
                  const Gap(8),
                  Text(label(item)),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _BillingQueueHeader extends StatelessWidget {
  const _BillingQueueHeader({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Text('Fatura Kuyruğu', style: Theme.of(context).textTheme.titleSmall),
          const Gap(8),
          AppBadge(label: '$count kayıt', tone: AppBadgeTone.neutral),
          const Spacer(),
          Text(
            'Onay / pasif / kalıcı sil işlemleri satır sonunda.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const Gap(8),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _InvoiceRow extends ConsumerStatefulWidget {
  const _InvoiceRow({
    required this.item,
    required this.money,
    required this.canEdit,
    required this.canArchive,
    required this.canDeletePermanently,
  });

  final InvoiceItem item;
  final NumberFormat money;
  final bool canEdit;
  final bool canArchive;
  final bool canDeletePermanently;

  @override
  ConsumerState<_InvoiceRow> createState() => _InvoiceRowState();
}

class _InvoiceRowState extends ConsumerState<_InvoiceRow> {
  bool _saving = false;

  Future<void> _toggleInvoiced() async {
    if (!widget.canEdit) return;
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final nextStatus = widget.item.status == 'pending'
          ? 'invoiced'
          : 'pending';
      final profile = await ref.read(currentUserProfileProvider.future);
      final userId = profile?.id;
      final now = DateTime.now().toIso8601String();

      if (apiClient != null) {
        try {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'invoice_items',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': widget.item.id},
              ],
              'values': {
                'status': nextStatus,
                'invoiced_at': nextStatus == 'invoiced' ? now : null,
                'approved_by': nextStatus == 'invoiced' ? userId : null,
                'approved_at': nextStatus == 'invoiced' ? now : null,
                'updated_by': userId,
                'updated_at': now,
              },
            },
          );
        } catch (_) {
          if (client != null) {
            try {
              await client
                  .from('invoice_items')
                  .update({
                    'status': nextStatus,
                    'invoiced_at': nextStatus == 'invoiced' ? now : null,
                    'approved_by': nextStatus == 'invoiced' ? userId : null,
                    'approved_at': nextStatus == 'invoiced' ? now : null,
                    'updated_by': userId,
                    'updated_at': now,
                  })
                  .eq('id', widget.item.id);
            } catch (_) {
              await client
                  .from('invoice_items')
                  .update({'status': nextStatus})
                  .eq('id', widget.item.id);
            }
          } else {
            rethrow;
          }
        }
      } else {
        try {
          await client!
              .from('invoice_items')
              .update({
                'status': nextStatus,
                'invoiced_at': nextStatus == 'invoiced' ? now : null,
                'approved_by': nextStatus == 'invoiced' ? userId : null,
                'approved_at': nextStatus == 'invoiced' ? now : null,
                'updated_by': userId,
                'updated_at': now,
              })
              .eq('id', widget.item.id);
        } catch (_) {
          await client!
              .from('invoice_items')
              .update({'status': nextStatus})
              .eq('id', widget.item.id);
        }
      }
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Güncellenemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleActive() async {
    if (!widget.canArchive) return;
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final profile = await ref.read(currentUserProfileProvider.future);
      final userId = profile?.id;
      final now = DateTime.now().toIso8601String();
      final nextActive = !widget.item.isActive;

      if (apiClient != null) {
        try {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'invoice_items',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': widget.item.id},
              ],
              'values': {
                'is_active': nextActive,
                'deactivated_by': nextActive ? null : userId,
                'deactivated_at': nextActive ? null : now,
                'updated_by': userId,
                'updated_at': now,
              },
            },
          );
        } catch (_) {
          if (client != null) {
            try {
              await client
                  .from('invoice_items')
                  .update({
                    'is_active': nextActive,
                    'deactivated_by': nextActive ? null : userId,
                    'deactivated_at': nextActive ? null : now,
                    'updated_by': userId,
                    'updated_at': now,
                  })
                  .eq('id', widget.item.id);
            } catch (_) {
              await client
                  .from('invoice_items')
                  .update({'is_active': nextActive})
                  .eq('id', widget.item.id);
            }
          } else {
            rethrow;
          }
        }
      } else {
        try {
          await client!
              .from('invoice_items')
              .update({
                'is_active': nextActive,
                'deactivated_by': nextActive ? null : userId,
                'deactivated_at': nextActive ? null : now,
                'updated_by': userId,
                'updated_at': now,
              })
              .eq('id', widget.item.id);
        } catch (_) {
          await client!
              .from('invoice_items')
              .update({'is_active': nextActive})
              .eq('id', widget.item.id);
        }
      }
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kayıt güncellenemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePermanently() async {
    if (!widget.canDeletePermanently) return;
    if (widget.item.isActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Önce kaydı pasife alın.')));
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kalıcı sil'),
        content: Text(
          '"${widget.item.description}" kaydı kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kalıcı Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'delete',
            'table': 'invoice_items',
            'id': widget.item.id,
          },
        );
      } else {
        await client!.from('invoice_items').delete().eq('id', widget.item.id);
      }
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Silinemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  List<PopupMenuEntry<String>> _buildMenuItems() {
    final item = widget.item;
    return [
      PopupMenuItem(
        value: 'toggleStatus',
        enabled: !_saving && widget.canEdit,
        child: Text(item.status == 'pending' ? 'Onayla' : 'Beklemede Yap'),
      ),
      PopupMenuItem(
        value: 'toggleActive',
        enabled: !_saving && widget.canArchive,
        child: Text(item.isActive ? 'Pasife Al' : 'Aktifleştir'),
      ),
      if (widget.canDeletePermanently)
        PopupMenuItem(
          value: 'delete',
          enabled: !_saving,
          child: const Text('Kalıcı Sil'),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final tone = item.status == 'pending'
        ? AppBadgeTone.warning
        : AppBadgeTone.success;
    final statusLabel = item.status == 'pending' ? 'Bekliyor' : 'Kesildi';

    final amountText = item.amount == null
        ? '—'
        : item.currency == 'TRY'
        ? widget.money.format(item.amount)
        : '${widget.money.format(item.amount)} ${item.currency}';

    final createdAtText = item.createdAt == null
        ? null
        : DateFormat('d MMM y', 'tr_TR').format(item.createdAt!);

    final isNarrow = MediaQuery.sizeOf(context).width < 900;

    return AppCard(
      padding: EdgeInsets.zero,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 4,
            height: 82,
            decoration: BoxDecoration(
              color: item.status == 'pending'
                  ? AppTheme.warning.withValues(alpha: 0.70)
                  : AppTheme.success.withValues(alpha: 0.70),
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(AppTheme.radiusMd),
              ),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: Icon(
                      Icons.receipt_long_rounded,
                      size: 20,
                      color: AppTheme.primary,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w800,
                                decoration: item.isActive
                                    ? TextDecoration.none
                                    : TextDecoration.lineThrough,
                              ),
                        ),
                        const Gap(5),
                        Text(
                          item.customerLabel?.trim().isNotEmpty ?? false
                              ? item.customerLabel!.trim()
                              : 'Cari bilgisi yok',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  SizedBox(
                    width: 170,
                    child: _InvoiceMetaText(
                      icon: Icons.payments_rounded,
                      text: amountText,
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _InvoiceMetaText(
                      icon: Icons.calendar_today_rounded,
                      text: createdAtText ?? '-',
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: _InvoiceMetaText(
                      icon: Icons.category_rounded,
                      text: item.itemType,
                    ),
                  ),
                  SizedBox(
                    width: 92,
                    child: AppBadge(label: statusLabel, tone: tone),
                  ),
                  const Gap(8),
                  if (isNarrow)
                    PopupMenuButton<String>(
                      enabled: !_saving,
                      itemBuilder: (_) => _buildMenuItems(),
                      onSelected: (value) async {
                        if (value == 'toggleStatus') await _toggleInvoiced();
                        if (value == 'toggleActive') await _toggleActive();
                        if (value == 'delete') await _deletePermanently();
                      },
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.more_horiz_rounded),
                      ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _TinyActionButton(
                          tooltip: item.status == 'pending'
                              ? 'Onayla'
                              : 'Geri Al',
                          onPressed: _saving ? null : _toggleInvoiced,
                          icon: _saving
                              ? Icons.hourglass_empty_rounded
                              : item.status == 'pending'
                              ? Icons.check_rounded
                              : Icons.undo_rounded,
                        ),
                        const Gap(6),
                        _TinyActionButton(
                          tooltip: item.isActive ? 'Pasife Al' : 'Aktifleştir',
                          onPressed: _saving ? null : _toggleActive,
                          icon: item.isActive
                              ? Icons.archive_outlined
                              : Icons.restore_rounded,
                        ),
                        if (widget.canDeletePermanently) ...[
                          const Gap(6),
                          _TinyActionButton(
                            tooltip: 'Kalıcı Sil',
                            onPressed: _saving ? null : _deletePermanently,
                            icon: Icons.delete_forever_rounded,
                          ),
                        ],
                      ],
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceMetaText extends StatelessWidget {
  const _InvoiceMetaText({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppTheme.textMuted),
        const Gap(7),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textSoft,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _TinyActionButton extends StatelessWidget {
  const _TinyActionButton({
    required this.tooltip,
    required this.onPressed,
    required this.icon,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton.filledTonal(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 38, height: 38),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
      ),
    );
  }
}

class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.customerId,
    required this.itemType,
    required this.description,
    required this.amount,
    required this.currency,
    required this.status,
    required this.isActive,
    required this.createdAt,
    required this.customerLabel,
  });

  final String id;
  final String? customerId;
  final String itemType;
  final String description;
  final double? amount;
  final String currency;
  final String status;
  final bool isActive;
  final DateTime? createdAt;
  final String? customerLabel;

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    final rawAmount = json['amount'];
    double? parseAmount(Object? value) {
      if (value == null) return null;
      if (value is num) return value.toDouble();
      if (value is String) {
        final text = value.trim();
        if (text.isEmpty) return null;
        return double.tryParse(text.replaceAll(',', '.'));
      }
      return null;
    }

    return InvoiceItem(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString(),
      itemType: (json['item_type'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      amount: parseAmount(rawAmount),
      currency: (json['currency'] ?? 'TRY').toString(),
      status: (json['status'] ?? 'pending').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt: DateTime.tryParse((json['created_at'] ?? '').toString()),
      customerLabel: json['customer_label']?.toString(),
    );
  }
}
