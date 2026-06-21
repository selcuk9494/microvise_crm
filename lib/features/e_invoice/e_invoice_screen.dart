import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../customers/customer_model.dart';
import '../customers/customers_providers.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import 'e_invoice_form_screen.dart';
import 'e_invoice_print.dart';

final eInvoiceSettingsProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      final local = await _loadLocalEInvoiceSettings();
      final base = {..._defaultSettings, ...local};
      if (apiClient == null) return Map<String, dynamic>.from(base);
      try {
        final response = await apiClient
            .getJson('/e-invoice')
            .timeout(const Duration(seconds: 8));
        final remote = (response['settings'] as Map?)?.cast<String, dynamic>();
        return _mergeEInvoiceSettings(base, remote);
      } catch (error) {
        return {...base, '_offline_error': error.toString()};
      }
    });

const _localSettingsKey = 'microvise.e_invoice.settings.local';
const _secretSettingKeys = {
  'password',
  'akinsoft_vpn_password',
  'akinsoft_mssql_password',
};

Map<String, dynamic> _mergeEInvoiceSettings(
  Map<String, dynamic> base,
  Map<String, dynamic>? remote,
) {
  final merged = <String, dynamic>{...base};
  if (remote == null) return merged;
  for (final entry in remote.entries) {
    final value = entry.value;
    final isEmptySecret =
        _secretSettingKeys.contains(entry.key) &&
        (value == null || value.toString().isEmpty);
    if (isEmptySecret && (merged[entry.key] ?? '').toString().isNotEmpty) {
      continue;
    }
    merged[entry.key] = value;
  }
  return merged;
}

Future<Map<String, dynamic>> _loadLocalEInvoiceSettings() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_localSettingsKey);
  if (raw == null || raw.trim().isEmpty) return const {};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : const {};
  } catch (_) {
    return const {};
  }
}

Future<void> _saveLocalEInvoiceSettings(Map<String, dynamic> settings) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_localSettingsKey, jsonEncode(settings));
}

Uri _akinsoftUri(String path, [Map<String, String>? queryParameters]) {
  final normalizedPath = path.startsWith('/') ? path.substring(1) : path;
  final base = Uri.base;
  final isLocalWeb =
      base.host == '127.0.0.1' ||
      base.host == 'localhost' ||
      base.host == '::1';
  final uri = isLocalWeb && base.port != 4000
      ? Uri.parse('http://127.0.0.1:4000/api/akinsoft/')
      : base.resolve('/api/akinsoft/');
  return uri.resolve(normalizedPath).replace(queryParameters: queryParameters);
}

const _defaultSettings = <String, dynamic>{
  'environment': 'test',
  'api_base_url': 'https://test-efatura.maliye.gov.ct.tr/api',
  'token_url':
      'https://keycloak.maliye.gov.ct.tr/realms/vergi-stage/protocol/openid-connect/token',
  'client_id': 'efatura-frontend',
  'seller_vkn': '620009058',
  'seller_title': 'MICROVISE INNOVATION LTD',
  'seller_branch_code': '1',
  'seller_tax_office': 'Lefkoşa',
  'seller_city': 'LEFKOŞA',
  'seller_country_code': 'XCT',
  'seller_country': 'Kuzey Kıbrıs Türk Cumhuriyeti',
  'seller_address_line1': 'ATATÜRK CAD YENİŞEHİR EMEK 2 APT. DIŞ KAPI NO:1',
  'next_sales_number': 1,
  'next_purchase_number': 1,
  'akinsoft_sync_enabled': 'false',
  'akinsoft_mssql_port': '1433',
  'akinsoft_database_year': '2026',
  'akinsoft_database_pattern': 'WOLVOX8_MICO_{year}_WOLVOX',
};

class EInvoiceScreen extends ConsumerWidget {
  const EInvoiceScreen({super.key, this.section = 'faturalar'});

  final String section;

  static final _moneyTry = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(eInvoiceSettingsProvider);
    final child = switch (section) {
      'stok' => _ProductsTab(moneyTry: _moneyTry),
      'cari' => _AccountsTab(moneyTry: _moneyTry),
      'ayarlar' => const _SettingsTab(),
      _ => _InvoicesTab(moneyTry: _moneyTry),
    };
    final subtitle = switch (section) {
      'stok' => 'Stok ve hizmet tanımları, Akınsoft grup/alt grup ayrımı.',
      'cari' => 'Cari borç, tahsilat ve ödeme takibi.',
      'ayarlar' => 'Maliye ve Akınsoft entegrasyon ayarları.',
      _ => 'Alış/satış faturaları, stok, cari ve KKTC e-fatura gönderimi.',
    };

    return AppPageLayout(
      title: 'E-Fatura',
      subtitle: subtitle,
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(eInvoiceSettingsProvider);
            ref.invalidate(invoicesProvider);
            ref.invalidate(productsProvider(null));
            ref.invalidate(accountBalancesProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _openInvoiceTypeDialog(context, ref),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Fatura'),
        ),
      ],
      body: Column(
        children: [
          _StatusStrip(settingsAsync: settingsAsync),
          const Gap(12),
          Expanded(child: child),
        ],
      ),
    );
  }

  Future<void> _openInvoiceTypeDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final navigator = Navigator.of(context);
    final type = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Fatura Türü'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _TypeTile(
              icon: Icons.north_east_rounded,
              color: AppTheme.success,
              title: 'Satış Faturası',
              subtitle: 'Müşteriye kesilecek e-fatura',
              onTap: () => Navigator.of(context).pop('sales'),
            ),
            const Gap(8),
            _TypeTile(
              icon: Icons.south_west_rounded,
              color: AppTheme.warning,
              title: 'Alış Faturası',
              subtitle: 'Tedarikçi/cari borç kaydı',
              onTap: () => Navigator.of(context).pop('purchase'),
            ),
          ],
        ),
      ),
    );
    if (type == null || !context.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => EInvoiceFormScreen(invoiceType: type),
      ),
    );
    ref.invalidate(invoicesProvider);
    ref.invalidate(accountBalancesProvider);
  }
}

class _StatusStrip extends StatelessWidget {
  const _StatusStrip({required this.settingsAsync});

  final AsyncValue<Map<String, dynamic>> settingsAsync;

  @override
  Widget build(BuildContext context) {
    final settings = settingsAsync.value ?? const {};
    final env = (settings['environment'] ?? 'test').toString();
    final username = (settings['username'] ?? '').toString();
    final sellerVkn = (settings['seller_vkn'] ?? '').toString();
    final offline = (settings['_offline_error'] ?? '').toString().isNotEmpty;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InfoPill(
            icon: Icons.science_rounded,
            label: env == 'production' ? 'Canlı ortam' : 'Test ortamı',
            color: env == 'production' ? AppTheme.error : AppTheme.success,
          ),
          _InfoPill(
            icon: Icons.apartment_rounded,
            label: sellerVkn.isEmpty ? 'VKN bekleniyor' : 'VKN $sellerVkn',
            color: AppTheme.primary,
          ),
          _InfoPill(
            icon: Icons.key_rounded,
            label: offline
                ? 'Backend bekleniyor'
                : username.isEmpty
                ? 'Test kullanıcısı yok'
                : 'Kullanıcı hazır',
            color: offline
                ? AppTheme.error
                : username.isEmpty
                ? AppTheme.warning
                : AppTheme.success,
          ),
          Text(
            'Gönderimden önce payload hazırlayarak Maliye şemasını kontrol edebilirsiniz.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _InvoicesTab extends ConsumerStatefulWidget {
  const _InvoicesTab({required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> {
  static const int _invoiceRenderStep = 80;

  final Set<String> _selectedInvoiceIds = {};
  InvoiceFilter _filter = const InvoiceFilter(status: 'open');
  List<Invoice> _lastInvoices = const [];
  int _visibleInvoiceLimit = _invoiceRenderStep;
  bool _bulkDeleting = false;
  bool _bulkProcessing = false;
  bool _pullingAkinsoft = false;

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(_filter));
    final customersAsync = ref.watch(customersLookupProvider);

    if (invoicesAsync.hasValue) {
      _lastInvoices = invoicesAsync.value ?? const [];
    }
    if (invoicesAsync.isLoading && _lastInvoices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (invoicesAsync.hasError && _lastInvoices.isEmpty) {
      return _ErrorCard(
        message: 'Faturalar yüklenemedi: ${invoicesAsync.error}',
      );
    }
    final items = invoicesAsync.hasValue
        ? (invoicesAsync.value ?? const <Invoice>[])
        : _lastInvoices;
    final loadingFilteredItems =
        invoicesAsync.isLoading && _lastInvoices.isNotEmpty;

    final itemIds = items.map((invoice) => invoice.id).toSet();
    _selectedInvoiceIds.removeWhere((id) => !itemIds.contains(id));
    final visibleItems = items.take(_visibleInvoiceLimit).toList();
    final hasHiddenItems = visibleItems.length < items.length;
    final sales = items.where((e) => e.invoiceType == 'sales').length;
    final purchases = items.where((e) => e.invoiceType == 'purchase').length;
    final open = items
        .where((e) => e.status == 'open' || e.status == 'partial')
        .length;
    final tryTotal = items
        .where((e) => e.currency.toUpperCase() == 'TRY')
        .fold<double>(0, (sum, item) => sum + item.grandTotal);
    final usdTotal = items
        .where((e) => e.currency.toUpperCase() == 'USD')
        .fold<double>(0, (sum, item) => sum + item.grandTotal);
    final usdMoney = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: 'USD ',
      decimalDigits: 2,
    );

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (loadingFilteredItems) const LinearProgressIndicator(minHeight: 2),
        if (loadingFilteredItems) const Gap(10),
        _MetricsRow(
          metrics: [
            _Metric('Satış', sales.toString(), Icons.north_east_rounded),
            _Metric('Alış', purchases.toString(), Icons.south_west_rounded),
            _Metric(
              'Açık Fatura',
              open.toString(),
              Icons.pending_actions_rounded,
            ),
            _Metric(
              'TL Toplam',
              widget.moneyTry.format(tryTotal),
              Icons.summarize_rounded,
            ),
            _Metric(
              'USD Toplam',
              usdMoney.format(usdTotal),
              Icons.attach_money_rounded,
            ),
          ],
        ),
        const Gap(12),
        _InvoiceFiltersCard(
          filter: _filter,
          customersAsync: customersAsync,
          onChanged: (filter) {
            setState(() {
              _filter = filter;
              _visibleInvoiceLimit = _invoiceRenderStep;
              _selectedInvoiceIds.clear();
            });
          },
          onRefresh: () => ref.invalidate(invoicesProvider(_filter)),
        ),
        const Gap(12),
        if (items.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Henüz fatura yok. Yeni Fatura veya Akınsoft’tan Çek ile başlayın.',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _pullingAkinsoft ? null : _pullAkinsoftData,
                    icon: _pullingAkinsoft
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_rounded, size: 18),
                    label: const Text('Akınsoft’tan Çek'),
                  ),
                ],
              ),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final statusWidth = constraints.maxWidth < 900
                          ? 150.0
                          : 240.0;
                      return Row(
                        children: [
                          Checkbox(
                            value:
                                _selectedInvoiceIds.length == items.length &&
                                items.isNotEmpty,
                            tristate: true,
                            onChanged: _bulkDeleting
                                ? null
                                : (value) {
                                    setState(() {
                                      if (value == true) {
                                        _selectedInvoiceIds
                                          ..clear()
                                          ..addAll(items.map((e) => e.id));
                                      } else {
                                        _selectedInvoiceIds.clear();
                                      }
                                    });
                                  },
                          ),
                          const Gap(8),
                          SizedBox(
                            width: statusWidth,
                            child: Text(
                              _selectedInvoiceIds.isEmpty
                                  ? hasHiddenItems
                                        ? '${visibleItems.length} / ${items.length} fatura gösteriliyor'
                                        : '${items.length} fatura listeleniyor'
                                  : '${_selectedInvoiceIds.length} fatura seçildi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                          const Gap(8),
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                reverse: true,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    TextButton(
                                      onPressed: _bulkDeleting
                                          ? null
                                          : () => setState(() {
                                              _selectedInvoiceIds
                                                ..clear()
                                                ..addAll(
                                                  items.map((e) => e.id),
                                                );
                                            }),
                                      child: const Text('Tümünü Seç'),
                                    ),
                                    TextButton(
                                      onPressed: _bulkDeleting
                                          ? null
                                          : () => setState(
                                              _selectedInvoiceIds.clear,
                                            ),
                                      child: const Text('Temizle'),
                                    ),
                                    const Gap(8),
                                    OutlinedButton.icon(
                                      onPressed:
                                          _selectedInvoiceIds.isEmpty ||
                                              _bulkDeleting ||
                                              _bulkProcessing
                                          ? null
                                          : () => _collectSelected(items),
                                      icon: const Icon(
                                        Icons.payments_rounded,
                                        size: 18,
                                      ),
                                      label: const Text('Tahsilat Yap'),
                                    ),
                                    const Gap(8),
                                    OutlinedButton.icon(
                                      onPressed:
                                          _pullingAkinsoft ||
                                              _bulkDeleting ||
                                              _bulkProcessing
                                          ? null
                                          : _pullAkinsoftData,
                                      icon: _pullingAkinsoft
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_download_rounded,
                                              size: 18,
                                            ),
                                      label: const Text('Akınsoft’tan Çek'),
                                    ),
                                    const Gap(8),
                                    OutlinedButton.icon(
                                      onPressed:
                                          _selectedInvoiceIds.isEmpty ||
                                              _bulkDeleting ||
                                              _bulkProcessing
                                          ? null
                                          : () => _bulkPrepare(
                                              items,
                                              send: false,
                                            ),
                                      icon: _bulkProcessing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.data_object_rounded,
                                              size: 18,
                                            ),
                                      label: const Text('Payload Hazırla'),
                                    ),
                                    const Gap(8),
                                    FilledButton.icon(
                                      onPressed:
                                          _selectedInvoiceIds.isEmpty ||
                                              _bulkDeleting ||
                                              _bulkProcessing
                                          ? null
                                          : () =>
                                                _bulkPrepare(items, send: true),
                                      icon: _bulkProcessing
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.cloud_upload_rounded,
                                              size: 18,
                                            ),
                                      label: const Text('Test API’ye Gönder'),
                                    ),
                                    const Gap(8),
                                    FilledButton.icon(
                                      onPressed:
                                          _selectedInvoiceIds.isEmpty ||
                                              _bulkDeleting ||
                                              _bulkProcessing
                                          ? null
                                          : () => _deleteSelected(items),
                                      icon: _bulkDeleting
                                          ? const SizedBox(
                                              width: 16,
                                              height: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_forever_rounded,
                                              size: 18,
                                            ),
                                      label: const Text('Seçilenleri Sil'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
                LayoutBuilder(
                  builder: (context, constraints) {
                    if (constraints.maxWidth < 900) {
                      return Column(
                        children: [
                          for (final invoice in visibleItems)
                            _EInvoiceRow(
                              invoice: invoice,
                              selected: _selectedInvoiceIds.contains(
                                invoice.id,
                              ),
                              onSelectedChanged: _bulkDeleting
                                  ? null
                                  : (selected) {
                                      setState(() {
                                        if (selected) {
                                          _selectedInvoiceIds.add(invoice.id);
                                        } else {
                                          _selectedInvoiceIds.remove(
                                            invoice.id,
                                          );
                                        }
                                      });
                                    },
                            ),
                          if (hasHiddenItems)
                            _LoadMoreInvoicesButton(
                              visible: visibleItems.length,
                              total: items.length,
                              onPressed: () => setState(() {
                                _visibleInvoiceLimit += _invoiceRenderStep;
                              }),
                            ),
                        ],
                      );
                    }
                    final tableWidth = constraints.maxWidth < 1180
                        ? 1180.0
                        : constraints.maxWidth;
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: SizedBox(
                        width: tableWidth,
                        child: Column(
                          children: [
                            const _EInvoiceListHeader(),
                            for (final invoice in visibleItems)
                              _EInvoiceRow(
                                invoice: invoice,
                                selected: _selectedInvoiceIds.contains(
                                  invoice.id,
                                ),
                                onSelectedChanged: _bulkDeleting
                                    ? null
                                    : (selected) {
                                        setState(() {
                                          if (selected) {
                                            _selectedInvoiceIds.add(invoice.id);
                                          } else {
                                            _selectedInvoiceIds.remove(
                                              invoice.id,
                                            );
                                          }
                                        });
                                      },
                              ),
                            if (hasHiddenItems)
                              _LoadMoreInvoicesButton(
                                visible: visibleItems.length,
                                total: items.length,
                                onPressed: () => setState(() {
                                  _visibleInvoiceLimit += _invoiceRenderStep;
                                }),
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _deleteSelected(List<Invoice> visibleInvoices) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .toList(growable: false);
    if (selected.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçilen faturaları sil'),
        content: Text(
          '${selected.length} fatura ve bu faturalara ait kalemler kalıcı olarak silinsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final ids = selected.map((invoice) => invoice.id).toList(growable: false);
    setState(() => _bulkDeleting = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'invoice_items',
          'filters': [
            {'col': 'invoice_id', 'op': 'in', 'value': ids},
          ],
        },
      );
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'in', 'value': ids},
          ],
        },
      );
      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${ids.length} fatura silindi.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toplu silme başarısız: $error')));
    } finally {
      if (mounted) setState(() => _bulkDeleting = false);
    }
  }

  Future<void> _collectSelected(List<Invoice> visibleInvoices) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .where((invoice) => invoice.isActive && invoice.remainingAmount > 0)
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tahsil edilecek açık fatura yok.')),
      );
      return;
    }
    final total = selected.fold<double>(
      0,
      (sum, invoice) => sum + invoice.remainingAmount,
    );
    final currencies = selected.map((invoice) => invoice.currency).toSet();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Toplu tahsilat'),
        content: Text(
          '${selected.length} açık fatura için kalan tutarlar tahsilat/ödeme hareketi olarak işlensin mi?\n'
          'Toplam: ${currencies.length == 1 ? '${currencies.first} ${total.toStringAsFixed(2)}' : 'karışık para birimi'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('İşle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _bulkProcessing = true);
    try {
      for (final invoice in selected) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'transactions',
            'returning': 'row',
            'values': {
              'customer_id': invoice.customerId,
              'invoice_id': invoice.id,
              'transaction_type': invoice.invoiceType == 'purchase'
                  ? 'payment'
                  : 'collection',
              'amount': invoice.remainingAmount,
              'currency': invoice.currency,
              'exchange_rate': invoice.exchangeRate,
              'payment_method': 'bank',
              'transaction_date': DateTime.now().toIso8601String().substring(
                0,
                10,
              ),
              'description':
                  'Toplu e-fatura tahsilatı: ${invoice.invoiceNumber}',
            },
          },
        );
      }
      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${selected.length} fatura kapatıldı/işlendi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplu tahsilat başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _bulkPrepare(
    List<Invoice> visibleInvoices, {
    required bool send,
  }) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .toList(growable: false);
    if (selected.isEmpty) return;

    final confirmed = send
        ? await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Seçilenleri test API’ye gönder'),
              content: Text(
                '${selected.length} fatura için payload hazırlanıp test API’ye gönderilsin mi?',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Gönder'),
                ),
              ],
            ),
          )
        : true;
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _bulkProcessing = true);
    final results = <Map<String, dynamic>>[];
    try {
      for (final invoice in selected) {
        try {
          final response = await apiClient.postJson(
            '/e-invoice',
            body: {
              'action': send ? 'send' : 'prepare',
              'invoiceId': invoice.id,
            },
          );
          results.add({
            'ok': true,
            'invoiceId': invoice.id,
            'invoiceNumber': invoice.invoiceNumber,
            'customerName': invoice.customerName,
            'response': response,
          });
        } catch (error) {
          results.add({
            'ok': false,
            'invoiceId': invoice.id,
            'invoiceNumber': invoice.invoiceNumber,
            'customerName': invoice.customerName,
            'error': error.toString(),
          });
        }
      }
      ref.invalidate(invoicesProvider);
      ref.invalidate(eInvoiceSettingsProvider);
      if (!mounted) return;
      final success = results.where((item) => item['ok'] == true).length;
      final failed = results.length - success;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(send ? 'Toplu Gönderim Sonucu' : 'Toplu Payload Hazır'),
          content: SizedBox(
            width: 760,
            height: MediaQuery.sizeOf(context).height * 0.62,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Başarılı: $success • Hatalı: $failed'),
                const Gap(12),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceMuted,
                      border: Border.all(color: AppTheme.border),
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                    ),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(12),
                      child: SelectableText(
                        const JsonEncoder.withIndent('  ').convert({
                          'mode': send ? 'send' : 'prepare',
                          'success': success,
                          'failed': failed,
                          'items': results,
                        }),
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert({
                      'mode': send ? 'send' : 'prepare',
                      'success': success,
                      'failed': failed,
                      'items': results,
                    }),
                  ),
                );
              },
              child: const Text('Kopyala'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _pullAkinsoftData() async {
    setState(() => _pullingAkinsoft = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final payload = {...settings, 'limit': 2000};
      final response = await http
          .post(
            _akinsoftUri('pull'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 2));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Beklenmeyen veri çekme yanıtı.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['ok'] != true) {
        throw Exception(decoded['error'] ?? 'Veri çekme başarısız.');
      }
      decoded['_settingsPayload'] = payload;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _AkinsoftPullDialog(data: decoded),
      );
      ref.invalidate(invoicesProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(eInvoiceSettingsProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Akınsoft verisi çekilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _pullingAkinsoft = false);
    }
  }
}

