import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_card.dart';
import '../customers/customers_providers.dart';
import '../work_orders/currency_service.dart';
import 'invoice_model.dart';
import 'invoice_providers.dart';

class InvoiceFormScreen extends ConsumerStatefulWidget {
  const InvoiceFormScreen({super.key, required this.invoiceType, this.editInvoice});

  final String invoiceType;
  final Invoice? editInvoice;

  @override
  ConsumerState<InvoiceFormScreen> createState() => _InvoiceFormScreenState();
}

class _InvoiceFormScreenState extends ConsumerState<InvoiceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  
  String? _selectedCustomerId;
  DateTime _invoiceDate = DateTime.now();
  DateTime? _dueDate;
  String _currency = 'TRY';
  double _exchangeRate = 1.0;
  
  final List<_ItemDraft> _items = [];
  bool _saving = false;
  Map<String, double> _rates = {};

  @override
  void initState() {
    super.initState();
    _loadRates();
    
    if (widget.editInvoice != null) {
      final inv = widget.editInvoice!;
      _selectedCustomerId = inv.customerId;
      _invoiceDate = inv.invoiceDate;
      _dueDate = inv.dueDate;
      _currency = inv.currency;
      _exchangeRate = inv.exchangeRate;
      _notesController.text = inv.notes ?? '';
      
      for (final item in inv.items) {
        _items.add(_ItemDraft(
          descController: TextEditingController(text: item.description),
          qtyController: TextEditingController(text: item.quantity.toString()),
          priceController: TextEditingController(text: item.unitPrice.toString()),
          taxRate: item.taxRate,
          discountRate: item.discountRate,
          unit: item.unit,
          productId: item.productId,
        ));
      }
    } else {
      _items.add(_ItemDraft());
    }
  }

  Future<void> _loadRates() async {
    _rates = await CurrencyService.getExchangeRates();
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _notesController.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double get _subtotal {
    double total = 0;
    for (final item in _items) {
      total += (item.quantity ?? 0) * (item.unitPrice ?? 0);
    }
    return total;
  }

  double get _taxTotal {
    double total = 0;
    for (final item in _items) {
      final base = (item.quantity ?? 0) * (item.unitPrice ?? 0);
      final afterDiscount = base * (1 - item.discountRate / 100);
      total += afterDiscount * (item.taxRate / 100);
    }
    return total;
  }

  double get _discountTotal {
    double total = 0;
    for (final item in _items) {
      final base = (item.quantity ?? 0) * (item.unitPrice ?? 0);
      total += base * (item.discountRate / 100);
    }
    return total;
  }

  double get _grandTotal => _subtotal - _discountTotal + _taxTotal;

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersLookupProvider);
    final productsAsync = ref.watch(productsProvider(null));
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2);
    
    final title = widget.editInvoice != null
        ? 'Fatura Düzenle'
        : (widget.invoiceType == 'sales' ? 'Yeni Satış Faturası' : 'Yeni Alış Faturası');

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: _saving ? null : _saveDraft,
            child: const Text('Taslak Kaydet'),
          ),
          const Gap(8),
          FilledButton(
            onPressed: _saving ? null : _saveAndFinalize,
            child: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Text('Kaydet'),
          ),
          const Gap(12),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Cari Seçimi
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Cari Bilgileri', style: Theme.of(context).textTheme.titleSmall),
                  const Gap(12),
                  customersAsync.when(
                    data: (customers) => DropdownButtonFormField<String>(
                      initialValue: _selectedCustomerId,
                      items: customers.map((c) => DropdownMenuItem(
                        value: c.id,
                        child: Text(c.name),
                      )).toList(),
                      onChanged: (v) => setState(() => _selectedCustomerId = v),
                      decoration: InputDecoration(
                        labelText: widget.invoiceType == 'sales' ? 'Müşteri' : 'Tedarikçi',
                      ),
                      validator: (v) => v == null ? 'Cari seçin' : null,
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Cariler yüklenemedi'),
                  ),
                ],
              ),
            ),
            const Gap(16),
            // Fatura Bilgileri
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Fatura Bilgileri', style: Theme.of(context).textTheme.titleSmall),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _invoiceDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setState(() => _invoiceDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Fatura Tarihi'),
                            child: Text(DateFormat('d MMM y', 'tr_TR').format(_invoiceDate)),
                          ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: () async {
                            final date = await showDatePicker(
                              context: context,
                              initialDate: _dueDate ?? _invoiceDate.add(const Duration(days: 30)),
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2030),
                            );
                            if (date != null) setState(() => _dueDate = date);
                          },
                          child: InputDecorator(
                            decoration: const InputDecoration(labelText: 'Vade Tarihi'),
                            child: Text(_dueDate == null ? 'Seçilmedi' : DateFormat('d MMM y', 'tr_TR').format(_dueDate!)),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _currency,
                          items: const [
                            DropdownMenuItem(value: 'TRY', child: Text('TRY (₺)')),
                            DropdownMenuItem(value: 'USD', child: Text('USD (\$)')),
                            DropdownMenuItem(value: 'EUR', child: Text('EUR (€)')),
                            DropdownMenuItem(value: 'GBP', child: Text('GBP (£)')),
                          ],
                          onChanged: (v) {
                            if (v == null) return;
                            setState(() {
                              _currency = v;
                              _exchangeRate = v == 'TRY' ? 1.0 : (_rates[v] ?? 1.0);
                            });
                          },
                          decoration: const InputDecoration(labelText: 'Para Birimi'),
                        ),
                      ),
                      if (_currency != 'TRY') ...[
                        const Gap(12),
                        Expanded(
                          child: TextFormField(
                            initialValue: _exchangeRate.toStringAsFixed(4),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: const InputDecoration(labelText: 'Kur'),
                            onChanged: (v) => _exchangeRate = double.tryParse(v) ?? 1.0,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const Gap(16),
            // Kalemler
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text('Fatura Kalemleri', style: Theme.of(context).textTheme.titleSmall)),
                      OutlinedButton.icon(
                        onPressed: () => setState(() => _items.add(_ItemDraft())),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Kalem Ekle'),
                      ),
                    ],
                  ),
                  const Gap(12),
                  productsAsync.when(
                    data: (products) => Column(
                      children: [
                        for (int i = 0; i < _items.length; i++)
                          _ItemRow(
                            key: ValueKey(i),
                            item: _items[i],
                            products: products,
                            onRemove: _items.length > 1 ? () => setState(() {
                              _items[i].dispose();
                              _items.removeAt(i);
                            }) : null,
                            onChanged: () => setState(() {}),
                          ),
                      ],
                    ),
                    loading: () => const LinearProgressIndicator(),
                    error: (_, _) => const Text('Ürünler yüklenemedi'),
                  ),
                  const Divider(height: 24),
                  _SummaryRow(label: 'Ara Toplam', value: money.format(_subtotal)),
                  if (_discountTotal > 0) _SummaryRow(label: 'İndirim', value: '-${money.format(_discountTotal)}'),
                  _SummaryRow(label: 'KDV Toplam', value: money.format(_taxTotal)),
                  const Gap(8),
                  _SummaryRow(label: 'Genel Toplam', value: money.format(_grandTotal), isTotal: true),
                ],
              ),
            ),
            const Gap(16),
            // Notlar
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Notlar', style: Theme.of(context).textTheme.titleSmall),
                  const Gap(12),
                  TextField(
                    controller: _notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Fatura ile ilgili notlar...',
                    ),
                  ),
                ],
              ),
            ),
            const Gap(80),
          ],
        ),
      ),
    );
  }

  Future<void> _saveDraft() => _save('draft');
  Future<void> _saveAndFinalize() => _save('open');

  Future<void> _save(String status) async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cari seçin')));
      return;
    }
    if (_items.isEmpty || _items.every((i) => (i.description?.isEmpty ?? true))) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('En az bir kalem ekleyin')));
      return;
    }

    setState(() => _saving = true);
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      setState(() => _saving = false);
      return;
    }

    try {
      String invoiceNumber;
      if (widget.editInvoice != null) {
        invoiceNumber = widget.editInvoice!.invoiceNumber;
      } else {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'invoice_number',
            'invoiceType': widget.invoiceType,
          },
        );
        invoiceNumber = (response['value'] ?? '').toString();
        if (invoiceNumber.trim().isEmpty) {
          invoiceNumber = 'INV-${DateTime.now().millisecondsSinceEpoch}';
        }
      }

      final profile = await ref.read(currentUserProfileProvider.future);
      final invoiceData = {
        'invoice_number': invoiceNumber,
        'invoice_type': widget.invoiceType,
        'customer_id': _selectedCustomerId,
        'invoice_date': _invoiceDate.toIso8601String().substring(0, 10),
        'due_date': _dueDate?.toIso8601String().substring(0, 10),
        'currency': _currency,
        'exchange_rate': _exchangeRate,
        'status': status,
        'notes': _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        'created_by': profile?.id,
      };

      String invoiceId;
      if (widget.editInvoice != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'invoices',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.editInvoice!.id},
            ],
            'values': invoiceData,
          },
        );
        invoiceId = widget.editInvoice!.id;
        // Delete old items
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
      } else {
        final result = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'invoices',
            'returning': 'row',
            'values': invoiceData,
          },
        );
        invoiceId = (result['id'] ?? '').toString();
      }

      // Insert items
      final itemsData = <Map<String, dynamic>>[];
      for (int i = 0; i < _items.length; i++) {
        final item = _items[i];
        if (item.description?.isEmpty ?? true) continue;

        final qty = item.quantity ?? 1;
        final price = item.unitPrice ?? 0;
        final base = qty * price;
        final discAmt = base * (item.discountRate / 100);
        final afterDiscount = base - discAmt;
        final taxAmt = afterDiscount * (item.taxRate / 100);
        final total = afterDiscount + taxAmt;

        itemsData.add({
          'invoice_id': invoiceId,
          'product_id': item.productId,
          'description': item.description,
          'quantity': qty,
          'unit': item.unit,
          'unit_price': price,
          'tax_rate': item.taxRate,
          'tax_amount': taxAmt,
          'discount_rate': item.discountRate,
          'discount_amount': discAmt,
          'line_total': total,
          'sort_order': i,
        });
      }

      if (itemsData.isNotEmpty) {
        await apiClient.postJson(
          '/mutate',
          body: {'op': 'insertMany', 'table': 'invoice_items', 'rows': itemsData},
        );
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(status == 'draft' ? 'Taslak kaydedildi' : 'Fatura kaydedildi')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _ItemDraft {
  _ItemDraft({
    TextEditingController? descController,
    TextEditingController? qtyController,
    TextEditingController? priceController,
    this.taxRate = 20,
    this.discountRate = 0,
    this.unit = 'Adet',
    this.productId,
  })  : descController = descController ?? TextEditingController(),
        qtyController = qtyController ?? TextEditingController(text: '1'),
        priceController = priceController ?? TextEditingController(text: '0');

  final TextEditingController descController;
  final TextEditingController qtyController;
  final TextEditingController priceController;
  double taxRate;
  double discountRate;
  String unit;
  String? productId;

  String? get description => descController.text.trim().isEmpty ? null : descController.text.trim();
  double? get quantity => double.tryParse(qtyController.text.replaceAll(',', '.'));
  double? get unitPrice => double.tryParse(priceController.text.replaceAll(',', '.'));

  void dispose() {
    descController.dispose();
    qtyController.dispose();
    priceController.dispose();
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    super.key,
    required this.item,
    required this.products,
    required this.onRemove,
    required this.onChanged,
  });

  final _ItemDraft item;
  final List<Product> products;
  final VoidCallback? onRemove;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 3,
                child: Autocomplete<Product>(
                  optionsBuilder: (text) {
                    final q = text.text.toLowerCase();
                    if (q.isEmpty) return products.take(10);
                    return products.where((p) =>
                        p.name.toLowerCase().contains(q) ||
                        (p.code?.toLowerCase().contains(q) ?? false)).take(10);
                  },
                  displayStringForOption: (p) => p.name,
                  onSelected: (p) {
                    item.productId = p.id;
                    item.descController.text = p.name;
                    item.priceController.text = p.salePrice.toString();
                    item.taxRate = p.taxRate;
                    item.unit = p.unit;
                    onChanged();
                  },
                  fieldViewBuilder: (context, controller, focusNode, _) {
                    if (controller.text.isEmpty && item.descController.text.isNotEmpty) {
                      controller.text = item.descController.text;
                    }
                    return TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        labelText: 'Ürün/Hizmet',
                        hintText: 'Ürün ara veya yaz',
                        isDense: true,
                      ),
                      onChanged: (v) {
                        item.descController.text = v;
                        item.productId = null;
                        onChanged();
                      },
                    );
                  },
                ),
              ),
              const Gap(8),
              if (onRemove != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, size: 20),
                  onPressed: onRemove,
                  tooltip: 'Kaldır',
                ),
            ],
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: item.qtyController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Miktar', isDense: true),
                  onChanged: (_) => onChanged(),
                ),
              ),
              const Gap(8),
              SizedBox(
                width: 80,
                child: DropdownButtonFormField<String>(
                  initialValue: item.unit,
                  items: const [
                    DropdownMenuItem(value: 'Adet', child: Text('Adet')),
                    DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                    DropdownMenuItem(value: 'Lt', child: Text('Lt')),
                    DropdownMenuItem(value: 'Mt', child: Text('Mt')),
                    DropdownMenuItem(value: 'Saat', child: Text('Saat')),
                  ],
                  onChanged: (v) {
                    item.unit = v ?? 'Adet';
                    onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'Birim', isDense: true),
                ),
              ),
              const Gap(8),
              Expanded(
                child: TextField(
                  controller: item.priceController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Birim Fiyat', isDense: true),
                  onChanged: (_) => onChanged(),
                ),
              ),
            ],
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: item.taxRate,
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('%0')),
                    DropdownMenuItem(value: 1.0, child: Text('%1')),
                    DropdownMenuItem(value: 10.0, child: Text('%10')),
                    DropdownMenuItem(value: 20.0, child: Text('%20')),
                  ],
                  onChanged: (v) {
                    item.taxRate = v ?? 20;
                    onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'KDV', isDense: true),
                ),
              ),
              const Gap(8),
              Expanded(
                child: DropdownButtonFormField<double>(
                  initialValue: item.discountRate,
                  items: const [
                    DropdownMenuItem(value: 0.0, child: Text('%0')),
                    DropdownMenuItem(value: 5.0, child: Text('%5')),
                    DropdownMenuItem(value: 10.0, child: Text('%10')),
                    DropdownMenuItem(value: 15.0, child: Text('%15')),
                    DropdownMenuItem(value: 20.0, child: Text('%20')),
                  ],
                  onChanged: (v) {
                    item.discountRate = v ?? 0;
                    onChanged();
                  },
                  decoration: const InputDecoration(labelText: 'İndirim', isDense: true),
                ),
              ),
              const Gap(8),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _calcLineTotal(item),
                    textAlign: TextAlign.end,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _calcLineTotal(_ItemDraft item) {
    final qty = item.quantity ?? 0;
    final price = item.unitPrice ?? 0;
    final base = qty * price;
    final afterDiscount = base * (1 - item.discountRate / 100);
    final total = afterDiscount * (1 + item.taxRate / 100);
    return NumberFormat.currency(locale: 'tr_TR', symbol: '', decimalDigits: 2).format(total);
  }
}

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.label, required this.value, this.isTotal = false});

  final String label;
  final String value;
  final bool isTotal;

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
                ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: isTotal ? FontWeight.w700 : FontWeight.w600,
                  fontSize: isTotal ? 18 : null,
                ),
          ),
        ],
      ),
    );
  }
}
