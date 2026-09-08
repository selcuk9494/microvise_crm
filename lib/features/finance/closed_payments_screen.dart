import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/app_date_time.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_phone_scroll.dart';
import '../../core/ui/empty_state_card.dart';
import '../e_invoice/pos_collections_tab.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _dateIso(DateTime date) => date.toIso8601String().substring(0, 10);

class ClosedPaymentsFilter {
  const ClosedPaymentsFilter({
    this.startDate,
    this.endDate,
    this.paymentMethod,
    this.transactionType,
    this.invoiceType,
    this.currency,
    this.search = '',
  });

  final DateTime? startDate;
  final DateTime? endDate;
  final String? paymentMethod;
  final String? transactionType;
  final String? invoiceType;
  final String? currency;
  final String search;

  ClosedPaymentsFilter copyWith({
    DateTime? startDate,
    DateTime? endDate,
    String? paymentMethod,
    String? transactionType,
    String? invoiceType,
    String? currency,
    String? search,
    bool clearStart = false,
    bool clearEnd = false,
    bool clearMethod = false,
    bool clearTxType = false,
    bool clearInvoiceType = false,
    bool clearCurrency = false,
  }) {
    return ClosedPaymentsFilter(
      startDate: clearStart ? null : startDate ?? this.startDate,
      endDate: clearEnd ? null : endDate ?? this.endDate,
      paymentMethod: clearMethod ? null : paymentMethod ?? this.paymentMethod,
      transactionType: clearTxType
          ? null
          : transactionType ?? this.transactionType,
      invoiceType: clearInvoiceType ? null : invoiceType ?? this.invoiceType,
      currency: clearCurrency ? null : currency ?? this.currency,
      search: search ?? this.search,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ClosedPaymentsFilter &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.paymentMethod == paymentMethod &&
        other.transactionType == transactionType &&
        other.invoiceType == invoiceType &&
        other.currency == currency &&
        other.search == search;
  }

  @override
  int get hashCode => Object.hash(
    startDate,
    endDate,
    paymentMethod,
    transactionType,
    invoiceType,
    currency,
    search,
  );
}

class ClosedPaymentRow {
  const ClosedPaymentRow({
    required this.id,
    required this.customerId,
    required this.amount,
    required this.currency,
    required this.exchangeRate,
    required this.paymentMethod,
    required this.transactionType,
    required this.transactionDate,
    required this.createdAt,
    required this.isActive,
    this.customerName,
    this.invoiceId,
    this.invoiceNumber,
    this.invoiceStatus,
    this.invoiceType,
    this.description,
    this.akinsoftSourceId,
    this.invoiceActivePaymentCount = 0,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final double amount;
  final String currency;
  final double exchangeRate;
  final String paymentMethod;
  final String transactionType;
  final DateTime transactionDate;
  final DateTime createdAt;
  final bool isActive;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? invoiceStatus;
  final String? invoiceType;
  final String? description;
  final String? akinsoftSourceId;
  final int invoiceActivePaymentCount;

  bool get isSanalPos {
    final desc = (description ?? '').toLowerCase();
    return desc.contains('sanal pos') || desc.contains('ödeme linki');
  }

  bool get isLinkedToAkinsoft => (akinsoftSourceId ?? '').trim().isNotEmpty;

  bool get isLastInvoicePayment => invoiceActivePaymentCount <= 1;

  String get invoiceNumberDisplay =>
      formatInvoiceNumberForDisplay(invoiceNumber);

  factory ClosedPaymentRow.fromJson(Map<String, dynamic> json) {
    final customer = json['customers'] as Map<String, dynamic>?;
    final invoice = json['invoices'] as Map<String, dynamic>?;
    return ClosedPaymentRow(
      id: json['id']?.toString() ?? '',
      customerId: json['customer_id']?.toString() ?? '',
      customerName: customer?['name']?.toString(),
      amount: _jsonDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: _jsonDouble(json['exchange_rate'], fallback: 1),
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      transactionType: json['transaction_type']?.toString() ?? 'collection',
      transactionDate:
          parseAppDateTime(json['transaction_date']?.toString()) ?? appNow(),
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
      isActive: json['is_active'] != false,
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: invoice?['invoice_number']?.toString(),
      invoiceStatus: invoice?['status']?.toString(),
      invoiceType: invoice?['invoice_type']?.toString(),
      description: json['description']?.toString(),
      akinsoftSourceId: json['akinsoft_source_id']?.toString(),
      invoiceActivePaymentCount: _jsonInt(json['invoice_active_payment_count']),
    );
  }
}

class ClosedPaymentsResult {
  const ClosedPaymentsResult({
    required this.items,
    this.count = 0,
    this.totals = const {},
    this.truncated = false,
  });

  final List<ClosedPaymentRow> items;
  final int count;
  final Map<String, double> totals;
  final bool truncated;
}

double _jsonDouble(dynamic value, {double fallback = 0}) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ??
      fallback;
}

int _jsonInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

final closedPaymentsProvider = FutureProvider.autoDispose
    .family<ClosedPaymentsResult, ClosedPaymentsFilter>((ref, filter) async {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) {
        return const ClosedPaymentsResult(items: []);
      }
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'transactions_list',
          if (filter.startDate != null)
            'startDate': _dateIso(filter.startDate!),
          if (filter.endDate != null) 'endDate': _dateIso(filter.endDate!),
          if (filter.paymentMethod != null)
            'paymentMethod': filter.paymentMethod!,
          if (filter.transactionType != null)
            'transactionType': filter.transactionType!,
          if (filter.invoiceType != null) 'invoiceType': filter.invoiceType!,
          if (filter.currency != null) 'currency': filter.currency!,
          if (filter.search.trim().isNotEmpty) 'search': filter.search.trim(),
        },
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ClosedPaymentRow.fromJson)
          .toList(growable: false);
      final summary = response['summary'];
      final summaryMap = summary is Map
          ? Map<String, dynamic>.from(summary)
          : null;
      final totalsRaw = summaryMap?['totals'];
      final totals = <String, double>{};
      if (totalsRaw is Map) {
        for (final entry in totalsRaw.entries) {
          totals[entry.key.toString()] = _jsonDouble(entry.value);
        }
      }
      return ClosedPaymentsResult(
        items: items,
        count: _jsonInt(summaryMap?['count'] ?? items.length),
        totals: totals,
        truncated: summaryMap?['truncated'] == true,
      );
    });

