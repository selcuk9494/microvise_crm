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

final billingFiltersProvider =
    NotifierProvider<BillingFiltersNotifier, BillingFilters>(
      BillingFiltersNotifier.new,
    );

class BillingFiltersNotifier extends Notifier<BillingFilters> {
  @override
  BillingFilters build() => const BillingFilters(search: '', status: 'all');

  void setSearch(String value) => state = state.copyWith(search: value);

  void setStatus(String value) => state = state.copyWith(status: value);
}

class BillingFilters {
  const BillingFilters({required this.search, required this.status});

  final String search;
  final String status;

  BillingFilters copyWith({String? search, String? status}) {
    return BillingFilters(
      search: search ?? this.search,
      status: status ?? this.status,
    );
  }
}

final invoiceItemsProvider = FutureProvider<List<InvoiceItem>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('invoice_items')
      .select(
        'id,customer_id,item_type,description,amount,currency,status,created_at,invoiced_at,customers(name)',
      )
      .order('created_at', ascending: false)
      .limit(200);

  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customer = map['customers'] as Map<String, dynamic>?;
        return InvoiceItem.fromJson({
          ...map,
          'customer_label': customer?['name'],
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
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '₺',
      decimalDigits: 2,
    );

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
                          (item.customerLabel ?? '').toLowerCase().contains(
                            search,
                          );
                      final matchesStatus =
                          filters.status == 'all' ||
                          item.status == filters.status;
                      return matchesSearch && matchesStatus;
                    })
                    .toList(growable: false);

                if (items.isEmpty) {
                  return AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Fatura listesi boş.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ),
                  );
                }

                final pendingCount = items
                    .where((item) => item.status == 'pending')
                    .length;
                final invoicedCount = items
                    .where((item) => item.status == 'invoiced')
                    .length;
                final pendingAmount = items
                    .where((item) => item.status == 'pending')
                    .fold<double>(0, (sum, item) => sum + (item.amount ?? 0));

                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _BillingStatCard(
                            label: 'Toplam Kalem',
                            value: items.length.toString(),
                            icon: Icons.receipt_long_rounded,
                            tone: AppBadgeTone.primary,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _BillingStatCard(
                            label: 'Bekleyen',
                            value: pendingCount.toString(),
                            icon: Icons.hourglass_top_rounded,
                            tone: AppBadgeTone.warning,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _BillingStatCard(
                            label: 'Kesilen',
                            value: invoicedCount.toString(),
                            icon: Icons.check_circle_outline_rounded,
                            tone: AppBadgeTone.success,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: _BillingStatCard(
                            label: 'Bekleyen Tutar',
                            value: money.format(pendingAmount),
                            icon: Icons.payments_outlined,
                            tone: AppBadgeTone.neutral,
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    AppCard(
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextField(
                                  onChanged: ref
                                      .read(billingFiltersProvider.notifier)
                                      .setSearch,
                                  decoration: const InputDecoration(
                                    labelText: 'Kalem Ara',
                                    hintText: 'Açıklama veya müşteri adı',
                                    prefixIcon: Icon(Icons.search_rounded),
                                  ),
                                ),
                              ),
                              const Gap(12),
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: filters.status,
                                  items: const [
                                    DropdownMenuItem(
                                      value: 'all',
                                      child: Text('Tüm Durumlar'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'pending',
                                      child: Text('Bekliyor'),
                                    ),
                                    DropdownMenuItem(
                                      value: 'invoiced',
                                      child: Text('Kesildi'),
                                    ),
                                  ],
                                  onChanged: (value) => ref
                                      .read(billingFiltersProvider.notifier)
                                      .setStatus(value ?? 'all'),
                                  decoration: const InputDecoration(
                                    labelText: 'Durum',
                                    prefixIcon: Icon(Icons.tune_rounded),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          if (filters.search.isNotEmpty ||
                              filters.status != 'all') ...[
                            const Gap(12),
                            Align(
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
                                  if (filters.status != 'all')
                                    AppBadge(
                                      label:
                                          'Durum: ${filters.status == 'pending' ? 'Bekliyor' : 'Kesildi'}',
                                      tone: AppBadgeTone.neutral,
                                    ),
                                  TextButton.icon(
                                    onPressed: () {
                                      ref
                                          .read(billingFiltersProvider.notifier)
                                          .setSearch('');
                                      ref
                                          .read(billingFiltersProvider.notifier)
                                          .setStatus('all');
                                    },
                                    icon: const Icon(
                                      Icons.clear_rounded,
                                      size: 18,
                                    ),
                                    label: const Text('Temizle'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const Gap(16),
                    AppCard(
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
                                    style: Theme.of(context).textTheme.bodySmall
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
                          if (filtered.isEmpty)
                            Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                'Filtrelere uygun kalem bulunamadı.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: const Color(0xFF64748B)),
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
                    'Fatura listesi yüklenemedi. Migration 0003 çalıştı mı?',
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

  Future<void> _toggleInvoiced() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final nextStatus = widget.item.status == 'pending'
          ? 'invoiced'
          : 'pending';
      await client
          .from('invoice_items')
          .update({
            'status': nextStatus,
            'invoiced_at': nextStatus == 'invoiced'
                ? DateTime.now().toIso8601String()
                : null,
          })
          .eq('id', widget.item.id);
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Gap(4),
                Text(
                  item.customerLabel ?? 'Müşteri atanmadı',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF475569),
                  ),
                ),
                const Gap(4),
                Text(
                  amountText,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
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
    required this.customerLabel,
  });

  final String id;
  final String? customerId;
  final String itemType;
  final String description;
  final double? amount;
  final String currency;
  final String status;
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
      customerLabel: json['customer_label']?.toString(),
    );
  }
}

class _BillingStatCard extends StatelessWidget {
  const _BillingStatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.primary => AppTheme.primary,
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => const Color(0xFF64748B),
    };

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
