import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/app_date_time.dart';
import '../../core/format/currency_format.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phosphor_icons.dart';
import '../../core/ui/empty_state_card.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

String posCurrencyCode(String? currency) {
  final code = (currency ?? 'TRY').trim().toUpperCase();
  return switch (code) {
    '840' || 'USD' => 'USD',
    '978' || 'EUR' => 'EUR',
    '826' || 'GBP' => 'GBP',
    '949' || 'TRY' || 'TL' => 'TRY',
    _ => code.isEmpty ? 'TRY' : code,
  };
}

String posCurrencySymbol(String? currency) {
  return switch (posCurrencyCode(currency)) {
    'TRY' => '₺',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    final code => '$code ',
  };
}

String resolvePosCurrency(String? linkCurrency, String? invoiceCurrency) {
  final link = posCurrencyCode(linkCurrency);
  final invoice = posCurrencyCode(invoiceCurrency);
  if (invoice != 'TRY' &&
      (linkCurrency == null || linkCurrency.trim().isEmpty || link == 'TRY')) {
    return invoice;
  }
  return link;
}

String formatPosMoney(double amount, String? currency) {
  return NumberFormat.currency(
    locale: 'tr_TR',
    symbol: posCurrencySymbol(currency),
    decimalDigits: 2,
  ).format(amount);
}

double? parsePosAmount(String raw) => parseCurrencyValue(raw);

double normalizePosCommissionRate(double value) {
  if (value.isNaN) return 0;
  return (value.clamp(0, 30) * 100).round() / 100;
}

double commissionAmountFromRate(double gross, double rate) {
  if (gross <= 0 || rate <= 0) return 0;
  return double.parse(((gross * rate) / 100).toStringAsFixed(2));
}

double commissionRateFromAmount(double gross, double commission) {
  if (gross <= 0 || commission < 0) return 0;
  return normalizePosCommissionRate((commission / gross) * 100);
}

class PosCollectionInvoice {
  final String id;
  final String? invoiceNumber;
  final String invoiceType;
  final String? status;
  final double grandTotal;
  final double paidAmount;
  final String currency;
  final double exchangeRate;
  final String? akinsoftSourceId;

  const PosCollectionInvoice({
    required this.id,
    this.invoiceNumber,
    this.invoiceType = 'sales',
    this.status,
    this.grandTotal = 0,
    this.paidAmount = 0,
    this.currency = 'TRY',
    this.exchangeRate = 1,
    this.akinsoftSourceId,
  });

  bool get isLinkedToAkinsoft =>
      (akinsoftSourceId ?? '').trim().isNotEmpty;

  factory PosCollectionInvoice.fromJson(Map<String, dynamic> json) {
    return PosCollectionInvoice(
      id: json['id']?.toString() ?? '',
      invoiceNumber: json['invoice_number']?.toString(),
      invoiceType: json['invoice_type']?.toString() ?? 'sales',
      status: json['status']?.toString(),
      grandTotal: PosCollectionRow._toDouble(json['grand_total']),
      paidAmount: PosCollectionRow._toDouble(json['paid_amount']),
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: PosCollectionRow._toDouble(
        json['exchange_rate'],
        fallback: 1,
      ),
      akinsoftSourceId: json['akinsoft_source_id']?.toString(),
    );
  }
}

String paidTotalsByCurrency(Iterable<PosCollectionRow> items) {
  final totals = <String, double>{};
  for (final row in items) {
    if (row.listStatus != 'paid' && row.listStatus != 'settled') continue;
    final code = posCurrencyCode(row.currency);
    totals[code] = (totals[code] ?? 0) + row.amount;
  }
  if (totals.isEmpty) return formatPosMoney(0, 'TRY');
  const order = ['TRY', 'USD', 'EUR', 'GBP'];
  final parts = <String>[];
  for (final code in order) {
    if (totals.containsKey(code)) {
      parts.add(formatPosMoney(totals[code]!, code));
    }
  }
  for (final entry in totals.entries) {
    if (!order.contains(entry.key)) {
      parts.add(formatPosMoney(entry.value, entry.key));
    }
  }
  return parts.join(' · ');
}

class PosCollectionsFilter {
  final DateTime? startDate;
  final DateTime? endDate;
  final bool includeRefunded;
  final String status;

  const PosCollectionsFilter({
    this.startDate,
    this.endDate,
    this.includeRefunded = false,
    this.status = 'all',
  });

  @override
  bool operator ==(Object other) {
    return other is PosCollectionsFilter &&
        other.startDate == startDate &&
        other.endDate == endDate &&
        other.includeRefunded == includeRefunded &&
        other.status == status;
  }