String paymentMethodLabel(String method, {String? description}) {
  final desc = (description ?? '').toLowerCase();
  if (desc.contains('sanal pos') || desc.contains('ödeme linki')) {
    return 'Sanal POS';
  }
  return switch (method.trim().toLowerCase()) {
    'cash' || 'nakit' => 'Nakit',
    'bank' || 'havale' || 'eft' => 'Havale / EFT',
    'check' || 'cheque' || 'cek' || 'çek' => 'Çek',
    'pos' => 'POS',
    'credit_card' || 'kart' => 'Kredi kartı',
    'other' => 'Diğer',
    _ => method.isEmpty ? 'Diğer' : method,
  };
}

String _txTypeLabel(String type) => type == 'payment' ? 'Ödeme' : 'Tahsilat';

String _invoiceStatusLabel(String? status) {
  return switch ((status ?? '').trim().toLowerCase()) {
    'paid' => 'Kapalı',
    'partial' => 'Kısmi',
    'open' => 'Açık',
    'draft' => 'Taslak',
    'cancelled' => 'İptal',
    _ => status == null || status.isEmpty ? '—' : status,
  };
}

AppBadgeTone _invoiceStatusTone(String? status) {
  return switch ((status ?? '').trim().toLowerCase()) {
    'paid' => AppBadgeTone.success,
    'partial' => AppBadgeTone.warning,
    'cancelled' => AppBadgeTone.error,
    'draft' => AppBadgeTone.neutral,
    _ => AppBadgeTone.primary,
  };
}

class ClosedPaymentsScreen extends ConsumerStatefulWidget {
  const ClosedPaymentsScreen({super.key});

  @override
  ConsumerState<ClosedPaymentsScreen> createState() =>
      _ClosedPaymentsScreenState();
}

class _ClosedPaymentsScreenState extends ConsumerState<ClosedPaymentsScreen> {
  DateTime? _start;
  DateTime? _end;
  String? _method;
  String? _txType;
  String? _invoiceType;
  String? _currency;
  String _search = '';
  bool _busy = false;
  final _searchController = TextEditingController();

