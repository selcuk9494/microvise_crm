import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/format/app_date_time.dart';
import '../../core/format/search_normalize.dart';
import '../../core/ui/app_card.dart';
import '../billing/application_form_invoice_link.dart';
import '../customers/customer_form_dialog.dart';
import '../customers/customer_model.dart';
import '../customers/customer_select_field.dart';
import '../customers/customers_providers.dart';
import '../definitions/definitions_screen.dart';
import '../invoices/invoice_issue_kind.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import '../products/products_screen.dart'
    show issuedLinesProvider, issuedLicensesProvider;
import '../work_orders/currency_service.dart';
import 'e_invoice_screen.dart';

const _invoiceCurrencies = ['TRY', 'USD', 'EUR', 'GBP'];
const _unitOptions = ['Adet', 'Kg', 'Lt', 'Mt', 'Saat'];

String _currencyLabel(String code) {
  switch (code) {
    case 'TRY':
      return 'TL';
    case 'USD':
      return 'USD';
    case 'EUR':
      return 'EUR';
    case 'GBP':
      return 'GBP';
    default:
      return code;
  }
}

String _currencySymbol(String currency) {
  switch (currency) {
    case 'TRY':
      return '₺';
    case 'USD':
      return '\$';
    case 'EUR':
      return '€';
    case 'GBP':
      return '£';
    default:
      return '$currency ';
  }
}

/// Maps free-form / API unit labels onto the invoice dropdown values.
/// Empty or unknown units become **Adet** so the Birim field is never blank.
String _coerceUnit(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return 'Adet';
  for (final option in _unitOptions) {
    if (option.toLowerCase() == raw.toLowerCase()) return option;
  }
  switch (raw.toUpperCase()) {
    case 'AD':
    case 'ADS':
    case 'PCS':
    case 'PIECE':
    case 'PIECES':
    case 'C62':
      return 'Adet';
    case 'KG':
    case 'KILO':
    case 'KILOGRAM':
    case 'KGM':
      return 'Kg';
    case 'LT':
    case 'L':
    case 'LITRE':
    case 'LITER':
    case 'LTR':
      return 'Lt';
    case 'MT':
    case 'M':
    case 'METRE':
    case 'METER':
    case 'MTR':
      return 'Mt';
    case 'SAAT':
    case 'HOUR':
    case 'HOURS':
    case 'HUR':
      return 'Saat';
    default:
      return 'Adet';
  }
}

