import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/providers/provider_cache.dart';
import '../../core/format/search_normalize.dart';
import '../../core/platform/open_external_url.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_phosphor_icons.dart';
import '../../core/ui/empty_state_card.dart';
import '../customers/customer_detail_screen.dart';
import '../customers/customer_model.dart';
import '../customers/customers_providers.dart';
import '../invoices/invoice_model.dart';
import '../invoices/invoice_providers.dart';
import '../invoices/invoice_statement_pdf.dart';
import '../invoices/invoice_statement_share.dart';
import 'e_invoice_form_screen.dart';
import 'e_invoice_official_url.dart';
import 'e_invoice_pdf_share.dart';
import 'e_invoice_print.dart';
import 'e_invoice_whatsapp_share.dart';
import '../quotes/quote_providers.dart';
import '../quotes/quotes_screen.dart';

String _friendlyPdfError(Object error) {
  var raw = error.toString().trim();
  // StateError / Exception sarmalayıcılarını soy; sunucu metnini göster.
  for (var i = 0; i < 3; i++) {
    final stripped = raw
        .replaceFirst(
          RegExp(r'^(Bad state: |Exception: |Error: |StateError: )'),
          '',
        )
        .trim();
    if (stripped == raw) break;
    raw = stripped;
  }
  if (raw.isEmpty) return 'PDF oluşturulamadı.';
  final lower = raw.toLowerCase();
  if (lower.contains('invalid user credentials') ||
      lower.contains('invalid login credentials') ||
      lower.contains('invalid_grant') ||
      lower.contains('e-fatura api oturumu açılamadı')) {
    return 'E-fatura API oturumu açılamadı. PDF kayıtlı CRM verisinden '
        'üretilmeli; uygulamayı güncelleyin veya Ayarlar’daki kullanıcı/şifreyi kontrol edin.';
  }
  return raw;
}

/// PDF aç/indir: force yalnızca yeniden üretimi ister; Maliye yenilemez.
Map<String, dynamic> _archivePdfRequestBody(String invoiceId) => {
  'action': 'archive',
  'invoiceId': invoiceId,
  'force': true,
  'includePdf': true,
  'refreshOfficial': false,
};

Future<void> _createInvoicePaymentLinkFlow({
  required BuildContext context,
  required WidgetRef ref,
  required List<Invoice> invoices,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final payable = invoices
      .where(
        (invoice) =>
            invoice.isActive &&
            invoice.isOpen &&
            invoice.remainingAmount > 0 &&
            invoice.invoiceType == 'sales',
      )
      .toList(growable: false);
  if (payable.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Ödeme linki için açık satış faturası seçin.'),
      ),
    );
    return;
  }

  final customerIds = payable.map((e) => e.customerId).toSet();
  if (customerIds.length > 1) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Ödeme linki aynı cari için oluşturulabilir.'),
      ),
    );
    return;
  }

  final currencies = payable.map((e) => e.currency).toSet();
  if (currencies.length > 1) {
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Seçilen faturaların para birimi aynı olmalıdır.'),
      ),
    );
    return;
  }

  final total = payable.fold<double>(
    0,
    (sum, inv) => sum + inv.remainingAmount,
  );
  final currency = (currencies.first).toString().trim().toUpperCase();
  final money = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: _currencySymbol(currency),
    decimalDigits: 2,
  );

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Ödeme linki oluştur'),
      content: Text(
        '${payable.length} fatura için toplam ${money.format(total)} '
        'tutarında Microvise sanal POS ödeme linki oluşturulacak.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Oluştur'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;

  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return;

  try {
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'createInvoicePaymentLink',
        'invoiceIds': payable.map((e) => e.id).toList(),
      },
    );
    final paymentUrl = response['paymentUrl']?.toString() ?? '';
    if (paymentUrl.isEmpty) {
      throw Exception('Ödeme linki alınamadı');
    }
    if (!context.mounted) return;
    final amount = (response['amount'] as num?)?.toDouble() ?? total;
    final responseCurrency =
        (response['currency']?.toString() ?? currency).trim().toUpperCase();
    final resultMoney = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: _currencySymbol(responseCurrency),
      decimalDigits: 2,
    );
    final invoiceCount =
        (response['invoiceCount'] as num?)?.toInt() ?? payable.length;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme linki hazır'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$invoiceCount fatura · ${resultMoney.format(amount)}',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const Gap(12),
            SelectableText(
              paymentUrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: paymentUrl));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Link kopyalandı')),
                );
              }
            },
            child: const Text('Kopyala'),
          ),
          TextButton(
            onPressed: () async {
              await Share.share(
                'Fatura ödemesi için link:\n$paymentUrl',
                subject: 'Microvise fatura ödeme linki',
              );
            },
            child: const Text('Paylaş'),
          ),
          FilledButton(
            onPressed: () async {
              await openExternalUrl(paymentUrl);
            },
            child: const Text('Aç'),
          ),
        ],
      ),
    );
  } catch (error) {
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(content: Text('Ödeme linki oluşturulamadı: $error')),
    );
  }
}

String _formatJobElapsed(Duration value) {
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  final hours = value.inHours;
  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:$minutes:$seconds';
  }
  return '$minutes:$seconds';
}

String _formatJobElapsedShort(Duration value) {
  if (value.inHours > 0) return _formatJobElapsed(value);
  if (value.inMinutes > 0) {
    final m = value.inMinutes;
    final s = value.inSeconds.remainder(60);
    return s > 0 ? '$m dk $s sn' : '$m dk';
  }
  return '${value.inSeconds} sn';
}

final eInvoiceSettingsProvider =
    FutureProvider<Map<String, dynamic>>((ref) async {
      keepProviderAliveFor(ref, const Duration(minutes: 15));
      final apiClient = ref.watch(apiClientProvider);
      final local = await _loadLocalEInvoiceSettings();
      final base = {..._defaultSettings, ...local};
      if (apiClient == null) return Map<String, dynamic>.from(base);
      try {
        final response = await apiClient
            .getJson('/e-invoice')
            .timeout(const Duration(seconds: 4));
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
  // Flutter web-server (ör. :3000/:8080) ayrı local_server (:4000) kullanır.
  // Electron / local_server aynı origin’de /api/akinsoft/ kullanır.
  final separateBridge = isLocalWeb && (base.port == 3000 || base.port == 8080);
  final uri = separateBridge
      ? Uri.parse('http://127.0.0.1:4000/api/akinsoft/')
      : base.resolve('/api/akinsoft/');
  return uri.resolve(normalizedPath).replace(queryParameters: queryParameters);
}

String _akinsoftBridgeError(Object error) {
  final text = error.toString();
  if (RegExp(
    r'Connection refused|Failed host lookup|ClientException|SocketException|XMLHttpRequest',
    caseSensitive: false,
  ).hasMatch(text)) {
    return 'SAP API’ye ulaşılamadı ($error). '
        'Yerelde PORT=4000 local_server çalıştığından emin olun.';
  }
  return 'SAP’a gönderilemedi: $error';
}

const _defaultSettings = <String, dynamic>{
  'environment': 'test',
  'api_base_url': 'https://test-efatura.maliye.gov.ct.tr/api',
  'token_url':
      'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
  'client_id': 'efatura-frontend',
  'seller_vkn': '0620009058',
  'seller_title': 'MICROVISE INNOVATION LTD',
  'seller_branch_code': '1',
  'seller_tax_office': 'Lefkoşa',
  'seller_city': 'LEFKOŞA',
  'seller_country_code': 'XCT',
  'seller_country': 'Kuzey Kıbrıs Türk Cumhuriyeti',
  'seller_address_line1': 'ATATÜRK CAD YENİŞEHİR EMEK 2 APT. DIŞ KAPI NO:1',
  'seller_bank_details':
      'Banka Hesap Bilgileri\nTürkiye İş Bankası\nMicrovise Innovation Ltd\nTL IBAN: TR57 0006 4000 0016 8010 3409 94\nUSD IBAN: TR41 0006 4000 0026 8010 4107 29',
  'next_sales_number': 1,
  'next_purchase_number': 1,
  'akinsoft_sync_enabled': 'false',
  'akinsoft_mssql_port': '1433',
  'akinsoft_database_year': '2026',
  'akinsoft_database_pattern': 'WOLVOX8_MICO_{year}_WOLVOX',
};

const _environmentEndpoints = <String, Map<String, String>>{
  'test': {
    'api_base_url': 'https://test-efatura.maliye.gov.ct.tr/api',
    'token_url':
        'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
  },
  'production': {
    'api_base_url': 'https://efatura.maliye.gov.ct.tr/api',
    'token_url':
        'https://keycloak.maliye.gov.ct.tr/realms/production/protocol/openid-connect/token',
  },
};

class EInvoiceScreen extends ConsumerWidget {
  const EInvoiceScreen({
    super.key,
    this.section = 'faturalar',
    this.invoiceType,
  });

  final String section;

  /// `purchase` | `sales` | null (tümü)
  final String? invoiceType;

  static final _moneyTry = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (section == 'teklif') {
      return const _EInvoiceQuotesShell();
    }

    final settingsAsync = ref.watch(eInvoiceSettingsProvider);

    final child = switch (section) {
      'stok' => _ProductsTab(moneyTry: _moneyTry),
      'cari' => _AccountsTab(moneyTry: _moneyTry),
      'ayarlar' => const _SettingsTab(),
      _ => _InvoicesTab(
        key: ValueKey('invoices-${invoiceType ?? 'all'}'),
        moneyTry: _moneyTry,
        initialInvoiceType: invoiceType,
      ),
    };
    final subtitle = switch (section) {
      'stok' => 'Stok ve hizmet tanımları, SAP grup/alt grup ayrımı.',
      'cari' => 'Cari borç, tahsilat ve ödeme takibi.',
      'ayarlar' => 'Maliye ve SAP entegrasyon ayarları.',
      _ => switch (invoiceType) {
        'purchase' => 'Alış faturaları ve KKTC e-fatura takibi.',
        'sales' => 'Satış faturaları ve KKTC e-fatura gönderimi.',
        _ => 'Alış/satış faturaları, stok, cari ve KKTC e-fatura gönderimi.',
      },
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
          icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _openInvoiceTypeDialog(context, ref),
          icon: const Icon(AppPhosphorIcons.plus, size: 18),
          label: const Text('Yeni Fatura'),
        ),
      ],
      body: Column(
        children: [
          _StatusStrip(settingsAsync: settingsAsync),
          const Gap(8),
          Expanded(child: ClipRect(child: child)),
        ],
      ),
    );
  }

  Future<void> _openInvoiceTypeDialog(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final navigator = Navigator.of(context);
    String? type = invoiceType;
    if (type != 'purchase' && type != 'sales') {
      type = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Fatura Türü'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TypeTile(
                icon: AppPhosphorIcons.arrowUpRight,
                color: AppTheme.primary,
                title: 'Satış Faturası',
                subtitle: 'Müşteriye kesilecek e-fatura',
                onTap: () => Navigator.of(context).pop('sales'),
              ),
              const Gap(8),
              _TypeTile(
                icon: AppPhosphorIcons.arrowDownLeft,
                color: AppTheme.warning,
                title: 'Alış Faturası',
                subtitle: 'Tedarikçi/cari borç kaydı',
                onTap: () => Navigator.of(context).pop('purchase'),
              ),
            ],
          ),
        ),
      );
    }
    if (type == null || !context.mounted) return;
    await navigator.push(
      MaterialPageRoute(
        builder: (context) => EInvoiceFormScreen(invoiceType: type!),
      ),
    );
    ref.invalidate(invoicesProvider);
    ref.invalidate(accountBalancesProvider);
  }
}

class _EInvoiceQuotesShell extends ConsumerStatefulWidget {
  const _EInvoiceQuotesShell();

  @override
  ConsumerState<_EInvoiceQuotesShell> createState() =>
      _EInvoiceQuotesShellState();
}

class _EInvoiceQuotesShellState extends ConsumerState<_EInvoiceQuotesShell> {
  final _quotesTabKey = GlobalKey<QuotesTabState>();