  @override
  int get hashCode => Object.hash(startDate, endDate, includeRefunded, status);
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
  final String listStatus;
  final DateTime? emailedAt;
  final DateTime? remindedAt;
  final int remindedCount;
  final int? daysOverdue;
  final bool paymentOverdue;
  final DateTime? settledAt;
  final String? emailedTo;
  final String? customerEmail;
  final int valorDays;
  final DateTime? expectedSettleOn;
  final int? daysUntilValor;
  final String valorLabel;
  final List<PosCollectionInvoice> invoiceList;
  final double? settleCommission;
  final String? settleBankAccountId;
  final DateTime? sapSettledAt;

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
    this.listStatus = 'pending',
    this.emailedAt,
    this.remindedAt,
    this.remindedCount = 0,
    this.daysOverdue,
    this.paymentOverdue = false,
    this.settledAt,
    this.emailedTo,
    this.customerEmail,
    this.valorDays = 1,
    this.expectedSettleOn,
    this.daysUntilValor,
    this.valorLabel = '',
    this.invoiceList = const [],
    this.settleCommission,
    this.settleBankAccountId,
    this.sapSettledAt,
  });

  List<PosCollectionInvoice> get sapInvoices => invoiceList
      .where((invoice) => invoice.isLinkedToAkinsoft)
      .toList(growable: false);

  bool get needsSapPost => sapInvoices.isNotEmpty && sapSettledAt == null;

  bool get isFx => posCurrencyCode(currency) != 'TRY';

  double get posTlAmount {
    if (!isFx) return amount;
    if (invoiceList.isEmpty) return amount;
    return invoiceList.fold<double>(0, (sum, invoice) {
      final paid = invoice.paidAmount > 0.009
          ? invoice.paidAmount
          : invoice.grandTotal;
      final rate = invoice.exchangeRate > 1.5 ? invoice.exchangeRate : 1;
      final code = posCurrencyCode(invoice.currency);
      return sum + (code == 'TRY' ? paid : paid * rate);
    });
  }

  bool get isPaymentOverdue =>
      listStatus == 'pending' &&
      (paymentOverdue || (daysOverdue ?? 0) >= 7);

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
    final invoiceListRaw = json['invoice_list'];
    final invoiceList = <PosCollectionInvoice>[];
    if (invoiceListRaw is List) {
      for (final item in invoiceListRaw) {
        if (item is Map) {
          invoiceList.add(
            PosCollectionInvoice.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    } else if (invoices is Map) {
      invoiceList.add(
        PosCollectionInvoice.fromJson(Map<String, dynamic>.from(invoices)),
      );
    }
    return PosCollectionRow(
      id: json['id'].toString(),
      customerId: json['customer_id']?.toString() ?? '',
      customerName: customers is Map ? customers['name']?.toString() : null,
      customerEmail: customers is Map ? customers['email']?.toString() : null,
      invoiceId:
          json['invoice_id']?.toString() ??
          (invoices is Map ? invoices['id']?.toString() : null),
      invoiceNumber:
          json['invoice_number']?.toString() ??
          (invoices is Map ? invoices['invoice_number']?.toString() : null),
      invoiceStatus: invoices is Map ? invoices['status']?.toString() : null,
      amount: _toDouble(json['amount']),
      currency: resolvePosCurrency(
        json['currency']?.toString(),
        invoices is Map ? invoices['currency']?.toString() : null,
      ),
      paidOn:
          parseAppDateTime(json['paid_on']?.toString()) ??
          parseAppDateTime(json['paid_at']?.toString()) ??
          parseAppDateTime(json['created_at']?.toString()) ??
          appNow(),
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
      description: json['description']?.toString(),
      isActive:
          (json['list_status']?.toString() ?? json['status']?.toString()) !=
          'refunded',
      providerOrderId: json['provider_order_id']?.toString(),
      paymentLinkStatus:
          json['payment_link_status']?.toString() ?? json['status']?.toString(),
      listStatus: json['list_status']?.toString() ?? 'pending',
      emailedAt: parseAppDateTime(json['emailed_at']?.toString()),
      remindedAt: parseAppDateTime(json['reminded_at']?.toString()),
      remindedCount: _toInt(json['reminded_count']),
      daysOverdue: json['days_overdue'] == null
          ? null
          : _toInt(json['days_overdue']),
      paymentOverdue: json['payment_overdue'] == true,
      settledAt: parseAppDateTime(json['settled_at']?.toString()),
      emailedTo: json['emailed_to']?.toString(),
      valorDays: _toInt(json['valor_days'], fallback: 1),
      expectedSettleOn: parseAppDateTime(
        json['expected_settle_on']?.toString(),
      ),
      daysUntilValor: json['days_until_valor'] == null
          ? null
          : _toInt(json['days_until_valor']),
      valorLabel: json['valor_label']?.toString() ?? '',
      invoiceList: invoiceList,
      settleCommission: json['settle_commission'] == null
          ? null
          : _toDouble(json['settle_commission']),
      settleBankAccountId: json['settle_bank_account_id']?.toString(),
      sapSettledAt: parseAppDateTime(json['sap_settled_at']?.toString()),
    );
  }
}

class PosCollectionsResult {
  final List<PosCollectionRow> items;
  final int count;
  final int activeCount;
  final int pendingCount;
  final int paidCount;
  final int settledCount;
  final int valorDays;
  final double commissionRate;
  final double totalAmount;

  const PosCollectionsResult({
    required this.items,
    required this.count,
    required this.activeCount,
    this.pendingCount = 0,
    this.paidCount = 0,
    this.settledCount = 0,
    this.valorDays = 1,
    this.commissionRate = 0,
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
          if (filter.startDate != null)
            'startDate': filter.startDate!.toIso8601String().substring(0, 10),
          if (filter.endDate != null)
            'endDate': filter.endDate!.toIso8601String().substring(0, 10),
          'includeRefunded': filter.includeRefunded.toString(),
          'status': filter.status,
        },
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(PosCollectionRow.fromJson)
          .toList(growable: false);
      final summary = response['summary'];
      final summaryMap = summary is Map
          ? Map<String, dynamic>.from(summary)
          : null;
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
        pendingCount: PosCollectionRow._toInt(
          summaryMap?['pendingCount'],
          fallback: items.where((e) => e.listStatus == 'pending').length,
        ),
        paidCount: PosCollectionRow._toInt(
          summaryMap?['paidCount'],
          fallback: items.where((e) => e.listStatus == 'paid').length,
        ),
        settledCount: PosCollectionRow._toInt(
          summaryMap?['settledCount'],
          fallback: items.where((e) => e.listStatus == 'settled').length,
        ),
        valorDays: PosCollectionRow._toInt(
          summaryMap?['valorDays'],
          fallback: 1,
        ),
        commissionRate: PosCollectionRow._toDouble(
          summaryMap?['posCommissionRate'] ?? summaryMap?['commissionRate'],
        ),
        totalAmount: PosCollectionRow._toDouble(
          summaryMap?['totalAmount'],
          fallback: items
              .where((e) => e.listStatus == 'paid' || e.listStatus == 'settled')
              .fold<double>(0, (sum, e) => sum + e.amount),
        ),
      );
    });

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

(String, AppBadgeTone) _valorBadge(PosCollectionRow row) {
  final days = row.daysUntilValor;
  if (days == null || row.valorLabel.isEmpty) {
    return ('', AppBadgeTone.neutral);
  }
  if (days < 0) return (row.valorLabel, AppBadgeTone.error);
  if (days == 0) return (row.valorLabel, AppBadgeTone.primary);
  return (row.valorLabel, AppBadgeTone.warning);
}