class _EInvoiceListHeader extends StatelessWidget {
  const _EInvoiceListHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: const [
          SizedBox(width: 46),
          Expanded(flex: 4, child: _InvoiceHeaderText('Cari / Fatura')),
          Expanded(flex: 2, child: _InvoiceHeaderText('Tarih')),
          Expanded(flex: 2, child: _InvoiceHeaderText('Tür')),
          Expanded(flex: 2, child: _InvoiceHeaderText('Durum')),
          SizedBox(
            width: 150,
            child: _InvoiceHeaderText('KDV Dahil', alignEnd: true),
          ),
          SizedBox(width: 340, child: _InvoiceHeaderText('İşlemler')),
        ],
      ),
    );
  }
}

class _InvoiceFiltersCard extends StatelessWidget {
  const _InvoiceFiltersCard({
    required this.filter,
    required this.customersAsync,
    required this.onChanged,
    required this.onRefresh,
  });

  final InvoiceFilter filter;
  final AsyncValue<List<Customer>> customersAsync;
  final ValueChanged<InvoiceFilter> onChanged;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('dd.MM.yyyy');
    final startLabel = filter.startDate == null
        ? 'Başlangıç'
        : dateFormat.format(filter.startDate!);
    final endLabel = filter.endDate == null
        ? 'Bitiş'
        : dateFormat.format(filter.endDate!);
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 1050;
          final fields = <Widget>[
            SizedBox(
              width: compact ? double.infinity : 280,
              child: customersAsync.when(
                data: (customers) => _CustomerFilterButton(
                  customers: customers,
                  selectedCustomerId: filter.customerId,
                  onSelected: (customerId) => onChanged(
                    filter.copyWith(
                      customerId: customerId,
                      clearCustomerId: customerId == null,
                    ),
                  ),
                ),
                loading: () => const LinearProgressIndicator(),
                error: (_, _) => const Text('Cari listesi alınamadı.'),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 190,
              child: DropdownButtonFormField<String>(
                initialValue: filter.status ?? '',
                isExpanded: true,
                items: const [
                  DropdownMenuItem(
                    value: '',
                    child: Text('Durum: Tümü', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'open,partial',
                    child: Text(
                      'Açık + Kısmi',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem(
                    value: 'open',
                    child: Text('Açık', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'partial',
                    child: Text('Kısmi', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'paid',
                    child: Text('Kapalı', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'draft',
                    child: Text('Taslak', overflow: TextOverflow.ellipsis),
                  ),
                  DropdownMenuItem(
                    value: 'cancelled',
                    child: Text('İptal', overflow: TextOverflow.ellipsis),
                  ),
                ],
                onChanged: (value) => onChanged(
                  InvoiceFilter(
                    invoiceType: filter.invoiceType,
                    status: (value ?? '').isEmpty ? null : value,
                    customerId: filter.customerId,
                    startDate: filter.startDate,
                    endDate: filter.endDate,
                  ),
                ),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.fact_check_rounded),
                  labelText: 'Açık / Kapalı',
                ),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 170,
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(context, isStart: true),
                icon: const Icon(Icons.date_range_rounded, size: 18),
                label: Text(startLabel),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 170,
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(context, isStart: false),
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text(endLabel),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Yenile'),
            ),
            TextButton.icon(
              onPressed: () => onChanged(const InvoiceFilter(status: 'open')),
              icon: const Icon(Icons.cleaning_services_rounded, size: 18),
              label: const Text('Temizle'),
            ),
          ];
          return Wrap(spacing: 10, runSpacing: 10, children: fields);
        },
      ),
    );
  }

  Future<void> _pickDate(BuildContext context, {required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate:
          (isStart ? filter.startDate : filter.endDate) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 2),
    );
    if (picked == null) return;
    onChanged(
      InvoiceFilter(
        invoiceType: filter.invoiceType,
        status: filter.status,
        customerId: filter.customerId,
        startDate: isStart ? picked : filter.startDate,
        endDate: isStart ? filter.endDate : picked,
      ),
    );
  }
}

class _LoadMoreInvoicesButton extends StatelessWidget {
  const _LoadMoreInvoicesButton({
    required this.visible,
    required this.total,
    required this.onPressed,
  });

  final int visible;
  final int total;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
      child: Center(
        child: OutlinedButton.icon(
          onPressed: onPressed,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          label: Text('Daha fazla göster ($visible / $total)'),
        ),
      ),
    );
  }
}

class _CustomerFilterButton extends StatelessWidget {
  const _CustomerFilterButton({
    required this.customers,
    required this.selectedCustomerId,
    required this.onSelected,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    Customer? selectedCustomer;
    for (final customer in customers) {
      if (customer.id == selectedCustomerId) {
        selectedCustomer = customer;
        break;
      }
    }
    final label = selectedCustomer == null
        ? 'Cari: Tümü'
        : selectedCustomer.name;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        final selected = await showDialog<Customer?>(
          context: context,
          builder: (context) => _CustomerFilterDialog(
            customers: customers,
            selectedCustomerId: selectedCustomerId,
          ),
        );
        if (selected == null) return;
        onSelected(selected.id.isEmpty ? null : selected.id);
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          prefixIcon: Icon(Icons.person_search_rounded),
          labelText: 'Cari',
          suffixIcon: Icon(Icons.search_rounded),
        ),
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    );
  }
}

class _CustomerFilterDialog extends StatefulWidget {
  const _CustomerFilterDialog({
    required this.customers,
    required this.selectedCustomerId,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;

  @override
  State<_CustomerFilterDialog> createState() => _CustomerFilterDialogState();
}

class _CustomerFilterDialogState extends State<_CustomerFilterDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _normalizeCustomerSearch(_search.text);
    final filtered = query.isEmpty
        ? widget.customers.take(80).toList(growable: false)
        : widget.customers
              .where((customer) {
                final haystack = _normalizeCustomerSearch(
                  [
                    customer.name,
                    customer.vkn ?? '',
                    customer.tcknMs ?? '',
                    customer.city ?? '',
                    customer.phone1 ?? '',
                  ].join(' '),
                );
                return haystack.contains(query);
              })
              .take(100)
              .toList(growable: false);

    return AlertDialog(
      title: const Text('Cari Seç'),
      content: SizedBox(
        width: 640,
        height: 560,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search_rounded),
                hintText: 'Ad, VKN, telefon veya şehir ara',
              ),
            ),
            const Gap(10),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => Navigator.of(context).pop(
                  const Customer(
                    id: '',
                    name: 'Cari: Tümü',
                    city: null,
                    address: null,
                    directorName: null,
                    email: null,
                    phone1: null,
                    phone1Title: null,
                    phone2: null,
                    phone2Title: null,
                    phone3: null,
                    phone3Title: null,
                    vkn: null,
                    tcknMs: null,
                    notes: null,
                    isActive: true,
                    activeLineCount: 0,
                    activeGmp3Count: 0,
                  ),
                ),
                icon: const Icon(Icons.clear_all_rounded, size: 18),
                label: const Text('Tüm cariler'),
              ),
            ),
            const Gap(4),
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
                            child: Text(_customerInitials(customer.name)),
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