List<DropdownMenuItem<String>> _unitDropdownItems() => [
  for (final unit in _unitOptions)
    DropdownMenuItem(value: unit, child: Text(unit)),
];

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
  final _irsaliyeNoController = TextEditingController();
  final _poNumberController = TextEditingController();
  final _exchangeRateController = TextEditingController(text: '1');
  final _items = <_EInvoiceItemDraft>[_EInvoiceItemDraft()];

  String? _customerId;
  DateTime _invoiceDate = normalizeAppDate(DateTime.now());
  DateTime? _dueDate = normalizeAppDate(DateTime.now());
  DateTime? _irsaliyeTarihi;
  late String _currency;
  double _exchangeRate = 1;
  bool _pricesIncludeVat = false;
  bool _saving = false;
  bool _sendAfterSave = false;
  Map<String, double> _rates = const {};

  bool get _isSales => widget.invoiceType == 'sales';
  bool get _isEditing => widget.initialInvoice != null;

  double get _subtotal =>
      _items.fold(0, (sum, item) => sum + item.subtotal(_pricesIncludeVat));
  double get _discountTotal => _items.fold(
    0,
    (sum, item) => sum + item.discountAmount(_pricesIncludeVat),
  );
  double get _taxTotal =>
      _items.fold(0, (sum, item) => sum + item.taxAmount(_pricesIncludeVat));
  double get _grandTotal => _subtotal - _discountTotal + _taxTotal;

  @override
  void initState() {
    super.initState();
    final invoice = widget.initialInvoice;
    if (invoice != null) {
      _customerId = invoice.customerId;
      _invoiceDate = normalizeAppDate(invoice.invoiceDate);
      _dueDate = invoice.dueDate == null
          ? null
          : normalizeAppDate(invoice.dueDate!);
      _irsaliyeNoController.text = invoice.irsaliyeNo ?? '';
      _irsaliyeTarihi = invoice.irsaliyeTarihi;
      _poNumberController.text = invoice.poNumber ?? '';
      _currency = invoice.currency;
      _exchangeRate = invoice.exchangeRate;
      _pricesIncludeVat = invoice.pricesIncludeVat;
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
              : invoice.items.map(
                  (item) => _EInvoiceItemDraft.fromInvoiceItem(
                    item,
                    pricesIncludeVat: invoice.pricesIncludeVat,
                  ),
                ),
        );
    } else {
      _currency = _isSales ? 'USD' : 'TRY';
    }
    _loadRates();
  }

  Future<void> _loadRates() async {
    final apiClient = ref.read(apiClientProvider);
    final rates = await CurrencyService.getExchangeRates(apiClient: apiClient);
    if (!mounted) return;
    setState(() {
      _rates = rates;
      if (!_isEditing && _currency != 'TRY') {
        _exchangeRate = rates[_currency] ?? _exchangeRate;
        _exchangeRateController.text = _exchangeRate.toStringAsFixed(4);
      }
    });
  }

  /// Kaydetmeden önce döviz kurunun güncel olduğundan emin ol.
  Future<void> _ensureCurrentExchangeRate() async {
    if (_currency == 'TRY') {
      _exchangeRate = 1;
      _exchangeRateController.text = '1';
      return;
    }
    final typed = _parseDecimal(_exchangeRateController.text);
    final autoRate = _rates[_currency];
    final looksManual =
        typed > 1 &&
        autoRate != null &&
        autoRate > 0 &&
        (typed - autoRate).abs() / autoRate > 0.0005;
    // Düzenleme veya elle değiştirilmiş kur: kullanıcı değerini koru.
    if (_isEditing || looksManual) {
      if (typed > 0) _exchangeRate = typed;
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    final rates = await CurrencyService.getExchangeRates(apiClient: apiClient);
    if (!mounted) return;
    final fresh = rates[_currency];
    setState(() {
      _rates = rates;
      if (fresh != null && fresh > 0) {
        _exchangeRate = fresh;
        _exchangeRateController.text = fresh.toStringAsFixed(4);
      } else if (typed > 1) {
        _exchangeRate = typed;
      }
    });
  }

  void _setCurrency(String value) {
    setState(() {
      _currency = value;
      _exchangeRate = value == 'TRY' ? 1 : (_rates[value] ?? 1);
      _exchangeRateController.text = _exchangeRate.toStringAsFixed(
        value == 'TRY' ? 0 : 4,
      );
    });
    if (value != 'TRY' && ((_rates[value] ?? 0) <= 1)) {
      _loadRates();
    }
  }

  void _setPricesIncludeVat(bool value) {
    if (value == _pricesIncludeVat) return;
    setState(() {
      for (final item in _items) {
        item.convertPriceDisplay(
          fromIncludeVat: _pricesIncludeVat,
          toIncludeVat: value,
        );
      }
      _pricesIncludeVat = value;
    });
  }

  @override
  void dispose() {
    _notesController.dispose();
    _irsaliyeNoController.dispose();
    _poNumberController.dispose();
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
    final eInvoiceSettings =
        ref.watch(eInvoiceSettingsProvider).value ?? const {};
    final isProduction =
        (eInvoiceSettings['environment'] ?? 'test').toString() == 'production';
    final apiEnvironmentLabel = isProduction ? 'canlı' : 'test';
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobileLayout = screenWidth < 980;
    final title = isMobileLayout
        ? (_isEditing
              ? (_isSales ? 'Faturayı Düzenle' : 'Alış Düzenle')
              : (_isSales ? 'Yeni Satış' : 'Yeni Alış'))
        : '${_isEditing ? 'Düzenle - ' : ''}${_isSales ? 'Satış E-Faturası' : 'Alış Faturası'}';

    final summary = _SummaryPanel(
      subtotal: _subtotal,
      discountTotal: _discountTotal,
      taxTotal: _taxTotal,
      grandTotal: _grandTotal,
      currency: _currency,
      pricesIncludeVat: _pricesIncludeVat,
      sendAfterSave: _sendAfterSave,
      isSales: _isSales,
      saving: _saving,
      onPricesIncludeVatChanged: _setPricesIncludeVat,
      onSendAfterSaveChanged: (value) => setState(() => _sendAfterSave = value),
      onSaveDraft: () => _save(status: 'draft'),
      onSaveOpen: () => _save(status: 'open'),
      apiEnvironmentLabel: apiEnvironmentLabel,
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        title: Text(title),
        actions: [
          if (!isMobileLayout) ...[
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
                  : const Icon(LucideIcons.save, size: 18),
              label: const Text('Kaydet'),
            ),
            const Gap(12),
          ],
        ],
      ),
      bottomNavigationBar: isMobileLayout
          ? _MobileSaveBar(
              grandTotal: _grandTotal,
              currency: _currency,
              sendAfterSave: _sendAfterSave,
              isSales: _isSales,
              saving: _saving,
              apiEnvironmentLabel: apiEnvironmentLabel,
              onSendAfterSaveChanged: (value) =>
                  setState(() => _sendAfterSave = value),
              onSaveDraft: () => _save(status: 'draft'),
              onSaveOpen: () => _save(status: 'open'),
            )
          : null,
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;

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
                    onCustomerSelected: (customer) =>
                        setState(() => _customerId = customer?.id),
                    onCreateCustomer: _createCustomer,
                    onInvoiceDateChanged: (value) =>
                        setState(() => _invoiceDate = normalizeAppDate(value)),
                    onDueDateChanged: (value) => setState(
                      () => _dueDate = value == null
                          ? null
                          : normalizeAppDate(value),
                    ),
                    onCurrencyChanged: _setCurrency,
                    onExchangeRateChanged: (value) =>
                        _exchangeRate = _parseDecimal(value),
                  ),
                  const Gap(14),
                  _DesktopItemsTable(
                    items: _items,
                    productsAsync: productsAsync,
                    taxRatesAsync: taxRatesAsync,
                    currency: _currency,
                    pricesIncludeVat: _pricesIncludeVat,
                    isSales: _isSales,
                    onChanged: () => setState(() {}),
                    onProductSearch: () async {
                      final products =
                          await ref.read(productsProvider(null).future);
                      if (!mounted) return;
                      await _addProducts(products);
                    },
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
                  _DispatchCard(
                    numberController: _irsaliyeNoController,
                    poController: _poNumberController,
                    date: _irsaliyeTarihi,
                    invoiceDate: _invoiceDate,
                    onDateChanged: (value) =>
                        setState(() => _irsaliyeTarihi = value),
                    onClear: () => setState(() {
                      _irsaliyeNoController.clear();
                      _irsaliyeTarihi = null;
                    }),
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

            final dateFormat = DateFormat('dd.MM.yyyy');
            return ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '1. Cari ve tarih',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      const Gap(10),
                      customersAsync.when(
                        data: (customers) => CustomerSelectField(
                          customers: customers,
                          selectedCustomerId: _customerId,
                          label: _isSales ? 'Müşteri' : 'Tedarikçi',
                          onSelected: (customer) =>
                              setState(() => _customerId = customer?.id),
                          onCreateNew: _createCustomer,
                        ),
                        loading: () => const LinearProgressIndicator(),
                        error: (_, _) =>
                            const Text('Cari listesi yüklenemedi.'),
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
                            child: _DateField(
                              label: 'Fatura Tarihi',
                              value: dateFormat.format(_invoiceDate),
                              initialDate: _invoiceDate,
                              onPicked: (value) => setState(
                                () => _invoiceDate = normalizeAppDate(value),
                              ),
                            ),
                          ),
                          const Gap(8),
                          SizedBox(
                            width: 118,
                            child: DropdownButtonFormField<String>(
                              initialValue:
                                  _invoiceCurrencies.contains(_currency)
                                  ? _currency
                                  : 'USD',
                              isExpanded: true,
                              items: [
                                for (final code in _invoiceCurrencies)
                                  DropdownMenuItem(
                                    value: code,
                                    child: Text(_currencyLabel(code)),
                                  ),
                              ],
                              onChanged: (value) => _setCurrency(
                                value ?? (_isSales ? 'USD' : 'TRY'),
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Para',
                                isDense: true,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: const Text('KDV dahil'),
                        subtitle: Text(
                          _pricesIncludeVat
                              ? 'Birim fiyatlar KDV dahil girilir'
                              : 'Birim fiyatlar KDV hariç girilir',
                        ),
                        value: _pricesIncludeVat,
                        onChanged: _setPricesIncludeVat,
                      ),
                      if (_currency != 'TRY') ...[
                        const Gap(8),
                        TextFormField(
                          controller: _exchangeRateController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Kur',
                            isDense: true,
                          ),
                          onChanged: (value) =>
                              _exchangeRate = _parseDecimal(value),
                          validator: (value) => _parseDecimal(value ?? '') <= 0
                              ? 'Kur gerekli'
                              : null,
                        ),
                      ],
                    ],
                  ),
                ),
                const Gap(10),
                _MobileItemsCard(
                  items: _items,
                  productsAsync: productsAsync,
                  taxRatesAsync: taxRatesAsync,
                  currency: _currency,
                  pricesIncludeVat: _pricesIncludeVat,
                  isSales: _isSales,
                  onChanged: () => setState(() {}),
                  onAddBlank: () =>
                      setState(() => _items.add(_EInvoiceItemDraft())),
                  onAddFromStock: () async {
                    final products =
                        await ref.read(productsProvider(null).future);
                    if (!mounted) return;
                    await _addProducts(products);
                  },
                  onRemove: (index) {
                    setState(() {
                      _items[index].dispose();
                      _items.removeAt(index);
                    });
                  },
                ),
                const Gap(10),
                AppCard(
                  padding: EdgeInsets.zero,
                  child: Theme(
                    data: Theme.of(
                      context,
                    ).copyWith(dividerColor: Colors.transparent),
                    child: ExpansionTile(
                      tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                      title: Text(
                        '3. Ek bilgiler (isteğe bağlı)',
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      subtitle: Text(() {
                        final bits = <String>[
                          if (_dueDate != null)
                            'Vade ${dateFormat.format(_dueDate!)}',
                          if (_irsaliyeNoController.text.trim().isNotEmpty)
                            'İrsaliye',
                          if (_poNumberController.text.trim().isNotEmpty) 'PO',
                          if (_notesController.text.trim().isNotEmpty) 'Not',
                        ];
                        return bits.isEmpty
                            ? 'Vade, irsaliye, PO, not'
                            : bits.join(' · ');
                      }(), style: Theme.of(context).textTheme.bodySmall),
                      children: [
                        _DateField(
                          label: 'Vade Tarihi',
                          value: _dueDate == null
                              ? 'Seçilmedi'
                              : dateFormat.format(_dueDate!),
                          initialDate:
                              _dueDate ??
                              _invoiceDate.add(const Duration(days: 30)),
                          onPicked: (value) => setState(
                            () => _dueDate = normalizeAppDate(value),
                          ),
                        ),
                        const Gap(8),
                        TextFormField(
                          controller: _irsaliyeNoController,
                          decoration: const InputDecoration(
                            labelText: 'İrsaliye No',
                            isDense: true,
                          ),
                          validator: (value) {
                            final hasNumber = (value ?? '').trim().isNotEmpty;
                            if (hasNumber != (_irsaliyeTarihi != null)) {
                              return 'Numara ve tarih birlikte girilmeli';
                            }
                            return null;
                          },
                        ),
                        const Gap(8),
                        _DateField(
                          label: 'İrsaliye Tarihi',
                          value: _irsaliyeTarihi == null
                              ? 'Seçilmedi'
                              : dateFormat.format(_irsaliyeTarihi!),
                          initialDate: _irsaliyeTarihi ?? _invoiceDate,
                          onPicked: (value) =>
                              setState(() => _irsaliyeTarihi = value),
                        ),
                        const Gap(8),
                        TextField(
                          controller: _poNumberController,
                          decoration: const InputDecoration(
                            labelText: 'PO No',
                            isDense: true,
                          ),
                        ),
                        const Gap(8),
                        TextField(
                          controller: _notesController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Not',
                            isDense: true,
                          ),
                        ),
                        if (_irsaliyeTarihi != null ||
                            _irsaliyeNoController.text.trim().isNotEmpty)
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(
                              onPressed: () => setState(() {
                                _irsaliyeNoController.clear();
                                _irsaliyeTarihi = null;
                              }),
                              child: const Text('İrsaliyeyi temizle'),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
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

    String? sendBranchCode;
    if (_sendAfterSave && _isSales && status != 'draft') {
      final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
      sendBranchCode = await pickEInvoiceBranchForSend(
        context: context,
        settings: settings,
      );
      if (sendBranchCode == null || !mounted) return;
    }

    setState(() => _saving = true);
    try {
      await _ensureCurrentExchangeRate();
      if (!mounted) return;

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
            'prices_include_vat': _pricesIncludeVat,
            'status': status,
            'notes': _notesController.text.trim().isEmpty
                ? null
                : _notesController.text.trim(),
            'irsaliye_no': _irsaliyeNoController.text.trim().isEmpty
                ? null
                : _irsaliyeNoController.text.trim(),
            'irsaliye_tarihi': _irsaliyeTarihi == null
                ? null
                : _dateIso(_irsaliyeTarihi!),
            'po_number': _poNumberController.text.trim().isEmpty
                ? null
                : _poNumberController.text.trim(),
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
                'notes': validItems[i].notes.isEmpty
                    ? null
                    : validItems[i].notes,
                'quantity': validItems[i].quantity,
                'unit': validItems[i].unit,
                'unit_price': _round2(
                  validItems[i].exclusiveUnitPrice(_pricesIncludeVat),
                ),
                'tax_rate': validItems[i].taxRate,
                'tax_amount': validItems[i].taxAmount(_pricesIncludeVat),
                'discount_rate': validItems[i].discountRate,
                'discount_amount': validItems[i].discountAmount(
                  _pricesIncludeVat,
                ),
                'line_total': validItems[i].lineTotal(_pricesIncludeVat),
                'sort_order': i,
                'special_matrah': false,
                'tax_exemption_code': null,
                'tax_exemption_description': null,
                'item_type': invoiceItemTypeForIssueKind(
                  validItems[i].issueKind,
                ),
              },
          ],
        },
      );

      if (_isSales) {
        await fillInvoiceDeviceNotesFromApplicationForms(
          apiClient,
          invoiceId: invoiceId,
        );
      }

      if (_sendAfterSave && _isSales && status != 'draft') {
        await apiClient.postJson(
          '/e-invoice',
          body: {
            'action': 'send',
            'invoiceId': invoiceId,
            'branchCode': sendBranchCode,
            'requireBranch': true,
          },
        );
      }

      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(eInvoiceSettingsProvider);
      ref.invalidate(issuedLinesProvider);
      ref.invalidate(issuedLicensesProvider);
      if (!mounted) return;
      final issuedHats = validItems
          .where((item) => item.issueKind == 'line')
          .fold<int>(0, (sum, item) => sum + item.quantity.round().clamp(1, 999));
      final issuedGmp3 = validItems
          .where((item) => item.issueKind == 'gmp3')
          .fold<int>(0, (sum, item) => sum + item.quantity.round().clamp(1, 999));
      final issuedNote = !_isSales || (issuedHats == 0 && issuedGmp3 == 0)
          ? ''
          : [
              if (issuedHats > 0) '$issuedHats hat',
              if (issuedGmp3 > 0) '$issuedGmp3 GMP3',
            ].join(' ve ');
      _showMessage(
        _sendAfterSave && _isSales && status != 'draft'
            ? 'Fatura kaydedildi ve '
                  '${(ref.read(eInvoiceSettingsProvider).value?['environment'] ?? 'test') == 'production' ? 'canlı' : 'test'} '
                  'API’ye gönderildi.'
                  '${issuedNote.isEmpty ? '' : ' $issuedNote listeye işlendi.'}'
            : issuedNote.isEmpty
            ? 'Fatura kaydedildi.'
            : 'Fatura kaydedildi. $issuedNote listeye işlendi.',
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

  Future<Customer?> _createCustomer() async {
    final createdId = await showCreateCustomerDialog(context);
    if (createdId == null || !mounted) return null;
    ref.invalidate(customersLookupProvider);
    ref.invalidate(customersProvider);
    final refreshed = await ref.read(customersLookupProvider.future);
    for (final customer in refreshed) {
      if (customer.id == createdId) {
        setState(() => _customerId = customer.id);
        return customer;
      }
    }
    return null;
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
        _items.add(
          _EInvoiceItemDraft.fromProduct(
            product,
            isSales: _isSales,
            pricesIncludeVat: _pricesIncludeVat,
          ),
        );
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
    required this.onCustomerSelected,
    required this.onCreateCustomer,
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
  final ValueChanged<Customer?> onCustomerSelected;
  final Future<Customer?> Function() onCreateCustomer;
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
    final dateFormat = DateFormat('dd.MM.yyyy');

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
                          style: TextStyle(color: AppTheme.primary),
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
                              data: (customers) => CustomerSelectField(
                                customers: customers,
                                selectedCustomerId: selectedCustomerId,
                                label: isSales ? 'Müşteri' : 'Tedarikçi',
                                onSelected: onCustomerSelected,
                                onCreateNew: onCreateCustomer,
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
                                    initialValue:
                                        _invoiceCurrencies.contains(currency)
                                        ? currency
                                        : 'USD',
                                    items: [
                                      for (final code in _invoiceCurrencies)
                                        DropdownMenuItem(
                                          value: code,
                                          child: Text(_currencyLabel(code)),
                                        ),
                                    ],
                                    onChanged: (value) =>
                                        onCurrencyChanged(value ?? currency),
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

class _AddressInfoPanel extends StatelessWidget {
  const _AddressInfoPanel({required this.customer});

  final Customer? customer;

  @override
  Widget build(BuildContext context) {
    final address = customer?.address?.trim();
    final city = customer?.city?.trim();
    final tax = customer?.vkn?.trim();

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        border: Border(left: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(LucideIcons.building2, size: 18, color: AppTheme.primary),
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
    required this.pricesIncludeVat,
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
  final bool pricesIncludeVat;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback onProductSearch;
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
                  icon: LucideIcons.list,
                  label: 'Öğeler',
                  selected: true,
                ),
                const Spacer(),
                OutlinedButton.icon(
                  onPressed: onProductSearch,
                  icon: const Icon(LucideIcons.search, size: 18),
                  label: const Text('Ürün Ara / Çoklu Ekle'),
                ),
                const Gap(8),
                IconButton.filled(
                  tooltip: 'Boş satır ekle',
                  onPressed: onAdd,
                  icon: const Icon(LucideIcons.plus, size: 20),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Builder(
            builder: (context) {
              final products = productsAsync.value ?? const <Product>[];
              final taxRates = _availableTaxRates(taxRatesAsync, items);
              return Column(
                children: [
                  if (productsAsync.isLoading && products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(18),
                      child: LinearProgressIndicator(),
                    ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 1160),
                      child: Column(
                        children: [
                          _InvoiceTableHeader(pricesIncludeVat: pricesIncludeVat),
                          for (var i = 0; i < items.length; i++)
                            _InvoiceTableRow(
                              key: ObjectKey(items[i]),
                              item: items[i],
                              products: products,
                              taxRates: taxRates,
                              currency: currency,
                              pricesIncludeVat: pricesIncludeVat,
                              isSales: isSales,
                              onChanged: onChanged,
                              onRemove: () => onRemove(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            },
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
    final color = selected ? AppTheme.primary : AppTheme.textSoft;
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
  const _InvoiceTableHeader({required this.pricesIncludeVat});

  final bool pricesIncludeVat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      color: AppTheme.tableHeaderBg,
      child: Row(
        children: [
          const _HeaderCell('Ürün', width: 330),
          const _HeaderCell('Miktar', width: 92),
          const _HeaderCell('Birim', width: 104),
          _HeaderCell(
            pricesIncludeVat ? 'Birim Fiyatı (KDV dahil)' : 'Birim Fiyatı',
            width: 130,
          ),
          const _HeaderCell('İndirim', width: 104),
          const _HeaderCell('Vergi', width: 104),
          const _HeaderCell('Toplam', width: 160),
          const _HeaderCell('', width: 62),
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
          ).textTheme.labelLarge?.copyWith(color: AppTheme.textSoft),
        ),
      ),
    );
  }
}

class _InvoiceTableRow extends StatelessWidget {
  const _InvoiceTableRow({
    super.key,
    required this.item,
    required this.products,
    required this.taxRates,
    required this.currency,
    required this.pricesIncludeVat,
    required this.isSales,
    required this.onChanged,
    required this.onRemove,
  });

  final _EInvoiceItemDraft item;
  final List<Product> products;
  final List<double> taxRates;
  final String currency;
  final bool pricesIncludeVat;
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
    final unit = _coerceUnit(item.unit);
    final taxRate = _taxInitialValue(item.taxRate, taxRates);
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                                (product.code ?? '').toLowerCase().contains(
                                  query,
                                ),
                          )
                          .take(12);
                    },
                    displayStringForOption: (product) => product.name,
                    onSelected: (product) {
                      item.applyProduct(
                        product,
                        isSales: isSales,
                        pricesIncludeVat: pricesIncludeVat,
                      );
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
                          hintText: 'Ürün seçin',
                        ),
                        validator: (value) =>
                            (value ?? '').trim().isEmpty ? 'Gerekli' : null,
                        onChanged: (value) {
                          item.productId = null;
                          item.descriptionController.text = value;
                          item.detectIssueKindFromDescription();
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: DropdownButtonFormField<String>(
                    key: ValueKey('unit-${identityHashCode(item)}-$unit'),
                    initialValue: unit,
                    isExpanded: true,
                    isDense: true,
                    items: _unitDropdownItems(),
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    onChanged: (value) {
                      item.unit = _coerceUnit(value);
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: TextFormField(
                    initialValue: item.discountRate.toStringAsFixed(0),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      isDense: true,
                      suffixText: '%',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
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
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: DropdownButtonFormField<double>(
                    key: ValueKey('tax-${identityHashCode(item)}-$taxRate'),
                    initialValue: taxRate,
                    isExpanded: true,
                    isDense: true,
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      for (final rate in taxRates)
                        DropdownMenuItem(
                          value: rate,
                          child: Text(_taxLabel(rate)),
                        ),
                    ],
                    onChanged: (value) {
                      item.taxRate = value ?? taxRate;
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
                        money.format(item.lineTotal(pricesIncludeVat)),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: AppTheme.success,
                        ),
                      ),
                      Text(
                        'KDV ${money.format(item.taxAmount(pricesIncludeVat))}',
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
                  icon: const Icon(LucideIcons.trash2),
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                if (isSales) ...[
                  _IssueKindChips(
                    kind: item.issueKind,
                    onChanged: (kind) {
                      item.setIssueKind(kind);
                      onChanged();
                    },
                  ),
                  const Gap(10),
                ],
                Expanded(
                  child: SizedBox(
                    width: 694,
                    child: TextFormField(
                      controller: item.notesController,
                      style: Theme.of(context).textTheme.bodySmall,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: item.issueKind == 'line'
                            ? 'Hat no / SIM (isteğe bağlı)'
                            : item.issueKind == 'gmp3'
                            ? 'Sicil no (isteğe bağlı)'
                            : 'Kalem açıklama (isteğe bağlı)',
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (_) {
                        item.detectIssueKindFromDescription();
                        onChanged();
                      },
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

class _TableTextField extends StatefulWidget {
  const _TableTextField({
    required this.width,
    required this.controller,
    required this.onChanged,
  });

  final double width;
  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  State<_TableTextField> createState() => _TableTextFieldState();
}

class _TableTextFieldState extends State<_TableTextField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_selectAllOnFocus);
  }

  void _selectAllOnFocus() {
    if (!_focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus || !mounted) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_selectAllOnFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onTap: () {
            widget.controller.selection = TextSelection(
              baseOffset: 0,
              extentOffset: widget.controller.text.length,
            );
          },
          onChanged: (_) => widget.onChanged(),
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
                prefixIcon: Icon(LucideIcons.search),
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
                                ? LucideIcons.penTool
                                : LucideIcons.package,
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
          icon: const Icon(LucideIcons.plus, size: 18),
          label: Text('Seçilenleri Ekle (${_selectedIds.length})'),
        ),
      ],
    );
  }
}

class _DispatchCard extends StatelessWidget {
  const _DispatchCard({
    required this.numberController,
    required this.poController,
    required this.date,
    required this.invoiceDate,
    required this.onDateChanged,
    required this.onClear,
  });

  final TextEditingController numberController;
  final TextEditingController poController;
  final DateTime? date;
  final DateTime invoiceDate;
  final ValueChanged<DateTime> onDateChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          SizedBox(
            width: 260,
            child: TextFormField(
              controller: numberController,
              decoration: const InputDecoration(
                labelText: 'İrsaliye Numarası',
                hintText: 'Mal satışı varsa girin',
              ),
              validator: (value) {
                final hasNumber = (value ?? '').trim().isNotEmpty;
                if (hasNumber != (date != null)) {
                  return 'Numara ve tarih birlikte girilmeli';
                }
                return null;
              },
            ),
          ),
          SizedBox(
            width: 220,
            child: _DateField(
              label: 'İrsaliye Tarihi',
              value: date == null ? 'Seçilmedi' : dateFormat.format(date!),
              initialDate: date ?? invoiceDate,
              onPicked: onDateChanged,
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(
              controller: poController,
              decoration: const InputDecoration(
                labelText: 'PO No',
                hintText: 'Müşteri sipariş no',
              ),
            ),
          ),
          if (date != null || numberController.text.trim().isNotEmpty)
            TextButton.icon(
              onPressed: onClear,
              icon: const Icon(LucideIcons.eraser),
              label: const Text('İrsaliyeyi temizle'),
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

class _ItemEditor extends StatelessWidget {
  const _ItemEditor({
    super.key,
    required this.item,
    required this.products,
    required this.taxRates,
    required this.currency,
    required this.pricesIncludeVat,
    required this.isSales,
    required this.onChanged,
    required this.onRemove,
  });

  final _EInvoiceItemDraft item;
  final List<Product> products;
  final List<double> taxRates;
  final String currency;
  final bool pricesIncludeVat;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: _currencySymbol(currency),
      decimalDigits: 2,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final fieldGap = compact ? 8.0 : 10.0;
        final inputDecoration = const InputDecoration(
          isDense: true,
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        );
        final productField = Autocomplete<Product>(
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
            item.applyProduct(
              product,
              isSales: isSales,
              pricesIncludeVat: pricesIncludeVat,
            );
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
              decoration: inputDecoration.copyWith(
                labelText: 'Stok/Hizmet',
                hintText: 'Ürün, hizmet veya açıklama',
              ),
              validator: (value) =>
                  (value ?? '').trim().isEmpty ? 'Kalem adı gerekli' : null,
              onChanged: (value) {
                item.productId = null;
                item.descriptionController.text = value;
                item.detectIssueKindFromDescription();
                onChanged();
              },
            );
          },
        );
        final notesField = TextFormField(
          controller: item.notesController,
          decoration: inputDecoration.copyWith(
            labelText: 'Kalem açıklama',
            hintText: item.issueKind == 'line'
                ? 'Hat no / SIM (isteğe bağlı)'
                : item.issueKind == 'gmp3'
                ? 'Sicil no (isteğe bağlı)'
                : 'PDF / Maliye / SAP (isteğe bağlı)',
          ),
          onChanged: (_) {
            item.detectIssueKindFromDescription();
            onChanged();
          },
        );
        final quantityField = _SelectAllNumberField(
          controller: item.quantityController,
          decoration: inputDecoration.copyWith(labelText: 'Miktar'),
          onChanged: (_) => onChanged(),
          validator: (value) =>
              _parseDecimal(value ?? '') <= 0 ? 'Gerekli' : null,
        );
        final priceField = _SelectAllNumberField(
          controller: item.priceController,
          decoration: inputDecoration.copyWith(
            labelText: pricesIncludeVat ? 'Fiyat (KDV dahil)' : 'Fiyat',
          ),
          onChanged: (_) => onChanged(),
        );
        final unit = _coerceUnit(item.unit);
        final taxRate = _taxInitialValue(item.taxRate, taxRates);
        final unitField = DropdownButtonFormField<String>(
          key: ValueKey('m-unit-${identityHashCode(item)}-$unit'),
          initialValue: unit,
          isExpanded: true,
          items: _unitDropdownItems(),
          onChanged: (value) {
            item.unit = _coerceUnit(value);
            onChanged();
          },
          decoration: inputDecoration.copyWith(labelText: 'Birim'),
        );
        final taxField = DropdownButtonFormField<double>(
          key: ValueKey('m-tax-${identityHashCode(item)}-$taxRate'),
          initialValue: taxRate,
          isExpanded: true,
          items: [
            for (final rate in taxRates)
              DropdownMenuItem(value: rate, child: Text(_taxLabel(rate))),
          ],
          onChanged: (value) {
            item.taxRate = value ?? taxRate;
            onChanged();
          },
          decoration: inputDecoration.copyWith(labelText: 'KDV'),
        );
        final discountField = TextFormField(
          initialValue: item.discountRate.toStringAsFixed(0),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: inputDecoration.copyWith(labelText: 'İndirim %'),
          onChanged: (value) {
            item.discountRate = _parseDecimal(value);
            onChanged();
          },
        );
        final totalField = _LineTotal(
          label: compact ? 'Toplam' : 'Kalem Toplamı',
          value: money.format(item.lineTotal(pricesIncludeVat)),
          subtitle: 'KDV ${money.format(item.taxAmount(pricesIncludeVat))}',
          dense: compact,
        );

        Widget twoUp(Widget first, Widget second) {
          return Row(
            children: [
              Expanded(child: first),
              Gap(fieldGap),
              Expanded(child: second),
            ],
          );
        }

        return DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            border: Border.all(color: AppTheme.border),
          ),
          child: Padding(
            padding: EdgeInsets.all(compact ? 10 : 12),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: productField),
                          IconButton(
                            tooltip: 'Kalemi sil',
                            visualDensity: VisualDensity.compact,
                            onPressed: onRemove,
                            icon: const Icon(LucideIcons.trash2),
                          ),
                        ],
                      ),
                      Gap(fieldGap),
                      if (isSales) ...[
                        _IssueKindChips(
                          kind: item.issueKind,
                          onChanged: (kind) {
                            item.setIssueKind(kind);
                            onChanged();
                          },
                        ),
                        Gap(fieldGap),
                      ],
                      notesField,
                      Gap(fieldGap),
                      Row(
                        children: [
                          Expanded(flex: 2, child: quantityField),
                          Gap(fieldGap),
                          Expanded(flex: 3, child: priceField),
                          Gap(fieldGap),
                          Expanded(flex: 3, child: totalField),
                        ],
                      ),
                      Theme(
                        data: Theme.of(
                          context,
                        ).copyWith(dividerColor: Colors.transparent),
                        child: ExpansionTile(
                          tilePadding: EdgeInsets.zero,
                          childrenPadding: EdgeInsets.only(top: fieldGap),
                          visualDensity: VisualDensity.compact,
                          title: Text(
                            'KDV / birim / indirim',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '$unit · ${_taxLabel(taxRate)}'
                            '${item.discountRate > 0 ? ' · %${item.discountRate.toStringAsFixed(0)} indirim' : ''}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          children: [
                            twoUp(unitField, taxField),
                            Gap(fieldGap),
                            discountField,
                          ],
                        ),
                      ),
                    ],
                  )
                : Column(
                    children: [
                      Row(
                        children: [
                          Expanded(flex: 3, child: productField),
                          Gap(fieldGap),
                          SizedBox(width: 90, child: quantityField),
                          Gap(fieldGap),
                          SizedBox(width: 105, child: priceField),
                          IconButton(
                            tooltip: 'Kalemi sil',
                            onPressed: onRemove,
                            icon: const Icon(LucideIcons.trash2),
                          ),
                        ],
                      ),
                      Gap(fieldGap),
                      if (isSales) ...[
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _IssueKindChips(
                            kind: item.issueKind,
                            onChanged: (kind) {
                              item.setIssueKind(kind);
                              onChanged();
                            },
                          ),
                        ),
                        Gap(fieldGap),
                      ],
                      notesField,
                      Gap(fieldGap),
                      Row(
                        children: [
                          SizedBox(width: 120, child: unitField),
                          Gap(fieldGap),
                          SizedBox(width: 120, child: taxField),
                          Gap(fieldGap),
                          SizedBox(width: 120, child: discountField),
                          Gap(fieldGap),
                          SizedBox(width: 170, child: totalField),
                          const Spacer(),
                        ],
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}

class _IssueKindChips extends StatelessWidget {
  const _IssueKindChips({required this.kind, required this.onChanged});

  final String? kind;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Listeye ekle',
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: AppTheme.textSoft),
        ),
        FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: const Text('Hat'),
          selected: kind == 'line',
          onSelected: (selected) => onChanged(selected ? 'line' : null),
        ),
        FilterChip(
          visualDensity: VisualDensity.compact,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          label: const Text('GMP3'),
          selected: kind == 'gmp3',
          onSelected: (selected) => onChanged(selected ? 'gmp3' : null),
        ),
      ],
    );
  }
}

class _LineTotal extends StatelessWidget {
  const _LineTotal({
    required this.label,
    required this.value,
    this.subtitle,
    this.dense = false,
  });

  final String label;
  final String value;
  final String? subtitle;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 7 : 9),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelLarge,
          ),
          if (subtitle != null)
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
        ],
      ),
    );
  }
}