(String, AppBadgeTone) _statusBadge(PosCollectionRow row) {
  return switch (row.listStatus) {
    'paid' => ('Ödendi', AppBadgeTone.success),
    'settled' => ('Hesaba yattı', AppBadgeTone.primary),
    'refunded' => ('İade edildi', AppBadgeTone.warning),
    _ => (
      'Ödeme bekleniyor',
      row.isPaymentOverdue ? AppBadgeTone.error : AppBadgeTone.warning,
    ),
  };
}

bool _matchesValorFilter(PosCollectionRow row, String valorFilter) {
  final days = row.daysUntilValor;
  return switch (valorFilter) {
    'overdue' => days != null && days < 0,
    'today' => days == 0,
    'tomorrow' => days == 1,
    'remaining' => days != null && days > 1,
    _ => true,
  };
}

int _compareValorSort(
  PosCollectionRow a,
  PosCollectionRow b,
  String valorSort,
) {
  final aOverdue = a.isPaymentOverdue;
  final bOverdue = b.isPaymentOverdue;
  if (aOverdue != bOverdue) return aOverdue ? -1 : 1;
  if (aOverdue && bOverdue) {
    final overdueCmp = (b.daysOverdue ?? 0).compareTo(a.daysOverdue ?? 0);
    if (overdueCmp != 0) return overdueCmp;
  }
  if (valorSort == 'paid_on') {
    return b.paidOn.compareTo(a.paidOn);
  }
  final aDays = a.daysUntilValor;
  final bDays = b.daysUntilValor;
  if (aDays == null && bDays == null) return b.paidOn.compareTo(a.paidOn);
  if (aDays == null) return 1;
  if (bDays == null) return -1;
  final cmp = valorSort == 'valor_late'
      ? bDays.compareTo(aDays)
      : aDays.compareTo(bDays);
  if (cmp != 0) return cmp;
  return b.paidOn.compareTo(a.paidOn);
}