String _normalizeCustomerSearch(String value) {
  return value
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('ü', 'u')
      .replaceAll('ş', 's')
      .replaceAll('ö', 'o')
      .replaceAll('ç', 'c');
}

String _customerInitials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return '?';
  return parts.map((part) => part.characters.first.toUpperCase()).join();
}

class _InvoiceHeaderText extends StatelessWidget {
  const _InvoiceHeaderText(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: AppTheme.textSoft),
    );
  }
}

class _EInvoiceRow extends ConsumerStatefulWidget {
  const _EInvoiceRow({
    required this.invoice,
    this.selected = false,
    this.onSelectedChanged,
  });

  final Invoice invoice;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;

  @override
  ConsumerState<_EInvoiceRow> createState() => _EInvoiceRowState();
}

class _EInvoiceRowState extends ConsumerState<_EInvoiceRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: invoice.currency == 'TRY' ? '₺' : '${invoice.currency} ',
      decimalDigits: 2,
    );

    if (MediaQuery.sizeOf(context).width < 900) {
      return _buildCompactRow(context, invoice, money);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 46,
            child: Checkbox(
              value: widget.selected,
              onChanged: widget.onSelectedChanged == null
                  ? null
                  : (value) => widget.onSelectedChanged!(value ?? false),
            ),
          ),
          Expanded(
            flex: 4,
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color:
                        (invoice.invoiceType == 'sales'
                                ? AppTheme.success
                                : AppTheme.warning)
                            .withValues(alpha: invoice.isActive ? 0.12 : 0.06),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  ),
                  child: Icon(
                    invoice.invoiceType == 'sales'
                        ? Icons.north_east_rounded
                        : Icons.south_west_rounded,
                    color: invoice.isActive
                        ? (invoice.invoiceType == 'sales'
                              ? AppTheme.success
                              : AppTheme.warning)
                        : AppTheme.textMuted,
                    size: 18,
                  ),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        invoice.customerName ?? 'Cari',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        invoice.invoiceNumber,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              DateFormat('dd.MM.yyyy').format(invoice.invoiceDate),
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              invoice.invoiceType == 'sales' ? 'Satış' : 'Alış',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Expanded(
            flex: 2,
            child: Row(
              children: [
                AppBadge(
                  label: invoice.isActive
                      ? _statusLabel(invoice.status)
                      : 'Pasif',
                  tone: invoice.isActive
                      ? _statusTone(invoice.status)
                      : AppBadgeTone.neutral,
                ),
              ],
            ),
          ),
          SizedBox(
            width: 150,
            child: Text(
              money.format(invoice.grandTotal),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall,
            ),
          ),
          SizedBox(
            width: 340,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: [
                _InvoiceIconAction(
                  tooltip: 'Düzenle',
                  icon: Icons.edit_rounded,
                  onPressed: _busy ? null : _edit,
                ),
                _InvoiceIconAction(
                  tooltip: invoice.isActive ? 'Pasife al' : 'Aktifleştir',
                  icon: invoice.isActive
                      ? Icons.archive_outlined
                      : Icons.restore_rounded,
                  onPressed: _busy ? null : _toggleActive,
                ),
                _InvoiceIconAction(
                  tooltip: 'Kalıcı sil',
                  icon: Icons.delete_forever_rounded,
                  onPressed: _busy ? null : _delete,
                ),
                _InvoiceIconAction(
                  tooltip: 'PDF / Yazdır',
                  icon: Icons.picture_as_pdf_rounded,
                  onPressed: _busy ? null : _print,
                ),
                _InvoiceIconAction(
                  tooltip: 'Payload hazırla',
                  icon: Icons.data_object_rounded,
                  onPressed: _busy ? null : () => _prepare(send: false),
                ),
                _InvoiceIconAction(
                  tooltip: 'Test API’ye gönder',
                  icon: _busy
                      ? Icons.hourglass_empty_rounded
                      : Icons.cloud_upload_rounded,
                  onPressed: _busy ? null : () => _prepare(send: true),
                  primary: true,
                ),
                _InvoiceIconAction(
                  tooltip: 'Özet kopyala',
                  icon: Icons.copy_rounded,
                  onPressed: _busy ? null : _copyPreview,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactRow(
    BuildContext context,
    Invoice invoice,
    NumberFormat money,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Checkbox(
                value: widget.selected,
                onChanged: widget.onSelectedChanged == null
                    ? null
                    : (value) => widget.onSelectedChanged!(value ?? false),
              ),
              const Gap(8),
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color:
                      (invoice.invoiceType == 'sales'
                              ? AppTheme.success
                              : AppTheme.warning)
                          .withValues(alpha: invoice.isActive ? 0.12 : 0.06),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                ),
                child: Icon(
                  invoice.invoiceType == 'sales'
                      ? Icons.north_east_rounded
                      : Icons.south_west_rounded,
                  color: invoice.isActive
                      ? (invoice.invoiceType == 'sales'
                            ? AppTheme.success
                            : AppTheme.warning)
                      : AppTheme.textMuted,
                  size: 18,
                ),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      invoice.customerName ?? 'Cari',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    Text(
                      invoice.invoiceNumber,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Gap(8),
              AppBadge(
                label: invoice.isActive
                    ? _statusLabel(invoice.status)
                    : 'Pasif',
                tone: invoice.isActive
                    ? _statusTone(invoice.status)
                    : AppBadgeTone.neutral,
              ),
            ],
          ),
          const Gap(10),
          Wrap(
            spacing: 14,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                DateFormat('dd.MM.yyyy').format(invoice.invoiceDate),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                invoice.invoiceType == 'sales' ? 'Satış' : 'Alış',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              Text(
                money.format(invoice.grandTotal),
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ],
          ),
          const Gap(10),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _InvoiceIconAction(
                tooltip: 'Düzenle',
                icon: Icons.edit_rounded,
                onPressed: _busy ? null : _edit,
              ),
              _InvoiceIconAction(
                tooltip: invoice.isActive ? 'Pasife al' : 'Aktifleştir',
                icon: invoice.isActive
                    ? Icons.archive_outlined
                    : Icons.restore_rounded,
                onPressed: _busy ? null : _toggleActive,
              ),
              _InvoiceIconAction(
                tooltip: 'Kalıcı sil',
                icon: Icons.delete_forever_rounded,
                onPressed: _busy ? null : _delete,
              ),
              _InvoiceIconAction(
                tooltip: 'PDF / Yazdır',
                icon: Icons.picture_as_pdf_rounded,
                onPressed: _busy ? null : _print,
              ),
              _InvoiceIconAction(
                tooltip: 'Payload hazırla',
                icon: Icons.data_object_rounded,
                onPressed: _busy ? null : () => _prepare(send: false),
              ),
              _InvoiceIconAction(
                tooltip: 'Test API’ye gönder',
                icon: _busy
                    ? Icons.hourglass_empty_rounded
                    : Icons.cloud_upload_rounded,
                onPressed: _busy ? null : () => _prepare(send: true),
                primary: true,
              ),
              _InvoiceIconAction(
                tooltip: 'Özet kopyala',
                icon: Icons.copy_rounded,
                onPressed: _busy ? null : _copyPreview,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _edit() async {
    final apiClient = ref.read(apiClientProvider);
    Invoice invoice = widget.invoice;
    if (apiClient != null) {
      setState(() => _busy = true);
      try {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'invoice_detail',
            'invoiceId': widget.invoice.id,
          },
        );
        if (response.isNotEmpty) {
          invoice = Invoice.fromJson(response);
        }
      } catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Fatura kalemleri yüklenemedi, liste bilgisiyle açılıyor: $error',
              ),
            ),
          );
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => EInvoiceFormScreen(
          invoiceType: invoice.invoiceType,
          initialInvoice: invoice,
        ),
      ),
    );
    ref.invalidate(invoicesProvider);
    ref.invalidate(accountBalancesProvider);
  }

  Future<void> _toggleActive() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.invoice.id},
          ],
          'values': {'is_active': !widget.invoice.isActive},
        },
      );
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fatura güncellenemedi: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faturayı sil'),
        content: Text(
          '${widget.invoice.invoiceNumber} numaralı fatura ve kalemleri kalıcı olarak silinsin mi?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'invoice_items',
          'filters': [
            {'col': 'invoice_id', 'op': 'eq', 'value': widget.invoice.id},
          ],
        },
      );
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'delete', 'table': 'invoices', 'id': widget.invoice.id},
      );
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fatura silinemedi: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final apiClient = ref.read(apiClientProvider);
    Invoice invoice = widget.invoice;
    if (apiClient != null) {
      setState(() => _busy = true);
      try {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'invoice_detail',
            'invoiceId': widget.invoice.id,
          },
        );
        if (response.isNotEmpty) {
          invoice = Invoice.fromJson(response);
        }
      } finally {
        if (mounted) setState(() => _busy = false);
      }
    }
    final ok = await printEInvoice(invoice);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu platformda yazdırma desteklenmiyor.')),
    );
  }

  Future<void> _prepare({required bool send}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      final response = await apiClient.postJson(
        '/e-invoice',
        body: {
          'action': send ? 'send' : 'prepare',
          'invoiceId': widget.invoice.id,
        },
      );
      if (!mounted) return;
      ref.invalidate(invoicesProvider);
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(send ? 'Gönderim Yanıtı' : 'Payload Hazır'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: SelectableText(
                const JsonEncoder.withIndent('  ').convert(response),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(
                  ClipboardData(
                    text: const JsonEncoder.withIndent('  ').convert(response),
                  ),
                );
              },
              child: const Text('Kopyala'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('E-fatura işlemi başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyPreview() async {
    final invoice = widget.invoice;
    await Clipboard.setData(
      ClipboardData(
        text:
            '${invoice.invoiceNumber} ${invoice.customerName ?? ''} ${invoice.currency} ${invoice.grandTotal}',
      ),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Fatura özeti kopyalandı.')));
  }

  String _statusLabel(String status) {
    return switch (status) {
      'draft' => 'Taslak',
      'open' => 'Açık',
      'partial' => 'Kısmi',
      'paid' => 'Kapalı',
      'cancelled' => 'İptal',
      _ => status,
    };
  }

  AppBadgeTone _statusTone(String status) {
    return switch (status) {
      'paid' => AppBadgeTone.success,
      'partial' => AppBadgeTone.warning,
      'cancelled' => AppBadgeTone.error,
      _ => AppBadgeTone.primary,
    };
  }
}

class _InvoiceIconAction extends StatelessWidget {
  const _InvoiceIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(
          backgroundColor: primary ? AppTheme.primary : AppTheme.surfaceMuted,
          foregroundColor: primary ? Colors.white : AppTheme.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            side: BorderSide(
              color: primary ? AppTheme.primary : AppTheme.border,
            ),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
      ),
    );
  }
}

class _ProductsTab extends ConsumerStatefulWidget {
  const _ProductsTab({required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<_ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends ConsumerState<_ProductsTab> {
  String _query = '';
  String _group = '';
  String _subGroup = '';

  @override
  Widget build(BuildContext context) {
    final productsAsync = ref.watch(productsProvider(null));

    return productsAsync.when(
      data: (products) {
        final groups =
            products
                .map((p) => (p.akinsoftGroup ?? p.category ?? '').trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final subGroups =
            products
                .where(
                  (p) =>
                      _group.isEmpty ||
                      (p.akinsoftGroup ?? p.category ?? '') == _group,
                )
                .map((p) => (p.akinsoftSubGroup ?? '').trim())
                .where((item) => item.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final q = _query.trim().toLowerCase();
        final filtered =
            products.where((product) {
              final group = (product.akinsoftGroup ?? product.category ?? '')
                  .trim();
              final subGroup = (product.akinsoftSubGroup ?? '').trim();
              if (_group.isNotEmpty && group != _group) return false;
              if (_subGroup.isNotEmpty && subGroup != _subGroup) return false;
              if (q.isEmpty) return true;
              final haystack = [
                product.code,
                product.name,
                product.description,
                group,
                subGroup,
              ].whereType<String>().join(' ').toLowerCase();
              return haystack.contains(q);
            }).toList()..sort((a, b) {
              final ag = (a.akinsoftGroup ?? a.category ?? '').compareTo(
                b.akinsoftGroup ?? b.category ?? '',
              );
              if (ag != 0) return ag;
              final asg = (a.akinsoftSubGroup ?? '').compareTo(
                b.akinsoftSubGroup ?? '',
              );
              if (asg != 0) return asg;
              return a.name.compareTo(b.name);
            });

        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Stok kodu, ürün adı, grup ara',
                    ),
                  ),
                ),
                const Gap(10),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _group,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Grup: Tümü'),
                      ),
                      for (final group in groups)
                        DropdownMenuItem(value: group, child: Text(group)),
                    ],
                    onChanged: (value) => setState(() {
                      _group = value ?? '';
                      _subGroup = '';
                    }),
                    decoration: const InputDecoration(labelText: 'Grup'),
                  ),
                ),
                const Gap(10),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: _subGroup,
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('Alt grup: Tümü'),
                      ),
                      for (final subGroup in subGroups)
                        DropdownMenuItem(
                          value: subGroup,
                          child: Text(subGroup),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _subGroup = value ?? ''),
                    decoration: const InputDecoration(labelText: 'Alt Grup'),
                  ),
                ),
                const Gap(10),
                FilledButton.icon(
                  onPressed: () => _showProductDialog(context, ref),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Stok Tanımla'),
                ),
              ],
            ),
            const Gap(12),
            if (filtered.isEmpty)
              const AppCard(
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('Bu filtrelere uygun stok/hizmet yok.'),
                ),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    Container(
                      height: 42,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: const BoxDecoration(
                        color: Color(0xFFF1F5F9),
                        border: Border(
                          bottom: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: Row(
                        children: const [
                          SizedBox(
                            width: 120,
                            child: _InvoiceHeaderText('Kod'),
                          ),
                          Expanded(flex: 3, child: _InvoiceHeaderText('Stok')),
                          Expanded(flex: 2, child: _InvoiceHeaderText('Grup')),
                          Expanded(
                            flex: 2,
                            child: _InvoiceHeaderText('Alt Grup'),
                          ),
                          SizedBox(
                            width: 92,
                            child: _InvoiceHeaderText('Birim'),
                          ),
                          SizedBox(width: 92, child: _InvoiceHeaderText('KDV')),
                          SizedBox(width: 100),
                        ],
                      ),
                    ),
                    for (final product in filtered)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 9,
                        ),
                        decoration: const BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppTheme.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 120,
                              child: Text(
                                product.code ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                            Expanded(
                              flex: 3,
                              child: Text(
                                product.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                product.akinsoftGroup ??
                                    product.category ??
                                    '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text(
                                product.akinsoftSubGroup ?? '-',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            SizedBox(width: 92, child: Text(product.unit)),
                            SizedBox(
                              width: 92,
                              child: Text(
                                '%${product.taxRate.toStringAsFixed(0)}',
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _showProductDialog(context, ref, product),
                                icon: const Icon(Icons.edit_rounded, size: 16),
                                label: const Text('Düzenle'),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorCard(message: 'Stoklar yüklenemedi: $error'),
    );
  }

  Future<void> _showProductDialog(
    BuildContext context,
    WidgetRef ref, [
    Product? product,
  ]) async {
    final name = TextEditingController(text: product?.name ?? '');
    final code = TextEditingController(text: product?.code ?? '');
    final category = TextEditingController(
      text: product?.akinsoftGroup ?? product?.category ?? '',
    );
    final subGroup = TextEditingController(
      text: product?.akinsoftSubGroup ?? '',
    );
    final description = TextEditingController(text: product?.description ?? '');
    final purchase = TextEditingController(
      text: (product?.purchasePrice ?? 0).toStringAsFixed(2),
    );
    final sale = TextEditingController(
      text: (product?.salePrice ?? 0).toStringAsFixed(2),
    );
    final minStock = TextEditingController(
      text: (product?.minStock ?? 0).toStringAsFixed(0),
    );
    String currency = product?.currency ?? 'TRY';
    String unit = product?.unit ?? 'Adet';
    String type = product?.productType ?? 'product';
    double taxRate = product?.taxRate ?? 20;
    bool trackStock = product?.trackStock ?? true;
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(
            product == null ? 'Stok/Hizmet Tanımı' : 'Stok/Hizmet Düzenle',
          ),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Ürün/Hizmet Adı',
                    ),
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: code,
                          decoration: const InputDecoration(labelText: 'Kod'),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: type,
                          items: const [
                            DropdownMenuItem(
                              value: 'product',
                              child: Text('Ürün'),
                            ),
                            DropdownMenuItem(
                              value: 'service',
                              child: Text('Hizmet'),
                            ),
                            DropdownMenuItem(
                              value: 'part',
                              child: Text('Parça'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => type = v ?? 'product'),
                          decoration: const InputDecoration(labelText: 'Tip'),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: category,
                          decoration: const InputDecoration(
                            labelText: 'Grup',
                            hintText: 'Akınsoft ara grubu',
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          controller: subGroup,
                          decoration: const InputDecoration(
                            labelText: 'Alt Grup',
                            hintText: 'Akınsoft alt grubu',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: minStock,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Minimum Stok',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: purchase,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Alış Fiyatı',
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          controller: sale,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Satış Fiyatı',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: currency,
                          items: const [
                            DropdownMenuItem(value: 'TRY', child: Text('TL')),
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                          ],
                          onChanged: (v) =>
                              setState(() => currency = v ?? 'TRY'),
                          decoration: const InputDecoration(
                            labelText: 'Para Birimi',
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          items: const [
                            DropdownMenuItem(
                              value: 'Adet',
                              child: Text('Adet'),
                            ),
                            DropdownMenuItem(value: 'Kg', child: Text('Kg')),
                            DropdownMenuItem(value: 'Lt', child: Text('Lt')),
                            DropdownMenuItem(value: 'Mt', child: Text('Mt')),
                            DropdownMenuItem(
                              value: 'Saat',
                              child: Text('Saat'),
                            ),
                          ],
                          onChanged: (v) => setState(() => unit = v ?? 'Adet'),
                          decoration: const InputDecoration(labelText: 'Birim'),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: DropdownButtonFormField<double>(
                          initialValue: taxRate,
                          items: const [
                            DropdownMenuItem(value: 0, child: Text('%0')),
                            DropdownMenuItem(value: 16, child: Text('%16')),
                            DropdownMenuItem(value: 20, child: Text('%20')),
                          ],
                          onChanged: (v) => setState(() => taxRate = v ?? 20),
                          decoration: const InputDecoration(labelText: 'KDV'),
                        ),
                      ),
                    ],
                  ),
                  CheckboxListTile(
                    value: trackStock,
                    onChanged: (v) => setState(() => trackStock = v ?? true),
                    title: const Text('Stok takibi yapılsın'),
                    contentPadding: EdgeInsets.zero,
                  ),
                  TextField(
                    controller: description,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      hintText: 'Faturada kullanılacak kısa açıklama',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final apiClient = ref.read(apiClientProvider);
                      final productName = name.text.trim();
                      if (apiClient == null) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('API bağlantısı yok.')),
                        );
                        return;
                      }
                      if (productName.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ürün/Hizmet adı zorunludur.'),
                          ),
                        );
                        return;
                      }
                      setState(() => saving = true);
                      try {
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'upsert',
                            'table': 'products',
                            'returning': 'row',
                            'values': {
                              if (product != null) 'id': product.id,
                              'name': productName,
                              'code': code.text.trim().isEmpty
                                  ? null
                                  : code.text.trim(),
                              'category': category.text.trim().isEmpty
                                  ? null
                                  : category.text.trim(),
                              'akinsoft_group': category.text.trim().isEmpty
                                  ? null
                                  : category.text.trim(),
                              'akinsoft_sub_group': subGroup.text.trim().isEmpty
                                  ? null
                                  : subGroup.text.trim(),
                              'description': description.text.trim().isEmpty
                                  ? null
                                  : description.text.trim(),
                              'product_type': type,
                              'unit': unit,
                              'purchase_price': _parseDecimal(purchase.text),
                              'sale_price': _parseDecimal(sale.text),
                              'currency': currency,
                              'tax_rate': taxRate,
                              'track_stock': trackStock,
                              'min_stock': _parseDecimal(minStock.text),
                              'is_active': true,
                            },
                          },
                        );
                        ref.invalidate(productsProvider(null));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Stok/Hizmet kaydedildi.'),
                          ),
                        );
                        Navigator.of(context).pop();
                      } catch (error) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Stok kaydedilemedi: $error')),
                        );
                      } finally {
                        if (context.mounted) setState(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsTab extends ConsumerStatefulWidget {
  const _AccountsTab({required this.moneyTry});

  final NumberFormat moneyTry;

  @override
  ConsumerState<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends ConsumerState<_AccountsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final balancesAsync = ref.watch(accountBalancesProvider);

    return balancesAsync.when(
      data: (balances) {
        final q = _query.trim().toLowerCase();
        final filtered = q.isEmpty
            ? balances
            : balances
                  .where((item) => item.name.toLowerCase().contains(q))
                  .toList(growable: false);
        final receivable = balances
            .where((item) => item.balance > 0)
            .fold<double>(0, (sum, item) => sum + item.balance);
        final payable = balances
            .where((item) => item.balance < 0)
            .fold<double>(0, (sum, item) => sum + item.balance.abs());
        final collections = balances.fold<double>(
          0,
          (sum, item) => sum + item.collectionsTotal,
        );
        final sales = balances.fold<double>(
          0,
          (sum, item) => sum + item.salesTotal,
        );

        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            _AccountsSummaryGrid(
              money: widget.moneyTry,
              totalAccounts: balances.length,
              receivable: receivable,
              payable: payable,
              collections: collections,
              sales: sales,
            ),
            const Gap(12),
            AppCard(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      onChanged: (value) => setState(() => _query = value),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        labelText: 'Cari ara',
                        hintText: 'Firma adı ile filtrele',
                      ),
                    ),
                  ),
                  const Gap(12),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(accountBalancesProvider),
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('Yenile'),
                  ),
                  const Gap(10),
                  FilledButton.icon(
                    onPressed: () => _showPaymentDialog(context, ref),
                    icon: const Icon(Icons.payments_rounded, size: 18),
                    label: const Text('Tahsilat/Ödeme'),
                  ),
                ],
              ),
            ),
            const Gap(12),
            if (balances.isEmpty)
              const AppCard(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Cari hareket yok.'),
                ),
              )
            else if (filtered.isEmpty)
              const AppCard(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('Arama ile eşleşen cari bulunamadı.'),
                ),
              )
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact = constraints.maxWidth < 860;
                    if (compact) {
                      return Column(
                        children: [
                          for (final balance in filtered)
                            _AccountMobileRow(
                              balance: balance,
                              money: widget.moneyTry,
                            ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        const _AccountsTableHeader(),
                        for (final balance in filtered)
                          _AccountTableRow(
                            balance: balance,
                            money: widget.moneyTry,
                          ),
                      ],
                    );
                  },
                ),
              ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) =>
          _ErrorCard(message: 'Cari hesap yüklenemedi: $error'),
    );
  }

  Future<void> _showPaymentDialog(BuildContext context, WidgetRef ref) async {
    final customersAsync = ref.read(customersLookupProvider);
    final amount = TextEditingController();
    final desc = TextEditingController();
    String? customerId;
    String type = 'collection';
    String currency = 'TRY';
    String method = 'bank';

    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Tahsilat / Ödeme'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                customersAsync.when(
                  data: (customers) => DropdownButtonFormField<String>(
                    initialValue: customerId,
                    items: [
                      for (final c in customers)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) => setState(() => customerId = v),
                    decoration: const InputDecoration(labelText: 'Cari'),
                  ),
                  loading: () => const LinearProgressIndicator(),
                  error: (_, _) => const Text('Cari listesi alınamadı.'),
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: type,
                        items: const [
                          DropdownMenuItem(
                            value: 'collection',
                            child: Text('Tahsilat'),
                          ),
                          DropdownMenuItem(
                            value: 'payment',
                            child: Text('Ödeme'),
                          ),
                        ],
                        onChanged: (v) =>
                            setState(() => type = v ?? 'collection'),
                        decoration: const InputDecoration(labelText: 'İşlem'),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextField(
                        controller: amount,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(labelText: 'Tutar'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: currency,
                        items: const [
                          DropdownMenuItem(value: 'TRY', child: Text('TL')),
                          DropdownMenuItem(value: 'USD', child: Text('USD')),
                        ],
                        onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                        decoration: const InputDecoration(
                          labelText: 'Para Birimi',
                        ),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: method,
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Nakit')),
                          DropdownMenuItem(value: 'bank', child: Text('Banka')),
                          DropdownMenuItem(
                            value: 'credit_card',
                            child: Text('Kredi Kartı'),
                          ),
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Diğer'),
                          ),
                        ],
                        onChanged: (v) => setState(() => method = v ?? 'bank'),
                        decoration: const InputDecoration(labelText: 'Yöntem'),
                      ),
                    ),
                  ],
                ),
                const Gap(10),
                TextField(
                  controller: desc,
                  decoration: const InputDecoration(labelText: 'Açıklama'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                final apiClient = ref.read(apiClientProvider);
                if (apiClient == null || customerId == null) return;
                await apiClient.postJson(
                  '/mutate',
                  body: {
                    'op': 'upsert',
                    'table': 'transactions',
                    'returning': 'row',
                    'values': {
                      'customer_id': customerId,
                      'transaction_type': type,
                      'amount': _parseDecimal(amount.text),
                      'currency': currency,
                      'exchange_rate': 1,
                      'payment_method': method,
                      'transaction_date': DateTime.now()
                          .toIso8601String()
                          .substring(0, 10),
                      'description': desc.text.trim().isEmpty
                          ? null
                          : desc.text.trim(),
                    },
                  },
                );
                ref.invalidate(accountBalancesProvider);
                if (context.mounted) Navigator.of(context).pop();
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountsSummaryGrid extends StatelessWidget {
  const _AccountsSummaryGrid({
    required this.money,
    required this.totalAccounts,
    required this.receivable,
    required this.payable,
    required this.collections,
    required this.sales,
  });

  final NumberFormat money;
  final int totalAccounts;
  final double receivable;
  final double payable;
  final double collections;
  final double sales;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final cards = [
          _AccountSummaryCard(
            title: 'Cari Sayısı',
            value: totalAccounts.toString(),
            icon: Icons.groups_rounded,
            color: AppTheme.primary,
          ),
          _AccountSummaryCard(
            title: 'Alacak',
            value: money.format(receivable),
            icon: Icons.trending_up_rounded,
            color: AppTheme.success,
          ),
          _AccountSummaryCard(
            title: 'Borç',
            value: money.format(payable),
            icon: Icons.trending_down_rounded,
            color: AppTheme.error,
          ),
          _AccountSummaryCard(
            title: 'Satış / Tahsilat',
            value: '${money.format(sales)} / ${money.format(collections)}',
            icon: Icons.receipt_long_rounded,
            color: const Color(0xFF229ED3),
          ),
        ];

        return GridView.count(
          crossAxisCount: compact ? 2 : 4,
          childAspectRatio: compact ? 2.6 : 3.7,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cards,
        );
      },
    );
  }
}

