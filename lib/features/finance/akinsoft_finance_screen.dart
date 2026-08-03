import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';

Uri _akinsoftFinanceUri(String path) {
  final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _pull());
  }

  @override
  void didUpdateWidget(covariant AkinsoftFinanceScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.section != widget.section) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _pull());
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
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw Exception('Geçersiz Akınsoft yanıtı.');
    }
    if (response.statusCode >= 400 || decoded['ok'] != true) {
      throw Exception(
        _text(decoded['error']).isEmpty
            ? 'Akınsoft işlem hatası (${response.statusCode})'
            : _text(decoded['error']),
      );
    }
    return decoded;
  }

  Future<void> _pull() async {
    setState(() {
      _loading = true;
      _error = null;
      _status = 'Akınsoft finans verileri çekiliyor…';
    });
    try {
      final data = await _post('finance/pull');
      if (!mounted) return;
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
        _pulledAt = DateTime.tryParse(_text(data['pulledAt']));
        _status =
            'Senkron: ${_banks.length} banka, ${_accounts.length} hesap, ${_kasas.length} kasa';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _status = null;
      });
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
      _status = 'Akınsoft’a yazılıyor…';
    });
    try {
      await _post(path, body);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
      await _pull();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
        _status = null;
      });
    }
  }

  String get _title {
    switch (widget.section) {
      case 'kasa':
        return 'Akınsoft Kasa';
      case 'transferler':
        return 'Akınsoft Transferler';
      case 'masraf':
        return 'Akınsoft Masraf Faturaları';
      case 'bankalar':
      default:
        return 'Akınsoft Bankalar / Hesaplar';
    }
  }

  String get _subtitle {
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
        return 'BANKA_ADI + BANKA_HESAP — $when';
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
          onPressed: _loading ? null : _pull,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          label: const Text('Akınsoft’tan Çek'),
        ),
        if (widget.section == 'bankalar')
          FilledButton.icon(
            onPressed: _loading ? null : () => _showBankDialog(),
            icon: const Icon(LucideIcons.plus, size: 18),
            label: const Text('Banka'),
          ),
        if (widget.section == 'bankalar')
          FilledButton.tonalIcon(
            onPressed: _loading || _banks.isEmpty
                ? null
                : () => _showAccountDialog(),
            icon: const Icon(LucideIcons.walletCards, size: 18),
            label: const Text('Hesap'),
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
          items: _kasas,
          onEdit: (row) => _showKasaDialog(existing: row),
          onDelete: (row) => _mutate(
            'finance/kasa',
            {'action': 'delete', 'sourceId': row['sourceId']},
            successMessage: 'Kasa Akınsoft’ta silindi/pasife alındı.',
          ),
        );
      case 'transferler':
        return _TransferList(
          items: _transfers,
          onDelete: (row) => _mutate(
            'finance/transfer',
            {
              'action': 'delete',
              'type': row['type'],
              'sourceId': row['sourceId'],
              'pairSourceId': row['pairSourceId'],
            },
            successMessage: 'Transfer Akınsoft’ta silindi (SILINDI=1).',
          ),
        );
      case 'masraf':
        return _MasrafList(
          items: _masraf,
          onDelete: (row) => _mutate(
            'finance/masraf',
            {'action': 'delete', 'sourceId': row['sourceId']},
            successMessage: 'Masraf faturası Akınsoft’ta silindi.',
          ),
        );
      case 'bankalar':
      default:
        return _BanksAccountsPane(
          banks: _banks,
          accounts: _accounts,
          onEditBank: (row) => _showBankDialog(existing: row),
          onDeleteBank: (row) => _mutate('finance/bank', {
            'action': 'delete',
            'sourceId': row['sourceId'],
          }, successMessage: 'Banka Akınsoft’tan silindi.'),
          onEditAccount: (row) => _showAccountDialog(existing: row),
          onDeleteAccount: (row) => _mutate(
            'finance/bank-account',
            {'action': 'delete', 'sourceId': row['sourceId']},
            successMessage: 'Hesap silindi veya kapatıldı.',
          ),
        );
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
      successMessage: existing == null
          ? 'Banka Akınsoft’a eklendi.'
          : 'Banka Akınsoft’ta güncellendi.',
    );
  }

  Future<void> _showAccountDialog({Map<String, dynamic>? existing}) async {
    String? bankId = _text(existing?['bankSourceId']).isEmpty
        ? (_banks.isEmpty ? null : _text(_banks.first['sourceId']))
        : _text(existing?['bankSourceId']);
    final tanimCtrl = TextEditingController(text: _text(existing?['tanimi']));
    final hesapCtrl = TextEditingController(text: _text(existing?['hesapNo']));
    final ibanCtrl = TextEditingController(text: _text(existing?['iban']));
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
                    for (final bank in _banks)
                      DropdownMenuItem(
                        value: _text(bank['sourceId']),
                        child: Text(_text(bank['bankName'])),
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
    await _mutate(
      'finance/bank-account',
      {
        if (existing != null) 'sourceId': existing['sourceId'],
        'bankSourceId': bankId,
        'tanimi': tanimCtrl.text.trim(),
        'hesapNo': hesapCtrl.text.trim(),
        'currency': currency,
        'iban': ibanCtrl.text.trim(),
      },
      successMessage: existing == null
          ? 'Hesap Akınsoft’a eklendi.'
          : 'Hesap Akınsoft’ta güncellendi.',
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
      successMessage: existing == null
          ? 'Kasa Akınsoft’a eklendi.'
          : 'Kasa Akınsoft’ta güncellendi.',
    );
  }

  Map<String, dynamic>? _accountById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final a in _accounts) {
      if (_text(a['sourceId']) == id) return a;
    }
    return null;
  }

  Future<void> _showTransferDialog() async {
    String type = 'bank_bank';
    String? fromAccount = _accounts.isEmpty
        ? null
        : _text(_accounts.first['sourceId']);
    String? toAccount = _accounts.length > 1
        ? _text(_accounts[1]['sourceId'])
        : fromAccount;
    String? accountId = fromAccount;
    String? kasaAdi = _kasas.isEmpty ? null : _text(_kasas.first['kasaAdi']);
    DateTime date = DateTime.now();
    final amountCtrl = TextEditingController();
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
            title: const Text('Akınsoft Transfer'),
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
                          for (final a in _accounts)
                            DropdownMenuItem(
                              value: _text(a['sourceId']),
                              child: Text(_text(a['label'])),
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
                          for (final a in _accounts)
                            DropdownMenuItem(
                              value: _text(a['sourceId']),
                              child: Text(_text(a['label'])),
                            ),
                        ],
                        onChanged: (v) => setLocal(() => toAccount = v),
                      ),
                    ] else ...[
                      DropdownButtonFormField<String>(
                        initialValue: kasaAdi,
                        decoration: const InputDecoration(labelText: 'Kasa *'),
                        items: [
                          for (final k in _kasas)
                            DropdownMenuItem(
                              value: _text(k['kasaAdi']),
                              child: Text(_text(k['kasaAdi'])),
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
                          for (final a in _accounts)
                            DropdownMenuItem(
                              value: _text(a['sourceId']),
                              child: Text(_text(a['label'])),
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
                        helperText: 'Wolvox BANKAHR / KASAHR çift kayıt yazar',
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
                child: const Text('Akınsoft’a Yaz'),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final amount =
        double.tryParse(amountCtrl.text.trim().replaceAll(',', '.')) ?? 0;
    final payload = <String, dynamic>{
      'type': type,
      'amount': amount,
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
      successMessage: 'Transfer Akınsoft’a yazıldı.',
    );
  }

  Future<void> _showMasrafDialog() async {
    DateTime date = DateTime.now();
    final cariCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final lines = <_MasrafLineDraft>[_MasrafLineDraft()];
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
            title: const Text('Akınsoft Masraf Faturası'),
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
                      'FATURA_DURUMU=7, FATURA_NO=MSF… olarak Wolvox’a yazılır',
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
                child: const Text('Akınsoft’a Yaz'),
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
    await _mutate(
      'finance/masraf',
      {
        'cariUnvan': cariCtrl.text.trim(),
        'description': descCtrl.text.trim(),
        'date': date.toIso8601String(),
        'items': items,
      },
      successMessage: 'Masraf faturası Akınsoft’a yazıldı (MSF).',
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

  double get qty =>
      double.tryParse(qtyCtrl.text.trim().replaceAll(',', '.')) ?? 0;
  double get unitPrice =>
      double.tryParse(priceCtrl.text.trim().replaceAll(',', '.')) ?? 0;
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
    required this.onEditBank,
    required this.onDeleteBank,
    required this.onEditAccount,
    required this.onDeleteAccount,
  });

  final List<Map<String, dynamic>> banks;
  final List<Map<String, dynamic>> accounts;
  final ValueChanged<Map<String, dynamic>> onEditBank;
  final ValueChanged<Map<String, dynamic>> onDeleteBank;
  final ValueChanged<Map<String, dynamic>> onEditAccount;
  final ValueChanged<Map<String, dynamic>> onDeleteAccount;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 320,
          child: _SimpleList(
            title: 'Bankalar (${banks.length})',
            empty: 'Banka yok — Akınsoft’tan çekin.',
            itemCount: banks.length,
            itemBuilder: (context, index) {
              final row = banks[index];
              return _DenseRow(
                index: index,
                title: _text(row['bankName']),
                subtitle: [
                  if (_text(row['branch']).isNotEmpty) _text(row['branch']),
                  'BLKODU ${_text(row['sourceId'])}',
                ].join(' · '),
                trailing: AppBadge(
                  label: 'ERP',
                  tone: AppBadgeTone.success,
                  dense: true,
                ),
                onEdit: () => onEditBank(row),
                onDelete: () => onDeleteBank(row),
              );
            },
          ),
        ),
        const Gap(12),
        Expanded(
          child: _SimpleList(
            title: 'Hesaplar (${accounts.length})',
            empty: 'Hesap yok.',
            itemCount: accounts.length,
            itemBuilder: (context, index) {
              final row = accounts[index];
              final active = row['isActive'] != false;
              return _DenseRow(
                index: index,
                title: _text(row['label']),
                subtitle:
                    '${_text(row['currency'])} · bakiye ${_money(row['balance'] as num? ?? 0)}',
                trailing: AppBadge(
                  label: active ? 'Açık' : 'Kapalı',
                  tone: active ? AppBadgeTone.success : AppBadgeTone.neutral,
                  dense: true,
                ),
                onEdit: () => onEditAccount(row),
                onDelete: () => onDeleteAccount(row),
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
          subtitle:
              'Bakiye ${_money(row['balance'] as num? ?? 0)} · BLKODU ${_text(row['sourceId'])}',
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
      empty: 'Transfer yok.',
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
          subtitle:
              '${_date(row['date'])} · ${_text(row['evrakNo'])} · ${_money(row['amount'] as num? ?? 0)}',
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
      empty: 'Masraf faturası yok.',
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
              '${_date(row['date'])} · ${_text(row['cariUnvan']).isEmpty ? 'Cari yok' : _text(row['cariUnvan'])} · ${_money(row['toplam'] as num? ?? 0)}${itemNames.isEmpty ? '' : ' · $itemNames'}',
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
    return Container(
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
  }
}