  @override
  Widget build(BuildContext context) {
    return AppPageLayout(
      title: 'E-Fatura',
      subtitle: 'Müşteri teklifleri — satış faturaları ile aynı liste düzeni.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => context.go('/e-fatura/teklif/ayarlar'),
          icon: const Icon(AppPhosphorIcons.gearSix, size: 18),
          label: const Text('Teklif Ayarları'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () {
            final tab = _quotesTabKey.currentState;
            if (tab != null) {
              ref.invalidate(quotesProvider(tab.filter));
            }
          },
          icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _quotesTabKey.currentState?.startNewQuote(),
          icon: const Icon(AppPhosphorIcons.plus, size: 18),
          label: const Text('Yeni Teklif'),
        ),
      ],
      body: Column(
        children: [
          const Gap(8),
          Expanded(
            child: ClipRect(
              child: QuotesTab(key: _quotesTabKey),
            ),
          ),
        ],
      ),
    );
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Color.alphaBlend(
        AppTheme.primary.withValues(alpha: 0.03),
        AppTheme.surface,
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          _InfoPill(
            icon: AppPhosphorIcons.flask,
            label: env == 'production' ? 'Canlı ortam' : 'Test ortamı',
            color: env == 'production' ? AppTheme.error : AppTheme.success,
          ),
          _InfoPill(
            icon: AppPhosphorIcons.buildings,
            label: sellerVkn.isEmpty ? 'VKN bekleniyor' : 'VKN $sellerVkn',
            color: AppTheme.primary,
          ),
          _InfoPill(
            icon: AppPhosphorIcons.key,
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
  const _InvoicesTab({
    super.key,
    required this.moneyTry,
    this.initialInvoiceType,
  });

  final NumberFormat moneyTry;
  final String? initialInvoiceType;

  @override
  ConsumerState<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> {
  static const int _invoiceRenderStep = 80;

  final Set<String> _selectedInvoiceIds = {};
  late InvoiceFilter _filter = InvoiceFilter(
    status: 'open',
    invoiceType: widget.initialInvoiceType,
  );
  List<Invoice> _lastInvoices = const [];
  int _visibleInvoiceLimit = _invoiceRenderStep;
  bool _bulkDeleting = false;
  bool _bulkProcessing = false;
  bool _pullingAkinsoft = false;
  bool _syncingIncoming = false;

  @override
  Widget build(BuildContext context) {
    final invoicesAsync = ref.watch(invoicesProvider(_filter));
    final customersAsync = ref.watch(customersLookupProvider);
    final eInvoiceSettings =
        ref.watch(eInvoiceSettingsProvider).value ?? const {};
    final isProduction =
        (eInvoiceSettings['environment'] ?? 'test').toString() == 'production';
    final apiSendLabel = isProduction
        ? 'Maliye’ye Gönder'
        : 'Maliye Testine Gönder';

    if (invoicesAsync.hasValue) {
      _lastInvoices = invoicesAsync.value ?? const [];
    }
    if (invoicesAsync.isLoading && _lastInvoices.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (invoicesAsync.hasError && _lastInvoices.isEmpty) {
      return _ErrorCard(
        message: 'Faturalar yüklenemedi.',
        onRetry: () => ref.invalidate(invoicesProvider(_filter)),
      );
    }
    final items = invoicesAsync.hasValue
        ? (invoicesAsync.value ?? const <Invoice>[])
        : _lastInvoices;
    final loadingFilteredItems =
        invoicesAsync.isLoading && _lastInvoices.isNotEmpty;

    final itemIds = items.map((invoice) => invoice.id).toSet();
    _selectedInvoiceIds.removeWhere((id) => !itemIds.contains(id));
    final selectedSendableCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              invoice.canSendEInvoiceTo(isProduction ? 'production' : 'test'),
        )
        .length;
    final selectedMarkableCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              !invoice.isEInvoiceSent &&
              !invoice.isEInvoiceManual &&
              invoice.eInvoiceStatus != 'manual_sent',
        )
        .length;
    final selectedManualCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              invoice.isEInvoiceManual &&
              invoice.eInvoiceEnvironment != 'test',
        )
        .length;
    final bulkManualUndo =
        selectedMarkableCount == 0 && selectedManualCount > 0;
    final bulkManualCount = bulkManualUndo
        ? selectedManualCount
        : selectedMarkableCount;
    final selectedErpPushCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              invoice.isEInvoiceSent &&
              (invoice.eInvoiceEnvironment == null ||
                  invoice.eInvoiceEnvironment == 'production') &&
              (invoice.eInvoiceNumber?.trim().isNotEmpty ?? false),
        )
        .length;
    final selectedSentCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              invoice.canOpenOfficialEInvoicePdf,
        )
        .length;
    final selectedAkinsoftCreateCount = items
        .where(
          (invoice) =>
              _selectedInvoiceIds.contains(invoice.id) &&
              invoice.isActive &&
              invoice.status != 'cancelled' &&
              !invoice.isLinkedToAkinsoft,
        )
        .length;
    // Seçimden bağımsız: listedeki SAP'a henüz gitmemiş tüm faturalar.
    // Tek buton hem yeni kayıt yazar hem de SAP numarası güncellemesi gerekenleri işler.
    final newErpCreateItems = items
        .where(
          (invoice) =>
              invoice.isActive &&
              invoice.status != 'cancelled' &&
              !invoice.isLinkedToAkinsoft &&
              !invoice.needsAkinsoftNumberSync,
        )
        .toList(growable: false);
    final newErpRenumberItems = items
        .where((invoice) => invoice.needsAkinsoftNumberSync)
        .toList(growable: false);
    final newErpSyncCount =
        newErpCreateItems.length + newErpRenumberItems.length;
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
            _Metric(
              'Satış',
              sales.toString(),
              AppPhosphorIcons.invoice,
              AppTheme.metricBlue,
            ),
            _Metric(
              'Alış',
              purchases.toString(),
              AppPhosphorIcons.shoppingCartSimple,
              AppTheme.blueBright,
            ),
            _Metric(
              'Açık Fatura',
              open.toString(),
              AppPhosphorIcons.receipt,
              open > 0 ? AppTheme.metricAmber : AppTheme.metricBlue,
            ),
            _Metric(
              'TL Toplam',
              widget.moneyTry.format(tryTotal),
              AppPhosphorIcons.coins,
              AppTheme.primary,
            ),
            _Metric(
              'USD Toplam',
              usdMoney.format(usdTotal),
              AppPhosphorIcons.bank,
              AppTheme.primaryDark,
            ),
          ],
        ),
        const Gap(8),
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
          onPullErp: _bulkDeleting || _bulkProcessing
              ? null
              : _pullAkinsoftData,
          pullingErp: _pullingAkinsoft,
          onSyncIncoming: _bulkDeleting || _bulkProcessing || _syncingIncoming
              ? null
              : _syncIncomingFromMaliye,
          syncingIncoming: _syncingIncoming,
        ),
        const Gap(8),
        if (newErpSyncCount > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: _bulkDeleting || _bulkProcessing || _pullingAkinsoft
                    ? null
                    : () => _pushNewInvoicesToErp(items),
                icon: const Icon(AppPhosphorIcons.cloudArrowUp, size: 18),
                label: Text('Yeni Faturaları SAP’a Gönder ($newErpSyncCount)'),
              ),
            ),
          ),
        if (items.isEmpty)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Henüz fatura yok. Yeni Fatura veya Fatura Çek ve Güncelle ile başlayın.',
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
                        : const Icon(AppPhosphorIcons.cloudArrowDown, size: 18),
                    label: const Text('Fatura Çek ve Güncelle'),
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
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      if (constraints.maxWidth < 700) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Checkbox(
                                  visualDensity: VisualDensity.compact,
                                  value:
                                      _selectedInvoiceIds.length ==
                                          items.length &&
                                      items.isNotEmpty,
                                  tristate: true,
                                  onChanged: _bulkDeleting
                                      ? null
                                      : (value) {
                                          setState(() {
                                            if (value == true) {
                                              _selectedInvoiceIds
                                                ..clear()
                                                ..addAll(
                                                  items.map((e) => e.id),
                                                );
                                            } else {
                                              _selectedInvoiceIds.clear();
                                            }
                                          });
                                        },
                                ),
                                const Gap(6),
                                Expanded(
                                  child: Text(
                                    _selectedInvoiceIds.isEmpty
                                        ? hasHiddenItems
                                              ? '${visibleItems.length}/${items.length} fatura'
                                              : '${items.length} fatura'
                                        : '${_selectedInvoiceIds.length} seçili',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleSmall,
                                  ),
                                ),
                                TextButton(
                                  onPressed: _bulkDeleting
                                      ? null
                                      : () =>
                                            setState(_selectedInvoiceIds.clear),
                                  child: const Text('Temizle'),
                                ),
                              ],
                            ),
                            const Gap(6),
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: [
                                  OutlinedButton.icon(
                                    onPressed:
                                        _selectedInvoiceIds.isEmpty ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _collectSelected(items),
                                    icon: const Icon(
                                      AppPhosphorIcons.coins,
                                      size: 18,
                                    ),
                                    label: const Text('Tahsilat'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        _selectedInvoiceIds.isEmpty ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _createPaymentLinkSelected(
                                            items,
                                          ),
                                    icon: const Icon(
                                      AppPhosphorIcons.link,
                                      size: 18,
                                    ),
                                    label: const Text('Toplu Ödeme Linki'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        _selectedInvoiceIds.isEmpty ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _exportSelectedStatement(items),
                                    icon: const Icon(
                                      AppPhosphorIcons.receipt,
                                      size: 18,
                                    ),
                                    label: const Text('Toplu Fatura Ekstresi'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        bulkManualCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _bulkMarkManual(
                                            items,
                                            manual: !bulkManualUndo,
                                          ),
                                    icon: Icon(
                                      bulkManualUndo
                                          ? AppPhosphorIcons.arrowUUpLeft
                                          : AppPhosphorIcons.handPalm,
                                      size: 18,
                                    ),
                                    label: Text(
                                      bulkManualUndo ? 'Geri Al' : 'Manuel',
                                    ),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        selectedErpPushCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing ||
                                            _pullingAkinsoft
                                        ? null
                                        : () => _pushSelectedInvoiceNumbers(
                                            items,
                                          ),
                                    icon: const Icon(
                                      AppPhosphorIcons.barcode,
                                      size: 18,
                                    ),
                                    label: const Text('SAP No'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        selectedAkinsoftCreateCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing ||
                                            _pullingAkinsoft
                                        ? null
                                        : () => _pushSelectedInvoicesToAkinsoft(
                                            items,
                                          ),
                                    icon: const Icon(
                                      AppPhosphorIcons.cloudArrowUp,
                                      size: 18,
                                    ),
                                    label: const Text('SAP’a Gönder'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        selectedSentCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _downloadSelectedPdfs(items),
                                    icon: const Icon(
                                      AppPhosphorIcons.fileMagnifyingGlass,
                                      size: 18,
                                    ),
                                    label: const Text('Toplu indir'),
                                  ),
                                  const Gap(8),
                                  OutlinedButton.icon(
                                    onPressed:
                                        selectedSendableCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () =>
                                              _bulkPrepare(items, send: false),
                                    icon: const Icon(
                                      AppPhosphorIcons.bracketsCurly,
                                      size: 18,
                                    ),
                                    label: const Text('Payload'),
                                  ),
                                  const Gap(8),
                                  FilledButton.icon(
                                    onPressed:
                                        selectedSendableCount == 0 ||
                                            _bulkDeleting ||
                                            _bulkProcessing
                                        ? null
                                        : () => _bulkPrepare(items, send: true),
                                    icon: const Icon(
                                      AppPhosphorIcons.cloudArrowUp,
                                      size: 18,
                                    ),
                                    label: const Text('Gönder'),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }
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
                            child: Wrap(
                              alignment: WrapAlignment.end,
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                TextButton(
                                  onPressed: _bulkDeleting
                                      ? null
                                      : () => setState(() {
                                          _selectedInvoiceIds
                                            ..clear()
                                            ..addAll(items.map((e) => e.id));
                                        }),
                                  child: const Text('Tümünü Seç'),
                                ),
                                TextButton(
                                  onPressed: _bulkDeleting
                                      ? null
                                      : () =>
                                            setState(_selectedInvoiceIds.clear),
                                  child: const Text('Temizle'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      _selectedInvoiceIds.isEmpty ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _collectSelected(items),
                                  icon: const Icon(
                                    AppPhosphorIcons.coins,
                                    size: 18,
                                  ),
                                  label: const Text('Tahsilat Yap'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      _selectedInvoiceIds.isEmpty ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _createPaymentLinkSelected(items),
                                  icon: const Icon(
                                    AppPhosphorIcons.link,
                                    size: 18,
                                  ),
                                  label: const Text('Toplu Ödeme Linki'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      bulkManualCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _bulkMarkManual(
                                          items,
                                          manual: !bulkManualUndo,
                                        ),
                                  icon: Icon(
                                    bulkManualUndo
                                        ? AppPhosphorIcons.arrowUUpLeft
                                        : AppPhosphorIcons.handPalm,
                                    size: 18,
                                  ),
                                  label: Text(
                                    bulkManualUndo
                                        ? 'Manuel İşareti Geri Al'
                                        : 'Manuel Kesildi',
                                  ),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      selectedErpPushCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing ||
                                          _pullingAkinsoft
                                      ? null
                                      : () =>
                                            _pushSelectedInvoiceNumbers(items),
                                  icon: const Icon(
                                    AppPhosphorIcons.barcode,
                                    size: 18,
                                  ),
                                  label: const Text('SAP No Güncelle'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      selectedAkinsoftCreateCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing ||
                                          _pullingAkinsoft
                                      ? null
                                      : () => _pushSelectedInvoicesToAkinsoft(
                                          items,
                                        ),
                                  icon: const Icon(
                                    AppPhosphorIcons.cloudArrowUp,
                                    size: 18,
                                  ),
                                  label: const Text('SAP’a Fatura Gönder'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      selectedSentCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _downloadSelectedPdfs(items),
                                  icon: _bulkProcessing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          AppPhosphorIcons.fileMagnifyingGlass,
                                          size: 18,
                                        ),
                                  label: const Text('Toplu PDF'),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed:
                                      _selectedInvoiceIds.isEmpty ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _exportSelectedStatement(items),
                                  icon: const Icon(
                                    AppPhosphorIcons.receipt,
                                    size: 18,
                                  ),
                                  label: const Text('Toplu Fatura Ekstresi'),
                                ),
                                OutlinedButton.icon(
                                  onPressed:
                                      selectedSendableCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _bulkPrepare(items, send: false),
                                  icon: _bulkProcessing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          AppPhosphorIcons.bracketsCurly,
                                          size: 18,
                                        ),
                                  label: const Text('Payload Hazırla'),
                                ),
                                FilledButton.icon(
                                  onPressed:
                                      selectedSendableCount == 0 ||
                                          _bulkDeleting ||
                                          _bulkProcessing
                                      ? null
                                      : () => _bulkPrepare(items, send: true),
                                  icon: _bulkProcessing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          AppPhosphorIcons.cloudArrowUp,
                                          size: 18,
                                        ),
                                  label: Text(apiSendLabel),
                                ),
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
                                          AppPhosphorIcons.trash,
                                          size: 18,
                                        ),
                                  label: const Text('Seçilenleri Sil'),
                                ),
                              ],
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
                          for (var i = 0; i < visibleItems.length; i++)
                            _EInvoiceRow(
                              index: i,
                              invoice: visibleItems[i],
                              selected: _selectedInvoiceIds.contains(
                                visibleItems[i].id,
                              ),
                              onSelectedChanged: _bulkDeleting
                                  ? null
                                  : (selected) {
                                      final id = visibleItems[i].id;
                                      setState(() {
                                        if (selected) {
                                          _selectedInvoiceIds.add(id);
                                        } else {
                                          _selectedInvoiceIds.remove(id);
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
                    final minTableWidth = AppInvoiceTableCols.fixedTotal + 260;
                    final tableWidth = constraints.maxWidth < minTableWidth
                        ? minTableWidth
                        : constraints.maxWidth;
                    return ClipRect(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: tableWidth,
                          child: Column(
                            children: [
                              const _EInvoiceListHeader(),
                              for (var i = 0; i < visibleItems.length; i++)
                                _EInvoiceRow(
                                  index: i,
                                  invoice: visibleItems[i],
                                  selected: _selectedInvoiceIds.contains(
                                    visibleItems[i].id,
                                  ),
                                  onSelectedChanged: _bulkDeleting
                                      ? null
                                      : (selected) {
                                          final id = visibleItems[i].id;
                                          setState(() {
                                            if (selected) {
                                              _selectedInvoiceIds.add(id);
                                            } else {
                                              _selectedInvoiceIds.remove(id);
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

  Future<void> _downloadSelectedPdfs(List<Invoice> visibleInvoices) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .where((invoice) => invoice.canOpenOfficialEInvoicePdf)
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'PDF için Maliye kayıtlı e-fatura seçin. '
            'Alışta orijinal nüsha Maliye sayfasında açılır.',
          ),
        ),
      );
      return;
    }

    final incoming = selected
        .where(
          (invoice) =>
              invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived,
        )
        .toList(growable: false);
    final outbound = selected
        .where((invoice) => invoice.canOpenArchiveEInvoicePdf)
        .toList(growable: false);
    final failures = <String>[];

    // Alış: CRM PDF indirme yok — Maliye /dogrula orijinal nüsha.
    var openedIncoming = 0;
    for (final invoice in incoming) {
      final officialUrl = buildOfficialEInvoiceUrl(
        verificationCode: invoice.eInvoiceUuid,
        environment: invoice.eInvoiceEnvironment ?? 'test',
      );
      if (officialUrl == null) {
        failures.add('${invoice.invoiceNumber}: doğrulama kodu yok');
        continue;
      }
      if (await openExternalUrl(officialUrl)) {
        openedIncoming += 1;
      }
    }

    if (outbound.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            openedIncoming > 0
                ? '$openedIncoming alış faturası Maliye orijinal nüshasında açıldı.'
                : (failures.isEmpty
                      ? 'İndirilecek satış e-faturası yok.'
                      : failures.join('\n')),
          ),
        ),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    setState(() => _bulkProcessing = true);
    final downloads = <EInvoicePdfDownload>[];
    try {
      for (final invoice in outbound) {
        try {
          final archive = await apiClient.postJson(
            '/e-invoice',
            body: _archivePdfRequestBody(invoice.id),
          );
          if (archive['officialOnly'] == true) {
            final officialUrl =
                archive['officialUrl']?.toString().trim() ?? '';
            if (officialUrl.isNotEmpty) {
              await openExternalUrl(officialUrl);
            }
            continue;
          }
          final pdfUrl = archive['pdfUrl']?.toString().trim() ?? '';
          final pdfBase64 = archive['pdfBase64']?.toString().trim() ?? '';
          if (pdfUrl.isEmpty && pdfBase64.isEmpty) {
            failures.add(
              '${invoice.invoiceNumber}: '
              '${_friendlyPdfError(archive['error'] ?? 'PDF bağlantısı yok.')}',
            );
            continue;
          }
          final number = (invoice.eInvoiceNumber?.trim().isNotEmpty ?? false)
              ? _localEInvoiceNumber(invoice.eInvoiceNumber!)
              : invoice.invoiceNumber.trim();
          final customer = (invoice.customerName ?? '').trim();
          final localPath = archive['localPdfPath']?.toString().trim();
          downloads.add(
            EInvoicePdfDownload(
              url: pdfUrl,
              fileName: customer.isEmpty
                  ? '$number.pdf'
                  : '${customer}_$number.pdf',
              localPath: (localPath != null && localPath.isNotEmpty)
                  ? localPath
                  : null,
              pdfBase64: pdfBase64.isNotEmpty ? pdfBase64 : null,
            ),
          );
        } catch (error) {
          failures.add('${invoice.invoiceNumber}: ${_friendlyPdfError(error)}');
        }
      }

      if (downloads.isEmpty) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              failures.isEmpty
                  ? (incoming.isEmpty
                        ? 'PDF oluşturulamadı.'
                        : 'Alış faturaları Maliye’de açıldı; satış PDF’i yok.')
                  : failures.join('\n'),
            ),
          ),
        );
        return;
      }

      final downloaded = await downloadEInvoicePdfs(files: downloads);
      if (!downloaded) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PDF indirme başarısız; dosyalar tek tek açılıyor.'),
          ),
        );
        for (final item in downloads) {
          if (item.url.trim().isNotEmpty) {
            await openExternalUrl(item.url);
          }
        }
      }

      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            !downloaded
                ? 'İndirme başarısız; ${downloads.length} PDF ayrı açıldı'
                      '${failures.isEmpty ? '.' : ', ${failures.length} atlandı.'}'
                : failures.isEmpty
                ? '${downloads.length} PDF dosya olarak indirildi'
                      '${incoming.isEmpty ? '.' : '; ${incoming.length} alış Maliye’de açıldı.'}'
                : '${downloads.length} PDF indirildi, ${failures.length} fatura atlandı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Toplu indir başarısız: ${_friendlyPdfError(error)}'),
        ),
      );
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _pushSelectedInvoicesToAkinsoft(
    List<Invoice> visibleInvoices, {
    List<Invoice>? forceSelected,
  }) async {
    final selected =
        (forceSelected ??
                visibleInvoices
                    .where(
                      (invoice) => _selectedInvoiceIds.contains(invoice.id),
                    )
                    .toList())
            .where(
              (invoice) =>
                  invoice.isActive &&
                  invoice.status != 'cancelled' &&
                  !invoice.isLinkedToAkinsoft,
            )
            .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SAP’a gönderilecek CRM faturası seçilmedi '
            '(zaten eşleşmiş veya pasif/iptal olanlar atlanır).',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SAP’a fatura gönder'),
        content: Text(
          '${selected.length} fatura SAP’a yeni kayıt olarak yazılsın mı?\n\n'
          '• Cari yoksa SAP’a otomatik eklenir\n'
          '• Stok eşleşmezse kalem açıklama olarak yazılır\n\n'
          'Örnek: ${selected.first.invoiceNumber}',
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
    );
    if (confirmed != true) return;

    setState(() => _bulkProcessing = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final response = await http
          .post(
            _akinsoftUri('push-invoices'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              ...settings,
              'invoiceIds': selected.map((invoice) => invoice.id).toList(),
            }),
          )
          .timeout(const Duration(minutes: 15));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('Beklenmeyen SAP yanıtı.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded['error'] ?? 'SAP gönderimi başarısız.');
      }
      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      final success = decoded['success'] ?? 0;
      final failed = decoded['failed'] ?? 0;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SAP’a Gönderim'),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * 0.5,
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
                        const JsonEncoder.withIndent('  ').convert(decoded),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_akinsoftBridgeError(error))));
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _pushSelectedInvoiceNumbers(
    List<Invoice> visibleInvoices,
  ) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .where((invoice) => invoice.isEInvoiceSent)
        .where(
          (invoice) =>
              invoice.eInvoiceEnvironment == null ||
              invoice.eInvoiceEnvironment == 'production',
        )
        .where((invoice) => invoice.eInvoiceNumber?.trim().isNotEmpty ?? false)
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SAP’a aktarılacak canlı gönderilmiş e-fatura seçilmedi.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SAP fatura no güncelle'),
        content: Text(
          '${selected.length} faturanın CRM ve SAP fatura numarası '
          'Maliye e-fatura numarasına güncellensin mi?\n\n'
          'SAP’ta kaydı olmayanlar Maliye numarasıyla yeni oluşturulur.\n\n'
          'Örnek: SF03393 → ${_localEInvoiceNumber(selected.first.eInvoiceNumber!)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Güncelle'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _bulkProcessing = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final response = await http
          .post(
            _akinsoftUri('push-invoice-numbers'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              ...settings,
              'invoiceIds': selected.map((invoice) => invoice.id).toList(),
            }),
          )
          .timeout(const Duration(minutes: 15));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('Beklenmeyen SAP yanıtı.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded['error'] ?? 'SAP güncelleme başarısız.');
      }
      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      final success = decoded['success'] ?? 0;
      final failed = decoded['failed'] ?? 0;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('SAP No Güncelleme'),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * 0.5,
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
                        const JsonEncoder.withIndent('  ').convert(decoded),
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
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Tamam'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_akinsoftBridgeError(error))));
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  /// Tek buton: listedeki (seçimden bağımsız) SAP'a gitmemiş tüm faturaları
  /// işler. Yeni olanları SAP'a kayıt olarak yazar, SAP numarası güncellenmesi
  /// gerekenleri günceller. İki iş de tek akışta yapılır.
  Future<void> _pushNewInvoicesToErp(List<Invoice> items) async {
    final createList = items
        .where(
          (invoice) =>
              invoice.isActive &&
              invoice.status != 'cancelled' &&
              !invoice.isLinkedToAkinsoft &&
              !invoice.needsAkinsoftNumberSync,
        )
        .toList(growable: false);
    final renumberList = items
        .where((invoice) => invoice.needsAkinsoftNumberSync)
        .toList(growable: false);
    if (createList.isEmpty && renumberList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'SAP’a gönderilecek yeni fatura yok (hepsi zaten aktarılmış).',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni faturaları SAP’a gönder'),
        content: Text(
          [
            if (createList.isNotEmpty)
              '• ${createList.length} yeni fatura SAP’a yeni kayıt olarak yazılacak',
            if (renumberList.isNotEmpty)
              '• ${renumberList.length} faturanın SAP numarası güncellenecek',
            '',
            'Seçim yapmanıza gerek yok; listedeki tüm uygun faturalar işlenir.',
          ].join('\n'),
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
    );
    if (confirmed != true) return;

    setState(() => _bulkProcessing = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      var totalSuccess = 0;
      var totalFailed = 0;
      final results = <String, dynamic>{};

      Future<void> runPush(String path, List<Invoice> list, String key) async {
        if (list.isEmpty) return;
        final response = await http
            .post(
              _akinsoftUri(path),
              headers: {'Content-Type': 'application/json; charset=utf-8'},
              body: jsonEncode({
                ...settings,
                'invoiceIds': list.map((invoice) => invoice.id).toList(),
              }),
            )
            .timeout(const Duration(minutes: 15));
        final decoded = jsonDecode(response.body);
        if (decoded is! Map) {
          throw Exception('Beklenmeyen SAP yanıtı.');
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw Exception(decoded['error'] ?? 'SAP gönderimi başarısız.');
        }
        totalSuccess += (decoded['success'] as num?)?.toInt() ?? 0;
        totalFailed += (decoded['failed'] as num?)?.toInt() ?? 0;
        results[key] = decoded;
      }

      await runPush('push-invoices', createList, 'yeni_kayit');
      await runPush('push-invoice-numbers', renumberList, 'no_guncelleme');

      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Yeni Faturaları SAP’a Gönder'),
          content: SizedBox(
            width: 640,
            height: MediaQuery.sizeOf(context).height * 0.5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Başarılı: $totalSuccess • Hatalı: $totalFailed'),
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
                        const JsonEncoder.withIndent('  ').convert(results),
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
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_akinsoftBridgeError(error))));
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _bulkMarkManual(
    List<Invoice> visibleInvoices, {
    required bool manual,
  }) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .where((invoice) => !invoice.isEInvoiceSent)
        .where((invoice) => invoice.eInvoiceStatus != 'manual_sent')
        .where(
          (invoice) => manual
              ? !invoice.isEInvoiceManual
              : invoice.isEInvoiceManual &&
                    invoice.eInvoiceEnvironment != 'test',
        )
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            manual
                ? 'İşaretlenecek uygun fatura yok. Maliye’ye gönderilmiş faturalar manuel yapılamaz.'
                : 'Geri alınacak manuel fatura seçilmedi.',
          ),
        ),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(manual ? 'Manuel Kesildi' : 'Manuel işareti geri al'),
        content: Text(
          manual
              ? '${selected.length} fatura başka sistemden kesilmiş olarak işaretlensin mi? Bu faturalar Maliye API’sine gönderilmez.'
              : '${selected.length} faturanın manuel kesildi işareti geri alınsın mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(manual ? 'İşaretle' : 'Geri al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final ids = selected.map((invoice) => invoice.id).toList(growable: false);
    setState(() => _bulkProcessing = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'in', 'value': ids},
          ],
          'values': {'e_invoice_status': manual ? 'manual' : 'not_sent'},
        },
      );
      _selectedInvoiceIds.clear();
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            manual
                ? '${ids.length} fatura Manuel Kesildi olarak işaretlendi.'
                : '${ids.length} faturanın manuel işareti geri alındı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manuel işaretleme başarısız: $error')),
      );
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _exportSelectedStatement(List<Invoice> visibleInvoices) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .toList(growable: false);
    if (selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ekstre için en az bir fatura seçin.')),
      );
      return;
    }

    final customerNames = selected
        .map((invoice) => invoice.customerName?.trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toSet();
    final customerName = customerNames.length == 1
        ? customerNames.first
        : 'Seçili Faturalar';
    final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
    final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
    setState(() => _bulkProcessing = true);
    try {
      await shareInvoiceStatementPdf(
        title: 'Fatura Ekstresi',
        customerName: customerName,
        invoices: selected,
        bankDetails: (settings['seller_bank_details'] ?? '').toString(),
        filename:
            'fatura_ekstresi_${safeStatementFilePart(customerName)}_$stamp.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ekstre oluşturulamadı: $error')));
    } finally {
      if (mounted) setState(() => _bulkProcessing = false);
    }
  }

  Future<void> _createPaymentLinkSelected(List<Invoice> visibleInvoices) async {
    final selected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .toList(growable: false);
    await _createInvoicePaymentLinkFlow(
      context: context,
      ref: ref,
      invoices: selected,
    );
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
    final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
    final isProduction =
        (settings['environment'] ?? 'test').toString() == 'production';
    final allSelected = visibleInvoices
        .where((invoice) => _selectedInvoiceIds.contains(invoice.id))
        .toList(growable: false);
    final selected = send
        ? allSelected
              .where(
                (invoice) => invoice.canSendEInvoiceTo(
                  isProduction ? 'production' : 'test',
                ),
              )
              .toList(growable: false)
        : allSelected;
    final skippedManual = send
        ? allSelected
              .where(
                (invoice) =>
                    invoice.isEInvoiceManual ||
                    invoice.eInvoiceStatus == 'manual_sent',
              )
              .length
        : 0;
    final skippedSent = send
        ? allSelected.length - selected.length - skippedManual
        : allSelected.length - selected.length;
    if (selected.isEmpty) {
      if (!send) return;
      final parts = <String>[];
      if (skippedManual > 0) {
        parts.add('$skippedManual manuel kesildi');
      }
      if (skippedSent > 0) {
        parts.add('$skippedSent daha önce gönderilmiş');
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            parts.isEmpty
                ? 'Gönderilecek fatura seçilmedi.'
                : 'Gönderilecek uygun fatura yok (${parts.join(', ')}).',
          ),
        ),
      );
      return;
    }

    final confirmed = send
        ? await showDialog<bool>(
            context: context,
            builder: (context) => AlertDialog(
              title: Text(
                isProduction ? 'Canlı API’ye gönder' : 'Test API’ye gönder',
              ),
              content: Text(
                isProduction
                    ? '${selected.length} fatura canlı (production) Maliye API’sine gönderilecek.\n\n'
                          'Bu işlem geri alınamaz. Devam edilsin mi?'
                          '${skippedSent > 0 ? '\n\nDaha önce gönderilmiş $skippedSent fatura atlanacak.' : ''}'
                          '${skippedManual > 0 ? '\n\nManuel işaretli $skippedManual fatura atlanacak (API’ye gönderilmez).' : ''}'
                    : '${selected.length} fatura için payload hazırlanıp test API’ye gönderilsin mi?'
                          '${skippedSent > 0 ? '\n\nDaha önce gönderilmiş $skippedSent fatura atlanacak.' : ''}'
                          '${skippedManual > 0 ? '\n\nManuel işaretli $skippedManual fatura atlanacak (API’ye gönderilmez).' : ''}',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(isProduction ? 'Canlıya Gönder' : 'Gönder'),
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
                if (skippedSent > 0)
                  Text('Atlanan (önceden gönderilmiş): $skippedSent'),
                if (skippedManual > 0)
                  Text('Atlanan (manuel kesildi): $skippedManual'),
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

  Future<void> _syncIncomingFromMaliye() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Maliye’den gelenleri al'),
        content: const Text(
          'Tedarikçilerin size kestiği e-faturalar Maliye’den çekilip Alış faturalarına eklenecek.\n\n'
          'Not: KKTC Maliye API’sinde kabul/ret işlemi yoktur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Al'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _syncingIncoming = true);
    try {
      final response = await apiClient.postJson(
        '/e-invoice',
        body: {'action': 'sync_incoming'},
      );
      if (!mounted) return;
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      final created = response['created'] ?? 0;
      final updated = response['updated'] ?? 0;
      final fetched = response['fetched'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Maliye: $fetched kayıt · $created yeni · $updated güncellendi',
          ),
        ),
      );
      setState(() {
        _filter = _filter.copyWith(invoiceType: 'purchase');
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Gelen faturalar alınamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _syncingIncoming = false);
    }
  }

  Future<void> _pullAkinsoftData() async {
    setState(() => _pullingAkinsoft = true);
    final startedAt = DateTime.now();
    var stageLabel = 'SAP faturaları çekiliyor';
    var current = 0;
    var total = 1;
    var percent = 0;
    var elapsedText = '00:00';
    String? invoiceNumber;
    StateSetter? setDialogState;
    var dialogVisible = false;
    Timer? tick;

    void refreshElapsed() {
      elapsedText = _formatJobElapsed(DateTime.now().difference(startedAt));
      setDialogState?.call(() {});
    }

    try {
      if (mounted) {
        dialogVisible = true;
        // ignore: unawaited_futures
        showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) {
            return StatefulBuilder(
              builder: (context, setLocal) {
                setDialogState = setLocal;
                final progress = total <= 0
                    ? null
                    : (current / total).clamp(0.0, 1.0);
                return AlertDialog(
                  title: const Text('Fatura Çek ve Güncelle'),
                  content: SizedBox(
                    width: 420,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          total > 1
                              ? '$stageLabel: $current / $total (%$percent)'
                              : stageLabel,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        const Gap(12),
                        LinearProgressIndicator(value: progress),
                        const Gap(12),
                        Text(
                          [
                            'Geçen süre: $elapsedText',
                            if ((invoiceNumber ?? '').isNotEmpty)
                              'Aktif fatura: $invoiceNumber',
                          ].join(' • '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const Gap(8),
                        Text(
                          'Lütfen bu pencereyi kapatmayın.',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textSoft),
                        ),
                      ],
                    ),
                  ),
                );
              },
            );
          },
        );
        tick = Timer.periodic(const Duration(milliseconds: 250), (_) {
          if (!mounted || !dialogVisible) return;
          refreshElapsed();
        });
      }

      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final payload = {...settings, 'limit': 2000};
      final startResponse = await http
          .post(
            _akinsoftUri('pull-and-update'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 30));
      final started = jsonDecode(startResponse.body);
      if (started is! Map || started['ok'] != true) {
        throw Exception(
          started is Map ? started['error'] : 'Fatura çekme başlatılamadı.',
        );
      }
      final jobId = started['jobId']?.toString() ?? '';
      if (jobId.isEmpty) {
        throw Exception('Fatura çekme iş numarası alınamadı.');
      }

      Map<String, dynamic> summary = const {};
      Map<String, dynamic>? result;
      while (true) {
        await Future<void>.delayed(const Duration(milliseconds: 400));
        final statusResponse = await http
            .get(_akinsoftUri('pull-and-update', {'id': jobId}))
            .timeout(const Duration(seconds: 15));
        final statusDecoded = jsonDecode(statusResponse.body);
        if (statusDecoded is! Map || statusDecoded['ok'] != true) {
          throw Exception(
            statusDecoded is Map
                ? statusDecoded['error']
                : 'Fatura çekme durumu alınamadı.',
          );
        }
        final job =
            (statusDecoded['job'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        if (mounted && dialogVisible) {
          setDialogState?.call(() {
            current = (job['current'] as num?)?.toInt() ?? current;
            total = (job['total'] as num?)?.toInt() ?? total;
            percent = (job['percent'] as num?)?.toInt() ?? percent;
            stageLabel = job['stageLabel']?.toString() ?? stageLabel;
            invoiceNumber = job['currentInvoiceNumber']?.toString();
            elapsedText = _formatJobElapsed(
              DateTime.now().difference(startedAt),
            );
          });
        }
        final status = job['status']?.toString();
        if (status == 'done') {
          summary =
              (job['summary'] as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{};
          result = (job['result'] as Map?)?.cast<String, dynamic>();
          break;
        }
        if (status == 'error') {
          throw Exception(job['error'] ?? 'Fatura çekme başarısız.');
        }
      }

      final elapsed = DateTime.now().difference(startedAt);
      ref.invalidate(invoicesProvider);
      ref.invalidate(customersProvider);
      ref.invalidate(productsProvider(null));
      ref.invalidate(accountBalancesProvider);
      ref.invalidate(eInvoiceSettingsProvider);
      if (!mounted) return;

      if (dialogVisible &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }

      final pulled = summary['pulled'] ?? 0;
      final created = summary['created'] ?? 0;
      final updated = summary['updated'] ?? 0;
      final failed = summary['failed'] ?? 0;
      final needReview = summary['needReview'] ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fatura çekildi ve güncellendi: çekilen $pulled, '
            'yeni $created, güncellenen $updated, hata $failed'
            '${needReview is num && needReview > 0 ? ', eşleşme bekleyen $needReview' : ''}'
            ' · ${_formatJobElapsedShort(elapsed)}.',
          ),
        ),
      );

      final needReviewInvoices =
          ((result?['needReviewInvoices'] as List?) ?? const [])
              .whereType<Map>()
              .toList();
      if (needReviewInvoices.isNotEmpty && result != null) {
        final dialogData = Map<String, dynamic>.from(result);
        dialogData['invoices'] = needReviewInvoices;
        dialogData['_settingsPayload'] = payload;
        await showDialog<void>(
          context: context,
          builder: (context) => _AkinsoftPullDialog(data: dialogData),
        );
        ref.invalidate(invoicesProvider);
        ref.invalidate(customersProvider);
      }
    } catch (error) {
      if (mounted &&
          dialogVisible &&
          Navigator.of(context, rootNavigator: true).canPop()) {
        Navigator.of(context, rootNavigator: true).pop();
        dialogVisible = false;
      }
      if (!mounted) return;
      final message = error is TimeoutException
          ? 'İşlem beklenenden uzun sürdü. Sunucuda devam etmiş olabilir; Yenile ile kontrol edin.'
          : 'SAP fatura çek/güncelle başarısız: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      tick?.cancel();
      if (mounted) setState(() => _pullingAkinsoft = false);
    }
  }
}

