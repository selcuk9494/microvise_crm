import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/app_date_time.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phosphor_icons.dart';
import '../../core/ui/empty_state_card.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

class PosCollectionsFilter {
  final DateTime startDate;
  final DateTime endDate;
  final bool includeRefunded;

  const PosCollectionsFilter({
    required this.startDate,
    required this.endDate,
    this.includeRefunded = false,
  });

  PosCollectionsFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    bool? includeRefunded,
  }) {
    return PosCollectionsFilter(
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      includeRefunded: includeRefunded ?? this.includeRefunded,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is PosCollectionsFilter &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.includeRefunded == includeRefunded;
  }

  @override
  int get hashCode => Object.hash(startDate, endDate, includeRefunded);
}

class PosCollectionRow {
  final String id;
  final String customerId;
  final String? customerName;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? invoiceStatus;
  final double amount;
  final String currency;
  final DateTime paidOn;
  final DateTime createdAt;
  final String? description;
  final bool isActive;
  final String? providerOrderId;
  final String? paymentLinkStatus;

  const PosCollectionRow({
    required this.id,
    required this.customerId,
    this.customerName,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceStatus,
    required this.amount,
    required this.currency,
    required this.paidOn,
    required this.createdAt,
    this.description,
    this.isActive = true,
    this.providerOrderId,
    this.paymentLinkStatus,
  });

  static double _toDouble(dynamic value, {double fallback = 0}) {
    if (value == null) return fallback;
    if (value is num) return value.toDouble();
    final text = value.toString().trim().replaceAll(',', '.');
    if (text.isEmpty) return fallback;
    return double.tryParse(text) ?? fallback;
  }

  static int _toInt(dynamic value, {int fallback = 0}) {
    if (value == null) return fallback;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString().trim()) ?? fallback;
  }

  factory PosCollectionRow.fromJson(Map<String, dynamic> json) {
    final invoices = json['invoices'];
    final customers = json['customers'];
    return PosCollectionRow(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString() ?? '',
      customerName: customers is Map ? customers['name']?.toString() : null,
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: invoices is Map
          ? invoices['invoice_number']?.toString()
          : null,
      invoiceStatus: invoices is Map ? invoices['status']?.toString() : null,
      amount: _toDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'TRY',
      paidOn:
          parseAppDateTime(json['paid_on']?.toString()) ??
          parseAppDateTime(json['transaction_date']?.toString()) ??
          appNow(),
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
      description: json['description']?.toString(),
      isActive: json['is_active'] == true ||
          json['is_active']?.toString().toLowerCase() == 'true',
      providerOrderId: json['provider_order_id']?.toString(),
      paymentLinkStatus: json['payment_link_status']?.toString(),
    );
  }
}

class PosCollectionsResult {
  final List<PosCollectionRow> items;
  final int count;
  final int activeCount;
  final double totalAmount;

  const PosCollectionsResult({
    required this.items,
    required this.count,
    required this.activeCount,
    required this.totalAmount,
  });
}

final posCollectionsProvider = FutureProvider.autoDispose
    .family<PosCollectionsResult, PosCollectionsFilter>((ref, filter) async {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) {
        return const PosCollectionsResult(
          items: [],
          count: 0,
          activeCount: 0,
          totalAmount: 0,
        );
      }
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'pos_collections_list',
          'startDate': filter.startDate.toIso8601String().substring(0, 10),
          'endDate': filter.endDate.toIso8601String().substring(0, 10),
          'includeRefunded': filter.includeRefunded.toString(),
        },
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PosCollectionRow.fromJson)
          .toList(growable: false);
      final summary = response['summary'];
      final summaryMap = summary is Map ? Map<String, dynamic>.from(summary) : null;
      return PosCollectionsResult(
        items: items,
        count: PosCollectionRow._toInt(
          summaryMap?['count'],
          fallback: items.length,
        ),
        activeCount: PosCollectionRow._toInt(
          summaryMap?['activeCount'],
          fallback: items.where((e) => e.isActive).length,
        ),
        totalAmount: PosCollectionRow._toDouble(
          summaryMap?['totalAmount'],
          fallback: items
              .where((e) => e.isActive)
              .fold<double>(0, (sum, e) => sum + e.amount),
        ),
      );
    });

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

