import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'invoice_model.dart';
import 'invoice_providers.dart';

class AccountsScreen extends ConsumerStatefulWidget {
  const AccountsScreen({super.key});

  @override
  ConsumerState<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends ConsumerState<AccountsScreen> {
  final _money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  String _filter = 'all'; // all, receivable, payable

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(accountBalancesProvider);

    return AppPageLayout(
      title: 'Cari Hesaplar',
      subtitle: 'Müşteri ve tedarikçi bakiyeleri',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(accountBalancesProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        children: [
          // Summary Cards
          balancesAsync.when(
            data: (balances) {
              final totalReceivable = balances
                  .where((b) => b.balance > 0)
                  .fold<double>(0, (sum, b) => sum + b.balance);
              final totalPayable = balances
                  .where((b) => b.balance < 0)
                  .fold<double>(0, (sum, b) => sum + b.balance.abs());
              final netBalance = totalReceivable - totalPayable;

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  children: [
                    Expanded(
                      child: _SummaryCard(
                        title: 'Toplam Alacak',
                        value: _money.format(totalReceivable),
                        color: AppTheme.success,
                        icon: Icons.arrow_upward_rounded,
                        onTap: () => setState(
                          () => _filter = _filter == 'receivable'
                              ? 'all'
                              : 'receivable',
                        ),
                        selected: _filter == 'receivable',
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Toplam Borç',
                        value: _money.format(totalPayable),
                        color: AppTheme.error,
                        icon: Icons.arrow_downward_rounded,
                        onTap: () => setState(
                          () => _filter = _filter == 'payable'
                              ? 'all'
                              : 'payable',
                        ),
                        selected: _filter == 'payable',
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: _SummaryCard(
                        title: 'Net Bakiye',
                        value: _money.format(netBalance),
                        color: netBalance >= 0
                            ? AppTheme.success
                            : AppTheme.error,
                        icon: Icons.account_balance_wallet_rounded,
                        onTap: () => setState(() => _filter = 'all'),
                        selected: _filter == 'all',
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          const Gap(16),
          // List
          Expanded(
            child: balancesAsync.when(
              data: (balances) {
                var filtered = balances;
                if (_filter == 'receivable') {
                  filtered = balances.where((b) => b.balance > 0).toList();
                } else if (_filter == 'payable') {
                  filtered = balances.where((b) => b.balance < 0).toList();
                }

                // Sort by absolute balance descending
                filtered.sort(
                  (a, b) => b.balance.abs().compareTo(a.balance.abs()),
                );

                if (filtered.isEmpty) {
                  return Center(
                    child: AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.account_balance_rounded,
                              size: 48,
                              color: const Color(0xFF94A3B8),
                            ),
                            const Gap(12),
                            Text(
                              'Cari hesap bulunmuyor',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  itemCount: filtered.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) {
                    final account = filtered[index];
                    return _AccountCard(
                      account: account,
                      money: _money,
                      onTap: () => _openAccountDetail(account),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(
                  'Cari hesaplar yüklenemedi',
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

  void _openAccountDetail(AccountBalance account) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => AccountDetailScreen(
          customerId: account.customerId,
          customerName: account.name,
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
    required this.onTap,
    required this.selected,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Container(
          decoration: selected
              ? BoxDecoration(
                  border: Border(bottom: BorderSide(color: color, width: 3)),
                )
              : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const Gap(10),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              Text(
                value,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({
    required this.account,
    required this.money,
    required this.onTap,
  });

  final AccountBalance account;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isReceivable = account.balance > 0;
    final isPayable = account.balance < 0;

    final (typeLabel, typeTone) = switch (account.accountType) {
      'customer' => ('Müşteri', AppBadgeTone.primary),
      'supplier' => ('Tedarikçi', AppBadgeTone.warning),
      'both' => ('Müşteri/Tedarikçi', AppBadgeTone.neutral),
      _ => ('Cari', AppBadgeTone.neutral),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isReceivable
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : isPayable
                    ? AppTheme.error.withValues(alpha: 0.1)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.business_rounded,
                color: isReceivable
                    ? AppTheme.success
                    : isPayable
                    ? AppTheme.error
                    : const Color(0xFF64748B),
                size: 22,
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(4),
                  AppBadge(label: typeLabel, tone: typeTone),
                ],
              ),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money.format(account.balance.abs()),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isReceivable
                        ? AppTheme.success
                        : isPayable
                        ? AppTheme.error
                        : null,
                  ),
                ),
                const Gap(2),
                Text(
                  isReceivable
                      ? 'Alacak'
                      : isPayable
                      ? 'Borç'
                      : 'Dengede',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
            const Gap(8),
            Icon(Icons.chevron_right_rounded, color: const Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

// Cari Hesap Detay Ekranı - Ekstre
class AccountDetailScreen extends ConsumerStatefulWidget {
  const AccountDetailScreen({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  final String customerId;
  final String customerName;

  @override
  ConsumerState<AccountDetailScreen> createState() =>
      _AccountDetailScreenState();
}

class _AccountDetailScreenState extends ConsumerState<AccountDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  final Set<String> _selectedInvoices = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(
      invoicesProvider(InvoiceFilter(customerId: widget.customerId)),
    );
    final transactionsAsync = ref.watch(
      transactionsProvider(TransactionFilter(customerId: widget.customerId)),
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(widget.customerName),
        actions: [
          IconButton(
            icon: const Icon(Icons.picture_as_pdf_rounded),
            tooltip: 'PDF Ekstre',
            onPressed: () => _exportStatement('pdf'),
          ),
          IconButton(
            icon: const Icon(Icons.table_chart_rounded),
            tooltip: 'Excel Ekstre',
            onPressed: () => _exportStatement('excel'),
          ),
          IconButton(
            icon: const Icon(Icons.email_rounded),
            tooltip: 'E-posta Gönder',
            onPressed: _sendStatement,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Açık Faturalar'),
            Tab(text: 'Tüm Faturalar'),
            Tab(text: 'İşlemler'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // Açık Faturalar
          _buildOpenInvoices(invoicesAsync),
          // Tüm Faturalar
          _buildAllInvoices(invoicesAsync),
          // İşlemler
          _buildTransactions(transactionsAsync),
        ],
      ),
      floatingActionButton: _selectedInvoices.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _exportSelectedStatement,
              icon: const Icon(Icons.description_rounded),
              label: Text('${_selectedInvoices.length} Fatura Seçili'),
            )
          : FloatingActionButton(
              tooltip: 'Tahsilat/Ödeme Ekle',
              onPressed: () => _addTransaction(context),
              child: const Icon(Icons.add_rounded),
            ),
    );
  }

  Widget _buildOpenInvoices(AsyncValue<List<Invoice>> invoicesAsync) {
    return invoicesAsync.when(
      data: (invoices) {
        final openInvoices = invoices
            .where((i) => i.status == 'open' || i.status == 'partial')
            .toList();
        if (openInvoices.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.check_circle_outline_rounded,
                  size: 64,
                  color: AppTheme.success,
                ),
                const Gap(12),
                Text(
                  'Açık fatura bulunmuyor',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ],
            ),
          );
        }

        final totalOpen = openInvoices.fold<double>(
          0,
          (sum, i) => sum + i.remainingAmount,
        );

        return Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: AppTheme.warning.withValues(alpha: 0.1),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, color: AppTheme.warning),
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Toplam Açık Tutar: ${_money.format(totalOpen)}',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: openInvoices.length,
                separatorBuilder: (context, index) => const Gap(10),
                itemBuilder: (context, index) {
                  final invoice = openInvoices[index];
                  return _InvoiceSelectCard(
                    invoice: invoice,
                    money: _money,
                    selected: _selectedInvoices.contains(invoice.id),
                    onTap: () => setState(() {
                      if (_selectedInvoices.contains(invoice.id)) {
                        _selectedInvoices.remove(invoice.id);
                      } else {
                        _selectedInvoices.add(invoice.id);
                      }
                    }),
                  );
                },
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Faturalar yüklenemedi')),
    );
  }

  Widget _buildAllInvoices(AsyncValue<List<Invoice>> invoicesAsync) {
    return invoicesAsync.when(
      data: (invoices) {
        if (invoices.isEmpty) {
          return const Center(child: Text('Fatura bulunmuyor'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: invoices.length,
          separatorBuilder: (context, index) => const Gap(10),
          itemBuilder: (context, index) {
            final invoice = invoices[index];
            return _InvoiceSelectCard(
              invoice: invoice,
              money: _money,
              selected: _selectedInvoices.contains(invoice.id),
              onTap: () => setState(() {
                if (_selectedInvoices.contains(invoice.id)) {
                  _selectedInvoices.remove(invoice.id);
                } else {
                  _selectedInvoices.add(invoice.id);
                }
              }),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Faturalar yüklenemedi')),
    );
  }

  Widget _buildTransactions(AsyncValue<List<Transaction>> transactionsAsync) {
    return transactionsAsync.when(
      data: (transactions) {
        if (transactions.isEmpty) {
          return const Center(child: Text('İşlem bulunmuyor'));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: transactions.length,
          separatorBuilder: (context, index) => const Gap(10),
          itemBuilder: (context, index) {
            final tx = transactions[index];
            final isCollection = tx.transactionType == 'collection';

            return AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: (isCollection ? AppTheme.success : AppTheme.error)
                          .withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isCollection
                          ? Icons.arrow_downward_rounded
                          : Icons.arrow_upward_rounded,
                      color: isCollection ? AppTheme.success : AppTheme.error,
                      size: 18,
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isCollection ? 'Tahsilat' : 'Ödeme',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        if (tx.invoiceNumber != null)
                          Text(
                            'Fatura: ${tx.invoiceNumber}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        Text(
                          DateFormat(
                            'd MMM y',
                            'tr_TR',
                          ).format(tx.transactionDate),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${isCollection ? '+' : '-'}${_money.format(tx.amount)}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isCollection ? AppTheme.success : AppTheme.error,
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('İşlemler yüklenemedi')),
    );
  }

  Future<void> _addTransaction(BuildContext context) async {
    String type = 'collection';
    final amountController = TextEditingController();
    String method = 'cash';

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Yeni İşlem'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'collection', label: Text('Tahsilat')),
                  ButtonSegment(value: 'payment', label: Text('Ödeme')),
                ],
                selected: {type},
                onSelectionChanged: (s) => setState(() => type = s.first),
              ),
              const Gap(16),
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Tutar'),
              ),
              const Gap(12),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                  DropdownMenuItem(value: 'bank', child: Text('Havale/EFT')),
                  DropdownMenuItem(value: 'pos', child: Text('POS')),
                  DropdownMenuItem(
                    value: 'credit_card',
                    child: Text('Kredi Kartı'),
                  ),
                  DropdownMenuItem(value: 'check', child: Text('Çek')),
                ],
                onChanged: (v) => setState(() => method = v ?? 'cash'),
                decoration: const InputDecoration(labelText: 'Ödeme Yöntemi'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result != true || !mounted) return;

    final amount =
        double.tryParse(amountController.text.replaceAll(',', '.')) ?? 0;
    if (amount <= 0) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client.from('transactions').insert({
        'customer_id': widget.customerId,
        'transaction_type': type,
        'amount': amount,
        'currency': 'TRY',
        'payment_method': method,
        'transaction_date': DateTime.now().toIso8601String().substring(0, 10),
        'created_by': client.auth.currentUser?.id,
      });

      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('İşlem kaydedildi')));
      ref.invalidate(
        transactionsProvider(TransactionFilter(customerId: widget.customerId)),
      );
      ref.invalidate(accountBalancesProvider);
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _exportStatement(String format) async {
    final invoices =
        ref
            .read(
              invoicesProvider(InvoiceFilter(customerId: widget.customerId)),
            )
            .value ??
        const <Invoice>[];
    final transactions =
        ref
            .read(
              transactionsProvider(
                TransactionFilter(customerId: widget.customerId),
              ),
            )
            .value ??
        const <Transaction>[];
    if (invoices.isEmpty && transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ekstre için veri bulunamadı.')),
      );
      return;
    }
    await _showStatementPreview(
      title: '${format.toUpperCase()} Ekstre Önizleme',
      text: _buildStatementText(
        invoices: invoices,
        transactions: transactions,
        onlySelected: false,
      ),
    );
  }

  Future<void> _sendStatement() async {
    final invoices =
        ref
            .read(
              invoicesProvider(InvoiceFilter(customerId: widget.customerId)),
            )
            .value ??
        const <Invoice>[];
    final transactions =
        ref
            .read(
              transactionsProvider(
                TransactionFilter(customerId: widget.customerId),
              ),
            )
            .value ??
        const <Transaction>[];
    if (invoices.isEmpty && transactions.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderilecek ekstre verisi yok.')),
      );
      return;
    }
    await _showStatementPreview(
      title: 'E-posta Ekstre İçeriği',
      text: _buildStatementText(
        invoices: invoices,
        transactions: transactions,
        onlySelected: false,
      ),
    );
  }

  Future<void> _exportSelectedStatement() async {
    final invoices =
        ref
            .read(
              invoicesProvider(InvoiceFilter(customerId: widget.customerId)),
            )
            .value ??
        const <Invoice>[];
    final transactions =
        ref
            .read(
              transactionsProvider(
                TransactionFilter(customerId: widget.customerId),
              ),
            )
            .value ??
        const <Transaction>[];
    if (_selectedInvoices.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Önce fatura seçin.')));
      return;
    }
    await _showStatementPreview(
      title: 'Seçili Açık Faturalar Ekstresi',
      text: _buildStatementText(
        invoices: invoices,
        transactions: transactions,
        onlySelected: true,
      ),
    );
  }

  String _buildStatementText({
    required List<Invoice> invoices,
    required List<Transaction> transactions,
    required bool onlySelected,
  }) {
    final filteredInvoices = onlySelected
        ? invoices
              .where((invoice) => _selectedInvoices.contains(invoice.id))
              .toList()
        : invoices;
    final totalOpen = filteredInvoices.fold<double>(
      0,
      (sum, invoice) => sum + invoice.remainingAmount,
    );
    final lines = <String>[
      'Cari: ${widget.customerName}',
      'Tarih: ${DateFormat('d MMMM y HH:mm', 'tr_TR').format(DateTime.now())}',
      '',
      'Açık Fatura Toplamı: ${_money.format(totalOpen)}',
      '',
      'Faturalar',
      for (final invoice in filteredInvoices)
        '- ${invoice.invoiceNumber} | ${DateFormat('d MMM y', 'tr_TR').format(invoice.invoiceDate)} | ${invoice.status} | Kalan: ${_money.format(invoice.remainingAmount)}',
      '',
      'İşlemler',
      for (final tx in transactions)
        '- ${DateFormat('d MMM y', 'tr_TR').format(tx.transactionDate)} | ${tx.transactionType == 'collection' ? 'Tahsilat' : 'Ödeme'} | ${_money.format(tx.amount)}${tx.invoiceNumber != null ? ' | ${tx.invoiceNumber}' : ''}${tx.description?.trim().isNotEmpty ?? false ? ' | ${tx.description}' : ''}',
    ];
    return lines.join('\n');
  }

  Future<void> _showStatementPreview({
    required String title,
    required String text,
  }) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(child: SelectableText(text)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Kapat'),
          ),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!context.mounted) return;
              Navigator.of(context).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Ekstre panoya kopyalandı.')),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Kopyala'),
          ),
        ],
      ),
    );
  }
}

class _InvoiceSelectCard extends StatelessWidget {
  const _InvoiceSelectCard({
    required this.invoice,
    required this.money,
    required this.selected,
    required this.onTap,
  });

  final Invoice invoice;
  final NumberFormat money;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusColor) = switch (invoice.status) {
      'open' => ('Açık', AppTheme.warning),
      'partial' => ('Kısmi', AppTheme.primary),
      'paid' => ('Ödendi', AppTheme.success),
      'cancelled' => ('İptal', AppTheme.error),
      _ => ('?', const Color(0xFF64748B)),
    };

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      onLongPress: onTap,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Checkbox(value: selected, onChanged: (_) => onTap()),
            const Gap(8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        invoice.invoiceNumber,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          statusLabel,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: statusColor,
                                fontWeight: FontWeight.w500,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    DateFormat('d MMM y', 'tr_TR').format(invoice.invoiceDate),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money.format(invoice.grandTotal),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                ),
                if (invoice.remainingAmount > 0 && invoice.status != 'paid')
                  Text(
                    'Kalan: ${money.format(invoice.remainingAmount)}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
