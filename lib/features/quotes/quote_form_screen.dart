import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/format/search_normalize.dart';
import '../../core/ui/app_card.dart';
import '../customers/customer_form_dialog.dart';
import '../customers/customer_model.dart';
import '../customers/customer_select_field.dart';
import '../customers/customers_providers.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import '../work_orders/currency_service.dart';
import 'quote_model.dart';
import 'quote_providers.dart';

const _quoteCurrencies = QuoteMoney.currencies;
const _quoteUnitOptions = ['Adet', 'Kg', 'Lt', 'Mt', 'Saat'];

double _parseQuoteDecimal(String value) {
  final normalized = value.trim().replaceAll(' ', '').replaceAll(',', '.');
  return double.tryParse(normalized) ?? 0;
}

double _roundQuote2(double value) => (value * 100).roundToDouble() / 100;

String _formatQuoteQty(double value) => value.toStringAsFixed(
  value.truncateToDouble() == value ? 0 : 2,
);

double _displayQuoteUnitPrice(
  double exclusivePrice, {
  required double taxRate,
  required bool pricesIncludeVat,
}) {
  if (!pricesIncludeVat || taxRate <= 0) {
    return _roundQuote2(exclusivePrice);
  }
  return _roundQuote2(exclusivePrice * (1 + taxRate / 100));
}

double _deriveQuoteUnitPrice(QuoteItem item) {
  if (item.unitPrice > 0) return item.unitPrice;
  if (item.quantity <= 0) return 0;
  final net = item.lineTotal > 0
      ? item.lineTotal - item.taxAmount
      : 0.0;
  if (net > 0) return net / item.quantity;
  return 0;
}

String _coerceQuoteUnit(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return 'Adet';
  for (final option in _quoteUnitOptions) {
    if (option.toLowerCase() == raw.toLowerCase()) return option;
  }
  return 'Adet';
}

class QuoteFormScreen extends ConsumerStatefulWidget {
  const QuoteFormScreen({super.key, this.quoteId});

  final String? quoteId;

  @override
  ConsumerState<QuoteFormScreen> createState() => _QuoteFormScreenState();
}

