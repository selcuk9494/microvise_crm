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

final invoiceItemsProvider = FutureProvider<List<InvoiceItem>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'invoice_items_queue'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(InvoiceItem.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
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

class BillingScreen extends ConsumerWidget {
  const BillingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView = ref.watch(hasPageAccessProvider(kPageBilling));
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final itemsAsync = ref.watch(invoiceItemsProvider);
    final money =
        NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2);

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
      body: Column(
        children: [
          if (!canView)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Bu sayfaya erişiminiz yok.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            )
          else
            itemsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Fatura listesi boş.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ),
                  );
                }

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Container(
                        height: 44,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        color: const Color(0xFFF8FAFC),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Kalem',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w600,
                                      color: const Color(0xFF475569),
                                    ),
                              ),
                            ),
                            const SizedBox(width: 140),
                            const SizedBox(width: 120),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) => _InvoiceRow(
                          item: items[index],
                          money: money,
                          canEdit: canEdit,
                          canArchive: canArchive,
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (e, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Fatura listesi yüklenemedi. Migration 0003 çalıştı mı?',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
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
  const _InvoiceRow({
    required this.item,
    required this.money,
    required this.canEdit,
    required this.canArchive,
  });

  final InvoiceItem item;
  final NumberFormat money;
  final bool canEdit;
  final bool canArchive;

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
      final nextStatus = widget.item.status == 'pending' ? 'invoiced' : 'pending';
      final profile = await ref.read(currentUserProfileProvider.future);
      final userId = profile?.id;
      final now = DateTime.now().toIso8601String();

      if (apiClient != null) {
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
      } else {
        try {
          await client!.from('invoice_items').update({
            'status': nextStatus,
            'invoiced_at': nextStatus == 'invoiced' ? now : null,
            'approved_by': nextStatus == 'invoiced' ? userId : null,
            'approved_at': nextStatus == 'invoiced' ? now : null,
            'updated_by': userId,
            'updated_at': now,
          }).eq('id', widget.item.id);
        } catch (_) {
          await client!.from('invoice_items').update({
            'status': nextStatus,
          }).eq('id', widget.item.id);
        }
      }
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Güncellenemedi.')),
      );
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
      } else {
        try {
          await client!.from('invoice_items').update({
            'is_active': nextActive,
            'deactivated_by': nextActive ? null : userId,
            'deactivated_at': nextActive ? null : now,
            'updated_by': userId,
            'updated_at': now,
          }).eq('id', widget.item.id);
        } catch (_) {
          await client!.from('invoice_items').update({
            'is_active': nextActive,
          }).eq('id', widget.item.id);
        }
      }
      ref.invalidate(invoiceItemsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt güncellenemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
        : '${widget.money.format(item.amount)} ${item.currency}';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration:
                            item.isActive ? TextDecoration.none : TextDecoration.lineThrough,
                      ),
                ),
                const Gap(4),
                Text(
                  [
                    item.customerLabel?.trim().isNotEmpty ?? false
                        ? item.customerLabel!.trim()
                        : null,
                    amountText,
                  ].whereType<String>().join(' • '),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 140),
          SizedBox(
            width: 120,
            child: Align(
              alignment: Alignment.centerRight,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  AppBadge(label: statusLabel, tone: tone),
                  const Gap(10),
                  IconButton(
                    tooltip: item.isActive ? 'Pasife Al' : 'Aktifleştir',
                    onPressed: _saving ? null : _toggleActive,
                    icon: Icon(
                      item.isActive
                          ? Icons.delete_outline_rounded
                          : Icons.restore_rounded,
                      color: AppTheme.textMuted,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Durum Değiştir',
                    onPressed: _saving ? null : _toggleInvoiced,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            item.status == 'pending'
                                ? Icons.check_rounded
                                : Icons.undo_rounded,
                            color: AppTheme.primary,
                          ),
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
  final String? customerLabel;

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString(),
      itemType: (json['item_type'] ?? '').toString(),
      description: (json['description'] ?? '').toString(),
      amount: (json['amount'] as num?)?.toDouble(),
      currency: (json['currency'] ?? 'TRY').toString(),
      status: (json['status'] ?? 'pending').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      customerLabel: json['customer_label']?.toString(),
    );
  }
}
