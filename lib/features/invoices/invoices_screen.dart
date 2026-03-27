import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'invoice_model.dart';
import 'invoice_providers.dart';
import 'invoice_form_screen.dart';

class InvoicesScreen extends ConsumerStatefulWidget {
  const InvoicesScreen({super.key});

  @override
  ConsumerState<InvoicesScreen> createState() => _InvoicesScreenState();
}

class _InvoicesScreenState extends ConsumerState<InvoicesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  InvoiceFilter _filter = const InvoiceFilter();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        final type = _tabController.index == 0 ? 'sales' : 'purchase';
        setState(() {
          _filter = _filter.copyWith(invoiceType: type, clearStatus: true);
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentFilter = _filter.copyWith(
      invoiceType: _tabController.index == 0 ? 'sales' : 'purchase',
    );
    final invoicesAsync = ref.watch(invoicesProvider(currentFilter));

    return AppPageLayout(
      title: 'Faturalar',
      subtitle: 'Alış ve satış faturalarını yönetin',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(invoicesProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showInvoiceTypeDialog(context),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Fatura'),
        ),
      ],
      body: Column(
        children: [
          // Tab Bar
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: TabBar(
              controller: _tabController,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: 'Satış Faturaları'),
                Tab(text: 'Alış Faturaları'),
              ],
            ),
          ),
          const Gap(12),
          // Filters
          _FilterBar(
            filter: _filter,
            onFilterChanged: (newFilter) => setState(() => _filter = newFilter),
          ),
          const Gap(12),
          // List
          Expanded(
            child: invoicesAsync.when(
              data: (invoices) {
                if (invoices.isEmpty) {
                  return Center(
                    child: AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.receipt_long_rounded,
                              size: 48,
                              color: const Color(0xFF94A3B8),
                            ),
                            const Gap(12),
                            Text(
                              'Fatura bulunmuyor',
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
                  itemCount: invoices.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) {
                    final invoice = invoices[index];
                    return _InvoiceCard(
                      invoice: invoice,
                      money: _money,
                      onTap: () => _openInvoiceDetail(invoice),
                    );
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => Center(
                child: Text(
                  'Faturalar yüklenemedi',
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

  Future<void> _showInvoiceTypeDialog(BuildContext context) async {
    final type = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fatura Türü'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.success.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  color: AppTheme.success,
                ),
              ),
              title: const Text('Satış Faturası'),
              subtitle: const Text('Müşteriye kesilen fatura'),
              onTap: () => Navigator.pop(context, 'sales'),
            ),
            const Gap(8),
            ListTile(
              leading: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.error.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.arrow_downward_rounded,
                  color: AppTheme.error,
                ),
              ),
              title: const Text('Alış Faturası'),
              subtitle: const Text('Tedarikçiden alınan fatura'),
              onTap: () => Navigator.pop(context, 'purchase'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );

    if (type == null || !context.mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InvoiceFormScreen(invoiceType: type),
      ),
    );
    ref.invalidate(invoicesProvider);
  }

  void _openInvoiceDetail(Invoice invoice) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InvoiceDetailScreen(invoiceId: invoice.id),
      ),
    );
    if (!mounted) return;
    ref.invalidate(invoicesProvider);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.filter, required this.onFilterChanged});

  final InvoiceFilter filter;
  final ValueChanged<InvoiceFilter> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Row(
        children: [
          _FilterChip(
            label: filter.status == null
                ? 'Tüm Durumlar'
                : _statusLabel(filter.status!),
            selected: filter.status != null,
            onTap: () => _showStatusFilter(context),
          ),
          const Gap(8),
          _FilterChip(
            label: filter.customerId == null ? 'Tüm Cariler' : 'Seçili Cari',
            selected: filter.customerId != null,
            onTap: () => _showCustomerFilter(context),
          ),
          const Gap(8),
          _FilterChip(
            label: 'Tarih Aralığı',
            selected: filter.startDate != null || filter.endDate != null,
            onTap: () => _showDateFilter(context),
          ),
          if (filter.status != null ||
              filter.customerId != null ||
              filter.startDate != null) ...[
            const Gap(8),
            ActionChip(
              label: const Text('Temizle'),
              onPressed: () => onFilterChanged(const InvoiceFilter()),
            ),
          ],
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    return switch (status) {
      'draft' => 'Taslak',
      'open' => 'Açık',
      'partial' => 'Kısmi Ödendi',
      'paid' => 'Ödendi',
      'cancelled' => 'İptal',
      _ => status,
    };
  }

  Future<void> _showStatusFilter(BuildContext context) async {
    final status = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Tümü'),
              onTap: () => Navigator.pop(context, ''),
            ),
            ListTile(
              title: const Text('Açık'),
              onTap: () => Navigator.pop(context, 'open'),
            ),
            ListTile(
              title: const Text('Kısmi Ödendi'),
              onTap: () => Navigator.pop(context, 'partial'),
            ),
            ListTile(
              title: const Text('Ödendi'),
              onTap: () => Navigator.pop(context, 'paid'),
            ),
            ListTile(
              title: const Text('İptal'),
              onTap: () => Navigator.pop(context, 'cancelled'),
            ),
          ],
        ),
      ),
    );

    if (status == null) return;
    onFilterChanged(
      filter.copyWith(
        status: status.isEmpty ? null : status,
        clearStatus: status.isEmpty,
      ),
    );
  }

  Future<void> _showCustomerFilter(BuildContext context) async {
    // Simplified - no customer selection for now
    onFilterChanged(filter.copyWith(clearCustomerId: true));
  }

  Future<void> _showDateFilter(BuildContext context) async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: filter.startDate != null && filter.endDate != null
          ? DateTimeRange(start: filter.startDate!, end: filter.endDate!)
          : null,
    );

    if (range == null) return;
    onFilterChanged(
      filter.copyWith(startDate: range.start, endDate: range.end),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      label: Text(label),
      backgroundColor: selected
          ? AppTheme.primary.withValues(alpha: 0.1)
          : null,
      side: selected
          ? BorderSide(color: AppTheme.primary.withValues(alpha: 0.3))
          : null,
      onPressed: onTap,
    );
  }
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({
    required this.invoice,
    required this.money,
    required this.onTap,
  });

  final Invoice invoice;
  final NumberFormat money;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = switch (invoice.status) {
      'draft' => ('Taslak', AppBadgeTone.neutral),
      'open' => ('Açık', AppBadgeTone.warning),
      'partial' => ('Kısmi', AppBadgeTone.primary),
      'paid' => ('Ödendi', AppBadgeTone.success),
      'cancelled' => ('İptal', AppBadgeTone.error),
      _ => ('?', AppBadgeTone.neutral),
    };

    final dateText = DateFormat('d MMM y', 'tr_TR').format(invoice.invoiceDate);
    final currencySymbol = switch (invoice.currency) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '₺',
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
                color: invoice.invoiceType == 'sales'
                    ? AppTheme.success.withValues(alpha: 0.1)
                    : AppTheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                invoice.invoiceType == 'sales'
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                color: invoice.invoiceType == 'sales'
                    ? AppTheme.success
                    : AppTheme.error,
                size: 22,
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          invoice.invoiceNumber,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      AppBadge(label: statusLabel, tone: statusTone),
                    ],
                  ),
                  const Gap(4),
                  Text(
                    invoice.customerName ?? '-',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const Gap(2),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 12,
                        color: const Color(0xFF94A3B8),
                      ),
                      const Gap(4),
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const Gap(12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '$currencySymbol${money.format(invoice.grandTotal).replaceAll('₺', '').trim()}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (invoice.remainingAmount > 0 &&
                    invoice.status != 'paid') ...[
                  const Gap(2),
                  Text(
                    'Kalan: $currencySymbol${money.format(invoice.remainingAmount).replaceAll('₺', '').trim()}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: AppTheme.error),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Fatura Detay Ekranı
class InvoiceDetailScreen extends ConsumerStatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoiceId});

  final String invoiceId;

  @override
  ConsumerState<InvoiceDetailScreen> createState() =>
      _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends ConsumerState<InvoiceDetailScreen> {
  final _money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context) {
    final invoiceAsync = ref.watch(invoiceDetailProvider(widget.invoiceId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: const Text('Fatura Detayı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'Yazdır / PDF',
            onPressed: () => _exportPdf(context),
          ),
          IconButton(
            icon: const Icon(Icons.email_rounded),
            tooltip: 'E-posta Gönder',
            onPressed: () => _sendEmail(context),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => _handleMenuAction(value),
            itemBuilder: (context) => [
              const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              const PopupMenuItem(value: 'payment', child: Text('Ödeme Ekle')),
              const PopupMenuItem(value: 'cancel', child: Text('İptal Et')),
            ],
          ),
        ],
      ),
      body: invoiceAsync.when(
        data: (invoice) {
          if (invoice == null) {
            return const Center(child: Text('Fatura bulunamadı'));
          }
          return _buildDetail(context, invoice);
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Hata oluştu')),
      ),
    );
  }

  Widget _buildDetail(BuildContext context, Invoice invoice) {
    final currencySymbol = switch (invoice.currency) {
      'USD' => '\$',
      'EUR' => '€',
      'GBP' => '£',
      _ => '₺',
    };

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Header Card
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          invoice.invoiceNumber,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const Gap(4),
                        Text(
                          invoice.invoiceType == 'sales'
                              ? 'Satış Faturası'
                              : 'Alış Faturası',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  _StatusBadgeLarge(status: invoice.status),
                ],
              ),
              const Gap(16),
              const Divider(),
              const Gap(16),
              _InfoRow(label: 'Cari', value: invoice.customerName ?? '-'),
              const Gap(8),
              _InfoRow(
                label: 'Fatura Tarihi',
                value: DateFormat(
                  'd MMMM y',
                  'tr_TR',
                ).format(invoice.invoiceDate),
              ),
              if (invoice.dueDate != null) ...[
                const Gap(8),
                _InfoRow(
                  label: 'Vade Tarihi',
                  value: DateFormat(
                    'd MMMM y',
                    'tr_TR',
                  ).format(invoice.dueDate!),
                ),
              ],
              const Gap(8),
              _InfoRow(label: 'Para Birimi', value: invoice.currency),
            ],
          ),
        ),
        const Gap(16),
        // Items
        AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kalemler', style: Theme.of(context).textTheme.titleSmall),
              const Gap(12),
              if (invoice.items.isEmpty)
                Text(
                  'Kalem bulunmuyor',
                  style: Theme.of(context).textTheme.bodySmall,
                )
              else
                ...invoice.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.description,
                                style: Theme.of(context).textTheme.bodyMedium,
                              ),
                              Text(
                                '${item.quantity} ${item.unit} x $currencySymbol${_money.format(item.unitPrice).replaceAll('₺', '').trim()}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          flex: 1,
                          child: Text(
                            '$currencySymbol${_money.format(item.lineTotal).replaceAll('₺', '').trim()}',
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              const Gap(8),
              _TotalRow(
                label: 'Ara Toplam',
                value:
                    '$currencySymbol${_money.format(invoice.subtotal).replaceAll('₺', '').trim()}',
              ),
              _TotalRow(
                label: 'KDV Toplam',
                value:
                    '$currencySymbol${_money.format(invoice.taxTotal).replaceAll('₺', '').trim()}',
              ),
              if (invoice.discountTotal > 0)
                _TotalRow(
                  label: 'İndirim',
                  value:
                      '-$currencySymbol${_money.format(invoice.discountTotal).replaceAll('₺', '').trim()}',
                ),
              const Gap(8),
              _TotalRow(
                label: 'Genel Toplam',
                value:
                    '$currencySymbol${_money.format(invoice.grandTotal).replaceAll('₺', '').trim()}',
                isTotal: true,
              ),
              const Gap(8),
              _TotalRow(
                label: 'Ödenen',
                value:
                    '$currencySymbol${_money.format(invoice.paidAmount).replaceAll('₺', '').trim()}',
                color: AppTheme.success,
              ),
              _TotalRow(
                label: 'Kalan',
                value:
                    '$currencySymbol${_money.format(invoice.remainingAmount).replaceAll('₺', '').trim()}',
                color: invoice.remainingAmount > 0
                    ? AppTheme.error
                    : AppTheme.success,
              ),
            ],
          ),
        ),
        if (invoice.notes?.isNotEmpty ?? false) ...[
          const Gap(16),
          AppCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Notlar', style: Theme.of(context).textTheme.titleSmall),
                const Gap(8),
                Text(
                  invoice.notes!,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
        const Gap(16),
        // Payment Button
        if (invoice.status == 'open' || invoice.status == 'partial')
          FilledButton.icon(
            onPressed: () => _addPayment(context, invoice),
            icon: const Icon(Icons.payment_rounded),
            label: const Text('Ödeme / Tahsilat Ekle'),
          ),
      ],
    );
  }

  Future<void> _handleMenuAction(String action) async {
    switch (action) {
      case 'edit':
        final invoice = ref.read(invoiceDetailProvider(widget.invoiceId)).value;
        if (invoice == null) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => InvoiceFormScreen(
              invoiceType: invoice.invoiceType,
              editInvoice: invoice,
            ),
          ),
        );
        if (!mounted) return;
        ref.invalidate(invoiceDetailProvider(widget.invoiceId));
        ref.invalidate(invoicesProvider);
        break;
      case 'payment':
        final invoiceAsync = ref.read(invoiceDetailProvider(widget.invoiceId));
        final invoice = invoiceAsync.value;
        if (invoice != null) _addPayment(context, invoice);
        break;
      case 'cancel':
        _cancelInvoice();
        break;
    }
  }

  Future<void> _addPayment(BuildContext context, Invoice invoice) async {
    final amountController = TextEditingController(
      text: invoice.remainingAmount.toStringAsFixed(2),
    );
    String currency = invoice.currency;
    String method = 'cash';

    final messenger = ScaffoldMessenger.of(context);
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            invoice.invoiceType == 'sales' ? 'Tahsilat Ekle' : 'Ödeme Ekle',
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'Tutar'),
              ),
              const Gap(12),
              DropdownButtonFormField<String>(
                initialValue: currency,
                items: const [
                  DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  DropdownMenuItem(value: 'GBP', child: Text('GBP')),
                ],
                onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                decoration: const InputDecoration(labelText: 'Para Birimi'),
              ),
              const Gap(12),
              DropdownButtonFormField<String>(
                initialValue: method,
                items: const [
                  DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                  DropdownMenuItem(value: 'bank', child: Text('Havale/EFT')),
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
        'customer_id': invoice.customerId,
        'transaction_type': invoice.invoiceType == 'sales'
            ? 'collection'
            : 'payment',
        'amount': amount,
        'currency': currency,
        'payment_method': method,
        'invoice_id': invoice.id,
        'transaction_date': DateTime.now().toIso8601String().substring(0, 10),
        'created_by': client.auth.currentUser?.id,
      });

      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Ödeme kaydedildi')));
      ref.invalidate(invoiceDetailProvider(widget.invoiceId));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text('Hata: $e')));
    }
  }

  Future<void> _cancelInvoice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faturayı İptal Et'),
        content: const Text(
          'Bu faturayı iptal etmek istediğinizden emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppTheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client
          .from('invoices')
          .update({'status': 'cancelled'})
          .eq('id', widget.invoiceId);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Fatura iptal edildi')));
        ref.invalidate(invoiceDetailProvider(widget.invoiceId));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  void _exportPdf(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PDF oluşturma özelliği yakında eklenecek')),
    );
  }

  void _sendEmail(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('E-posta gönderme özelliği yakında eklenecek'),
      ),
    );
  }
}

class _StatusBadgeLarge extends StatelessWidget {
  const _StatusBadgeLarge({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'draft' => ('Taslak', const Color(0xFF64748B)),
      'open' => ('Açık', const Color(0xFFF59E0B)),
      'partial' => ('Kısmi Ödendi', AppTheme.primary),
      'paid' => ('Ödendi', AppTheme.success),
      'cancelled' => ('İptal', AppTheme.error),
      _ => ('?', const Color(0xFF64748B)),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 120,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
        ),
        Expanded(
          child: Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ),
      ],
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.isTotal = false,
    this.color,
  });

  final String label;
  final String value;
  final bool isTotal;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w500,
              color: color,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
