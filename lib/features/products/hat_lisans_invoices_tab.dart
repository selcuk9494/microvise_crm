import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_phone_scroll.dart';
import '../customers/customer_detail_screen.dart';
import '../e_invoice/e_invoice_whatsapp_share.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

final hatLisansInvoicePaymentFilterProvider =
    NotifierProvider<HatLisansInvoicePaymentFilterNotifier, String>(
      HatLisansInvoicePaymentFilterNotifier.new,
    );

class HatLisansTotalsTickNotifier extends Notifier<int> {
  @override
  int build() => 0;

  void bump() => state++;
}

final hatLisansTotalsTickProvider =
    NotifierProvider<HatLisansTotalsTickNotifier, int>(
      HatLisansTotalsTickNotifier.new,
    );

class HatLisansInvoicePaymentFilterNotifier extends Notifier<String> {
  @override
  String build() => 'pending';

  void set(String value) => state = value;
}

final hatLisansInvoicesProvider = FutureProvider.autoDispose<List<Invoice>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final payment = ref.watch(hatLisansInvoicePaymentFilterProvider);
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'hat_lisans_invoices',
      if (payment.isNotEmpty) 'payment': payment,
    },
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Invoice.fromJson)
      .toList(growable: false);
});

final hatLisansBillingCatalogProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null) return const {};
      return apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'hat_lisans_billing_catalog'},
      );
    });

class HatLisansInvoiceCustomer {
  const HatLisansInvoiceCustomer({
    required this.customerId,
    required this.customerName,
    required this.linesTotal,
    required this.gmp3Total,
    required this.irestoTotal,
  });

  final String customerId;
  final String customerName;
  final int linesTotal;
  final int gmp3Total;
  final int irestoTotal;
}

NumberFormat _money(String currency) {
  return NumberFormat.currency(
    locale: 'tr_TR',
    symbol: currency.toUpperCase() == 'USD'
        ? r'$'
        : currency.toUpperCase() == 'EUR'
        ? '€'
        : '₺',
    decimalDigits: 2,
  );
}

String _priceText(Object? value) {
  final n = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 0;
  if (n <= 0) return '';
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toString();
}

String _titleText(Object? value, String fallback) {
  final text = value?.toString().trim() ?? '';
  return text.isEmpty ? fallback : text;
}

String _taxText(Object? value) {
  final n = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString().replaceAll(',', '.') ?? '') ?? 20;
  if (!n.isFinite || n < 0 || n > 100) return '20';
  if (n == n.roundToDouble()) return n.round().toString();
  return n.toString();
}

String _periodFrom(Object? value) {
  final raw = (value ?? 'yearly').toString().trim().toLowerCase();
  if (raw == 'monthly' ||
      raw == 'month' ||
      raw == 'aylik' ||
      raw == 'aylık' ||
      raw == 'ay') {
    return 'monthly';
  }
  return 'yearly';
}

const _kLinePaymentTitle = 'Yazar kasa İnternet hattı Yıllık kullanım';
const _kGmp3PaymentTitle = 'Yazar Kasa Entegrasyon ödemesi';
const _kIrestoPaymentTitle = 'iResto Yazarkasa Entegrasyon ödemesi';

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  return const {};
}

Future<void> showCreateHatLisansInvoiceDialog({
  required BuildContext context,
  required WidgetRef ref,
  required List<HatLisansInvoiceCustomer> customers,
  String? singleCustomerId,
}) async {
  final targets = singleCustomerId == null
      ? customers
      : customers.where((e) => e.customerId == singleCustomerId).toList();
  if (targets.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Fatura oluşturulacak müşteri yok.')),
    );
    return;
  }

  final created = await showDialog<int>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _CreateHatLisansInvoiceDialog(
      targets: targets,
      singleCustomer: singleCustomerId != null,
    ),
  );
  if (!context.mounted || created == null) return;
  if (created > 0) {
    ref.read(hatLisansTotalsTickProvider.notifier).bump();
    final tab = DefaultTabController.maybeOf(context);
    if (tab != null && tab.length > 4) {
      tab.animateTo(4);
    }
  }
}

class _CreateHatLisansInvoiceDialog extends ConsumerStatefulWidget {
  const _CreateHatLisansInvoiceDialog({
    required this.targets,
    required this.singleCustomer,
  });

  final List<HatLisansInvoiceCustomer> targets;
  final bool singleCustomer;

  @override
  ConsumerState<_CreateHatLisansInvoiceDialog> createState() =>
      _CreateHatLisansInvoiceDialogState();
}