class _QuoteFormScreenState extends ConsumerState<QuoteFormScreen> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  bool _loadingQuote = false;
  Quote? _initialQuote;
  final _notesController = TextEditingController();
  final _exchangeRateController = TextEditingController(text: '1');
  String? _customerId;
  DateTime _quoteDate = DateTime.now();
  DateTime? _validUntil;
  String _currency = 'USD';
  double _exchangeRate = 1;
  Map<String, double> _rates = const {};
  String _status = 'draft';
  bool _pricesIncludeVat = false;
  final List<_QuoteLineDraft> _lines = [_QuoteLineDraft()];
  final ValueNotifier<int> _totalsTick = ValueNotifier(0);
  bool _loadingProducts = false;

  bool get _isEditing => _initialQuote != null;

  @override
  void initState() {
    super.initState();
    _validUntil = DateTime.now().add(const Duration(days: 14));
    _loadRates();
    if (widget.quoteId != null) {
      _loadQuote();
    }
  }

  void _disposeLines() {
    for (final line in _lines) {
      line.dispose();
    }
    _lines.clear();
  }

  void _notifyTotalsChanged() {
    _totalsTick.value++;
  }

  Future<List<Product>> _loadProductsForPicker() async {
    return ref.read(productsProvider(null).future);
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

  Future<void> _ensureCurrentExchangeRate() async {
    if (_currency == 'TRY') {
      _exchangeRate = 1;
      _exchangeRateController.text = '1';
      return;
    }
    final typed = _parseQuoteDecimal(_exchangeRateController.text);
    final autoRate = _rates[_currency];
    final looksManual =
        typed > 1 &&
        autoRate != null &&
        autoRate > 0 &&
        (typed - autoRate).abs() / autoRate > 0.0005;
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

  Future<void> _loadQuote() async {
    setState(() => _loadingQuote = true);
    try {
      final quote = await ref.read(quoteDetailProvider(widget.quoteId!).future);
      if (!mounted) return;
      if (quote != null) {
        setState(() => _applyQuote(quote));
        _notifyTotalsChanged();
      } else {
        _message('Teklif bulunamadı.');
      }
    } catch (error) {
      if (mounted) _message('Teklif yüklenemedi: $error');
    } finally {
      if (mounted) setState(() => _loadingQuote = false);
    }
  }

  void _applyQuote(Quote quote) {
    _initialQuote = quote;
    _customerId = quote.customerId;
    _quoteDate = quote.quoteDate;
    _validUntil = quote.validUntil;
    _currency = quote.currency.trim().isEmpty ? 'USD' : quote.currency.toUpperCase();
    _exchangeRate = quote.exchangeRate;
    _exchangeRateController.text = quote.exchangeRate.toStringAsFixed(
      _currency == 'TRY' ? 0 : 4,
    );
    _status = quote.status;
    _pricesIncludeVat = quote.pricesIncludeVat;
    _notesController.text = quote.notes ?? '';
    _disposeLines();
    _lines.addAll(
      quote.items.map(
        (item) => _QuoteLineDraft.fromItem(
          item,
          pricesIncludeVat: quote.pricesIncludeVat,
        ),
      ),
    );
    if (_lines.isEmpty && quote.grandTotal > 0) {
      _lines.add(
        _QuoteLineDraft(
          description: 'Teklif kalemi',
          unitPrice: quote.subtotal > 0
              ? quote.subtotal
              : quote.grandTotal / 1.2,
          quantity: 1,
          taxRate: quote.taxTotal > 0 && quote.subtotal > 0
              ? (quote.taxTotal / quote.subtotal * 100)
              : 20,
        ),
      );
    }
    if (_lines.isEmpty) _lines.add(_QuoteLineDraft());
  }

  @override
  void dispose() {
    _notesController.dispose();
    _exchangeRateController.dispose();
    _totalsTick.dispose();
    _disposeLines();
    super.dispose();
  }

  String _extractSavedQuoteId(Map<String, dynamic> response) {
    final direct = response['id']?.toString().trim();
    if (direct != null && direct.isNotEmpty) return direct;
    final row = response['row'];
    if (row is Map) {
      final fromRow = row['id']?.toString().trim();
      if (fromRow != null && fromRow.isNotEmpty) return fromRow;
    }
    return '';
  }

  Future<Customer?> _createCustomer() async {
    final createdId = await showCreateCustomerDialog(context);
    if (createdId == null || !mounted) return null;
    ref.invalidate(customersLookupProvider);
    final refreshed = await ref.read(customersLookupProvider.future);
    for (final customer in refreshed) {
      if (customer.id == createdId) {
        setState(() => _customerId = customer.id);
        return customer;
      }
    }
    return null;
  }

  String _dateIso(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  double _round2(double v) => _roundQuote2(v);

  void _setPricesIncludeVat(bool value) {
    if (value == _pricesIncludeVat) return;
    setState(() {
      for (final line in _lines) {
        line.convertPriceDisplay(
          fromIncludeVat: _pricesIncludeVat,
          toIncludeVat: value,
        );
      }
      _pricesIncludeVat = value;
    });
    _notifyTotalsChanged();
  }

  ({double subtotal, double tax, double discount, double grand}) _totals(
    List<_QuoteLineDraft> lines,
  ) {
    var subtotal = 0.0;
    var tax = 0.0;
    var discount = 0.0;
    for (final line in lines) {
      subtotal += line.exclusiveSubtotal(_pricesIncludeVat);
      tax += line.taxAmount(_pricesIncludeVat);
      discount += line.discountAmount(_pricesIncludeVat);
    }
    return (
      subtotal: _round2(subtotal),
      tax: _round2(tax),
      discount: _round2(discount),
      grand: _round2(subtotal + tax - discount),
    );
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_customerId == null) {
      _message('Müşteri seçin.');
      return;
    }
    final validLines = _lines
        .where((l) => l.description.text.trim().isNotEmpty && l.quantity > 0)
        .toList();
    if (validLines.isEmpty) {
      _message('En az bir kalem ekleyin.');
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      _message('API bağlantısı yok.');
      return;
    }

    setState(() => _saving = true);
    try {
      await _ensureCurrentExchangeRate();
      final quoteNumber = _isEditing
          ? _initialQuote!.quoteNumber
          : (await apiClient.getJson(
                  '/data',
                  queryParameters: {'resource': 'quote_number'},
                ))['value']
                ?.toString()
                .trim() ??
              '';

      final totals = _totals(validLines);
      final profile = await ref.read(currentUserProfileProvider.future);

      final quoteResponse = await apiClient.postJson('/mutate', body: {
        'op': 'upsert',
        'table': 'quotes',
        'returning': 'row',
        'values': {
          if (_isEditing) 'id': _initialQuote!.id,
          'quote_number': quoteNumber.isEmpty
              ? 'TKL-${DateTime.now().millisecondsSinceEpoch}'
              : quoteNumber,
          'customer_id': _customerId,
          'quote_date': _dateIso(_quoteDate),
          'valid_until': _validUntil == null ? null : _dateIso(_validUntil!),
          'currency': _currency,
          'exchange_rate': _currency == 'TRY' ? 1 : _exchangeRate,
          'prices_include_vat': _pricesIncludeVat,
          'subtotal': totals.subtotal,
          'tax_total': totals.tax,
          'discount_total': totals.discount,
          'grand_total': totals.grand,
          'status': _status,
          'notes': _notesController.text.trim().isEmpty
              ? null
              : _notesController.text.trim(),
          'created_by': profile?.id,
          'is_active': true,
        },
      });

      final quoteId = _isEditing
          ? _initialQuote!.id
          : _extractSavedQuoteId(quoteResponse);
      if (quoteId.isEmpty) throw Exception('Teklif ID alınamadı.');

      if (_isEditing) {
        await apiClient.postJson('/mutate', body: {
          'op': 'deleteWhere',
          'table': 'quote_items',
          'filters': [
            {'col': 'quote_id', 'op': 'eq', 'value': quoteId},
          ],
        });
      }

      await apiClient.postJson('/mutate', body: {
        'op': 'insertMany',
        'table': 'quote_items',
        'rows': [
          for (var i = 0; i < validLines.length; i++)
            validLines[i].toRow(
              quoteId,
              i,
              pricesIncludeVat: _pricesIncludeVat,
            ),
        ],
      });

      if (!mounted) return;
      _message('Teklif kaydedildi.');
      context.go('/e-fatura/teklif');
    } catch (error) {
      if (mounted) _message('Kaydedilemedi: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addProducts() async {
    setState(() => _loadingProducts = true);
    try {
      final products = await _loadProductsForPicker();
      if (!mounted) return;
      final selected = await showDialog<List<Product>>(
        context: context,
        builder: (context) => _QuoteProductPickerDialog(products: products),
      );
      if (selected == null || selected.isEmpty) return;
      setState(() {
        if (_lines.length == 1 &&
            _lines.first.description.text.trim().isEmpty &&
            _lines.first.productId == null) {
          _disposeLines();
        }
        for (final product in selected) {
          _lines.add(
            _QuoteLineDraft.fromProduct(
              product,
              pricesIncludeVat: _pricesIncludeVat,
            ),
          );
        }
      });
      _notifyTotalsChanged();
    } catch (error) {
      if (mounted) _message('Stok listesi yüklenemedi: $error');
    } finally {
      if (mounted) setState(() => _loadingProducts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersLookupProvider);
    final productsAsync = ref.watch(productsProvider(null));
    final products = productsAsync.value ?? const <Product>[];
    final productsLoading = productsAsync.isLoading && products.isEmpty;
    final dateFormat = DateFormat('dd.MM.yyyy');
    final selectedCustomer = customersAsync.value
        ?.where((customer) => customer.id == _customerId)
        .cast<Customer?>()
        .firstOrNull;
    final title = _isEditing ? 'Teklif Düzenle' : 'Satış Teklifi';

    final summary = ValueListenableBuilder<int>(
      valueListenable: _totalsTick,
      builder: (context, _, _) {
        final totals = _totals(
          _lines.where((l) => l.description.text.trim().isNotEmpty).toList(),
        );
        return _QuoteSummaryPanel(
          subtotal: totals.subtotal,
          tax: totals.tax,
          discount: totals.discount,
          grandTotal: totals.grand,
          currency: _currency,
          pricesIncludeVat: _pricesIncludeVat,
        );
      },
    );

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Listeye dön',
          icon: const Icon(LucideIcons.arrowLeft),
          onPressed: _saving ? null : () => context.go('/e-fatura/teklif'),
        ),
        title: Text(title),
        actions: [
          if (_loadingQuote)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          TextButton(
            onPressed: _saving ? null : () => context.go('/e-fatura/teklif'),
            child: const Text('Vazgeç'),
          ),
          const Gap(8),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
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
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 980;

            final topCard = AppCard(
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
                                const TextSpan(text: 'Teklif '),
                                TextSpan(
                                  text: '(Standart)',
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
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                            border: Border(
                              left: BorderSide(color: AppTheme.success, width: 4),
                            ),
                          ),
                          child: Text(
                            'Hazırlanıyor',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: AppTheme.success),
                          ),
                        ),
                        const Gap(10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary.withValues(alpha: 0.08),
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                            border: Border.all(color: AppTheme.primary.withValues(alpha: 0.25)),
                          ),
                          child: Text(
                            'Para: ${QuoteMoney.label(_currency)}',
                            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: AppTheme.primary,
                              fontWeight: FontWeight.w700,
                            ),
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
                                    _QuoteReadonlyField(
                                      label: 'Teklif Nu.',
                                      value: _isEditing
                                          ? _initialQuote!.quoteNumber
                                          : 'Otomatik oluşturulacak',
                                    ),
                                    const Gap(10),
                                    customersAsync.when(
                                      data: (customers) => CustomerSelectField(
                                        customers: customers,
                                        selectedCustomerId: _customerId,
                                        label: 'Müşteri',
                                        onSelected: (customer) => setState(
                                          () => _customerId = customer?.id,
                                        ),
                                        onCreateNew: _createCustomer,
                                      ),
                                      loading: () =>
                                          const LinearProgressIndicator(),
                                      error: (_, _) => const Text(
                                        'Cari listesi yüklenemedi.',
                                      ),
                                    ),
                                    const Gap(10),
                                    DropdownButtonFormField<String>(
                                      initialValue: _status,
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Durum',
                                      ),
                                      items: const [
                                        DropdownMenuItem(
                                          value: 'draft',
                                          child: Text('Taslak'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'sent',
                                          child: Text('Gönderildi'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'accepted',
                                          child: Text('Onaylandı'),
                                        ),
                                        DropdownMenuItem(
                                          value: 'rejected',
                                          child: Text('Reddedildi'),
                                        ),
                                      ],
                                      onChanged: _saving
                                          ? null
                                          : (v) {
                                              if (v != null) {
                                                setState(() => _status = v);
                                              }
                                            },
                                    ),
                                    const Gap(10),
                                    DropdownButtonFormField<String>(
                                      key: ValueKey('quote-currency-main-$_currency'),
                                      initialValue:
                                          _quoteCurrencies.contains(_currency)
                                          ? _currency
                                          : 'USD',
                                      isExpanded: true,
                                      decoration: const InputDecoration(
                                        labelText: 'Para Birimi',
                                        hintText: 'Döviz seçin',
                                      ),
                                      items: [
                                        for (final code in _quoteCurrencies)
                                          DropdownMenuItem(
                                            value: code,
                                            child: Text(
                                              '${QuoteMoney.label(code)} (${QuoteMoney.symbol(code).trim()})',
                                            ),
                                          ),
                                      ],
                                      onChanged: _saving
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                _setCurrency(value);
                                              }
                                            },
                                    ),
                                    const Gap(6),
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
                                      onChanged: _saving
                                          ? null
                                          : _setPricesIncludeVat,
                                    ),
                                  ],
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _QuoteDateField(
                                            label: 'Teklif Tarihi',
                                            value: dateFormat.format(_quoteDate),
                                            enabled: !_saving,
                                            onPick: () async {
                                              final picked = await showDatePicker(
                                                context: context,
                                                initialDate: _quoteDate,
                                                firstDate: DateTime(2020),
                                                lastDate: DateTime(2035),
                                              );
                                              if (picked != null) {
                                                setState(() => _quoteDate = picked);
                                              }
                                            },
                                          ),
                                        ),
                                      ],
                                    ),
                                    const Gap(10),
                                    _QuoteDateField(
                                      label: 'Geçerlilik Tarihi',
                                      value: _validUntil == null
                                          ? '—'
                                          : dateFormat.format(_validUntil!),
                                      enabled: !_saving,
                                      onPick: () async {
                                        final picked = await showDatePicker(
                                          context: context,
                                          initialDate:
                                              _validUntil ?? DateTime.now(),
                                          firstDate: DateTime.now(),
                                          lastDate: DateTime(2035),
                                        );
                                        if (picked != null) {
                                          setState(() => _validUntil = picked);
                                        }
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      if (wide)
                        SizedBox(
                          width: 430,
                          child: _QuoteAddressPanel(customer: selectedCustomer),
                        ),
                    ],
                  ),
                ],
              ),
            );

            final itemsCard = AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(0, 8, 14, 8),
                    child: Row(
                      children: [
                        Container(
                          margin: const EdgeInsets.only(left: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppTheme.primary,
                            borderRadius:
                                BorderRadius.circular(AppTheme.radiusSm),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                LucideIcons.list,
                                size: 18,
                                color: Colors.white,
                              ),
                              const Gap(8),
                              Text(
                                'Öğeler',
                                style: Theme.of(context)
                                    .textTheme
                                    .labelLarge
                                    ?.copyWith(color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                        const Spacer(),
                        OutlinedButton.icon(
                          onPressed: _saving || _loadingProducts
                              ? null
                              : _addProducts,
                          icon: _loadingProducts
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(LucideIcons.search, size: 18),
                          label: const Text('Ürün Ara / Çoklu Ekle'),
                        ),
                        const Gap(8),
                        IconButton.filled(
                          tooltip: 'Boş satır ekle',
                          onPressed: _saving
                              ? null
                              : () => setState(
                                  () => _lines.add(_QuoteLineDraft()),
                                ),
                          icon: const Icon(LucideIcons.plus, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minWidth: wide ? constraints.maxWidth - 36 : 1120,
                      ),
                      child: Column(
                        children: [
                          _QuoteTableHeader(
                            pricesIncludeVat: _pricesIncludeVat,
                          ),
                          for (var i = 0; i < _lines.length; i++)
                            _QuoteLineEditor(
                              key: ValueKey(identityHashCode(_lines[i])),
                              line: _lines[i],
                              products: products,
                              productsLoading: productsLoading,
                              productsError: productsAsync.hasError,
                              onRetryProducts: () =>
                                  ref.invalidate(productsProvider(null)),
                              currency: _currency,
                              pricesIncludeVat: _pricesIncludeVat,
                              enabled: !_saving && !_loadingQuote,
                              onTotalsChanged: _notifyTotalsChanged,
                              onRemove: _lines.length > 1
                                  ? () {
                                      setState(() {
                                        _lines[i].dispose();
                                        _lines.removeAt(i);
                                      });
                                      _notifyTotalsChanged();
                                    }
                                  : null,
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );

            if (wide) {
              return ListView(
                padding: const EdgeInsets.fromLTRB(18, 16, 18, 120),
                children: [
                  topCard,
                  const Gap(14),
                  itemsCard,
                  const Gap(14),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: AppCard(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            controller: _notesController,
                            enabled: !_saving,
                            minLines: 7,
                            maxLines: 9,
                            decoration: const InputDecoration(
                              labelText: 'Not',
                              hintText: 'Teklif notu',
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
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
              children: [
                topCard,
                if (!wide) ...[
                  const Gap(12),
                  _QuoteAddressPanel(customer: selectedCustomer),
                ],
                const Gap(12),
                itemsCard,
                const Gap(12),
                summary,
                const Gap(12),
                AppCard(
                  child: TextField(
                    controller: _notesController,
                    enabled: !_saving,
                    decoration: const InputDecoration(labelText: 'Notlar'),
                    maxLines: 3,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _QuoteReadonlyField extends StatelessWidget {
  const _QuoteReadonlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      initialValue: value,
      enabled: false,
      decoration: InputDecoration(labelText: label),
    );
  }
}

class _QuoteAddressPanel extends StatelessWidget {
  const _QuoteAddressPanel({required this.customer});

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
          Container(
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
                Text(
                  'Teklif Adresi',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const Divider(height: 14),
                Text(
                  customer == null
                      ? 'Cari seçildiğinde adres burada görünecek.'
                      : [
                          customer!.name,
                          if (address != null && address.isNotEmpty) address,
                          if (city != null && city.isNotEmpty) city,
                          if (tax != null && tax.isNotEmpty) 'VKN $tax',
                        ].join('\n'),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteSummaryPanel extends StatelessWidget {
  const _QuoteSummaryPanel({
    required this.subtotal,
    required this.tax,
    required this.discount,
    required this.grandTotal,
    required this.currency,
    required this.pricesIncludeVat,
  });

  final double subtotal;
  final double tax;
  final double discount;
  final double grandTotal;
  final String currency;
  final bool pricesIncludeVat;

  @override
  Widget build(BuildContext context) {
    final money = QuoteMoney.format(currency);
    return AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Teklif Özeti',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                QuoteMoney.label(currency),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: AppTheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          if (pricesIncludeVat) ...[
            const Gap(6),
            Text(
              'Birim fiyatlar KDV dahil girildi',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textSoft,
              ),
            ),
          ],
          const Gap(12),
          _QuoteSummaryRow('Ara Toplam', money.format(subtotal)),
          _QuoteSummaryRow('KDV', money.format(tax)),
          if (discount > 0)
            _QuoteSummaryRow('İndirim', '-${money.format(discount)}'),
          const Divider(height: 20),
          _QuoteSummaryRow(
            'Genel Toplam',
            money.format(grandTotal),
            bold: true,
          ),
        ],
      ),
    );
  }
}

class _QuoteSummaryRow extends StatelessWidget {
  const _QuoteSummaryRow(this.label, this.value, {this.bold = false});

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(
      fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

class _QuoteDateField extends StatelessWidget {
  const _QuoteDateField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onPick,
  });

  final String label;
  final String value;
  final bool enabled;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      onTap: enabled ? onPick : null,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label),
        child: Text(value),
      ),
    );
  }
}

class _QuoteTableHeader extends StatelessWidget {
  const _QuoteTableHeader({required this.pricesIncludeVat});

  final bool pricesIncludeVat;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      color: AppTheme.tableHeaderBg,
      child: Row(
        children: [
          const _QuoteHeaderCell('Stok/Hizmet', width: 360),
          const _QuoteHeaderCell('Miktar', width: 88),
          const _QuoteHeaderCell('Birim', width: 96),
          _QuoteHeaderCell(
            pricesIncludeVat ? 'Birim Fiyat (KDV dahil)' : 'Birim Fiyat',
            width: 120,
          ),
          const _QuoteHeaderCell('KDV', width: 88),
          const _QuoteHeaderCell('Tutar', width: 130),
          const _QuoteHeaderCell('', width: 48),
        ],
      ),
    );
  }
}

class _QuoteHeaderCell extends StatelessWidget {
  const _QuoteHeaderCell(this.label, {required this.width});

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
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: AppTheme.textSoft,
          ),
        ),
      ),
    );
  }
}

class _QuoteLineDraft {
  _QuoteLineDraft({
    String description = '',
    this.productId,
    double quantity = 1,
    String unit = 'Adet',
    double unitPrice = 0,
    double taxRate = 20,
  }) : description = TextEditingController(text: description),
       quantityController = TextEditingController(
         text: _formatQuoteQty(quantity),
       ),
       unitPriceController = TextEditingController(
         text: unitPrice.toStringAsFixed(2),
       ),
       taxRateController = TextEditingController(
         text: taxRate.toStringAsFixed(0),
       ),
       unit = _coerceQuoteUnit(unit);

  _QuoteLineDraft.fromProduct(
    Product product, {
    required bool pricesIncludeVat,
  }) : description = TextEditingController(text: product.name),
       productId = product.id,
       quantityController = TextEditingController(text: '1'),
       unitPriceController = TextEditingController(
         text: _displayQuoteUnitPrice(
           product.salePrice,
           taxRate: product.taxRate,
           pricesIncludeVat: pricesIncludeVat,
         ).toStringAsFixed(2),
       ),
       taxRateController = TextEditingController(
         text: product.taxRate.toStringAsFixed(0),
       ),
       unit = _coerceQuoteUnit(product.unit);

  _QuoteLineDraft.fromItem(
    QuoteItem item, {
    required bool pricesIncludeVat,
  }) : description = TextEditingController(text: item.description),
       productId = item.productId,
       quantityController = TextEditingController(
         text: _formatQuoteQty(item.quantity),
       ),
       unitPriceController = TextEditingController(
         text: _displayQuoteUnitPrice(
           _deriveQuoteUnitPrice(item),
           taxRate: item.taxRate,
           pricesIncludeVat: pricesIncludeVat,
         ).toStringAsFixed(2),
       ),
       taxRateController = TextEditingController(
         text: item.taxRate.toStringAsFixed(0),
       ),
       unit = _coerceQuoteUnit(item.unit);

  final TextEditingController description;
  final TextEditingController quantityController;
  final TextEditingController unitPriceController;
  final TextEditingController taxRateController;
  String? productId;
  String unit;

  double get quantity => _parseQuoteDecimal(quantityController.text);
  double get unitPrice => _parseQuoteDecimal(unitPriceController.text);
  double get taxRate => _parseQuoteDecimal(taxRateController.text);

  double exclusiveUnitPrice(bool pricesIncludeVat) {
    final entered = unitPrice;
    if (!pricesIncludeVat || taxRate <= 0) return entered;
    return _roundQuote2(entered / (1 + taxRate / 100));
  }

  double exclusiveSubtotal(bool pricesIncludeVat) =>
      _roundQuote2(quantity * exclusiveUnitPrice(pricesIncludeVat));

  double discountAmount(bool pricesIncludeVat) => 0;

  double taxAmount(bool pricesIncludeVat) => _roundQuote2(
    exclusiveSubtotal(pricesIncludeVat) * taxRate / 100,
  );

  double lineTotal(bool pricesIncludeVat) => _roundQuote2(
    exclusiveSubtotal(pricesIncludeVat) + taxAmount(pricesIncludeVat),
  );

  void applyProduct(Product product, {required bool pricesIncludeVat}) {
    productId = product.id;
    description.text = product.name;
    unit = _coerceQuoteUnit(product.unit);
    taxRateController.text = product.taxRate.toStringAsFixed(0);
    unitPriceController.text = _displayQuoteUnitPrice(
      product.salePrice,
      taxRate: product.taxRate,
      pricesIncludeVat: pricesIncludeVat,
    ).toStringAsFixed(2);
  }

  void convertPriceDisplay({
    required bool fromIncludeVat,
    required bool toIncludeVat,
  }) {
    if (fromIncludeVat == toIncludeVat || taxRate <= 0) return;
    final current = unitPrice;
    final next = fromIncludeVat
        ? current / (1 + taxRate / 100)
        : current * (1 + taxRate / 100);
    unitPriceController.text = _roundQuote2(next).toStringAsFixed(2);
  }

  void dispose() {
    description.dispose();
    quantityController.dispose();
    unitPriceController.dispose();
    taxRateController.dispose();
  }

  Map<String, dynamic> toRow(
    String quoteId,
    int sortOrder, {
    required bool pricesIncludeVat,
  }) => {
    'quote_id': quoteId,
    if (productId != null && productId!.isNotEmpty) 'product_id': productId,
    'description': description.text.trim(),
    'quantity': quantity,
    'unit': unit,
    'unit_price': exclusiveUnitPrice(pricesIncludeVat),
    'tax_rate': taxRate,
    'tax_amount': taxAmount(pricesIncludeVat),
    'discount_rate': 0,
    'discount_amount': 0,
    'line_total': lineTotal(pricesIncludeVat),
    'sort_order': sortOrder,
  };
}

class _QuoteTableNumberField extends StatefulWidget {
  const _QuoteTableNumberField({
    required this.controller,
    required this.onChanged,
    this.width = 88,
    this.suffixText,
    this.focusNode,
    this.enabled = true,
  });

  final TextEditingController controller;
  final VoidCallback onChanged;
  final double width;
  final String? suffixText;
  final FocusNode? focusNode;
  final bool enabled;

  @override
  State<_QuoteTableNumberField> createState() => _QuoteTableNumberFieldState();
}

class _QuoteTableNumberFieldState extends State<_QuoteTableNumberField> {
  FocusNode? _ownedFocusNode;

  FocusNode get _focusNode => widget.focusNode ?? _ownedFocusNode!;

  @override
  void initState() {
    super.initState();
    if (widget.focusNode == null) {
      _ownedFocusNode = FocusNode();
    }
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

  void _selectAll() {
    widget.controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: widget.controller.text.length,
    );
  }

  @override
  void dispose() {
    _focusNode.removeListener(_selectAllOnFocus);
    _ownedFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(),
    );

    return SizedBox(
      width: widget.width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: TextFormField(
          controller: widget.controller,
          focusNode: _focusNode,
          enabled: widget.enabled,
          decoration: dense.copyWith(suffixText: widget.suffixText),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onTap: _selectAll,
          onChanged: (_) => widget.onChanged(),
        ),
      ),
    );
  }
}

