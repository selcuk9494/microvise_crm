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
import '../../core/ui/app_section_card.dart';
import '../../core/ui/compact_stat_card.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/ui/smart_filter_bar.dart';

final billingFiltersProvider =
    NotifierProvider<BillingFiltersNotifier, BillingFilters>(
      BillingFiltersNotifier.new,
    );

class BillingFiltersNotifier extends Notifier<BillingFilters> {
  @override
  BillingFilters build() =>
      const BillingFilters(search: '', showPassive: false, showInvoiced: false);

  void setSearch(String value) => state = state.copyWith(search: value);

  void toggleShowPassive() =>
      state = state.copyWith(showPassive: !state.showPassive);

  void toggleShowInvoiced() =>
      state = state.copyWith(showInvoiced: !state.showInvoiced);

  void reset() => state = build();
}

class BillingFilters {
  const BillingFilters({
    required this.search,
    required this.showPassive,
    required this.showInvoiced,
  });

  final String search;
  final bool showPassive;
  final bool showInvoiced;

  BillingFilters copyWith({
    String? search,
    bool? showPassive,
    bool? showInvoiced,
  }) {
    return BillingFilters(
      search: search ?? this.search,
      showPassive: showPassive ?? this.showPassive,
      showInvoiced: showInvoiced ?? this.showInvoiced,
    );
  }
}

