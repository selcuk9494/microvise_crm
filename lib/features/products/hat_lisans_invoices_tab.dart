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
import '../customers/customer_detail_screen.dart';
import '../e_invoice/e_invoice_whatsapp_share.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';

final hatLisansInvoicePaymentFilterProvider =
    NotifierProvider<HatLisansInvoicePaymentFilterNotifier, String>(
      HatLisansInvoicePaymentFilterNotifier.new,
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
  String _currency = 'TRY';
  String? _lineProductId;
  String? _gmp3ProductId;
  String? _irestoProductId;
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _lineTry.dispose();
    _lineUsd.dispose();
    _gmp3Try.dispose();
    _gmp3Usd.dispose();
    _irestoTry.dispose();
    _irestoUsd.dispose();
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
    _currency = (settings['defaultCurrency'] ?? 'TRY').toString().toUpperCase() ==
            'USD'
        ? 'USD'
        : 'TRY';
    _lineProductId = settings['lineProductId']?.toString();
    _gmp3ProductId = settings['gmp3ProductId']?.toString();
    _irestoProductId = settings['irestoProductId']?.toString();
    _hydrated = true;
  }

  void _applyProductPrice(Product product, {required String kind}) {
    final price = _priceText(product.salePrice);
    if (price.isEmpty) return;
    final isUsd = product.currency.toUpperCase() == 'USD';
    setState(() {
      switch (kind) {
        case 'line':
          _lineProductId = product.id;
          if (isUsd) {
            if (_lineUsd.text.trim().isEmpty) _lineUsd.text = price;
          } else if (_lineTry.text.trim().isEmpty) {
            _lineTry.text = price;
          }
        case 'gmp3':
          _gmp3ProductId = product.id;
          if (isUsd) {
            if (_gmp3Usd.text.trim().isEmpty) _gmp3Usd.text = price;
          } else if (_gmp3Try.text.trim().isEmpty) {
            _gmp3Try.text = price;
          }
        case 'iresto':
          _irestoProductId = product.id;
          if (isUsd) {
            if (_irestoUsd.text.trim().isEmpty) _irestoUsd.text = price;
          } else if (_irestoTry.text.trim().isEmpty) {
            _irestoTry.text = price;
          }
      }
    });
  }

  Future<void> _submit() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null || _saving) return;
    final selectedPrice = _currency == 'USD'
        ? (_lineUsd.text.trim().isNotEmpty ||
              _gmp3Usd.text.trim().isNotEmpty ||
              _irestoUsd.text.trim().isNotEmpty)
        : (_lineTry.text.trim().isNotEmpty ||
              _gmp3Try.text.trim().isNotEmpty ||
              _irestoTry.text.trim().isNotEmpty);
    if (!selectedPrice) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _currency == 'USD'
                ? 'USD fatura için Hat ve GMP3 dolar fiyatı girin.'
                : 'TL fatura için Hat ve GMP3 TL fiyatı girin.',
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
            'lineProductId': _lineProductId,
            'gmp3ProductId': _gmp3ProductId,
            'irestoProductId': _irestoProductId,
            'lineUnitPriceTry': _lineTry.text.trim(),
            'lineUnitPriceUsd': _lineUsd.text.trim(),
            'gmp3UnitPriceTry': _gmp3Try.text.trim(),
            'gmp3UnitPriceUsd': _gmp3Usd.text.trim(),
            'irestoUnitPriceTry': _irestoTry.text.trim(),
            'irestoUnitPriceUsd': _irestoUsd.text.trim(),
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
    final hatCount = widget.targets.fold<int>(0, (sum, e) => sum + e.linesTotal);
    final gmp3Count = widget.targets.fold<int>(0, (sum, e) => sum + e.gmp3Total);
    final irestoCount = widget.targets.fold<int>(
      0,
      (sum, e) => sum + e.irestoTotal,
    );

    return AlertDialog(
      title: const Text('Hat & Lisans faturası'),
      content: SizedBox(
        width: 560,
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
                'Kalem adları Ürün/Hizmet kataloğundan seçilir. Fiyatları bu ekranda '
                'TL ve USD olarak girin; faturanın para birimini aşağıdan seçin.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
              const Gap(12),
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
              const Gap(14),
              _ProductPickField(
                label: 'Hat kalemi',
                products: products,
                selectedId: _lineProductId,
                enabled: !_saving,
                onSelected: (product) =>
                    _applyProductPrice(product, kind: 'line'),
              ),
              const Gap(8),
              _DualPriceRow(
                tryController: _lineTry,
                usdController: _lineUsd,
                tryLabel: 'Hat TL',
                usdLabel: 'Hat USD',
                highlightUsd: _currency == 'USD',
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
              _DualPriceRow(
                tryController: _gmp3Try,
                usdController: _gmp3Usd,
                tryLabel: 'GMP3 TL',
                usdLabel: 'GMP3 USD',
                highlightUsd: _currency == 'USD',
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
              _DualPriceRow(
                tryController: _irestoTry,
                usdController: _irestoUsd,
                tryLabel: 'iResto TL',
                usdLabel: 'iResto USD',
                highlightUsd: _currency == 'USD',
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

class _DualPriceRow extends StatelessWidget {
  const _DualPriceRow({
    required this.tryController,
    required this.usdController,
    required this.tryLabel,
    required this.usdLabel,
    required this.highlightUsd,
    required this.enabled,
  });

  final TextEditingController tryController;
  final TextEditingController usdController;
  final String tryLabel;
  final String usdLabel;
  final bool highlightUsd;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: tryController,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: tryLabel,
              prefixText: '₺ ',
              filled: !highlightUsd,
              isDense: true,
            ),
          ),
        ),
        const Gap(8),
        Expanded(
          child: TextField(
            controller: usdController,
            enabled: enabled,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: usdLabel,
              prefixText: r'$ ',
              filled: highlightUsd,
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
  String _currency = 'TRY';
  String? _lineProductId;
  String? _gmp3ProductId;
  String? _irestoProductId;
  bool _hydrated = false;
  bool _saving = false;

  @override
  void dispose() {
    _lineTry.dispose();
    _lineUsd.dispose();
    _gmp3Try.dispose();
    _gmp3Usd.dispose();
    _irestoTry.dispose();
    _irestoUsd.dispose();
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
    _currency =
        (settings['defaultCurrency'] ?? 'TRY').toString().toUpperCase() ==
            'USD'
        ? 'USD'
        : 'TRY';
    _lineProductId = settings['lineProductId']?.toString();
    _gmp3ProductId = settings['gmp3ProductId']?.toString();
    _irestoProductId = settings['irestoProductId']?.toString();
    _hydrated = true;
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
            'lineProductId': _lineProductId,
            'gmp3ProductId': _gmp3ProductId,
            'irestoProductId': _irestoProductId,
            'linePriceTry': _lineTry.text.trim(),
            'linePriceUsd': _lineUsd.text.trim(),
            'gmp3PriceTry': _gmp3Try.text.trim(),
            'gmp3PriceUsd': _gmp3Usd.text.trim(),
            'irestoPriceTry': _irestoTry.text.trim(),
            'irestoPriceUsd': _irestoUsd.text.trim(),
          },
        },
      );
      ref.invalidate(hatLisansBillingCatalogProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hat / GMP3 fiyatları kaydedildi.')),
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

    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Hat / GMP3 fiyatları',
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
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
            'Kalem adını Ürün/Hizmet kataloğundan seçin. Her kalem için TL ve USD '
            'birim fiyatı girin; fatura oluştururken seçilen para birimi kullanılır.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
          ),
          const Gap(10),
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
                      final price = _priceText(product.salePrice);
                      if (price.isEmpty) return;
                      if (product.currency.toUpperCase() == 'USD') {
                        if (_lineUsd.text.trim().isEmpty) _lineUsd.text = price;
                      } else if (_lineTry.text.trim().isEmpty) {
                        _lineTry.text = price;
                      }
                    },
                  ),
                  const Gap(8),
                  _DualPriceRow(
                    tryController: _lineTry,
                    usdController: _lineUsd,
                    tryLabel: 'Hat TL',
                    usdLabel: 'Hat USD',
                    highlightUsd: _currency == 'USD',
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
                      final price = _priceText(product.salePrice);
                      if (price.isEmpty) return;
                      if (product.currency.toUpperCase() == 'USD') {
                        if (_gmp3Usd.text.trim().isEmpty) _gmp3Usd.text = price;
                      } else if (_gmp3Try.text.trim().isEmpty) {
                        _gmp3Try.text = price;
                      }
                    },
                  ),
                  const Gap(8),
                  _DualPriceRow(
                    tryController: _gmp3Try,
                    usdController: _gmp3Usd,
                    tryLabel: 'GMP3 TL',
                    usdLabel: 'GMP3 USD',
                    highlightUsd: _currency == 'USD',
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
                  _DualPriceRow(
                    tryController: _irestoTry,
                    usdController: _irestoUsd,
                    tryLabel: 'iResto TL',
                    usdLabel: 'iResto USD',
                    highlightUsd: _currency == 'USD',
                    enabled: !_saving,
                  ),
                ],
              );
              if (narrow) {
                return Column(
                  children: [hat, const Gap(12), gmp3, const Gap(12), iresto],
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

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
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
          Expanded(
            child: invoicesAsync.when(
              data: (rows) {
                if (rows.isEmpty) {
                  return const Center(
                    child: Text('Bu listede fatura yok.'),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.only(bottom: 120),
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, index) {
                    return _HatLisansInvoiceRow(invoice: rows[index]);
                  },
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => Center(child: Text('Yüklenemedi: $error')),
            ),
          ),
        ],
      ),
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Ödeme linki maili gönderildi.')));
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
          if (invoice.isHatLisansPayable) ...[
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
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
            ),
          ],
        ],
      ),
    );
  }
}