class _QuoteLineEditor extends StatefulWidget {
  const _QuoteLineEditor({
    super.key,
    required this.line,
    required this.products,
    required this.productsLoading,
    required this.productsError,
    required this.onRetryProducts,
    required this.currency,
    required this.pricesIncludeVat,
    required this.enabled,
    required this.onTotalsChanged,
    this.onRemove,
  });

  final _QuoteLineDraft line;
  final List<Product> products;
  final bool productsLoading;
  final bool productsError;
  final VoidCallback onRetryProducts;
  final String currency;
  final bool pricesIncludeVat;
  final bool enabled;
  final VoidCallback onTotalsChanged;
  final VoidCallback? onRemove;

  @override
  State<_QuoteLineEditor> createState() => _QuoteLineEditorState();
}

class _QuoteLineEditorState extends State<_QuoteLineEditor> {
  late final FocusNode _priceFocusNode;
  late final FocusNode _productFocusNode;

  @override
  void initState() {
    super.initState();
    _priceFocusNode = FocusNode();
    _productFocusNode = FocusNode();
  }

  @override
  void dispose() {
    _priceFocusNode.dispose();
    _productFocusNode.dispose();
    super.dispose();
  }

  void _handleChanged() {
    setState(() {});
    widget.onTotalsChanged();
  }