class _EInvoiceListHeader extends StatelessWidget {
  const _EInvoiceListHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: AppDenseList.headerH,
      padding: const EdgeInsets.symmetric(horizontal: AppDenseList.rowH),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withValues(alpha: 0.9),
        border: Border(bottom: AppDenseList.hairline),
      ),
      child: const Row(
        children: [
          SizedBox(width: AppInvoiceTableCols.check),
          Expanded(child: _InvoiceHeaderText('Cari / Fatura')),
          SizedBox(
            width: AppInvoiceTableCols.date,
            child: _InvoiceHeaderText('Tarih'),
          ),
          SizedBox(
            width: AppInvoiceTableCols.type,
            child: _InvoiceHeaderText('Tür'),
          ),
          SizedBox(
            width: AppInvoiceTableCols.status,
            child: _InvoiceHeaderText('Durum'),
          ),
          SizedBox(
            width: AppInvoiceTableCols.amount,
            child: _InvoiceHeaderText('KDV Dahil', alignEnd: true),
          ),
          SizedBox(
            width: AppInvoiceTableCols.actions,
            child: _InvoiceHeaderText('İşlemler', alignEnd: true),
          ),
        ],
      ),
    );
  }
}

class _DuotoneFilterIcon extends StatelessWidget {
  const _DuotoneFilterIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 44,
      child: Center(
        child: Container(
          width: 29,
          height: 29,
          decoration: AppTheme.categoryIconWell(
            color,
            radius: AppTheme.radiusXs,
          ),
          child: AppPhosphorIcon(
            icon,
            size: 16,
            color: AppTheme.categoryIconFg(color),
          ),
        ),
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
    required this.onPullErp,
    required this.pullingErp,
    required this.onSyncIncoming,
    required this.syncingIncoming,
  });

  final InvoiceFilter filter;
  final AsyncValue<List<Customer>> customersAsync;
  final ValueChanged<InvoiceFilter> onChanged;
  final VoidCallback onRefresh;
  final VoidCallback? onPullErp;
  final bool pullingErp;
  final VoidCallback? onSyncIncoming;
  final bool syncingIncoming;

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
      color: Color.alphaBlend(
        AppTheme.primary.withValues(alpha: 0.025),
        AppTheme.surface,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Keep the desktop-style compact filter row on tablet/web widths.
          // The former 1050px breakpoint turned most desktop side-panel views
          // into a very tall mobile form and pushed the invoice list off-screen.
          final compact = constraints.maxWidth < 600;
          final activeChips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                ('active', 'Aktif'),
                ('passive', 'Pasif'),
                ('all', 'Tümü'),
              ])
                FilterChip(
                  label: Text(option.$2),
                  selected: filter.activeFilter == option.$1,
                  onSelected: (_) {
                    onChanged(
                      filter.copyWith(
                        activeFilter: option.$1,
                        clearStatus: option.$1 == 'passive',
                      ),
                    );
                  },
                ),
            ],
          );
          final typeChips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                ('', 'Tümü'),
                ('sales', 'Satış'),
                ('purchase', 'Alış'),
              ])
                FilterChip(
                  label: Text(option.$2),
                  selected: (filter.invoiceType ?? '') == option.$1,
                  onSelected: (_) {
                    onChanged(
                      filter.copyWith(
                        invoiceType: option.$1.isEmpty ? null : option.$1,
                        clearInvoiceType: option.$1.isEmpty,
                      ),
                    );
                  },
                ),
            ],
          );
          final eInvoiceChips = Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in const [
                ('', 'E-Fatura: Tümü'),
                ('not_sent', 'Gönderilmedi'),
                ('received', 'Maliye’den gelen'),
                ('sent', 'Gönderildi'),
                ('manual_sent', 'Manuel Gönderildi'),
                ('manual', 'Manuel Kesildi'),
              ])
                FilterChip(
                  label: Text(option.$2),
                  selected: (filter.eInvoiceStatus ?? '') == option.$1,
                  onSelected: (_) {
                    onChanged(
                      filter.copyWith(
                        eInvoiceStatus: option.$1.isEmpty ? null : option.$1,
                        clearEInvoiceStatus: option.$1.isEmpty,
                      ),
                    );
                  },
                ),
            ],
          );
          final fields = <Widget>[
            if (compact) ...[
              SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Aktiflik',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(6),
                    activeChips,
                    const Gap(12),
                    Text(
                      'Tür',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(6),
                    typeChips,
                    const Gap(12),
                    Text(
                      'E-Fatura',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: AppTheme.textSoft,
                      ),
                    ),
                    const Gap(6),
                    eInvoiceChips,
                  ],
                ),
              ),
            ],
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
            if (!compact)
              SizedBox(
                width: 150,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('type-${filter.invoiceType ?? ''}'),
                  initialValue: filter.invoiceType ?? '',
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text('Tür: Tümü', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'sales',
                      child: Text('Satış', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'purchase',
                      child: Text('Alış', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (value) => onChanged(
                    filter.copyWith(
                      invoiceType: (value ?? '').isEmpty ? null : value,
                      clearInvoiceType: (value ?? '').isEmpty,
                    ),
                  ),
                  decoration: InputDecoration(
                    prefixIcon: _DuotoneFilterIcon(
                      icon: AppPhosphorIcons.arrowsLeftRight,
                      color: AppTheme.blueBright,
                    ),
                    labelText: 'Satış / Alış',
                  ),
                ),
              ),
            if (!compact)
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('active-${filter.activeFilter}'),
                  initialValue: filter.activeFilter,
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: 'active',
                      child: Text('Aktif', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'passive',
                      child: Text('Pasif', overflow: TextOverflow.ellipsis),
                    ),
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Tümü', overflow: TextOverflow.ellipsis),
                    ),
                  ],
                  onChanged: (value) {
                    final next = (value ?? 'active').trim();
                    onChanged(
                      filter.copyWith(
                        activeFilter: next,
                        clearStatus: next == 'passive',
                      ),
                    );
                  },
                  decoration: InputDecoration(
                    prefixIcon: _DuotoneFilterIcon(
                      icon: AppPhosphorIcons.toggleRight,
                      color: AppTheme.success,
                    ),
                    labelText: 'Aktiflik',
                  ),
                ),
              ),
            SizedBox(
              width: compact ? double.infinity : 190,
              child: DropdownButtonFormField<String>(
                key: ValueKey('status-${filter.status ?? ''}'),
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
                    child: Text('Ödendi', overflow: TextOverflow.ellipsis),
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
                  filter.copyWith(
                    status: (value ?? '').isEmpty ? null : value,
                    clearStatus: (value ?? '').isEmpty,
                  ),
                ),
                decoration: InputDecoration(
                  prefixIcon: _DuotoneFilterIcon(
                    icon: AppPhosphorIcons.trafficSignal,
                    color: AppTheme.purple,
                  ),
                  labelText: 'Açık / Kapalı',
                ),
              ),
            ),
            if (!compact)
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<String>(
                  key: ValueKey('einv-${filter.eInvoiceStatus ?? ''}'),
                  initialValue: filter.eInvoiceStatus ?? '',
                  isExpanded: true,
                  items: const [
                    DropdownMenuItem(
                      value: '',
                      child: Text(
                        'E-Fatura: Tümü',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'received',
                      child: Text(
                        'Maliye’den gelenler',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'sent',
                      child: Text(
                        'Gönderilenler',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'manual_sent',
                      child: Text(
                        'Manuel gönderilenler',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'manual',
                      child: Text(
                        'Manuel kesilenler',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    DropdownMenuItem(
                      value: 'not_sent',
                      child: Text(
                        'Gönderilmeyenler',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                  onChanged: (value) => onChanged(
                    filter.copyWith(
                      eInvoiceStatus: (value ?? '').isEmpty ? null : value,
                      clearEInvoiceStatus: (value ?? '').isEmpty,
                    ),
                  ),
                  decoration: InputDecoration(
                    prefixIcon: _DuotoneFilterIcon(
                      icon: AppPhosphorIcons.rocket,
                      color: AppTheme.primary,
                    ),
                    labelText: 'E-Fatura Gönderimi',
                  ),
                ),
              ),
            SizedBox(
              width: compact ? double.infinity : 170,
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(context, isStart: true),
                icon: const Icon(AppPhosphorIcons.calendarCheck, size: 18),
                label: Text(startLabel),
              ),
            ),
            SizedBox(
              width: compact ? double.infinity : 170,
              child: OutlinedButton.icon(
                onPressed: () => _pickDate(context, isStart: false),
                icon: const Icon(AppPhosphorIcons.calendarX, size: 18),
                label: Text(endLabel),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(
                AppPhosphorIcons.arrowsCounterClockwise,
                size: 18,
              ),
              label: const Text('Yenile'),
            ),
            TextButton.icon(
              onPressed: () => onChanged(const InvoiceFilter(status: 'open')),
              icon: const Icon(AppPhosphorIcons.broom, size: 18),
              label: const Text('Temizle'),
            ),
          ];
          final incomingButton = FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.softTint(AppTheme.warning, alpha: 0.16),
              foregroundColor: AppTheme.softFg(AppTheme.warning),
              iconColor: AppTheme.softFg(AppTheme.warning),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
            ),
            onPressed: syncingIncoming ? null : onSyncIncoming,
            icon: syncingIncoming
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppPhosphorIcons.arrowDownLeft, size: 18),
            label: Text(
              syncingIncoming
                  ? 'Gelenler alınıyor…'
                  : 'Maliye’den gelenleri al',
            ),
          );
          final pullButton = FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.softTint(AppTheme.primary, alpha: 0.14),
              foregroundColor: AppTheme.softFg(AppTheme.primary),
              iconColor: AppTheme.softFg(AppTheme.primary),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              ),
            ),
            onPressed: pullingErp ? null : onPullErp,
            icon: pullingErp
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppPhosphorIcons.cloudArrowDown, size: 18),
            label: Text(
              pullingErp
                  ? 'Çekiliyor ve güncelleniyor…'
                  : 'Fatura Çek ve Güncelle',
            ),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (compact) ...[
                incomingButton,
                const Gap(8),
                pullButton,
              ] else
                Row(
                  children: [
                    incomingButton,
                    const Gap(8),
                    pullButton,
                    const Gap(12),
                    Expanded(
                      child: Text(
                        'Gelen e-faturaları Maliye’den alır; SAP butonu ERP faturalarını çeker.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textSoft,
                        ),
                      ),
                    ),
                  ],
                ),
              const Gap(12),
              Wrap(spacing: 10, runSpacing: 10, children: fields),
            ],
          );
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
      filter.copyWith(
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
          icon: const Icon(AppPhosphorIcons.caretDown, size: 18),
          label: Text('Daha fazla göster ($visible / $total)'),
        ),
      ),
    );
  }
}