class _CreateHatLisansInvoiceDialogState
    extends ConsumerState<_CreateHatLisansInvoiceDialog> {
  final _lineTry = TextEditingController();
  final _lineUsd = TextEditingController();
  final _gmp3Try = TextEditingController();
  final _gmp3Usd = TextEditingController();
  final _irestoTry = TextEditingController();
  final _irestoUsd = TextEditingController();
  final _lineMonthTry = TextEditingController();
  final _lineMonthUsd = TextEditingController();
  final _gmp3MonthTry = TextEditingController();
  final _gmp3MonthUsd = TextEditingController();
  final _irestoMonthTry = TextEditingController();
  final _irestoMonthUsd = TextEditingController();
  final _lineTax = TextEditingController(text: '20');
  final _gmp3Tax = TextEditingController(text: '20');
  final _irestoTax = TextEditingController(text: '20');
  final _lineTitle = TextEditingController(text: _kLinePaymentTitle);
  final _gmp3Title = TextEditingController(text: _kGmp3PaymentTitle);
  final _irestoTitle = TextEditingController(text: _kIrestoPaymentTitle);
  String _currency = 'TRY';
  String _period = 'yearly';
  String? _lineProductId;
  String? _gmp3ProductId;
  String? _irestoProductId;
  bool _hydrated = false;
  bool _saving = false;
  bool _pricesIncludeVat = false;

  @override
  void dispose() {
    _lineTry.dispose();
    _lineUsd.dispose();
    _gmp3Try.dispose();
    _gmp3Usd.dispose();
    _irestoTry.dispose();
    _irestoUsd.dispose();
    _lineMonthTry.dispose();
    _lineMonthUsd.dispose();
    _gmp3MonthTry.dispose();
    _gmp3MonthUsd.dispose();
    _irestoMonthTry.dispose();
    _irestoMonthUsd.dispose();
    _lineTax.dispose();
    _gmp3Tax.dispose();
    _irestoTax.dispose();
    _lineTitle.dispose();
    _gmp3Title.dispose();
    _irestoTitle.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> catalog) {
    if (_hydrated || catalog.isEmpty) return;
    final settings = _asMap(catalog['settings']);
    _lineTry.text = _priceText(settings['linePriceTry']);
    _lineUsd.text = _priceText(settings['linePriceUsd']);
    _gmp3Try.text = _priceText(settings['gmp3PriceTry']);
    _gmp3Usd.text = _priceText(settings['gmp3PriceUsd']);
    _irestoTry.text = _priceText(settings['irestoPriceTry']);
    _irestoUsd.text = _priceText(settings['irestoPriceUsd']);
    _lineMonthTry.text = _priceText(settings['linePriceMonthTry']);
    _lineMonthUsd.text = _priceText(settings['linePriceMonthUsd']);
    _gmp3MonthTry.text = _priceText(settings['gmp3PriceMonthTry']);
    _gmp3MonthUsd.text = _priceText(settings['gmp3PriceMonthUsd']);
    _irestoMonthTry.text = _priceText(settings['irestoPriceMonthTry']);
    _irestoMonthUsd.text = _priceText(settings['irestoPriceMonthUsd']);
    _lineTax.text = _taxText(settings['lineTaxRate']);
    _gmp3Tax.text = _taxText(settings['gmp3TaxRate']);
    _irestoTax.text = _taxText(settings['irestoTaxRate']);
    _lineTitle.text = _titleText(
      settings['linePaymentTitle'],
      _kLinePaymentTitle,
    );
    _gmp3Title.text = _titleText(
      settings['gmp3PaymentTitle'],
      _kGmp3PaymentTitle,
    );
    _irestoTitle.text = _titleText(
      settings['irestoPaymentTitle'],
      _kIrestoPaymentTitle,
    );
    _currency =
        (settings['defaultCurrency'] ?? 'TRY').toString().toUpperCase() == 'USD'
        ? 'USD'
        : 'TRY';
    _period = _periodFrom(settings['defaultPeriod']);
    _lineProductId = settings['lineProductId']?.toString();
    _gmp3ProductId = settings['gmp3ProductId']?.toString();
    _irestoProductId = settings['irestoProductId']?.toString();
    _hydrated = true;
  }

  void _applyProductPrice(Product product, {required String kind}) {
    final price = _priceText(product.salePrice);
    final tax = _taxText(product.taxRate);
    final isUsd = product.currency.toUpperCase() == 'USD';
    setState(() {
      switch (kind) {
        case 'line':
          _lineProductId = product.id;
          if (_lineTax.text.trim().isEmpty) _lineTax.text = tax;
          if (price.isEmpty) return;
          if (isUsd) {
            if (_lineUsd.text.trim().isEmpty) _lineUsd.text = price;
          } else if (_lineTry.text.trim().isEmpty) {
            _lineTry.text = price;
          }
        case 'gmp3':
          _gmp3ProductId = product.id;
          if (_gmp3Tax.text.trim().isEmpty) _gmp3Tax.text = tax;
          if (price.isEmpty) return;
          if (isUsd) {
            if (_gmp3Usd.text.trim().isEmpty) _gmp3Usd.text = price;
          } else if (_gmp3Try.text.trim().isEmpty) {
            _gmp3Try.text = price;
          }
        case 'iresto':
          _irestoProductId = product.id;
          if (_irestoTax.text.trim().isEmpty) _irestoTax.text = tax;
          if (price.isEmpty) return;
          if (isUsd) {
            if (_irestoUsd.text.trim().isEmpty) _irestoUsd.text = price;
          } else if (_irestoTry.text.trim().isEmpty) {
            _irestoTry.text = price;
          }
      }
    });
  }

  bool _hasSelectedPeriodPrice(
    TextEditingController tryC,
    TextEditingController usdC,
  ) {
    return _currency == 'USD'
        ? usdC.text.trim().isNotEmpty
        : tryC.text.trim().isNotEmpty;
  }

  Future<void> _submit() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null || _saving) return;
    final monthly = _period == 'monthly';
    final selectedPrice =
        _hasSelectedPeriodPrice(
          monthly ? _lineMonthTry : _lineTry,
          monthly ? _lineMonthUsd : _lineUsd,
        ) ||
        _hasSelectedPeriodPrice(
          monthly ? _gmp3MonthTry : _gmp3Try,
          monthly ? _gmp3MonthUsd : _gmp3Usd,
        ) ||
        _hasSelectedPeriodPrice(
          monthly ? _irestoMonthTry : _irestoTry,
          monthly ? _irestoMonthUsd : _irestoUsd,
        );
    if (!selectedPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            monthly
                ? (_currency == 'USD'
                      ? 'Aylık USD fatura için Hat, GMP3 veya iResto dolar fiyatı girin.'
                      : 'Aylık TL fatura için Hat, GMP3 veya iResto TL fiyatı girin.')
                : (_currency == 'USD'
                      ? 'Yıllık USD fatura için Hat, GMP3 veya iResto dolar fiyatı girin.'
                      : 'Yıllık TL fatura için Hat, GMP3 veya iResto TL fiyatı girin.'),
          ),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final response = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'createHatLisansInvoices',
          'customerIds': widget.targets.map((e) => e.customerId).toList(),
          'prices': {
            'currency': _currency,
            'period': _period,
            'defaultPeriod': _period,
            'lineProductId': _lineProductId,
            'gmp3ProductId': _gmp3ProductId,
            'irestoProductId': _irestoProductId,
            'linePriceTry': _lineTry.text.trim(),
            'linePriceUsd': _lineUsd.text.trim(),
            'gmp3PriceTry': _gmp3Try.text.trim(),
            'gmp3PriceUsd': _gmp3Usd.text.trim(),
            'irestoPriceTry': _irestoTry.text.trim(),
            'irestoPriceUsd': _irestoUsd.text.trim(),
            'linePriceMonthTry': _lineMonthTry.text.trim(),
            'linePriceMonthUsd': _lineMonthUsd.text.trim(),
            'gmp3PriceMonthTry': _gmp3MonthTry.text.trim(),
            'gmp3PriceMonthUsd': _gmp3MonthUsd.text.trim(),
            'irestoPriceMonthTry': _irestoMonthTry.text.trim(),
            'irestoPriceMonthUsd': _irestoMonthUsd.text.trim(),
            'lineUnitPriceTry': (monthly ? _lineMonthTry : _lineTry).text
                .trim(),
            'lineUnitPriceUsd': (monthly ? _lineMonthUsd : _lineUsd).text
                .trim(),
            'gmp3UnitPriceTry': (monthly ? _gmp3MonthTry : _gmp3Try).text
                .trim(),
            'gmp3UnitPriceUsd': (monthly ? _gmp3MonthUsd : _gmp3Usd).text
                .trim(),
            'irestoUnitPriceTry': (monthly ? _irestoMonthTry : _irestoTry).text
                .trim(),
            'irestoUnitPriceUsd': (monthly ? _irestoMonthUsd : _irestoUsd).text
                .trim(),
            'lineTaxRate': _lineTax.text.trim(),
            'gmp3TaxRate': _gmp3Tax.text.trim(),
            'irestoTaxRate': _irestoTax.text.trim(),
            'linePaymentTitle': _lineTitle.text.trim(),
            'gmp3PaymentTitle': _gmp3Title.text.trim(),
            'irestoPaymentTitle': _irestoTitle.text.trim(),
            'pricesIncludeVat': _pricesIncludeVat,
          },
        },
        timeout: const Duration(seconds: 120),
      );
      final created = (response['createdCount'] as num?)?.toInt() ?? 0;
      final skipped = (response['skipped'] as List?) ?? const [];
      ref.invalidate(hatLisansInvoicesProvider);
      ref.invalidate(hatLisansBillingCatalogProvider);
      if (!mounted) return;
      final skipText = skipped
          .whereType<Map>()
          .take(4)
          .map((row) {
            final name = row['customerName'] ?? '';
            final reason = row['reason'] ?? '';
            return '$name: $reason';
          })
          .join('\n');
      final message = created == 0
          ? (skipText.isEmpty
                ? 'Fatura oluşmadı. Seçilen para biriminde fiyat girin.'
                : 'Fatura oluşmadı.\n$skipText')
          : 'Taslak fatura: $created'
                '${skipped.isEmpty ? '' : ' • Atlanan ${skipped.length}'}'
                '${skipText.isEmpty ? '' : '\n$skipText'}';
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(created);
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          duration: Duration(seconds: skipped.isEmpty ? 3 : 8),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fatura oluşturulamadı: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(hatLisansBillingCatalogProvider);
    final productsAsync = ref.watch(productsProvider(null));
    catalogAsync.whenData((catalog) {
      if (_hydrated || catalog.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hydrated) return;
        setState(() => _hydrate(catalog));
      });
    });
    final products = productsAsync.asData?.value ?? const <Product>[];
    final hatCount = widget.targets.fold<int>(
      0,
      (sum, e) => sum + e.linesTotal,
    );
    final gmp3Count = widget.targets.fold<int>(
      0,
      (sum, e) => sum + e.gmp3Total,
    );
    final irestoCount = widget.targets.fold<int>(
      0,
      (sum, e) => sum + e.irestoTotal,
    );

    return AlertDialog(
      title: const Text('Hat & Lisans faturası'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.singleCustomer
                    ? '${widget.targets.first.customerName}: Hat ${widget.targets.first.linesTotal} · '
                          'GMP3 ${widget.targets.first.gmp3Total} · iResto ${widget.targets.first.irestoTotal}'
                    : '${widget.targets.length} müşteri için taslak fatura oluşacak. '
                          'Hat $hatCount · GMP3 $gmp3Count · iResto $irestoCount',
              ),
              const Gap(8),
              Text(
                'Önce Aylık veya Yıllık seçin, o dönemin fiyatını girin. '
                'Diğer dönem için seçimi değiştirip ayrı fiyat yazın; Kaydet / Fatura '
                'her iki dönemi de saklar. Ödeme açıklaması mail ve WhatsApp’ta görünür.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
              const Gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'yearly', label: Text('Yıllık')),
                      ButtonSegment(value: 'monthly', label: Text('Aylık')),
                    ],
                    selected: {_period},
                    onSelectionChanged: _saving
                        ? null
                        : (value) {
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() => _period = value.first);
                          },
                  ),
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'TRY', label: Text('Fatura: TL')),
                      ButtonSegment(value: 'USD', label: Text('Fatura: USD')),
                    ],
                    selected: {_currency},
                    onSelectionChanged: _saving
                        ? null
                        : (value) => setState(() => _currency = value.first),
                  ),
                ],
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('KDV dahil'),
                subtitle: const Text(
                  'Açıksa girilen birim fiyat KDV dahildir.',
                ),
                value: _pricesIncludeVat,
                onChanged: _saving
                    ? null
                    : (value) => setState(() => _pricesIncludeVat = value),
              ),
              const Gap(8),
              _ProductPickField(
                label: 'Hat kalemi',
                products: products,
                selectedId: _lineProductId,
                enabled: !_saving,
                onSelected: (product) =>
                    _applyProductPrice(product, kind: 'line'),
              ),
              const Gap(8),
              _TaxRateField(
                id: 'create-line',
                controller: _lineTax,
                enabled: !_saving,
              ),
              const Gap(8),
              _PeriodPriceRow(
                idPrefix: 'create-line',
                kindLabel: 'Hat',
                period: _period,
                currency: _currency,
                monthTry: _lineMonthTry,
                monthUsd: _lineMonthUsd,
                yearTry: _lineTry,
                yearUsd: _lineUsd,
                enabled: !_saving,
              ),
              const Gap(8),
              _PaymentTitleField(
                id: 'create-line',
                controller: _lineTitle,
                label: 'Ödeme açıklaması (Hat)',
                enabled: !_saving,
              ),
              const Gap(14),
              _ProductPickField(
                label: 'GMP3 kalemi',
                products: products,
                selectedId: _gmp3ProductId,
                enabled: !_saving,
                onSelected: (product) =>
                    _applyProductPrice(product, kind: 'gmp3'),
              ),
              const Gap(8),
              _TaxRateField(
                id: 'create-gmp3',
                controller: _gmp3Tax,
                enabled: !_saving,
              ),
              const Gap(8),
              _PeriodPriceRow(
                idPrefix: 'create-gmp3',
                kindLabel: 'GMP3',
                period: _period,
                currency: _currency,
                monthTry: _gmp3MonthTry,
                monthUsd: _gmp3MonthUsd,
                yearTry: _gmp3Try,
                yearUsd: _gmp3Usd,
                enabled: !_saving,
              ),
              const Gap(8),
              _PaymentTitleField(
                id: 'create-gmp3',
                controller: _gmp3Title,
                label: 'Ödeme açıklaması (GMP3)',
                enabled: !_saving,
              ),
              const Gap(14),
              _ProductPickField(
                label: 'iResto kalemi (opsiyonel)',
                products: products,
                selectedId: _irestoProductId,
                enabled: !_saving,
                onSelected: (product) =>
                    _applyProductPrice(product, kind: 'iresto'),
              ),
              const Gap(8),
              _TaxRateField(
                id: 'create-iresto',
                controller: _irestoTax,
                enabled: !_saving,
              ),
              const Gap(8),
              _PeriodPriceRow(
                idPrefix: 'create-iresto',
                kindLabel: 'iResto',
                period: _period,
                currency: _currency,
                monthTry: _irestoMonthTry,
                monthUsd: _irestoMonthUsd,
                yearTry: _irestoTry,
                yearUsd: _irestoUsd,
                enabled: !_saving,
              ),
              const Gap(8),
              _PaymentTitleField(
                id: 'create-iresto',
                controller: _irestoTitle,
                label: 'Ödeme açıklaması (iResto)',
                enabled: !_saving,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Fatura Oluştur'),
        ),
      ],
    );
  }
}