class PosCollectionsTab extends ConsumerStatefulWidget {
  const PosCollectionsTab({super.key, required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<PosCollectionsTab> createState() => _PosCollectionsTabState();
}

class _PosCollectionsTabState extends ConsumerState<PosCollectionsTab> {
  DateTime? _start;
  DateTime? _end;
  bool _includeRefunded = false;
  String _status = 'all';
  String _valorFilter = 'all';
  String _valorSort = 'valor_soon';
  bool _busy = false;
  bool _savingValor = false;
  bool _savingCommission = false;
  final Set<String> _selectedIds = {};

  PosCollectionsFilter get _filter => PosCollectionsFilter(
    startDate: _start,
    endDate: _end,
    includeRefunded: _includeRefunded,
    status: _status,
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

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final today = _dateOnly(now);
    final initialStart = _start ?? DateTime(today.year, today.month, 1);
    var initialEnd = _end ?? today;
    if (initialEnd.isBefore(initialStart)) initialEnd = initialStart;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      currentDate: today,
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      locale: const Locale('tr', 'TR'),
      helpText: 'Sanal POS tarih aralığı',
      saveText: 'Uygula',
      cancelText: 'Vazgeç',
      builder: (context, child) {
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 640),
            child: child,
          ),
        );
      },
    );
    if (picked == null || !mounted) return;
    setState(() {
      _start = _dateOnly(picked.start);
      _end = _dateOnly(picked.end);
    });
  }

  void _setAllDates() {
    setState(() {
      _start = null;
      _end = null;
    });
  }

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

  Future<void> _markSettled(
    PosCollectionRow row, {
    bool settled = true,
    bool sapOnly = false,
  }) async {
    if (settled && row.listStatus != 'paid' && !sapOnly) return;
    if (!settled) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('İşareti geri al'),
          content: Text(
            row.sapSettledAt != null
                ? 'Hesaba yattı işareti kaldırılacak. SAP tahsilatı da geri alınacak.'
                : 'Hesaba yattı işareti kaldırılacak.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Geri al'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
      await _applySettle(
        row,
        settled: false,
        reverseSap: row.sapSettledAt != null,
      );
      return;
    }

    final defaultRate = ref.read(posCollectionsProvider(_filter)).value?.commissionRate ?? 0;
    final details = await showDialog<_PosSettleDetails>(
      context: context,
      builder: (context) => _PosSettleDialog(
        row: row,
        defaultRate: defaultRate,
        sapOnly: sapOnly,
      ),
    );
    if (details == null || !mounted) return;
    await _applySettle(
      row,
      settled: true,
      details: details,
    );
  }

  Future<void> _applySettle(
    PosCollectionRow row, {
    required bool settled,
    _PosSettleDetails? details,
    bool reverseSap = false,
  }) async {
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (reverseSap) {
        for (final invoice in row.sapInvoices) {
          await _postAkinsoftFinance('finance/collection', {
            'action': 'reverse',
            'invoiceSourceId': invoice.akinsoftSourceId,
            'invoiceNumber': invoice.invoiceNumber,
            'invoiceType': invoice.invoiceType,
          });
        }
      }
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      var sapPosted = false;
      Map<String, dynamic>? response;
      if (settled) {
        response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'markPosPaymentSettled',
            'linkId': row.id,
            'settled': true,
            if (details != null) 'commission': details.commission,
            if (details != null) 'bankAccountId': details.bankAccountId,
            if (details != null) 'kpbAmount': details.kpbAmount,
            'sapPosted': false,
          },
        );
      }
      if (settled && details != null && details.postToSap) {
        try {
          sapPosted = await _postSapPosCollection(row, details);
        } catch (error) {
          if (!mounted) return;
          ref.invalidate(posCollectionsProvider(_filter));
          ref.invalidate(invoicesProvider);
          ref.invalidate(accountBalancesProvider);
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Hesaba yattı işaretlendi. SAP yazılamadı: ${_akinsoftBridgeError(error)}',
              ),
            ),
          );
          return;
        }
      }
      response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'markPosPaymentSettled',
          'linkId': row.id,
          'settled': settled,
          if (details != null) 'commission': details.commission,
          if (details != null) 'bankAccountId': details.bankAccountId,
          if (details != null) 'kpbAmount': details.kpbAmount,
          'sapPosted': sapPosted,
        },
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                (settled
                    ? 'Hesaba yattı olarak işaretlendi.'
                    : 'İşaret kaldırıldı.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            settled
                ? 'Hesaba yatırılamadı: ${_settleError(error)}'
                : 'İşaret kaldırılamadı: ${_settleError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool> _postSapPosCollection(
    PosCollectionRow row,
    _PosSettleDetails details,
  ) async {
    final invoices = row.sapInvoices;
    if (invoices.isEmpty) return false;
    final totalPaid = invoices.fold<double>(0, (sum, invoice) {
      final paid = invoice.paidAmount > 0.009
          ? invoice.paidAmount
          : invoice.grandTotal;
      return sum + paid;
    });
    var remainingCommission = details.commission;
    for (var i = 0; i < invoices.length; i++) {
      final invoice = invoices[i];
      final paid = invoice.paidAmount > 0.009
          ? invoice.paidAmount
          : invoice.grandTotal;
      final share = invoices.length == 1
          ? remainingCommission
          : (i == invoices.length - 1
                ? remainingCommission
                : (totalPaid > 0
                      ? double.parse(
                          (details.commission * (paid / totalPaid))
                              .toStringAsFixed(2),
                        )
                      : 0.0));
      remainingCommission = double.parse(
        (remainingCommission - share).toStringAsFixed(2),
      );
      final rate = invoice.exchangeRate > 1.5 ? invoice.exchangeRate : 1;
      final isTry = posCurrencyCode(invoice.currency) == 'TRY';
      final kpb = isTry ? paid : paid * rate;
      await _postAkinsoftFinance('finance/collection', {
        'invoiceSourceId': invoice.akinsoftSourceId,
        'invoiceNumber': invoice.invoiceNumber,
        'amount': paid,
        'kpbAmount': kpb,
        'commissionKpb': share,
        'currency': invoice.currency,
        'exchangeRate': rate,
        'method': 'pos',
        'bankAccountId': details.bankAccountId,
        'description':
            'Sanal POS ${formatInvoiceNumberForDisplay(invoice.invoiceNumber)}'
            '${share > 0.009 ? ' · POS komisyon ${share.toStringAsFixed(2)} TL' : ''}',
        'invoiceType': invoice.invoiceType,
        'closeInvoice': true,
      });
    }
    return true;
  }

  Future<void> _dismiss(PosCollectionRow row) => _dismissMany([row]);

  Future<void> _dismissSelected(List<PosCollectionRow> items) {
    return _dismissMany(
      items.where((row) => _selectedIds.contains(row.id)).toList(),
    );
  }

  Future<void> _dismissMany(List<PosCollectionRow> rows) async {
    final pending = rows
        .where((row) => row.listStatus == 'pending')
        .toList(growable: false);
    if (pending.isEmpty) return;
    final single = pending.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Listeden çıkar'),
        content: Text(
          single
              ? '${formatInvoiceNumberForDisplay(pending.first.invoiceNumber)} · '
                    '${pending.first.customerName ?? 'Cari'}\n\n'
                    'Bu kayıt sanal POS listesinden kalkar. Fatura veya tahsilat silinmez.'
              : '${pending.length} kayıt sanal POS listesinden kalkar. '
                    'Fatura veya tahsilat silinmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              single
                  ? 'Listeden çıkar'
                  : '${pending.length} kaydı çıkar',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final ids = pending.map((row) => row.id).toList(growable: false);
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'dismissPosCollection',
          'linkId': ids.first,
          'linkIds': ids,
        },
      );
      if (!mounted) return;
      setState(() {
        _selectedIds.removeAll(ids);
      });
      ref.invalidate(posCollectionsProvider(_filter));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                (single
                    ? 'Kayıt sanal POS listesinden çıkarıldı.'
                    : '${ids.length} kayıt sanal POS listesinden çıkarıldı.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Listeden çıkarılamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remind(PosCollectionRow row) => _remindMany([row]);

  Future<void> _remindSelected(List<PosCollectionRow> items) {
    return _remindMany(
      items.where((row) => _selectedIds.contains(row.id)).toList(),
    );
  }

  Future<void> _remindMany(List<PosCollectionRow> rows) async {
    final pending = rows
        .where((row) => row.listStatus == 'pending')
        .toList(growable: false);
    if (pending.isEmpty) return;
    final missingEmail = pending
        .where((row) => (row.customerEmail ?? '').trim().isEmpty)
        .length;
    final single = pending.length == 1;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hatırlatma gönder'),
        content: Text(
          single
              ? '${formatInvoiceNumberForDisplay(pending.first.invoiceNumber)} · '
                    '${pending.first.customerName ?? 'Cari'}\n\n'
                    'Ödeme linki ve fatura özeti tekrar mail atılır.'
              : '${pending.length} kayıt için ödeme hatırlatması gönderilecek.'
                    '${missingEmail > 0 ? '\n$missingEmail kayıtta e-posta yok; onlar atlanır.' : ''}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              single ? 'Hatırlat' : '${pending.length} hatırlatma gönder',
            ),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final ids = pending.map((row) => row.id).toList(growable: false);
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'remindPosCollection',
          'linkId': ids.first,
          'linkIds': ids,
        },
      );
      if (!mounted) return;
      setState(_selectedIds.clear);
      ref.invalidate(posCollectionsProvider(_filter));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ?? 'Hatırlatma gönderildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Hatırlatma gönderilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveValorDays(int days) async {
    final next = days.clamp(0, 30);
    setState(() => _savingValor = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.postJson(
        '/e-invoice',
        body: {'action': 'save_pos_valor_days', 'days': next},
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                'Valör $next gün olarak kaydedildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Valör kaydedilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingValor = false);
    }
  }

  Future<void> _saveCommissionRate(double rate) async {
    final next = normalizePosCommissionRate(rate);
    setState(() => _savingCommission = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.postJson(
        '/e-invoice',
        body: {'action': 'save_pos_commission_rate', 'rate': next},
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                'POS komisyon oranı %${next.toStringAsFixed(2).replaceAll('.', ',')} kaydedildi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Komisyon oranı kaydedilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingCommission = false);
    }
  }

  Future<void> _editCommissionRate(double current) async {
    final controller = TextEditingController(
      text: current > 0 ? formatMoneyInput(current) : '',
    );
    final next = await showDialog<double>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Komisyon oranı'),
        content: TextField(
          controller: controller,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: moneyDecimalInputFormatters,
          decoration: const InputDecoration(
            labelText: 'Oran (%)',
            helperText: 'Nokta veya virgül aynıdır. Örn. 2,45',
          ),
          onSubmitted: (value) {
            Navigator.pop(context, parsePosAmount(value) ?? 0);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, parsePosAmount(controller.text) ?? 0),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (next == null || !mounted) return;
    await _saveCommissionRate(next);
  }

  Future<void> _refund(PosCollectionRow row, {bool crmOnly = false}) async {
    if (row.invoiceId == null || row.invoiceId!.isEmpty || !row.isActive) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(crmOnly ? 'CRM kaydını eşitle' : 'Sanal POS iade'),
        content: Text(
          crmOnly
              ? '${formatInvoiceNumberForDisplay(row.invoiceNumber)} · '
                    '${row.customerName ?? 'Cari'}\n'
                    'Banka paneli üzerinden iade yaptıysanız CRM tahsilatı geri alınır. '
                    'Karttan otomatik iade yapılmaz.'
              : '${formatInvoiceNumberForDisplay(row.invoiceNumber)} · '
                    '${row.customerName ?? 'Cari'}\n'
                    '${formatPosMoney(row.amount, row.currency)} bankaya iade edilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(crmOnly ? 'CRM’de geri al' : 'İade Et'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'refundInvoicePosPayment',
          'invoiceId': row.invoiceId,
          if (crmOnly) 'crmOnly': true,
        },
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            response['message']?.toString() ??
                (crmOnly
                    ? 'CRM tahsilatı geri alındı.'
                    : 'Sanal POS iadesi tamamlandı.'),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final text = error.toString();
      final bankDenied =
          text.toLowerCase().contains('insufficient') ||
          text.contains('iade yetkisi');
      if (!crmOnly && bankDenied) {
        messenger.showSnackBar(
          SnackBar(content: Text('İade başarısız: $error')),
        );
        await _refund(row, crmOnly: true);
        return;
      }
      messenger.showSnackBar(SnackBar(content: Text('İade başarısız: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(posCollectionsProvider(_filter));
    final valorDays = async.value?.valorDays ?? 1;
    final commissionRate = async.value?.commissionRate ?? 0;
    final dateLabel = _isAllDates
        ? 'Tüm tarihler'
        : _start == _end
        ? DateFormat('d MMM yyyy', 'tr_TR').format(_start!)
        : '${DateFormat('d MMM', 'tr_TR').format(_start!)} – ${DateFormat('d MMM yyyy', 'tr_TR').format(_end!)}';

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: AppCard(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Sanal POS ödemeleri',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Gap(4),
                Text(
                  'Ödeme linki veya mail atılan tahsilatlar. '
                  'Valör, ödemenin hesaba kaç gün sonra yatacağını belirtir. '
                  'Komisyon oranı Hesaba yattı’da otomatik gelir; tutarı veya yüzdeyi değiştirebilirsiniz.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
                const Gap(10),
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
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final entry in const [
                      ('all', 'Tümü'),
                      ('pending', 'Ödeme bekleniyor'),
                      ('paid', 'Ödendi'),
                      ('settled', 'Hesaba yattı'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _status == entry.$1,
                        onSelected: (_) {
                          setState(() => _status = entry.$1);
                        },
                      ),
                  ],
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      'Valör',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final entry in const [
                      ('all', 'Tümü'),
                      ('overdue', 'Gecikti'),
                      ('today', 'Bugün yatmalı'),
                      ('tomorrow', 'Yarın'),
                      ('remaining', 'Kalan'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _valorFilter == entry.$1,
                        onSelected: (_) {
                          setState(() {
                            _valorFilter = entry.$1;
                            if (entry.$1 != 'all' && _status == 'all') {
                              _status = 'paid';
                            }
                          });
                        },
                      ),
                    const Gap(8),
                    Text(
                      'Sıra',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    for (final entry in const [
                      ('valor_soon', 'Yakın valör'),
                      ('valor_late', 'Uzak valör'),
                      ('paid_on', 'Ödeme tarihi'),
                    ])
                      FilterChip(
                        label: Text(entry.$2),
                        selected: _valorSort == entry.$1,
                        onSelected: (_) {
                          setState(() => _valorSort = entry.$1);
                        },
                      ),
                  ],
                ),
                const Gap(10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(AppPhosphorIcons.calendarBlank, size: 16),
                      const Gap(8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Valör',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              valorDays == 0
                                  ? 'Ödeme aynı gün hesaba yatar (T+0).'
                                  : 'Ödeme $valorDays gün sonra hesaba yatar. Yeni anlaşmada buradan değiştirin.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Azalt',
                        onPressed: _savingValor || valorDays <= 0
                            ? null
                            : () => _saveValorDays(valorDays - 1),
                        icon: const Icon(Icons.remove),
                      ),
                      Text(
                        '$valorDays gün',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Artır',
                        onPressed: _savingValor || valorDays >= 30
                            ? null
                            : () => _saveValorDays(valorDays + 1),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
                const Gap(10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    children: [
                      const Icon(AppPhosphorIcons.coins, size: 16),
                      const Gap(8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Komisyon oranı',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            Text(
                              commissionRate <= 0
                                  ? 'Hesaba yattı’da komisyon otomatik gelmez. Banka oranını buraya yazın.'
                                  : 'Hesaba yattı’da %${commissionRate.toStringAsFixed(2).replaceAll('.', ',')} olarak gelir. Tutarı veya yüzdeyi orada değiştirebilirsiniz.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Azalt',
                        onPressed: _savingCommission || commissionRate <= 0
                            ? null
                            : () => _saveCommissionRate(commissionRate - 0.05),
                        icon: const Icon(Icons.remove),
                      ),
                      TextButton(
                        onPressed: _savingCommission
                            ? null
                            : () => _editCommissionRate(commissionRate),
                        child: Text(
                          '%${commissionRate.toStringAsFixed(2).replaceAll('.', ',')}',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Artır',
                        onPressed: _savingCommission || commissionRate >= 30
                            ? null
                            : () => _saveCommissionRate(commissionRate + 0.05),
                        icon: const Icon(Icons.add),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 10)),
        ...async.when(
          loading: () => const [
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
          error: (error, _) => [
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyStateCard(
                icon: AppPhosphorIcons.warningCircle,
                title: 'Liste alınamadı',
                message: '$error',
              ),
            ),
          ],
          data: (result) {
            final items =
                result.items
                    .where((row) => _matchesValorFilter(row, _valorFilter))
                    .toList()
                  ..sort((a, b) => _compareValorSort(a, b, _valorSort));
            final pendingIds = items
                .where((row) => row.listStatus == 'pending')
                .map((row) => row.id)
                .toSet();
            _selectedIds.removeWhere((id) => !pendingIds.contains(id));
            final selectedCount = _selectedIds.length;
            final allPendingSelected =
                pendingIds.isNotEmpty && selectedCount == pendingIds.length;
            if (items.isEmpty) {
              return [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyStateCard(
                    icon: AppPhosphorIcons.calendarBlank,
                    title: _valorFilter == 'all'
                        ? 'Sanal POS kaydı yok'
                        : 'Bu valör filtresinde kayıt yok',
                    message: _valorFilter == 'all'
                        ? 'Ödeme linki veya ödeme maili olan kayıtlar burada görünür. '
                              'Nakit kapanmış faturalar listeden düşer.'
                        : 'Başka bir valör filtresi veya tarih aralığı seçin.',
                  ),
                ),
              ];
            }
            return [
              SliverToBoxAdapter(
                child: AppCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 12,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            '${result.pendingCount} bekliyor · ${result.paidCount} ödendi · ${result.settledCount} hesaba yattı',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          Text(
                            paidTotalsByCurrency(items),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                        ],
                      ),
                      if (pendingIds.isNotEmpty) ...[
                        const Gap(8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Checkbox(
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              tristate: true,
                              value: selectedCount == 0
                                  ? false
                                  : allPendingSelected
                                  ? true
                                  : null,
                              onChanged: _busy
                                  ? null
                                  : (value) {
                                      setState(() {
                                        if (value == true) {
                                          _selectedIds
                                            ..clear()
                                            ..addAll(pendingIds);
                                        } else {
                                          _selectedIds.clear();
                                        }
                                      });
                                    },
                            ),
                            Text(
                              selectedCount == 0
                                  ? '${pendingIds.length} bekleyen kayıt'
                                  : '$selectedCount seçili',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            if (selectedCount > 0)
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => setState(_selectedIds.clear),
                                child: const Text('Temizle'),
                              ),
                            FilledButton.tonal(
                              onPressed: selectedCount == 0 || _busy
                                  ? null
                                  : () => _remindSelected(items),
                              child: Text(
                                selectedCount <= 1
                                    ? 'Hatırlatma gönder'
                                    : 'Hatırlat ($selectedCount)',
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: selectedCount == 0 || _busy
                                  ? null
                                  : () => _dismissSelected(items),
                              child: Text(
                                selectedCount <= 1
                                    ? 'Listeden çıkar'
                                    : 'Listeden çıkar ($selectedCount)',
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 8)),
              SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = items[index];
                  final invoiceLabel = formatInvoiceNumberForDisplay(
                    row.invoiceNumber,
                  );
                  final (statusLabel, statusTone) = _statusBadge(row);
                  final (valorLabel, valorTone) = _valorBadge(row);
                  final canSelect = row.listStatus == 'pending';
                  final selected = _selectedIds.contains(row.id);
                  final overdue = row.isPaymentOverdue;
                  final accent = overdue ? AppTheme.error : null;
                  return AppCard(
                    padding: const EdgeInsets.fromLTRB(6, 12, 10, 12),
                    color: selected
                        ? AppTheme.primary.withValues(alpha: 0.06)
                        : overdue
                        ? AppTheme.error.withValues(alpha: 0.07)
                        : null,
                    borderColor: selected
                        ? AppTheme.primary.withValues(alpha: 0.35)
                        : overdue
                        ? AppTheme.error.withValues(alpha: 0.55)
                        : null,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          width: 40,
                          child: canSelect
                              ? Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  value: selected,
                                  onChanged: _busy
                                      ? null
                                      : (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedIds.add(row.id);
                                            } else {
                                              _selectedIds.remove(row.id);
                                            }
                                          });
                                        },
                                )
                              : const SizedBox.shrink(),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                invoiceLabel.isEmpty ? 'Fatura' : invoiceLabel,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: accent,
                                    ),
                              ),
                              const Gap(2),
                              Text(
                                row.customerName ?? 'Cari',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: accent ?? AppTheme.textMuted,
                                      fontWeight: overdue
                                          ? FontWeight.w700
                                          : null,
                                    ),
                              ),
                              const Gap(6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  AppBadge(
                                    dense: true,
                                    label: statusLabel,
                                    tone: statusTone,
                                  ),
                                  const AppBadge(
                                    dense: true,
                                    label: 'Sanal POS',
                                    tone: AppBadgeTone.primary,
                                  ),
                                  if (posCurrencyCode(row.currency) != 'TRY')
                                    AppBadge(
                                      dense: true,
                                      label: posCurrencyCode(row.currency),
                                      tone: AppBadgeTone.neutral,
                                    ),
                                  if (row.emailedAt != null &&
                                      row.listStatus == 'pending' &&
                                      row.remindedAt == null)
                                    const AppBadge(
                                      dense: true,
                                      label: 'Link gönderildi',
                                      tone: AppBadgeTone.warning,
                                    ),
                                  if (row.remindedAt != null &&
                                      row.listStatus == 'pending')
                                    const AppBadge(
                                      dense: true,
                                      label: 'Hatırlatma gönderildi',
                                      tone: AppBadgeTone.error,
                                    ),
                                  if (overdue)
                                    AppBadge(
                                      dense: true,
                                      label: row.daysOverdue != null
                                          ? '${row.daysOverdue} gün gecikti'
                                          : 'Ödeme gecikti',
                                      tone: AppBadgeTone.error,
                                    ),
                                  if (valorLabel.isNotEmpty)
                                    _ValorBadge(
                                      label: valorLabel,
                                      tone: valorTone,
                                    ),
                                  Text(
                                    DateFormat(
                                      'd MMM yyyy HH:mm',
                                      'tr_TR',
                                    ).format((row.paidOn).toLocal()),
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: accent ?? AppTheme.textMuted,
                                          fontWeight: overdue
                                              ? FontWeight.w700
                                              : null,
                                        ),
                                  ),
                                ],
                              ),
                              if ((row.providerOrderId ?? '').isNotEmpty) ...[
                                const Gap(4),
                                Text(
                                  'Sipariş: ${row.providerOrderId}',
                                  style: Theme.of(context).textTheme.bodySmall
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
                              formatPosMoney(row.amount, row.currency),
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    color: accent,
                                  ),
                            ),
                            if (row.listStatus == 'paid') ...[
                              const Gap(4),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _markSettled(row),
                                child: const Text('Hesaba yattı'),
                              ),
                            ],
                            if (row.listStatus == 'settled') ...[
                              const Gap(4),
                              if (row.needsSapPost)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _markSettled(
                                          row,
                                          sapOnly: true,
                                        ),
                                  child: const Text('SAP’a yaz'),
                                ),
                              TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _markSettled(row, settled: false),
                                child: const Text('Geri al'),
                              ),
                            ],
                            if ((row.listStatus == 'paid' ||
                                    row.listStatus == 'settled') &&
                                (row.invoiceId ?? '').isNotEmpty)
                              TextButton(
                                onPressed: _busy ? null : () => _refund(row),
                                child: const Text('İade'),
                              ),
                            if (row.listStatus == 'pending') ...[
                              TextButton(
                                onPressed: _busy ? null : () => _remind(row),
                                child: Text(
                                  'Hatırlat',
                                  style: TextStyle(
                                    color: overdue ? AppTheme.error : null,
                                    fontWeight: overdue ? FontWeight.w800 : null,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: _busy ? null : () => _dismiss(row),
                                child: const Text('Listeden çıkar'),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ];
          },
        ),
      ],
    );
  }
}

class _ValorBadge extends StatelessWidget {
  const _ValorBadge({required this.label, required this.tone});

  final String label;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.primary => AppTheme.primary,
      _ => AppTheme.warning,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
        border: Border.all(color: color, width: 1.2),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          height: 1.15,
          color: color,
        ),
      ),
    );
  }
}

