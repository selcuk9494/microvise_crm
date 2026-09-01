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
  });

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
  final double totalAmount;

  const PosCollectionsResult({
    required this.items,
    required this.count,
    required this.activeCount,
    this.pendingCount = 0,
    this.paidCount = 0,
    this.settledCount = 0,
    this.valorDays = 1,
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

  Future<void> _markSettled(PosCollectionRow row, {bool settled = true}) async {
    if (row.listStatus != 'paid' && settled) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(settled ? 'Hesaba yattı' : 'İşareti geri al'),
        content: Text(
          settled
              ? '${formatInvoiceNumberForDisplay(row.invoiceNumber)} · '
                    '${row.customerName ?? 'Cari'}\n'
                    'Banka hesabınıza geçtiyse bu tahsilatı “Hesaba yattı” olarak işaretleyin.'
              : 'Hesaba yattı işareti kaldırılacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(settled ? 'Hesaba yattı' : 'Geri al'),
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
          'op': 'markPosPaymentSettled',
          'linkId': row.id,
          'settled': settled,
        },
      );
      if (!mounted) return;
      ref.invalidate(posCollectionsProvider(_filter));
      ref.invalidate(invoicesProvider);
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
      messenger.showSnackBar(SnackBar(content: Text('İşaretlenemedi: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
                  'Valör, ödemenin hesaba kaç gün sonra yatacağını belirtir; '
                  'yeni anlaşmada buradan güncellenir.',
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