class _PaymentTitleField extends StatelessWidget {
  const _PaymentTitleField({
    required this.id,
    required this.controller,
    required this.label,
    required this.enabled,
  });

  final String id;
  final TextEditingController controller;
  final String label;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey('$id-title'),
      restorationId: '$id-title',
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        hintText: 'Mail ve WhatsApp’ta görünen ödeme açıklaması',
        isDense: true,
      ),
    );
  }
}

class _TaxRateField extends StatelessWidget {
  const _TaxRateField({
    required this.id,
    required this.controller,
    required this.enabled,
  });

  final String id;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: ValueKey('$id-tax'),
      restorationId: '$id-tax',
      controller: controller,
      enabled: enabled,
      enableSuggestions: false,
      autocorrect: false,
      autofillHints: const [],
      keyboardType: TextInputType.text,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      decoration: const InputDecoration(
        labelText: 'KDV %',
        hintText: '20',
        isDense: true,
      ),
    );
  }
}

class _PeriodPriceRow extends StatelessWidget {
  const _PeriodPriceRow({
    required this.idPrefix,
    required this.kindLabel,
    required this.period,
    required this.currency,
    required this.monthTry,
    required this.monthUsd,
    required this.yearTry,
    required this.yearUsd,
    required this.enabled,
  });

