import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/app_date_time.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_page_layout.dart';

double _num(dynamic value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0;
}

String _text(dynamic value) => value?.toString().trim() ?? '';

String _date(DateTime date) => date.toIso8601String().substring(0, 10);

String _money(double value, String currency) {
  final sign = value < 0 ? '-' : '';
  final raw = value.abs().toStringAsFixed(2).replaceAll('.', ',');
  return '$sign$currency $raw';
}

class FinanceAccount {
  const FinanceAccount({
    required this.id,
    required this.name,
    required this.accountType,
    required this.currency,
    required this.currentBalance,
    required this.openingBalance,
    required this.isActive,
    this.bankName,
    this.iban,
    this.posEnabled = false,
    this.notes,
  });

  final String id;
  final String name;
  final String accountType;
  final String currency;
  final double currentBalance;
  final double openingBalance;
  final bool isActive;
  final String? bankName;
  final String? iban;
  final bool posEnabled;
  final String? notes;

  factory FinanceAccount.fromJson(Map<String, dynamic> json) {
    return FinanceAccount(
      id: _text(json['id']),
      name: _text(json['name']),
      accountType: _text(json['account_type']).isEmpty
          ? 'bank'
          : _text(json['account_type']),
      currency: _text(json['currency']).isEmpty ? 'TRY' : _text(json['currency']),
      currentBalance: _num(json['current_balance']),
      openingBalance: _num(json['opening_balance']),
      isActive: json['is_active'] != false,
      bankName: _text(json['bank_name']).isEmpty ? null : _text(json['bank_name']),
      iban: _text(json['iban']).isEmpty ? null : _text(json['iban']),
      posEnabled: json['pos_enabled'] == true,
      notes: _text(json['notes']).isEmpty ? null : _text(json['notes']),
    );
  }
}

class FinanceTransaction {
  const FinanceTransaction({
    required this.id,
    required this.accountId,
    required this.accountName,
    required this.date,
    required this.direction,
    required this.transactionType,
    required this.paymentMethod,
    required this.amount,
    required this.currency,
    required this.isActive,
    this.customerName,
    this.invoiceNumber,
    this.description,
    this.referenceNo,
  });

  final String id;
  final String accountId;
  final String accountName;
  final DateTime date;
  final String direction;
  final String transactionType;
  final String paymentMethod;
  final double amount;
  final String currency;
  final bool isActive;
  final String? customerName;
  final String? invoiceNumber;
  final String? description;
  final String? referenceNo;

  factory FinanceTransaction.fromJson(Map<String, dynamic> json) {
    final account = json['finance_accounts'] as Map<String, dynamic>?;
    final customer = json['customers'] as Map<String, dynamic>?;
    final invoice = json['invoices'] as Map<String, dynamic>?;
    return FinanceTransaction(
      id: _text(json['id']),
      accountId: _text(json['account_id']),
      accountName: _text(account?['name']).isEmpty
          ? 'Hesap'
          : _text(account?['name']),
      date: parseAppDateTime(_text(json['transaction_date'])) ?? appNow(),
      direction: _text(json['direction']).isEmpty ? 'in' : _text(json['direction']),
      transactionType: _text(json['transaction_type']).isEmpty
          ? 'collection'
          : _text(json['transaction_type']),
      paymentMethod: _text(json['payment_method']).isEmpty
          ? 'bank'
          : _text(json['payment_method']),
      amount: _num(json['amount']),
      currency: _text(json['currency']).isEmpty ? 'TRY' : _text(json['currency']),
      isActive: json['is_active'] != false,
      customerName: _text(customer?['name']).isEmpty ? null : _text(customer?['name']),
      invoiceNumber: _text(invoice?['invoice_number']).isEmpty
          ? null
          : _text(invoice?['invoice_number']),
      description: _text(json['description']).isEmpty ? null : _text(json['description']),
      referenceNo: _text(json['reference_no']).isEmpty ? null : _text(json['reference_no']),
    );
  }
}