final invoiceItemsProvider = FutureProvider<List<InvoiceItem>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  List rows;
  try {
    rows = await client
        .from('invoice_items')
        .select(
          'id,customer_id,item_type,source_table,source_id,description,amount,currency,status,created_at,invoiced_at,created_by,approved_by,approved_at,updated_by,updated_at,deactivated_by,deactivated_at,is_active,source_event,source_label,customers(name)',
        )
        .order('created_at', ascending: false)
        .limit(400);
  } catch (_) {
    rows = await client
        .from('invoice_items')
        .select(
          'id,customer_id,item_type,description,amount,currency,status,created_at,invoiced_at,created_by,customers(name)',
        )
        .order('created_at', ascending: false)
        .limit(400);
  }

  final actorIds = <String>{};
  for (final row in rows) {
    final map = row as Map<String, dynamic>;
    for (final key
        in const ['created_by', 'approved_by', 'updated_by', 'deactivated_by']) {
      final value = map[key]?.toString();
      if (value != null && value.isNotEmpty) {
        actorIds.add(value);
      }
    }
  }

  final userLabels = <String, String>{};
  if (actorIds.isNotEmpty) {
    final userRows = await client
        .from('users')
        .select('id,full_name')
        .inFilter('id', actorIds.toList(growable: false));
    for (final row in userRows as List) {
      final map = row as Map<String, dynamic>;
      final id = map['id']?.toString();
      if (id == null || id.isEmpty) continue;
      userLabels[id] = map['full_name']?.toString() ?? id;
    }
  }

  return rows
      .map((row) {
        final map = row as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        return InvoiceItem.fromJson({
          ...map,
          'customer_label': customer?['name'],
          'created_by_label': userLabels[map['created_by']?.toString()],
          'approved_by_label': userLabels[map['approved_by']?.toString()],
          'updated_by_label': userLabels[map['updated_by']?.toString()],
          'deactivated_by_label': userLabels[map['deactivated_by']?.toString()],
        });
      })
      .toList(growable: false);
});

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final itemsAsync = ref.watch(invoiceItemsProvider);
    final filters = ref.watch(billingFiltersProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

    return AppPageLayout(
      title: 'Faturalama',
      subtitle: 'Sisteme düşen tüm işlem kalemlerini kaynak ve personel bazında izleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(invoiceItemsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        children: [
          if (!isAdmin)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Bu sayfa sadece admin için erişilebilir.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else
            itemsAsync.when(
              data: (items) {
                final filtered = items
                    .where((item) {
                      final search = filters.search.trim().toLowerCase();
                      final matchesSearch =
                          search.isEmpty ||
                          item.description.toLowerCase().contains(search) ||
                          item.typeLabel.toLowerCase().contains(search) ||
                          (item.customerLabel ?? '').toLowerCase().contains(
                            search,
                          ) ||
                          (item.createdByLabel ?? '').toLowerCase().contains(
                            search,
                          ) ||
                          (item.sourceLabel ?? '').toLowerCase().contains(
                            search,
                          );
                      final matchesPassive =
                          filters.showPassive || item.isActive;
                      final matchesInvoiced =
                          filters.showInvoiced || item.status != 'invoiced';
                      return matchesSearch &&
                          matchesPassive &&
                          matchesInvoiced;
                    })
                    .toList(growable: false);

                if (items.isEmpty) {
                  return const EmptyStateCard(
                    icon: Icons.receipt_long_rounded,
                    title: 'Fatura kalemi yok',
                    message: 'Henüz görüntülenecek fatura kalemi oluşmadı.',
                  );
                }

                final pendingCount = items
                    .where((item) => item.status == 'pending' && item.isActive)
                    .length;
                final invoicedCount = items
                    .where((item) => item.status == 'invoiced')
                    .length;
                final passiveCount = items.where((item) => !item.isActive).length;
                final pendingAmount = items
                    .where((item) => item.status == 'pending' && item.isActive)
                    .fold<double>(0, (sum, item) => sum + (item.amount ?? 0));

                return Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: isMobile ? (width - 44) / 2 : null,
                          child: CompactStatCard(
                            label: 'Toplam Kalem',
                            value: items.length.toString(),
                            icon: Icons.receipt_long_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? (width - 44) / 2 : null,
                          child: CompactStatCard(
                            label: 'Bekleyen',
                            value: pendingCount.toString(),
                            icon: Icons.hourglass_top_rounded,
                            color: AppTheme.warning,
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? (width - 44) / 2 : null,
                          child: CompactStatCard(
                            label: 'Kesilen',
                            value: invoicedCount.toString(),
                            icon: Icons.check_circle_outline_rounded,
                            color: AppTheme.success,
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? (width - 44) / 2 : null,
                          child: CompactStatCard(
                            label: 'Pasif',
                            value: passiveCount.toString(),
                            icon: Icons.visibility_off_rounded,
                            color: AppTheme.textMuted,
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? (width - 44) / 2 : null,
                          child: CompactStatCard(
                            label: 'Bekleyen Tutar',
                            value: money.format(pendingAmount),
                            icon: Icons.payments_outlined,
                            color: AppTheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    SmartFilterBar(
                      title: 'Filtreler',
                      subtitle:
                          'Kalemleri kaynak, müşteri ve işlem yapan personel bazında arayın.',
                      footer:
                          (filters.search.isNotEmpty ||
                              filters.showPassive ||
                              filters.showInvoiced)
                          ? Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                if (filters.search.isNotEmpty)
                                  AppBadge(
                                    label: 'Arama: ${filters.search}',
                                    tone: AppBadgeTone.primary,
                                  ),
                                if (filters.showPassive)
                                  const AppBadge(
                                    label: 'Pasifler açık',
                                    tone: AppBadgeTone.neutral,
                                  ),
                                if (filters.showInvoiced)
                                  const AppBadge(
                                    label: 'Kesilenler açık',
                                    tone: AppBadgeTone.success,
                                  ),
                                TextButton.icon(
                                  onPressed: () => ref
                                      .read(billingFiltersProvider.notifier)
                                      .reset(),
                                  icon: const Icon(
                                    Icons.clear_rounded,
                                    size: 16,
                                  ),
                                  label: const Text('Temizle'),
                                ),
                              ],
                            )
                          : null,
                      children: [
                        SizedBox(
                          width: isMobile ? double.infinity : width * 0.38,
                          child: TextField(
                            onChanged: ref
                                .read(billingFiltersProvider.notifier)
                                .setSearch,
                            decoration: const InputDecoration(
                              hintText: 'Kalem, müşteri veya personel ara',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        FilterChip(
                          selected: filters.showInvoiced,
                          label: const Text('Kesilenleri Göster'),
                          avatar: const Icon(
                            Icons.task_alt_rounded,
                            size: 18,
                          ),
                          onSelected: (_) => ref
                              .read(billingFiltersProvider.notifier)
                              .toggleShowInvoiced(),
                        ),
                        FilterChip(
                          selected: filters.showPassive,
                          label: const Text('Pasifleri Göster'),
                          avatar: const Icon(
                            Icons.visibility_off_rounded,
                            size: 18,
                          ),
                          onSelected: (_) => ref
                              .read(billingFiltersProvider.notifier)
                              .toggleShowPassive(),
                        ),
                      ],
                    ),
                    const Gap(16),
                    AppSectionCard(
                      title: 'Fatura Kuyruğu',
                      subtitle: '${filtered.length} kayıt gösteriliyor',
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            color: AppTheme.surfaceSoft,
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Kaynak / Açıklama',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.w700,
                                          color: AppTheme.textMuted,
                                        ),
                                  ),
                                ),
                                Text(
                                  'İşlemler',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AppTheme.textMuted,
                                      ),
                                ),
                              ],
                            ),
                          ),
                          const Divider(height: 1),
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(20),
                              child: Text(
                                'Filtrelere uygun kalem bulunamadı.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: AppTheme.textMuted),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filtered.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) => _InvoiceRow(
                                item: filtered[index],
                                money: money,
                              ),
                            ),
                        ],
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
                    'Fatura listesi yüklenemedi. ${e.toString()}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
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

class _InvoiceRow extends ConsumerStatefulWidget {
  const _InvoiceRow({required this.item, required this.money});

  final InvoiceItem item;
  final NumberFormat money;

  @override
  ConsumerState<_InvoiceRow> createState() => _InvoiceRowState();
}

class _InvoiceRowState extends ConsumerState<_InvoiceRow> {
  bool _saving = false;

  Future<void> _patchInvoiceItem(Map<String, dynamic> payload) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client.from('invoice_items').update(payload).eq('id', widget.item.id);
    } catch (error) {
      final message = error.toString();
      final fallback = Map<String, dynamic>.from(payload);
      if (message.contains("'approved_by' column")) {
        fallback.remove('approved_by');
        fallback.remove('approved_at');
      }
      if (message.contains("'updated_by' column")) {
        fallback.remove('updated_by');
        fallback.remove('updated_at');
      }
      if (message.contains("'deactivated_by' column")) {
        fallback.remove('deactivated_by');
        fallback.remove('deactivated_at');
      }
      if (message.contains("'is_active' column")) {
        fallback.remove('is_active');
      }
      await client.from('invoice_items').update(fallback).eq('id', widget.item.id);
    }
  }

  Future<void> _toggleInvoiced() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final userId = client.auth.currentUser?.id;
      final nextStatus = widget.item.status == 'pending'
          ? 'invoiced'
          : 'pending';
      await _patchInvoiceItem({
        'status': nextStatus,
        'invoiced_at': nextStatus == 'invoiced'
            ? DateTime.now().toIso8601String()
            : null,
        'approved_by': nextStatus == 'invoiced' ? userId : null,
        'approved_at': nextStatus == 'invoiced'
            ? DateTime.now().toIso8601String()
            : null,
        'updated_by': userId,
        'updated_at': DateTime.now().toIso8601String(),
      });
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
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final userId = client.auth.currentUser?.id;
      final nextActive = !widget.item.isActive;
      await _patchInvoiceItem({
        'is_active': nextActive,
        'deactivated_by': nextActive ? null : userId,
        'deactivated_at': nextActive
            ? null
            : DateTime.now().toIso8601String(),
        'updated_by': userId,
        'updated_at': DateTime.now().toIso8601String(),
      });
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

  Future<void> _showEditDialog() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final descriptionController = TextEditingController(
      text: widget.item.description,
    );
    final amountController = TextEditingController(
      text: widget.item.amount?.toStringAsFixed(2) ?? '',
    );
    String currency = widget.item.currency;

    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setLocalState) => AlertDialog(
          title: const Text('Kalemi Düzenle'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: descriptionController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    alignLabelWithHint: true,
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'Tutar'),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setLocalState(() => currency = value);
                  },
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (shouldSave != true) return;

    final amount = double.tryParse(
      amountController.text.trim().replaceAll(',', '.'),
    );
    setState(() => _saving = true);
    try {
      await _patchInvoiceItem({
        'description': descriptionController.text.trim().isEmpty
            ? widget.item.description
            : descriptionController.text.trim(),
        'amount': amount,
        'currency': currency,
        'updated_by': client.auth.currentUser?.id,
        'updated_at': DateTime.now().toIso8601String(),
      });
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Kalem düzenlenemedi.')));
    } finally {
      descriptionController.dispose();
      amountController.dispose();
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePassiveItem() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Kalemi Sil'),
        content: const Text(
          'Pasif kayıt tamamen silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await client.from('invoice_items').delete().eq('id', widget.item.id);
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

  String _formatDate(DateTime? value) {
    if (value == null) return '—';
    return DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(value);
  }

  Widget _buildAuditLine(
    BuildContext context, {
    required String label,
    String? person,
    DateTime? date,
  }) {
    final textStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: AppTheme.textMuted,
      height: 1.35,
    );
    return Text(
      '$label: ${person ?? '—'}${date == null ? '' : ' • ${_formatDate(date)}'}',
      style: textStyle,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final item = widget.item;
    final tone = item.status == 'pending'
        ? AppBadgeTone.warning
        : AppBadgeTone.success;
    final statusLabel = item.status == 'pending' ? 'Bekliyor' : 'Kesildi';

    final amountText = item.amount == null
        ? 'Tutar bekleniyor'
        : '${widget.money.format(item.amount)} ${item.currency}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.description,
                      style: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                    ),
                    const Gap(8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        AppBadge(
                          label: item.typeLabel,
                          tone: AppBadgeTone.primary,
                        ),
                        if (item.customerLabel != null)
                          AppBadge(
                            label: item.customerLabel!,
                            tone: AppBadgeTone.neutral,
                          ),
                        AppBadge(
                          label: amountText,
                          tone: AppBadgeTone.neutral,
                        ),
                        AppBadge(label: statusLabel, tone: tone),
                        if (!item.isActive)
                          const AppBadge(
                            label: 'Pasif',
                            tone: AppBadgeTone.error,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (_saving)
                const Padding(
                  padding: EdgeInsets.only(left: 12, top: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
            ],
          ),
          const Gap(10),
          _buildAuditLine(
            context,
            label: 'Gönderen',
            person: item.createdByLabel,
            date: item.createdAt,
          ),
          if (item.approvedByLabel != null || item.approvedAt != null) ...[
            const Gap(2),
            _buildAuditLine(
              context,
              label: 'Onaylayan',
              person: item.approvedByLabel,
              date: item.approvedAt,
            ),
          ],
          if (item.updatedByLabel != null || item.updatedAt != null) ...[
            const Gap(2),
            _buildAuditLine(
              context,
              label: 'Düzenleyen',
              person: item.updatedByLabel,
              date: item.updatedAt,
            ),
          ],
          if (!item.isActive &&
              (item.deactivatedByLabel != null ||
                  item.deactivatedAt != null)) ...[
            const Gap(2),
            _buildAuditLine(
              context,
              label: 'Pasife Alan',
              person: item.deactivatedByLabel,
              date: item.deactivatedAt,
            ),
          ],
          const Gap(10),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: _saving ? null : _showEditDialog,
                icon: const Icon(Icons.edit_rounded, size: 16),
                label: Text(isMobile ? 'Düzenle' : 'Düzenle'),
              ),
              FilledButton.tonalIcon(
                onPressed: _saving ? null : _toggleInvoiced,
                icon: Icon(
                  item.status == 'pending'
                      ? Icons.check_rounded
                      : Icons.undo_rounded,
                  size: 16,
                ),
                label: Text(
                  item.status == 'pending' ? 'Onayla' : 'Onayı Kaldır',
                ),
              ),
              OutlinedButton.icon(
                onPressed: _saving ? null : _toggleActive,
                icon: Icon(
                  item.isActive
                      ? Icons.visibility_off_rounded
                      : Icons.restart_alt_rounded,
                  size: 16,
                ),
                label: Text(item.isActive ? 'Pasife Al' : 'Aktifleştir'),
              ),
              if (!item.isActive)
                OutlinedButton.icon(
                  onPressed: _saving ? null : _deletePassiveItem,
                  icon: const Icon(Icons.delete_forever_rounded, size: 16),
                  label: const Text('Sil'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class InvoiceItem {
  const InvoiceItem({
    required this.id,
    required this.customerId,
    required this.itemType,
    required this.sourceTable,
    required this.sourceId,
    required this.description,
    required this.amount,
    required this.currency,
    required this.status,
    required this.customerLabel,
    required this.isActive,
    this.sourceEvent,
    this.sourceLabel,
    this.createdAt,
    this.invoicedAt,
    this.createdBy,
    this.createdByLabel,
    this.approvedBy,
    this.approvedByLabel,
    this.approvedAt,
    this.updatedBy,
    this.updatedByLabel,
    this.updatedAt,
    this.deactivatedBy,
    this.deactivatedByLabel,
    this.deactivatedAt,
  });

  final String id;
  final String? customerId;
  final String itemType;
  final String? sourceTable;
  final String? sourceId;
  final String description;
  final double? amount;
  final String currency;
  final String status;
  final String? customerLabel;
  final bool isActive;
  final String? sourceEvent;
  final String? sourceLabel;
  final DateTime? createdAt;
  final DateTime? invoicedAt;
  final String? createdBy;
  final String? createdByLabel;
  final String? approvedBy;
  final String? approvedByLabel;
  final DateTime? approvedAt;
  final String? updatedBy;
  final String? updatedByLabel;
  final DateTime? updatedAt;
  final String? deactivatedBy;
  final String? deactivatedByLabel;
  final DateTime? deactivatedAt;

  String get typeLabel {
    if (sourceLabel != null && sourceLabel!.trim().isNotEmpty) {
      return sourceLabel!;
    }
    switch (itemType) {
      case 'line_renewal':
        return 'Hat Uzatma';
      case 'gmp3_renewal':
        return 'GMP3 Uzatma';
      case 'line_activation':
        return 'Hat Aktivasyonu';
      case 'gmp3_activation':
        return 'GMP3 Aktivasyonu';
      case 'work_order_payment':
        return 'İş Emri Ödemesi';
      case 'application_form':
        return 'Başvuru Formu';
      case 'scrap_form':
        return 'Hurda Formu';
      case 'transfer_form':
        return 'Devir Formu';
      default:
        return itemType;
    }
  }

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString(),
      itemType: (json['item_type'] ?? '').toString(),
      sourceTable: json['source_table']?.toString(),
      sourceId: json['source_id']?.toString(),
      description: (json['description'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      currency: (json['currency'] ?? 'TRY').toString(),
      status: (json['status'] ?? 'pending').toString(),
      customerLabel: json['customer_label']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      sourceEvent: json['source_event']?.toString(),
      sourceLabel: json['source_label']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      invoicedAt: DateTime.tryParse(json['invoiced_at']?.toString() ?? ''),
      createdBy: json['created_by']?.toString(),
      createdByLabel: json['created_by_label']?.toString(),
      approvedBy: json['approved_by']?.toString(),
      approvedByLabel: json['approved_by_label']?.toString(),
      approvedAt: DateTime.tryParse(json['approved_at']?.toString() ?? ''),
      updatedBy: json['updated_by']?.toString(),
      updatedByLabel: json['updated_by_label']?.toString(),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
      deactivatedBy: json['deactivated_by']?.toString(),
      deactivatedByLabel: json['deactivated_by_label']?.toString(),
      deactivatedAt: DateTime.tryParse(
        json['deactivated_at']?.toString() ?? '',
      ),
    );
  }
}
