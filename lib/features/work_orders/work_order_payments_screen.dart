import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

class WorkOrderPaymentItem {
  const WorkOrderPaymentItem({
    required this.id,
    required this.workOrderId,
    required this.workOrderTitle,
    required this.customerId,
    required this.customerName,
    required this.amount,
    required this.currency,
    required this.paidAt,
  });

  final String id;
  final String? workOrderId;
  final String? workOrderTitle;
  final String? customerId;
  final String? customerName;
  final double amount;
  final String currency;
  final DateTime? paidAt;

  factory WorkOrderPaymentItem.fromJson(Map<String, dynamic> json) {
    final amountRaw = json['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString().replaceAll(',', '.') ?? '') ??
            0.0;
    return WorkOrderPaymentItem(
      id: json['id']?.toString() ?? '',
      workOrderId: json['work_order_id']?.toString(),
      workOrderTitle: json['work_order_title']?.toString(),
      customerId: json['customer_id']?.toString(),
      customerName: json['customer_name']?.toString(),
      amount: amount,
      currency: (json['currency'] ?? 'TRY').toString(),
      paidAt: json['paid_at'] == null
          ? null
          : DateTime.tryParse(json['paid_at'].toString()),
    );
  }
}

final workOrderPaymentsProvider = FutureProvider.family<
    List<WorkOrderPaymentItem>,
    ({String from, String to})>((ref, range) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'work_order_payments',
        'from': range.from,
        'to': range.to,
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(WorkOrderPaymentItem.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('payments')
      .select('id,work_order_id,customer_id,amount,currency,paid_at,is_active')
      .eq('is_active', true)
      .gte('paid_at', '${range.from}T00:00:00')
      .lte('paid_at', '${range.to}T23:59:59')
      .order('paid_at', ascending: false);

  return (rows as List)
      .map((e) => WorkOrderPaymentItem.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

class WorkOrderPaymentsScreen extends ConsumerStatefulWidget {
  const WorkOrderPaymentsScreen({super.key});

  @override
  ConsumerState<WorkOrderPaymentsScreen> createState() =>
      _WorkOrderPaymentsScreenState();
}

class _WorkOrderPaymentsScreenState extends ConsumerState<WorkOrderPaymentsScreen> {
  DateTime _from = DateTime.now();
  DateTime _to = DateTime.now();

  @override
  Widget build(BuildContext context) {
    final fromStr = DateFormat('yyyy-MM-dd').format(_from);
    final toStr = DateFormat('yyyy-MM-dd').format(_to);
    final paymentsAsync =
        ref.watch(workOrderPaymentsProvider((from: fromStr, to: toStr)));

    return AppPageLayout(
      title: 'Tahsilatlar',
      subtitle: 'İş emri ödemelerini tarih bazlı görüntüleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(
            workOrderPaymentsProvider((from: fromStr, to: toStr)),
          ),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 980;

                final controls = Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        final now = DateTime.now();
                        _from = DateTime(now.year, now.month, now.day);
                        _to = DateTime(now.year, now.month, now.day);
                      }),
                      child: const Text('Bugün'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        final now = DateTime.now();
                        _to = DateTime(now.year, now.month, now.day);
                        _from = _to.subtract(const Duration(days: 6));
                      }),
                      child: const Text('Son 7 Gün'),
                    ),
                    FilledButton.tonal(
                      onPressed: () => setState(() {
                        final now = DateTime.now();
                        _from = DateTime(now.year, now.month, 1);
                        _to = DateTime(now.year, now.month + 1, 0);
                      }),
                      child: const Text('Bu Ay'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _from,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked == null) return;
                        setState(() {
                          _from = picked;
                          if (_to.isBefore(_from)) _to = _from;
                        });
                      },
                      icon: const Icon(Icons.event_rounded, size: 18),
                      label: Text('Başlangıç: $fromStr'),
                    ),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _to,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked == null) return;
                        setState(() {
                          _to = picked;
                          if (_to.isBefore(_from)) _from = _to;
                        });
                      },
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text('Bitiş: $toStr'),
                    ),
                  ],
                );

                return wide
                    ? Row(
                        children: [
                          Expanded(child: controls),
                        ],
                      )
                    : controls;
              },
            ),
          ),
          const Gap(12),
          Expanded(
            child: paymentsAsync.when(
              data: (items) {
                if (items.isEmpty) {
                  return const AppCard(
                    child: Center(child: Text('Kayıt bulunamadı.')),
                  );
                }

                final totalsByCurrency = <String, double>{};
                for (final item in items) {
                  totalsByCurrency.update(
                    item.currency,
                    (value) => value + item.amount,
                    ifAbsent: () => item.amount,
                  );
                }

                return Column(
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        AppBadge(
                          label: 'Toplam: ${items.length}',
                          tone: AppBadgeTone.primary,
                        ),
                        for (final entry in totalsByCurrency.entries)
                          AppBadge(
                            label:
                                '${entry.key}: ${entry.value.toStringAsFixed(2)}',
                            tone: AppBadgeTone.neutral,
                          ),
                      ],
                    ),
                    const Gap(12),
                    Expanded(
                      child: ListView.separated(
                        padding: EdgeInsets.zero,
                        itemCount: items.length,
                        separatorBuilder: (context, index) => const Gap(10),
                        itemBuilder: (context, index) => _PaymentRow(
                          item: items[index],
                        ),
                      ),
                    ),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Tahsilatlar yüklenemedi: $error',
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

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({required this.item});

  final WorkOrderPaymentItem item;

  @override
  Widget build(BuildContext context) {
    final paidAt = item.paidAt == null
        ? null
        : DateFormat('d MMM y HH:mm', 'tr_TR').format(item.paidAt!.toLocal());

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
            ),
            child: Center(
              child: Text(
                item.currency,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: AppTheme.primary,
                    ),
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${item.amount.toStringAsFixed(2)} ${item.currency}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                ),
                const Gap(4),
                Text(
                  [
                    item.customerName?.trim().isNotEmpty ?? false
                        ? item.customerName!.trim()
                        : null,
                    item.workOrderTitle?.trim().isNotEmpty ?? false
                        ? item.workOrderTitle!.trim()
                        : null,
                  ].whereType<String>().join(' • '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          if (paidAt != null) ...[
            const Gap(10),
            Text(
              paidAt,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: AppTheme.textMuted),
            ),
          ],
        ],
      ),
    );
  }
}