class _AccountSummaryCard extends StatelessWidget {
  const _AccountSummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(AppTheme.radiusMd),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountsTableHeader extends StatelessWidget {
  const _AccountsTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFF1F5F9),
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: const [
          Expanded(flex: 4, child: _AccountHeaderText('Cari')),
          Expanded(flex: 2, child: _AccountHeaderText('Satış')),
          Expanded(flex: 2, child: _AccountHeaderText('Alış')),
          Expanded(flex: 2, child: _AccountHeaderText('Tahsilat')),
          Expanded(flex: 2, child: _AccountHeaderText('Ödeme')),
          SizedBox(
            width: 150,
            child: _AccountHeaderText('Bakiye', alignEnd: true),
          ),
        ],
      ),
    );
  }
}

class _AccountHeaderText extends StatelessWidget {
  const _AccountHeaderText(this.label, {this.alignEnd = false});

  final String label;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      textAlign: alignEnd ? TextAlign.end : TextAlign.start,
      style: Theme.of(
        context,
      ).textTheme.labelLarge?.copyWith(color: AppTheme.textSoft),
    );
  }
}

class _AccountTableRow extends StatelessWidget {
  const _AccountTableRow({required this.balance, required this.money});

  final AccountBalance balance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final positive = balance.balance >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Row(
              children: [
                _AccountAvatar(name: balance.name, positive: positive),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        balance.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      Text(
                        '${balance.accountType} • ${balance.currency}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: _AmountText(money.format(balance.salesTotal)),
          ),
          Expanded(
            flex: 2,
            child: _AmountText(money.format(balance.purchaseTotal)),
          ),
          Expanded(
            flex: 2,
            child: _AmountText(money.format(balance.collectionsTotal)),
          ),
          Expanded(
            flex: 2,
            child: _AmountText(money.format(balance.paymentsTotal)),
          ),
          SizedBox(
            width: 150,
            child: Text(
              money.format(balance.balance),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: positive ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountMobileRow extends StatelessWidget {
  const _AccountMobileRow({required this.balance, required this.money});

  final AccountBalance balance;
  final NumberFormat money;

  @override
  Widget build(BuildContext context) {
    final positive = balance.balance >= 0;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          _AccountAvatar(name: balance.name, positive: positive),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  balance.name,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                Text(
                  'Satış ${money.format(balance.salesTotal)} • Tahsilat ${money.format(balance.collectionsTotal)}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Text(
            money.format(balance.balance),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: positive ? AppTheme.success : AppTheme.error,
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountAvatar extends StatelessWidget {
  const _AccountAvatar({required this.name, required this.positive});

  final String name;
  final bool positive;

  @override
  Widget build(BuildContext context) {
    final initials = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.characters.first.toUpperCase())
        .join();
    final color = positive ? AppTheme.success : AppTheme.error;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(color: color),
      ),
    );
  }
}

class _AmountText extends StatelessWidget {
  const _AmountText(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }
}

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  final _controllers = <String, TextEditingController>{};
  String _environment = 'test';
  bool _hydrated = false;
  bool _saving = false;
  bool _testingAkinsoft = false;
  bool _analyzingAkinsoft = false;
  bool _pullingAkinsoft = false;
  bool _bulkMatchingCustomers = false;
  bool _cleaningCustomers = false;

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _c(String key) =>
      _controllers.putIfAbsent(key, TextEditingController.new);

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(eInvoiceSettingsProvider);
    return settingsAsync.when(
      data: (settings) {
        final offlineError = (settings['_offline_error'] ?? '').toString();
        if (!_hydrated) {
          _environment = (settings['environment'] ?? 'test').toString();
          for (final key in _settingKeys) {
            _c(key).text = (settings[key] ?? '').toString();
          }
          _hydrated = true;
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 120),
          children: [
            AppCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (offlineError.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.warning.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                        border: Border.all(
                          color: AppTheme.warning.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.cloud_off_rounded,
                            color: AppTheme.warning,
                            size: 20,
                          ),
                          const Gap(10),
                          Expanded(
                            child: Text(
                              'Uzak backend e-fatura endpointi henüz cevap vermiyor. Form test varsayılanlarıyla açıldı; kaydetme ve gönderim için /api/e-invoice deploy edilmeli.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Gap(14),
                  ],
                  Text(
                    'Maliye API Ayarları',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _environment,
                          items: const [
                            DropdownMenuItem(
                              value: 'test',
                              child: Text('Test'),
                            ),
                            DropdownMenuItem(
                              value: 'production',
                              child: Text('Canlı'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => _environment = v ?? 'test'),
                          decoration: const InputDecoration(labelText: 'Ortam'),
                        ),
                      ),
                      const Gap(10),
                      Expanded(child: _field('seller_vkn', 'Satıcı VKN')),
                      const Gap(10),
                      Expanded(child: _field('seller_branch_code', 'Şube Kod')),
                    ],
                  ),
                  const Gap(10),
                  _field('seller_title', 'Satıcı Ünvanı'),
                  const Gap(10),
                  _field('seller_address_line1', 'Adres Satırı 1'),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(child: _field('seller_city', 'Şehir')),
                      const Gap(10),
                      Expanded(
                        child: _field('seller_tax_office', 'Vergi Dairesi'),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(child: _field('username', 'Test Kullanıcı')),
                      const Gap(10),
                      Expanded(
                        child: _field('password', 'Şifre', obscureText: true),
                      ),
                    ],
                  ),
                  const Gap(10),
                  _field('api_base_url', 'API Base URL'),
                  const Gap(10),
                  _field('token_url', 'Token URL'),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: _field('next_sales_number', 'Sonraki Satış No'),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field(
                          'next_purchase_number',
                          'Sonraki Alış No',
                        ),
                      ),
                    ],
                  ),
                  const Gap(16),
                  const Divider(height: 24),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                        child: const Icon(
                          Icons.storage_rounded,
                          color: AppTheme.primary,
                          size: 20,
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Akınsoft MSSQL / VPN Bağlantısı',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Text(
                              'WOLVOX MSSQL veritabanından fatura, cari ve stok senkronu için bağlantı bilgileri.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: _field('akinsoft_vpn_name', 'VPN Adı / Tipi'),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field('akinsoft_vpn_host', 'VPN Sunucu / IP'),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field('akinsoft_vpn_username', 'VPN Kullanıcı'),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: _field(
                          'akinsoft_vpn_password',
                          'VPN Şifre',
                          obscureText: true,
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field(
                          'akinsoft_mssql_host',
                          'SQL Server Host / IP',
                        ),
                      ),
                      const Gap(10),
                      Expanded(child: _field('akinsoft_mssql_port', 'Port')),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: _field('akinsoft_mssql_database', 'Database'),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field(
                          'akinsoft_mssql_username',
                          'SQL Kullanıcı',
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _field(
                          'akinsoft_mssql_password',
                          'SQL Şifre',
                          obscureText: true,
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: _field('akinsoft_database_year', 'Aktif Yıl'),
                      ),
                      const Gap(10),
                      Expanded(
                        flex: 2,
                        child: _field(
                          'akinsoft_database_pattern',
                          'Database Şablonu',
                          hintText: 'WOLVOX8_MICO_{year}_WOLVOX',
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  _field(
                    'akinsoft_sync_notes',
                    'Bağlantı Notları',
                    maxLines: 3,
                  ),
                  const Gap(10),
                  _field(
                    'akinsoft_sync_enabled',
                    'Senkron Durumu',
                    hintText: 'true / false',
                  ),
                  const Gap(16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _testingAkinsoft
                            ? null
                            : _testAkinsoftConnection,
                        icon: _testingAkinsoft
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.cable_rounded, size: 18),
                        label: const Text('Bağlantıyı Test Et'),
                      ),
                      const Gap(10),
                      OutlinedButton.icon(
                        onPressed: _analyzingAkinsoft
                            ? null
                            : _analyzeAkinsoftTables,
                        icon: _analyzingAkinsoft
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.schema_rounded, size: 18),
                        label: const Text('Tabloları Analiz Et'),
                      ),
                      const Gap(10),
                      OutlinedButton.icon(
                        onPressed: _pullingAkinsoft ? null : _pullAkinsoftData,
                        icon: _pullingAkinsoft
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.sync_rounded, size: 18),
                        label: const Text('Akınsoft’tan Çek'),
                      ),
                      const Gap(10),
                      OutlinedButton.icon(
                        onPressed: _bulkMatchingCustomers
                            ? null
                            : _bulkMatchAkinsoftCustomers,
                        icon: _bulkMatchingCustomers
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.hub_rounded, size: 18),
                        label: const Text('Toplu Cari Eşleştir'),
                      ),
                      const Gap(10),
                      OutlinedButton.icon(
                        onPressed: _cleaningCustomers
                            ? null
                            : _cleanupDuplicateCustomers,
                        icon: _cleaningCustomers
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.merge_type_rounded, size: 18),
                        label: const Text('Çift Carileri Temizle'),
                      ),
                      const Gap(10),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Ayarları Kaydet'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => _ErrorCard(message: 'Ayarlar yüklenemedi: $error'),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool obscureText = false,
    int maxLines = 1,
    String? hintText,
  }) {
    return TextField(
      controller: _c(key),
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      decoration: InputDecoration(labelText: label, hintText: hintText),
    );
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    setState(() => _saving = true);
    final existing = await _loadLocalEInvoiceSettings();
    final settings = <String, dynamic>{'environment': _environment};
    for (final key in _settingKeys) {
      final text = _c(key).text.trim();
      if (text.isEmpty && _secretSettingKeys.contains(key)) {
        final previous = existing[key]?.toString() ?? '';
        settings[key] = previous.isEmpty ? null : previous;
      } else {
        settings[key] = text.isEmpty ? null : text;
      }
    }
    settings['next_sales_number'] =
        int.tryParse(_c('next_sales_number').text.trim()) ?? 1;
    settings['next_purchase_number'] =
        int.tryParse(_c('next_purchase_number').text.trim()) ?? 1;

    try {
      await _saveLocalEInvoiceSettings(settings);
      await _saveAkinsoftEnvSettings(settings);

      if (apiClient == null) {
        ref.invalidate(eInvoiceSettingsProvider);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Ayarlar bu tarayıcıya lokal kaydedildi. Backend yayınlanınca sunucuya da kaydedilecek.',
            ),
          ),
        );
        return;
      }
      await apiClient.postJson(
        '/e-invoice',
        body: {'action': 'save_settings', 'settings': settings},
      );
      ref.invalidate(eInvoiceSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-fatura ayarları kaydedildi.')),
      );
    } catch (error) {
      await _saveLocalEInvoiceSettings(settings);
      ref.invalidate(eInvoiceSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Backend kaydı yapılamadı ama bilgiler bu tarayıcıya lokal kaydedildi. Detay: $error',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAkinsoftEnvSettings(Map<String, dynamic> settings) async {
    try {
      await http
          .post(
            _akinsoftUri('save-local-settings'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(settings),
          )
          .timeout(const Duration(seconds: 5));
    } catch (_) {}
  }

  Map<String, dynamic> _currentSettingsPayload() {
    return {
      'environment': _environment,
      for (final key in _settingKeys) key: _c(key).text.trim(),
    };
  }

  Future<void> _testAkinsoftConnection() async {
    setState(() => _testingAkinsoft = true);
    try {
      final response = await http
          .post(
            _akinsoftUri('test-connection'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(_currentSettingsPayload()),
          )
          .timeout(const Duration(seconds: 20));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Beklenmeyen test yanıtı.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['ok'] != true) {
        throw Exception(decoded['error'] ?? 'Bağlantı başarısız.');
      }
      if (!mounted) return;
      final tables = (decoded['candidateTables'] as List?) ?? const [];
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Akınsoft MSSQL Bağlantısı Başarılı'),
          content: SizedBox(
            width: 620,
            child: SingleChildScrollView(
              child: Text(
                [
                  'Database: ${decoded['database']}',
                  if ((decoded['version'] ?? '').toString().isNotEmpty)
                    'Server: ${decoded['version']}',
                  '',
                  'Fatura/Cari/Stok aday tablolar:',
                  for (final row in tables.take(80))
                    '- ${row['schema_name']}.${row['table_name']}',
                ].join('\n'),
              ),
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Akınsoft bağlantı testi başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _testingAkinsoft = false);
    }
  }

  Future<void> _analyzeAkinsoftTables() async {
    setState(() => _analyzingAkinsoft = true);
    try {
      final response = await http
          .post(
            _akinsoftUri('analyze'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(_currentSettingsPayload()),
          )
          .timeout(const Duration(seconds: 35));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Beklenmeyen analiz yanıtı.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['ok'] != true) {
        throw Exception(decoded['error'] ?? 'Tablo analizi başarısız.');
      }
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _AkinsoftAnalysisDialog(data: decoded),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Akınsoft tablo analizi başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _analyzingAkinsoft = false);
    }
  }

  Future<void> _pullAkinsoftData() async {
    setState(() => _pullingAkinsoft = true);
    try {
      final response = await http
          .post(
            _akinsoftUri('pull'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({..._currentSettingsPayload(), 'limit': 2000}),
          )
          .timeout(const Duration(minutes: 2));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw Exception('Beklenmeyen veri çekme yanıtı.');
      }
      if (response.statusCode < 200 ||
          response.statusCode >= 300 ||
          decoded['ok'] != true) {
        throw Exception(decoded['error'] ?? 'Veri çekme başarısız.');
      }
      decoded['_settingsPayload'] = _currentSettingsPayload();
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _AkinsoftPullDialog(data: decoded),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Akınsoft verisi çekilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _pullingAkinsoft = false);
    }
  }

  Future<void> _bulkMatchAkinsoftCustomers() async {
    setState(() => _bulkMatchingCustomers = true);
    try {
      final localCustomers = await ref.read(customersLookupProvider.future);
      final response = await http
          .post(
            _akinsoftUri('pull'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({..._currentSettingsPayload(), 'limit': 2000}),
          )
          .timeout(const Duration(minutes: 2));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['ok'] != true) {
        throw Exception(
          decoded is Map ? decoded['error'] : 'Akınsoft carileri alınamadı.',
        );
      }
      final akinsoftCustomers = ((decoded['customers'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.cast<String, dynamic>())
          .toList();
      final suggestions = _buildCustomerMatchSuggestions(
        akinsoftCustomers,
        localCustomers,
      );
      final selected = <int>{
        for (var i = 0; i < suggestions.length; i++)
          if ((suggestions[i]['score'] as num? ?? 0) >= 0.72) i,
      };
      var savingMatches = false;
      var savingDone = 0;
      var savingTotal = 0;
      Map<String, dynamic>? saveSummary;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) => AlertDialog(
            title: const Text('Toplu Cari Eşleştirme'),
            content: SizedBox(
              width: 980,
              height: MediaQuery.sizeOf(context).height * 0.70,
              child: Stack(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        saveSummary != null
                            ? 'Eşleştirme tamamlandı. Bu ekranda tekrar görünmemesi için listeyi kapatıp yeniden açabilirsiniz.'
                            : savingMatches
                            ? '$savingDone / $savingTotal eşleşme yazıldı (%${savingTotal == 0 ? 0 : ((savingDone / savingTotal) * 100).floor()})'
                            : '${akinsoftCustomers.length} Akınsoft cari tarandı. '
                                  '${suggestions.length} öneri bulundu. Seçili olanlar Akınsoft’a yazılacak.',
                      ),
                      if (savingMatches) ...[
                        const Gap(10),
                        LinearProgressIndicator(
                          value: savingTotal == 0
                              ? null
                              : savingDone / savingTotal,
                        ),
                      ],
                      const Gap(10),
                      Expanded(
                        child: saveSummary != null
                            ? _BulkMatchResult(summary: saveSummary!)
                            : suggestions.isEmpty
                            ? const Center(
                                child: Text('Eşleşme önerisi bulunamadı.'),
                              )
                            : ListView.separated(
                                itemCount: suggestions.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = suggestions[index];
                                  final source =
                                      item['source'] as Map<String, dynamic>;
                                  final customer = item['customer'] as Customer;
                                  final score =
                                      ((item['score'] as num? ?? 0) * 100)
                                          .round();
                                  return CheckboxListTile(
                                    value: selected.contains(index),
                                    onChanged: savingMatches
                                        ? null
                                        : (value) => setDialogState(() {
                                            if (value == true) {
                                              selected.add(index);
                                            } else {
                                              selected.remove(index);
                                            }
                                          }),
                                    title: Text(
                                      '${source['name'] ?? '-'}  ->  ${customer.name}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      'Akınsoft: ${source['code'] ?? '-'} / VKN ${source['taxNumber'] ?? '-'}  |  CRM VKN ${customer.vkn ?? '-'}  |  Benzerlik %$score',
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                  if (savingMatches)
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.78),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(
                                value: savingTotal == 0
                                    ? null
                                    : savingDone / savingTotal,
                              ),
                              const Gap(16),
                              Text(
                                '$savingDone / $savingTotal eşleşme yazıldı',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const Gap(8),
                              Text(
                                'İlerleme: %${savingTotal == 0 ? 0 : ((savingDone / savingTotal) * 100).floor()}',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                              const Gap(8),
                              Text(
                                'Lütfen bu pencereyi kapatmayın.',
                                textAlign: TextAlign.center,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: savingMatches
                    ? null
                    : () => Navigator.of(dialogContext).pop(),
                child: const Text('Kapat'),
              ),
              FilledButton.icon(
                onPressed:
                    selected.isEmpty || savingMatches || saveSummary != null
                    ? null
                    : () async {
                        final messenger = ScaffoldMessenger.of(context);
                        final matches = selected.map((index) {
                          final item = suggestions[index];
                          final source = item['source'] as Map<String, dynamic>;
                          final customer = item['customer'] as Customer;
                          return {
                            'sourceId': source['sourceId'],
                            'sourceCode': source['code'],
                            'sourceName': source['name'],
                            'localCustomerId': customer.id,
                            'matchedManually': true,
                          };
                        }).toList();
                        setDialogState(() {
                          savingMatches = true;
                          savingDone = 0;
                          savingTotal = matches.length;
                        });
                        await Future<void>.delayed(Duration.zero);
                        try {
                          final startResponse = await http
                              .post(
                                _akinsoftUri('bulk-map-customers-job'),
                                headers: {
                                  'Content-Type':
                                      'application/json; charset=utf-8',
                                },
                                body: jsonEncode({
                                  'settings': _currentSettingsPayload(),
                                  'matches': matches,
                                }),
                              )
                              .timeout(const Duration(seconds: 20));
                          final started = jsonDecode(startResponse.body);
                          if (started is! Map || started['ok'] != true) {
                            throw Exception(
                              started is Map
                                  ? started['error']
                                  : 'Toplu eşleştirme başlatılamadı.',
                            );
                          }
                          final jobId = started['jobId']?.toString() ?? '';
                          if (jobId.isEmpty) {
                            throw Exception('İş numarası alınamadı.');
                          }
                          Map<String, dynamic> summary = const {};
                          while (true) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 700),
                            );
                            final statusResponse = await http
                                .get(
                                  _akinsoftUri('bulk-map-customers-job', {
                                    'id': jobId,
                                  }),
                                )
                                .timeout(const Duration(seconds: 10));
                            final statusDecoded = jsonDecode(
                              statusResponse.body,
                            );
                            if (statusDecoded is! Map ||
                                statusDecoded['ok'] != true) {
                              throw Exception(
                                statusDecoded is Map
                                    ? statusDecoded['error']
                                    : 'İş durumu alınamadı.',
                              );
                            }
                            final job =
                                ((statusDecoded['job'] as Map?) ??
                                        const <String, dynamic>{})
                                    .cast<String, dynamic>();
                            if (dialogContext.mounted) {
                              setDialogState(() {
                                savingDone = ((job['current'] as num?) ?? 0)
                                    .toInt();
                                savingTotal =
                                    ((job['total'] as num?) ?? matches.length)
                                        .toInt();
                              });
                            }
                            final status = job['status']?.toString() ?? '';
                            if (status == 'done') {
                              summary =
                                  ((job['summary'] as Map?) ??
                                          const <String, dynamic>{})
                                      .cast<String, dynamic>();
                              break;
                            }
                            if (status == 'error') {
                              throw Exception(
                                job['error'] ?? 'Toplu eşleştirme hatası.',
                              );
                            }
                          }
                          setDialogState(() {
                            saveSummary = summary;
                            savingMatches = false;
                            selected.clear();
                          });
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Toplu eşleşme kaydedildi: ${summary['saved'] ?? 0}. '
                                'Akınsoft’a yazılan: ${summary['wroteBack'] ?? 0}. '
                                'Hata: ${((summary['errors'] as List?) ?? const []).length}.',
                              ),
                            ),
                          );
                        } catch (error) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(
                                'Toplu eşleşme kaydedilemedi: $error',
                              ),
                            ),
                          );
                          if (dialogContext.mounted) {
                            setDialogState(() => savingMatches = false);
                          }
                        }
                      },
                icon: savingMatches
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.save_rounded, size: 18),
                label: Text(
                  savingMatches
                      ? 'Yazılıyor...'
                      : saveSummary != null
                      ? 'Tamamlandı'
                      : 'Seçili Eşleşmeleri Akınsoft’a Yaz (${selected.length})',
                ),
              ),
            ],
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplu cari eşleştirme yapılamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _bulkMatchingCustomers = false);
    }
  }

  List<Map<String, Object>> _buildCustomerMatchSuggestions(
    List<Map<String, dynamic>> akinsoftCustomers,
    List<Customer> localCustomers,
  ) {
    final result = <Map<String, Object>>[];
    final byVkn = {
      for (final c in localCustomers)
        if ((c.vkn ?? '').trim().isNotEmpty) c.vkn!.trim(): c,
    };
    for (final source in akinsoftCustomers) {
      final sourceId = source['sourceId']?.toString() ?? '';
      if (sourceId.isEmpty) continue;
      final customerMatch = source['customerMatch'];
      if (customerMatch is Map && customerMatch['matched'] == true) {
        continue;
      }
      final tax = source['taxNumber']?.toString().trim();
      Customer? best;
      var bestScore = 0.0;
      if (tax != null && tax.isNotEmpty && byVkn.containsKey(tax)) {
        best = byVkn[tax];
        bestScore = 1;
      } else {
        final sourceName = _matchKey(source['name']);
        if (sourceName.length < 4) continue;
        for (final customer in localCustomers) {
          final score = _nameSimilarity(sourceName, _matchKey(customer.name));
          if (score > bestScore) {
            bestScore = score;
            best = customer;
          }
        }
      }
      if (best != null && bestScore >= 0.58) {
        result.add({'source': source, 'customer': best, 'score': bestScore});
      }
    }
    result.sort((a, b) => ((b['score'] as num).compareTo(a['score'] as num)));
    return result;
  }

  static String _matchKey(Object? value) {
    final text = (value ?? '').toString().toUpperCase();
    return text
        .replaceAll('İ', 'I')
        .replaceAll('I', 'I')
        .replaceAll('Ğ', 'G')
        .replaceAll('Ü', 'U')
        .replaceAll('Ş', 'S')
        .replaceAll('Ö', 'O')
        .replaceAll('Ç', 'C')
        .replaceAll(
          RegExp(r'\b(LTD|LIMITED|ŞTI|STI|ANONIM|AŞ|AS|TIC|TICARET|VE)\b'),
          ' ',
        )
        .replaceAll(RegExp(r'[^A-Z0-9]+'), ' ')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  static double _nameSimilarity(String a, String b) {
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 1;
    if (a.contains(b) || b.contains(a)) {
      return (a.length < b.length ? a.length : b.length) /
          (a.length > b.length ? a.length : b.length);
    }
    final aTokens = a.split(' ').where((e) => e.length > 1).toSet();
    final bTokens = b.split(' ').where((e) => e.length > 1).toSet();
    if (aTokens.isEmpty || bTokens.isEmpty) return 0;
    final common = aTokens.intersection(bTokens).length;
    return (2 * common) / (aTokens.length + bTokens.length);
  }

  Future<void> _cleanupDuplicateCustomers() async {
    setState(() => _cleaningCustomers = true);
    try {
      final previewResponse = await http
          .get(_akinsoftUri('duplicate-customers'))
          .timeout(const Duration(seconds: 30));
      final preview = jsonDecode(previewResponse.body);
      if (preview is! Map || preview['ok'] != true) {
        throw Exception(
          preview is Map ? preview['error'] : 'Önizleme alınamadı.',
        );
      }
      final groups = preview['duplicateGroups'] ?? 0;
      final removable = preview['removableCustomers'] ?? 0;
      final vknless = preview['vknlessCustomers'] ?? 0;
      if (!mounted) return;
      if (removable == 0 && vknless == 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Temizlenecek çift cari bulunmadı.')),
        );
        return;
      }
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Çift carileri temizle'),
          content: Text(
            '$groups grup içinde $removable çift cari ve $vknless VKN’siz Akınsoft carisi bulundu. Bağlantılar korunarak temizlensin mi?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Temizle'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final response = await http
          .post(_akinsoftUri('duplicate-customers'))
          .timeout(const Duration(minutes: 2));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception(
          decoded is Map ? decoded['error'] : 'Temizlik başarısız.',
        );
      }
      ref.invalidate(customersLookupProvider);
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Temizlendi: ${decoded['merged'] ?? 0} silindi, ${decoded['deactivated'] ?? 0} pasife alındı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Çift cari temizliği başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _cleaningCustomers = false);
    }
  }
}