  ClosedPaymentsFilter get _filter => ClosedPaymentsFilter(
    startDate: _start,
    endDate: _end,
    paymentMethod: _method,
    transactionType: _txType,
    invoiceType: _invoiceType,
    currency: _currency,
    search: _search,
  );

  bool get _isAllDates => _start == null || _end == null;

  bool get _isToday {
    if (_start == null || _end == null) return false;
    final today = _dateOnly(DateTime.now());
    return _start == today && _end == today;
  }

  bool get _isThisMonth {
    if (_start == null || _end == null) return false;
    final today = _dateOnly(DateTime.now());
    return _start == DateTime(today.year, today.month, 1) && _end == today;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _setAllDates() => setState(() {
    _start = null;
    _end = null;
  });

  void _setToday() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _start = today;
      _end = today;
    });
  }

  void _setMonth() {
    final today = _dateOnly(DateTime.now());
    setState(() {
      _start = DateTime(today.year, today.month, 1);
      _end = today;
    });
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: _start != null && _end != null
          ? DateTimeRange(start: _start!, end: _end!)
          : DateTimeRange(
              start: DateTime(now.year, now.month, 1),
              end: _dateOnly(now),
            ),
    );
    if (picked == null) return;
    setState(() {
      _start = _dateOnly(picked.start);
      _end = _dateOnly(picked.end);
    });
  }

  Future<void> _delete(ClosedPaymentRow row) async {
    final money = formatPosMoney(row.amount, row.currency);
    final method = paymentMethodLabel(
      row.paymentMethod,
      description: row.description,
    );
    final sapNote = row.isLinkedToAkinsoft && row.isLastInvoicePayment
        ? '\n\nSAP’a yazılmışsa Wolvox tahsilatı da silinmeye çalışılır.'
        : row.isLinkedToAkinsoft
        ? '\n\nFaturada başka CRM ödemesi kaldığı için SAP kaydı silinmez.'
        : '';
    final posNote = row.isSanalPos
        ? '\n\nSanal POS: karttan otomatik iade yapılmaz; yalnızca CRM hareketi kalkar.'
        : '';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödemeyi sil'),
        content: Text(
          '${row.customerName ?? 'Cari'}'
          '${row.invoiceNumberDisplay.isEmpty ? '' : ' · ${row.invoiceNumberDisplay}'}'
          '\n$method · ${_txTypeLabel(row.transactionType)} · $money'
          '\n\nBu kayıt silinecek; ilgili faturanın ödeme hareketi düşecek '
          've fatura tutarı yeniden hesaplanacak.'
          '$posNote$sapNote',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    String? sapError;
    try {
      if (row.isLinkedToAkinsoft &&
          row.isLastInvoicePayment &&
          (row.invoiceId ?? '').isNotEmpty) {
        try {
          await _postAkinsoftFinance('finance/collection', {
            'action': 'reverse',
            'invoiceSourceId': row.akinsoftSourceId,
            'invoiceNumber': row.invoiceNumber,
            'invoiceType': row.invoiceType,
          });
        } catch (error) {
          sapError = _akinsoftBridgeError(error);
        }
      }
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'reverseInvoiceCollection',
          if ((row.invoiceId ?? '').isNotEmpty) 'invoiceId': row.invoiceId,
          'transactionId': row.id,
          'allowPos': true,
        },
      );
      if (!mounted) return;
      ref.invalidate(closedPaymentsProvider(_filter));
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      final crmMessage =
          response['message']?.toString() ??
          'Ödeme silindi; fatura hareketi düşüldü.';
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            sapError == null ? crmMessage : '$crmMessage SAP: $sapError',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Ödeme silinemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(closedPaymentsProvider(_filter));
    final dateLabel = _isAllDates
        ? 'Tüm tarihler'
        : _start == _end
        ? DateFormat('d MMM yyyy', 'tr_TR').format(_start!)
        : '${DateFormat('d MMM', 'tr_TR').format(_start!)} – ${DateFormat('d MMM yyyy', 'tr_TR').format(_end!)}';

    return AppPageLayout(
      title: 'Kapatılan Ödemeler',
      subtitle:
          'Nakit, çek, POS, havale ve döviz tahsilatları. Silinen kayıt faturanın ödeme hareketinden düşer.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(closedPaymentsProvider(_filter)),
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Stack(
        children: [
          AppPhoneScrollColumn(
            header: [
              AppCard(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        FilterChip(
                          label: const Text('Tümü'),
                          selected: _isAllDates,
                          onSelected: (_) => _setAllDates(),
                        ),
                        FilterChip(
                          label: const Text('Bugün'),
                          selected: _isToday,
                          onSelected: (_) => _setToday(),
                        ),
                        FilterChip(
                          label: const Text('Bu ay'),
                          selected: _isThisMonth && !_isToday,
                          onSelected: (_) => _setMonth(),
                        ),
                        OutlinedButton.icon(
                          onPressed: _pickRange,
                          icon: const Icon(Icons.date_range, size: 16),
                          label: Text(dateLabel),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _searchController,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Cari / fatura / açıklama',
                              prefixIcon: Icon(LucideIcons.search, size: 16),
                            ),
                            onSubmitted: (value) =>
                                setState(() => _search = value.trim()),
                          ),
                        ),
                        OutlinedButton(
                          onPressed: () => setState(
                            () => _search = _searchController.text.trim(),
                          ),
                          child: const Text('Ara'),
                        ),
                      ],
                    ),
                    const Gap(10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: 180,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('method-${_method ?? 'all'}'),
                            initialValue: _method,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Ödeme şekli',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tümü'),
                              ),
                              DropdownMenuItem(
                                value: 'cash',
                                child: Text('Nakit'),
                              ),
                              DropdownMenuItem(
                                value: 'bank',
                                child: Text('Havale / EFT'),
                              ),
                              DropdownMenuItem(
                                value: 'check',
                                child: Text('Çek'),
                              ),
                              DropdownMenuItem(
                                value: 'pos',
                                child: Text('POS'),
                              ),
                              DropdownMenuItem(
                                value: 'credit_card',
                                child: Text('Kredi kartı'),
                              ),
                              DropdownMenuItem(
                                value: 'fx',
                                child: Text('Döviz'),
                              ),
                              DropdownMenuItem(
                                value: 'other',
                                child: Text('Diğer'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _method = value),
                          ),
                        ),
                        SizedBox(
                          width: 170,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('type-${_txType ?? 'all'}'),
                            initialValue: _txType,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'İşlem',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tümü'),
                              ),
                              DropdownMenuItem(
                                value: 'collection',
                                child: Text('Tahsilat'),
                              ),
                              DropdownMenuItem(
                                value: 'payment',
                                child: Text('Ödeme'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _txType = value),
                          ),
                        ),
                        SizedBox(
                          width: 160,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('inv-${_invoiceType ?? 'all'}'),
                            initialValue: _invoiceType,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Fatura',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tümü'),
                              ),
                              DropdownMenuItem(
                                value: 'sales',
                                child: Text('Satış'),
                              ),
                              DropdownMenuItem(
                                value: 'purchase',
                                child: Text('Alış'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _invoiceType = value),
                          ),
                        ),
                        SizedBox(
                          width: 140,
                          child: DropdownButtonFormField<String?>(
                            key: ValueKey('cur-${_currency ?? 'all'}'),
                            initialValue: _currency,
                            decoration: const InputDecoration(
                              isDense: true,
                              labelText: 'Döviz',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: null,
                                child: Text('Tümü'),
                              ),
                              DropdownMenuItem(
                                value: 'TRY',
                                child: Text('TRY'),
                              ),
                              DropdownMenuItem(
                                value: 'USD',
                                child: Text('USD'),
                              ),
                              DropdownMenuItem(
                                value: 'EUR',
                                child: Text('EUR'),
                              ),
                              DropdownMenuItem(
                                value: 'GBP',
                                child: Text('GBP'),
                              ),
                              DropdownMenuItem(
                                value: 'FX',
                                child: Text('Döviz (hepsi)'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _currency = value),
                          ),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _start = null;
                              _end = null;
                              _method = null;
                              _txType = null;
                              _invoiceType = null;
                              _currency = null;
                              _search = '';
                            });
                          },
                          icon: const Icon(LucideIcons.sparkles, size: 16),
                          label: const Text('Temizle'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              async.maybeWhen(
                data: (data) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _SummaryChip(
                        label: 'Kayıt',
                        value: '${data.count}${data.truncated ? '+' : ''}',
                      ),
                      for (final entry in data.totals.entries)
                        _SummaryChip(
                          label: entry.key,
                          value: formatPosMoney(entry.value, entry.key),
                        ),
                    ],
                  ),
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
            body: ({required nested}) => async.when(
              loading: () => const Padding(
                padding: EdgeInsets.only(top: 24),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (error, _) => EmptyStateCard(
                icon: LucideIcons.circleAlert,
                title: 'Liste yüklenemedi',
                message: error.toString(),
                action: OutlinedButton(
                  onPressed: () =>
                      ref.invalidate(closedPaymentsProvider(_filter)),
                  child: const Text('Tekrar dene'),
                ),
              ),
              data: (data) {
                if (data.items.isEmpty) {
                  return const EmptyStateCard(
                    icon: LucideIcons.banknote,
                    title: 'Ödeme yok',
                    message:
                        'Filtreye uyan nakit, çek, POS veya döviz tahsilatı bulunamadı.',
                  );
                }
                final isPhone = AppPhoneScrollColumn.isPhone(context);
                if (isPhone) {
                  return ListView.separated(
                    shrinkWrap: nested,
                    physics: AppPhoneScrollColumn.physicsFor(nested: nested),
                    itemCount: data.items.length,
                    separatorBuilder: (_, _) => const Gap(AppDenseList.listGap),
                    itemBuilder: (context, index) => _PaymentCard(
                      row: data.items[index],
                      onDelete: _busy ? null : () => _delete(data.items[index]),
                    ),
                  );
                }
                return _PaymentsTable(
                  items: data.items,
                  nested: nested,
                  busy: _busy,
                  onDelete: _delete,
                );
              },
            ),
          ),
          if (_busy)
            const Positioned(
              left: 0,
              right: 0,
              top: 0,
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.titleSmall),
        ],
      ),
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({required this.row, this.onDelete});

  final ClosedPaymentRow row;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final collection = row.transactionType != 'payment';
    return AppDenseListCard(
      leading: AppDenseLeadingIcon(
        icon: collection ? LucideIcons.arrowDownLeft : LucideIcons.arrowUpRight,
        color: collection ? AppTheme.success : AppTheme.error,
      ),
      title: row.customerName ?? 'Cari',
      subtitle: row.invoiceNumberDisplay.isEmpty
          ? DateFormat('d MMM y', 'tr_TR').format(row.transactionDate)
          : '${row.invoiceNumberDisplay} · ${DateFormat('d MMM y', 'tr_TR').format(row.transactionDate)}',
      badge: AppBadge(
        label: paymentMethodLabel(
          row.paymentMethod,
          description: row.description,
        ),
        tone: row.isSanalPos ? AppBadgeTone.primary : AppBadgeTone.neutral,
        dense: true,
      ),
      meta: [
        AppDenseInfoChip(
          icon: LucideIcons.banknote,
          text: formatPosMoney(row.amount, row.currency),
          color: collection ? AppTheme.success : AppTheme.error,
        ),
        AppDenseInfoChip(
          icon: LucideIcons.receiptText,
          text: _invoiceStatusLabel(row.invoiceStatus),
        ),
      ],
      actions: [
        IconButton(
          tooltip: 'Sil',
          onPressed: onDelete,
          icon: const Icon(LucideIcons.trash2, size: AppDenseList.actionIcon),
        ),
      ],
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({
    required this.items,
    required this.nested,
    required this.busy,
    required this.onDelete,
  });

  final List<ClosedPaymentRow> items;
  final bool nested;
  final bool busy;
  final ValueChanged<ClosedPaymentRow> onDelete;

  @override
  Widget build(BuildContext context) {
    final table = Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            height: AppDenseList.headerH,
            color: AppTheme.tableHeaderBg,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: const Row(
              children: [
                Expanded(flex: 2, child: Text('Tarih')),
                Expanded(flex: 3, child: Text('Cari')),
                Expanded(flex: 2, child: Text('Fatura')),
                Expanded(flex: 2, child: Text('Şekil')),
                Expanded(child: Text('İşlem')),
                Expanded(
                  flex: 2,
                  child: Text('Tutar', textAlign: TextAlign.right),
                ),
                Expanded(child: Text('Durum')),
                SizedBox(width: 52),
              ],
            ),
          ),
          Expanded(
            child: ListView.separated(
              shrinkWrap: nested,
              physics: AppPhoneScrollColumn.physicsFor(nested: nested),
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final row = items[index];
                final collection = row.transactionType != 'payment';
                return Container(
                  height: 56,
                  color: AppDenseList.rowFill(index),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: Text(
                          DateFormat(
                            'd MMM y',
                            'tr_TR',
                          ).format(row.transactionDate),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: row.customerId.isEmpty
                              ? null
                              : () =>
                                    context.go('/musteriler/${row.customerId}'),
                          child: Text(
                            row.customerName ?? 'Cari',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: row.customerId.isEmpty
                                  ? null
                                  : AppTheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          row.invoiceNumberDisplay.isEmpty
                              ? '—'
                              : row.invoiceNumberDisplay,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: AppBadge(
                          label: paymentMethodLabel(
                            row.paymentMethod,
                            description: row.description,
                          ),
                          tone: row.isSanalPos
                              ? AppBadgeTone.primary
                              : AppBadgeTone.neutral,
                          dense: true,
                        ),
                      ),
                      Expanded(child: Text(_txTypeLabel(row.transactionType))),
                      Expanded(
                        flex: 2,
                        child: Text(
                          formatPosMoney(row.amount, row.currency),
                          textAlign: TextAlign.right,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(
                                color: collection
                                    ? AppTheme.success
                                    : AppTheme.error,
                              ),
                        ),
                      ),
                      Expanded(
                        child: AppBadge(
                          label: _invoiceStatusLabel(row.invoiceStatus),
                          tone: _invoiceStatusTone(row.invoiceStatus),
                          dense: true,
                        ),
                      ),
                      SizedBox(
                        width: 52,
                        child: IconButton(
                          tooltip: 'Sil',
                          onPressed: busy ? null : () => onDelete(row),
                          icon: const Icon(LucideIcons.trash2, size: 18),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
    return nested ? table : SizedBox.expand(child: table);
  }
}

String _akinsoftBridgeError(Object error) {
  final text = error.toString();
  if (RegExp(
    r'Connection refused|Failed host lookup|ClientException|SocketException|XMLHttpRequest',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'SAP API’ye ulaşılamadı ($error).';
  }
  return 'SAP’a gönderilemedi: $error';
}

Uri _akinsoftUri(String path) {
  var normalized = path.startsWith('/') ? path.substring(1) : path;
  if (normalized.startsWith('finance/')) {
    normalized = 'finance-${normalized.substring('finance/'.length)}';
  }
  final base = Uri.base;
  final isLocalWeb =
      base.host == '127.0.0.1' ||
      base.host == 'localhost' ||
      base.host == '::1';
  final separateBridge = isLocalWeb && (base.port == 3000 || base.port == 8080);
  final uri = separateBridge
      ? Uri.parse('http://127.0.0.1:4000/api/akinsoft/')
      : base.resolve('/api/akinsoft/');
  return uri.resolve(normalized);
}

Future<Map<String, dynamic>> _postAkinsoftFinance(
  String path, [
  Map<String, dynamic>? body,
]) async {
  final response = await http
      .post(
        _akinsoftUri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body ?? const <String, dynamic>{}),
      )
      .timeout(const Duration(seconds: 120));
  final parsed = jsonDecode(response.body);
  if (parsed is! Map) {
    throw Exception('Geçersiz SAP yanıtı.');
  }
  final decoded = Map<String, dynamic>.from(parsed);
  if (response.statusCode >= 400 || decoded['ok'] != true) {
    throw Exception(
      (decoded['error']?.toString().trim().isNotEmpty == true)
          ? decoded['error'].toString()
          : 'SAP işlem hatası (${response.statusCode})',
    );
  }
  return decoded;
}
