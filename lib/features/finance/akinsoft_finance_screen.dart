import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/currency_format.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import '../e_invoice/akinsoft_bridge.dart';
import '../e_invoice/e_invoice_screen.dart' show eInvoiceSettingsProvider;

Uri _akinsoftFinanceUri(String path) {
  var normalizedPath = path.startsWith('/') ? path.substring(1) : path;
  // Vercel catch-all only matches a single segment after /api/akinsoft/.
  // Nested /finance/pull returns HTML 404; hyphenated finance-pull works.
  if (normalizedPath.startsWith('finance/')) {
    normalizedPath = 'finance-${normalizedPath.substring('finance/'.length)}';
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
  return uri.resolve(normalizedPath);
}

String _money(num value) {
  final fmt = NumberFormat('#,##0.00', 'tr_TR');
  return fmt.format(value);
}

String _date(dynamic value) {
  if (value == null) return '—';
  final dt = DateTime.tryParse(value.toString());
  if (dt == null) return value.toString();
  return DateFormat('dd.MM.yyyy').format(dt.toLocal());
}

String _text(dynamic value) => value?.toString().trim() ?? '';

class AkinsoftFinanceScreen extends ConsumerStatefulWidget {
  const AkinsoftFinanceScreen({super.key, this.section = 'bankalar'});

  final String section;

  @override
  ConsumerState<AkinsoftFinanceScreen> createState() =>
      _AkinsoftFinanceScreenState();
}

class _AkinsoftFinanceScreenState extends ConsumerState<AkinsoftFinanceScreen> {
  bool _loading = false;
  String? _error;
  String? _status;
  DateTime? _pulledAt;

  List<Map<String, dynamic>> _banks = const [];
  List<Map<String, dynamic>> _accounts = const [];
  List<Map<String, dynamic>> _kasas = const [];
  List<Map<String, dynamic>> _transfers = const [];
  List<Map<String, dynamic>> _masraf = const [];
  List<Map<String, dynamic>> _movements = const [];
  List<Map<String, dynamic>> _crmBanks = const [];
  List<Map<String, dynamic>> _crmAccounts = const [];
  List<Map<String, dynamic>> _crmTransactions = const [];
  String? _selectedAccountKey;
  String? _pendingMovementId;
  String? _handledHareket;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocal());
  }

  @override
  void didUpdateWidget(covariant AkinsoftFinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadLocal());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final q = GoRouterState.of(context).uri.queryParameters;
    final hesap = q['hesap']?.trim();
    final hareket = q['hareket']?.trim();
    if (hesap != null && hesap.isNotEmpty && hesap != _selectedAccountKey) {
      _selectedAccountKey = hesap;
    }
    if (hareket != null &&
        hareket.isNotEmpty &&
        hareket != _handledHareket) {
      _handledHareket = hareket;
      _pendingMovementId = hareket;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMovementById(hareket);
      });
    }
  }

  Future<Map<String, dynamic>> _post(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final response = await http
        .post(
          _akinsoftFinanceUri(path),
          headers: const {'Content-Type': 'application/json'},
          body: jsonEncode(body ?? const <String, dynamic>{}),
        )
        .timeout(const Duration(seconds: 120));
    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(response.body);
      if (parsed is! Map<String, dynamic>) {
        throw Exception('Geçersiz SAP yanıtı.');
      }
      decoded = parsed;
    } on FormatException {
      final preview = response.body.trim();
      if (response.statusCode == 404 ||
          preview.startsWith('The page') ||
          preview.contains('NOT_FOUND')) {
        throw Exception(
          'SAP finans API bulunamadı (${response.statusCode}). '
          'Sunucu henüz finance uçlarını yayınlamıyor.',
        );
      }
      final snippet = preview.length > 80 ? '${preview.substring(0, 80)}…' : preview;
      throw Exception('SAP yanıtı JSON değil: $snippet');
    }
    if (response.statusCode >= 400 || decoded['ok'] != true) {
      throw Exception(
        _text(decoded['error']).isEmpty
            ? 'SAP işlem hatası (${response.statusCode})'
            : _text(decoded['error']),
      );
    }
    return decoded;
  }

  Future<List<Map<String, dynamic>>> _crmItems(String resource) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return const [];
    final response = await api.getJson(
      '/data',
      queryParameters: {'resource': resource, 'includePassive': 'true'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<void> _loadCrmFinance() async {
    try {
      final banks = await _crmItems('finance_banks');
      final accounts = await _crmItems('finance_accounts');
      final txs = await _crmItems('finance_transactions');
      if (!mounted) return;
      setState(() {
        _crmBanks = banks;
        _crmAccounts = accounts;
        _crmTransactions = txs;
      });
    } catch (_) {}
  }

  String _accountKey(Map<String, dynamic> row) {
    final sap = _text(row['sourceId']);
    if (sap.isNotEmpty) return sap;
    return _text(row['id']);
  }

  Map<String, dynamic>? _selectedAccount() {
    final key = _selectedAccountKey;
    if (key == null || key.isEmpty) return null;
    for (final a in _visibleAccounts()) {
      if (_accountKey(a) == key) return a;
    }
    for (final a in _crmAccounts) {
      if (_text(a['id']) == key || _text(a['akinsoft_source_id']) == key) {
        return {
          ...a,
          'sourceId': _text(a['akinsoft_source_id']).isEmpty
              ? _text(a['id'])
              : _text(a['akinsoft_source_id']),
          'label': _text(a['name']),
          'balance': a['current_balance'] ?? 0,
          'origin': 'crm',
        };
      }
    }
    if (kAkinsoftBridgeEnabled) {
      for (final a in _accounts) {
        if (_accountKey(a) == key) return a;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> _movementsForSelected() {
    final key = _selectedAccountKey;
    if (key == null || key.isEmpty) return const [];
    final sap = kAkinsoftBridgeEnabled
        ? _movements.where((m) => _text(m['accountSourceId']) == key).toList()
        : const <Map<String, dynamic>>[];
    final crm = _crmTransactions.where((t) {
      final accountId = _text(t['account_id']);
      final sapId = _text(t['akinsoft_source_id']);
      if (sapId == key) return true;
      for (final a in _crmAccounts) {
        if (_text(a['id']) == accountId &&
            (_text(a['id']) == key || _text(a['akinsoft_source_id']) == key)) {
          return true;
        }
      }
      return accountId == key;
    }).map((t) {
      final amount = (t['amount'] is num)
          ? (t['amount'] as num).toDouble()
          : double.tryParse('${t['amount']}') ?? 0;
      final direction = _text(t['direction']).isEmpty ? 'in' : _text(t['direction']);
      return {
        ...t,
        'sourceId': _text(t['id']),
        'accountSourceId': key,
        'date': t['transaction_date'],
        'description': t['description'],
        'evrakNo': t['reference_no'],
        'amount': direction == 'out' ? -amount.abs() : amount.abs(),
        'direction': direction,
        'origin': 'crm',
        'currency': t['currency'],
      };
    });
    final all = [...sap, ...crm];
    all.sort((a, b) {
      final da = DateTime.tryParse(_text(a['date'])) ?? DateTime(1970);
      final db = DateTime.tryParse(_text(b['date'])) ?? DateTime(1970);
      return db.compareTo(da);
    });
    return all;
  }

  Future<String?> _ensureCrmAccount(Map<String, dynamic> sapOrCrm) async {
    final existingId = _text(sapOrCrm['id']);
    // Yalnızca ERP çekiminden gelen `balance` açılış bakiyesidir;
    // CRM `current_balance` hareketleri de içerir, açılışa yazılmaz.
    final knownBalance = _num(sapOrCrm['balance']);
    if (existingId.contains('-') && existingId.length > 20) {
      await _seedOpeningBalance(existingId, knownBalance);
      return existingId;
    }
    final sapId = _text(sapOrCrm['sourceId']);
    for (final a in _crmAccounts) {
      if (sapId.isNotEmpty && _text(a['akinsoft_source_id']) == sapId) {
        final id = _text(a['id']);
        await _seedOpeningBalance(id, knownBalance);
        return id;
      }
    }
    final api = ref.read(apiClientProvider);
    if (api == null) return null;
    final result = await api.postJson(
      '/mutate',
      body: {
        'op': 'upsert',
        'table': 'finance_accounts',
        'values': {
          'name': _text(sapOrCrm['label']).isEmpty
              ? (_text(sapOrCrm['tanimi']).isEmpty
                    ? _text(sapOrCrm['name'])
                    : _text(sapOrCrm['tanimi']))
              : _text(sapOrCrm['label']),
          'account_type': _text(sapOrCrm['account_type']).isEmpty
              ? 'bank'
              : _text(sapOrCrm['account_type']),
          'bank_name': _text(sapOrCrm['bankName']),
          'account_no': _text(sapOrCrm['hesapNo']),
          'iban': _text(sapOrCrm['iban']),
          'currency': _text(sapOrCrm['currency']).isEmpty
              ? 'TRY'
              : _text(sapOrCrm['currency']),
          'opening_balance': knownBalance,
          'akinsoft_source_id': sapId.isEmpty ? null : sapId,
          'akinsoft_bank_source_id': _text(sapOrCrm['bankSourceId']),
          'is_active': sapOrCrm['isActive'] != false,
        },
      },
    );
    await _loadCrmFinance();
    return _text(result['id']);
  }

  Future<void> _seedOpeningBalance(String accountId, double balance) async {
    if (accountId.isEmpty || balance.abs() < 0.009) return;
    Map<String, dynamic>? crm;
    for (final a in _crmAccounts) {
      if (_text(a['id']) == accountId) {
        crm = a;
        break;
      }
    }
    if (crm != null && _num(crm['opening_balance']).abs() > 0.009) return;
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    var txSum = 0.0;
    for (final t in _crmTransactions) {
      if (_text(t['account_id']) != accountId) continue;
      if (t['is_active'] == false) continue;
      final amount = _num(t['amount']).abs();
      txSum += _text(t['direction']) == 'out' ? -amount : amount;
    }
    await api.postJson(
      '/mutate',
      body: {
        'op': 'upsert',
        'table': 'finance_accounts',
        'values': {
          'id': accountId,
          'opening_balance': balance,
          'current_balance': balance + txSum,
        },
      },
    );
    await _loadCrmFinance();
  }

  void _openMovementById(String id) {
    for (final m in _movementsForSelected()) {
      if (_text(m['sourceId']) == id || _text(m['id']) == id) {
        _showMovementDialog(existing: m);
        return;
      }
    }
    for (final t in _crmTransactions) {
      if (_text(t['id']) == id) {
        _showMovementDialog(existing: t);
        return;
      }
    }
  }

  double _num(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse('$value'.replaceAll(',', '.')) ?? 0;
  }

  /// Son bilinen ERP bakiyesini CRM opening_balance olarak saklar;
  /// böylece CRM hareketleri bakiyeye eklenir.
  Future<void> _migrateSapBalancesIntoCrm() async {
    if (_accounts.isEmpty) return;
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    for (final sap in _accounts) {
      final sapId = _text(sap['sourceId']);
      if (sapId.isEmpty) continue;
      final sapBalance = _num(sap['balance']);
      Map<String, dynamic>? crm;
      for (final a in _crmAccounts) {
        if (_text(a['akinsoft_source_id']) == sapId) {
          crm = a;
          break;
        }
      }
      if (crm == null) {
        await _ensureCrmAccount(sap);
        continue;
      }
      final opening = _num(crm['opening_balance']);
      if (opening.abs() > 0.009) continue;
      if (sapBalance.abs() < 0.009) continue;
      var txSum = 0.0;
      final crmId = _text(crm['id']);
      for (final t in _crmTransactions) {
        if (_text(t['account_id']) != crmId) continue;
        if (t['is_active'] == false) continue;
        final amount = _num(t['amount']).abs();
        txSum += _text(t['direction']) == 'out' ? -amount : amount;
      }
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_accounts',
          'values': {
            'id': crm['id'],
            'opening_balance': sapBalance,
            'current_balance': sapBalance + txSum,
          },
        },
      );
    }
    await _loadCrmFinance();
  }

  void _clearSapCaches() {
    _banks = const [];
    _accounts = const [];
    _kasas = const [];
    _transfers = const [];
    _masraf = const [];
    _movements = const [];
    _pulledAt = null;
  }

  Future<void> _finishCrmView({String? status, String? error}) async {
    if (!mounted) return;
    final q = GoRouterState.of(context).uri.queryParameters;
    setState(() {
      _clearSapCaches();
      _selectedAccountKey = q['hesap']?.trim().isNotEmpty == true
          ? q['hesap']!.trim()
          : _selectedAccountKey;
      _pendingMovementId = q['hareket']?.trim();
      _status = status ??
          '${_visibleBanks().length} banka, ${_visibleAccounts().length} hesap · bakiyeler CRM’de';
      _error = error;
      _loading = false;
    });
    final pending = _pendingMovementId;
    if (pending != null && pending.isNotEmpty) {
      _pendingMovementId = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMovementById(pending);
      });
    }
  }

  Future<void> _loadLocal() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'CRM finans kayıtları yükleniyor…';
    });
    await _loadCrmFinance();
    if (!mounted) return;
    if (_accounts.isNotEmpty) {
      await _migrateSapBalancesIntoCrm();
      if (!mounted) return;
    }
    // Yazım kapalı ama çekim açıksa ERP’den CRM’ye bir kez aktar.
    if (!kAkinsoftBridgeEnabled && kAkinsoftBridgePullEnabled) {
      await _importFromErp(showErrors: false);
      return;
    }
    // Önceki aktarımdan kalan çift hesapları temizle.
    await _dedupeCrmAccounts();
    if (!mounted) return;
    await _finishCrmView();
  }

  Future<void> _pull() async {
    if (!kAkinsoftBridgeEnabled && kAkinsoftBridgePullEnabled) {
      await _importFromErp(showErrors: true);
      return;
    }
    if (!kAkinsoftBridgeEnabled) {
      await _loadLocal();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _status = 'ERP finans verileri çekiliyor…';
    });
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final data = await _post('finance/pull', {
        ...settings,
        'movementLimit': 500,
        'transferLimit': 200,
        'masrafLimit': 120,
      });
      await _loadCrmFinance();
      if (!mounted) return;
      final q = GoRouterState.of(context).uri.queryParameters;
      setState(() {
        _banks = ((data['banks'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _accounts = ((data['accounts'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _kasas = ((data['kasas'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _transfers = ((data['transfers'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _masraf = ((data['masraf'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _movements = ((data['movements'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _pulledAt = DateTime.tryParse(_text(data['pulledAt']));
        _selectedAccountKey =
            q['hesap']?.trim().isNotEmpty == true ? q['hesap']!.trim() : _selectedAccountKey;
        _pendingMovementId = q['hareket']?.trim();
        _status =
            'ERP çekildi. ${_banks.length} banka, ${_accounts.length} hesap';
        _loading = false;
      });
      final pending = _pendingMovementId;
      if (pending != null && pending.isNotEmpty) {
        _pendingMovementId = null;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _openMovementById(pending);
        });
      }
    } catch (error) {
      await _loadCrmFinance();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _status = 'ERP çekilemedi; CRM kayıtları gösteriliyor.';
      });
    }
  }

  Future<void> _importFromErp({required bool showErrors}) async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'ERP’den CRM’ye aktarılıyor…';
    });
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final data = await _post('finance/pull', {
        ...settings,
        'movementLimit': 500,
        'transferLimit': 200,
        'masrafLimit': 120,
      });
      await _importErpSnapshotIntoCrm(data);
      await _dedupeCrmAccounts();
      await _loadCrmFinance();
      if (!mounted) return;
      await _finishCrmView(
        status:
            'ERP aktarıldı → CRM: ${_visibleBanks().length} banka, ${_visibleAccounts().length} hesap, ${_crmTransactions.length} hareket',
      );
    } catch (error) {
      await _loadCrmFinance();
      if (!mounted) return;
      await _finishCrmView(
        status:
            'CRM kayıtları gösteriliyor (${_visibleBanks().length} banka, ${_visibleAccounts().length} hesap)',
        error: showErrors ? error.toString() : null,
      );
    }
  }

  Future<void> _importErpSnapshotIntoCrm(Map<String, dynamic> data) async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;

    final banks = ((data['banks'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final accounts = ((data['accounts'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final kasas = ((data['kasas'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final movements = ((data['movements'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final transfers = ((data['transfers'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final masraf = ((data['masraf'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();

    for (final b in banks) {
      final sourceId = _text(b['sourceId']);
      if (sourceId.isEmpty) continue;
      String? crmId;
      for (final existing in _crmBanks) {
        if (_text(existing['akinsoft_source_id']) == sourceId) {
          crmId = _text(existing['id']);
          break;
        }
      }
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_banks',
          'values': {
            if (crmId != null && crmId.isNotEmpty) 'id': crmId,
            'name': _text(b['bankName']).isEmpty ? 'Banka' : _text(b['bankName']),
            'branch': _text(b['branch']),
            'phone': _text(b['phone']),
            'address': _text(b['address']),
            'akinsoft_source_id': sourceId,
            'is_active': true,
          },
        },
      );
    }
    await _loadCrmFinance();

    final accountIdBySap = <String, String>{};
    for (final a in accounts) {
      final sourceId = _text(a['sourceId']);
      if (sourceId.isEmpty) continue;
      final related = movements.where((m) => _text(m['accountSourceId']) == sourceId);
      var net = 0.0;
      for (final m in related) {
        net += _num(m['amount']);
      }
      final sapBalance = _num(a['balance']);
      // Açılış = ERP bakiyesi − bu çekimde gelen hareketler (çift sayım olmasın).
      final opening = sapBalance - net;
      final match = _matchCrmAccount(a);
      final crmId = match == null ? null : _text(match['id']);
      final values = <String, dynamic>{
        if (crmId != null && crmId.isNotEmpty) 'id': crmId,
        'name': _text(a['label']).isEmpty
            ? (_text(a['tanimi']).isEmpty ? 'Hesap' : _text(a['tanimi']))
            : _text(a['label']),
        'account_type': 'bank',
        'bank_name': _text(a['bankName']),
        'account_no': _text(a['hesapNo']),
        'iban': _text(a['iban']),
        'currency': _normalizeCurrency(_text(a['currency'])),
        'opening_balance': opening,
        'current_balance': sapBalance,
        'akinsoft_source_id': sourceId,
        'akinsoft_bank_source_id': _text(a['bankSourceId']),
        'is_active': a['isActive'] != false,
      };
      final result = await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_accounts',
          'values': values,
        },
      );
      final id = _text(result['id']).isEmpty ? crmId : _text(result['id']);
      if (id != null && id.isNotEmpty) accountIdBySap[sourceId] = id;
    }

    for (final k in kasas) {
      final sourceId = _text(k['sourceId']);
      final name = _text(k['kasaAdi']);
      if (name.isEmpty) continue;
      String? crmId;
      for (final existing in _crmAccounts) {
        if (_text(existing['akinsoft_source_id']) == sourceId ||
            (_text(existing['account_type']) == 'cash' &&
                _text(existing['name']) == name)) {
          crmId = _text(existing['id']);
          break;
        }
      }
      final result = await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_accounts',
          'values': {
            if (crmId != null && crmId.isNotEmpty) 'id': crmId,
            'name': name,
            'account_type': 'cash',
            'currency': 'TRY',
            'notes': _text(k['aciklama1']),
            'opening_balance': _num(k['balance']),
            'akinsoft_source_id': sourceId.isEmpty ? null : sourceId,
            'is_active': k['isActive'] != false,
          },
        },
      );
      final id = _text(result['id']).isEmpty ? crmId : _text(result['id']);
      if (id != null && id.isNotEmpty && sourceId.isNotEmpty) {
        accountIdBySap[sourceId] = id;
      }
    }
    await _loadCrmFinance();
    for (final a in _crmAccounts) {
      final sap = _text(a['akinsoft_source_id']);
      if (sap.isNotEmpty) accountIdBySap[sap] = _text(a['id']);
    }

    final existingSapTx = <String>{
      for (final t in _crmTransactions)
        if (_text(t['akinsoft_source_id']).isNotEmpty) _text(t['akinsoft_source_id']),
    };

    Future<void> writeMovement(Map<String, dynamic> m, {String type = 'manual'}) async {
      final sapTxId = _text(m['sourceId']);
      if (sapTxId.isEmpty || existingSapTx.contains(sapTxId)) return;
      final accountSap = _text(m['accountSourceId']);
      var accountId = accountIdBySap[accountSap];
      if (accountId == null || accountId.isEmpty) {
        for (final a in accounts) {
          if (_text(a['sourceId']) == accountSap) {
            accountId = await _ensureCrmAccount(a);
            break;
          }
        }
      }
      if (accountId == null || accountId.isEmpty) return;
      final amount = _num(m['amount']).abs();
      if (amount < 0.009) return;
      final direction = _text(m['direction']).isEmpty
          ? (_num(m['amount']) < 0 ? 'out' : 'in')
          : _text(m['direction']);
      final date = DateTime.tryParse(_text(m['date'])) ?? DateTime.now();
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_transactions',
          'values': {
            'account_id': accountId,
            'transaction_date': DateFormat('yyyy-MM-dd').format(date),
            'direction': direction == 'out' ? 'out' : 'in',
            'transaction_type': type,
            'payment_method': 'bank',
            'amount': amount,
            'currency': _text(m['currency']).isEmpty ? 'TRY' : _text(m['currency']),
            'description': _text(m['description']),
            'reference_no': _text(m['evrakNo']),
            'source': 'erp_import',
            'akinsoft_source_id': sapTxId,
            'is_active': true,
          },
        },
      );
      existingSapTx.add(sapTxId);
    }

    for (final m in movements) {
      await writeMovement(m, type: 'manual');
    }
    for (final t in transfers) {
      // Transfer satırları hareketlerde de olabilir; yoksa özet kayıt.
      final sapTxId = _text(t['sourceId']);
      if (sapTxId.isEmpty || existingSapTx.contains(sapTxId)) continue;
      final fromId = accountIdBySap[_text(t['fromAccountId'])];
      final toId = accountIdBySap[_text(t['toAccountId'])];
      final amount = _num(t['amount']).abs();
      if (amount < 0.009) continue;
      final date = DateTime.tryParse(_text(t['date'] ?? t['tarihi'])) ?? DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd').format(date);
      final desc = _text(t['description'] ?? t['aciklama']);
      if (fromId != null && fromId.isNotEmpty) {
        await api.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'finance_transactions',
            'values': {
              'account_id': fromId,
              'transaction_date': dateStr,
              'direction': 'out',
              'transaction_type': 'transfer',
              'payment_method': 'bank',
              'amount': amount,
              'currency': _text(t['currency']).isEmpty ? 'TRY' : _text(t['currency']),
              'description': desc.isEmpty ? 'Transfer' : desc,
              'reference_no': _text(t['evrakNo']),
              'source': 'erp_import',
              'akinsoft_source_id': sapTxId,
              'is_active': true,
            },
          },
        );
        existingSapTx.add(sapTxId);
      }
      final pairId = _text(t['pairSourceId']);
      if (toId != null && toId.isNotEmpty && pairId.isNotEmpty && !existingSapTx.contains(pairId)) {
        await api.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'finance_transactions',
            'values': {
              'account_id': toId,
              'transaction_date': dateStr,
              'direction': 'in',
              'transaction_type': 'transfer',
              'payment_method': 'bank',
              'amount': amount,
              'currency': _text(t['currency']).isEmpty ? 'TRY' : _text(t['currency']),
              'description': desc.isEmpty ? 'Transfer' : desc,
              'reference_no': _text(t['evrakNo']),
              'source': 'erp_import',
              'akinsoft_source_id': pairId,
              'is_active': true,
            },
          },
        );
        existingSapTx.add(pairId);
      }
    }
    for (final m in masraf) {
      final sapTxId = 'masraf-${_text(m['sourceId'])}';
      if (_text(m['sourceId']).isEmpty || existingSapTx.contains(sapTxId)) continue;
      final payAccount = _text(m['bankAccountId'] ?? m['accountSourceId']);
      var accountId = accountIdBySap[payAccount];
      if (accountId == null || accountId.isEmpty) {
        // kasa adı ile eşle
        final kasaAdi = _text(m['kasaAdi'] ?? m['payLabel']);
        for (final a in _crmAccounts) {
          if (_text(a['account_type']) == 'cash' && _text(a['name']) == kasaAdi) {
            accountId = _text(a['id']);
            break;
          }
        }
      }
      if (accountId == null || accountId.isEmpty) continue;
      final amount = _num(m['total'] ?? m['amount']).abs();
      if (amount < 0.009) continue;
      final date = DateTime.tryParse(_text(m['date'] ?? m['tarihi'])) ?? DateTime.now();
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_transactions',
          'values': {
            'account_id': accountId,
            'transaction_date': DateFormat('yyyy-MM-dd').format(date),
            'direction': 'out',
            'transaction_type': 'masraf',
            'payment_method': _text(m['payMethod']).isEmpty ? 'cash' : _text(m['payMethod']),
            'amount': amount,
            'currency': 'TRY',
            'description': _text(m['description'] ?? m['cariUnvan']).isEmpty
                ? 'Masraf ${_text(m['faturaNo'])}'
                : _text(m['description'] ?? m['cariUnvan']),
            'reference_no': _text(m['faturaNo'] ?? m['evrakNo']),
            'source': 'erp_import',
            'akinsoft_source_id': sapTxId,
            'is_active': true,
          },
        },
      );
      existingSapTx.add(sapTxId);
    }
  }

  Future<void> _mutate(
    String path,
    Map<String, dynamic> body, {
    required String successMessage,
  }) async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'CRM’ye kaydediliyor…';
    });
    try {
      await _saveCrmFinance(path, body);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(successMessage)),
      );
      await _loadCrmFinance();
      if (mounted) {
        setState(() {
          _loading = false;
          _status = kAkinsoftBridgeEnabled
              ? 'Kayıt CRM işlem günlüğünde.'
              : '${_crmBanks.length} banka, ${_crmAccounts.length} hesap · bakiyeler CRM hareketleriyle güncellenir';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _status = null;
      });
    }
  }

  Future<void> _saveCrmFinance(String path, Map<String, dynamic> body) async {
    final api = ref.read(apiClientProvider);
    if (api == null) throw Exception('API yok.');
    final action = _text(body['action']).toLowerCase();
    if (path == 'finance/bank') {
      if (action == 'delete') {
        final id = _crmBankId(body);
        if (id == null) {
          throw Exception('Banka silinemedi. CRM kaydı bulunamadı.');
        }
        await api.postJson(
          '/mutate',
          body: {'op': 'delete', 'table': 'finance_banks', 'id': id},
        );
        return;
      }
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_banks',
          'values': {
            if (_crmBankId(body) != null) 'id': _crmBankId(body),
            'name': _text(body['bankName']),
            'branch': _text(body['branch']),
            'phone': _text(body['phone']),
            'address': _text(body['address']),
            'akinsoft_source_id': _text(body['sourceId']).isEmpty
                ? null
                : _text(body['sourceId']),
            'is_active': true,
          },
        },
      );
      return;
    }
    if (path == 'finance/bank-account') {
      if (action == 'delete') {
        final id = await _ensureCrmAccount({
          'sourceId': body['sourceId'],
          ...?_accountById(_text(body['sourceId'])),
        });
        if (id == null) throw Exception('Hesap bulunamadı.');
        await api.postJson(
          '/mutate',
          body: {'op': 'delete', 'table': 'finance_accounts', 'id': id},
        );
        return;
      }
      Map<String, dynamic>? bank;
      for (final b in _visibleBanks()) {
        if (_text(b['sourceId']) == _text(body['bankSourceId']) ||
            _text(b['id']) == _text(body['bankSourceId'])) {
          bank = b;
          break;
        }
      }
      final opening = body.containsKey('opening_balance')
          ? _num(body['opening_balance'])
          : null;
      var txSum = 0.0;
      final crmId = _text(body['crmId']);
      if (opening != null && crmId.isNotEmpty) {
        for (final t in _crmTransactions) {
          if (_text(t['account_id']) != crmId) continue;
          if (t['is_active'] == false) continue;
          final amount = _num(t['amount']).abs();
          txSum += _text(t['direction']) == 'out' ? -amount : amount;
        }
      }
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_accounts',
          'values': {
            if (crmId.isNotEmpty) 'id': crmId,
            'name': _text(body['tanimi']).isEmpty
                ? _text(body['hesapNo'])
                : _text(body['tanimi']),
            'account_type': 'bank',
            'bank_name': _text(bank?['bankName'] ?? bank?['name']),
            'account_no': _text(body['hesapNo']),
            'iban': _text(body['iban']),
            'currency': _text(body['currency']).isEmpty
                ? 'TRY'
                : _text(body['currency']),
            if (opening != null) 'opening_balance': opening,
            if (opening != null) 'current_balance': opening + txSum,
            'akinsoft_source_id': _text(body['sourceId']).isEmpty
                ? null
                : _text(body['sourceId']),
            'akinsoft_bank_source_id': _text(body['bankSourceId']),
            'is_active': true,
          },
        },
      );
      return;
    }
    if (path == 'finance/kasa') {
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_accounts',
          'values': {
            'name': _text(body['kasaAdi']),
            'account_type': 'cash',
            'notes': _text(body['aciklama1']),
            'currency': 'TRY',
            'akinsoft_source_id': _text(body['sourceId']).isEmpty
                ? null
                : _text(body['sourceId']),
            'is_active': action != 'delete',
          },
        },
      );
      return;
    }
    if (path == 'finance/transfer') {
      await _saveCrmTransfer(body);
      return;
    }
    if (path == 'finance/masraf') {
      throw Exception(
        'Masraf kaydı için Bankalar ekranından hesap hareketi ekleyin.',
      );
    }
    throw Exception('Desteklenmeyen işlem: $path');
  }

  Future<void> _saveCrmTransfer(Map<String, dynamic> body) async {
    final api = ref.read(apiClientProvider);
    if (api == null) throw Exception('API yok.');
    final action = _text(body['action']).toLowerCase();
    if (action == 'delete') {
      throw Exception(
        'Eski ERP transferleri silinemez. CRM hareketlerini Bankalar ekranından düzeltin.',
      );
    }
    final amount = _num(body['amount']);
    final fee = _num(body['masraf']);
    if (amount <= 0) throw Exception('Tutar girin.');
    final type = _text(body['type']).toLowerCase();
    final date = DateTime.tryParse(_text(body['date'])) ?? DateTime.now();
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    final desc = _text(body['description']);
    final currency = _text(body['currency']).isEmpty
        ? 'TRY'
        : _text(body['currency']);

    Future<String> resolveAccount(String? raw) async {
      final key = _text(raw);
      if (key.isEmpty) throw Exception('Hesap seçin.');
      Map<String, dynamic>? row = _accountById(key);
      if (row == null) {
        for (final a in _visibleAccounts()) {
          if (_accountKey(a) == key) {
            row = a;
            break;
          }
        }
      }
      if (row == null) throw Exception('Hesap bulunamadı.');
      final id = await _ensureCrmAccount(row);
      if (id == null || id.isEmpty) throw Exception('Hesap CRM’ye alınamadı.');
      return id;
    }

    Future<void> writeTx({
      required String accountId,
      required String direction,
      required double value,
      required String description,
      String? reference,
    }) async {
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_transactions',
          'values': {
            'account_id': accountId,
            'transaction_date': dateStr,
            'direction': direction,
            'transaction_type': 'transfer',
            'payment_method': 'bank',
            'amount': value,
            'currency': currency,
            'description': description,
            'reference_no': reference,
            'source': 'crm',
            'is_active': true,
          },
        },
      );
    }

    if (type == 'bank_bank') {
      final fromId = await resolveAccount(_text(body['fromAccountId']));
      final toId = await resolveAccount(_text(body['toAccountId']));
      if (fromId == toId) throw Exception('Kaynak ve hedef hesap farklı olmalı.');
      final fromLabel = _text(_accountById(_text(body['fromAccountId']))?['label']);
      final toLabel = _text(_accountById(_text(body['toAccountId']))?['label']);
      final base = desc.isEmpty ? 'Hesap transferi' : desc;
      await writeTx(
        accountId: fromId,
        direction: 'out',
        value: amount,
        description: '$base → $toLabel',
        reference: 'TRF',
      );
      await writeTx(
        accountId: toId,
        direction: 'in',
        value: amount,
        description: '$base ← $fromLabel',
        reference: 'TRF',
      );
      if (fee > 0.009) {
        await writeTx(
          accountId: fromId,
          direction: 'out',
          value: fee,
          description: 'Transfer masrafı${desc.isEmpty ? '' : ': $desc'}',
          reference: 'TRF-FEE',
        );
      }
      return;
    }

    // Kasa ↔ banka: kasayı da CRM hesabı olarak çöz.
    final bankId = await resolveAccount(_text(body['accountId']));
    final kasaAdi = _text(body['kasaAdi']);
    if (kasaAdi.isEmpty) throw Exception('Kasa seçin.');
    Map<String, dynamic>? kasaRow;
    for (final k in _visibleKasas()) {
      if (_text(k['kasaAdi']) == kasaAdi || _text(k['name']) == kasaAdi) {
        kasaRow = k;
        break;
      }
    }
    kasaRow ??= {
      'kasaAdi': kasaAdi,
      'name': kasaAdi,
      'label': kasaAdi,
      'account_type': 'cash',
      'currency': 'TRY',
    };
    final kasaId = await _ensureCrmAccount({
      ...kasaRow,
      'label': kasaAdi,
      'account_type': 'cash',
    });
    if (kasaId == null || kasaId.isEmpty) {
      throw Exception('Kasa CRM’ye alınamadı.');
    }
    final toBank = type == 'kasa_bank' || type.contains('kasa_bank');
    final bankLabel = _text(_accountById(_text(body['accountId']))?['label']);
    final base = desc.isEmpty ? 'Kasa-Banka transferi' : desc;
    if (toBank) {
      await writeTx(
        accountId: kasaId,
        direction: 'out',
        value: amount,
        description: '$base → $bankLabel',
        reference: 'TRF',
      );
      await writeTx(
        accountId: bankId,
        direction: 'in',
        value: amount,
        description: '$base ← $kasaAdi',
        reference: 'TRF',
      );
    } else {
      await writeTx(
        accountId: bankId,
        direction: 'out',
        value: amount,
        description: '$base → $kasaAdi',
        reference: 'TRF',
      );
      await writeTx(
        accountId: kasaId,
        direction: 'in',
        value: amount,
        description: '$base ← $bankLabel',
        reference: 'TRF',
      );
    }
    if (fee > 0.009) {
      await writeTx(
        accountId: toBank ? kasaId : bankId,
        direction: 'out',
        value: fee,
        description: 'Transfer masrafı${desc.isEmpty ? '' : ': $desc'}',
        reference: 'TRF-FEE',
      );
    }
  }

  String? _crmBankId(Map<String, dynamic> body) {
    final sourceId = _text(body['sourceId']);
    for (final b in _crmBanks) {
      if (_text(b['id']) == sourceId || _text(b['akinsoft_source_id']) == sourceId) {
        return _text(b['id']);
      }
    }
    return null;
  }

  String get _title {
    switch (widget.section) {
      case 'kasa':
        return 'Kasa';
      case 'transferler':
        return 'Transferler';
      case 'masraf':
        return 'Masraf Faturaları';
      case 'bankalar':
      default:
        return 'Bankalar / Hesaplar';
    }
  }

  String get _subtitle {
    if (!kAkinsoftBridgeEnabled) {
      switch (widget.section) {
        case 'kasa':
          return 'CRM kasa hesapları';
        case 'transferler':
          return 'Transferler CRM hesap hareketi olarak kaydedilir';
        case 'masraf':
          return 'Masraflar için Bankalar ekranından hareket ekleyin';
        default:
          return 'Bakiyeler CRM hareketleriyle güncellenir';
      }
    }
    final when = _pulledAt == null
        ? 'Wolvox MSSQL ile canlı senkron'
        : 'Son çekim: ${DateFormat('dd.MM.yyyy HH:mm').format(_pulledAt!.toLocal())}';
    switch (widget.section) {
      case 'kasa':
        return 'KASA tablosu — $when';
      case 'transferler':
        return 'BANKAHR / KASAHR transferleri — $when';
      case 'masraf':
        return 'MSF / FATURA_DURUMU=7 — $when';
      default:
        return 'Hareketler bu ekranda — $when';
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPageLayout(
      title: _title,
      subtitle: _subtitle,
      compactHeader: true,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading
              ? null
              : (kAkinsoftBridgePullEnabled || kAkinsoftBridgeEnabled
                    ? _pull
                    : _loadLocal),
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          label: Text(
            !kAkinsoftBridgeEnabled && kAkinsoftBridgePullEnabled
                ? 'ERP’den Aktar'
                : (kAkinsoftBridgeEnabled ? 'ERP’den Çek' : 'Yenile'),
          ),
        ),
        if (widget.section == 'bankalar')
          FilledButton.icon(
            onPressed: _loading ? null : () => _showBankDialog(),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Banka'),
          ),
        if (widget.section == 'bankalar')
          FilledButton.tonalIcon(
            onPressed: _loading || _visibleBanks().isEmpty
                ? null
                : () => _showAccountDialog(),
            icon: const Icon(LucideIcons.walletCards, size: 18),
            label: const Text('Hesap'),
          ),
        if (widget.section == 'bankalar')
          FilledButton.tonalIcon(
            onPressed: _loading || _selectedAccountKey == null
                ? null
                : () => _showMovementDialog(),
            icon: const Icon(LucideIcons.listPlus, size: 18),
            label: const Text('Hareket'),
          ),
        OutlinedButton.icon(
          onPressed: () => context.go('/finans/log'),
          icon: const Icon(LucideIcons.scrollText, size: 18),
          label: const Text('Günlük'),
        ),
        if (widget.section == 'kasa')
          FilledButton.icon(
            onPressed: _loading ? null : () => _showKasaDialog(),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Kasa'),
          ),
        if (widget.section == 'transferler')
          FilledButton.icon(
            onPressed: _loading ? null : () => _showTransferDialog(),
            icon: const Icon(LucideIcons.arrowLeftRight, size: 18),
            label: const Text('Transfer'),
          ),
        if (widget.section == 'masraf')
          FilledButton.icon(
            onPressed: _loading ? null : () => _showMasrafDialog(),
            icon: const Icon(LucideIcons.receiptText, size: 18),
            label: const Text('Masraf'),
          ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            const Gap(8),
            _Banner(message: _error!, tone: AppBadgeTone.error),
          ],
          if (_status != null && _error == null) ...[
            const Gap(8),
            _Banner(message: _status!, tone: AppBadgeTone.primary),
          ],
          const Gap(10),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    switch (widget.section) {
      case 'kasa':
        return _KasaList(
          items: _visibleKasas(),
          onEdit: (row) => _showKasaDialog(existing: row),
          onDelete: (row) => _mutate(
            'finance/kasa',
            {'action': 'delete', 'sourceId': row['sourceId'] ?? row['id']},
            successMessage: 'Kasa silindi.',
          ),
        );
      case 'transferler':
        return _TransferList(
          items: _visibleTransfers(),
          onDelete: (row) => _mutate(
            'finance/transfer',
            {
              'action': 'delete',
              'type': row['type'],
              'sourceId': row['sourceId'],
              'pairSourceId': row['pairSourceId'],
              'evrakNo': row['evrakNo'],
            },
            successMessage: 'Transfer silindi.',
          ),
        );
      case 'masraf':
        return _MasrafList(
          items: kAkinsoftBridgeEnabled ? _masraf : _visibleMasraf(),
          onDelete: (row) => _mutate(
            'finance/masraf',
            {'action': 'delete', 'sourceId': row['sourceId']},
            successMessage: 'Masraf faturası silindi.',
          ),
        );
      case 'bankalar':
      default:
        return _BanksAccountsPane(
          banks: _visibleBanks(),
          accounts: _visibleAccounts(),
          movements: _movementsForSelected(),
          selectedAccountKey: _selectedAccountKey,
          onSelectAccount: (key) => setState(() => _selectedAccountKey = key),
          onEditBank: (row) => _showBankDialog(existing: row),
          onDeleteBank: (row) => _mutate('finance/bank', {
            'action': 'delete',
            'sourceId': row['sourceId'] ?? row['id'],
          }, successMessage: 'Banka CRM’de silindi.'),
          onEditAccount: (row) => _showAccountDialog(existing: row),
          onDeleteAccount: (row) => _mutate(
            'finance/bank-account',
            {'action': 'delete', 'sourceId': row['sourceId'] ?? row['id']},
            successMessage: 'Hesap CRM’de silindi.',
          ),
          onOpenMovement: (row) => _showMovementDialog(existing: row),
        );
    }
  }

  String _normalizeCurrency(String value) {
    final t = value.trim().toUpperCase();
    if (t.isEmpty || t == 'TL' || t == 'TRY' || t == '₺') return 'TRY';
    if (t == r'$' || t == r'US$' || t == 'USD') return 'USD';
    if (t == '€' || t == 'EUR') return 'EUR';
    if (t == '£' || t == 'GBP' || t == 'STG' || t == 'STERLIN') return 'GBP';
    return t;
  }

  String _normalizeBankName(String value) {
    return value
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('i\u0307', 'i') // Dart İ → i + combining dot
        .replaceAll('ş', 's')
        .replaceAll('ğ', 'g')
        .replaceAll('ü', 'u')
        .replaceAll('ö', 'o')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// HALK BANK / Halk Bank STG / İŞBANK → aynı kök.
  String _bankStem(String value) {
    var n = _normalizeBankName(value);
    if (n.isEmpty) return '';
    n = n.replaceAll(
      RegExp(r'(try|tl|usd|eur|euro|gbp|stg|sterlin|usdollari?)$'),
      '',
    );
    if (n.contains('halk')) return 'halkbank';
    if (n.contains('garanti')) return 'garanti';
    if (n.contains('isbank') ||
        n.contains('isbankasi') ||
        n == 'ibank' ||
        (n.startsWith('is') && n.contains('bank'))) {
      return 'isbank';
    }
    if (n.contains('akbank')) return 'akbank';
    if (n.contains('yapikredi') || n.contains('ykb')) return 'yapikredi';
    if (n.contains('ziraat')) return 'ziraat';
    if (n.contains('vakif')) return 'vakifbank';
    return n;
  }

  String _accountBankStem(Map<String, dynamic> a) {
    final bankName = _text(a['bank_name']);
    if (bankName.isNotEmpty) return _bankStem(bankName);
    return _bankStem(_text(a['name']));
  }

  String _accountDedupeKey(Map<String, dynamic> a) {
    final currency = _normalizeCurrency(_text(a['currency']));
    final bank = _accountBankStem(a);
    final iban = _text(a['iban']).replaceAll(' ', '').toUpperCase();
    final no = _text(a['account_no'] ?? a['hesapNo']).replaceAll(' ', '');
    if (iban.isNotEmpty) return '$currency|iban:$iban';
    if (no.isNotEmpty && bank.isNotEmpty) return '$currency|$bank|no:$no';
    // Aynı banka + döviz = tek hesap (eski CRM adı ≠ ERP etiketi)
    if (bank.isNotEmpty) return '$currency|$bank';
    final name = _normalizeBankName(_text(a['name']));
    return '$currency|name:$name';
  }

  Map<String, dynamic>? _matchCrmAccount(Map<String, dynamic> sapAccount) {
    final sourceId = _text(sapAccount['sourceId']);
    for (final existing in _crmAccounts) {
      if (sourceId.isNotEmpty &&
          _text(existing['akinsoft_source_id']) == sourceId) {
        return existing;
      }
    }
    final key = _accountDedupeKey({
      'bank_name': sapAccount['bankName'],
      'name': sapAccount['label'] ?? sapAccount['tanimi'],
      'currency': sapAccount['currency'],
      'iban': sapAccount['iban'],
      'account_no': sapAccount['hesapNo'],
    });
    for (final existing in _crmAccounts) {
      if (_text(existing['account_type']) == 'cash') continue;
      if (existing['is_active'] == false) continue;
      if (_accountDedupeKey(existing) == key) return existing;
    }
    // banka + döviz (birden fazla varsa ERP bakiyesi olan / kaynaklı tercih)
    final bank = _bankStem(_text(sapAccount['bankName']));
    final currency = _normalizeCurrency(_text(sapAccount['currency']));
    final sameBankCurrency = _crmAccounts.where((existing) {
      if (_text(existing['account_type']) == 'cash') return false;
      if (existing['is_active'] == false) return false;
      if (_normalizeCurrency(_text(existing['currency'])) != currency) {
        return false;
      }
      return _accountBankStem(existing) == bank && bank.isNotEmpty;
    }).toList();
    if (sameBankCurrency.isEmpty) return null;
    sameBankCurrency.sort((a, b) {
      final aSap = _text(a['akinsoft_source_id']).isNotEmpty ? 0 : 1;
      final bSap = _text(b['akinsoft_source_id']).isNotEmpty ? 0 : 1;
      if (aSap != bSap) return aSap - bSap;
      return _num(b['current_balance']).abs().compareTo(_num(a['current_balance']).abs());
    });
    return sameBankCurrency.first;
  }

  /// ERP aktarımından kalan çift hesapları birleştirir.
  Future<void> _dedupeCrmAccounts() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    await _loadCrmFinance();
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final a in _crmAccounts) {
      if (_text(a['account_type']) == 'cash') continue;
      if (a['is_active'] == false) continue;
      final key = _accountDedupeKey(a);
      groups.putIfAbsent(key, () => []).add(Map<String, dynamic>.from(a));
    }

    for (final group in groups.values) {
      if (group.length < 2) continue;
      group.sort((a, b) {
        final aSap = _text(a['akinsoft_source_id']).isNotEmpty ? 0 : 1;
        final bSap = _text(b['akinsoft_source_id']).isNotEmpty ? 0 : 1;
        if (aSap != bSap) return aSap - bSap;
        final aBal = _num(a['current_balance']).abs();
        final bBal = _num(b['current_balance']).abs();
        return bBal.compareTo(aBal);
      });
      final keeper = group.first;
      final keeperId = _text(keeper['id']);
      if (keeperId.isEmpty) continue;
      for (final orphan in group.skip(1)) {
        final orphanId = _text(orphan['id']);
        if (orphanId.isEmpty || orphanId == keeperId) continue;
        for (final t in _crmTransactions) {
          if (_text(t['account_id']) != orphanId) continue;
          await api.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'finance_transactions',
              'values': {
                'id': t['id'],
                'account_id': keeperId,
              },
            },
          );
        }
        // ERP kaynağını koru
        if (_text(keeper['akinsoft_source_id']).isEmpty &&
            _text(orphan['akinsoft_source_id']).isNotEmpty) {
          await api.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'finance_accounts',
              'values': {
                'id': keeperId,
                'akinsoft_source_id': orphan['akinsoft_source_id'],
                'akinsoft_bank_source_id': orphan['akinsoft_bank_source_id'],
                'name': orphan['name'],
                'bank_name': orphan['bank_name'],
                'account_no': orphan['account_no'],
                'iban': orphan['iban'],
              },
            },
          );
        }
        try {
          await api.postJson(
            '/mutate',
            body: {'op': 'delete', 'table': 'finance_accounts', 'id': orphanId},
          );
        } catch (_) {
          await api.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'finance_accounts',
              'values': {'id': orphanId, 'is_active': false, 'name': orphan['name']},
            },
          );
        }
      }
    }
    // Hareketler taşındıktan sonra bakiyeleri yeniden hesapla.
    await _loadCrmFinance();
    final keeperIds = <String>{};
    for (final group in groups.values) {
      if (group.length < 2) continue;
      final id = _text(group.first['id']);
      if (id.isNotEmpty) keeperIds.add(id);
    }
    for (final id in keeperIds) {
      await _recalcAccountBalance(id);
    }
    await _loadCrmFinance();
  }

  Future<void> _recalcAccountBalance(String accountId) async {
    final api = ref.read(apiClientProvider);
    if (api == null || accountId.isEmpty) return;
    Map<String, dynamic>? account;
    for (final a in _crmAccounts) {
      if (_text(a['id']) == accountId) {
        account = a;
        break;
      }
    }
    final opening = _num(account?['opening_balance']);
    var txSum = 0.0;
    for (final t in _crmTransactions) {
      if (_text(t['account_id']) != accountId) continue;
      if (t['is_active'] == false) continue;
      final amount = _num(t['amount']).abs();
      txSum += _text(t['direction']) == 'out' ? -amount : amount;
    }
    await api.postJson(
      '/mutate',
      body: {
        'op': 'upsert',
        'table': 'finance_accounts',
        'values': {
          'id': accountId,
          'current_balance': opening + txSum,
        },
      },
    );
  }

  List<Map<String, dynamic>> _crmBankRows() {
    final fromTable = _crmBanks
        .map(
          (b) => {
            ...b,
            'sourceId': _text(b['akinsoft_source_id']).isEmpty
                ? _text(b['id'])
                : _text(b['akinsoft_source_id']),
            'bankName': b['name'],
            'origin': 'crm',
          },
        )
        .toList();
    if (fromTable.isNotEmpty) return fromTable;
    // finance_banks boşsa hesaplardaki banka adlarından üret.
    final names = <String>{};
    for (final a in _crmAccounts) {
      if (_text(a['account_type']) == 'cash') continue;
      if (a['is_active'] == false) continue;
      final name = _text(a['bank_name']);
      if (name.isNotEmpty) names.add(name);
    }
    return [
      for (final name in names)
        {
          'id': 'derived-$name',
          'sourceId': 'derived-$name',
          'name': name,
          'bankName': name,
          'origin': 'crm',
        },
    ];
  }

  List<Map<String, dynamic>> _crmAccountRows({String? accountType}) {
    final rows = _crmAccounts
        .where((a) {
          if (a['is_active'] == false) return false;
          if (accountType == null) {
            return _text(a['account_type']) != 'cash';
          }
          return _text(a['account_type']) == accountType;
        })
        .map(
          (a) => {
            ...a,
            'sourceId': _text(a['akinsoft_source_id']).isEmpty
                ? _text(a['id'])
                : _text(a['akinsoft_source_id']),
            'label': _text(a['name']),
            'kasaAdi': _text(a['name']),
            'balance': a['current_balance'] ?? 0,
            'origin': 'crm',
          },
        )
        .toList();
    // Aynı banka+döviz için ERP kaynaklı / dolu bakiyeli olanı göster.
    final best = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final bank = _accountBankStem(row);
      final currency = _normalizeCurrency(_text(row['currency']));
      final key = bank.isEmpty
          ? '$currency|id:${_text(row['id'])}'
          : '$currency|$bank';
      final prev = best[key];
      if (prev == null) {
        best[key] = row;
        continue;
      }
      final prevSap = _text(prev['akinsoft_source_id']).isNotEmpty;
      final rowSap = _text(row['akinsoft_source_id']).isNotEmpty;
      if (rowSap && !prevSap) {
        best[key] = row;
      } else if (rowSap == prevSap &&
          _num(row['current_balance']).abs() >
              _num(prev['current_balance']).abs()) {
        best[key] = row;
      }
    }
    final list = best.values.toList();
    list.sort((a, b) {
      final bank = _text(a['bank_name']).compareTo(_text(b['bank_name']));
      if (bank != 0) return bank;
      return _text(a['name']).compareTo(_text(b['name']));
    });
    return list;
  }

  List<Map<String, dynamic>> _visibleBanks() {
    if (!kAkinsoftBridgeEnabled) return _crmBankRows();
    final sapIds = {for (final b in _banks) _text(b['sourceId'])};
    final extra = _crmBankRows().where((b) {
      final sap = _text(b['akinsoft_source_id']);
      return sap.isEmpty || !sapIds.contains(sap);
    });
    return [..._banks, ...extra];
  }

  List<Map<String, dynamic>> _visibleAccounts() {
    if (!kAkinsoftBridgeEnabled) return _crmAccountRows();
    final sapIds = {for (final a in _accounts) _text(a['sourceId'])};
    final extra = _crmAccountRows().where((a) {
      final sap = _text(a['akinsoft_source_id']);
      return sap.isEmpty || !sapIds.contains(sap);
    });
    return [..._accounts, ...extra];
  }

  List<Map<String, dynamic>> _visibleKasas() {
    if (!kAkinsoftBridgeEnabled) return _crmAccountRows(accountType: 'cash');
    return _kasas;
  }

  List<Map<String, dynamic>> _visibleTransfers() {
    if (kAkinsoftBridgeEnabled) return _transfers;
    final transfers = _crmTransactions
        .where((t) => _text(t['transaction_type']) == 'transfer')
        .map((t) {
          final amount = _num(t['amount']);
          final direction = _text(t['direction']);
          return {
            ...t,
            'sourceId': _text(t['id']),
            'type': 'bank_bank',
            'date': t['transaction_date'],
            'amount': direction == 'out' ? -amount.abs() : amount.abs(),
            'evrakNo': t['reference_no'],
            'description': t['description'],
            'origin': 'crm',
          };
        })
        .toList();
    transfers.sort((a, b) {
      final da = DateTime.tryParse(_text(a['date'])) ?? DateTime(1970);
      final db = DateTime.tryParse(_text(b['date'])) ?? DateTime(1970);
      return db.compareTo(da);
    });
    return transfers;
  }

  List<Map<String, dynamic>> _visibleMasraf() {
    final items = _crmTransactions
        .where((t) => _text(t['transaction_type']) == 'masraf')
        .map((t) {
          final amount = _num(t['amount']).abs();
          return {
            ...t,
            'sourceId': _text(t['id']),
            'date': t['transaction_date'],
            'faturaNo': t['reference_no'],
            'cariUnvan': t['description'],
            'total': amount,
            'amount': amount,
            'origin': 'crm',
          };
        })
        .toList();
    items.sort((a, b) {
      final da = DateTime.tryParse(_text(a['date'])) ?? DateTime(1970);
      final db = DateTime.tryParse(_text(b['date'])) ?? DateTime(1970);
      return db.compareTo(da);
    });
    return items;
  }

  Future<void> _showMovementDialog({Map<String, dynamic>? existing}) async {
    final account = _selectedAccount();
    if (account == null) {
      setState(() => _error = 'Önce bir hesap seçin.');
      return;
    }
    final isCrm = _text(existing?['origin']) == 'crm' ||
        _text(existing?['id']).contains('-');
    if (existing != null && !isCrm && kAkinsoftBridgeEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bu hareket CRM kopyası üzerinden düzeltilecek.',
          ),
        ),
      );
    }
    DateTime date =
        DateTime.tryParse(_text(existing?['date'] ?? existing?['transaction_date'])) ??
            DateTime.now();
    String direction = _text(existing?['direction']).isEmpty
        ? ((existing?['amount'] is num && (existing?['amount'] as num) < 0)
              ? 'out'
              : 'in')
        : _text(existing?['direction']);
    final amountCtrl = TextEditingController(
      text: existing == null
          ? ''
          : ((existing['amount'] is num)
                    ? (existing['amount'] as num).abs()
                    : double.tryParse('${existing['amount']}')?.abs() ?? 0)
                .toStringAsFixed(2)
                .replaceAll('.', ','),
    );
    final descCtrl = TextEditingController(
      text: _text(existing?['description']),
    );
    final refCtrl = TextEditingController(
      text: _text(existing?['evrakNo'] ?? existing?['reference_no']),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Hareket Ekle' : 'Hareketi Düzelt'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Tarih'),
                  subtitle: Text(DateFormat('dd.MM.yyyy').format(date)),
                  trailing: IconButton(
                    icon: const Icon(LucideIcons.calendarDays),
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: date,
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked != null) setLocal(() => date = picked);
                    },
                  ),
                ),
                DropdownButtonFormField<String>(
                  initialValue: direction,
                  decoration: const InputDecoration(labelText: 'Yön'),
                  items: const [
                    DropdownMenuItem(value: 'in', child: Text('Giriş')),
                    DropdownMenuItem(value: 'out', child: Text('Çıkış')),
                  ],
                  onChanged: (v) => setLocal(() => direction = v ?? 'in'),
                ),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyDecimalInputFormatters,
                  decoration: const InputDecoration(labelText: 'Tutar'),
                ),
                TextField(
                  controller: refCtrl,
                  decoration: const InputDecoration(labelText: 'Evrak / referans'),
                ),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    final accountId = await _ensureCrmAccount(account);
    if (accountId == null) {
      setState(() => _error = 'Hesap CRM’ye alınamadı.');
      return;
    }
    final amount = parseCurrencyValue(amountCtrl.text) ?? 0;
    if (amount <= 0) {
      setState(() => _error = 'Tutar girin.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await api.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'finance_transactions',
          'values': {
            if (isCrm && _text(existing?['id']).isNotEmpty) 'id': existing!['id'],
            'account_id': accountId,
            'transaction_date': DateFormat('yyyy-MM-dd').format(date),
            'direction': direction,
            'transaction_type': 'manual',
            'payment_method': 'bank',
            'amount': amount,
            'currency': _text(account['currency']).isEmpty
                ? 'TRY'
                : _text(account['currency']),
            'description': descCtrl.text.trim(),
            'reference_no': refCtrl.text.trim(),
            'source': 'crm',
            'akinsoft_source_id': _text(existing?['sourceId']).isEmpty
                ? null
                : _text(existing?['sourceId']),
            'is_active': true,
          },
        },
      );
      await _loadCrmFinance();
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hareket kaydedildi.')),
      );
      if (!kAkinsoftBridgeEnabled) {
        setState(() {
          _status =
              '${_crmBanks.length} banka, ${_crmAccounts.length} hesap · bakiyeler CRM hareketleriyle güncellenir';
        });
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _showBankDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: _text(existing?['bankName']));
    final branchCtrl = TextEditingController(text: _text(existing?['branch']));
    final phoneCtrl = TextEditingController(text: _text(existing?['phone']));
    final addressCtrl = TextEditingController(
      text: _text(existing?['address']),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Banka Ekle' : 'Banka Düzenle'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Banka adı *'),
              ),
              TextField(
                controller: branchCtrl,
                decoration: const InputDecoration(labelText: 'Şube'),
              ),
              TextField(
                controller: phoneCtrl,
                decoration: const InputDecoration(labelText: 'Telefon'),
              ),
              TextField(
                controller: addressCtrl,
                decoration: const InputDecoration(labelText: 'Adres'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(
      'finance/bank',
      {
        if (existing != null) 'sourceId': existing['sourceId'],
        'bankName': nameCtrl.text.trim(),
        'branch': branchCtrl.text.trim(),
        'phone': phoneCtrl.text.trim(),
        'address': addressCtrl.text.trim(),
      },
      successMessage: existing == null ? 'Banka eklendi.' : 'Banka güncellendi.',
    );
  }

  Future<void> _showAccountDialog({Map<String, dynamic>? existing}) async {
    final banks = _visibleBanks();
    String? bankId = _text(existing?['bankSourceId']).isEmpty &&
            _text(existing?['akinsoft_bank_source_id']).isEmpty
        ? (banks.isEmpty ? null : _text(banks.first['sourceId']).isEmpty
              ? _text(banks.first['id'])
              : _text(banks.first['sourceId']))
        : (_text(existing?['bankSourceId']).isEmpty
              ? _text(existing?['akinsoft_bank_source_id'])
              : _text(existing?['bankSourceId']));
    final tanimCtrl = TextEditingController(
      text: _text(existing?['tanimi']).isEmpty
          ? _text(existing?['label'] ?? existing?['name'])
          : _text(existing?['tanimi']),
    );
    final hesapCtrl = TextEditingController(
      text: _text(existing?['hesapNo'] ?? existing?['account_no']),
    );
    final ibanCtrl = TextEditingController(text: _text(existing?['iban']));
    final openingCtrl = TextEditingController(
      text: _num(existing?['opening_balance']).toStringAsFixed(2).replaceAll('.', ','),
    );
    String currency = _text(existing?['currency']).isEmpty
        ? 'TRY'
        : _text(existing?['currency']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(existing == null ? 'Hesap Ekle' : 'Hesap Düzenle'),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: bankId,
                  decoration: const InputDecoration(labelText: 'Banka *'),
                  items: [
                    for (final bank in banks)
                      DropdownMenuItem(
                        value: _text(bank['sourceId']).isEmpty
                            ? _text(bank['id'])
                            : _text(bank['sourceId']),
                        child: Text(_text(bank['bankName'] ?? bank['name'])),
                      ),
                  ],
                  onChanged: (value) => setLocal(() => bankId = value),
                ),
                TextField(
                  controller: tanimCtrl,
                  decoration: const InputDecoration(labelText: 'Hesap tanımı'),
                ),
                TextField(
                  controller: hesapCtrl,
                  decoration: const InputDecoration(labelText: 'Hesap no'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  decoration: const InputDecoration(labelText: 'Döviz'),
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TL')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                    DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                  ],
                  onChanged: (value) =>
                      setLocal(() => currency = value ?? 'TRY'),
                ),
                TextField(
                  controller: ibanCtrl,
                  decoration: const InputDecoration(labelText: 'IBAN'),
                ),
                TextField(
                  controller: openingCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: moneyDecimalInputFormatters,
                  decoration: const InputDecoration(
                    labelText: 'Açılış bakiyesi',
                    helperText:
                        'Eski ERP bakiyesini buraya yazın; CRM hareketleri üzerine eklenir.',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || bankId == null) return;
    final crmId = _text(existing?['id']).contains('-')
        ? _text(existing?['id'])
        : '';
    await _mutate(
      'finance/bank-account',
      {
        if (existing != null) 'sourceId': existing['sourceId'] ?? existing['id'],
        if (crmId.isNotEmpty) 'crmId': crmId,
        'bankSourceId': bankId,
        'tanimi': tanimCtrl.text.trim(),
        'hesapNo': hesapCtrl.text.trim(),
        'currency': currency,
        'iban': ibanCtrl.text.trim(),
        'opening_balance': parseCurrencyValue(openingCtrl.text) ?? 0,
      },
      successMessage: existing == null ? 'Hesap eklendi.' : 'Hesap güncellendi.',
    );
  }

  Future<void> _showKasaDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: _text(existing?['kasaAdi']));
    final yetkiliCtrl = TextEditingController(
      text: _text(existing?['yetkilisi']),
    );
    final noteCtrl = TextEditingController(text: _text(existing?['aciklama1']));
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(existing == null ? 'Kasa Ekle' : 'Kasa Düzenle'),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Kasa adı * (max 10)',
                ),
                maxLength: 10,
              ),
              TextField(
                controller: yetkiliCtrl,
                decoration: const InputDecoration(labelText: 'Yetkilisi'),
              ),
              TextField(
                controller: noteCtrl,
                decoration: const InputDecoration(labelText: 'Açıklama'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(
      'finance/kasa',
      {
        if (existing != null) 'sourceId': existing['sourceId'],
        'kasaAdi': nameCtrl.text.trim(),
        'yetkilisi': yetkiliCtrl.text.trim(),
        'aciklama1': noteCtrl.text.trim(),
      },
      successMessage: existing == null ? 'Kasa eklendi.' : 'Kasa güncellendi.',
    );
  }

  Map<String, dynamic>? _accountById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in _visibleAccounts()) {
      if (_accountKey(a) == id || _text(a['sourceId']) == id) return a;
    }
    for (final a in _accounts) {
      if (_text(a['sourceId']) == id) return a;
    }
    return null;
  }

  Future<void> _showTransferDialog() async {
    final accounts = _visibleAccounts();
    final kasas = _visibleKasas();
    String type = 'bank_bank';
    String? fromAccount = accounts.isEmpty
        ? null
        : _accountKey(accounts.first);
    String? toAccount = accounts.length > 1
        ? _accountKey(accounts[1])
        : fromAccount;
    String? accountId = fromAccount;
    String? kasaAdi = kasas.isEmpty
        ? null
        : (_text(kasas.first['kasaAdi']).isEmpty
              ? _text(kasas.first['name'])
              : _text(kasas.first['kasaAdi']));
    DateTime date = DateTime.now();
    final amountCtrl = TextEditingController();
    final feeCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          final currencyAccount = type == 'bank_bank'
              ? _accountById(fromAccount)
              : _accountById(accountId);
          final currency = _text(currencyAccount?['currency']).isEmpty
              ? 'TRY'
              : _text(currencyAccount?['currency']);
          return AlertDialog(
            title: const Text('Transfer'),
            content: SizedBox(
              width: 480,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Tür'),
                      items: const [
                        DropdownMenuItem(
                          value: 'bank_bank',
                          child: Text('Banka → Banka'),
                        ),
                        DropdownMenuItem(
                          value: 'kasa_bank',
                          child: Text('Kasa → Banka'),
                        ),
                        DropdownMenuItem(
                          value: 'bank_kasa',
                          child: Text('Banka → Kasa'),
                        ),
                      ],
                      onChanged: (value) =>
                          setLocal(() => type = value ?? type),
                    ),
                    const Gap(8),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tarih'),
                      subtitle: Text(DateFormat('dd.MM.yyyy').format(date)),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.calendarDays),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => date = picked);
                          }
                        },
                      ),
                    ),
                    if (type == 'bank_bank') ...[
                      DropdownButtonFormField<String>(
                        initialValue: fromAccount,
                        decoration: const InputDecoration(
                          labelText: 'Kaynak hesap *',
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: _accountKey(a),
                              child: Text(_text(a['label'] ?? a['name'])),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => fromAccount = v),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: toAccount,
                        decoration: const InputDecoration(
                          labelText: 'Hedef hesap *',
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: _accountKey(a),
                              child: Text(_text(a['label'] ?? a['name'])),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => toAccount = v),
                      ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        initialValue: kasaAdi,
                        decoration: const InputDecoration(labelText: 'Kasa *'),
                        items: [
                          for (final k in kasas)
                            DropdownMenuItem(
                              value: _text(k['kasaAdi']).isEmpty
                                  ? _text(k['name'])
                                  : _text(k['kasaAdi']),
                              child: Text(
                                _text(k['kasaAdi']).isEmpty
                                    ? _text(k['name'])
                                    : _text(k['kasaAdi']),
                              ),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => kasaAdi = v),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: accountId,
                        decoration: const InputDecoration(
                          labelText: 'Banka hesabı *',
                        ),
                        items: [
                          for (final a in accounts)
                            DropdownMenuItem(
                              value: _accountKey(a),
                              child: Text(_text(a['label'] ?? a['name'])),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => accountId = v),
                      ),
                    ],
                    TextField(
                      controller: amountCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Tutar * ($currency)',
                        helperText: 'Her iki hesaba CRM hareketi yazılır',
                      ),
                    ),
                    const Gap(8),
                    TextField(
                      controller: feeCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Masraf ($currency)',
                        helperText:
                            'Kaynak hesaptan düşülür. Boş bırakılabilir.',
                      ),
                    ),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Açıklama'),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final amount =
        double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final masraf =
        double.tryParse(feeCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final payload = <String, dynamic>{
      'type': type,
      'amount': amount,
      'masraf': masraf,
      'description': descCtrl.text.trim(),
      'date': date.toIso8601String(),
      'currency': _text(
        (type == 'bank_bank'
            ? _accountById(fromAccount)
            : _accountById(accountId))?['currency'],
      ),
    };
    if (type == 'bank_bank') {
      payload['fromAccountId'] = fromAccount;
      payload['toAccountId'] = toAccount;
    } else {
      payload['kasaAdi'] = kasaAdi;
      payload['accountId'] = accountId;
      payload['direction'] = type;
    }
    await _mutate(
      'finance/transfer',
      payload,
      successMessage: 'Transfer kaydedildi.',
    );
    if (!kAkinsoftBridgeEnabled) {
      await _loadLocal();
    }
  }

  Future<void> _showMasrafDialog() async {
    DateTime date = DateTime.now();
    final cariCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final lines = <_MasrafLineDraft>[_MasrafLineDraft()];
    var payMethod = _kasas.isNotEmpty
        ? 'cash'
        : (_accounts.isNotEmpty ? 'bank' : 'cash');
    String? kasaAdi = _kasas.isEmpty ? null : _text(_kasas.first['kasaAdi']);
    String? bankAccountId = _accounts.isEmpty
        ? null
        : _text(_accounts.first['sourceId']);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) {
          double alt = 0;
          double kdv = 0;
          for (final line in lines) {
            final net = line.qty * line.unitPrice;
            alt += net;
            kdv += net * (line.taxRate / 100);
          }
          final genel = alt + kdv;
          return AlertDialog(
            title: const Text('Masraf Faturası'),
            content: SizedBox(
              width: 560,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Tarih'),
                      subtitle: Text(DateFormat('dd.MM.yyyy').format(date)),
                      trailing: IconButton(
                        icon: const Icon(LucideIcons.calendarDays),
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: date,
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (picked != null) {
                            setLocal(() => date = picked);
                          }
                        },
                      ),
                    ),
                    TextField(
                      controller: cariCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Cari / Ünvan',
                      ),
                    ),
                    TextField(
                      controller: descCtrl,
                      decoration: const InputDecoration(labelText: 'Açıklama'),
                    ),
                    const Gap(8),
                    DropdownButtonFormField<String>(
                      key: ValueKey('masraf-pay-$payMethod'),
                      initialValue: payMethod,
                      decoration: const InputDecoration(
                        labelText: 'Çıkış kaynağı *',
                        helperText: 'Tutar bu kasa veya banka hesabından düşülür.',
                      ),
                      items: const [
                        DropdownMenuItem(value: 'cash', child: Text('Kasa')),
                        DropdownMenuItem(value: 'bank', child: Text('Banka')),
                      ],
                      onChanged: (value) =>
                          setLocal(() => payMethod = value ?? payMethod),
                    ),
                    if (payMethod == 'cash') ...[
                      const Gap(8),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _kasas.any((k) => _text(k['kasaAdi']) == kasaAdi)
                            ? kasaAdi
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Kasa *',
                          helperText: _kasas.isEmpty
                              ? 'Önce Kasa ekranından kasa ekleyin.'
                              : null,
                        ),
                        items: [
                          for (final k in _kasas)
                            DropdownMenuItem(
                              value: _text(k['kasaAdi']),
                              child: Text(_text(k['kasaAdi'])),
                            ),
                        ],
                        onChanged: _kasas.isEmpty
                            ? null
                            : (v) => setLocal(() => kasaAdi = v),
                      ),
                    ] else ...[
                      const Gap(8),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _accounts.any(
                              (a) => _text(a['sourceId']) == bankAccountId,
                            )
                            ? bankAccountId
                            : null,
                        decoration: InputDecoration(
                          labelText: 'Banka hesabı *',
                          helperText: _accounts.isEmpty
                              ? 'Önce Bankalar / Hesaplar’dan hesap ekleyin.'
                              : null,
                        ),
                        items: [
                          for (final a in _accounts)
                            DropdownMenuItem(
                              value: _text(a['sourceId']),
                              child: Text(
                                _text(a['label']).isEmpty
                                    ? _text(a['hesapNo'])
                                    : _text(a['label']),
                              ),
                            ),
                        ],
                        onChanged: _accounts.isEmpty
                            ? null
                            : (v) => setLocal(() => bankAccountId = v),
                      ),
                    ],
                    const Gap(12),
                    Row(
                      children: [
                        Text(
                          'Kalemler',
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () =>
                              setLocal(() => lines.add(_MasrafLineDraft())),
                          icon: const Icon(LucideIcons.plus, size: 18),
                          label: const Text('Kalem'),
                        ),
                      ],
                    ),
                    for (var i = 0; i < lines.length; i++) ...[
                      const Gap(8),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: AppTheme.border.withValues(alpha: 0.7),
                          ),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusSm,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      'Kalem ${i + 1}',
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelLarge,
                                    ),
                                  ),
                                  if (lines.length > 1)
                                    IconButton(
                                      tooltip: 'Kalemi sil',
                                      onPressed: () =>
                                          setLocal(() => lines.removeAt(i)),
                                      icon: const Icon(
                                        LucideIcons.trash2,
                                        size: 18,
                                      ),
                                    ),
                                ],
                              ),
                              TextField(
                                controller: lines[i].nameCtrl,
                                decoration: const InputDecoration(
                                  labelText: 'Kalem adı *',
                                ),
                                onChanged: (_) => setLocal(() {}),
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: lines[i].qtyCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Miktar',
                                      ),
                                      onChanged: (_) => setLocal(() {}),
                                    ),
                                  ),
                                  const Gap(8),
                                  Expanded(
                                    child: TextField(
                                      controller: lines[i].priceCtrl,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      inputFormatters:
                                          moneyDecimalInputFormatters,
                                      decoration: const InputDecoration(
                                        labelText: 'Birim fiyat *',
                                      ),
                                      onChanged: (_) => setLocal(() {}),
                                    ),
                                  ),
                                  const Gap(8),
                                  Expanded(
                                    child: DropdownButtonFormField<double>(
                                      initialValue: lines[i].taxRate,
                                      decoration: const InputDecoration(
                                        labelText: 'KDV %',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 0,
                                          child: Text('0'),
                                        ),
                                        DropdownMenuItem(
                                          value: 5,
                                          child: Text('5'),
                                        ),
                                        DropdownMenuItem(
                                          value: 10,
                                          child: Text('10'),
                                        ),
                                        DropdownMenuItem(
                                          value: 16,
                                          child: Text('16'),
                                        ),
                                        DropdownMenuItem(
                                          value: 20,
                                          child: Text('20'),
                                        ),
                                      ],
                                      onChanged: (v) => setLocal(
                                        () => lines[i].taxRate = v ?? 0,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const Gap(12),
                    Text(
                      'Ara toplam: ${_money(alt)}  ·  KDV: ${_money(kdv)}  ·  Genel: ${_money(genel)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const Gap(4),
                    Text(
                      'Masraf için Bankalar ekranından hesap hareketi ekleyin',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Kaydet'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final items = <Map<String, dynamic>>[];
    for (final line in lines) {
      final name = line.nameCtrl.text.trim();
      final qty = line.qty;
      final unit = line.unitPrice;
      if (name.isEmpty && unit <= 0) continue;
      items.add({
        'name': name.isEmpty ? 'Masraf' : name,
        'qty': qty <= 0 ? 1 : qty,
        'unitPrice': unit,
        'taxRate': line.taxRate,
      });
    }
    if (items.isEmpty) {
      setState(() => _error = 'En az bir masraf kalemi girin.');
      return;
    }
    if (payMethod == 'cash' && (kasaAdi ?? '').isEmpty) {
      setState(() => _error = 'Masrafın düşüleceği kasayı seçin.');
      return;
    }
    if (payMethod == 'bank' && (bankAccountId ?? '').isEmpty) {
      setState(() => _error = 'Masrafın düşüleceği banka hesabını seçin.');
      return;
    }
    await _mutate(
      'finance/masraf',
      {
        'cariUnvan': cariCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'date': date.toIso8601String(),
        'items': items,
        'payMethod': payMethod,
        if (payMethod == 'cash') 'kasaAdi': kasaAdi,
        if (payMethod == 'bank') 'bankAccountId': bankAccountId,
      },
      successMessage: 'Masraf kaydı oluşturuldu.',
    );
  }
}

class _MasrafLineDraft {
  _MasrafLineDraft()
    : nameCtrl = TextEditingController(),
      qtyCtrl = TextEditingController(text: '1'),
      priceCtrl = TextEditingController();

  final TextEditingController nameCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController priceCtrl;
  double taxRate = 0;

  double get qty => parseCurrencyValue(qtyCtrl.text) ?? 0;
  double get unitPrice => parseCurrencyValue(priceCtrl.text) ?? 0;
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.tone});

  final String message;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.primary => AppTheme.primary,
      AppBadgeTone.neutral => AppTheme.textMuted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.softTint(color, alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.softBorder(color, alpha: 0.18)),
      ),
      child: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.softFg(color),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _BanksAccountsPane extends StatelessWidget {
  const _BanksAccountsPane({
    required this.banks,
    required this.accounts,
    required this.movements,
    required this.selectedAccountKey,
    required this.onSelectAccount,
    required this.onEditBank,
    required this.onDeleteBank,
    required this.onEditAccount,
    required this.onDeleteAccount,
    required this.onOpenMovement,
  });

  final List<Map<String, dynamic>> banks;
  final List<Map<String, dynamic>> accounts;
  final List<Map<String, dynamic>> movements;
  final String? selectedAccountKey;
  final ValueChanged<String> onSelectAccount;
  final ValueChanged<Map<String, dynamic>> onEditBank;
  final ValueChanged<Map<String, dynamic>> onDeleteBank;
  final ValueChanged<Map<String, dynamic>> onEditAccount;
  final ValueChanged<Map<String, dynamic>> onDeleteAccount;
  final ValueChanged<Map<String, dynamic>> onOpenMovement;

  String _keyOf(Map<String, dynamic> row) {
    final sap = _text(row['sourceId']);
    if (sap.isNotEmpty) return sap;
    return _text(row['id']);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 260,
          child: _SimpleList(
            title: 'Bankalar (${banks.length})',
            empty: 'Banka yok — ekleyin.',
            itemCount: banks.length,
            itemBuilder: (context, index) {
              final row = banks[index];
              return _DenseRow(
                index: index,
                title: _text(row['bankName'] ?? row['name']),
                subtitle: [
                  if (_text(row['branch']).isNotEmpty) _text(row['branch']),
                  if (_text(row['phone']).isNotEmpty) _text(row['phone']),
                ].where((p) => p.trim().isNotEmpty).join(' · '),
                trailing: AppBadge(
                  label: 'Aktif',
                  tone: AppBadgeTone.success,
                  dense: true,
                ),
                onEdit: () => onEditBank(row),
                onDelete: () => onDeleteBank(row),
              );
            },
          ),
        ),
        const Gap(10),
        Expanded(
          child: _SimpleList(
            title: 'Hesaplar (${accounts.length})',
            empty: 'Hesap yok.',
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final row = accounts[index];
              final active =
                  row['isActive'] != false && row['is_active'] != false;
              final selected = selectedAccountKey == _keyOf(row);
              final title = _text(row['label']).isEmpty
                  ? _text(row['name'])
                  : _text(row['label']);
              final balanceRaw = row['balance'] ?? row['current_balance'] ?? 0;
              final balance = balanceRaw is num
                  ? balanceRaw.toDouble()
                  : double.tryParse('$balanceRaw'.replaceAll(',', '.')) ?? 0;
              return Material(
                color: selected
                    ? AppTheme.primary.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: InkWell(
                  onTap: () => onSelectAccount(_keyOf(row)),
                  child: SizedBox(
                    width: double.infinity,
                    child: _DenseRow(
                      index: index,
                      title: title.isEmpty ? 'Hesap' : title,
                      subtitle:
                          '${_text(row['currency']).isEmpty ? 'TRY' : _text(row['currency'])} · bakiye ${_money(balance)}',
                      trailing: AppBadge(
                        label: active ? 'Açık' : 'Kapalı',
                        tone: active
                            ? AppBadgeTone.success
                            : AppBadgeTone.neutral,
                        dense: true,
                      ),
                      onEdit: () => onEditAccount(row),
                      onDelete: () => onDeleteAccount(row),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 2,
          child: _SimpleList(
            title: selectedAccountKey == null
                ? 'Hareketler'
                : 'Hareketler (${movements.length})',
            empty: selectedAccountKey == null
                ? 'Hesap seçin — hareketler burada görünür.'
                : 'Bu hesapta hareket yok.',
            itemCount: movements.length,
            itemBuilder: (context, index) {
              final row = movements[index];
              final amountRaw = row['amount'];
              final amount = amountRaw is num
                  ? amountRaw.toDouble()
                  : double.tryParse('$amountRaw'.replaceAll(',', '.')) ?? 0;
              final inbound = amount >= 0;
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => onOpenMovement(row),
                  child: SizedBox(
                    width: double.infinity,
                    child: _DenseRow(
                      index: index,
                      title:
                          '${inbound ? '+' : '−'}${_money(amount.abs())}  ${_text(row['currency'])}',
                      subtitle: [
                        _date(row['date']),
                        _text(row['evrakNo']),
                        _text(row['description']),
                      ].where((p) => p.trim().isNotEmpty).join(' · '),
                      trailing: AppBadge(
                        label: inbound ? 'Giriş' : 'Çıkış',
                        tone: inbound
                            ? AppBadgeTone.success
                            : AppBadgeTone.neutral,
                        dense: true,
                      ),
                      onEdit: () => onOpenMovement(row),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _KasaList extends StatelessWidget {
  const _KasaList({
    required this.items,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onEdit;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleList(
      title: 'Kasalar (${items.length})',
      empty: 'Kasa yok.',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final row = items[index];
        final active = row['isActive'] != false;
        return _DenseRow(
          index: index,
          title: _text(row['kasaAdi']),
          subtitle: 'Bakiye ${_money(row['balance'] as num? ?? row['current_balance'] as num? ?? 0)}',
          trailing: AppBadge(
            label: active ? 'Aktif' : 'Pasif',
            tone: active ? AppBadgeTone.success : AppBadgeTone.neutral,
            dense: true,
          ),
          onEdit: () => onEdit(row),
          onDelete: () => onDelete(row),
        );
      },
    );
  }
}

class _TransferList extends StatelessWidget {
  const _TransferList({required this.items, required this.onDelete});

  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleList(
      title: 'Son transferler (${items.length})',
      empty:
          'Transfer yok. “ERP’den Aktar” ile eski kayıtları alın veya yeni transfer ekleyin.',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final row = items[index];
        final type = _text(row['type']);
        final tone = switch (type) {
          'bank_bank' => AppBadgeTone.primary,
          'kasa_bank' => AppBadgeTone.warning,
          'bank_kasa' => AppBadgeTone.success,
          _ => AppBadgeTone.neutral,
        };
        return _DenseRow(
          index: index,
          title: '${_text(row['fromLabel'])} → ${_text(row['toLabel'])}',
          subtitle: [
            _date(row['date']),
            _text(row['evrakNo']),
            _money(row['amount'] as num? ?? 0),
            if ((row['masraf'] as num? ?? 0) > 0)
              'masraf ${_money(row['masraf'] as num)}',
          ].where((part) => part.toString().trim().isNotEmpty).join(' · '),
          trailing: AppBadge(
            label: _text(row['typeLabel']),
            tone: tone,
            dense: true,
          ),
          onDelete: () => onDelete(row),
        );
      },
    );
  }
}

class _MasrafList extends StatelessWidget {
  const _MasrafList({required this.items, required this.onDelete});

  final List<Map<String, dynamic>> items;
  final ValueChanged<Map<String, dynamic>> onDelete;

  @override
  Widget build(BuildContext context) {
    return _SimpleList(
      title: 'Masraf faturaları (${items.length})',
      empty:
          'Masraf yok. “ERP’den Aktar” ile eski kayıtları alın veya Bankalar’dan hareket ekleyin.',
      itemCount: items.length,
      itemBuilder: (context, index) {
        final row = items[index];
        final itemNames = ((row['items'] as List?) ?? const [])
            .whereType<Map>()
            .map((e) => _text(e['name']))
            .where((e) => e.isNotEmpty)
            .take(2)
            .join(', ');
        return _DenseRow(
          index: index,
          title: _text(row['faturaNo']),
          subtitle:
              '${_date(row['date'])} · ${_text(row['cariUnvan']).isEmpty ? 'Cari yok' : _text(row['cariUnvan'])} · ${_money(row['toplam'] as num? ?? 0)}${_text(row['payLabel']).isEmpty ? '' : ' · ${_text(row['payLabel'])}'}${itemNames.isEmpty ? '' : ' · $itemNames'}',
          trailing: const AppBadge(
            label: 'MSF',
            tone: AppBadgeTone.warning,
            dense: true,
          ),
          onDelete: () => onDelete(row),
        );
      },
    );
  }
}

class _SimpleList extends StatelessWidget {
  const _SimpleList({
    required this.title,
    required this.empty,
    required this.itemCount,
    required this.itemBuilder,
  });

  final String title;
  final String empty;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Divider(height: 1, color: AppTheme.border.withValues(alpha: 0.7)),
          Expanded(
            child: itemCount == 0
                ? Center(
                    child: Text(
                      empty,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  )
                : ListView.builder(
                    itemCount: itemCount,
                    itemBuilder: itemBuilder,
                  ),
          ),
        ],
      ),
    );
  }
}

class _DenseRow extends StatelessWidget {
  const _DenseRow({
    required this.index,
    required this.title,
    required this.subtitle,
    required this.trailing,
    this.onEdit,
    this.onDelete,
  });

  final int index;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final row = Container(
      color: AppDenseList.rowFill(index),
      padding: const EdgeInsets.symmetric(
        horizontal: AppDenseList.rowH,
        vertical: AppDenseList.rowV,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Gap(2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          trailing,
          if (onEdit != null)
            IconButton(
              tooltip: 'Düzenle',
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
              icon: const Icon(LucideIcons.pencil, size: 18),
            ),
          if (onDelete != null)
            IconButton(
              tooltip: 'Sil',
              visualDensity: VisualDensity.compact,
              onPressed: onDelete,
              icon: const Icon(LucideIcons.trash2, size: 18),
            ),
        ],
      ),
    );
    return row;
  }
}