class _PosSettleDetails {
  const _PosSettleDetails({
    required this.commission,
    required this.rate,
    required this.kpbAmount,
    required this.postToSap,
    this.bankAccountId,
  });

  final double commission;
  final double rate;
  final double kpbAmount;
  final bool postToSap;
  final String? bankAccountId;
}

class _PosSettleDialog extends StatefulWidget {
  const _PosSettleDialog({
    required this.row,
    required this.defaultRate,
    this.sapOnly = false,
  });

  final PosCollectionRow row;
  final double defaultRate;
  final bool sapOnly;

  @override
  State<_PosSettleDialog> createState() => _PosSettleDialogState();
}

class _PosSettleDialogState extends State<_PosSettleDialog> {
  late final TextEditingController _gross;
  late final TextEditingController _rate;
  late final TextEditingController _commission;
  var _syncing = false;
  var _loadingBanks = true;
  var _loadError = '';
  var _accounts = <Map<String, dynamic>>[];
  String? _bankAccountId;

  double get _grossAmount => parsePosAmount(_gross.text) ?? 0;
  double get _commissionAmount => parsePosAmount(_commission.text) ?? 0;
  double get _rateAmount => parsePosAmount(_rate.text) ?? 0;
  double get _bankNet =>
      (_grossAmount - _commissionAmount).clamp(0, double.infinity);
  bool get _hasSap => widget.row.sapInvoices.isNotEmpty;