class FinanceFilter {
  const FinanceFilter({
    this.accountId,
    this.direction,
    this.transactionType,
    this.startDate,
    this.endDate,
  });

  final String? accountId;
  final String? direction;
  final String? transactionType;
  final DateTime? startDate;
  final DateTime? endDate;

  FinanceFilter copyWith({
    String? accountId,
    String? direction,
    String? transactionType,
    DateTime? startDate,
    DateTime? endDate,
    bool clearAccount = false,
    bool clearDirection = false,
    bool clearType = false,
    bool clearStart = false,
    bool clearEnd = false,
  }) {
    return FinanceFilter(
      accountId: clearAccount ? null : accountId ?? this.accountId,
      direction: clearDirection ? null : direction ?? this.direction,
      transactionType: clearType ? null : transactionType ?? this.transactionType,
      startDate: clearStart ? null : startDate ?? this.startDate,
      endDate: clearEnd ? null : endDate ?? this.endDate,
    );
  }
}

final financeAccountsProvider =
    FutureProvider.autoDispose<List<FinanceAccount>>((ref) async {
  final api = ref.read(apiClientProvider);
  if (api == null) return const [];
  final response = await api.getJson(
    '/data',
    queryParameters: {'resource': 'finance_accounts'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(FinanceAccount.fromJson)
      .toList(growable: false);
});

class FinanceFilterNotifier extends Notifier<FinanceFilter> {
  @override
  FinanceFilter build() => const FinanceFilter();

  void set(FinanceFilter value) => state = value;
}

final financeFilterProvider =
    NotifierProvider<FinanceFilterNotifier, FinanceFilter>(
      FinanceFilterNotifier.new,
    );

final financeTransactionsProvider =
    FutureProvider.autoDispose<List<FinanceTransaction>>((ref) async {
  final api = ref.read(apiClientProvider);
  final filter = ref.watch(financeFilterProvider);
  if (api == null) return const [];
  final response = await api.getJson(
    '/data',
    queryParameters: {
      'resource': 'finance_transactions',
      if (filter.accountId != null) 'accountId': filter.accountId!,
      if (filter.direction != null) 'direction': filter.direction!,
      if (filter.transactionType != null) 'transactionType': filter.transactionType!,
      if (filter.startDate != null) 'startDate': _date(filter.startDate!),
      if (filter.endDate != null) 'endDate': _date(filter.endDate!),
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(FinanceTransaction.fromJson)
      .toList(growable: false);
});

class FinanceScreen extends ConsumerWidget {
  const FinanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountsAsync = ref.watch(financeAccountsProvider);
    final transactionsAsync = ref.watch(financeTransactionsProvider);

    return AppPageLayout(
      title: 'Finans',
      subtitle: 'Banka, kasa, POS ve ödeme hareketleri.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(financeAccountsProvider);
            ref.invalidate(financeTransactionsProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: () => _showAccountDialog(context, ref),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Hesap Ekle'),
        ),
        FilledButton.tonalIcon(
          onPressed: () => _showTransactionDialog(context, ref),
          icon: const Icon(Icons.payments_rounded, size: 18),
          label: const Text('Hareket Ekle'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          accountsAsync.when(
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, _) => _ErrorBox(message: 'Finans hesapları yüklenemedi: $error'),
            data: (accounts) => _FinanceSummary(accounts: accounts),
          ),
          const Gap(12),
          accountsAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (_, _) => const SizedBox.shrink(),
            data: (accounts) => _FinanceFilters(accounts: accounts),
          ),
          const Gap(12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  width: 390,
                  child: accountsAsync.when(
                    loading: () => const _LoadingCard(),
                    error: (error, _) => _ErrorBox(message: '$error'),
                    data: (accounts) => _AccountsPanel(
                      accounts: accounts,
                      onEdit: (account) => _showAccountDialog(context, ref, account: account),
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: transactionsAsync.when(
                    loading: () => const _LoadingCard(),
                    error: (error, _) => _ErrorBox(message: '$error'),
                    data: (transactions) => _TransactionsPanel(
                      transactions: transactions,
                      onEdit: (tx) => _showTransactionDialog(context, ref, transaction: tx),
                    ),
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

class _FinanceSummary extends StatelessWidget {
  const _FinanceSummary({required this.accounts});

  final List<FinanceAccount> accounts;

  @override
  Widget build(BuildContext context) {
    final active = accounts.where((a) => a.isActive).toList();
    final bank = active.where((a) => a.accountType == 'bank').length;
    final cash = active.where((a) => a.accountType == 'cash').length;
    final pos = active.where((a) => a.posEnabled || a.accountType == 'pos').length;
    final tryTotal = active
        .where((a) => a.currency == 'TRY')
        .fold<double>(0, (sum, a) => sum + a.currentBalance);

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryCard(label: 'Banka', value: bank.toString(), icon: Icons.account_balance_rounded),
        _SummaryCard(label: 'Kasa', value: cash.toString(), icon: Icons.point_of_sale_rounded),
        _SummaryCard(label: 'POS', value: pos.toString(), icon: Icons.credit_card_rounded),
        _SummaryCard(label: 'TRY Bakiye', value: _money(tryTotal, 'TRY'), icon: Icons.savings_rounded),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          _IconBox(icon: icon, color: AppTheme.primary),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Theme.of(context).textTheme.bodySmall),
                Text(value, style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FinanceFilters extends ConsumerWidget {
  const _FinanceFilters({required this.accounts});

  final List<FinanceAccount> accounts;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(financeFilterProvider);
    void set(FinanceFilter next) =>
        ref.read(financeFilterProvider.notifier).set(next);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 250,
            child: DropdownButtonFormField<String>(
              initialValue: filter.accountId,
              decoration: const InputDecoration(
                labelText: 'Hesap',
                prefixIcon: Icon(Icons.account_balance_wallet_rounded),
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Tüm Hesaplar')),
                for (final account in accounts)
                  DropdownMenuItem(value: account.id, child: Text(account.name)),
              ],
              onChanged: (value) => set(filter.copyWith(accountId: value, clearAccount: value == null)),
            ),
          ),
          SizedBox(
            width: 190,
            child: DropdownButtonFormField<String>(
              initialValue: filter.direction,
              decoration: const InputDecoration(labelText: 'Giriş / Çıkış'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tümü')),
                DropdownMenuItem(value: 'in', child: Text('Giriş')),
                DropdownMenuItem(value: 'out', child: Text('Çıkış')),
              ],
              onChanged: (value) => set(filter.copyWith(direction: value, clearDirection: value == null)),
            ),
          ),
          SizedBox(
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: filter.transactionType,
              decoration: const InputDecoration(labelText: 'İşlem Tipi'),
              items: const [
                DropdownMenuItem(value: null, child: Text('Tümü')),
                DropdownMenuItem(value: 'collection', child: Text('Tahsilat')),
                DropdownMenuItem(value: 'payment', child: Text('Ödeme')),
                DropdownMenuItem(value: 'pos', child: Text('POS Çekim')),
                DropdownMenuItem(value: 'transfer', child: Text('Virman')),
                DropdownMenuItem(value: 'expense', child: Text('Gider')),
              ],
              onChanged: (value) => set(filter.copyWith(transactionType: value, clearType: value == null)),
            ),
          ),
          OutlinedButton.icon(
            onPressed: () => set(const FinanceFilter()),
            icon: const Icon(Icons.cleaning_services_rounded, size: 18),
            label: const Text('Temizle'),
          ),
        ],
      ),
    );
  }
}

class _AccountsPanel extends StatelessWidget {
  const _AccountsPanel({required this.accounts, required this.onEdit});

  final List<FinanceAccount> accounts;
  final ValueChanged<FinanceAccount> onEdit;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Hesaplar',
      child: accounts.isEmpty
          ? const Center(child: Text('Banka veya kasa hesabı ekleyin.'))
          : ListView.separated(
              padding: const EdgeInsets.all(10),
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const Gap(8),
              itemBuilder: (context, index) {
                final account = accounts[index];
                return InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                  onTap: () => onEdit(account),
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMuted,
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        _IconBox(
                          icon: _accountIcon(account.accountType),
                          color: account.isActive ? AppTheme.accent : AppTheme.textMuted,
                        ),
                        const Gap(10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(account.name, style: Theme.of(context).textTheme.titleSmall),
                              Text(
                                [
                                  _accountTypeLabel(account.accountType),
                                  if (account.bankName != null) account.bankName!,
                                  account.currency,
                                ].join(' • '),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              _money(account.currentBalance, account.currency),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            AppBadge(
                              label: account.isActive ? 'Aktif' : 'Pasif',
                              tone: account.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
                              dense: true,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}

class _TransactionsPanel extends StatelessWidget {
  const _TransactionsPanel({required this.transactions, required this.onEdit});

  final List<FinanceTransaction> transactions;
  final ValueChanged<FinanceTransaction> onEdit;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Hareket Dökümü',
      child: transactions.isEmpty
          ? const Center(child: Text('Filtreye uygun hareket yok.'))
          : Column(
              children: [
                Container(
                  height: 44,
                  color: const Color(0xFFEFF6FF),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: const Row(
                    children: [
                      Expanded(flex: 3, child: _Header('Tarih / Açıklama')),
                      Expanded(flex: 2, child: _Header('Hesap')),
                      Expanded(flex: 2, child: _Header('Cari')),
                      Expanded(child: _Header('Tip')),
                      Expanded(child: _Header('Tutar')),
                      SizedBox(width: 52),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    itemCount: transactions.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final tx = transactions[index];
                      final isIn = tx.direction == 'in';
                      return Container(
                        height: 68,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Row(
                                children: [
                                  _IconBox(
                                    icon: isIn ? Icons.south_west_rounded : Icons.north_east_rounded,
                                    color: isIn ? AppTheme.success : AppTheme.error,
                                    small: true,
                                  ),
                                  const Gap(10),
                                  Expanded(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          tx.description ?? _typeLabel(tx.transactionType),
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.titleSmall,
                                        ),
                                        Text('${_date(tx.date)}${tx.referenceNo == null ? '' : ' • ${tx.referenceNo}'}'),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(flex: 2, child: Text(tx.accountName, overflow: TextOverflow.ellipsis)),
                            Expanded(flex: 2, child: Text(tx.customerName ?? '-', overflow: TextOverflow.ellipsis)),
                            Expanded(child: AppBadge(label: _typeLabel(tx.transactionType), tone: AppBadgeTone.primary, dense: true)),
                            Expanded(
                              child: Text(
                                _money(isIn ? tx.amount : -tx.amount, tx.currency),
                                textAlign: TextAlign.right,
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      color: isIn ? AppTheme.success : AppTheme.error,
                                    ),
                              ),
                            ),
                            SizedBox(
                              width: 52,
                              child: IconButton(
                                tooltip: 'Düzenle',
                                onPressed: () => onEdit(tx),
                                icon: const Icon(Icons.edit_rounded),
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
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          const Divider(height: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.titleSmall);
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox({required this.icon, required this.color, this.small = false});

  final IconData icon;
  final Color color;
  final bool small;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: small ? 36 : 44,
      height: small ? 36 : 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Icon(icon, color: color, size: small ? 18 : 22),
    );
  }
}

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return const _Panel(
      title: 'Yükleniyor',
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.error.withValues(alpha: 0.16)),
      ),
      child: Text(message),
    );
  }
}

Future<void> _showAccountDialog(
  BuildContext context,
  WidgetRef ref, {
  FinanceAccount? account,
}) async {
  final name = TextEditingController(text: account?.name ?? '');
  final bankName = TextEditingController(text: account?.bankName ?? '');
  final iban = TextEditingController(text: account?.iban ?? '');
  final opening = TextEditingController(text: account?.openingBalance.toStringAsFixed(2) ?? '0');
  final notes = TextEditingController(text: account?.notes ?? '');
  var type = account?.accountType ?? 'bank';
  var currency = account?.currency ?? 'TRY';
  var posEnabled = account?.posEnabled ?? false;
  var isActive = account?.isActive ?? true;

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(account == null ? 'Hesap Ekle' : 'Hesap Düzenle'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: name, decoration: const InputDecoration(labelText: 'Hesap Adı')),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'Hesap Tipi'),
                        items: const [
                          DropdownMenuItem(value: 'bank', child: Text('Banka')),
                          DropdownMenuItem(value: 'cash', child: Text('Kasa')),
                          DropdownMenuItem(value: 'pos', child: Text('POS')),
                          DropdownMenuItem(value: 'other', child: Text('Diğer')),
                        ],
                        onChanged: (v) => setState(() => type = v ?? 'bank'),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: currency,
                        decoration: const InputDecoration(labelText: 'Para Birimi'),
                        items: const [
                          DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                          DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                          DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                        ],
                        onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                TextField(controller: bankName, decoration: const InputDecoration(labelText: 'Banka Adı / Şube')),
                const Gap(10),
                TextField(controller: iban, decoration: const InputDecoration(labelText: 'IBAN / Hesap No')),
                const Gap(10),
                TextField(
                  controller: opening,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Açılış Bakiyesi'),
                ),
                const Gap(10),
                SwitchListTile(
                  value: posEnabled,
                  onChanged: (v) => setState(() => posEnabled = v),
                  title: const Text('POS çekim hesabı'),
                  contentPadding: EdgeInsets.zero,
                ),
                SwitchListTile(
                  value: isActive,
                  onChanged: (v) => setState(() => isActive = v),
                  title: const Text('Aktif'),
                  contentPadding: EdgeInsets.zero,
                ),
                TextField(controller: notes, decoration: const InputDecoration(labelText: 'Not'), maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final api = ref.read(apiClientProvider);
              if (api == null) return;
              await api.postJson(
                '/mutate',
                body: {
                  'op': 'upsert',
                  'table': 'finance_accounts',
                  'values': {
                    if (account != null) 'id': account.id,
                    'name': name.text.trim(),
                    'account_type': type,
                    'bank_name': bankName.text.trim(),
                    'iban': iban.text.trim(),
                    'currency': currency,
                    'opening_balance': _num(opening.text),
                    'pos_enabled': posEnabled,
                    'is_active': isActive,
                    'notes': notes.text.trim(),
                  },
                },
              );
              ref.invalidate(financeAccountsProvider);
              ref.invalidate(financeTransactionsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}

Future<void> _showTransactionDialog(
  BuildContext context,
  WidgetRef ref, {
  FinanceTransaction? transaction,
}) async {
  final accounts = await ref.read(financeAccountsProvider.future);
  if (!context.mounted) return;
  if (accounts.isEmpty && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Önce banka veya kasa hesabı ekleyin.')),
    );
    return;
  }
  final amount = TextEditingController(text: transaction?.amount.toStringAsFixed(2) ?? '');
  final description = TextEditingController(text: transaction?.description ?? '');
  final reference = TextEditingController(text: transaction?.referenceNo ?? '');
  var accountId = transaction?.accountId ?? accounts.first.id;
  var account = accounts.firstWhere((a) => a.id == accountId, orElse: () => accounts.first);
  var direction = transaction?.direction ?? 'in';
  var type = transaction?.transactionType ?? 'collection';
  var method = transaction?.paymentMethod ?? (account.accountType == 'cash' ? 'cash' : 'bank');
  var date = transaction?.date ?? appNow();

  await showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setState) => AlertDialog(
        title: Text(transaction == null ? 'Hareket Ekle' : 'Hareket Düzenle'),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: accountId,
                  decoration: const InputDecoration(labelText: 'Banka / Kasa Hesabı'),
                  items: [
                    for (final item in accounts)
                      DropdownMenuItem(value: item.id, child: Text('${item.name} • ${item.currency}')),
                  ],
                  onChanged: (v) => setState(() {
                    accountId = v ?? accountId;
                    account = accounts.firstWhere((a) => a.id == accountId);
                    method = account.accountType == 'cash' ? 'cash' : method;
                  }),
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: direction,
                        decoration: const InputDecoration(labelText: 'Yön'),
                        items: const [
                          DropdownMenuItem(value: 'in', child: Text('Giriş')),
                          DropdownMenuItem(value: 'out', child: Text('Çıkış')),
                        ],
                        onChanged: (v) => setState(() => direction = v ?? 'in'),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: type,
                        decoration: const InputDecoration(labelText: 'İşlem Tipi'),
                        items: const [
                          DropdownMenuItem(value: 'collection', child: Text('Tahsilat')),
                          DropdownMenuItem(value: 'payment', child: Text('Ödeme')),
                          DropdownMenuItem(value: 'pos', child: Text('POS Çekim')),
                          DropdownMenuItem(value: 'transfer', child: Text('Virman')),
                          DropdownMenuItem(value: 'expense', child: Text('Gider')),
                        ],
                        onChanged: (v) => setState(() => type = v ?? 'collection'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: method,
                        decoration: const InputDecoration(labelText: 'Ödeme Şekli'),
                        items: const [
                          DropdownMenuItem(value: 'bank', child: Text('Banka')),
                          DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                          DropdownMenuItem(value: 'pos', child: Text('POS')),
                          DropdownMenuItem(value: 'cheque', child: Text('Çek')),
                          DropdownMenuItem(value: 'transfer', child: Text('Virman')),
                        ],
                        onChanged: (v) => setState(() => method = v ?? 'bank'),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextField(
                        controller: amount,
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(labelText: 'Tutar (${account.currency})'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.calendar_month_rounded),
                  title: Text(_date(date)),
                  trailing: const Icon(Icons.expand_more_rounded),
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: date,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2035),
                    );
                    if (picked != null) setState(() => date = picked);
                  },
                ),
                TextField(controller: reference, decoration: const InputDecoration(labelText: 'Fiş / Referans No')),
                const Gap(10),
                TextField(controller: description, decoration: const InputDecoration(labelText: 'Açıklama'), maxLines: 2),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
          FilledButton(
            onPressed: () async {
              final api = ref.read(apiClientProvider);
              if (api == null) return;
              await api.postJson(
                '/mutate',
                body: {
                  'op': 'upsert',
                  'table': 'finance_transactions',
                  'values': {
                    if (transaction != null) 'id': transaction.id,
                    'account_id': accountId,
                    'transaction_date': _date(date),
                    'direction': direction,
                    'transaction_type': type,
                    'payment_method': method,
                    'amount': _num(amount.text),
                    'currency': account.currency,
                    'description': description.text.trim(),
                    'reference_no': reference.text.trim(),
                    'source': 'manual',
                    'is_active': true,
                  },
                },
              );
              ref.invalidate(financeAccountsProvider);
              ref.invalidate(financeTransactionsProvider);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    ),
  );
}

IconData _accountIcon(String type) {
  return switch (type) {
    'cash' => Icons.point_of_sale_rounded,
    'pos' => Icons.credit_card_rounded,
    'other' => Icons.account_balance_wallet_rounded,
    _ => Icons.account_balance_rounded,
  };
}

String _accountTypeLabel(String type) {
  return switch (type) {
    'cash' => 'Kasa',
    'pos' => 'POS',
    'other' => 'Diğer',
    _ => 'Banka',
  };
}

String _typeLabel(String type) {
  return switch (type) {
    'payment' => 'Ödeme',
    'pos' => 'POS',
    'transfer' => 'Virman',
    'expense' => 'Gider',
    _ => 'Tahsilat',
  };
}