class _MobileItemsCard extends StatelessWidget {
  const _MobileItemsCard({
    required this.items,
    required this.productsAsync,
    required this.taxRatesAsync,
    required this.currency,
    required this.pricesIncludeVat,
    required this.isSales,
    required this.onChanged,
    required this.onAddBlank,
    required this.onAddFromStock,
    required this.onRemove,
  });

  final List<_EInvoiceItemDraft> items;
  final AsyncValue<List<Product>> productsAsync;
  final AsyncValue<List<TaxRate>> taxRatesAsync;
  final String currency;
  final bool pricesIncludeVat;
  final bool isSales;
  final VoidCallback onChanged;
  final VoidCallback onAddBlank;
  final VoidCallback onAddFromStock;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '2. Kalemler',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                '${items.length}',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
          const Gap(8),
          Builder(
            builder: (context) {
              final products = productsAsync.value ?? const <Product>[];
              final taxRates = _availableTaxRates(taxRatesAsync, items);
              return Column(
                children: [
                  if (productsAsync.isLoading && products.isEmpty)
                    const LinearProgressIndicator(),
                  for (var i = 0; i < items.length; i++) ...[
                    _ItemEditor(
                      key: ObjectKey(items[i]),
                      item: items[i],
                      products: products,
                      taxRates: taxRates,
                      currency: currency,
                      pricesIncludeVat: pricesIncludeVat,
                      isSales: isSales,
                      onChanged: onChanged,
                      onRemove: items.length == 1 ? null : () => onRemove(i),
                    ),
                    if (i != items.length - 1) const Gap(8),
                  ],
                ],
              );
            },
          ),
          const Gap(10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddFromStock,
                  icon: const Icon(LucideIcons.package, size: 18),
                  label: const Text('Stoktan'),
                ),
              ),
              const Gap(8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onAddBlank,
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('Satır'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileSaveBar extends StatelessWidget {
  const _MobileSaveBar({
    required this.grandTotal,
    required this.currency,
    required this.sendAfterSave,
    required this.isSales,
    required this.saving,
    required this.apiEnvironmentLabel,
    required this.onSendAfterSaveChanged,
    required this.onSaveDraft,
    required this.onSaveOpen,
  });

  final double grandTotal;
  final String currency;
  final bool sendAfterSave;
  final bool isSales;
  final bool saving;
  final String apiEnvironmentLabel;
  final ValueChanged<bool> onSendAfterSaveChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onSaveOpen;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: _currencySymbol(currency),
      decimalDigits: 2,
    );
    return Material(
      elevation: 8,
      color: AppTheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isSales)
                CheckboxListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                  value: sendAfterSave,
                  onChanged: saving
                      ? null
                      : (value) => onSendAfterSaveChanged(value ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(
                    'Kaydettikten sonra $apiEnvironmentLabel API’ye gönder',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Toplam',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                        Text(
                          money.format(grandTotal),
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: saving ? null : onSaveDraft,
                    child: const Text('Taslak'),
                  ),
                  const Gap(4),
                  FilledButton(
                    onPressed: saving ? null : onSaveOpen,
                    child: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kaydet'),
                  ),
                ],
              ),
            ],
          ),
        ),
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
    required this.pricesIncludeVat,
    required this.sendAfterSave,
    required this.isSales,
    required this.saving,
    required this.onPricesIncludeVatChanged,
    required this.onSendAfterSaveChanged,
    required this.onSaveDraft,
    required this.onSaveOpen,
    required this.apiEnvironmentLabel,
  });

  final double subtotal;
  final double discountTotal;
  final double taxTotal;
  final double grandTotal;
  final String currency;
  final bool pricesIncludeVat;
  final bool sendAfterSave;
  final bool isSales;
  final bool saving;
  final ValueChanged<bool> onPricesIncludeVatChanged;
  final ValueChanged<bool> onSendAfterSaveChanged;
  final VoidCallback onSaveDraft;
  final VoidCallback onSaveOpen;
  final String apiEnvironmentLabel;

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: _currencySymbol(currency),
      decimalDigits: 2,
    );
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Fatura Özeti', style: Theme.of(context).textTheme.titleMedium),
          const Gap(8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('KDV dahil'),
            subtitle: Text(
              pricesIncludeVat
                  ? 'Birim fiyatlar KDV dahil girilir'
                  : 'Birim fiyatlar KDV hariç girilir',
            ),
            value: pricesIncludeVat,
            onChanged: saving ? null : onPricesIncludeVatChanged,
          ),
          const Gap(6),
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
              title: Text('Kaydet ve $apiEnvironmentLabel API’ye gönder'),
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
      notesController = TextEditingController(),
      quantityController = TextEditingController(text: '1'),
      priceController = TextEditingController(text: '0');

  _EInvoiceItemDraft.fromProduct(
    Product product, {
    required bool isSales,
    required bool pricesIncludeVat,
  }) : descriptionController = TextEditingController(text: product.name),
       notesController = TextEditingController(),
       quantityController = TextEditingController(text: '1'),
       priceController = TextEditingController(
         text: _displayUnitPrice(
           isSales ? product.salePrice : product.purchasePrice,
           taxRate: product.taxRate,
           pricesIncludeVat: pricesIncludeVat,
         ).toStringAsFixed(2),
       ),
       productId = product.id,
       _unit = _coerceUnit(product.unit),
       taxRate = product.taxRate,
       issueKind = detectInvoiceIssueKind(
         description: product.name,
         productName: product.name,
         productCode: product.code,
         productCategory: [
           product.category,
           product.akinsoftGroup,
           product.akinsoftSubGroup,
         ].whereType<String>().join(' '),
       );

  _EInvoiceItemDraft.fromInvoiceItem(
    InvoiceItem item, {
    required bool pricesIncludeVat,
  }) : descriptionController = TextEditingController(text: item.description),
       notesController = TextEditingController(text: item.notes ?? ''),
       quantityController = TextEditingController(
         text: item.quantity.toStringAsFixed(
           item.quantity.truncateToDouble() == item.quantity ? 0 : 2,
         ),
       ),
       priceController = TextEditingController(
         text: _displayUnitPrice(
           item.unitPrice,
           taxRate: item.taxRate,
           pricesIncludeVat: pricesIncludeVat,
         ).toStringAsFixed(2),
       ),
       productId = item.productId,
       _unit = _coerceUnit(item.unit),
       taxRate = item.taxRate,
       discountRate = item.discountRate,
       issueKind =
           issueKindFromInvoiceItemType(item.itemType) ??
           detectInvoiceIssueKind(
             description: item.description,
             notes: item.notes,
           ),
       _issueKindManual = issueKindFromInvoiceItemType(item.itemType) != null;

  final TextEditingController descriptionController;
  final TextEditingController notesController;
  final TextEditingController quantityController;
  final TextEditingController priceController;
  String? productId;
  String _unit = 'Adet';
  double taxRate = 20;
  double discountRate = 0;
  String? issueKind;
  bool _issueKindManual = false;

  String get unit => _coerceUnit(_unit);
  set unit(String value) => _unit = _coerceUnit(value);

  String get description => descriptionController.text.trim();
  String get notes => notesController.text.trim();
  double get quantity => _parseDecimal(quantityController.text);
  double get unitPrice => _parseDecimal(priceController.text);

  double exclusiveUnitPrice(bool pricesIncludeVat) {
    final entered = unitPrice;
    if (!pricesIncludeVat || taxRate <= 0) return entered;
    // KDV dahil → hariç çevirirken 2 hane; aksi halde 350/1.05=333.333…
    // DB/Maliye toplamında 0,01 sapma üretir.
    return _round2(entered / (1 + taxRate / 100));
  }

  double subtotal(bool pricesIncludeVat) =>
      _round2(quantity * exclusiveUnitPrice(pricesIncludeVat));

  double discountAmount(bool pricesIncludeVat) =>
      _round2(subtotal(pricesIncludeVat) * (discountRate / 100));

  double taxAmount(bool pricesIncludeVat) => _round2(
    (subtotal(pricesIncludeVat) - discountAmount(pricesIncludeVat)) *
        (taxRate / 100),
  );

  double lineTotal(bool pricesIncludeVat) => _round2(
    subtotal(pricesIncludeVat) -
        discountAmount(pricesIncludeVat) +
        taxAmount(pricesIncludeVat),
  );

  void applyProduct(
    Product product, {
    required bool isSales,
    required bool pricesIncludeVat,
  }) {
    productId = product.id;
    descriptionController.text = product.name;
    unit = _coerceUnit(product.unit);
    taxRate = product.taxRate;
    priceController.text = _displayUnitPrice(
      isSales ? product.salePrice : product.purchasePrice,
      taxRate: product.taxRate,
      pricesIncludeVat: pricesIncludeVat,
    ).toStringAsFixed(2);
    if (!_issueKindManual) {
      issueKind = detectInvoiceIssueKind(
        description: product.name,
        productName: product.name,
        productCode: product.code,
        productCategory: [
          product.category,
          product.akinsoftGroup,
          product.akinsoftSubGroup,
        ].whereType<String>().join(' '),
      );
    }
  }

  void detectIssueKindFromDescription() {
    if (_issueKindManual) return;
    issueKind = detectInvoiceIssueKind(
      description: descriptionController.text,
      notes: notesController.text,
    );
  }

  void setIssueKind(String? kind) {
    _issueKindManual = true;
    issueKind = kind;
  }

  void convertPriceDisplay({
    required bool fromIncludeVat,
    required bool toIncludeVat,
  }) {
    if (fromIncludeVat == toIncludeVat || taxRate <= 0) {
      return;
    }
    final current = unitPrice;
    final next = fromIncludeVat
        ? current / (1 + taxRate / 100)
        : current * (1 + taxRate / 100);
    priceController.text = _round2(next).toStringAsFixed(2);
  }

  void dispose() {
    descriptionController.dispose();
    notesController.dispose();
    quantityController.dispose();
    priceController.dispose();
  }
}