class _CustomerFilterButton extends StatefulWidget {
  const _CustomerFilterButton({
    required this.customers,
    required this.selectedCustomerId,
    required this.onSelected,
  });

  final List<Customer> customers;
  final String? selectedCustomerId;
  final ValueChanged<String?> onSelected;

  @override
  State<_CustomerFilterButton> createState() => _CustomerFilterButtonState();
}

class _CustomerFilterButtonState extends State<_CustomerFilterButton> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: _selectedName());
    _focusNode = FocusNode();
    _focusNode.addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant _CustomerFilterButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCustomerId != widget.selectedCustomerId ||
        oldWidget.customers != widget.customers) {
      final next = _selectedName();
      if (_controller.text != next && !_focusNode.hasFocus) {
        _controller.value = TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: next.length),
        );
      }
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChange() {
    if (!_focusNode.hasFocus) {
      final selected = _selectedName();
      if (_controller.text != selected) {
        _controller.value = TextEditingValue(
          text: selected,
          selection: TextSelection.collapsed(offset: selected.length),
        );
      }
      return;
    }
    if (_controller.text.isEmpty) return;
    _controller.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _controller.text.length,
    );
  }

  String _selectedName() {
    final id = widget.selectedCustomerId;
    if (id == null || id.isEmpty) return '';
    for (final customer in widget.customers) {
      if (customer.id == id) return customer.name;
    }
    return '';
  }

  Iterable<Customer> _optionsFor(String rawQuery) {
    final query = rawQuery.trim();
    if (query.isEmpty) {
      return widget.customers.take(40);
    }
    return widget.customers
        .where(
          (customer) => matchesSearchQuery(
            [
              customer.name,
              customer.vkn ?? '',
              customer.tcknMs ?? '',
              customer.city ?? '',
              customer.phone1 ?? '',
            ].join(' '),
            query,
          ),
        )
        .take(100);
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection =
        widget.selectedCustomerId != null &&
        widget.selectedCustomerId!.isNotEmpty;

    return RawAutocomplete<Customer>(
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (customer) => customer.name,
      optionsBuilder: (value) => _optionsFor(value.text),
      onSelected: (customer) => widget.onSelected(customer.id),
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          onSubmitted: (_) => onFieldSubmitted(),
          onChanged: (value) {
            if (value.trim().isEmpty && hasSelection) {
              widget.onSelected(null);
            }
          },
          decoration: InputDecoration(
            prefixIcon: const Icon(AppPhosphorIcons.userFocus),
            labelText: 'Cari',
            hintText: hasSelection ? null : 'Ad, VKN, telefon veya şehir ara',
            suffixIcon: hasSelection
                ? IconButton(
                    tooltip: 'Tüm cariler',
                    onPressed: () {
                      controller.clear();
                      widget.onSelected(null);
                      focusNode.requestFocus();
                    },
                    icon: const Icon(AppPhosphorIcons.x),
                  )
                : const Icon(AppPhosphorIcons.magnifyingGlass),
          ),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        final items = options.toList(growable: false);
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 360),
              child: items.isEmpty
                  ? const ListTile(dense: true, title: Text('Cari bulunamadı.'))
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      shrinkWrap: true,
                      itemCount: items.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final customer = items[index];
                        final selected =
                            customer.id == widget.selectedCustomerId;
                        return ListTile(
                          dense: true,
                          selected: selected,
                          leading: CircleAvatar(
                            radius: 16,
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
                              ? const Icon(AppPhosphorIcons.checkCircle)
                              : null,
                          onTap: () => onSelected(customer),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }
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

String _localEInvoiceNumber(String value) {
  return value.trim().replaceFirst(RegExp(r'^\d{9}-'), '');
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
    this.index = 0,
  });

  final Invoice invoice;
  final bool selected;
  final ValueChanged<bool>? onSelectedChanged;
  final int index;

  @override
  ConsumerState<_EInvoiceRow> createState() => _EInvoiceRowState();
}

class _EInvoiceRowState extends ConsumerState<_EInvoiceRow> {
  bool _busy = false;