  final String idPrefix;
  final String kindLabel;
  final String period;
  final String currency;
  final TextEditingController monthTry;
  final TextEditingController monthUsd;
  final TextEditingController yearTry;
  final TextEditingController yearUsd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final monthly = period == 'monthly';
    final tag = monthly ? 'aylık' : 'yıllık';
    return _DualPriceRow(
      key: ValueKey('$idPrefix-$period'),
      id: '$idPrefix-$period',
      tryController: monthly ? monthTry : yearTry,
      usdController: monthly ? monthUsd : yearUsd,
      tryLabel: '$kindLabel $tag TL',
      usdLabel: '$kindLabel $tag USD',
      highlightUsd: currency == 'USD',
      enabled: enabled,
    );
  }
}

class _DualPriceRow extends StatefulWidget {
  const _DualPriceRow({
    super.key,
    required this.id,
    required this.tryController,
    required this.usdController,
    required this.tryLabel,
    required this.usdLabel,
    required this.highlightUsd,
    required this.enabled,
  });

  final String id;
  final TextEditingController tryController;
  final TextEditingController usdController;
  final String tryLabel;
  final String usdLabel;
  final bool highlightUsd;
  final bool enabled;

  @override
  State<_DualPriceRow> createState() => _DualPriceRowState();
}

class _DualPriceRowState extends State<_DualPriceRow> {
  late final FocusNode _tryFocus;
  late final FocusNode _usdFocus;

  @override
  void initState() {
    super.initState();
    _tryFocus = FocusNode(debugLabel: '${widget.id}-try');
    _usdFocus = FocusNode(debugLabel: '${widget.id}-usd');
  }