class _BulkMatchResult extends StatelessWidget {
  const _BulkMatchResult({required this.summary});

  final Map<String, dynamic> summary;

  @override
  Widget build(BuildContext context) {
    final requested = summary['requested'] ?? 0;
    final saved = summary['saved'] ?? 0;
    final verified = summary['verified'] ?? 0;
    final wroteBack = summary['wroteBack'] ?? 0;
    final skipped = (summary['skipped'] as List?) ?? const [];
    final errors = (summary['errors'] as List?) ?? const [];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
      ),
      child: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            'İstenen: $requested',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Gap(8),
          Text('CRM eşleşme kaydı: $saved'),
          Text('CRM doğrulanan kayıt: $verified'),
          Text('Akınsoft’a yazılan: $wroteBack'),
          Text('Atlanan: ${skipped.length}'),
          Text('Hata: ${errors.length}'),
          if (errors.isNotEmpty) ...[
            const Gap(12),
            Text('Hatalar', style: Theme.of(context).textTheme.titleSmall),
            const Gap(6),
            for (final raw in errors.take(20)) _BulkMatchDetail(raw: raw),
          ],
          if (skipped.isNotEmpty) ...[
            const Gap(12),
            Text('Atlananlar', style: Theme.of(context).textTheme.titleSmall),
            const Gap(6),
            for (final raw in skipped.take(20)) _BulkMatchDetail(raw: raw),
          ],
        ],
      ),
    );
  }
}