  @override
  void initState() {
    super.initState();
    final gross = widget.row.posTlAmount;
    final savedCommission = widget.row.settleCommission;
    final rate = savedCommission != null && savedCommission > 0.009
        ? commissionRateFromAmount(gross, savedCommission)
        : normalizePosCommissionRate(widget.defaultRate);
    final commission = savedCommission != null && savedCommission > 0.009
        ? savedCommission
        : commissionAmountFromRate(gross, rate);
    _gross = TextEditingController(text: formatMoneyInput(gross));
    _rate = TextEditingController(
      text: rate > 0 ? formatMoneyInput(rate) : '',
    );
    _commission = TextEditingController(
      text: commission > 0 ? formatMoneyInput(commission) : '',
    );
    _gross.addListener(_onGrossChanged);
    _rate.addListener(_onRateChanged);
    _commission.addListener(_onCommissionChanged);
    _loadBanks();
  }

  @override
  void dispose() {
    _gross.removeListener(_onGrossChanged);
    _rate.removeListener(_onRateChanged);
    _commission.removeListener(_onCommissionChanged);
    _gross.dispose();
    _rate.dispose();
    _commission.dispose();
    super.dispose();
  }

  void _onGrossChanged() {
    if (_syncing) return;
    _fillFromRate();
  }