  @override
  void dispose() {
    _tryFocus.dispose();
    _usdFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            key: ValueKey('${widget.id}-try'),
            restorationId: '${widget.id}-try',
            controller: widget.tryController,
            focusNode: _tryFocus,
            enabled: widget.enabled,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [],
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: widget.tryLabel,
              prefixText: '₺ ',
              filled: !widget.highlightUsd,
              isDense: true,
            ),
          ),
        ),
        const Gap(8),
        Expanded(
          child: TextField(
            key: ValueKey('${widget.id}-usd'),
            restorationId: '${widget.id}-usd',
            controller: widget.usdController,
            focusNode: _usdFocus,
            enabled: widget.enabled,
            enableSuggestions: false,
            autocorrect: false,
            autofillHints: const [],
            keyboardType: TextInputType.text,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            decoration: InputDecoration(
              labelText: widget.usdLabel,
              prefixText: r'$ ',
              filled: widget.highlightUsd,
              isDense: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _ProductPickField extends StatelessWidget {
  const _ProductPickField({
    required this.label,
    required this.products,
    required this.selectedId,
    required this.onSelected,
    required this.enabled,
  });

  final String label;
  final List<Product> products;
  final String? selectedId;
  final ValueChanged<Product> onSelected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final selected = products.where((p) => p.id == selectedId).firstOrNull;
    return Autocomplete<Product>(
      optionsBuilder: (text) {
        final q = text.text.toLowerCase();
        final active = products.where((p) => p.isActive).toList();
        if (q.isEmpty) return active.take(12);
        return active
            .where(
              (p) =>
                  p.name.toLowerCase().contains(q) ||
                  (p.code?.toLowerCase().contains(q) ?? false),
            )
            .take(12);
      },
      displayStringForOption: (p) => p.name,
      onSelected: onSelected,
      fieldViewBuilder: (context, controller, focusNode, _) {
        if (controller.text.isEmpty && selected != null) {
          controller.text = selected.name;
        }
        return TextField(
          controller: controller,
          focusNode: focusNode,
          enabled: enabled,
          decoration: InputDecoration(
            labelText: label,
            hintText: 'Ürün/Hizmet kataloğundan ara',
            isDense: true,
          ),
        );
      },
    );
  }
}

class HatLisansBillingPriceCard extends ConsumerStatefulWidget {
  const HatLisansBillingPriceCard({super.key});

  @override
  ConsumerState<HatLisansBillingPriceCard> createState() =>
      _HatLisansBillingPriceCardState();
}

class _HatLisansBillingPriceCardState
    extends ConsumerState<HatLisansBillingPriceCard> {
  final _lineTry = TextEditingController();
  final _lineUsd = TextEditingController();
  final _gmp3Try = TextEditingController();
  final _gmp3Usd = TextEditingController();
  final _irestoTry = TextEditingController();
  final _irestoUsd = TextEditingController();
  final _lineMonthTry = TextEditingController();
  final _lineMonthUsd = TextEditingController();
  final _gmp3MonthTry = TextEditingController();
  final _gmp3MonthUsd = TextEditingController();
  final _irestoMonthTry = TextEditingController();
  final _irestoMonthUsd = TextEditingController();
  final _lineTax = TextEditingController(text: '20');
  final _gmp3Tax = TextEditingController(text: '20');
  final _irestoTax = TextEditingController(text: '20');
  final _lineTitle = TextEditingController(text: _kLinePaymentTitle);
  final _gmp3Title = TextEditingController(text: _kGmp3PaymentTitle);
  final _irestoTitle = TextEditingController(text: _kIrestoPaymentTitle);
  String _currency = 'TRY';
  String _period = 'yearly';
  String? _lineProductId;
  String? _gmp3ProductId;
  String? _irestoProductId;
  bool _hydrated = false;
  bool _saving = false;
  bool _expanded = false;

  @override
  void dispose() {
    _lineTry.dispose();
    _lineUsd.dispose();
    _gmp3Try.dispose();
    _gmp3Usd.dispose();
    _irestoTry.dispose();
    _irestoUsd.dispose();
    _lineMonthTry.dispose();
    _lineMonthUsd.dispose();
    _gmp3MonthTry.dispose();
    _gmp3MonthUsd.dispose();
    _irestoMonthTry.dispose();
    _irestoMonthUsd.dispose();
    _lineTax.dispose();
    _gmp3Tax.dispose();
    _irestoTax.dispose();
    _lineTitle.dispose();
    _gmp3Title.dispose();
    _irestoTitle.dispose();
    super.dispose();
  }

  void _hydrate(Map<String, dynamic> catalog) {
    if (_hydrated || catalog.isEmpty) return;
    final settings = _asMap(catalog['settings']);
    _lineTry.text = _priceText(settings['linePriceTry']);
    _lineUsd.text = _priceText(settings['linePriceUsd']);
    _gmp3Try.text = _priceText(settings['gmp3PriceTry']);
    _gmp3Usd.text = _priceText(settings['gmp3PriceUsd']);
    _irestoTry.text = _priceText(settings['irestoPriceTry']);
    _irestoUsd.text = _priceText(settings['irestoPriceUsd']);
    _lineMonthTry.text = _priceText(settings['linePriceMonthTry']);
    _lineMonthUsd.text = _priceText(settings['linePriceMonthUsd']);
    _gmp3MonthTry.text = _priceText(settings['gmp3PriceMonthTry']);
    _gmp3MonthUsd.text = _priceText(settings['gmp3PriceMonthUsd']);
    _irestoMonthTry.text = _priceText(settings['irestoPriceMonthTry']);
    _irestoMonthUsd.text = _priceText(settings['irestoPriceMonthUsd']);
    _lineTax.text = _taxText(settings['lineTaxRate']);
    _gmp3Tax.text = _taxText(settings['gmp3TaxRate']);
    _irestoTax.text = _taxText(settings['irestoTaxRate']);
    _lineTitle.text = _titleText(
      settings['linePaymentTitle'],
      _kLinePaymentTitle,
    );
    _gmp3Title.text = _titleText(
      settings['gmp3PaymentTitle'],
      _kGmp3PaymentTitle,
    );
    _irestoTitle.text = _titleText(
      settings['irestoPaymentTitle'],
      _kIrestoPaymentTitle,
    );
    _currency =
        (settings['defaultCurrency'] ?? 'TRY').toString().toUpperCase() == 'USD'
        ? 'USD'
        : 'TRY';
    _period = _periodFrom(settings['defaultPeriod']);
    _lineProductId = settings['lineProductId']?.toString();
    _gmp3ProductId = settings['gmp3ProductId']?.toString();
    _irestoProductId = settings['irestoProductId']?.toString();
    _hydrated = true;
  }

  String _fmtAmount(TextEditingController tryC, TextEditingController usdC) {
    if (_currency == 'USD') {
      return usdC.text.trim().isEmpty ? '—' : '\$${usdC.text.trim()}';
    }
    return tryC.text.trim().isEmpty ? '—' : '₺${tryC.text.trim()}';
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null || _saving) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'saveHatLisansBillingSettings',
          'settings': {
            'currency': _currency,
            'period': _period,
            'defaultPeriod': _period,
            'lineProductId': _lineProductId,
            'gmp3ProductId': _gmp3ProductId,
            'irestoProductId': _irestoProductId,
            'linePriceTry': _lineTry.text.trim(),
            'linePriceUsd': _lineUsd.text.trim(),
            'gmp3PriceTry': _gmp3Try.text.trim(),
            'gmp3PriceUsd': _gmp3Usd.text.trim(),
            'irestoPriceTry': _irestoTry.text.trim(),
            'irestoPriceUsd': _irestoUsd.text.trim(),
            'linePriceMonthTry': _lineMonthTry.text.trim(),
            'linePriceMonthUsd': _lineMonthUsd.text.trim(),
            'gmp3PriceMonthTry': _gmp3MonthTry.text.trim(),
            'gmp3PriceMonthUsd': _gmp3MonthUsd.text.trim(),
            'irestoPriceMonthTry': _irestoMonthTry.text.trim(),
            'irestoPriceMonthUsd': _irestoMonthUsd.text.trim(),
            'lineTaxRate': _lineTax.text.trim(),
            'gmp3TaxRate': _gmp3Tax.text.trim(),
            'irestoTaxRate': _irestoTax.text.trim(),
            'linePaymentTitle': _lineTitle.text.trim(),
            'gmp3PaymentTitle': _gmp3Title.text.trim(),
            'irestoPaymentTitle': _irestoTitle.text.trim(),
          },
        },
      );
      ref.invalidate(hatLisansBillingCatalogProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hat / GMP3 / iResto KDV, aylık ve yıllık fiyatlar kaydedildi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catalogAsync = ref.watch(hatLisansBillingCatalogProvider);
    final products =
        ref.watch(productsProvider(null)).asData?.value ?? const <Product>[];
    catalogAsync.whenData((catalog) {
      if (_hydrated || catalog.isEmpty) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _hydrated) return;
        setState(() => _hydrate(catalog));
      });
    });
    final monthly = _period == 'monthly';
    final hatAmt = monthly
        ? _fmtAmount(_lineMonthTry, _lineMonthUsd)
        : _fmtAmount(_lineTry, _lineUsd);
    final gmp3Amt = monthly
        ? _fmtAmount(_gmp3MonthTry, _gmp3MonthUsd)
        : _fmtAmount(_gmp3Try, _gmp3Usd);
    final irestoAmt = monthly
        ? _fmtAmount(_irestoMonthTry, _irestoMonthUsd)
        : _fmtAmount(_irestoTry, _irestoUsd);

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hat / GMP3 / iResto fiyatları',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        '${monthly ? 'Aylık' : 'Yıllık'} · Hat $hatAmt · GMP3 $gmp3Amt · iResto $irestoAmt · KDV %${_lineTax.text.trim().isEmpty ? '20' : _lineTax.text}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() => _expanded = !_expanded),
                  child: Text(_expanded ? 'Gizle' : 'Düzenle'),
                ),
                Icon(
                  _expanded ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                  size: 18,
                  color: AppTheme.textMuted,
                ),
              ],
            ),
          ),
          Visibility(
            visible: _expanded,
            maintainState: true,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'yearly',
                          label: Text('Yıllık fiyat'),
                        ),
                        ButtonSegment(
                          value: 'monthly',
                          label: Text('Aylık fiyat'),
                        ),
                      ],
                      selected: {_period},
                      onSelectionChanged: _saving
                          ? null
                          : (value) {
                              FocusManager.instance.primaryFocus?.unfocus();
                              setState(() => _period = value.first);
                            },
                    ),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'TRY', label: Text('Fatura TL')),
                        ButtonSegment(value: 'USD', label: Text('Fatura USD')),
                      ],
                      selected: {_currency},
                      onSelectionChanged: _saving
                          ? null
                          : (value) => setState(() => _currency = value.first),
                    ),
                    FilledButton.tonal(
                      onPressed: _saving ? null : _save,
                      child: Text(_saving ? 'Kaydediliyor…' : 'Kaydet'),
                    ),
                  ],
                ),
                const Gap(6),
                Text(
                  'Aylık ve yıllık fiyatlar ayrıdır. Dönemi seçip fiyatı girin; Kaydet ikisini de saklar.',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
                const Gap(8),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 900;
                    final hat = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProductPickField(
                          label: 'Hat kalemi',
                          products: products,
                          selectedId: _lineProductId,
                          enabled: !_saving,
                          onSelected: (product) {
                            setState(() => _lineProductId = product.id);
                            if (_lineTax.text.trim().isEmpty) {
                              _lineTax.text = _taxText(product.taxRate);
                            }
                            final price = _priceText(product.salePrice);
                            if (price.isEmpty) return;
                            if (product.currency.toUpperCase() == 'USD') {
                              if (_lineUsd.text.trim().isEmpty)
                                _lineUsd.text = price;
                            } else if (_lineTry.text.trim().isEmpty) {
                              _lineTry.text = price;
                            }
                          },
                        ),
                        const Gap(8),
                        _TaxRateField(
                          id: 'settings-line',
                          controller: _lineTax,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PeriodPriceRow(
                          idPrefix: 'settings-line',
                          kindLabel: 'Hat',
                          period: _period,
                          currency: _currency,
                          monthTry: _lineMonthTry,
                          monthUsd: _lineMonthUsd,
                          yearTry: _lineTry,
                          yearUsd: _lineUsd,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PaymentTitleField(
                          id: 'settings-line',
                          controller: _lineTitle,
                          label: 'Ödeme açıklaması',
                          enabled: !_saving,
                        ),
                      ],
                    );
                    final gmp3 = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProductPickField(
                          label: 'GMP3 kalemi',
                          products: products,
                          selectedId: _gmp3ProductId,
                          enabled: !_saving,
                          onSelected: (product) {
                            setState(() => _gmp3ProductId = product.id);
                            if (_gmp3Tax.text.trim().isEmpty) {
                              _gmp3Tax.text = _taxText(product.taxRate);
                            }
                            final price = _priceText(product.salePrice);
                            if (price.isEmpty) return;
                            if (product.currency.toUpperCase() == 'USD') {
                              if (_gmp3Usd.text.trim().isEmpty)
                                _gmp3Usd.text = price;
                            } else if (_gmp3Try.text.trim().isEmpty) {
                              _gmp3Try.text = price;
                            }
                          },
                        ),
                        const Gap(8),
                        _TaxRateField(
                          id: 'settings-gmp3',
                          controller: _gmp3Tax,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PeriodPriceRow(
                          idPrefix: 'settings-gmp3',
                          kindLabel: 'GMP3',
                          period: _period,
                          currency: _currency,
                          monthTry: _gmp3MonthTry,
                          monthUsd: _gmp3MonthUsd,
                          yearTry: _gmp3Try,
                          yearUsd: _gmp3Usd,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PaymentTitleField(
                          id: 'settings-gmp3',
                          controller: _gmp3Title,
                          label: 'Ödeme açıklaması',
                          enabled: !_saving,
                        ),
                      ],
                    );
                    final iresto = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ProductPickField(
                          label: 'iResto (opsiyonel)',
                          products: products,
                          selectedId: _irestoProductId,
                          enabled: !_saving,
                          onSelected: (product) {
                            setState(() => _irestoProductId = product.id);
                            if (_irestoTax.text.trim().isEmpty) {
                              _irestoTax.text = _taxText(product.taxRate);
                            }
                            final price = _priceText(product.salePrice);
                            if (price.isEmpty) return;
                            if (product.currency.toUpperCase() == 'USD') {
                              if (_irestoUsd.text.trim().isEmpty) {
                                _irestoUsd.text = price;
                              }
                            } else if (_irestoTry.text.trim().isEmpty) {
                              _irestoTry.text = price;
                            }
                          },
                        ),
                        const Gap(8),
                        _TaxRateField(
                          id: 'settings-iresto',
                          controller: _irestoTax,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PeriodPriceRow(
                          idPrefix: 'settings-iresto',
                          kindLabel: 'iResto',
                          period: _period,
                          currency: _currency,
                          monthTry: _irestoMonthTry,
                          monthUsd: _irestoMonthUsd,
                          yearTry: _irestoTry,
                          yearUsd: _irestoUsd,
                          enabled: !_saving,
                        ),
                        const Gap(8),
                        _PaymentTitleField(
                          id: 'settings-iresto',
                          controller: _irestoTitle,
                          label: 'Ödeme açıklaması',
                          enabled: !_saving,
                        ),
                      ],
                    );
                    if (narrow) {
                      return Column(
                        children: [
                          hat,
                          const Gap(12),
                          gmp3,
                          const Gap(12),
                          iresto,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: hat),
                        const Gap(12),
                        Expanded(child: gmp3),
                        const Gap(12),
                        Expanded(child: iresto),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class HatLisansInvoicesTab extends ConsumerWidget {
  const HatLisansInvoicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final payment = ref.watch(hatLisansInvoicePaymentFilterProvider);
    final invoicesAsync = ref.watch(hatLisansInvoicesProvider);
    final items = invoicesAsync.asData?.value ?? const <Invoice>[];

    return AppPhoneScrollColumn(
      padding: const EdgeInsets.all(10),
      header: [
        AppCard(
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final filter = SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'pending',
                    label: Text('Ödeme bekleyen'),
                  ),
                  ButtonSegment(value: 'paid', label: Text('Ödenenler')),
                ],
                selected: {payment},
                onSelectionChanged: (value) {
                  ref
                      .read(hatLisansInvoicePaymentFilterProvider.notifier)
                      .set(value.first);
                },
              );
              if (constraints.maxWidth < 720) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    filter,
                    const Gap(8),
                    Text(
                      'Bu sekmedeki faturalar taslaktır. Ödeme sonrası satış '
                      'faturasına döner; Maliye gönderimiyle kapanır.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                );
              }
              return Row(
                children: [
                  filter,
                  const Gap(12),
                  Expanded(
                    child: Text(
                      'Taslak faturalar E-Fatura listesine satış olarak düşmez. '
                      'Ödeme + Maliye gönderimi sonrası kapanır.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ),
                  AppBadge(
                    label: '${items.length}',
                    tone: AppBadgeTone.neutral,
                    dense: true,
                  ),
                ],
              );
            },
          ),
        ),
        const Gap(8),
        const HatLisansBillingPriceCard(),
        const Gap(8),
      ],
      body: ({required nested}) => invoicesAsync.when(
        data: (rows) {
          if (rows.isEmpty) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: Text('Bu listede fatura yok.')),
            );
          }
          return ListView.separated(
            padding: nested
                ? EdgeInsets.zero
                : const EdgeInsets.only(bottom: 120),
            shrinkWrap: nested,
            physics: AppPhoneScrollColumn.physicsFor(nested: nested),
            itemCount: rows.length,
            separatorBuilder: (_, _) => const Gap(8),
            itemBuilder: (context, index) {
              return _HatLisansInvoiceRow(invoice: rows[index]);
            },
          );
        },
        loading: () => const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (error, _) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Center(child: Text('Yüklenemedi: $error')),
        ),
      ),
    );
  }
}