class _BulkMatchDetail extends StatelessWidget {
  const _BulkMatchDetail({required this.raw});

  final Object? raw;

  @override
  Widget build(BuildContext context) {
    final map = raw is Map ? raw as Map : null;
    return Text(
      '- ${map?['sourceId'] ?? '-'}: ${map?['error'] ?? map?['reason'] ?? raw}',
      style: Theme.of(context).textTheme.bodySmall,
    );
  }
}

class _AkinsoftPullDialog extends ConsumerStatefulWidget {
  const _AkinsoftPullDialog({required this.data});

  final Map<String, dynamic> data;

  @override
  ConsumerState<_AkinsoftPullDialog> createState() =>
      _AkinsoftPullDialogState();
}

class _AkinsoftPullDialogState extends ConsumerState<_AkinsoftPullDialog> {
  bool _importing = false;
  int _importCurrent = 0;
  int _importTotal = 0;
  int _importPercent = 0;
  String _importElapsed = '00:00';
  String? _importInvoiceNumber;
  bool _savingMatches = false;
  bool _showOnlyMatchedInvoices = false;
  final Set<String> _selectedInvoices = {};

  @override
  void initState() {
    super.initState();
    final invoices = (widget.data['invoices'] as List?) ?? const [];
    for (final raw in invoices) {
      if (raw is! Map) continue;
      final id = raw['sourceId']?.toString();
      if (id != null && id.isNotEmpty) _selectedInvoices.add(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final counts = (data['counts'] as Map?)?.cast<String, dynamic>() ?? {};
    final customers = (data['customers'] as List?) ?? const [];
    final products = (data['products'] as List?) ?? const [];
    final invoices = ((data['invoices'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final selectedMatchedCount = invoices
        .where(
          (item) => _selectedInvoices.contains(item['sourceId']?.toString()),
        )
        .where((item) => (item['customerMatch'] as Map?)?['matched'] == true)
        .length;
    final unmatched = invoices
        .where((item) => (item['customerMatch'] as Map?)?['matched'] != true)
        .length;
    final visibleInvoices = _showOnlyMatchedInvoices
        ? invoices
              .where(
                (item) => (item['customerMatch'] as Map?)?['matched'] == true,
              )
              .toList()
        : invoices;
    return AlertDialog(
      title: const Text('Akınsoft Verisi Hazır'),
      content: SizedBox(
        width: 1040,
        height: MediaQuery.sizeOf(context).height * 0.76,
        child: ListView(
          children: [
            Text('Database: ${data['database']}'),
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                AppBadge(
                  label: '${counts['customers'] ?? 0} cari',
                  tone: AppBadgeTone.primary,
                ),
                AppBadge(
                  label: '${counts['products'] ?? 0} stok',
                  tone: AppBadgeTone.success,
                ),
                AppBadge(
                  label: '${counts['invoices'] ?? 0} fatura',
                  tone: AppBadgeTone.warning,
                ),
                if (((counts['filteredInvoices'] as num?)?.toInt() ?? 0) > 0)
                  AppBadge(
                    label:
                        '${counts['filteredInvoices']} filtre dışı (${counts['rawInvoices']} ham)',
                    tone: AppBadgeTone.neutral,
                  ),
                AppBadge(
                  label: '${counts['invoiceItems'] ?? 0} fatura satırı',
                  tone: AppBadgeTone.neutral,
                ),
                AppBadge(
                  label: '$unmatched eşleşmeyen cari',
                  tone: unmatched == 0
                      ? AppBadgeTone.success
                      : AppBadgeTone.warning,
                ),
              ],
            ),
            const Gap(16),
            if (_importing) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Faturalar içe aktarılıyor: $_importCurrent / $_importTotal (%$_importPercent)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(8),
                    LinearProgressIndicator(
                      value: _importTotal <= 0
                          ? null
                          : (_importCurrent / _importTotal).clamp(0, 1),
                    ),
                    const Gap(8),
                    Text(
                      [
                        'Geçen süre: $_importElapsed',
                        if ((_importInvoiceNumber ?? '').isNotEmpty)
                          'Aktif fatura: $_importInvoiceNumber',
                      ].join(' • '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const Gap(12),
            ],
            _InvoiceSelectionSection(
              invoices: visibleInvoices,
              selectedInvoices: _selectedInvoices,
              showOnlyMatched: _showOnlyMatchedInvoices,
              onShowOnlyMatchedChanged: (value) {
                setState(() {
                  _showOnlyMatchedInvoices = value;
                  if (value) {
                    final visibleIds = invoices
                        .where(
                          (item) =>
                              (item['customerMatch'] as Map?)?['matched'] ==
                              true,
                        )
                        .map((item) => item['sourceId']?.toString() ?? '')
                        .where((id) => id.isNotEmpty)
                        .toSet();
                    _selectedInvoices.removeWhere(
                      (id) => !visibleIds.contains(id),
                    );
                  }
                });
              },
              onToggle: (id, selected) {
                setState(() {
                  if (selected) {
                    _selectedInvoices.add(id);
                  } else {
                    _selectedInvoices.remove(id);
                  }
                });
              },
              onSelectAll: () {
                setState(() {
                  _selectedInvoices
                    ..clear()
                    ..addAll(
                      visibleInvoices
                          .map((item) => item['sourceId']?.toString() ?? '')
                          .where((id) => id.isNotEmpty),
                    );
                });
              },
              onClear: () => setState(_selectedInvoices.clear),
              onMatchCustomer: _showCustomerMatchDialog,
            ),
            const Gap(12),
            _PullPreviewSection(
              title: 'Cari Örnekleri',
              rows: customers,
              formatter: (row) =>
                  '${row['code'] ?? '-'} • ${row['name']} • VKN ${row['taxNumber'] ?? '-'}',
            ),
            const Gap(12),
            _PullPreviewSection(
              title: 'Stok Örnekleri',
              rows: products,
              formatter: (row) =>
                  '${row['code'] ?? '-'} • ${row['name']} • KDV %${_fmt(row['taxRate'])}',
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _importing || _savingMatches
              ? null
              : () {
                  Clipboard.setData(
                    ClipboardData(
                      text: const JsonEncoder.withIndent('  ').convert(data),
                    ),
                  );
                },
          child: const Text('JSON Kopyala'),
        ),
        OutlinedButton.icon(
          onPressed: _importing || _savingMatches
              ? null
              : _saveMatchedCustomers,
          icon: _savingMatches
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.link_rounded, size: 18),
          label: const Text('Eşleşmeleri Toplu Kaydet'),
        ),
        OutlinedButton.icon(
          onPressed: _importing || _savingMatches ? null : _importData,
          icon: _importing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.download_done_rounded, size: 18),
          label: Text('Eşleşmişleri İçe Aktar ($selectedMatchedCount)'),
        ),
        FilledButton(
          onPressed: _importing || _savingMatches
              ? null
              : () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }

  Future<void> _saveMatchedCustomers() async {
    final invoices = ((widget.data['invoices'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where(
          (item) => _selectedInvoices.contains(item['sourceId']?.toString()),
        )
        .toList();
    final seenSources = <String>{};
    final matches = <Map<String, dynamic>>[];
    var unmatched = 0;
    for (final invoice in invoices) {
      final match =
          (invoice['customerMatch'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final sourceId = invoice['customerSourceId']?.toString() ?? '';
      final localId = match['localId']?.toString() ?? '';
      if (match['matched'] != true || sourceId.isEmpty || localId.isEmpty) {
        unmatched += 1;
        continue;
      }
      if (!seenSources.add(sourceId)) continue;
      matches.add({
        'sourceId': sourceId,
        'sourceCode': invoice['customerCode'],
        'sourceName': invoice['customerName'],
        'localCustomerId': localId,
        'matchedManually':
            match['method']?.toString().startsWith('manual') == true,
      });
    }
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            unmatched > 0
                ? 'Seçili faturalarda kaydedilecek eşleşmiş cari yok.'
                : 'Kaydedilecek cari eşleşmesi yok.',
          ),
        ),
      );
      return;
    }
    setState(() => _savingMatches = true);
    try {
      final response = await http
          .post(
            _akinsoftUri('bulk-map-customers'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              'settings': widget.data['_settingsPayload'],
              'matches': matches,
            }),
          )
          .timeout(const Duration(minutes: 3));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map || decoded['ok'] != true) {
        throw Exception(
          decoded is Map ? decoded['error'] : 'Toplu eşleştirme başarısız.',
        );
      }
      if (!mounted) return;
      final summary =
          (decoded['summary'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      final errors = (summary['errors'] as List? ?? const []).length;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Eşleşmeler kaydedildi: ${summary['saved'] ?? 0}. '
            'Akınsoft’a yazılan: ${summary['wroteBack'] ?? 0}. '
            'Eşleşmeyen seçili: $unmatched. Hata: $errors.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplu eşleşme kaydedilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingMatches = false);
    }
  }

  Future<void> _importData() async {
    final invoices = ((widget.data['invoices'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where(
          (item) => _selectedInvoices.contains(item['sourceId']?.toString()),
        )
        .toList();
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İçe aktarılacak fatura seçilmedi.')),
      );
      return;
    }
    final unmatchedInvoices = invoices
        .where(
          (invoice) => (invoice['customerMatch'] as Map?)?['matched'] != true,
        )
        .toList();
    if (unmatchedInvoices.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${unmatchedInvoices.length} seçili faturanın carisi eşleşmemiş. '
            'Eşleşmeyen faturalar içe aktarılamaz.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _importing = true;
      _importCurrent = 0;
      _importTotal = invoices.length;
      _importPercent = 0;
      _importElapsed = '00:00';
      _importInvoiceNumber = null;
    });
    try {
      final payload = Map<String, dynamic>.from(widget.data);
      payload['invoices'] = invoices;
      payload['customers'] = _relatedCustomers(invoices);
      payload['products'] = _relatedProducts(invoices);
      final startedAt = DateTime.now();
      final startResponse = await http
          .post(
            _akinsoftUri('import-job'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 20));
      final started = jsonDecode(startResponse.body);
      if (started is! Map || started['ok'] != true) {
        throw Exception(
          started is Map ? started['error'] : 'İçe aktarma başlatılamadı.',
        );
      }
      final jobId = started['jobId']?.toString() ?? '';
      if (jobId.isEmpty) throw Exception('İçe aktarma iş numarası alınamadı.');
      Map<String, dynamic> summary = const {};
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 700));
        final statusResponse = await http
            .get(_akinsoftUri('import-job', {'id': jobId}))
            .timeout(const Duration(seconds: 10));
        final statusDecoded = jsonDecode(statusResponse.body);
        if (statusDecoded is! Map || statusDecoded['ok'] != true) {
          throw Exception(
            statusDecoded is Map
                ? statusDecoded['error']
                : 'İçe aktarma durumu alınamadı.',
          );
        }
        final job =
            (statusDecoded['job'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final elapsed = DateTime.now().difference(startedAt);
        if (mounted) {
          setState(() {
            _importCurrent = (job['current'] as num?)?.toInt() ?? 0;
            _importTotal = (job['total'] as num?)?.toInt() ?? invoices.length;
            _importPercent = (job['percent'] as num?)?.toInt() ?? 0;
            _importElapsed = _formatDuration(elapsed);
            _importInvoiceNumber = job['currentInvoiceNumber']?.toString();
          });
        }
        final status = job['status']?.toString();
        if (status == 'done') {
          summary =
              (job['summary'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          break;
        }
        if (status == 'error') {
          throw Exception(job['error'] ?? 'İçe aktarma başarısız.');
        }
      }
      ref.invalidate(invoicesProvider);
      ref.invalidate(productsProvider(null));
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      final matches =
          (summary['customerMatches'] as Map?)?.cast<String, dynamic>() ??
          const <String, dynamic>{};
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'İçe aktarıldı: ${summary['customers'] ?? 0} cari, '
            '${summary['products'] ?? 0} stok, '
            '${summary['invoices'] ?? 0} fatura. '
            'Cari eşleşme: kaynak ${matches['source'] ?? 0}, '
            'VKN ${matches['tax'] ?? 0}, kod ${matches['code'] ?? 0}, '
            'yeni ${matches['created'] ?? 0}.',
          ),
        ),
      );
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? 'İçe aktarma beklenenden uzun sürdü. İşlem sunucuda devam etmiş olabilir; birkaç dakika sonra Yenile ile kontrol edin.'
          : 'İçe aktarılamadı: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _formatDuration(Duration value) {
    final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours = value.inHours;
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  List<Map<String, dynamic>> _relatedCustomers(
    List<Map<String, dynamic>> invoices,
  ) {
    final sourceIds = invoices
        .map((item) => item['customerSourceId']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet();
    final codes = invoices
        .map((item) => item['customerCode']?.toString() ?? '')
        .where((item) => item.isNotEmpty)
        .toSet();
    return ((widget.data['customers'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) {
          final sourceId = item['sourceId']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          return sourceIds.contains(sourceId) || codes.contains(code);
        })
        .toList();
  }

  List<Map<String, dynamic>> _relatedProducts(
    List<Map<String, dynamic>> invoices,
  ) {
    final sourceIds = <String>{};
    final codes = <String>{};
    for (final invoice in invoices) {
      for (final raw in (invoice['items'] as List? ?? const [])) {
        if (raw is! Map) continue;
        final item = raw.cast<String, dynamic>();
        final sourceId = item['productSourceId']?.toString() ?? '';
        final code = item['code']?.toString() ?? '';
        if (sourceId.isNotEmpty) sourceIds.add(sourceId);
        if (code.isNotEmpty) codes.add(code);
      }
    }
    return ((widget.data['products'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where((item) {
          final sourceId = item['sourceId']?.toString() ?? '';
          final code = item['code']?.toString() ?? '';
          return sourceIds.contains(sourceId) || codes.contains(code);
        })
        .toList();
  }

  Future<void> _showCustomerMatchDialog(Map<String, dynamic> invoice) async {
    final sourceId = invoice['customerSourceId']?.toString();
    if (sourceId == null || sourceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu faturada Akınsoft cari kodu yok.')),
      );
      return;
    }
    final search = TextEditingController(
      text: (invoice['customerName'] ?? '').toString(),
    );
    List<Map<String, dynamic>> customers = [];
    String? selectedCustomerId;
    bool loading = false;
    bool saving = false;
    bool hasLoaded = false;
    int searchRequestId = 0;
    Timer? searchDebounce;

    Future<void> load(StateSetter setDialogState) async {
      final query = search.text.trim();
      if (query.length < 2) {
        setDialogState(() {
          hasLoaded = true;
          loading = false;
          customers = [];
          selectedCustomerId = null;
        });
        return;
      }
      final requestId = ++searchRequestId;
      setDialogState(() {
        hasLoaded = true;
        loading = true;
      });
      try {
        final uri = _akinsoftUri('local-customers', {'search': query});
        final response = await http
            .get(uri)
            .timeout(const Duration(seconds: 20));
        final decoded = jsonDecode(response.body);
        if (decoded is! Map || decoded['ok'] != true) {
          throw Exception(
            decoded is Map ? decoded['error'] : 'Cari aranamadı.',
          );
        }
        final rows = (decoded['customers'] as List? ?? const [])
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList();
        if (requestId != searchRequestId) return;
        setDialogState(() {
          customers = rows;
          if (!rows.any(
            (item) => item['id']?.toString() == selectedCustomerId,
          )) {
            selectedCustomerId = null;
          }
        });
      } catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cari listesi alınamadı: $error')),
        );
      } finally {
        if (requestId == searchRequestId) {
          setDialogState(() => loading = false);
        }
      }
    }

    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            if (!hasLoaded && !loading) {
              scheduleMicrotask(() => load(setDialogState));
            }
            return AlertDialog(
              title: const Text('Cari Eşleştir'),
              content: SizedBox(
                width: 680,
                height: 470,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invoice['invoiceNumber']} • ${invoice['customerName'] ?? '-'}',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: search,
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              labelText: 'CRM carisi ara',
                            ),
                            onChanged: (_) {
                              searchDebounce?.cancel();
                              searchDebounce = Timer(
                                const Duration(milliseconds: 350),
                                () {
                                  if (dialogContext.mounted) {
                                    load(setDialogState);
                                  }
                                },
                              );
                            },
                            onSubmitted: (_) => load(setDialogState),
                          ),
                        ),
                        const Gap(8),
                        OutlinedButton.icon(
                          onPressed: loading
                              ? null
                              : () => load(setDialogState),
                          icon: loading
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_rounded, size: 18),
                          label: const Text('Ara'),
                        ),
                      ],
                    ),
                    const Gap(12),
                    Expanded(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppTheme.border),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusMd,
                          ),
                        ),
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : search.text.trim().length < 2
                            ? const Center(
                                child: Text(
                                  'Listelemek için en az 2 harf yazın.',
                                ),
                              )
                            : customers.isEmpty
                            ? const Center(child: Text('Cari bulunamadı.'))
                            : ListView.separated(
                                itemCount: customers.length,
                                separatorBuilder: (_, _) => const Divider(
                                  height: 1,
                                  color: AppTheme.border,
                                ),
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  final id = customer['id']?.toString() ?? '';
                                  final selected = selectedCustomerId == id;
                                  return ListTile(
                                    selected: selected,
                                    leading: Icon(
                                      selected
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: selected
                                          ? AppTheme.primary
                                          : AppTheme.textMuted,
                                    ),
                                    title: Text(
                                      customer['name']?.toString() ?? '-',
                                    ),
                                    subtitle: Text(
                                      'VKN: ${customer['tax_number'] ?? '-'} - Tel: ${customer['phone1'] ?? '-'}',
                                    ),
                                    onTap: () => setDialogState(
                                      () => selectedCustomerId = id,
                                    ),
                                  );
                                },
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: const Text('İptal'),
                ),
                FilledButton.icon(
                  onPressed: saving || selectedCustomerId == null
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          setDialogState(() => saving = true);
                          try {
                            final response = await http
                                .post(
                                  _akinsoftUri('map-customer'),
                                  headers: {
                                    'Content-Type':
                                        'application/json; charset=utf-8',
                                  },
                                  body: jsonEncode({
                                    'settings': widget.data['_settingsPayload'],
                                    'sourceId': sourceId,
                                    'sourceCode': invoice['customerCode'],
                                    'sourceName': invoice['customerName'],
                                    'localCustomerId': selectedCustomerId,
                                  }),
                                )
                                .timeout(const Duration(seconds: 45));
                            final decoded = jsonDecode(response.body);
                            if (decoded is! Map || decoded['ok'] != true) {
                              throw Exception(
                                decoded is Map
                                    ? decoded['error']
                                    : 'Eşleştirme başarısız.',
                              );
                            }
                            setState(
                              () => invoice['customerMatch'] = decoded['match'],
                            );
                            if (!dialogContext.mounted) return;
                            Navigator.of(dialogContext).pop();
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Cari eşleşmesi kaydedildi.'),
                              ),
                            );
                          } catch (error) {
                            if (!mounted) return;
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Eşleştirilemedi: $error'),
                              ),
                            );
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  icon: saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.link_rounded, size: 18),
                  label: const Text('Eşleştir ve Akınsoft’a Yaz'),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      searchDebounce?.cancel();
      search.dispose();
    }
  }

  static String _fmt(Object? value) {
    final number = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (number == null) return '-';
    return number.toStringAsFixed(2);
  }
}