  List<Widget> _buildInvoiceActions({
    required String sendTooltip,
    required bool canSend,
    required bool showSendAction,
    bool withGaps = false,
    bool mobile = false,
  }) {
    final invoice = widget.invoice;
    final alreadySent =
        invoice.isEInvoiceSent || invoice.eInvoiceStatus == 'manual_sent';
    final canOpenOfficialPdf = invoice.canOpenOfficialEInvoicePdf;
    final isManual = invoice.isEInvoiceManual;
    final isManualSent = invoice.eInvoiceStatus == 'manual_sent';
    final canMarkManualSent =
        isManualSent ||
        (invoice.eInvoiceStatus == 'sent' &&
            invoice.eInvoiceEnvironment == 'test');

    // Compact rows scroll horizontally, so actions can keep clear labels.
    if (mobile) {
      final canPaymentLink = invoice.invoiceType == 'sales' &&
          invoice.isActive &&
          invoice.isOpen &&
          invoice.remainingAmount > 0;
      final actions = <Widget>[
        if (canPaymentLink)
          _InvoiceIconAction(
            tooltip: 'Ödeme linki gönder',
            icon: AppPhosphorIcons.link,
            tone: _InvoiceActionTone.primary,
            onPressed: _busy ? null : _sendPaymentLink,
          ),
        if (showSendAction)
          _InvoiceIconAction(
            tooltip: sendTooltip,
            icon: _busy ? Icons.schedule_rounded : Icons.send_rounded,
            tone: _InvoiceActionTone.primary,
            onPressed: _busy || !canSend ? null : () => _prepare(send: true),
          ),
        if (canOpenOfficialPdf)
          _InvoiceIconAction(
            tooltip: invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived
                ? 'Maliye orijinal nüshasını aç'
                : 'PDF oluştur / aç',
            icon: Icons.picture_as_pdf_outlined,
            tone: _InvoiceActionTone.danger,
            onPressed: _busy
                ? null
                : (invoice.invoiceType == 'purchase' ||
                        invoice.isEInvoiceReceived)
                    ? _openMaliyeLink
                    : _printOfficialPdf,
          )
        else
          _InvoiceIconAction(
            tooltip: 'PDF yazdır',
            icon: AppPhosphorIcons.printer,
            onPressed: _busy ? null : _print,
          ),
        if (canOpenOfficialPdf)
          _InvoiceIconAction(
            tooltip: 'Maliye sayfasını aç',
            icon: Icons.upload_rounded,
            tone: _InvoiceActionTone.success,
            onPressed: _busy ? null : _openMaliyeLink,
          ),
        if ((!invoice.isLinkedToAkinsoft || invoice.needsAkinsoftNumberSync) &&
            invoice.isActive &&
            invoice.status != 'cancelled')
          _InvoiceIconAction(
            tooltip: invoice.needsAkinsoftNumberSync
                ? 'SAP fatura numarasını Maliye no ile güncelle'
                : 'SAP’a fatura gönder',
            icon: invoice.needsAkinsoftNumberSync
                ? AppPhosphorIcons.arrowsClockwise
                : AppPhosphorIcons.cloudArrowUp,
            tone: _InvoiceActionTone.success,
            onPressed: _busy ? null : _pushToAkinsoft,
          ),
        _InvoiceIconAction(
          tooltip: 'Düzenle',
          icon: Icons.edit_outlined,
          tone: _InvoiceActionTone.purple,
          onPressed: _busy ? null : _edit,
        ),
        PopupMenuButton<String>(
          tooltip: 'Diğer işlemler',
          enabled: !_busy,
          padding: EdgeInsets.zero,
          offset: const Offset(0, 36),
          onSelected: (value) {
            switch (value) {
              case 'payment_link':
                _sendPaymentLink();
              case 'manual':
                _toggleManual();
              case 'manual_sent':
                _toggleManualSent();
              case 'statement':
                _statement();
              case 'payload':
                _prepare(send: false);
              case 'active':
                _toggleActive();
              case 'delete':
                _delete();
            }
          },
          itemBuilder: (context) => [
            if (invoice.invoiceType == 'sales' &&
                invoice.isActive &&
                invoice.isOpen &&
                invoice.remainingAmount > 0)
              const PopupMenuItem(
                value: 'payment_link',
                child: Text('Tekil ödeme linki'),
              ),
            if (!alreadySent)
              PopupMenuItem(
                value: 'manual',
                child: Text(
                  isManual ? 'Manuel işareti geri al' : 'Manuel fatura kesildi',
                ),
              ),
            if (canMarkManualSent)
              PopupMenuItem(
                value: 'manual_sent',
                child: Text(
                  isManualSent
                      ? 'Manuel gönderildi işaretini geri al'
                      : 'Manuel Gönderildi olarak işaretle',
                ),
              ),
            const PopupMenuItem(
              value: 'statement',
              child: Text('Cari ekstre PDF'),
            ),
            if (showSendAction)
              const PopupMenuItem(
                value: 'payload',
                child: Text('Gönderim verisini hazırla'),
              ),
            PopupMenuItem(
              value: 'active',
              child: Text(invoice.isActive ? 'Pasife al' : 'Aktifleştir'),
            ),
            if (!invoice.isActive)
              const PopupMenuItem(value: 'delete', child: Text('Kalıcı sil')),
          ],
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.surfaceMuted.withValues(alpha: 0.9),
              borderRadius: BorderRadius.circular(13),
            ),
            child: AppPhosphorIcon(
              AppPhosphorIcons.dotsThree,
              size: 24,
              color: AppTheme.textSoft,
            ),
          ),
        ),
      ];
      final spaced = <Widget>[];
      for (var i = 0; i < actions.length; i++) {
        if (i > 0) spaced.add(const Gap(6));
        spaced.add(actions[i]);
      }
      return spaced;
    }

    final actions = <Widget>[
      if (showSendAction)
        _InvoiceIconAction(
          tooltip: sendTooltip,
          icon: _busy ? Icons.schedule_rounded : Icons.send_rounded,
          tone: _InvoiceActionTone.primary,
          onPressed: _busy || !canSend ? null : () => _prepare(send: true),
        ),
      if (canOpenOfficialPdf)
        _InvoiceIconAction(
          tooltip: invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived
              ? 'Maliye orijinal nüshasını aç'
              : 'PDF oluştur / aç',
          icon: Icons.picture_as_pdf_outlined,
          tone: _InvoiceActionTone.danger,
          onPressed: _busy
              ? null
              : (invoice.invoiceType == 'purchase' ||
                      invoice.isEInvoiceReceived)
                  ? _openMaliyeLink
                  : _printOfficialPdf,
        )
      else
        _InvoiceIconAction(
          tooltip: 'PDF yazdır',
          icon: AppPhosphorIcons.printer,
          onPressed: _busy ? null : _print,
        ),
      if (canOpenOfficialPdf)
        _InvoiceIconAction(
          tooltip: 'Maliye sayfasını aç',
          icon: Icons.upload_rounded,
          tone: _InvoiceActionTone.success,
          onPressed: _busy ? null : _openMaliyeLink,
        ),
      if ((!invoice.isLinkedToAkinsoft || invoice.needsAkinsoftNumberSync) &&
          invoice.isActive &&
          invoice.status != 'cancelled')
        _InvoiceIconAction(
          tooltip: invoice.needsAkinsoftNumberSync
              ? 'SAP fatura numarasını Maliye no ile güncelle'
              : 'SAP’a fatura gönder',
          icon: invoice.needsAkinsoftNumberSync
              ? AppPhosphorIcons.arrowsClockwise
              : AppPhosphorIcons.cloudArrowUp,
          tone: _InvoiceActionTone.success,
          onPressed: _busy ? null : _pushToAkinsoft,
        ),
      _InvoiceIconAction(
        tooltip: 'Düzenle',
        icon: Icons.edit_outlined,
        tone: _InvoiceActionTone.purple,
        onPressed: _busy ? null : _edit,
      ),
      PopupMenuButton<String>(
        tooltip: 'Diğer işlemler',
        enabled: !_busy,
        padding: EdgeInsets.zero,
        offset: const Offset(0, 36),
        onSelected: (value) {
          switch (value) {
            case 'payment_link':
              _sendPaymentLink();
            case 'manual':
              _toggleManual();
            case 'manual_sent':
              _toggleManualSent();
            case 'statement':
              _statement();
            case 'payload':
              _prepare(send: false);
            case 'active':
              _toggleActive();
            case 'delete':
              _delete();
          }
        },
        itemBuilder: (context) => [
          if (invoice.invoiceType == 'sales' &&
              invoice.isActive &&
              invoice.isOpen &&
              invoice.remainingAmount > 0)
            const PopupMenuItem(
              value: 'payment_link',
              child: Text('Tekil ödeme linki'),
            ),
          if (!alreadySent)
            PopupMenuItem(
              value: 'manual',
              child: Text(
                isManual ? 'Manuel işareti geri al' : 'Manuel fatura kesildi',
              ),
            ),
          if (canMarkManualSent)
            PopupMenuItem(
              value: 'manual_sent',
              child: Text(
                isManualSent
                    ? 'Manuel gönderildi işaretini geri al'
                    : 'Manuel Gönderildi olarak işaretle',
              ),
            ),
          const PopupMenuItem(
            value: 'statement',
            child: Text('Cari ekstre PDF'),
          ),
          if (showSendAction)
            const PopupMenuItem(
              value: 'payload',
              child: Text('Gönderim verisini hazırla'),
            ),
          PopupMenuItem(
            value: 'active',
            child: Text(invoice.isActive ? 'Pasife al' : 'Aktifleştir'),
          ),
          if (!invoice.isActive)
            const PopupMenuItem(value: 'delete', child: Text('Kalıcı sil')),
        ],
        child: Container(
          width: 44,
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(13),
          ),
          child: AppPhosphorIcon(
            AppPhosphorIcons.dotsThree,
            size: 24,
            color: AppTheme.textSoft,
          ),
        ),
      ),
    ];
    if (!withGaps) return actions;
    final spaced = <Widget>[];
    for (var i = 0; i < actions.length; i++) {
      if (i > 0) spaced.add(const Gap(2));
      spaced.add(actions[i]);
    }
    return spaced;
  }

  @override
  Widget build(BuildContext context) {
    final invoice = widget.invoice;
    final settings = ref.watch(eInvoiceSettingsProvider).value ?? const {};
    final alreadySent =
        invoice.isEInvoiceSent || invoice.eInvoiceStatus == 'manual_sent';
    final environment = (settings['environment'] ?? 'test').toString();
    final canSend = invoice.canSendEInvoiceTo(environment);
    // Alış / Maliye’den gelen: gönder butonu hiç gösterilmez (e-fatura ile aynı).
    final showSendAction =
        invoice.invoiceType != 'purchase' && !invoice.isEInvoiceReceived;
    final sendTooltip = invoice.isEInvoiceManual
        ? 'Manuel fatura olarak işaretli; API gönderimi kapalı'
        : invoice.eInvoiceStatus == 'manual_sent'
        ? 'Manuel gönderildi olarak işaretli; canlı API gönderimi kapalı'
        : alreadySent &&
              invoice.eInvoiceEnvironment == 'test' &&
              environment == 'production'
        ? 'Testte gönderildi; canlı API’ye gönder'
        : alreadySent
        ? 'Bu fatura bu ortamda başarıyla gönderildi'
        : environment == 'production'
        ? 'Canlı API’ye gönder'
        : 'Test API’ye gönder';
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: invoice.currency == 'TRY' ? '₺' : '${invoice.currency} ',
      decimalDigits: 2,
    );

    if (MediaQuery.sizeOf(context).width < 900) {
      return _buildCompactRow(
        context,
        invoice,
        money,
        sendTooltip,
        canSend,
        showSendAction,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDenseList.rowFill(widget.index, selected: widget.selected),
        border: Border(bottom: AppDenseList.hairline),
      ),
      child: SizedBox(
        height: AppDenseList.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDenseList.rowH),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: AppInvoiceTableCols.check,
                child: Checkbox(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: widget.selected,
                  onChanged: widget.onSelectedChanged == null
                      ? null
                      : (value) => widget.onSelectedChanged!(value ?? false),
                ),
              ),
              Expanded(
                child: Row(
                  children: [
                    AppDenseLeadingIcon(
                      icon: invoice.invoiceType == 'sales'
                          ? AppPhosphorIcons.receipt
                          : AppPhosphorIcons.clipboardText,
                      color: invoice.invoiceType == 'sales'
                          ? AppTheme.primary
                          : AppTheme.warning,
                      active: invoice.isActive,
                      colorful: true,
                    ),
                    const Gap(AppInvoiceTableCols.leadingGap),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            invoice.customerName ?? 'Cari',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.text,
                                ),
                          ),
                          Tooltip(
                            message: invoice.invoiceNumber,
                            waitDuration: const Duration(milliseconds: 250),
                            child: Text(
                              invoice.invoiceNumberDisplay,
                              maxLines: 1,
                              softWrap: false,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontSize: 11.5,
                                    height: 1.1,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textSoft,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: AppInvoiceTableCols.date,
                child: Text(
                  DateFormat('dd.MM.yyyy').format(invoice.invoiceDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
              SizedBox(
                width: AppInvoiceTableCols.type,
                child: Text(
                  invoice.invoiceType == 'sales' ? 'Satış' : 'Alış',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
              SizedBox(
                width: AppInvoiceTableCols.status,
                child: AppDenseBadgeRow(
                  children: [
                    AppBadge(
                      dense: true,
                      label: invoice.isActive
                          ? _statusLabel(invoice.status)
                          : 'Pasif',
                      tone: invoice.isActive
                          ? _statusTone(invoice.status)
                          : AppBadgeTone.neutral,
                    ),
                    if (invoice.isPaidViaPos)
                      AppBadge(
                        dense: true,
                        label: 'Sanal POS',
                        tone: AppBadgeTone.success,
                      ),
                    AppBadge(
                      dense: true,
                      label: _eInvoiceStatusLabel(invoice),
                      tone: _eInvoiceStatusTone(invoice),
                    ),
                    Tooltip(
                      message:
                          invoice.akinsoftSyncStatusEffective == 'error' &&
                              (invoice.akinsoftSyncError?.trim().isNotEmpty ??
                                  false)
                          ? invoice.akinsoftSyncError!.trim()
                          : _akinsoftSyncStatusLabel(invoice),
                      waitDuration: const Duration(milliseconds: 250),
                      child: AppBadge(
                        dense: true,
                        label: _akinsoftSyncStatusLabel(invoice),
                        tone: _akinsoftSyncStatusTone(invoice),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: AppInvoiceTableCols.amount,
                child: Text(
                  money.format(invoice.grandTotal),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SizedBox(
                width: AppInvoiceTableCols.actions,
                height: AppDenseList.action,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: _buildInvoiceActions(
                      sendTooltip: sendTooltip,
                      canSend: canSend,
                      showSendAction: showSendAction,
                      withGaps: true,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCompactRow(
    BuildContext context,
    Invoice invoice,
    NumberFormat money,
    String sendTooltip,
    bool canSend,
    bool showSendAction,
  ) {
    final syncError =
        invoice.akinsoftSyncStatusEffective == 'error' &&
        (invoice.akinsoftSyncError?.trim().isNotEmpty ?? false);
    final statusTone = invoice.isActive
        ? _eInvoiceStatusTone(invoice)
        : AppBadgeTone.neutral;
    final statusLabel = invoice.isActive
        ? _eInvoiceStatusLabel(invoice)
        : 'Pasif';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        color: widget.selected
            ? AppTheme.softTint(AppTheme.primary, alpha: 0.12)
            : AppTheme.surface,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  value: widget.selected,
                  onChanged: widget.onSelectedChanged == null
                      ? null
                      : (value) => widget.onSelectedChanged!(value ?? false),
                ),
                const Gap(4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Tooltip(
                              message: invoice.invoiceNumber,
                              waitDuration: const Duration(milliseconds: 250),
                              child: Text(
                                invoice.invoiceNumberDisplay,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(
                                      fontSize: 14,
                                      height: 1.2,
                                      fontWeight: FontWeight.w800,
                                      color: AppTheme.text,
                                    ),
                              ),
                            ),
                          ),
                          const Gap(8),
                          Text(
                            DateFormat(
                              'd MMM yyyy',
                              'tr_TR',
                            ).format(invoice.invoiceDate),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textMuted,
                                ),
                          ),
                        ],
                      ),
                      const Gap(4),
                      Text(
                        invoice.customerName ?? 'Cari',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontSize: 13,
                          height: 1.25,
                          fontWeight: FontWeight.w500,
                          color: AppTheme.textMuted,
                        ),
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
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        money.format(invoice.grandTotal),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppTheme.text,
                        ),
                      ),
                      if (invoice.paidAmount > 0) ...[
                        const Gap(2),
                        Text(
                          invoice.isPaid
                              ? 'Tahsil: ${money.format(invoice.paidAmount)}'
                              : 'Tahsil: ${money.format(invoice.paidAmount)} · Kalan ${money.format(invoice.remainingAmount)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: invoice.isPaid
                                ? const Color(0xFF15803D)
                                : AppTheme.textMuted,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Flexible(
                  child: Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      AppBadge(
                        dense: true,
                        label: invoice.isActive
                            ? _statusLabel(invoice.status)
                            : 'Pasif',
                        tone: invoice.isActive
                            ? _statusTone(invoice.status)
                            : AppBadgeTone.neutral,
                      ),
                      if (invoice.isPaidViaPos)
                        AppBadge(
                          dense: true,
                          label: invoice.lastPaymentAt != null
                              ? 'Sanal POS · ${DateFormat('d MMM', 'tr_TR').format(invoice.lastPaymentAt!)}'
                              : 'Sanal POS',
                          tone: AppBadgeTone.success,
                        ),
                      AppBadge(
                        dense: true,
                        label: statusLabel,
                        tone: statusTone,
                      ),
                      if (syncError)
                        Tooltip(
                          message: invoice.akinsoftSyncError!.trim(),
                          child: AppBadge(
                            dense: true,
                            label: 'Uyarı',
                            tone: AppBadgeTone.warning,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            const Gap(12),
            SizedBox(
              height: AppDenseList.action + 4,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _buildInvoiceActions(
                  sendTooltip: sendTooltip,
                  canSend: canSend,
                  showSendAction: showSendAction,
                  withGaps: true,
                  mobile: true,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendPaymentLink() async {
    setState(() => _busy = true);
    try {
      await _createInvoicePaymentLinkFlow(
        context: context,
        ref: ref,
        invoices: [widget.invoice],
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
    final nextActive = !widget.invoice.isActive;
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
          'values': {'is_active': nextActive},
        },
      );
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextActive
                ? '${widget.invoice.invoiceNumber} aktifleştirildi.'
                : '${widget.invoice.invoiceNumber} pasife alındı.',
          ),
        ),
      );
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
    if (widget.invoice.isActive) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Faturayı kalıcı sil'),
        content: Text(
          '${widget.invoice.invoiceNumber} numaralı pasif fatura ve kalemleri '
          'kalıcı olarak silinsin mi? Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kalıcı Sil'),
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
        body: {
          'op': 'deleteWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.invoice.id},
          ],
        },
      );
      ref.invalidate(invoicesProvider);
      ref.invalidate(accountBalancesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.invoice.invoiceNumber} kalıcı olarak silindi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fatura silinemedi: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleManual() async {
    if (widget.invoice.isEInvoiceSent ||
        widget.invoice.eInvoiceStatus == 'manual_sent') {
      return;
    }
    final marking = !widget.invoice.isEInvoiceManual;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          marking ? 'Manuel fatura kesildi' : 'Manuel işareti geri al',
        ),
        content: Text(
          marking
              ? '${widget.invoice.invoiceNumber} numaralı fatura başka sistemden kesilmiş olarak işaretlensin mi? Bu işlem sonrası API gönderimi kapanır.'
              : '${widget.invoice.invoiceNumber} numaralı faturanın manuel kesildi işareti geri alınsın mı? Fatura tekrar API’ye gönderilebilir hale gelir.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(marking ? 'İşaretle' : 'Geri al'),
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
          'op': 'updateWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.invoice.id},
          ],
          'values': {
            'e_invoice_status': marking
                ? 'manual'
                : (widget.invoice.eInvoiceEnvironment == 'test'
                      ? 'sent'
                      : 'not_sent'),
          },
        },
      );
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            marking
                ? '${widget.invoice.invoiceNumber} manuel fatura olarak işaretlendi.'
                : '${widget.invoice.invoiceNumber} manuel işareti geri alındı.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Manuel durum güncellenemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleManualSent() async {
    final invoice = widget.invoice;
    final isMarked = invoice.eInvoiceStatus == 'manual_sent';
    final canMark =
        isMarked ||
        (invoice.eInvoiceStatus == 'sent' &&
            invoice.eInvoiceEnvironment == 'test');
    if (!canMark) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isMarked
              ? 'Manuel gönderildi işaretini geri al'
              : 'Manuel Gönderildi',
        ),
        content: Text(
          isMarked
              ? '${invoice.invoiceNumber} numaralı faturanın manuel gönderildi işareti geri alınsın mı? Fatura tekrar canlı API’ye gönderilebilir hale gelir.'
              : '${invoice.invoiceNumber} numaralı fatura test API sonrası manuel gönderildi olarak işaretlensin mi? Canlı API gönderimi kapanır; test gönderim kaydı korunur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(isMarked ? 'Geri al' : 'İşaretle'),
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
          'op': 'updateWhere',
          'table': 'invoices',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': invoice.id},
          ],
          'values': {
            'e_invoice_status': isMarked ? 'sent' : 'manual_sent',
            if (!isMarked) 'e_invoice_environment': 'test',
          },
        },
      );
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isMarked
                ? '${invoice.invoiceNumber} manuel gönderildi işareti geri alındı.'
                : '${invoice.invoiceNumber} Manuel Gönderildi olarak işaretlendi.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Manuel gönderildi durumu güncellenemedi: $error'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final invoice = await _loadInvoiceDetail();
    if (invoice == null) return;
    if (invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived) {
      if (invoice.canOpenOfficialMaliyeNushasi) {
        await _openOfficialInvoicePage(invoice);
        return;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Maliye orijinal nüshası için doğrulama kodu yok. '
            'E-Fatura > Alış’tan “Maliye’den gelenleri al” ile yeniden senkronize edin.',
          ),
        ),
      );
      return;
    }
    if (invoice.canOpenArchiveEInvoicePdf) {
      await _printOfficialPdf();
      return;
    }
    await _printInvoiceCopy(invoice);
  }

  Future<void> _openMaliyeLink() async {
    if (await _openOfficialInvoicePage(widget.invoice)) return;

    final invoice = await _loadInvoiceDetail();
    if (invoice == null) return;
    if (await _openOfficialInvoicePage(invoice)) return;

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Maliye doğrulama kodu bulunamadı. Fatura detayını yenileyin.',
        ),
      ),
    );
  }

  /// Tarayıcılar açılır pencereyi yalnızca kullanıcı hareketiyle aynı çağrı
  /// yığınında açar; bu yüzden ağ isteği beklenmeden çağrılmalıdır.
  Future<bool> _openOfficialInvoicePage(Invoice invoice) async {
    final officialUrl = buildOfficialEInvoiceUrl(
      verificationCode: invoice.eInvoiceUuid,
      environment: invoice.eInvoiceEnvironment ?? 'test',
    );
    if (officialUrl == null) return false;

    final opened = await openExternalUrl(officialUrl);
    if (!opened) {
      await _showLinkFallbackDialog('Maliye Fatura Sayfası', officialUrl);
    }
    return true;
  }

  Future<void> _showLinkFallbackDialog(String title, String url) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 520,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bağlantı otomatik açılamadı. Aşağıdaki adresi açabilir veya '
                'kopyalayıp tarayıcınıza yapıştırabilirsiniz.',
              ),
              const Gap(12),
              SelectableText(
                url,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: url)),
            child: const Text('Kopyala'),
          ),
          FilledButton(
            onPressed: () {
              unawaited(openExternalUrl(url));
              Navigator.of(context).pop();
            },
            child: const Text('Aç'),
          ),
        ],
      ),
    );
  }

  Future<void> _printOfficialPdf() async {
    final invoice = await _loadInvoiceDetail();
    if (invoice == null) return;

    // Alış / gelen: asla CRM pdfkit. Orijinal Maliye /dogrula nüshası.
    if (invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived) {
      final opened = await _openOfficialInvoicePage(invoice);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Maliye orijinal nüshası açılamadı: doğrulama kodu yok.',
            ),
          ),
        );
      }
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PDF oluşturmak için sunucu bağlantısı gerekli.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final archive = await apiClient.postJson(
        '/e-invoice',
        body: _archivePdfRequestBody(invoice.id),
      );
      ref.invalidate(invoicesProvider);

      final officialOnly = archive['officialOnly'] == true;
      final officialUrl = archive['officialUrl']?.toString().trim() ?? '';
      if (officialOnly && officialUrl.isNotEmpty) {
        final opened = await openExternalUrl(officialUrl);
        if (!opened) {
          await _showLinkFallbackDialog('Maliye Fatura Sayfası', officialUrl);
        }
        return;
      }

      final pdfUrl = archive['pdfUrl']?.toString().trim() ?? '';
      final pdfBase64 = archive['pdfBase64']?.toString().trim() ?? '';
      if (pdfUrl.isEmpty && pdfBase64.isEmpty) {
        throw Exception(
          archive['error']?.toString().trim().isNotEmpty == true
              ? archive['error'].toString()
              : 'PDF bağlantısı oluşturulamadı.',
        );
      }
      final opened = await _shareOrOpenPdf(
        invoice,
        pdfUrl,
        pdfBase64: pdfBase64.isNotEmpty ? pdfBase64 : null,
      );
      if (!mounted) return;
      if (!opened) {
        // Mobilde yerel open-pdf /tmp yolu anlamsız; yalnızca http(s) göster.
        final canShowLink =
            pdfUrl.isNotEmpty &&
            !isLocalOpenPdfUrl(pdfUrl) &&
            (pdfUrl.startsWith('https://') || pdfUrl.startsWith('http://'));
        if (canShowLink) {
          await _showLinkFallbackDialog('Oluşturulan PDF', pdfUrl);
          return;
        }
        throw Exception('PDF paylaşılamadı.');
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('PDF hazır.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Oluşturulan PDF açılamadı: ${_friendlyPdfError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ignore: unused_element
  Future<void> _sendWhatsAppPdf() async {
    final invoice = await _loadInvoiceDetail();
    if (invoice == null) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('WhatsApp için sunucu bağlantısı gerekli.'),
        ),
      );
      return;
    }

    setState(() => _busy = true);
    try {
      final archive = await apiClient.postJson(
        '/e-invoice',
        body: _archivePdfRequestBody(invoice.id),
      );
      ref.invalidate(invoicesProvider);
      final pdfUrl = archive['pdfUrl']?.toString().trim() ?? '';
      final pdfBase64 = archive['pdfBase64']?.toString().trim() ?? '';
      if (pdfUrl.isEmpty && pdfBase64.isEmpty) {
        throw Exception(
          archive['error']?.toString().trim().isNotEmpty == true
              ? archive['error'].toString()
              : 'PDF bağlantısı oluşturulamadı.',
        );
      }
      if (!mounted) return;
      await _sendWhatsAppPdfWithUrl(
        invoice,
        pdfUrl,
        pdfBase64: pdfBase64.isNotEmpty ? pdfBase64 : null,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'WhatsApp gönderimi başarısız: ${_friendlyPdfError(error)}',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ignore: unused_element
  Future<void> _sendWhatsAppPdfWithUrl(
    Invoice invoice,
    String pdfUrl, {
    String? pdfBase64,
  }) async {
    CustomerDetail? customer;
    final customerId = invoice.customerId.trim();
    if (customerId.isNotEmpty) {
      try {
        customer = await ref.read(customerDetailProvider(customerId).future);
      } catch (_) {
        customer = null;
      }
    }
    if (!mounted) return;
    await shareEInvoicePdfWithWhatsApp(
      context: context,
      invoice: invoice,
      pdfUrl: pdfUrl,
      pdfBase64: pdfBase64,
      customer: customer,
    );
  }

  /// Mobilde imzalı URL yerine PDF dosyasını paylaşır; paylaşım metninde
  /// fatura numarası ve müşteri adı görünür.
  Future<bool> _shareOrOpenPdf(
    Invoice invoice,
    String pdfUrl, {
    String? pdfBase64,
  }) async {
    // Electron/web: open-pdf köprüsü shell.openPath ile açar. Mobilde bu URL
    // geçersizdir; pdfBase64 / https ile devam et.
    if (kIsWeb && isLocalOpenPdfUrl(pdfUrl)) {
      return openExternalUrl(pdfUrl);
    }

    final number = (invoice.eInvoiceNumber?.trim().isNotEmpty ?? false)
        ? _localEInvoiceNumber(invoice.eInvoiceNumber!)
        : invoice.invoiceNumber.trim();
    final customer = (invoice.customerName ?? '').trim();
    final shareText = customer.isEmpty ? number : '$number - $customer';
    final fileName = customer.isEmpty
        ? '$number.pdf'
        : '${customer}_$number.pdf';

    final shareUrl = isLocalOpenPdfUrl(pdfUrl) ? '' : pdfUrl;

    try {
      if (await shareEInvoicePdf(
        url: shareUrl,
        fileName: fileName,
        shareText: shareText,
        pdfBase64: pdfBase64,
      )) {
        return true;
      }
    } catch (_) {
      // Paylaşım başarısızsa bağlantıyı açmaya geri düşülür.
    }
    if (shareUrl.trim().isEmpty) return false;
    return openExternalUrl(shareUrl);
  }

  Future<Invoice?> _loadInvoiceDetail() async {
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
    return invoice;
  }

  Future<void> _printInvoiceCopy(Invoice invoice) async {
    final ok = await printEInvoice(invoice);
    if (!mounted || ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bu platformda yazdırma desteklenmiyor.')),
    );
  }

  Future<void> _statement() async {
    setState(() => _busy = true);
    try {
      final invoice = widget.invoice;
      final customerName = invoice.customerName?.trim().isNotEmpty == true
          ? invoice.customerName!.trim()
          : 'Cari';
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
      await shareInvoiceStatementPdf(
        title: 'Fatura Ekstresi',
        customerName: customerName,
        invoices: [invoice],
        bankDetails: (settings['seller_bank_details'] ?? '').toString(),
        filename:
            'fatura_ekstresi_${safeStatementFilePart(customerName)}_${safeStatementFilePart(invoice.invoiceNumber, fallback: 'fatura')}_$stamp.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Ekstre oluşturulamadı: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _prepare({required bool send}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final invoice = widget.invoice;
    if (invoice.invoiceType == 'purchase' || invoice.isEInvoiceReceived) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Alış veya Maliye’den gelen faturalar API’ye gönderilemez.',
          ),
        ),
      );
      return;
    }

    if (send) {
      final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
      final isProduction =
          (settings['environment'] ?? 'test').toString() == 'production';
      if (isProduction) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Canlı API’ye gönder'),
            content: Text(
              '${widget.invoice.invoiceNumber} numaralı fatura '
              'canlı (production) Maliye API’sine gönderilecek.\n\n'
              'Bu işlem geri alınamaz. Devam edilsin mi?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Canlıya Gönder'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;
      }
    }

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

  // ignore: unused_element
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

  Future<void> _pushToAkinsoft() async {
    final invoice = widget.invoice;
    final syncNumber = invoice.needsAkinsoftNumberSync;
    if (!syncNumber && invoice.isLinkedToAkinsoft) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu fatura zaten SAP ile eşleşmiş.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          syncNumber ? 'SAP fatura no güncelle' : 'SAP’a fatura gönder',
        ),
        content: Text(
          syncNumber
              ? '${invoice.invoiceNumber} için SAP kaydı Maliye e-fatura '
                    'numarasına güncellensin mi?\n\n'
                    'SAP’ta yoksa Maliye numarasıyla yeni oluşturulur.'
              : '${invoice.invoiceNumber} numaralı fatura SAP’a yeni kayıt '
                    'olarak yazılsın mı?\n\n'
                    'Cari yoksa eklenir; stok eşleşmezse kalem açıklama olarak yazılır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(syncNumber ? 'Güncelle' : 'Gönder'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final response = await http
          .post(
            _akinsoftUri(syncNumber ? 'push-invoice-numbers' : 'push-invoices'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode({
              ...settings,
              'invoiceIds': [invoice.id],
            }),
          )
          .timeout(const Duration(minutes: 5));
      final decoded = jsonDecode(response.body);
      if (decoded is! Map) {
        throw Exception('Beklenmeyen SAP yanıtı.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(decoded['error'] ?? 'SAP gönderimi başarısız.');
      }
      ref.invalidate(invoicesProvider);
      if (!mounted) return;
      final items = decoded['items'];
      final first = items is List && items.isNotEmpty ? items.first : null;
      final ok = first is Map && first['ok'] == true;
      final reason = first is Map ? first['reason']?.toString() : null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? (reason?.isNotEmpty == true
                      ? '${invoice.invoiceNumber}: $reason'
                      : syncNumber
                      ? '${invoice.invoiceNumber} SAP no güncellendi.'
                      : '${invoice.invoiceNumber} SAP’a yazıldı.')
                : '${invoice.invoiceNumber} gönderilemedi: ${reason ?? 'bilinmeyen hata'}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_akinsoftBridgeError(error))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _statusLabel(String status) {
    return switch (status) {
      'draft' => 'Taslak',
      'open' => 'Açık',
      'partial' => 'Kısmi ödendi',
      'paid' => 'Ödendi',
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

  String _eInvoiceStatusLabel(Invoice invoice) {
    if (invoice.isEInvoiceManualSent) return 'E-Fat. manuel';
    return switch (invoice.eInvoiceStatus) {
      'sent' => 'E-Fat. gönderildi',
      'received' => 'Maliye’den geldi',
      'manual' => 'E-Fat. manuel',
      'prepared' => 'E-Fat. hazır',
      'failed' => 'E-Fat. hatalı',
      'cancelled' => 'E-Fat. iptal',
      _ => 'E-Fat. yok',
    };
  }

  AppBadgeTone _eInvoiceStatusTone(Invoice invoice) {
    if (invoice.isEInvoiceManualSent) return AppBadgeTone.primary;
    return switch (invoice.eInvoiceStatus) {
      'sent' => AppBadgeTone.success,
      'received' => AppBadgeTone.success,
      'manual' => AppBadgeTone.warning,
      'prepared' => AppBadgeTone.warning,
      'failed' => AppBadgeTone.error,
      'cancelled' => AppBadgeTone.neutral,
      _ => AppBadgeTone.neutral,
    };
  }

  String _akinsoftSyncStatusLabel(Invoice invoice) {
    return switch (invoice.akinsoftSyncStatusEffective) {
      'synced' => 'SAP gönderildi',
      'error' => 'SAP hata',
      _ => 'SAP yok',
    };
  }

  AppBadgeTone _akinsoftSyncStatusTone(Invoice invoice) {
    return switch (invoice.akinsoftSyncStatusEffective) {
      'synced' => AppBadgeTone.success,
      'error' => AppBadgeTone.error,
      _ => AppBadgeTone.neutral,
    };
  }
}

class _InvoiceIconAction extends StatelessWidget {
  const _InvoiceIconAction({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.tone = _InvoiceActionTone.neutral,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final _InvoiceActionTone tone;

  @override
  Widget build(BuildContext context) {
    final colors = _toneColors(context, tone);
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 250),
      child: IconButton(
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints.tightFor(width: 44, height: 44),
        style: IconButton.styleFrom(
          backgroundColor: colors.background,
          foregroundColor: colors.foreground,
          disabledBackgroundColor: colors.background,
          disabledForegroundColor: colors.foreground.withValues(alpha: 0.72),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
            side: BorderSide.none,
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 24),
      ),
    );
  }

  static ({Color background, Color foreground, Color border}) _toneColors(
    BuildContext context,
    _InvoiceActionTone tone,
  ) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return switch (tone) {
      _InvoiceActionTone.primary => (
        background: dark ? const Color(0xFF1D2B45) : const Color(0xFFE7F0FF),
        foreground: dark ? const Color(0xFF72A7FF) : const Color(0xFF2864D7),
        border: AppTheme.primary,
      ),
      _InvoiceActionTone.success => (
        background: dark ? const Color(0xFF203833) : const Color(0xFFE2F7EF),
        foreground: dark ? const Color(0xFF63D4A5) : const Color(0xFF16805E),
        border: AppTheme.success,
      ),
      _InvoiceActionTone.warning => (
        background: AppTheme.softTint(AppTheme.warning, alpha: 0.18),
        foreground: AppTheme.warning,
        border: AppTheme.warning,
      ),
      _InvoiceActionTone.danger => (
        background: dark ? const Color(0xFF3B2C33) : const Color(0xFFFFE8EC),
        foreground: dark ? const Color(0xFFFF8197) : const Color(0xFFC33D59),
        border: AppTheme.error,
      ),
      _InvoiceActionTone.info => (
        background: dark ? const Color(0xFF1D2B45) : const Color(0xFFE7F0FF),
        foreground: dark ? const Color(0xFF72A7FF) : const Color(0xFF2864D7),
        border: AppTheme.primary,
      ),
      _InvoiceActionTone.purple => (
        background: dark ? const Color(0xFF302D45) : const Color(0xFFF0E9FF),
        foreground: dark ? const Color(0xFFB18AFF) : const Color(0xFF7042C1),
        border: AppTheme.purple,
      ),
      _InvoiceActionTone.neutral => (
        background: Colors.transparent,
        foreground: AppTheme.textSoft,
        border: AppTheme.border,
      ),
    };
  }
}

enum _InvoiceActionTone {
  neutral,
  primary,
  success,
  warning,
  danger,
  info,
  purple,
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
  String? _editingPriceProductId;
  bool _pullingErp = false;

  Future<void> _pullAkinsoftProducts() async {
    setState(() => _pullingErp = true);
    try {
      final settings = await ref.read(eInvoiceSettingsProvider.future);
      final payload = {...settings, 'limit': 2000};
      final response = await http
          .post(
            _akinsoftUri('pull'),
            headers: {'Content-Type': 'application/json; charset=utf-8'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(minutes: 5));
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
      ref.invalidate(productsProvider(null));
      ref.invalidate(invoicesProvider);
      ref.invalidate(customersProvider);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('SAP stok/hizmet çekilemedi: $error')),
      );
    } finally {
      if (mounted) setState(() => _pullingErp = false);
    }
  }

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
                product.productType,
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
                      prefixIcon: Icon(AppPhosphorIcons.magnifyingGlass),
                      hintText: 'Stok kodu, ürün/hizmet adı, grup ara',
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
                FilledButton.tonalIcon(
                  onPressed: _pullingErp ? null : _pullAkinsoftProducts,
                  icon: _pullingErp
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(AppPhosphorIcons.cloudArrowDown, size: 18),
                  label: Text(_pullingErp ? 'Çekiliyor…' : 'SAP’tan Çek'),
                ),
                const Gap(10),
                FilledButton.icon(
                  onPressed: () => _showProductDialog(context, ref),
                  icon: const Icon(AppPhosphorIcons.plus, size: 18),
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
                      decoration: BoxDecoration(
                        color: AppTheme.surfaceMuted,
                        border: Border(
                          bottom: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: Row(
                        children: const [
                          SizedBox(
                            width: 40,
                            child: _InvoiceHeaderText('Görsel'),
                          ),
                          SizedBox(
                            width: 100,
                            child: _InvoiceHeaderText('Kod'),
                          ),
                          Expanded(flex: 3, child: _InvoiceHeaderText('Stok')),
                          Expanded(flex: 2, child: _InvoiceHeaderText('Grup')),
                          Expanded(
                            flex: 2,
                            child: _InvoiceHeaderText('Alt Grup'),
                          ),
                          SizedBox(
                            width: 72,
                            child: _InvoiceHeaderText('Birim'),
                          ),
                          SizedBox(
                            width: 300,
                            child: _InvoiceHeaderText('Fiyat'),
                          ),
                          SizedBox(width: 64, child: _InvoiceHeaderText('KDV')),
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
                        decoration: BoxDecoration(
                          border: Border(
                            bottom: BorderSide(color: AppTheme.border),
                          ),
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 40,
                              child: _ProductThumb(url: product.imageUrl),
                            ),
                            SizedBox(
                              width: 100,
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
                            SizedBox(width: 72, child: Text(product.unit)),
                            SizedBox(
                              width: 300,
                              child: _InlineStockPriceCell(
                                product: product,
                                editing: _editingPriceProductId == product.id,
                                onStartEdit: () => setState(
                                  () => _editingPriceProductId = product.id,
                                ),
                                onCancelEdit: () => setState(
                                  () => _editingPriceProductId = null,
                                ),
                                onSave:
                                    ({
                                      required double exclusiveSalePrice,
                                      required String currency,
                                    }) async {
                                      final apiClient = ref.read(
                                        apiClientProvider,
                                      );
                                      if (apiClient == null) {
                                        throw Exception('API bağlantısı yok.');
                                      }
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'upsert',
                                          'table': 'products',
                                          'returning': 'row',
                                          'values': {
                                            'id': product.id,
                                            'name': product.name,
                                            'sale_price': exclusiveSalePrice,
                                            'currency': currency,
                                            'tax_rate': product.taxRate,
                                            'is_active': true,
                                          },
                                        },
                                      );
                                      ref.invalidate(productsProvider(null));
                                      if (mounted) {
                                        setState(
                                          () => _editingPriceProductId = null,
                                        );
                                      }
                                    },
                              ),
                            ),
                            SizedBox(
                              width: 64,
                              child: Text(
                                '%${product.taxRate.toStringAsFixed(0)}',
                              ),
                            ),
                            SizedBox(
                              width: 100,
                              child: TextButton.icon(
                                onPressed: () =>
                                    _showProductDialog(context, ref, product),
                                icon: const Icon(
                                  AppPhosphorIcons.pencil,
                                  size: 16,
                                ),
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
      error: (error, _) => _ErrorCard(
        message: 'Stoklar yüklenemedi.',
        onRetry: () => ref.invalidate(productsProvider(null)),
      ),
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
    String currency = product == null
        ? 'USD'
        : _coerceStockDialogCurrency(_stockSaleCurrency(product));
    String unit = _coerceStockUnit(product?.unit);
    String type = product?.productType ?? 'product';
    double taxRate = _coerceStockTaxRate(product?.taxRate);
    bool trackStock = product?.trackStock ?? true;
    bool pricesIncludeVat = false;
    bool saving = false;
    String? imageUrl = product?.imageUrl;
    Uint8List? pendingImageBytes;
    String? pendingImageMime;
    String? pendingImageName;
    var imageRemoved = false;

    Future<void> pickProductImage(StateSetter setState) async {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 75,
        maxWidth: 900,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      final name = picked.name.toLowerCase();
      final mime = name.endsWith('.png')
          ? 'image/png'
          : name.endsWith('.webp')
          ? 'image/webp'
          : 'image/jpeg';
      setState(() {
        pendingImageBytes = bytes;
        pendingImageMime = mime;
        pendingImageName = picked.name;
        imageUrl = null;
        imageRemoved = false;
      });
    }

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
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                        child: Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            border: Border.all(color: AppTheme.border),
                            borderRadius: BorderRadius.circular(AppTheme.radiusXs),
                          ),
                          child: pendingImageBytes != null
                              ? Image.memory(
                                  pendingImageBytes!,
                                  fit: BoxFit.cover,
                                )
                              : (imageUrl ?? '').trim().isNotEmpty
                              ? Image.network(
                                  imageUrl!.trim(),
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => Icon(
                                    LucideIcons.image,
                                    color: AppTheme.textMuted,
                                  ),
                                )
                              : Icon(
                                  LucideIcons.image,
                                  color: AppTheme.textMuted,
                                ),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: saving
                                  ? null
                                  : () => pickProductImage(setState),
                              icon: const Icon(LucideIcons.upload, size: 16),
                              label: const Text('Görsel seç'),
                            ),
                            if (pendingImageBytes != null ||
                                (imageUrl ?? '').trim().isNotEmpty)
                              TextButton(
                                onPressed: saving
                                    ? null
                                    : () => setState(() {
                                        pendingImageBytes = null;
                                        pendingImageMime = null;
                                        pendingImageName = null;
                                        imageUrl = null;
                                        imageRemoved = true;
                                      }),
                                child: const Text('Kaldır'),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
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
                            hintText: 'SAP ara grubu',
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: TextField(
                          controller: subGroup,
                          decoration: const InputDecoration(
                            labelText: 'Alt Grup',
                            hintText: 'SAP alt grubu',
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
                          decoration: InputDecoration(
                            labelText: pricesIncludeVat
                                ? 'Satış Fiyatı (KDV dahil)'
                                : 'Satış Fiyatı (KDV hariç)',
                          ),
                        ),
                      ),
                    ],
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Satış fiyatı KDV dahil'),
                    subtitle: Text(
                      pricesIncludeVat
                          ? 'Girilen satış fiyatı KDV dahil; kayıt KDV hariç tutulur'
                          : 'Girilen satış fiyatı KDV hariç (fatura ile uyumlu)',
                    ),
                    value: pricesIncludeVat,
                    onChanged: (value) {
                      if (value == pricesIncludeVat) return;
                      final current = _parseDecimal(sale.text);
                      if (taxRate > 0 && current > 0) {
                        final converted = pricesIncludeVat
                            ? current / (1 + taxRate / 100)
                            : current * (1 + taxRate / 100);
                        sale.text = _roundMoney(converted).toStringAsFixed(2);
                      }
                      setState(() => pricesIncludeVat = value);
                    },
                  ),
                  const Gap(10),
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: currency,
                          items: const [
                            DropdownMenuItem(value: 'USD', child: Text('USD')),
                            DropdownMenuItem(value: 'TRY', child: Text('TL')),
                          ],
                          onChanged: (v) =>
                              setState(() => currency = v ?? 'USD'),
                          decoration: const InputDecoration(
                            labelText: 'Para Birimi',
                          ),
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: unit,
                          items: [
                            for (final option in _stockUnitOptions)
                              DropdownMenuItem(
                                value: option,
                                child: Text(option),
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
                          items: [
                            for (final rate in _stockTaxRateOptions)
                              DropdownMenuItem(
                                value: rate,
                                child: Text('%${rate.toStringAsFixed(0)}'),
                              ),
                          ],
                          onChanged: (v) => setState(() => taxRate = v ?? 5),
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
                        final enteredSale = _parseDecimal(sale.text);
                        final exclusiveSale = pricesIncludeVat && taxRate > 0
                            ? enteredSale / (1 + taxRate / 100)
                            : enteredSale;
                        final saved = await apiClient.postJson(
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
                              'sale_price': _roundMoney(exclusiveSale),
                              'currency': currency,
                              'tax_rate': taxRate,
                              'track_stock': trackStock,
                              'min_stock': _parseDecimal(minStock.text),
                              'is_active': true,
                              if (imageRemoved) 'image_url': null,
                              if (!imageRemoved &&
                                  (imageUrl ?? '').trim().isNotEmpty &&
                                  pendingImageBytes == null)
                                'image_url': imageUrl!.trim(),
                            },
                          },
                        );
                        var productId = (saved['id'] ?? product?.id ?? '')
                            .toString();
                        if (pendingImageBytes != null &&
                            pendingImageMime != null &&
                            productId.isNotEmpty) {
                          final uploaded = await apiClient.postJson(
                            '/mutate',
                            body: {
                              'op': 'uploadProductImage',
                              'productId': productId,
                              'filename':
                                  pendingImageName ??
                                  'product-${DateTime.now().millisecondsSinceEpoch}.jpg',
                              'contentType': pendingImageMime,
                              'data': base64Encode(pendingImageBytes!),
                            },
                          );
                          final uploadedUrl = uploaded['url']?.toString();
                          if ((uploadedUrl ?? '').trim().isNotEmpty) {
                            await apiClient.postJson(
                              '/mutate',
                              body: {
                                'op': 'upsert',
                                'table': 'products',
                                'returning': 'row',
                                'values': {
                                  'id': productId,
                                  'name': productName,
                                  'image_url': uploadedUrl!.trim(),
                                  'is_active': true,
                                },
                              },
                            );
                          }
                        }
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
  final Set<String> _exportingAccountIds = {};

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
                        prefixIcon: Icon(AppPhosphorIcons.magnifyingGlass),
                        labelText: 'Cari ara',
                        hintText: 'Firma adı ile filtrele',
                      ),
                    ),
                  ),
                  const Gap(12),
                  OutlinedButton.icon(
                    onPressed: () => ref.invalidate(accountBalancesProvider),
                    icon: const Icon(
                      AppPhosphorIcons.arrowsCounterClockwise,
                      size: 18,
                    ),
                    label: const Text('Yenile'),
                  ),
                  const Gap(10),
                  FilledButton.icon(
                    onPressed: () => _showPaymentDialog(context, ref),
                    icon: const Icon(AppPhosphorIcons.money, size: 18),
                    label: const Text('Tahsilat/Ödeme'),
                  ),
                ],
              ),
            ),
            const Gap(12),
            if (balances.isEmpty)
              const EmptyStateCard(
                icon: AppPhosphorIcons.wallet,
                title: 'Cari hareket yok',
                message: 'Henüz kayıtlı bir cari hesap hareketi bulunmuyor.',
              )
            else if (filtered.isEmpty)
              const EmptyStateCard(
                icon: AppPhosphorIcons.magnifyingGlass,
                title: 'Sonuç bulunamadı',
                message: 'Arama ile eşleşen cari bulunamadı.',
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
                              exporting: _exportingAccountIds.contains(
                                balance.customerId,
                              ),
                              onStatement: () =>
                                  _exportAccountStatement(balance),
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
                            exporting: _exportingAccountIds.contains(
                              balance.customerId,
                            ),
                            onStatement: () => _exportAccountStatement(balance),
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
      error: (error, _) => _ErrorCard(
        message: 'Cari hesap yüklenemedi.',
        onRetry: () => ref.invalidate(accountBalancesProvider),
      ),
    );
  }

  Future<void> _exportAccountStatement(AccountBalance balance) async {
    setState(() => _exportingAccountIds.add(balance.customerId));
    try {
      final invoices = await ref.read(
        invoicesProvider(InvoiceFilter(customerId: balance.customerId)).future,
      );
      if (!mounted) return;
      final settings = ref.read(eInvoiceSettingsProvider).value ?? const {};
      final stamp = DateFormat('yyyyMMdd_HHmm').format(DateTime.now());
      await shareInvoiceStatementPdf(
        title: 'Cari Hesap Ekstresi',
        customerName: balance.name,
        invoices: invoices,
        bankDetails: (settings['seller_bank_details'] ?? '').toString(),
        filename:
            'cari_ekstresi_${safeStatementFilePart(balance.name)}_$stamp.pdf',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Cari ekstresi alınamadı: $error')),
      );
    } finally {
      if (mounted) {
        setState(() => _exportingAccountIds.remove(balance.customerId));
      }
    }
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
                if (apiClient == null) return;
                if (customerId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Lütfen bir cari seçin.')),
                  );
                  return;
                }
                try {
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
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Kaydedilemedi. Lütfen tekrar deneyin.'),
                      ),
                    );
                  }
                }
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
            icon: AppPhosphorIcons.users,
            color: AppTheme.primary,
          ),
          _AccountSummaryCard(
            title: 'Alacak',
            value: money.format(receivable),
            icon: AppPhosphorIcons.phoneOutgoing,
            color: AppTheme.primary,
          ),
          _AccountSummaryCard(
            title: 'Borç',
            value: money.format(payable),
            icon: AppPhosphorIcons.phoneIncoming,
            color: AppTheme.error,
          ),
          _AccountSummaryCard(
            title: 'Satış / Tahsilat',
            value: '${money.format(sales)} / ${money.format(collections)}',
            icon: AppPhosphorIcons.receipt,
            color: AppTheme.blueBright,
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
            decoration: AppTheme.categoryIconWell(color, radius: 10),
            child: Icon(icon, color: AppTheme.categoryIconFg(color), size: 19),
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
      decoration: BoxDecoration(
        color: AppTheme.tableHeaderBg,
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
            width: 130,
            child: _AccountHeaderText('Bakiye', alignEnd: true),
          ),
          SizedBox(
            width: 64,
            child: _AccountHeaderText('İşlem', alignEnd: true),
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
  const _AccountTableRow({
    required this.balance,
    required this.money,
    required this.exporting,
    required this.onStatement,
  });

  final AccountBalance balance;
  final NumberFormat money;
  final bool exporting;
  final VoidCallback onStatement;

  @override
  Widget build(BuildContext context) {
    final positive = balance.balance >= 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
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
            width: 130,
            child: Text(
              money.format(balance.balance),
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: positive ? AppTheme.success : AppTheme.error,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 64,
            child: Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: 'Cari hesap ekstresi',
                onPressed: exporting ? null : onStatement,
                icon: exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppPhosphorIcons.fileText),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AccountMobileRow extends StatelessWidget {
  const _AccountMobileRow({
    required this.balance,
    required this.money,
    required this.exporting,
    required this.onStatement,
  });

  final AccountBalance balance;
  final NumberFormat money;
  final bool exporting;
  final VoidCallback onStatement;

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
          const Gap(8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                money.format(balance.balance),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: positive ? AppTheme.success : AppTheme.error,
                ),
              ),
              IconButton(
                tooltip: 'Cari hesap ekstresi',
                onPressed: exporting ? null : onStatement,
                icon: exporting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(AppPhosphorIcons.fileText),
              ),
            ],
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

  void _selectEnvironment(String value) {
    final environment = value == 'production' ? 'production' : 'test';
    final endpoints = _environmentEndpoints[environment]!;
    setState(() {
      _environment = environment;
      _c('api_base_url').text = endpoints['api_base_url']!;
      _c('token_url').text = endpoints['token_url']!;
    });
  }

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
          _hydrateBankFields(_c('seller_bank_details').text);
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
                            AppPhosphorIcons.cloudSlash,
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
                          onChanged: (v) => _selectEnvironment(v ?? 'test'),
                          decoration: const InputDecoration(labelText: 'Ortam'),
                        ),
                      ),
                      const Gap(10),
                      Expanded(child: _field('seller_vkn', 'Satıcı VKN')),
                      const Gap(10),
                      Expanded(
                        child: _field(
                          'seller_branch_code',
                          'Şube Kod',
                          hintText:
                              'Maliye ortamında kayıtlı kod (örn. MERKEZ)',
                        ),
                      ),
                    ],
                  ),
                  const Gap(10),
                  _field('seller_title', 'Satıcı Ünvanı'),
                  const Gap(10),
                  _field('seller_address_line1', 'Adres Satırı 1'),
                  const Gap(10),
                  Row(
                    children: [
                      Icon(
                        AppPhosphorIcons.wallet,
                        size: 15,
                        color: AppTheme.textSoft,
                      ),
                      const Gap(6),
                      Text(
                        'Faturada Gösterilecek Banka Hesapları',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: AppTheme.textSoft),
                      ),
                    ],
                  ),
                  const Gap(6),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final bankName = _field(
                        'bank_name',
                        'Banka',
                        dense: true,
                      );
                      final accountName = _field(
                        'bank_account_name',
                        'Hesap Sahibi',
                        dense: true,
                      );
                      final ibanTl = _field(
                        'bank_iban_tl',
                        'TL IBAN',
                        dense: true,
                        hintText: 'TR00 0000 0000 0000 0000 0000 00',
                        inputFormatters: const [_IbanInputFormatter()],
                      );
                      final ibanUsd = _field(
                        'bank_iban_usd',
                        'USD IBAN',
                        dense: true,
                        hintText: 'TR00 0000 0000 0000 0000 0000 00',
                        inputFormatters: const [_IbanInputFormatter()],
                      );
                      // IBAN'lar tek satırda okunaklı kalsın diye geniş
                      // ekranda dörtlü, orta genişlikte ikişerli dizilir.
                      final Widget layout;
                      if (constraints.maxWidth >= 1000) {
                        layout = Row(
                          children: [
                            Expanded(flex: 3, child: bankName),
                            const Gap(8),
                            Expanded(flex: 3, child: accountName),
                            const Gap(8),
                            Expanded(flex: 4, child: ibanTl),
                            const Gap(8),
                            Expanded(flex: 4, child: ibanUsd),
                          ],
                        );
                      } else if (constraints.maxWidth >= 620) {
                        layout = Column(
                          children: [
                            Row(
                              children: [
                                Expanded(child: bankName),
                                const Gap(8),
                                Expanded(child: accountName),
                              ],
                            ),
                            const Gap(8),
                            Row(
                              children: [
                                Expanded(child: ibanTl),
                                const Gap(8),
                                Expanded(child: ibanUsd),
                              ],
                            ),
                          ],
                        );
                      } else {
                        layout = Column(
                          children: [
                            bankName,
                            const Gap(8),
                            accountName,
                            const Gap(8),
                            ibanTl,
                            const Gap(8),
                            ibanUsd,
                          ],
                        );
                      }
                      return layout;
                    },
                  ),
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
                        child: Icon(
                          AppPhosphorIcons.database,
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
                              'SAP MSSQL / VPN Bağlantısı',
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
                            : const Icon(AppPhosphorIcons.link, size: 18),
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
                            : const Icon(AppPhosphorIcons.flowArrow, size: 18),
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
                            : const Icon(
                                AppPhosphorIcons.arrowsCounterClockwise,
                                size: 18,
                              ),
                        label: const Text('SAP’tan Veri Çek'),
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
                            : const Icon(AppPhosphorIcons.flowArrow, size: 18),
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
                            : const Icon(AppPhosphorIcons.gitMerge, size: 18),
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
                            : const Icon(AppPhosphorIcons.floppyDisk, size: 18),
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
      error: (error, _) => _ErrorCard(
        message: 'Ayarlar yüklenemedi.',
        onRetry: () => ref.invalidate(eInvoiceSettingsProvider),
      ),
    );
  }

  Widget _field(
    String key,
    String label, {
    bool obscureText = false,
    int maxLines = 1,
    String? hintText,
    bool dense = false,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextField(
      controller: _c(key),
      obscureText: obscureText,
      maxLines: obscureText ? 1 : maxLines,
      inputFormatters: inputFormatters,
      style: dense ? const TextStyle(fontSize: 13) : null,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        isDense: dense,
        labelStyle: dense ? const TextStyle(fontSize: 13) : null,
        hintStyle: dense ? const TextStyle(fontSize: 12) : null,
        contentPadding: dense
            ? const EdgeInsets.symmetric(horizontal: 10, vertical: 11)
            : null,
      ),
    );
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    setState(() => _saving = true);
    final existing = await _loadLocalEInvoiceSettings();
    final settings = <String, dynamic>{'environment': _environment};
    final environmentEndpoints = _environmentEndpoints[_environment]!;
    _c('api_base_url').text = environmentEndpoints['api_base_url']!;
    _c('token_url').text = environmentEndpoints['token_url']!;
    _c('seller_bank_details').text = _composeBankDetails();
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

  void _hydrateBankFields(String raw) {
    final parsed = _parseBankDetails(raw);
    _c('bank_name').text = parsed.bankName;
    _c('bank_account_name').text = parsed.accountName;
    _c('bank_iban_tl').text = _formatIban(parsed.ibanTl);
    _c('bank_iban_usd').text = _formatIban(parsed.ibanUsd);
  }

  String _composeBankDetails() {
    final bankName = _c('bank_name').text.trim();
    final accountName = _c('bank_account_name').text.trim();
    final ibanTl = _formatIban(_c('bank_iban_tl').text);
    final ibanUsd = _formatIban(_c('bank_iban_usd').text);
    final lines = <String>[
      if (bankName.isNotEmpty ||
          accountName.isNotEmpty ||
          ibanTl.isNotEmpty ||
          ibanUsd.isNotEmpty)
        'Banka Hesap Bilgileri',
      if (bankName.isNotEmpty) bankName,
      if (accountName.isNotEmpty) accountName,
      if (ibanTl.isNotEmpty) 'TL IBAN: $ibanTl',
      if (ibanUsd.isNotEmpty) 'USD IBAN: $ibanUsd',
    ];
    return lines.join('\n');
  }

  ({String bankName, String accountName, String ibanTl, String ibanUsd})
  _parseBankDetails(String raw) {
    final lines = raw
        .split(RegExp(r'\r?\n'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList(growable: false);

    var ibanTl = '';
    var ibanUsd = '';
    final others = <String>[];
    for (final line in lines) {
      final tlMatch = RegExp(
        r'^TL\s*IBAN\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (tlMatch != null) {
        ibanTl = tlMatch.group(1)!.trim();
        continue;
      }
      final usdMatch = RegExp(
        r'^USD\s*IBAN\s*:\s*(.+)$',
        caseSensitive: false,
      ).firstMatch(line);
      if (usdMatch != null) {
        ibanUsd = usdMatch.group(1)!.trim();
        continue;
      }
      if (line.toLowerCase() == 'banka hesap bilgileri') continue;
      others.add(line);
    }

    return (
      bankName: others.isNotEmpty ? others.first : '',
      accountName: others.length > 1 ? others[1] : '',
      ibanTl: ibanTl,
      ibanUsd: ibanUsd,
    );
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
          title: const Text('SAP MSSQL Bağlantısı Başarılı'),
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
        SnackBar(content: Text('SAP bağlantı testi başarısız: $error')),
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
        SnackBar(content: Text('SAP tablo analizi başarısız: $error')),
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
          .timeout(const Duration(minutes: 5));
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('SAP verisi çekilemedi: $error')));
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
          decoded is Map ? decoded['error'] : 'SAP carileri alınamadı.',
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
                            : '${akinsoftCustomers.length} SAP cari tarandı. '
                                  '${suggestions.length} öneri bulundu. Seçili olanlar SAP’a yazılacak.',
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
                                      'SAP: ${source['code'] ?? '-'} / VKN ${source['taxNumber'] ?? '-'}  |  CRM VKN ${customer.vkn ?? '-'}  |  Benzerlik %$score',
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
                          color: AppTheme.surface.withValues(alpha: 0.92),
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
                                'SAP’a yazılan: ${summary['wroteBack'] ?? 0}. '
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
                    : const Icon(AppPhosphorIcons.floppyDisk, size: 18),
                label: Text(
                  savingMatches
                      ? 'Yazılıyor...'
                      : saveSummary != null
                      ? 'Tamamlandı'
                      : 'Seçili Eşleşmeleri SAP’a Yaz (${selected.length})',
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
            '$groups grup içinde $removable çift cari ve $vknless VKN’siz SAP carisi bulundu. Bağlantılar korunarak temizlensin mi?',
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
          Text('SAP’a yazılan: $wroteBack'),
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
  bool _statusSyncing = false;
  int _importCurrent = 0;
  int _importTotal = 0;
  int _importPercent = 0;
  String _importStageLabel = 'Faturalar yazılıyor';
  String _importElapsed = '00:00';
  String? _importInvoiceNumber;
  bool _savingMatches = false;
  bool _showOnlyMatchedInvoices = false;
  String _invoiceCustomerQuery = '';
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
    final warnings = ((data['warnings'] as List?) ?? const [])
        .map((item) => item.toString())
        .where((item) => item.trim().isNotEmpty)
        .toList(growable: false);
    final customers = (data['customers'] as List?) ?? const [];
    final products = (data['products'] as List?) ?? const [];
    final invoices = ((data['invoices'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .toList();
    final customerQuery = _invoiceCustomerQuery.trim();
    final customerFilteredInvoices = customerQuery.isEmpty
        ? invoices
        : invoices
              .where(
                (item) => matchesSearchQuery(
                  [
                    item['customerName'],
                    item['customerCode'],
                    item['taxNumber'],
                    item['invoiceNumber'],
                  ].whereType<Object>().join(' '),
                  customerQuery,
                ),
              )
              .toList();
    final selectedInvoiceRows = invoices
        .where(
          (item) => _selectedInvoices.contains(item['sourceId']?.toString()),
        )
        .toList();
    final selectedCount = selectedInvoiceRows.length;
    final selectedMatchedCount = selectedInvoiceRows
        .where((item) => (item['customerMatch'] as Map?)?['matched'] == true)
        .length;
    final unmatched = invoices
        .where((item) => (item['customerMatch'] as Map?)?['matched'] != true)
        .length;
    final visibleInvoices = _showOnlyMatchedInvoices
        ? customerFilteredInvoices
              .where(
                (item) => (item['customerMatch'] as Map?)?['matched'] == true,
              )
              .toList()
        : customerFilteredInvoices;
    return AlertDialog(
      title: const Text('SAP Verisi Hazır'),
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
                  label: () {
                    final selected =
                        (counts['productsSelected'] as num?)?.toInt() ??
                        (data['products'] is List
                            ? (data['products'] as List).length
                            : (counts['products'] as num?)?.toInt() ?? 0);
                    final unchanged =
                        (counts['productsUnchanged'] as num?)?.toInt() ?? 0;
                    final hizmet = (counts['hizmet'] as num?)?.toInt() ?? 0;
                    final base = hizmet > 0
                        ? '$selected stok/hizmet'
                        : '$selected stok';
                    if (unchanged > 0) {
                      return '$base aktarılacak · $unchanged değişmedi';
                    }
                    return base;
                  }(),
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
            if (warnings.isNotEmpty) ...[
              const Gap(12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'SAP uyarısı',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(6),
                    ...warnings
                        .take(3)
                        .map(
                          (warning) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              warning,
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ),
                        ),
                  ],
                ),
              ),
            ],
            const Gap(16),
            if (_importing) ...[
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$_importStageLabel: $_importCurrent / $_importTotal (%$_importPercent)',
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
              customerQuery: _invoiceCustomerQuery,
              showOnlyMatched: _showOnlyMatchedInvoices,
              onCustomerQueryChanged: (value) {
                setState(() => _invoiceCustomerQuery = value);
              },
              onShowOnlyMatchedChanged: (value) {
                setState(() {
                  _showOnlyMatchedInvoices = value;
                  if (value) {
                    final visibleIds = customerFilteredInvoices
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
              : const Icon(AppPhosphorIcons.link, size: 18),
          label: const Text('Eşleşmeleri Toplu Kaydet'),
        ),
        Tooltip(
          message:
              'Yeni fatura/cari/stok yazmaz; seçili faturaların ödeme ve '
              'durum bilgisini CRM’de günceller.',
          child: OutlinedButton.icon(
            onPressed: _importing || _savingMatches
                ? null
                : () => _importData(statusOnly: true),
            icon: _statusSyncing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(AppPhosphorIcons.arrowsCounterClockwise, size: 18),
            label: Text('Sadece Durum Güncelle ($selectedCount)'),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _importing || _savingMatches ? null : () => _importData(),
          icon: _importing && !_statusSyncing
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(AppPhosphorIcons.checkCircle, size: 18),
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
            'SAP’a yazılan: ${summary['wroteBack'] ?? 0}. '
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

  Future<void> _importData({bool statusOnly = false}) async {
    final invoices = ((widget.data['invoices'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => item.cast<String, dynamic>())
        .where(
          (item) => _selectedInvoices.contains(item['sourceId']?.toString()),
        )
        .toList();
    if (invoices.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            statusOnly
                ? 'Durumu güncellenecek fatura seçilmedi.'
                : 'İçe aktarılacak fatura seçilmedi.',
          ),
        ),
      );
      return;
    }
    // Durum güncellemesi mevcut CRM faturalarını tazelediği için cari
    // eşleşmesi aranmaz; yalnızca tam aktarımda zorunludur.
    if (!statusOnly) {
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
    }
    setState(() {
      _importing = true;
      _statusSyncing = statusOnly;
      _importCurrent = 0;
      _importTotal = invoices.length;
      _importPercent = 0;
      _importStageLabel = statusOnly
          ? 'Fatura durumları güncelleniyor'
          : 'Aktarım hazırlanıyor';
      _importElapsed = '00:00';
      _importInvoiceNumber = null;
    });
    try {
      final payload = Map<String, dynamic>.from(widget.data);
      payload['invoices'] = invoices;
      payload['statusOnly'] = statusOnly;
      payload['customers'] = statusOnly
          ? const <Map<String, dynamic>>[]
          : _relatedCustomers(invoices);
      payload['products'] = statusOnly
          ? const <Map<String, dynamic>>[]
          : ((widget.data['products'] as List?) ?? const [])
                .whereType<Map>()
                .map((item) => item.cast<String, dynamic>())
                .toList();
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
            _importStageLabel =
                job['stageLabel']?.toString() ??
                (statusOnly
                    ? 'Fatura durumları güncelleniyor'
                    : 'Faturalar yazılıyor');
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
      if (statusOnly) {
        final statusSummary =
            (summary['statusSync'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Durum güncellendi: ${statusSummary['updated'] ?? 0} fatura. '
              'Değişmeyen: ${statusSummary['unchanged'] ?? 0}, '
              'CRM’de bulunamayan: ${statusSummary['notFound'] ?? 0}, '
              'ödeme bilgisi okunamayan: ${statusSummary['unreliable'] ?? 0}.',
            ),
          ),
        );
      } else {
        final matches =
            (summary['customerMatches'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        final productsPush =
            (summary['productsPush'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'İçe aktarıldı: ${summary['customers'] ?? 0} cari, '
              '${summary['products'] ?? 0} stok'
              ' (yeni ${summary['productsCreated'] ?? 0} / '
              'güncel ${summary['productsUpdated'] ?? 0}'
              '${(summary['productsSkipped'] ?? 0) > 0 ? ' / atlanan ${summary['productsSkipped']}' : ''}), '
              '${summary['invoices'] ?? 0} fatura. '
              'CRM→SAP stok: +${productsPush['created'] ?? 0}'
              '${(productsPush['matched'] ?? 0) > 0 ? ' / eşleşen ${productsPush['matched']}' : ''}'
              '${(productsPush['failed'] ?? 0) > 0 ? ' / hata ${productsPush['failed']}' : ''}. '
              'Cari eşleşme: kaynak ${matches['source'] ?? 0}, '
              'VKN ${matches['tax'] ?? 0}, kod ${matches['code'] ?? 0}, '
              'yeni ${matches['created'] ?? 0}.',
            ),
          ),
        );
      }
      Navigator.of(context).pop();
    } catch (error) {
      if (!mounted) return;
      final message = error is TimeoutException
          ? 'İşlem beklenenden uzun sürdü. Sunucuda devam etmiş olabilir; birkaç dakika sonra Yenile ile kontrol edin.'
          : statusOnly
          ? 'Durumlar güncellenemedi: $error'
          : 'İçe aktarılamadı: $error';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) {
        setState(() {
          _importing = false;
          _statusSyncing = false;
        });
      }
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

  Future<void> _showCustomerMatchDialog(Map<String, dynamic> invoice) async {
    final sourceId = invoice['customerSourceId']?.toString();
    if (sourceId == null || sourceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu faturada SAP cari kodu yok.')),
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
                              prefixIcon: Icon(
                                AppPhosphorIcons.magnifyingGlass,
                              ),
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
                              : const Icon(
                                  AppPhosphorIcons.magnifyingGlass,
                                  size: 18,
                                ),
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
                                separatorBuilder: (_, _) =>
                                    Divider(height: 1, color: AppTheme.border),
                                itemBuilder: (context, index) {
                                  final customer = customers[index];
                                  final id = customer['id']?.toString() ?? '';
                                  final selected = selectedCustomerId == id;
                                  return ListTile(
                                    selected: selected,
                                    leading: Icon(
                                      selected
                                          ? AppPhosphorIcons.circle
                                          : AppPhosphorIcons.circle,
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
                      : const Icon(AppPhosphorIcons.link, size: 18),
                  label: const Text('Eşleştir ve SAP’a Yaz'),
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
    required this.customerQuery,
    required this.showOnlyMatched,
    required this.onCustomerQueryChanged,
    required this.onShowOnlyMatchedChanged,
    required this.onToggle,
    required this.onSelectAll,
    required this.onClear,
    required this.onMatchCustomer,
  });

  final List<Map<String, dynamic>> invoices;
  final Set<String> selectedInvoices;
  final String customerQuery;
  final bool showOnlyMatched;
  final ValueChanged<String> onCustomerQueryChanged;
  final ValueChanged<bool> onShowOnlyMatchedChanged;
  final void Function(String id, bool selected) onToggle;
  final VoidCallback onSelectAll;
  final VoidCallback onClear;
  final Future<void> Function(Map<String, dynamic> invoice) onMatchCustomer;

  @override
  Widget build(BuildContext context) {
    final searchController = TextEditingController(text: customerQuery)
      ..selection = TextSelection.collapsed(offset: customerQuery.length);
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              final title = Text(
                'Aktarılacak Faturalar',
                style: Theme.of(context).textTheme.titleSmall,
              );
              final search = SizedBox(
                width: narrow ? double.infinity : 260,
                child: TextField(
                  controller: searchController,
                  onChanged: onCustomerQueryChanged,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(AppPhosphorIcons.magnifyingGlass),
                    hintText: 'Cari veya fatura ara',
                    isDense: true,
                  ),
                ),
              );
              final actions = Row(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    child: const Text('Görünenleri Seç'),
                  ),
                  TextButton(onPressed: onClear, child: const Text('Temizle')),
                ],
              );
              return Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: narrow
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          title,
                          const Gap(8),
                          search,
                          const Gap(8),
                          SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: actions,
                          ),
                        ],
                      )
                    : Row(
                        children: [
                          Expanded(child: title),
                          search,
                          const Gap(10),
                          actions,
                        ],
                      ),
              );
            },
          ),
          if (invoices.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Bu filtreye uygun fatura bulunamadı.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            ),
          Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            color: AppTheme.surfaceMuted,
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
                  Divider(height: 1, color: AppTheme.border),
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
                                icon: const Icon(
                                  AppPhosphorIcons.link,
                                  size: 16,
                                ),
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
        return 'SAP eşleme';
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
      title: const Text('SAP Tablo Analizi'),
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
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        color: AppTheme.surface,
        boxShadow: AppTheme.cardShadow,
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
            Text(error, style: TextStyle(color: AppTheme.error)),
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

String _formatIban(String value) {
  final raw = value.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
  if (raw.isEmpty) return '';
  final buffer = StringBuffer();
  for (var i = 0; i < raw.length; i++) {
    if (i > 0 && i % 4 == 0) buffer.write(' ');
    buffer.write(raw[i]);
  }
  return buffer.toString();
}

/// IBAN girişini büyük harfe çevirip dörtlü gruplara ayırır.
class _IbanInputFormatter extends TextInputFormatter {
  const _IbanInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatIban(newValue.text);
    final typedBeforeCursor = newValue.text
        .substring(0, newValue.selection.end.clamp(0, newValue.text.length))
        .toUpperCase()
        .replaceAll(RegExp('[^A-Z0-9]'), '')
        .length;
    var offset = 0;
    var seen = 0;
    while (offset < formatted.length && seen < typedBeforeCursor) {
      if (formatted[offset] != ' ') seen += 1;
      offset += 1;
    }
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: offset),
    );
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
  'seller_bank_details',
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
        final wide = constraints.maxWidth >= 700;
        return GridView.count(
          crossAxisCount: wide ? 5 : 2,
          mainAxisExtent: 72,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final metric in metrics)
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                color: AppTheme.surface,
                child: Row(
                  children: [
                    AppDenseLeadingIcon(
                      icon: metric.icon,
                      color: metric.accent,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.label,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                          ),
                          Text(
                            metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.15,
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
    );
  }
}

class _Metric {
  const _Metric(this.label, this.value, this.icon, this.accent);

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
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
    final fg = AppTheme.textSoft;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.72)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: fg),
          const Gap(6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: fg,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return EmptyStateCard(
      icon: AppPhosphorIcons.warningCircle,
      title: 'Bir şeyler ters gitti',
      message: message,
      action: onRetry == null
          ? null
          : OutlinedButton.icon(
              onPressed: onRetry,
              icon: const Icon(
                AppPhosphorIcons.arrowsCounterClockwise,
                size: 18,
              ),
              label: const Text('Tekrar Dene'),
            ),
    );
  }
}

double _parseDecimal(String value) {
  final trimmed = value.trim().replaceAll(' ', '');
  if (trimmed.isEmpty) return 0;
  // TR: 1.234,56 — mixed separators → strip thousands dots
  if (trimmed.contains(',') && trimmed.contains('.')) {
    return double.tryParse(trimmed.replaceAll('.', '').replaceAll(',', '.')) ??
        0;
  }
  // TR decimal comma: 12,50
  if (trimmed.contains(',')) {
    return double.tryParse(trimmed.replaceAll(',', '.')) ?? 0;
  }
  // Plain / US: 12.50
  return double.tryParse(trimmed) ?? 0;
}

double _roundMoney(double value) => (value * 100).roundToDouble() / 100;

const _stockUnitOptions = ['Adet', 'Kg', 'Lt', 'Mt', 'Saat'];
const _stockTaxRateOptions = <double>[0, 5, 10, 16, 20];

/// Maps SAP/WOLVOX unit labels (e.g. ADET) onto dropdown values (Adet).
String _coerceStockUnit(String? value) {
  final raw = (value ?? '').trim();
  if (raw.isEmpty) return 'Adet';
  for (final option in _stockUnitOptions) {
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

double _coerceStockTaxRate(double? value) {
  final rate = value ?? 5;
  for (final option in _stockTaxRateOptions) {
    if ((option - rate).abs() < 0.001) return option;
  }
  return 20;
}

/// Stock/hizmet sale currency from product.currency (WOLVOX HESAP / DOVIZ_BIRIMI).
String _stockSaleCurrency(Product product) {
  final value = product.currency.trim().toUpperCase();
  if (value.isEmpty) return 'USD';
  if (value == 'USD' || value == 'TRY' || value == 'EUR' || value == 'GBP') {
    return value;
  }
  if (value == '\$' || value.contains('DOLAR') || value.contains('DOVIZ')) {
    return 'USD';
  }
  if (value == 'TL' || value.contains('TURK')) return 'TRY';
  return 'USD';
}

/// Dialog only offers USD/TRY; map other codes to a safe dropdown value.
String _coerceStockDialogCurrency(String? value) {
  final code = (value ?? 'USD').trim().toUpperCase();
  if (code == 'TRY' || code == 'TL') return 'TRY';
  return 'USD';
}

String _currencySymbol(String currency) {
  return switch (currency.trim().toUpperCase()) {
    'TRY' => '₺',
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    final code when code.isNotEmpty => '$code ',
    _ => '\$',
  };
}

String _formatProductMoney(double amount, String currency) {
  final code = currency.trim().toUpperCase();
  final effective = code.isEmpty ? 'USD' : code;
  return NumberFormat.currency(
    locale: 'tr_TR',
    symbol: _currencySymbol(effective),
    decimalDigits: 2,
  ).format(amount);
}

class _InlineStockPriceCell extends StatefulWidget {
  const _InlineStockPriceCell({
    required this.product,
    required this.editing,
    required this.onStartEdit,
    required this.onCancelEdit,
    required this.onSave,
  });

  final Product product;
  final bool editing;
  final VoidCallback onStartEdit;
  final VoidCallback onCancelEdit;
  final Future<void> Function({
    required double exclusiveSalePrice,
    required String currency,
  })
  onSave;

  @override
  State<_InlineStockPriceCell> createState() => _InlineStockPriceCellState();
}

class _InlineStockPriceCellState extends State<_InlineStockPriceCell> {
  late final TextEditingController _controller;
  late String _currency;
  bool _pricesIncludeVat = false;
  bool _saving = false;

  Product get _product => widget.product;

  @override
  void initState() {
    super.initState();
    _currency = _stockSaleCurrency(_product);
    _controller = TextEditingController(
      text: _product.salePrice.toStringAsFixed(2),
    );
  }

  @override
  void didUpdateWidget(covariant _InlineStockPriceCell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editing && !oldWidget.editing) {
      _currency = _stockSaleCurrency(widget.product);
      _pricesIncludeVat = false;
      _controller.text = widget.product.salePrice.toStringAsFixed(2);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _controller.text.length,
        );
      });
    }
    if (!widget.editing &&
        (oldWidget.product.salePrice != widget.product.salePrice ||
            oldWidget.product.currency != widget.product.currency)) {
      _currency = _stockSaleCurrency(widget.product);
      _controller.text = widget.product.salePrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final entered = _parseDecimal(_controller.text);
      final taxRate = _product.taxRate;
      final exclusive = _pricesIncludeVat && taxRate > 0
          ? entered / (1 + taxRate / 100)
          : entered;
      await widget.onSave(
        exclusiveSalePrice: _roundMoney(exclusive),
        currency: _currency == 'TRY' ? 'TRY' : _currency,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fiyat: ${_formatProductMoney(_roundMoney(exclusive), _currency)}',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Fiyat kaydedilemedi: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayCurrency = _stockSaleCurrency(_product);
    if (!widget.editing) {
      return InkWell(
        onTap: widget.onStartEdit,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Text(
            _formatProductMoney(_product.salePrice, displayCurrency),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                enabled: !_saving,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  height: 1.2,
                ),
                decoration: const InputDecoration(
                  isDense: false,
                  hintText: '0.00',
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _submit(),
              ),
            ),
            const Gap(8),
            SizedBox(
              width: 88,
              child: DropdownButtonFormField<String>(
                initialValue: _currency,
                isDense: true,
                items: const [
                  DropdownMenuItem(value: 'USD', child: Text('USD')),
                  DropdownMenuItem(value: 'TRY', child: Text('TL')),
                ],
                onChanged: _saving
                    ? null
                    : (v) => setState(() => _currency = v ?? 'USD'),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 12,
                  ),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const Gap(4),
            IconButton(
              tooltip: 'Kaydet',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(AppPhosphorIcons.check, size: 22),
            ),
            IconButton(
              tooltip: 'İptal',
              visualDensity: VisualDensity.compact,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
              onPressed: _saving ? null : widget.onCancelEdit,
              icon: const Icon(AppPhosphorIcons.x, size: 20),
            ),
          ],
        ),
        const Gap(4),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: Text(
            _pricesIncludeVat ? 'KDV dahil' : 'KDV hariç',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          value: _pricesIncludeVat,
          onChanged: _saving
              ? null
              : (value) {
                  if (value == _pricesIncludeVat) return;
                  final current = _parseDecimal(_controller.text);
                  final taxRate = _product.taxRate;
                  if (taxRate > 0 && current > 0) {
                    final converted = _pricesIncludeVat
                        ? current / (1 + taxRate / 100)
                        : current * (1 + taxRate / 100);
                    _controller.text = _roundMoney(
                      converted,
                    ).toStringAsFixed(2);
                  }
                  setState(() => _pricesIncludeVat = value);
                },
        ),
      ],
    );
  }
}

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final trimmed = (url ?? '').trim();
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.surfaceMuted,
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.7)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: trimmed.isEmpty
            ? Icon(LucideIcons.image, size: 14, color: AppTheme.textMuted)
            : Image.network(
                trimmed,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  LucideIcons.image,
                  size: 14,
                  color: AppTheme.textMuted,
                ),
              ),
      ),
    );
  }
}