double _displayUnitPrice(
  double exclusivePrice, {
  required double taxRate,
  required bool pricesIncludeVat,
}) {
  if (!pricesIncludeVat || taxRate <= 0) {
    return _round2(exclusivePrice);
  }
  return _round2(exclusivePrice * (1 + taxRate / 100));
}

class _SelectAllNumberField extends StatefulWidget {
  const _SelectAllNumberField({
    required this.controller,
    required this.decoration,
    required this.onChanged,
    this.validator,
  });

  final TextEditingController controller;
  final InputDecoration decoration;
  final ValueChanged<String> onChanged;
  final FormFieldValidator<String>? validator;

  @override
  State<_SelectAllNumberField> createState() => _SelectAllNumberFieldState();
}

class _SelectAllNumberFieldState extends State<_SelectAllNumberField> {
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode();
    _focusNode.addListener(_selectAllOnFocus);
  }

  void _selectAllOnFocus() {
    if (!_focusNode.hasFocus) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_focusNode.hasFocus || !mounted) return;
      widget.controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: widget.controller.text.length,
      );
    });
  }

  @override
  void dispose() {
    _focusNode.removeListener(_selectAllOnFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: widget.decoration,
      validator: widget.validator,
      onTap: () {
        widget.controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: widget.controller.text.length,
        );
      },
      onChanged: widget.onChanged,
    );
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

double _round2(double value) => (value * 100).roundToDouble() / 100;

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

String _dateIso(DateTime date) => formatAppDateIso(date);

double _parseDecimal(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}