  Iterable<Product> _productOptionsFor(String rawQuery) {
    final query = rawQuery.trim();
    final active = widget.products.where((p) => p.isActive);
    if (query.isEmpty) return active.take(12);
    return active
        .where(
          (product) =>
              matchesSearchQuery(product.name, query) ||
              matchesSearchQuery(product.code ?? '', query) ||
              matchesSearchQuery(product.category ?? '', query),
        )
        .take(12);
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final money = QuoteMoney.format(widget.currency);
    const dense = InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      border: OutlineInputBorder(),
    );

    final productHint = widget.productsLoading
        ? 'Stok listesi yükleniyor…'
        : widget.productsError
        ? 'Stok yüklenemedi — yeniden dene'
        : widget.products.isEmpty
        ? 'Stok listesi boş — serbest yazabilirsiniz'
        : 'Stok veya açıklama';

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 360,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: RawAutocomplete<Product>(
                textEditingController: line.description,
                focusNode: _productFocusNode,
                displayStringForOption: (product) => product.name,
                optionsBuilder: (value) => _productOptionsFor(value.text),
                onSelected: (product) {
                  line.applyProduct(
                    product,
                    pricesIncludeVat: widget.pricesIncludeVat,
                  );
                  _handleChanged();
                },
                fieldViewBuilder:
                    (context, controller, focusNode, onFieldSubmitted) {
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        enabled: widget.enabled,
                        decoration: dense.copyWith(
                          hintText: productHint,
                          suffixIcon: widget.productsLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(10),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                )
                              : widget.productsError
                              ? IconButton(
                                  tooltip: 'Stok listesini yenile',
                                  onPressed: widget.onRetryProducts,
                                  icon: const Icon(LucideIcons.refreshCw, size: 16),
                                )
                              : null,
                        ),
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'Gerekli'
                            : null,
                        onFieldSubmitted: (_) => onFieldSubmitted(),
                        onChanged: (_) {
                          // Yazarken setState yapma — öneri listesi kapanmasın.
                          line.productId = null;
                        },
                      );
                    },
                optionsViewBuilder: (context, onSelected, options) {
                  final items = options.toList(growable: false);
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 8,
                      borderRadius: BorderRadius.circular(10),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: 420,
                          maxHeight: 280,
                        ),
                        child: items.isEmpty
                            ? ListTile(
                                dense: true,
                                title: Text(
                                  widget.productsLoading
                                      ? 'Stok listesi yükleniyor…'
                                      : widget.products.isEmpty
                                      ? 'Stok bulunamadı'
                                      : 'Eşleşen stok yok',
                                ),
                              )
                            : ListView.separated(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 4,
                                ),
                                shrinkWrap: true,
                                itemCount: items.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = items[index];
                                  return ListTile(
                                    dense: true,
                                    title: Text(
                                      product.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle:
                                        (product.code ?? '').trim().isEmpty
                                        ? null
                                        : Text(product.code!),
                                    trailing: Text(
                                      QuoteMoney.format(
                                        widget.currency,
                                      ).format(product.salePrice),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.labelMedium,
                                    ),
                                    onTap: () => onSelected(product),
                                  );
                                },
                              ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          _QuoteTableNumberField(
            width: 88,
            controller: line.quantityController,
            enabled: widget.enabled,
            onChanged: _handleChanged,
          ),
          SizedBox(
            width: 96,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: DropdownButtonFormField<String>(
                key: ValueKey('q-unit-${identityHashCode(line)}-${line.unit}'),
                initialValue: line.unit,
                isExpanded: true,
                decoration: dense,
                items: [
                  for (final unit in _quoteUnitOptions)
                    DropdownMenuItem(value: unit, child: Text(unit)),
                ],
                onChanged: widget.enabled
                    ? (v) {
                        if (v != null) {
                          line.unit = v;
                          _handleChanged();
                        }
                      }
                    : null,
              ),
            ),
          ),
          _QuoteTableNumberField(
            width: 120,
            controller: line.unitPriceController,
            focusNode: _priceFocusNode,
            enabled: widget.enabled,
            onChanged: _handleChanged,
          ),
          _QuoteTableNumberField(
            width: 88,
            controller: line.taxRateController,
            suffixText: '%',
            enabled: widget.enabled,
            onChanged: _handleChanged,
          ),
          SizedBox(
            width: 130,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  onTap: widget.enabled
                      ? () {
                          _priceFocusNode.requestFocus();
                        }
                      : null,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          money.format(
                            line.lineTotal(widget.pricesIncludeVat),
                          ),
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: AppTheme.success,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          'KDV ${money.format(line.taxAmount(widget.pricesIncludeVat))}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: 'Kalemi sil',
              visualDensity: VisualDensity.compact,
              onPressed: widget.enabled ? widget.onRemove : null,
              icon: const Icon(LucideIcons.trash2, size: 18),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuoteProductPickerDialog extends StatefulWidget {
  const _QuoteProductPickerDialog({required this.products});

  final List<Product> products;

  @override
  State<_QuoteProductPickerDialog> createState() =>
      _QuoteProductPickerDialogState();
}

class _QuoteProductPickerDialogState extends State<_QuoteProductPickerDialog> {
  final _search = TextEditingController();
  final _selectedIds = <String>{};

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim();
    final active = widget.products.where((p) => p.isActive).toList();
    final filtered = query.isEmpty
        ? active.take(100).toList()
        : active
              .where(
                (product) => matchesSearchQuery(
                  [
                    product.name,
                    product.code ?? '',
                    product.category ?? '',
                  ].join(' '),
                  query,
                ),
              )
              .take(140)
              .toList();

    return AlertDialog(
      title: const Text('Stoktan Ürün Seç'),
      content: SizedBox(
        width: 820,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(LucideIcons.search),
                hintText: 'Stok kodu, ad veya grup ara',
              ),
            ),
            const Gap(10),
            Expanded(
              child: filtered.isEmpty
                  ? const Center(child: Text('Stok bulunamadı.'))
                  : ListView.separated(
                      itemCount: filtered.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
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
                              'Satış ${product.salePrice.toStringAsFixed(2)}',
                            ].join(' • '),
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
                      .where((p) => _selectedIds.contains(p.id))
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