class PosCollectionsTab extends ConsumerStatefulWidget {
  const PosCollectionsTab({super.key, required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<PosCollectionsTab> createState() => _PosCollectionsTabState();
}

class _PosCollectionsTabState extends ConsumerState<PosCollectionsTab> {
  late DateTime _start;
  late DateTime _end;
  bool _includeRefunded = false;
  bool _refundingId = false;

  @override
  void initState() {
    super.initState();
    final today = _dateOnly(DateTime.now());
    _start = today;
    _end = today;
  }

  PosCollectionsFilter get _filter => PosCollectionsFilter(
    startDate: _start,
    endDate: _end,
    includeRefunded: _includeRefunded,
  );

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 2),
      lastDate: DateTime(now.year + 1),
      initialDateRange: DateTimeRange(start: _start, end: _end),
      locale: const Locale('tr', 'TR'),
      helpText: 'Sanal POS tarih aralığı',
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = _dateOnly(picked.start);
      _end = _dateOnly(picked.end);
    });
  }

  void _setToday() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _start = today;
      _end = today;
    });
  }

  void _setYesterday() {
    final day = _dateOnly(DateTime.now().subtract(const Duration(days: 1)));
    setState(() {
      _start = day;
      _end = day;
    });
  }

  Future<void> _refund(PosCollectionRow row) async {
    if (row.invoiceId == null || row.invoiceId!.isEmpty || !row.isActive) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sanal POS iade'),
        content: Text(
          '${formatInvoiceNumberForDisplay(row.invoiceNumber)} · '
          '${row.customerName ?? 'Cari'}\n'
          '${widget.moneyTry.format(row.amount)} bankaya iade edilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('İade Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _refundingId = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'refundInvoicePosPayment',
          'invoiceId': row.invoiceId,
          'transactionId': row.id,
        },
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ?? 'Sanal POS iadesi tamamlandı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('İade başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _refundingId = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(posCollectionsProvider(_filter));
    final dateLabel = _start == _end
        ? DateFormat('d MMM yyyy', 'tr_TR').format(_start)
        : '${DateFormat('d MMM', 'tr_TR').format(_start)} – ${DateFormat('d MMM yyyy', 'tr_TR').format(_end)}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppCard(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Ödeme linki ile otomatik kapanan tahsilatlar',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(4),
              Text(
                'Gözden kaçırmamak için tarih seçerek listeleyin.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: _setToday,
                    icon: const Icon(AppPhosphorIcons.calendarBlank, size: 16),
                    label: const Text('Bugün'),
                  ),
                  OutlinedButton(
                    onPressed: _setYesterday,
                    child: const Text('Dün'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pickRange,
                    icon: const Icon(Icons.date_range, size: 16),
                    label: Text(dateLabel),
                  ),
                  FilterChip(
                    label: const Text('İadeler dahil'),
                    selected: _includeRefunded,
                    onSelected: (value) {
                      setState(() => _includeRefunded = value);
                    },
                  ),
                  IconButton(
                    tooltip: 'Yenile',
                    onPressed: () =>
                        ref.invalidate(posCollectionsProvider(_filter)),
                    icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(10),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => EmptyStateCard(
              icon: AppPhosphorIcons.warningCircle,
              title: 'Liste alınamadı',
              message: '$error',
            ),
            data: (result) {
              if (result.items.isEmpty) {
                return const EmptyStateCard(
                  icon: AppPhosphorIcons.money,
                  title: 'Sanal POS tahsilatı yok',
                  message:
                      'Seçilen tarihte kayıt yok. Bugün / dün veya farklı tarih deneyin.',
                );
              }
              return Column(
                children: [
                  AppCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${result.activeCount} tahsilat · ${widget.moneyTry.format(result.totalAmount)}',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        if (result.count != result.activeCount)
                          Text(
                            '${result.count - result.activeCount} iade',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: ListView.separated(
                      itemCount: result.items.length,
                      separatorBuilder: (_, __) => const Gap(8),
                      itemBuilder: (context, index) {
                        final row = result.items[index];
                        final invoiceLabel = formatInvoiceNumberForDisplay(
                          row.invoiceNumber,
                        );
                        return AppCard(
                          padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      invoiceLabel.isEmpty
                                          ? 'Fatura'
                                          : invoiceLabel,
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleSmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.w800,
                                          ),
                                    ),
                                    const Gap(2),
                                    Text(
                                      row.customerName ?? 'Cari',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: AppTheme.textMuted,
                                          ),
                                    ),
                                    const Gap(6),
                                    Wrap(
                                      spacing: 6,
                                      runSpacing: 6,
                                      children: [
                                        AppBadge(
                                          dense: true,
                                          label: row.isActive
                                              ? 'Ödendi'
                                              : 'İade edildi',
                                          tone: row.isActive
                                              ? AppBadgeTone.success
                                              : AppBadgeTone.warning,
                                        ),
                                        AppBadge(
                                          dense: true,
                                          label: 'Sanal POS',
                                          tone: AppBadgeTone.primary,
                                        ),
                                        if ((row.invoiceStatus ?? '') == 'paid')
                                          const AppBadge(
                                            dense: true,
                                            label: 'Fatura kapalı',
                                            tone: AppBadgeTone.success,
                                          ),
                                        Text(
                                          DateFormat(
                                            'd MMM yyyy HH:mm',
                                            'tr_TR',
                                          ).format(row.createdAt.toLocal()),
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: AppTheme.textMuted,
                                              ),
                                        ),
                                      ],
                                    ),
                                    if ((row.providerOrderId ?? '')
                                        .isNotEmpty) ...[
                                      const Gap(4),
                                      Text(
                                        'Sipariş: ${row.providerOrderId}',
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              fontFamily: 'monospace',
                                              fontSize: 11,
                                              color: AppTheme.textSoft,
                                            ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Gap(8),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    widget.moneyTry.format(row.amount),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  if (row.isActive &&
                                      (row.invoiceId ?? '').isNotEmpty) ...[
                                    const Gap(8),
                                    TextButton(
                                      onPressed: _refundingId
                                          ? null
                                          : () => _refund(row),
                                      child: const Text('İade'),
                                    ),
                                  ],
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}