  void _onRateChanged() {
    if (_syncing) return;
    _fillFromRate();
  }

  void _onCommissionChanged() {
    if (_syncing) return;
    final gross = _grossAmount;
    final commission = parsePosAmount(_commission.text);
    if (commission == null || gross <= 0) {
      setState(() {});
      return;
    }
    _syncing = true;
    final nextRate = commissionRateFromAmount(gross, commission);
    _rate.text = nextRate > 0 ? formatMoneyInput(nextRate) : '';
    _syncing = false;
    setState(() {});
  }

  void _fillFromRate() {
    final gross = _grossAmount;
    final rate = parsePosAmount(_rate.text) ?? 0;
    _syncing = true;
    final commission = commissionAmountFromRate(gross, rate);
    _commission.text = commission > 0
        ? formatMoneyInput(commission)
        : (rate <= 0 ? '' : '0,00');
    _syncing = false;
    setState(() {});
  }

  Future<void> _loadBanks() async {
    try {
      final data = await _postAkinsoftFinance('finance/pull', {
        'catalogOnly': true,
      });
      if (!mounted) return;
      final accounts = ((data['accounts'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .where(
            (e) =>
                e['isActive'] != false &&
                (e['sourceId']?.toString().isNotEmpty ?? false),
          )
          .toList();
      accounts.sort((a, b) {
        final rank = _bankRank(a).compareTo(_bankRank(b));
        if (rank != 0) return rank;
        return (a['label']?.toString() ?? '').compareTo(
          b['label']?.toString() ?? '',
        );
      });
      final preferred = widget.row.settleBankAccountId;
      setState(() {
        _accounts = accounts;
        _bankAccountId =
            (preferred != null &&
                accounts.any((a) => a['sourceId']?.toString() == preferred))
            ? preferred
            : (accounts.isEmpty ? null : accounts.first['sourceId']?.toString());
        _loadingBanks = false;
        _loadError = accounts.isEmpty ? 'Banka hesabı bulunamadı.' : '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingBanks = false;
        _loadError = _akinsoftBridgeError(error);
      });
    }
  }

  int _bankRank(Map<String, dynamic> account) {
    final label =
        '${account['label'] ?? ''} ${account['tanimi'] ?? ''} ${account['bankName'] ?? ''}'
            .toLowerCase();
    if (label.contains('halk')) return 0;
    return 1;
  }

  void _submit() {
    final gross = parsePosAmount(_gross.text);
    if (gross == null || gross <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('POS tutarını girin.')),
      );
      return;
    }
    final commissionText = _commission.text.trim();
    final rateText = _rate.text.trim();
    if (commissionText.isEmpty && rateText.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Komisyon tutarını veya yüzdesini girin. Yoksa 0 yazın.',
          ),
        ),
      );
      return;
    }
    final commission = parsePosAmount(commissionText) ?? 0;
    if (commission < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Komisyon negatif olamaz.')),
      );
      return;
    }
    if (commission >= gross) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Komisyon, POS tutarından küçük olmalı.'),
        ),
      );
      return;
    }
    if (_hasSap && (_bankAccountId ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _loadingBanks
                ? 'Banka hesapları yükleniyor, biraz bekleyin.'
                : (_loadError.isNotEmpty ? _loadError : 'Banka hesabı seçin.'),
          ),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      _PosSettleDetails(
        commission: double.parse(commission.toStringAsFixed(2)),
        rate: _rateAmount,
        kpbAmount: gross,
        postToSap: _hasSap,
        bankAccountId: _bankAccountId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final banks = _accounts;
    final bankValue =
        banks.any((a) => a['sourceId']?.toString() == _bankAccountId)
        ? _bankAccountId
        : null;
    return AlertDialog(
      title: Text(widget.sapOnly ? 'SAP’a yaz' : 'Hesaba yattı'),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${formatInvoiceNumberForDisplay(row.invoiceNumber)} · '
                '${row.customerName ?? 'Cari'}',
              ),
              const Gap(12),
              TextField(
                controller: _gross,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: moneyDecimalInputFormatters,
                decoration: const InputDecoration(
                  labelText: 'POS tutarı (TL)',
                  helperText: 'Bankanın müşteriden çektiği brüt tutar.',
                ),
              ),
              const Gap(10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _rate,
                      autofocus: widget.defaultRate <= 0,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyDecimalInputFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Komisyon %',
                        helperText: 'Oran yazınca tutar hesaplanır.',
                      ),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: TextField(
                      controller: _commission,
                      autofocus: widget.defaultRate > 0,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      inputFormatters: moneyDecimalInputFormatters,
                      decoration: const InputDecoration(
                        labelText: 'Komisyon tutarı (TL)',
                        helperText: 'Tutar yazınca yüzde hesaplanır.',
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              Text(
                'Bankaya ${_bankNet.toStringAsFixed(2).replaceAll('.', ',')} TL yatar'
                '${_commissionAmount > 0 ? ' · komisyon ${_commissionAmount.toStringAsFixed(2).replaceAll('.', ',')} TL' : ''}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (_hasSap) ...[
                const Gap(12),
                DropdownButtonFormField<String>(
                  key: ValueKey('settle-bank-${banks.length}-$bankValue'),
                  initialValue: bankValue,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: 'Banka hesabı (SAP)',
                    helperText: _loadingBanks
                        ? 'Hesaplar yükleniyor…'
                        : banks.isEmpty
                        ? (_loadError.isEmpty
                              ? 'Banka hesabı bulunamadı.'
                              : _loadError)
                        : 'Komisyon düşülmüş net bu hesaba yazılır; SAP faturası kapanır.',
                  ),
                  items: [
                    for (final account in banks)
                      DropdownMenuItem(
                        value: account['sourceId']?.toString(),
                        child: Text(
                          account['label']?.toString() ??
                              account['tanimi']?.toString() ??
                              'Hesap',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: banks.isEmpty
                      ? null
                      : (v) => setState(() => _bankAccountId = v),
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    'Bu fatura SAP’a bağlı değil. Yalnızca CRM’de hesaba yattı işaretlenir.',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(
            widget.sapOnly
                ? 'SAP’a yaz'
                : (_hasSap ? 'Hesaba yattı ve SAP’a yaz' : 'Hesaba yattı'),
          ),
        ),
      ],
    );
  }
}

String _settleError(Object error) {
  final text = error.toString().replaceFirst(RegExp(r'^Exception: '), '');
  if (RegExp(
    r'Connection refused|Failed host lookup|ClientException|SocketException|XMLHttpRequest',
    caseSensitive: false,
  ).hasMatch(text)) {
    return _akinsoftBridgeError(error);
  }
  return text;
}

String _akinsoftBridgeError(Object error) {
  final text = error.toString();
  if (RegExp(
    r'Connection refused|Failed host lookup|ClientException|SocketException|XMLHttpRequest',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'SAP API’ye ulaşılamadı ($error). '
        'Yerelde PORT=4000 local_server çalıştığından emin olun.';
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
