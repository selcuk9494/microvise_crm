import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_model.dart';
import '../customers/customers_providers.dart';
import '../definitions/definitions_screen.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import '../work_orders/currency_service.dart';
import 'e_invoice_screen.dart';

class EInvoiceFormScreen extends ConsumerStatefulWidget {
  const EInvoiceFormScreen({
    super.key,
    required this.invoiceType,
    this.initialInvoice,
  });

  final String invoiceType;
  final Invoice? initialInvoice;

  @override
  ConsumerState<EInvoiceFormScreen> createState() => _EInvoiceFormScreenState();
}

class _EInvoiceFormScreenState extends ConsumerState<EInvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _exchangeRateController = TextEditingController(text: '1');
  final _items = <_EInvoiceItemDraft>[_EInvoiceItemDraft()];

  String? _customerId;
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _currency = 'TRY';
  double _exchangeRate = 1;
  bool _saving = false;
  bool _sendAfterSave = false;
  Map<String, double> _rates = const {};

  bool get _isSales => widget.invoiceType == 'sales';
  bool get _isEditing => widget.initialInvoice != null;

  double get _subtotal => _items.fold(0, (sum, item) => sum + item.subtotal);
  double get _discountTotal =>
      _items.fold(0, (sum, item) => sum + item.discountAmount);
  double get _taxTotal => _items.fold(0, (sum, item) => sum + item.taxAmount);
  double get _grandTotal => _subtotal - _discountTotal + _taxTotal;

  @override
  void initState() {
    super.initState();
    final invoice = widget.initialInvoice;
    if (invoice != null) {
      _customerId = invoice.customerId;
      _invoiceDate = invoice.invoiceDate;
      _dueDate = invoice.dueDate;
      _currency = invoice.currency;
      _exchangeRate = invoice.exchangeRate;
      _exchangeRateController.text = invoice.exchangeRate.toStringAsFixed(
        invoice.currency == 'TRY' ? 0 : 4,
      );
      _notesController.text = invoice.notes ?? '';
      for (final item in _items) {
        item.dispose();
      }
      _items
        ..clear()
        ..addAll(
          invoice.items.isEmpty
              ? [_EInvoiceItemDraft()]
              : invoice.items.map(_EInvoiceItemDraft.fromInvoiceItem),
        );
    }
    _loadRates();
  }

  Future<void> _loadRates() async {
    final rates = await CurrencyService.getExchangeRates();
    if (!mounted) return;
    setState(() => _rates = rates);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _exchangeRateController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersLookupProvider);
    final productsAsync = ref.watch(productsProvider(null));
    final taxRatesAsync = ref.watch(taxRatesProvider);
    final title =
        '${_isEditing ? 'Düzenle - ' : ''}${_isSales ? 'Satış E-Faturası' : 'Alış Faturası'}';

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => _save(status: 'draft'),
            child: const Text('Taslak'),
          ),
          const Gap(8),
          FilledButton.icon(
            onPressed: _saving ? null : () => _save(status: 'open'),
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_rounded, size: 18),
            label: const Text('Kaydet'),
          ),
          const Gap(12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;
            final content = [
              _HeaderCard(isSales: _isSales),
              const Gap(12),
              _PartyCard(
                customersAsync: customersAsync,
                selectedCustomerId: _customerId,
                isSales: _isSales,
                onChanged: (value) => setState(() => _customerId = value),
              ),
              const Gap(12),
              _InvoiceInfoCard(
                invoiceDate: _invoiceDate,
                dueDate: _dueDate,
                currency: _currency,
                exchangeRateController: _exchangeRateController,
                onInvoiceDateChanged: (value) =>
                    setState(() => _invoiceDate = value),
                onDueDateChanged: (value) => setState(() => _dueDate = value),
                onCurrencyChanged: (value) {
                  setState(() {
                    _currency = value;
                    _exchangeRate = value == 'TRY' ? 1 : (_rates[value] ?? 1);
                    _exchangeRateController.text = _exchangeRate
                        .toStringAsFixed(value == 'TRY' ? 0 : 4);
                  });
                },
                onExchangeRateChanged: (value) =>
                    _exchangeRate = _parseDecimal(value),
              ),
              const Gap(12),
              _ItemsCard(
                items: _items,
                productsAsync: productsAsync,
                taxRatesAsync: taxRatesAsync,
                currency: _currency,
                isSales: _isSales,
                onChanged: () => setState(() {}),
                onAdd: () => setState(() => _items.add(_EInvoiceItemDraft())),
                onRemove: (index) {
                  setState(() {
                    _items[index].dispose();
                    _items.removeAt(index);
                  });
                },
              ),
              const Gap(12),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _notesController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: 'Fatura Notu',
                    hintText: 'Teslimat, ödeme veya açıklama notu',
                  ),
                ),
              ),
            ];

            final summary = _SummaryPanel(
              subtotal: _subtotal,
              discountTotal: _discountTotal,
              taxTotal: _taxTotal,
              grandTotal: _grandTotal,
              currency: _currency,
              sendAfterSave: _sendAfterSave,
              isSales: _isSales,
              saving: _saving,
              onSendAfterSaveChanged: (value) =>
                  setState(() => _sendAfterSave = value),
              onSaveDraft: () => _save(status: 'draft'),
              onSaveOpen: () => _save(status: 'open'),
            );

            if (wide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
                children: [
                  _DesktopInvoiceTop(
                    isSales: _isSales,
                    customersAsync: customersAsync,
                    selectedCustomerId: _customerId,
                    invoiceDate: _invoiceDate,
                    dueDate: _dueDate,
                    currency: _currency,
                    exchangeRateController: _exchangeRateController,
                    onCustomerSearch: (customers) => _pickCustomer(customers),
                    onInvoiceDateChanged: (value) =>
                        setState(() => _invoiceDate = value),
                    onDueDateChanged: (value) =>
                        setState(() => _dueDate = value),
                    onCurrencyChanged: (value) {
                      setState(() {
                        _currency = value;
                        _exchangeRate = value == 'TRY'
                            ? 1
                            : (_rates[value] ?? 1);
                        _exchangeRateController.text = _exchangeRate
                            .toStringAsFixed(value == 'TRY' ? 0 : 4);
                      });
                    },
                    onExchangeRateChanged: (value) =>
                        _exchangeRate = _parseDecimal(value),
                  ),
                  const Gap(14),
                  _DesktopItemsTable(
                    items: _items,
                    productsAsync: productsAsync,
                    taxRatesAsync: taxRatesAsync,
                    currency: _currency,
                    isSales: _isSales,
                    onChanged: () => setState(() {}),
                    onProductSearch: (products) => _addProducts(products),
                    onAdd: () =>
                        setState(() => _items.add(_EInvoiceItemDraft())),
                    onRemove: (index) {
                      setState(() {
                        _items[index].dispose();
                        _items.removeAt(index);
                      });
                    },
                  ),
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _notesController,
                            minLines: 7,
                            maxLines: 9,
                            decoration: const InputDecoration(
                              labelText: 'Not',
                              hintText: 'Fatura notu',
                            ),
                          ),
                        ),
                      ),
                      const Gap(16),
                      SizedBox(width: 360, child: summary),
                    ],
                  ),
                ],
              );
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 120),
              children: [...content, const Gap(12), summary],
            );
          },
        ),
      ),
    );
  }

  Future<void> _save({required String status}) async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null) {
      _showMessage('Cari seçin.');
      return;
    }
    final validItems = _items
        .where((item) => item.description.isNotEmpty && item.quantity > 0)
        .toList(growable: false);
    if (validItems.isEmpty) {
      _showMessage('En az bir fatura kalemi ekleyin.');
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      _showMessage('API bağlantısı yok.');
      return;
    }

    setState(() => _saving = true);
    try {
      final invoiceNumber = _isEditing
          ? widget.initialInvoice!.invoiceNumber
          : (await apiClient.getJson(
                  '/data',
                  queryParameters: {
                    'resource': 'invoice_number',
                    'invoiceType': widget.invoiceType,
                  },
                ))['value']?.toString().trim() ??
                '';
      final profile = await ref.read(currentUserProfileProvider.future);

      final invoiceResponse = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'invoices',
          'returning': 'row',
          'values': {
            if (_isEditing) 'id': widget.initialInvoice!.id,
            'invoice_number': invoiceNumber.isEmpty
                ? (widget.initialInvoice?.invoiceNumber ??
                      'EF-${DateTime.now().millisecondsSinceEpoch}')
                : invoiceNumber,
            'invoice_type': widget.invoiceType,
            'customer_id': _customerId,
            'invoice_date': _dateIso(_invoiceDate),
            'due_date': _dueDate == null ? null : _dateIso(_dueDate!),
            'currency': _currency,
            'exchange_rate': _currency == 'TRY' ? 1 : _exchangeRate,
            'status': status,
            'notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            'created_by': profile?.id,
          },
        },
      );
      final invoiceId = (invoiceResponse['id'] ?? '').toString();
      if (invoiceId.isEmpty) throw Exception('Fatura ID alınamadı.');

      if (_isEditing) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'invoice_items',
            'filters': [
              {'col': 'invoice_id', 'op': 'eq', 'value': invoiceId},
            ],
          },
        );
      }

      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'insertMany',
          'table': 'invoice_items',
          'rows': [
            for (var i = 0; i < validItems.length; i++)
              {
                'invoice_id': invoiceId,
                'product_id': validItems[i].productId,
                'description': validItems[i].description,
                'quantity': validItems[i].quantity,
                'unit': validItems[i].unit,
                'unit_price': validItems[i].unitPrice,
                'tax_rate': validItems[i].taxRate,
                'tax_amount': validItems[i].taxAmount,
                'discount_rate': validItems[i].discountRate,
                'discount_amount': validItems[i].discountAmount,
                'line_total': validItems[i].lineTotal,
                'sort_order': i,
              },
          ],
        },
      );

      if (_sendAfterSave && _isSales && status != 'draft') {
        await apiClient.postJson(
          '/e-invoice',
          body: {'action': 'send', 'invoiceId': invoiceId},
        );
      }

      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(eInvoiceSettingsProvider);
      if (!mounted) return;
      _showMessage(
        _sendAfterSave && _isSales && status != 'draft'
            ? 'Fatura kaydedildi ve test API’ye gönderildi.'
            : 'Fatura kaydedildi.',
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (mounted) _showMessage('Fatura kaydedilemedi: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _pickCustomer(List<Customer> customers) async {
    final selected = await showDialog<Customer>(
      context: context,
      builder: (context) => _CustomerPickerDialog(
        customers: customers,
        selectedCustomerId: _customerId,
        title: _isSales ? 'Müşteri Seç' : 'Tedarikçi / Cari Seç',
      ),
    );
    if (selected == null) return;
    setState(() => _customerId = selected.id);
  }

  Future<void> _addProducts(List<Product> products) async {
    final selected = await showDialog<List<Product>>(
      context: context,
      builder: (context) => _ProductPickerDialog(products: products),
    );
    if (selected == null || selected.isEmpty) return;
    setState(() {
      if (_items.length == 1 &&
          _items.first.description.isEmpty &&
          _items.first.unitPrice == 0) {
        _items.first.dispose();
        _items.clear();
      }
      for (final product in selected) {
        _items.add(_EInvoiceItemDraft.fromProduct(product, isSales: _isSales));
      }
    });
  }
}