class _EditHatLisansLine {
  _EditHatLisansLine({
    required this.productId,
    required this.unit,
    required this.taxRate,
    required String description,
    required String quantity,
    required String unitPrice,
  }) : description = TextEditingController(text: description),
       quantity = TextEditingController(text: quantity),
       unitPrice = TextEditingController(text: unitPrice);

  final String? productId;
  final String unit;
  final double taxRate;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unitPrice;

  void dispose() {
    description.dispose();
    quantity.dispose();
    unitPrice.dispose();
  }
}

class _EditHatLisansInvoiceDialog extends ConsumerStatefulWidget {
  const _EditHatLisansInvoiceDialog({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_EditHatLisansInvoiceDialog> createState() =>
      _EditHatLisansInvoiceDialogState();
}

class _EditHatLisansInvoiceDialogState
    extends ConsumerState<_EditHatLisansInvoiceDialog> {
  late final List<_EditHatLisansLine> _lines;
  late bool _pricesIncludeVat;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final invoice = widget.invoice;
    _pricesIncludeVat = invoice.pricesIncludeVat;
    _lines = [
      for (final item in invoice.items)
        _EditHatLisansLine(
          productId: item.productId,
          unit: item.unit,
          taxRate: item.taxRate,
          description: item.description,
          quantity: _priceText(item.quantity),
          unitPrice: _priceText(
            _pricesIncludeVat
                ? item.unitPrice * (1 + item.taxRate / 100)
                : item.unitPrice,
          ),
        ),
    ];
  }

  @override
  void dispose() {
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  void _toggleVat(bool value) {
    if (value == _pricesIncludeVat) return;
    setState(() {
      for (final line in _lines) {
        final entered = double.tryParse(
          line.unitPrice.text.replaceAll(',', '.'),
        );
        if (entered == null || line.taxRate <= 0) continue;
        if (value) {
          line.unitPrice.text = _priceText(entered * (1 + line.taxRate / 100));
        } else {
          line.unitPrice.text = _priceText(entered / (1 + line.taxRate / 100));
        }
      }
      _pricesIncludeVat = value;
    });
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null || _saving) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateHatLisansInvoice',
          'invoiceId': widget.invoice.id,
          'pricesIncludeVat': _pricesIncludeVat,
          'items': [
            for (final line in _lines)
              {
                'productId': line.productId,
                'description': line.description.text.trim(),
                'quantity': line.quantity.text.trim(),
                'unit': line.unit,
                'unitPrice': line.unitPrice.text.trim(),
                'taxRate': line.taxRate,
              },
          ],
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Faturayı düzenle'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('KDV dahil'),
                value: _pricesIncludeVat,
                onChanged: _saving ? null : _toggleVat,
              ),
              const Gap(8),
              for (final line in _lines) ...[
                TextField(
                  controller: line.description,
                  enabled: !_saving,
                  decoration: const InputDecoration(
                    labelText: 'Ödeme açıklaması',
                    isDense: true,
                  ),
                ),
                const Gap(8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: line.quantity,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Adet',
                          isDense: true,
                        ),
                      ),
                    ),
                    const Gap(8),
                    Expanded(
                      child: TextField(
                        controller: line.unitPrice,
                        enabled: !_saving,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _pricesIncludeVat
                              ? 'Birim fiyat (KDV dahil)'
                              : 'Birim fiyat',
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(14),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}

class _HatLisansInvoiceRow extends ConsumerStatefulWidget {
  const _HatLisansInvoiceRow({required this.invoice});

  final Invoice invoice;

  @override
  ConsumerState<_HatLisansInvoiceRow> createState() =>
      _HatLisansInvoiceRowState();
}

class _HatLisansInvoiceRowState extends ConsumerState<_HatLisansInvoiceRow> {
  bool _busy = false;

  String _statusLabel(Invoice invoice) {
    if (invoice.isEInvoiceClosed && invoice.remainingAmount <= 0.009) {
      return 'Kapandı';
    }
    if (invoice.remainingAmount <= 0.009) {
      return invoice.status == 'paid' ? 'Ödendi' : 'Ödendi · Maliye bekliyor';
    }
    if (invoice.status == 'draft') return 'Taslak · ödeme bekliyor';
    if (invoice.status == 'partial') return 'Kısmi ödeme';
    return 'Satış · ödeme bekliyor';
  }

  AppBadgeTone _statusTone(Invoice invoice) {
    if (invoice.isEInvoiceClosed && invoice.remainingAmount <= 0.009) {
      return AppBadgeTone.success;
    }
    if (invoice.remainingAmount <= 0.009) return AppBadgeTone.warning;
    if (invoice.status == 'draft') return AppBadgeTone.neutral;
    return AppBadgeTone.primary;
  }

  Future<void> _withBusy(Future<void> Function() run) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await run();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _mailLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    var email = (invoice.customerEmail ?? '').trim();
    if (!email.contains('@')) {
      final controller = TextEditingController();
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mail ile ödeme linki'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'E-posta'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Gönder'),
            ),
          ],
        ),
      );
      email = controller.text.trim();
      controller.dispose();
      if (ok != true || !email.contains('@')) return;
    }
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'sendInvoicePaymentLinkEmail',
        'invoiceIds': [invoice.id],
        'email': email,
      },
    );
    ref.invalidate(hatLisansInvoicesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Ödeme linki maili gönderildi.')),
    );
  }

  Future<void> _whatsAppLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createInvoicePaymentLink',
        'invoiceIds': [invoice.id],
      },
    );
    final paymentUrl = response['paymentUrl']?.toString() ?? '';
    if (paymentUrl.isEmpty) {
      throw Exception('Ödeme linki alınamadı');
    }
    CustomerDetail? customer;
    try {
      customer = await ref.read(
        customerDetailProvider(invoice.customerId).future,
      );
    } catch (_) {}
    if (!mounted) return;
    ref.invalidate(hatLisansInvoicesProvider);
    await shareInvoicePaymentLinkWithWhatsApp(
      context: context,
      paymentUrl: paymentUrl,
      amountLabel: _money(invoice.currency).format(invoice.remainingAmount),
      invoiceLabels: [formatInvoiceNumberForDisplay(invoice.invoiceNumber)],
      customerName: invoice.customerName,
      customer: customer,
      paymentLines: [for (final item in invoice.items) item.description],
    );
  }

  Future<void> _copyLink() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansPayable) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createInvoicePaymentLink',
        'invoiceIds': [invoice.id],
      },
    );
    final paymentUrl = response['paymentUrl']?.toString() ?? '';
    if (paymentUrl.isEmpty) {
      throw Exception('Ödeme linki alınamadı');
    }
    await Clipboard.setData(ClipboardData(text: paymentUrl));
    ref.invalidate(hatLisansInvoicesProvider);
    ref.invalidate(invoicesProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ödeme linki kopyalandı.')));
  }

  Future<void> _edit() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansMutable) return;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _EditHatLisansInvoiceDialog(invoice: invoice),
    );
    if (saved != true || !mounted) return;
    ref.invalidate(hatLisansInvoicesProvider);
    ref.invalidate(invoicesProvider);
    ref.read(hatLisansTotalsTickProvider.notifier).bump();
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fatura güncellendi.')));
  }

  Future<void> _delete() async {
    final invoice = widget.invoice;
    if (!invoice.isHatLisansMutable) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faturayı sil'),
        content: Text(
          '${formatInvoiceNumberForDisplay(invoice.invoiceNumber)} taslak faturası silinsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    await apiClient.postJson(
      '/mutate',
      body: {'op': 'deleteHatLisansInvoice', 'invoiceId': invoice.id},
    );
    ref.invalidate(hatLisansInvoicesProvider);
    ref.invalidate(invoicesProvider);
    ref.read(hatLisansTotalsTickProvider.notifier).bump();
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fatura silindi.')));
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final money = _money(invoice.currency);
    final items = invoice.items;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  invoice.customerName?.trim().isNotEmpty == true
                      ? invoice.customerName!
                      : '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.text,
                  ),
                ),
              ),
              AppBadge(
                label: _statusLabel(invoice),
                tone: _statusTone(invoice),
                dense: true,
              ),
            ],
          ),
          const Gap(4),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              AppBadge(
                label: formatInvoiceNumberForDisplay(invoice.invoiceNumber),
                tone: AppBadgeTone.neutral,
                dense: true,
              ),
              AppBadge(
                label: money.format(invoice.grandTotal),
                tone: AppBadgeTone.primary,
                dense: true,
              ),
              if (invoice.remainingAmount > 0.009)
                AppBadge(
                  label: 'Kalan ${money.format(invoice.remainingAmount)}',
                  tone: AppBadgeTone.warning,
                  dense: true,
                ),
              for (final item in items.take(3))
                AppBadge(
                  label:
                      '${item.description} × ${item.quantity.toStringAsFixed(item.quantity % 1 == 0 ? 0 : 2)}',
                  tone: AppBadgeTone.neutral,
                  dense: true,
                ),
            ],
          ),
          if (invoice.isHatLisansPayable || invoice.isHatLisansMutable) ...[
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (invoice.isHatLisansMutable) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _withBusy(_edit),
                    icon: const Icon(LucideIcons.pencil, size: 16),
                    label: const Text('Düzenle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _withBusy(_delete),
                    icon: const Icon(LucideIcons.trash2, size: 16),
                    label: const Text('Sil'),
                  ),
                ],
                if (invoice.isHatLisansPayable) ...[
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _withBusy(_copyLink),
                    icon: const Icon(LucideIcons.link, size: 16),
                    label: const Text('Ödeme linki'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _withBusy(_mailLink),
                    icon: const Icon(LucideIcons.mail, size: 16),
                    label: const Text('Mail'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : () => _withBusy(_whatsAppLink),
                    icon: const Icon(LucideIcons.messageCircle, size: 16),
                    label: const Text('WhatsApp'),
                  ),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}