class _InvoiceSelectionSection extends StatelessWidget {
  const _InvoiceSelectionSection({
    required this.invoices,
    required this.selectedInvoices,
    required this.showOnlyMatched,
    required this.onShowOnlyMatchedChanged,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    required this.onMatchCustomer,
  });

  final List<Map<String, dynamic>> invoices;
  final Set<String> selectedInvoices;
  final bool showOnlyMatched;
  final ValueChanged<bool> onShowOnlyMatchedChanged;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final Future<void> Function(Map<String, dynamic> invoice) onMatchCustomer;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Aktarılacak Faturalar',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Checkbox(
                      value: showOnlyMatched,
                      onChanged: (value) =>
                          onShowOnlyMatchedChanged(value ?? false),
                    ),
                    const Text('Sadece eşleşmiş'),
                  ],
                ),
                const Gap(8),
                TextButton(
                  onPressed: onSelectAll,
                  child: const Text('Tümünü Seç'),
                ),
                TextButton(onPressed: onClear, child: const Text('Temizle')),
              ],
            ),
          ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: const Color(0xFFF1F5F9),
            child: const Row(
              children: [
                SizedBox(width: 46),
                Expanded(flex: 3, child: _InvoiceHeaderText('Fatura / Cari')),
                SizedBox(width: 108, child: _InvoiceHeaderText('Tarih')),
                SizedBox(width: 118, child: _InvoiceHeaderText('KDV Dahil')),
                SizedBox(
                  width: 230,
                  child: _InvoiceHeaderText('Cari Eşleşmesi'),
                ),
                SizedBox(width: 132),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 330),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: invoices.length,
              separatorBuilder: (_, _) =>
                  const Divider(height: 1, color: AppTheme.border),
              itemBuilder: (context, index) {
                final invoice = invoices[index];
                final id = invoice['sourceId']?.toString() ?? '';
                final sourceCurrency =
                    invoice['currency']?.toString().trim().isEmpty == false
                    ? invoice['currency'].toString()
                    : 'TRY';
                final accountMode = invoice['accountMode']?.toString() ?? '';
                final match =
                    (invoice['customerMatch'] as Map?)
                        ?.cast<String, dynamic>() ??
                    const <String, dynamic>{};
                final matched = match['matched'] == true;
                return Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 7,
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 46,
                        child: Checkbox(
                          value: selectedInvoices.contains(id),
                          onChanged: (value) => onToggle(id, value ?? false),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              invoice['customerName']?.toString() ?? '-',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            Text(
                              '${invoice['invoiceNumber'] ?? '-'} • VKN ${invoice['taxNumber'] ?? '-'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      SizedBox(
                        width: 108,
                        child: Text(
                          _shortDate(invoice['invoiceDate']),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      SizedBox(
                        width: 118,
                        child: Text(
                          [
                            '$sourceCurrency ${_AkinsoftPullDialogState._fmt(invoice['grandTotal'])}',
                            if (accountMode.isNotEmpty) accountMode,
                          ].join(' • '),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      SizedBox(
                        width: 230,
                        child: AppBadge(
                          label: matched
                              ? '${_matchMethodLabel(match['method'])}: ${match['localName'] ?? '-'}'
                              : 'Cari eşleşmedi',
                          tone: matched
                              ? AppBadgeTone.success
                              : AppBadgeTone.warning,
                        ),
                      ),
                      SizedBox(
                        width: 132,
                        child: matched
                            ? const SizedBox.shrink()
                            : OutlinedButton.icon(
                                onPressed: () => onMatchCustomer(invoice),
                                icon: const Icon(Icons.link_rounded, size: 16),
                                label: const Text('Eşleştir'),
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

  static String _shortDate(Object? value) {
    final raw = value?.toString();
    if (raw == null || raw.isEmpty) return '-';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw.length > 10 ? raw.substring(0, 10) : raw;
    return DateFormat('dd.MM.yyyy').format(parsed);
  }

  static String _matchMethodLabel(Object? method) {
    switch (method?.toString()) {
      case 'tax':
        return 'VKN';
      case 'source':
        return 'Kaynak';
      case 'code':
        return 'Kod';
      case 'akinsoft_map':
      case 'manual_akinsoft':
        return 'Akınsoft eşleme';
      case 'manual_local':
        return 'CRM eşleme';
      default:
        return 'Eşleşti';
    }
  }
}

class _PullPreviewSection extends StatelessWidget {
  const _PullPreviewSection({
    required this.title,
    required this.rows,
    required this.formatter,
  });

  final String title;
  final List<dynamic> rows;
  final String Function(Map<String, dynamic> row) formatter;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleSmall),
          const Gap(8),
          if (rows.isEmpty)
            const Text('Kayıt bulunamadı.')
          else
            for (final raw in rows.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Text(
                  formatter(
                    raw is Map
                        ? raw.cast<String, dynamic>()
                        : <String, dynamic>{},
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
        ],
      ),
    );
  }
}

class _AkinsoftAnalysisDialog extends StatelessWidget {
  const _AkinsoftAnalysisDialog({required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final tables = (data['analyzedTables'] as List?) ?? const [];
    final candidates = (data['candidateTables'] as List?) ?? const [];
    final columns = (data['candidateColumns'] as List?) ?? const [];
    return AlertDialog(
      title: const Text('Akınsoft Tablo Analizi'),
      content: SizedBox(
        width: 920,
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: ListView(
          children: [
            Text(
              'Database: ${data['database']}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if ((data['version'] ?? '').toString().isNotEmpty) ...[
              const Gap(4),
              Text('Server: ${data['version']}'),
            ],
            const Gap(14),
            Text(
              'Analiz Edilen Tablolar',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Gap(8),
            for (final raw in tables) _AnalysisTableCard(raw: raw),
            const Gap(12),
            Text(
              'Aday Tablo Sayısı: ${candidates.length}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Gap(6),
            Text(
              candidates
                  .take(70)
                  .map(
                    (row) =>
                        '${row['schema_name']}.${row['table_name']} (${row['approx_rows'] ?? '-'})',
                  )
                  .join('  ·  '),
            ),
            const Gap(14),
            Text(
              'Öne Çıkan Kolonlar',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Gap(6),
            Text(
              columns
                  .take(80)
                  .map(
                    (row) =>
                        '${row['table_name']}.${row['column_name']} (${row['data_type']})',
                  )
                  .join('  ·  '),
            ),
          ],
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Kapat'),
        ),
      ],
    );
  }
}

class _AnalysisTableCard extends StatelessWidget {
  const _AnalysisTableCard({required this.raw});

  final dynamic raw;

  @override
  Widget build(BuildContext context) {
    final row = raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
    final columns = (row['columns'] as List?) ?? const [];
    final samples = (row['samples'] as List?) ?? const [];
    final error = (row['error'] ?? '').toString();
    final tableTitle = '${row['schemaName']}.${row['tableName']}';
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        color: Colors.white,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tableTitle,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              AppBadge(
                label: '${row['rowCount'] ?? '-'} kayıt',
                tone: AppBadgeTone.primary,
                dense: true,
              ),
            ],
          ),
          if (error.isNotEmpty) ...[
            const Gap(8),
            Text(error, style: const TextStyle(color: AppTheme.error)),
          ] else ...[
            const Gap(8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final column in columns.take(24))
                  AppBadge(
                    label: '${column['name']}',
                    tone: AppBadgeTone.neutral,
                    dense: true,
                  ),
              ],
            ),
            if (samples.isNotEmpty) ...[
              const Gap(10),
              Text(
                _formatSample(samples.first),
                maxLines: 7,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontFamily: 'monospace',
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ],
        ],
      ),
    );
  }

  String _formatSample(Object sample) {
    if (sample is! Map) return sample.toString();
    return sample.entries
        .map((entry) => '${entry.key}: ${entry.value ?? '-'}')
        .join('\n');
  }
}

const _settingKeys = [
  'api_base_url',
  'token_url',
  'client_id',
  'username',
  'password',
  'seller_vkn',
  'seller_title',
  'seller_branch_code',
  'seller_tax_office',
  'seller_city',
  'seller_country_code',
  'seller_country',
  'seller_address_line1',
  'seller_address_line2',
  'seller_phone',
  'seller_email',
  'seller_website',
  'next_sales_number',
  'next_purchase_number',
  'akinsoft_sync_enabled',
  'akinsoft_vpn_name',
  'akinsoft_vpn_host',
  'akinsoft_vpn_username',
  'akinsoft_vpn_password',
  'akinsoft_mssql_host',
  'akinsoft_mssql_port',
  'akinsoft_mssql_database',
  'akinsoft_database_year',
  'akinsoft_database_pattern',
  'akinsoft_mssql_username',
  'akinsoft_mssql_password',
  'akinsoft_sync_notes',
];

class _TypeTile extends StatelessWidget {
  const _TypeTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.12),
        child: Icon(icon, color: color),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}

class _MetricsRow extends StatelessWidget {
  const _MetricsRow({required this.metrics});

  final List<_Metric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return GridView.count(
          crossAxisCount: wide ? 4 : 2,
          childAspectRatio: wide ? 3.3 : 2.2,
          crossAxisSpacing: 10,
          mainAxisSpacing: 10,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final metric in metrics)
              AppCard(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
                      child: Icon(metric.icon, color: AppTheme.primary),
                    ),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          Text(
                            metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const Gap(6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(padding: const EdgeInsets.all(16), child: Text(message)),
    );
  }
}

double _parseDecimal(String value) {
  return double.tryParse(value.replaceAll('.', '').replaceAll(',', '.')) ??
      double.tryParse(value.replaceAll(',', '.')) ??
      0;
}