class _DesktopInvoiceTop extends StatelessWidget {
  const _DesktopInvoiceTop({
    required this.isSales,
    required this.customersAsync,
    required this.selectedCustomerId,
    required this.invoiceDate,
    required this.dueDate,
    required this.currency,
    required this.exchangeRateController,
    required this.onCustomerSearch,
    required this.onInvoiceDateChanged,
    required this.onDueDateChanged,
    required this.onCurrencyChanged,
    required this.onExchangeRateChanged,
  });

  final bool isSales;
  final AsyncValue<List<Customer>> customersAsync;
  final String? selectedCustomerId;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String currency;
  final TextEditingController exchangeRateController;
  final ValueChanged<List<Customer>> onCustomerSearch;
  final ValueChanged<DateTime> onInvoiceDateChanged;
  final ValueChanged<DateTime?> onDueDateChanged;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<String> onExchangeRateChanged;

  @override
  Widget build(BuildContext context) {
    final selectedCustomer = customersAsync.value
        ?.where((customer) => customer.id == selectedCustomerId)
        .cast<Customer?>()
        .firstOrNull;
    final dateFormat = DateFormat('dd.MM.yyyy HH:mm');

    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.titleMedium,
                      children: [
                        TextSpan(
                          text: isSales
                              ? 'Gönderilen Fatura '
                              : 'Alış Faturası ',
                        ),
                        TextSpan(
                          text: isSales ? '(Standart)' : '(Cari)',
                          style: const TextStyle(color: Color(0xFF1AA8D8)),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(
                  width: 170,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(vertical: 7),
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border(
                      left: BorderSide(color: AppTheme.success, width: 4),
                    ),
                  ),
                  child: Text(
                    'Hazırlanıyor',
                    style: Theme.of(
                      context,
                    ).textTheme.titleMedium?.copyWith(color: AppTheme.success),
                  ),
                ),
              ],
            ),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          children: [
                            const _DesktopTextBox(
                              label: 'Fatura Nu.',
                              value: 'Otomatik oluşturulacak',
                              enabled: false,
                            ),
                            const Gap(10),
                            customersAsync.when(
                              data: (customers) => _CustomerSelectField(
                                customers: customers,
                                selectedCustomerId: selectedCustomerId,
                                label: isSales ? 'Müşteri' : 'Tedarikçi',
                                onSearch: () => onCustomerSearch(customers),
                              ),
                              loading: () => const LinearProgressIndicator(),
                              error: (_, _) =>
                                  const Text('Cari listesi yüklenemedi.'),
                            ),
                            const Gap(10),
                            DropdownButtonFormField<String>(
                              initialValue: 'Pesin',
                              items: const [
                                DropdownMenuItem(
                                  value: 'Pesin',
                                  child: Text('Peşin'),
                                ),
                                DropdownMenuItem(
                                  value: 'Vadeli',
                                  child: Text('Vadeli'),
                                ),
                              ],
                              onChanged: (_) {},
                              decoration: const InputDecoration(
                                labelText: 'Ödeme Planı',
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Gap(16),
                      Expanded(
                        child: Column(
                          children: [
                            _DateField(
                              label: 'Fatura Tarihi',
                              value: dateFormat.format(invoiceDate),
                              initialDate: invoiceDate,
                              onPicked: onInvoiceDateChanged,
                            ),
                            const Gap(10),
                            _DateField(
                              label: 'Vade Tarihi',
                              value: dueDate == null
                                  ? dateFormat.format(invoiceDate)
                                  : dateFormat.format(dueDate!),
                              initialDate:
                                  dueDate ??
                                  invoiceDate.add(const Duration(days: 30)),
                              onPicked: onDueDateChanged,
                            ),
                            const Gap(10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: currency,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'TRY',
                                        child: Text('TL'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'USD',
                                        child: Text('USD'),
                                      ),
                                    ],
                                    onChanged: (value) =>
                                        onCurrencyChanged(value ?? 'TRY'),
                                    decoration: const InputDecoration(
                                      labelText: 'Para Birimi',
                                    ),
                                  ),
                                ),
                                if (currency != 'TRY') ...[
                                  const Gap(10),
                                  Expanded(
                                    child: TextFormField(
                                      controller: exchangeRateController,
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      decoration: const InputDecoration(
                                        labelText: 'Kur',
                                      ),
                                      onChanged: onExchangeRateChanged,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 430,
                child: _AddressInfoPanel(customer: selectedCustomer),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopTextBox extends StatelessWidget {
  const _DesktopTextBox({
    required this.label,
    required this.value,
    this.enabled = true,
  });

  final String label;
  final String value;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: enabled,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _CustomerSelectField extends StatelessWidget {
  const _CustomerSelectField({
    required this.customers,
    required this.selectedCustomerId,
    required this.label,
    required this.onSearch,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final String label;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final selected = customers
        .where((customer) => customer.id == selectedCustomerId)
        .cast<Customer?>()
        .firstOrNull;
    return FormField<String>(
      initialValue: selectedCustomerId,
      validator: (value) =>
          (selectedCustomerId ?? '').isEmpty ? 'Cari seçin' : null,
      builder: (field) {
        return InkWell(
          borderRadius: BorderRadius.circular(AppTheme.radiusMd),
          onTap: onSearch,
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              errorText: field.errorText,
              suffixIcon: IconButton(
                tooltip: 'Cari ara',
                onPressed: onSearch,
                icon: const Icon(Icons.search_rounded),
              ),
            ),
            child: Text(
              selected == null ? 'Cari ara ve seç' : selected.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: selected == null ? AppTheme.textMuted : AppTheme.text,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    required this.customers,
    required this.selectedCustomerId,
    required this.title,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final String title;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.customers.take(80).toList(growable: false)
        : widget.customers
              .where((customer) {
                final haystack = [
                  customer.name,
                  customer.vkn ?? '',
                  customer.tcknMs ?? '',
                  customer.city ?? '',
                  customer.phone1 ?? '',
                ].join(' ').toLowerCase();
                return haystack.contains(query);
              })
              .take(120)
              .toList(growable: false);

    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Ad, VKN, telefon veya şehir ile ara',
              ),
            ),
            const Gap(10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Cari bulunamadı.'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = filtered[index];
                        final selected =
                            customer.id == widget.selectedCustomerId;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: CircleAvatar(
                            radius: 17,
                            child: Text(_initials(customer.name)),
                          ),
                          title: Text(
                            customer.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if ((customer.vkn ?? '').isNotEmpty)
                                'VKN ${customer.vkn}',
                              if ((customer.city ?? '').isNotEmpty)
                                customer.city,
                              if ((customer.phone1 ?? '').isNotEmpty)
                                customer.phone1,
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? const Icon(Icons.check_circle_rounded)
                              : null,
                          onTap: () => Navigator.of(context).pop(customer),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _AddressInfoPanel extends StatelessWidget {
  const _AddressInfoPanel({required this.customer});

  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    final address = customer?.address?.trim();
    final city = customer?.city?.trim();
    final tax = customer?.vkn?.trim();

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFFF8FAFC),
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.home_work_rounded, size: 18, color: AppTheme.primary),
              const Gap(8),
              Text(
                'Adres ve Vergi Bilgisi',
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const Gap(10),
          _AddressBox(
            title: 'Fatura Adresi',
            value: customer == null
                ? 'Cari seçildiğinde adres burada görünecek.'
                : [
                    customer!.name,
                    if (address != null && address.isNotEmpty) address,
                    if (city != null && city.isNotEmpty) city,
                    if (tax != null && tax.isNotEmpty) 'VKN $tax',
                  ].join('\n'),
          ),
        ],
      ),
    );
  }
}

class _AddressBox extends StatelessWidget {
  const _AddressBox({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Divider(height: 14),
          Text(
            value,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _DesktopItemsTable extends StatelessWidget {
  const _DesktopItemsTable({
    required this.items,
    required this.productsAsync,
    required this.taxRatesAsync,
    required this.currency,
    required this.isSales,
    required this.onChanged,
    required this.onProductSearch,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_EInvoiceItemDraft> items;
  final AsyncValue<List<Product>> productsAsync;
  final AsyncValue<List<TaxRate>> taxRatesAsync;
  final String currency;
  final bool isSales;
  final VoidCallback onChanged;
  final ValueChanged<List<Product>> onProductSearch;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
            child: Row(
              children: [
                const _SectionTab(
                  icon: Icons.format_list_bulleted_rounded,
                  label: 'Öğeler',
                  selected: true,
                ),
                const Spacer(),
                productsAsync.maybeWhen(
                  data: (products) => OutlinedButton.icon(
                    onPressed: () => onProductSearch(products),
                    icon: const Icon(Icons.search_rounded, size: 18),
                    label: const Text('Ürün Ara / Çoklu Ekle'),
                  ),
                  orElse: () => const SizedBox.shrink(),
                ),
                const Gap(8),
                IconButton.filled(
                  tooltip: 'Boş satır ekle',
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          productsAsync.when(
            data: (products) {
              final taxRates = _availableTaxRates(taxRatesAsync, items);
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 1160),
                  child: Column(
                    children: [
                      const _InvoiceTableHeader(),
                      for (var i = 0; i < items.length; i++)
                        _InvoiceTableRow(
                          item: items[i],
                          products: products,
                          taxRates: taxRates,
                          currency: currency,
                          isSales: isSales,
                          onChanged: onChanged,
                          onRemove: () => onRemove(i),
                        ),
                    ],
                  ),
                ),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(18),
              child: LinearProgressIndicator(),
            ),
            error: (_, _) => const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Stok/hizmet listesi yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionTab extends StatelessWidget {
  const _SectionTab({
    required this.icon,
    required this.label,
    this.selected = false,
  });

  final IconData icon;
  final String label;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF229ED3) : AppTheme.textSoft;
    return Container(
      margin: const EdgeInsets.only(left: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: selected ? color : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: selected ? Colors.white : color),
          const Gap(8),
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: selected ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTableHeader extends StatelessWidget {
  const _InvoiceTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: const Color(0xFFEFF6FD),
      child: Row(
        children: const [
          _HeaderCell('Ürün', width: 330),
          _HeaderCell('Miktar', width: 92),
          _HeaderCell('Birim', width: 104),
          _HeaderCell('Birim Fiyatı', width: 130),
          _HeaderCell('İndirim', width: 104),
          _HeaderCell('Vergi', width: 104),
          _HeaderCell('Toplam', width: 160),
          _HeaderCell('', width: 62),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.width});

  final String label;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelLarge?.copyWith(color: const Color(0xFF40556F)),
        ),
      ),
    );
  }
}

class _InvoiceTableRow extends StatelessWidget {
  const _InvoiceTableRow({
    required this.item,
    required this.products,
    required this.taxRates,
    required this.currency,
    required this.isSales,
    required this.onChanged,
    required this.onRemove,
  });

  final _EInvoiceItemDraft item;
  final List<Product> products;
  final List<double> taxRates;
  final String currency;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: currency == 'TRY' ? '' : '$currency ',
      decimalDigits: 2,
    );
    return Container(
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 330,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Autocomplete<Product>(
                optionsBuilder: (value) {
                  final query = value.text.trim().toLowerCase();
                  if (query.isEmpty) return products.take(12);
                  return products
                      .where(
                        (product) =>
                            product.name.toLowerCase().contains(query) ||
                            (product.code ?? '').toLowerCase().contains(query),
                      )
                      .take(12);
                },
                displayStringForOption: (product) => product.name,
                onSelected: (product) {
                  item.productId = product.id;
                  item.descriptionController.text = product.name;
                  item.unit = product.unit;
                  item.taxRate = product.taxRate;
                  item.priceController.text =
                      (isSales ? product.salePrice : product.purchasePrice)
                          .toStringAsFixed(2);
                  onChanged();
                },
                fieldViewBuilder: (context, controller, focusNode, _) {
                  if (controller.text.isEmpty &&
                      item.descriptionController.text.isNotEmpty) {
                    controller.text = item.descriptionController.text;
                  }
                  return TextFormField(
                    controller: controller,
                    focusNode: focusNode,
                    decoration: const InputDecoration(hintText: 'Ürün seçin'),
                    validator: (value) =>
                        (value ?? '').trim().isEmpty ? 'Gerekli' : null,
                    onChanged: (value) {
                      item.productId = null;
                      item.descriptionController.text = value;
                      onChanged();
                    },
                  );
                },
              ),
            ),
          ),
          _TableTextField(
            width: 92,
            controller: item.quantityController,
            onChanged: onChanged,
          ),
          SizedBox(
            width: 104,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonFormField<String>(
                initialValue: item.unit,
                items: const [
                  DropdownMenuItem(value: 'Adet', child: Text('Adet')),
                  DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                  DropdownMenuItem(value: 'Lt', child: Text('Lt')),
                  DropdownMenuItem(value: 'Mt', child: Text('Mt')),
                  DropdownMenuItem(value: 'Saat', child: Text('Saat')),
                ],
                onChanged: (value) {
                  item.unit = value ?? 'Adet';
                  onChanged();
                },
              ),
            ),
          ),
          _TableTextField(
            width: 130,
            controller: item.priceController,
            onChanged: onChanged,
          ),
          SizedBox(
            width: 104,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextFormField(
                initialValue: item.discountRate.toStringAsFixed(0),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(suffixText: '%'),
                onChanged: (value) {
                  item.discountRate = _parseDecimal(value);
                  onChanged();
                },
              ),
            ),
          ),
          SizedBox(
            width: 104,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButtonFormField<double>(
                initialValue: _taxInitialValue(item.taxRate, taxRates),
                items: [
                  for (final rate in taxRates)
                    DropdownMenuItem(value: rate, child: Text(_taxLabel(rate))),
                ],
                onChanged: (value) {
                  item.taxRate = value ?? 20;
                  onChanged();
                },
              ),
            ),
          ),
          SizedBox(
            width: 160,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    money.format(item.lineTotal),
                    style: Theme.of(
                      context,
                    ).textTheme.titleSmall?.copyWith(color: AppTheme.success),
                  ),
                  Text(
                    'KDV ${money.format(item.taxAmount)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            width: 62,
            child: IconButton(
              tooltip: 'Sil',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableTextField extends StatelessWidget {
  const _TableTextField({
    required this.width,
    required this.controller,
    required this.onChanged,
  });

  final double width;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextFormField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => onChanged(),
        ),
      ),
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});

  final List<Product> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _search = TextEditingController();
  final _selectedIds = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    final activeProducts = widget.products.where((p) => p.isActive).toList();
    final filtered = query.isEmpty
        ? activeProducts.take(100).toList(growable: false)
        : activeProducts
              .where((product) {
                final haystack = [
                  product.name,
                  product.code ?? '',
                  product.category ?? '',
                  product.description ?? '',
                ].join(' ').toLowerCase();
                return haystack.contains(query);
              })
              .take(140)
              .toList(growable: false);

    return AlertDialog(
      title: const Text('Ürün Ara ve Ekle'),
      content: SizedBox(
        width: 820,
        height: 600,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Ürün adı, kod veya kategori ile ara',
              ),
            ),
            const Gap(10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Ürün bulunamadı.'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final product = filtered[index];
                        final selected = _selectedIds.contains(product.id);
                        return CheckboxListTile(
                          dense: true,
                          value: selected,
                          onChanged: (value) {
                            setState(() {
                              if (value ?? false) {
                                _selectedIds.add(product.id);
                              } else {
                                _selectedIds.remove(product.id);
                              }
                            });
                          },
                          title: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            [
                              if ((product.code ?? '').isNotEmpty) product.code,
                              product.unit,
                              product.currency,
                              'Alış ${product.purchasePrice.toStringAsFixed(2)}',
                              'Satış ${product.salePrice.toStringAsFixed(2)}',
                            ].join(' • '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: Icon(
                            product.productType == 'service'
                                ? Icons.design_services_rounded
                                : Icons.inventory_2_rounded,
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton.icon(
          onPressed: _selectedIds.isEmpty
              ? null
              : () {
                  final selected = widget.products
                      .where((product) => _selectedIds.contains(product.id))
                      .toList(growable: false);
                  Navigator.of(context).pop(selected);
                },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: Text('Seçilenleri Ekle (${_selectedIds.length})'),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({required this.isSales});

  final bool isSales;

  @override
  Widget build(BuildContext context) {
    final color = isSales ? AppTheme.success : AppTheme.warning;
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: color.withValues(alpha: 0.12),
            child: Icon(
              isSales ? Icons.north_east_rounded : Icons.south_west_rounded,
              color: color,
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isSales
                      ? 'Müşteriye satış faturası'
                      : 'Tedarikçi alış faturası',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  isSales
                      ? 'Kalemleri stok/hizmet listesinden seçip e-fatura gönderimine hazırlayın.'
                      : 'Alış faturası cari borç ve stok maliyet takibi için kaydedilir.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          AppBadge(
            label: isSales ? 'Satış' : 'Alış',
            tone: isSales ? AppBadgeTone.success : AppBadgeTone.warning,
          ),
        ],
      ),
    );
  }
}

class _PartyCard extends StatelessWidget {
  const _PartyCard({
    required this.customersAsync,
    required this.selectedCustomerId,
    required this.isSales,
    required this.onChanged,
  });

  final AsyncValue<List<Customer>> customersAsync;
  final String? selectedCustomerId;
  final bool isSales;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cari Bilgisi', style: Theme.of(context).textTheme.titleSmall),
          const Gap(12),
          customersAsync.when(
            data: (customers) => DropdownButtonFormField<String>(
              initialValue: selectedCustomerId,
              isExpanded: true,
              items: [
                for (final customer in customers)
                  DropdownMenuItem(
                    value: customer.id,
                    child: Text(
                      [
                        customer.name,
                        if ((customer.vkn ?? '').isNotEmpty)
                          'VKN ${customer.vkn}',
                      ].join(' • '),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
              ],
              onChanged: onChanged,
              decoration: InputDecoration(
                labelText: isSales ? 'Müşteri' : 'Tedarikçi / Cari',
              ),
              validator: (value) => value == null ? 'Cari seçin' : null,
            ),
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Cari listesi yüklenemedi.'),
          ),
        ],
      ),
    );
  }
}

class _InvoiceInfoCard extends StatelessWidget {
  const _InvoiceInfoCard({
    required this.invoiceDate,
    required this.dueDate,
    required this.currency,
    required this.exchangeRateController,
    required this.onInvoiceDateChanged,
    required this.onDueDateChanged,
    required this.onCurrencyChanged,
    required this.onExchangeRateChanged,
  });

  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String currency;
  final TextEditingController exchangeRateController;
  final ValueChanged<DateTime> onInvoiceDateChanged;
  final ValueChanged<DateTime?> onDueDateChanged;
  final ValueChanged<String> onCurrencyChanged;
  final ValueChanged<String> onExchangeRateChanged;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Fatura Bilgileri',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Gap(12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: 210,
                child: _DateField(
                  label: 'Fatura Tarihi',
                  value: dateFormat.format(invoiceDate),
                  initialDate: invoiceDate,
                  onPicked: onInvoiceDateChanged,
                ),
              ),
              SizedBox(
                width: 210,
                child: _DateField(
                  label: 'Vade Tarihi',
                  value: dueDate == null
                      ? 'Seçilmedi'
                      : dateFormat.format(dueDate!),
                  initialDate:
                      dueDate ?? invoiceDate.add(const Duration(days: 30)),
                  onPicked: onDueDateChanged,
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TL')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                  ],
                  onChanged: (value) => onCurrencyChanged(value ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
              ),
              if (currency != 'TRY')
                SizedBox(
                  width: 180,
                  child: TextFormField(
                    controller: exchangeRateController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Kur'),
                    onChanged: onExchangeRateChanged,
                    validator: (value) =>
                        _parseDecimal(value ?? '') <= 0 ? 'Kur gerekli' : null,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.initialDate,
    required this.onPicked,
  });

  final String label;
  final String value;
  final DateTime initialDate;
  final ValueChanged<DateTime> onPicked;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: initialDate,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value),
      ),
    );
  }
}

class _ItemsCard extends StatelessWidget {
  const _ItemsCard({
    required this.items,
    required this.productsAsync,
    required this.taxRatesAsync,
    required this.currency,
    required this.isSales,
    required this.onChanged,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_EInvoiceItemDraft> items;
  final AsyncValue<List<Product>> productsAsync;
  final AsyncValue<List<TaxRate>> taxRatesAsync;
  final String currency;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kalemler',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kalem Ekle'),
              ),
            ],
          ),
          const Gap(12),
          productsAsync.when(
            data: (products) {
              final taxRates = _availableTaxRates(taxRatesAsync, items);
              return Column(
                children: [
                  for (var i = 0; i < items.length; i++) ...[
                    _ItemEditor(
                      item: items[i],
                      products: products,
                      taxRates: taxRates,
                      currency: currency,
                      isSales: isSales,
                      onChanged: onChanged,
                      onRemove: () => onRemove(i),
                    ),
                    if (i != items.length - 1) const Gap(10),
                  ],
                ],
              );
            },
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text('Stok/hizmet listesi yüklenemedi.'),
          ),
        ],
      ),
    );
  }
}

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    required this.item,
    required this.products,
    required this.taxRates,
    required this.currency,
    required this.isSales,
    required this.onChanged,
    required this.onRemove,
  });

  final _EInvoiceItemDraft item;
  final List<Product> products;
  final List<double> taxRates;
  final String currency;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: currency == 'TRY' ? '₺' : '$currency ',
      decimalDigits: 2,
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Autocomplete<Product>(
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      if (query.isEmpty) return products.take(12);
                      return products
                          .where(
                            (product) =>
                                product.name.toLowerCase().contains(query) ||
                                (product.code ?? '').toLowerCase().contains(
                                  query,
                                ),
                          )
                          .take(12);
                    },
                    displayStringForOption: (product) => product.name,
                    onSelected: (product) {
                      item.productId = product.id;
                      item.descriptionController.text = product.name;
                      item.unit = product.unit;
                      item.taxRate = product.taxRate;
                      item.priceController.text =
                          (isSales ? product.salePrice : product.purchasePrice)
                              .toStringAsFixed(2);
                      onChanged();
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      if (controller.text.isEmpty &&
                          item.descriptionController.text.isNotEmpty) {
                        controller.text = item.descriptionController.text;
                      }
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Stok/Hizmet',
                          hintText: 'Ürün, hizmet veya açıklama',
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Kalem adı gerekli'
                            : null,
                        onChanged: (value) {
                          item.productId = null;
                          item.descriptionController.text = value;
                          onChanged();
                        },
                      );
                    },
                  ),
                ),
                const Gap(10),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    controller: item.quantityController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Miktar'),
                    onChanged: (_) => onChanged(),
                    validator: (value) =>
                        _parseDecimal(value ?? '') <= 0 ? 'Gerekli' : null,
                  ),
                ),
                const Gap(10),
                SizedBox(
                  width: 105,
                  child: TextFormField(
                    controller: item.priceController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Fiyat'),
                    onChanged: (_) => onChanged(),
                  ),
                ),
                IconButton(
                  tooltip: 'Kalemi sil',
                  onPressed: onRemove,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<String>(
                    initialValue: item.unit,
                    items: const [
                      DropdownMenuItem(value: 'Adet', child: Text('Adet')),
                      DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                      DropdownMenuItem(value: 'Lt', child: Text('Lt')),
                      DropdownMenuItem(value: 'Mt', child: Text('Mt')),
                      DropdownMenuItem(value: 'Saat', child: Text('Saat')),
                    ],
                    onChanged: (value) {
                      item.unit = value ?? 'Adet';
                      onChanged();
                    },
                    decoration: const InputDecoration(labelText: 'Birim'),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: DropdownButtonFormField<double>(
                    initialValue: _taxInitialValue(item.taxRate, taxRates),
                    items: [
                      for (final rate in taxRates)
                        DropdownMenuItem(
                          value: rate,
                          child: Text(_taxLabel(rate)),
                        ),
                    ],
                    onChanged: (value) {
                      item.taxRate = value ?? 20;
                      onChanged();
                    },
                    decoration: const InputDecoration(labelText: 'KDV'),
                  ),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    initialValue: item.discountRate.toStringAsFixed(0),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(labelText: 'İndirim %'),
                    onChanged: (value) {
                      item.discountRate = _parseDecimal(value);
                      onChanged();
                    },
                  ),
                ),
                SizedBox(
                  width: 170,
                  child: _LineTotal(
                    label: 'Kalem Toplamı',
                    value: money.format(item.lineTotal),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LineTotal extends StatelessWidget {
  const _LineTotal({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(value, style: Theme.of(context).textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _SummaryPanel extends StatelessWidget {
  const _SummaryPanel({
    required this.subtotal,
    required this.discountTotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.currency,
    required this.sendAfterSave,
    required this.isSales,
    required this.saving,
    required this.onSendAfterSaveChanged,
    required this.onSaveDraft,
    required this.onSaveOpen,
  });

  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double grandTotal;
  final String currency;
  final bool sendAfterSave;
  final bool isSales;
  final bool saving;
  final ValueChanged<bool> onSendAfterSaveChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onSaveOpen;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: currency == 'TRY' ? '₺' : '$currency ',
      decimalDigits: 2,
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fatura Özeti', style: Theme.of(context).textTheme.titleMedium),
          const Gap(14),
          _SummaryLine(label: 'Ara Toplam', value: money.format(subtotal)),
          _SummaryLine(label: 'İndirim', value: money.format(discountTotal)),
          _SummaryLine(label: 'KDV', value: money.format(taxTotal)),
          const Divider(height: 22),
          _SummaryLine(
            label: 'Genel Toplam',
            value: money.format(grandTotal),
            isTotal: true,
          ),
          const Gap(12),
          if (isSales)
            SwitchListTile(
              value: sendAfterSave,
              onChanged: saving ? null : onSendAfterSaveChanged,
              title: const Text('Kaydet ve test API’ye gönder'),
              contentPadding: EdgeInsets.zero,
            ),
          const Gap(8),
          OutlinedButton(
            onPressed: saving ? null : onSaveDraft,
            child: const Text('Taslak Kaydet'),
          ),
          const Gap(8),
          FilledButton(
            onPressed: saving ? null : onSaveOpen,
            child: Text(
              isSales ? 'Faturayı Oluştur' : 'Alış Faturasını Kaydet',
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({
    required this.label,
    required this.value,
    this.isTotal = false,
  });

  final String label;
  final String value;
  final bool isTotal;

  @override
  Widget build(BuildContext context) {
    final style = isTotal
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style?.copyWith(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _EInvoiceItemDraft {
  _EInvoiceItemDraft()
    : descriptionController = TextEditingController(),
      quantityController = TextEditingController(text: '1'),
      priceController = TextEditingController(text: '0');

  _EInvoiceItemDraft.fromProduct(Product product, {required bool isSales})
    : descriptionController = TextEditingController(text: product.name),
      quantityController = TextEditingController(text: '1'),
      priceController = TextEditingController(
        text: (isSales ? product.salePrice : product.purchasePrice)
            .toStringAsFixed(2),
      ),
      productId = product.id,
      unit = product.unit,
      taxRate = product.taxRate;

  _EInvoiceItemDraft.fromInvoiceItem(InvoiceItem item)
    : descriptionController = TextEditingController(text: item.description),
      quantityController = TextEditingController(
        text: item.quantity.toStringAsFixed(
          item.quantity.truncateToDouble() == item.quantity ? 0 : 2,
        ),
      ),
      priceController = TextEditingController(
        text: item.unitPrice.toStringAsFixed(2),
      ),
      productId = item.productId,
      unit = item.unit,
      taxRate = item.taxRate,
      discountRate = item.discountRate;

  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  String? productId;
  String unit = 'Adet';
  double taxRate = 20;
  double discountRate = 0;

  String get description => descriptionController.text.trim();
  double get quantity => _parseDecimal(quantityController.text);
  double get unitPrice => _parseDecimal(priceController.text);
  double get subtotal => quantity * unitPrice;
  double get discountAmount => subtotal * (discountRate / 100);
  double get taxAmount => (subtotal - discountAmount) * (taxRate / 100);
  double get lineTotal => subtotal - discountAmount + taxAmount;

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    priceController.dispose();
  }
}

List<double> _availableTaxRates(
  AsyncValue<List<TaxRate>> ratesAsync,
  List<_EInvoiceItemDraft> items,
) {
  final rates = <double>{0, 1, 5, 10, 16, 18, 20};
  ratesAsync.whenData((items) {
    for (final item in items) {
      if (item.isActive) rates.add(_normalizeRate(item.rate));
    }
  });
  for (final item in items) {
    rates.add(_normalizeRate(item.taxRate));
  }
  final sorted = rates.where((rate) => rate >= 0).toList()..sort();
  return sorted;
}

double _taxInitialValue(double value, List<double> rates) {
  final normalized = _normalizeRate(value);
  if (rates.contains(normalized)) return normalized;
  return normalized;
}

double _normalizeRate(double value) => (value * 100).roundToDouble() / 100;

String _taxLabel(double value) {
  final normalized = _normalizeRate(value);
  final text = normalized.truncateToDouble() == normalized
      ? normalized.toInt().toString()
      : normalized
            .toStringAsFixed(2)
            .replaceFirst(RegExp(r'0+$'), '')
            .replaceFirst(RegExp(r'\.$'), '');
  return '%$text';
}

String _dateIso(DateTime date) => date.toIso8601String().substring(0, 10);

double _parseDecimal(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2);
  final text = parts.map((part) => part.characters.first.toUpperCase()).join();
  return text.isEmpty ? '?' : text;
}
