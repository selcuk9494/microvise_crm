import 'package:excel/excel.dart' as excel;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../billing/billing_screen.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import '../definitions/definitions_screen.dart';
import 'line_stock_tab.dart';

final productSearchProvider =
    NotifierProvider<ProductSearchNotifier, String>(ProductSearchNotifier.new);
final showPassiveProvider =
    NotifierProvider<ShowPassiveNotifier, bool>(ShowPassiveNotifier.new);
final lineOperatorFilterProvider =
    NotifierProvider<LineOperatorFilterNotifier, LineOperatorFilter>(
  LineOperatorFilterNotifier.new,
);
final licenseCompanyFilterProvider =
    NotifierProvider<LicenseCompanyFilterNotifier, String>(
  LicenseCompanyFilterNotifier.new,
);
final lineCustomerFilterProvider =
    NotifierProvider<LineCustomerFilterNotifier, String>(
  LineCustomerFilterNotifier.new,
);
final licenseCustomerFilterProvider =
    NotifierProvider<LicenseCustomerFilterNotifier, String>(
  LicenseCustomerFilterNotifier.new,
);
final lineEndsFromProvider =
    NotifierProvider<LineEndsFromNotifier, DateTime?>(LineEndsFromNotifier.new);
final lineEndsToProvider =
    NotifierProvider<LineEndsToNotifier, DateTime?>(LineEndsToNotifier.new);
final licenseEndsFromProvider =
    NotifierProvider<LicenseEndsFromNotifier, DateTime?>(
  LicenseEndsFromNotifier.new,
);
final licenseEndsToProvider =
    NotifierProvider<LicenseEndsToNotifier, DateTime?>(LicenseEndsToNotifier.new);
final totalsCustomerSearchProvider =
    NotifierProvider<TotalsCustomerSearchNotifier, String>(
  TotalsCustomerSearchNotifier.new,
);

class ProductSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class ShowPassiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

enum LineOperatorFilter { all, turkcell, telsim }

class LineOperatorFilterNotifier extends Notifier<LineOperatorFilter> {
  @override
  LineOperatorFilter build() => LineOperatorFilter.all;

  void set(LineOperatorFilter value) => state = value;
}

class LicenseCompanyFilterNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void set(String value) => state = value.trim().isEmpty ? 'all' : value.trim();
}

class LineCustomerFilterNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class LicenseCustomerFilterNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

class LineEndsFromNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? value) => state = value;
}

class LineEndsToNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? value) => state = value;
}

class LicenseEndsFromNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? value) => state = value;
}

class LicenseEndsToNotifier extends Notifier<DateTime?> {
  @override
  DateTime? build() => null;

  void set(DateTime? value) => state = value;
}

class TotalsCustomerSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final issuedLinesProvider = FutureProvider<List<IssuedLine>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);
  final operatorFilter = ref.watch(lineOperatorFilterProvider);
  final customerFilter = ref.watch(lineCustomerFilterProvider).trim();
  final endsFrom = ref.watch(lineEndsFromProvider);
  final endsTo = ref.watch(lineEndsToProvider);

  String? isoDate(DateTime? d) {
    final s = d?.toIso8601String();
    return s?.substring(0, 10);
  }

  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'products_lines',
        if (search.isNotEmpty) 'search': search,
        if (operatorFilter != LineOperatorFilter.all)
          'operator': operatorFilter == LineOperatorFilter.turkcell
              ? 'turkcell'
              : 'telsim',
        if (customerFilter.isNotEmpty) 'customer': customerFilter,
        if (isoDate(endsFrom) != null) 'endsFrom': isoDate(endsFrom)!,
        if (isoDate(endsTo) != null) 'endsTo': isoDate(endsTo)!,
        if (isAdmin) 'showPassive': showPassive.toString(),
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(IssuedLine.fromJson)
        .toList(growable: false);
  }

  if (client == null) return const [];

  var q = client
      .from('lines')
      .select(
        'id,label,number,sim_number,operator,starts_at,ends_at,expires_at,is_active,customer_id,branch_id,customers(name),branches(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if (search.isNotEmpty) {
    q = q.or(
      'number.ilike.%$search%,sim_number.ilike.%$search%,customers.name.ilike.%$search%,branches.name.ilike.%$search%',
    );
  }

  if (customerFilter.isNotEmpty) {
    q = q.ilike('customers.name', '%$customerFilter%');
  }

  if (operatorFilter != LineOperatorFilter.all) {
    q = q.eq(
      'operator',
      operatorFilter == LineOperatorFilter.turkcell ? 'turkcell' : 'telsim',
    );
  }

  if (endsFrom != null) {
    q = q.gte('ends_at', isoDate(endsFrom)!);
  }
  if (endsTo != null) {
    q = q.lte('ends_at', isoDate(endsTo)!);
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);

  return (rows as List).map((e) {
    final map = e as Map<String, dynamic>;
    final customer = map['customers'] as Map<String, dynamic>?;
    final branch = map['branches'] as Map<String, dynamic>?;
    return IssuedLine.fromJson({
      ...map,
      'customer_name': customer?['name'],
      'branch_name': branch?['name'],
    });
  }).toList(growable: false);
});

final issuedLicensesProvider = FutureProvider<List<IssuedLicense>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);
  final companyFilter = ref.watch(licenseCompanyFilterProvider);
  final customerFilter = ref.watch(licenseCustomerFilterProvider).trim();
  final endsFrom = ref.watch(licenseEndsFromProvider);
  final endsTo = ref.watch(licenseEndsToProvider);

  String? isoDate(DateTime? d) {
    final s = d?.toIso8601String();
    return s?.substring(0, 10);
  }

  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'products_licenses',
        if (search.isNotEmpty) 'search': search,
        if (companyFilter != 'all') 'softwareCompanyId': companyFilter,
        if (customerFilter.isNotEmpty) 'customer': customerFilter,
        if (isoDate(endsFrom) != null) 'endsFrom': isoDate(endsFrom)!,
        if (isoDate(endsTo) != null) 'endsTo': isoDate(endsTo)!,
        if (isAdmin) 'showPassive': showPassive.toString(),
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(IssuedLicense.fromJson)
        .toList(growable: false);
  }

  if (client == null) return const [];

  var q = client
      .from('licenses')
      .select(
        'id,name,license_type,software_company_id,registry_number,starts_at,ends_at,is_active,customer_id,customers(name),software_companies(name)',
      );

  if (!(isAdmin && showPassive)) {
    q = q.eq('is_active', true);
  }

  if (search.isNotEmpty) {
    q = q.or(
      'name.ilike.%$search%,customers.name.ilike.%$search%,software_companies.name.ilike.%$search%',
    );
  }

  if (customerFilter.isNotEmpty) {
    q = q.ilike('customers.name', '%$customerFilter%');
  }

  if (companyFilter != 'all') {
    if (companyFilter == 'unknown') {
      q = q.isFilter('software_company_id', null);
    } else {
      q = q.eq('software_company_id', companyFilter);
    }
  }

  if (endsFrom != null) {
    q = q.gte('ends_at', isoDate(endsFrom)!);
  }
  if (endsTo != null) {
    q = q.lte('ends_at', isoDate(endsTo)!);
  }

  final rows = await q.order('ends_at', ascending: true).limit(500);
  return (rows as List).map((e) {
    final map = e as Map<String, dynamic>;
    final customer = map['customers'] as Map<String, dynamic>?;
    final company = map['software_companies'] as Map<String, dynamic>?;
    return IssuedLicense.fromJson({
      ...map,
      'customer_name': customer?['name'],
      'software_company_name': company?['name'],
    });
  }).toList(growable: false);
});

class CustomerTotalsRow {
  const CustomerTotalsRow({
    required this.customerId,
    required this.customerName,
    required this.linesTotal,
    required this.linesTurkcell,
    required this.linesTelsim,
    required this.gmp3Total,
  });

  final String customerId;
  final String customerName;
  final int linesTotal;
  final int linesTurkcell;
  final int linesTelsim;
  final int gmp3Total;

  factory CustomerTotalsRow.fromJson(Map<String, dynamic> json) {
    return CustomerTotalsRow(
      customerId: json['customer_id']?.toString() ?? '',
      customerName: json['customer_name']?.toString() ?? '',
      linesTotal: (json['lines_total'] as int?) ?? 0,
      linesTurkcell: (json['lines_turkcell'] as int?) ?? 0,
      linesTelsim: (json['lines_telsim'] as int?) ?? 0,
      gmp3Total: (json['gmp3_total'] as int?) ?? 0,
    );
  }
}

final issuedCustomerTotalsProvider =
    FutureProvider.autoDispose<List<CustomerTotalsRow>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];

  final search = ref.watch(totalsCustomerSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);

  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'products_customer_totals',
      if (search.isNotEmpty) 'search': search,
      if (isAdmin) 'showPassive': showPassive.toString(),
    },
  );

  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(CustomerTotalsRow.fromJson)
      .toList(growable: false);
});

final customersLookupProvider = FutureProvider<List<CustomerLookup>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'customers_lookup'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CustomerLookup.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('customers')
      .select('id,name,is_active')
      .order('name');
  return (rows as List)
      .map((e) => CustomerLookup.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

class ProductsLicensesStats {
  const ProductsLicensesStats({
    required this.gmp3Total,
    required this.byCompany,
    required this.byCustomer,
  });

  final int gmp3Total;
  final List<Map<String, dynamic>> byCompany;
  final List<Map<String, dynamic>> byCustomer;

  factory ProductsLicensesStats.fromJson(Map<String, dynamic> json) {
    final byCompany = ((json['by_company'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    final byCustomer = ((json['by_customer'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
    return ProductsLicensesStats(
      gmp3Total: (json['gmp3_total'] as int?) ?? 0,
      byCompany: byCompany,
      byCustomer: byCustomer,
    );
  }
}

final issuedLicensesStatsProvider =
    FutureProvider.autoDispose<ProductsLicensesStats?>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return null;

  final search = ref.watch(productSearchProvider).trim();
  final showPassive = ref.watch(showPassiveProvider);
  final isAdmin = ref.watch(isAdminProvider);

  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'products_licenses_stats',
      if (search.isNotEmpty) 'search': search,
      if (isAdmin) 'showPassive': showPassive.toString(),
    },
  );

  return ProductsLicensesStats.fromJson(response);
});

class ProductsScreen extends ConsumerWidget {
  const ProductsScreen({super.key});

  excel.CellValue _cell(Object? v) {
    final text = (v ?? '').toString();
    return excel.TextCellValue(text);
  }

  String _operatorLabel(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v == 'turkcell') return 'TURKCELL';
    if (v == 'telsim' || v == 'vodafone') return 'TELSİM';
    return '-';
  }

  Future<void> _exportExcel({
    required BuildContext context,
    required List<IssuedLine> lines,
    required List<IssuedLicense> licenses,
  }) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışarı aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final book = excel.Excel.createExcel();
    final hats = book['Hatlar'];
    final gmp3 = book['GMP3'];

    hats.appendRow([
      _cell('customer_name'),
      _cell('line_number'),
      _cell('operator'),
      _cell('sim_number'),
      _cell('ends_at'),
      _cell('is_active'),
    ]);
    for (final l in lines) {
      hats.appendRow([
        _cell(l.customerName ?? ''),
        _cell(l.number ?? ''),
        _cell(_operatorLabel(l.operator)),
        _cell(l.simNumber ?? ''),
        _cell(l.endsAt == null ? '' : l.endsAt!.toIso8601String().substring(0, 10)),
        _cell(l.isActive.toString()),
      ]);
    }

    gmp3.appendRow([
      _cell('customer_name'),
      _cell('license_name'),
      _cell('software_company'),
      _cell('registry_number'),
      _cell('ends_at'),
      _cell('is_active'),
    ]);
    for (final lic in licenses) {
      gmp3.appendRow([
        _cell(lic.customerName ?? ''),
        _cell(lic.name),
        _cell(lic.softwareCompanyName ?? ''),
        _cell(lic.registryNumber ?? ''),
        _cell(lic.endsAt == null ? '' : lic.endsAt!.toIso8601String().substring(0, 10)),
        _cell(lic.isActive.toString()),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'hat_lisanslar.xlsx');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final showPassive = ref.watch(showPassiveProvider);
    final linesAsync = ref.watch(issuedLinesProvider);
    final licensesAsync = ref.watch(issuedLicensesProvider);
    final licensesStatsAsync = ref.watch(issuedLicensesStatsProvider);

    final lines = linesAsync.asData?.value ?? const <IssuedLine>[];
    final licenses = licensesAsync.asData?.value ?? const <IssuedLicense>[];

    final turkcellCount = lines
        .where((e) => (e.operator ?? '').trim().toLowerCase() == 'turkcell')
        .length;
    final telsimCount = lines
        .where((e) => (e.operator ?? '').trim().toLowerCase() == 'telsim')
        .length;
    final stats = licensesStatsAsync.asData?.value;
    final gmp3Total = stats?.gmp3Total ??
        licenses.where((e) => e.licenseType.trim().toLowerCase() == 'gmp3').length;

    String displayNameOrUnknown(String? value) {
      final v = (value ?? '').trim();
      return v.isEmpty ? 'Belirsiz' : v;
    }

    final gmp3CompanyEntries = stats == null
        ? <MapEntry<String, int>>[]
        : stats.byCompany
            .map((e) {
              final name = displayNameOrUnknown(e['software_company_name']?.toString());
              final total = (e['total'] as int?) ?? 0;
              return MapEntry(name, total);
            })
            .where((e) => e.value > 0)
            .toList(growable: false);

    final gmp3CustomerEntries = stats == null
        ? <MapEntry<String, int>>[]
        : stats.byCustomer
            .map((e) {
              final name = displayNameOrUnknown(e['customer_name']?.toString());
              final total = (e['total'] as int?) ?? 0;
              return MapEntry(name, total);
            })
            .where((e) => e.value > 0)
            .toList(growable: false);

    String shortCompany(String input) {
      final s = input.trim();
      if (s.length <= 14) return s;
      return '${s.substring(0, 13)}…';
    }
    String shortCustomer(String input) {
      final s = input.trim();
      if (s.length <= 16) return s;
      return '${s.substring(0, 15)}…';
    }

    return DefaultTabController(
      length: 4,
      child: AppPageLayout(
        title: 'Hat & Lisanslar',
        subtitle: 'Verilen hatlar ve GMP3 lisansları tek listede.',
        compactHeader: true,
        actions: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (linesAsync is AsyncData) ...[
                  AppBadge(
                    label: 'TURKCELL: $turkcellCount',
                    tone: AppBadgeTone.primary,
                    dense: true,
                  ),
                  const SizedBox(width: 8),
                  AppBadge(
                    label: 'TELSİM: $telsimCount',
                    tone: AppBadgeTone.warning,
                    dense: true,
                  ),
                  const SizedBox(width: 8),
                ],
                if (licensesAsync is AsyncData) ...[
                  AppBadge(
                    label: 'GMP3: $gmp3Total',
                    tone: AppBadgeTone.success,
                    dense: true,
                  ),
                  const SizedBox(width: 8),
                ],
                if (gmp3CompanyEntries.isNotEmpty) ...[
                  for (final e in gmp3CompanyEntries.take(3)) ...[
                    AppBadge(
                      label: '${shortCompany(e.key)}: ${e.value}',
                      tone: AppBadgeTone.neutral,
                      dense: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (gmp3CompanyEntries.length > 3) ...[
                    PopupMenuButton<String>(
                      tooltip: 'GMP3 Firma Toplamları',
                      itemBuilder: (context) => [
                        for (final e in gmp3CompanyEntries)
                          PopupMenuItem(
                            value: e.key,
                            child: Text('${e.key} (${e.value})'),
                          ),
                      ],
                      child: AppBadge(
                        label: '+${gmp3CompanyEntries.length - 3}',
                        tone: AppBadgeTone.neutral,
                        dense: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
                if (gmp3CustomerEntries.isNotEmpty) ...[
                  for (final e in gmp3CustomerEntries.take(2)) ...[
                    AppBadge(
                      label: '${shortCustomer(e.key)}: ${e.value}',
                      tone: AppBadgeTone.neutral,
                      dense: true,
                    ),
                    const SizedBox(width: 8),
                  ],
                  if (gmp3CustomerEntries.length > 2) ...[
                    PopupMenuButton<String>(
                      tooltip: 'GMP3 Müşteri Toplamları',
                      itemBuilder: (context) => [
                        for (final e in gmp3CustomerEntries)
                          PopupMenuItem(
                            value: e.key,
                            child: Text('${e.key} (${e.value})'),
                          ),
                      ],
                      child: AppBadge(
                        label: 'Müşteri +${gmp3CustomerEntries.length - 2}',
                        tone: AppBadgeTone.neutral,
                        dense: true,
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
                PopupMenuButton<String>(
                  tooltip: 'Dışarı Aktar',
                  onSelected: (value) async {
                    if (value == 'export') {
                      await _exportExcel(
                        context: context,
                        lines: lines,
                        licenses: licenses,
                      );
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'export',
                      child: Text('Dışarı Aktar (Excel)'),
                    ),
                  ],
                  child: const SizedBox(
                    width: 36,
                    height: 34,
                    child: Icon(Icons.download_rounded),
                  ),
                ),
              ],
            ),
          ),
        ],
        body: Column(
          children: [
            Expanded(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isNarrow = constraints.maxWidth < 980;
                        final searchField = SizedBox(
                          width: isNarrow ? double.infinity : 320,
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: 'Ara (müşteri, hat, SIM, firma...)',
                              prefixIcon: Icon(Icons.search_rounded),
                              isDense: true,
                            ),
                            onChanged: (v) =>
                                ref.read(productSearchProvider.notifier).set(v),
                          ),
                        );

                        final passiveToggle = isAdmin
                            ? FilledButton.tonalIcon(
                                onPressed: () => ref
                                    .read(showPassiveProvider.notifier)
                                    .set(!showPassive),
                                icon: const Icon(Icons.visibility_rounded, size: 18),
                                label:
                                    Text(showPassive ? 'Kayıt: Tümü' : 'Kayıt: Aktif'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A)
                                      .withValues(alpha: 0.12),
                                  foregroundColor: const Color(0xFF14532D),
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink();

                        if (isNarrow) {
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              children: [
                                searchField,
                                if (isAdmin) ...[
                                  const Gap(10),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: passiveToggle,
                                  ),
                                ],
                                const Gap(10),
                                const TabBar(
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  labelPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  tabs: [
                                    Tab(text: 'Hatlar'),
                                    Tab(text: 'Lisanslar (GMP3)'),
                                    Tab(text: 'Toplamlar'),
                                    Tab(text: 'Hat Stok'),
                                  ],
                                ),
                              ],
                            ),
                          );
                        }

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Row(
                            children: [
                              const Expanded(
                                child: TabBar(
                                  isScrollable: true,
                                  tabAlignment: TabAlignment.start,
                                  labelPadding: EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  tabs: [
                                    Tab(text: 'Hatlar'),
                                    Tab(text: 'Lisanslar (GMP3)'),
                                    Tab(text: 'Toplamlar'),
                                    Tab(text: 'Hat Stok'),
                                  ],
                                ),
                              ),
                              const Gap(10),
                              searchField,
                              if (isAdmin) ...[
                                const Gap(10),
                                passiveToggle,
                              ],
                            ],
                          ),
                        );
                      },
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _LinesTab(
                            isAdmin: isAdmin,
                            exportAll: () => _exportExcel(
                              context: context,
                              lines: lines,
                              licenses: licenses,
                            ),
                          ),
                          _LicensesTab(
                            isAdmin: isAdmin,
                            exportAll: () => _exportExcel(
                              context: context,
                              lines: lines,
                              licenses: licenses,
                            ),
                          ),
                          const _TotalsTab(),
                          const LineStockTab(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.tone});

  final String title;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => const Color(0xFF64748B),
      AppBadgeTone.primary => AppTheme.primary,
    };
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Gap(10),
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LinesTab extends ConsumerStatefulWidget {
  const _LinesTab({required this.isAdmin, required this.exportAll});

  final bool isAdmin;
  final VoidCallback exportAll;

  @override
  ConsumerState<_LinesTab> createState() => _LinesTabState();
}

class _LinesTabState extends ConsumerState<_LinesTab> {
  late final TextEditingController _customerController;

  @override
  void initState() {
    super.initState();
    _customerController =
        TextEditingController(text: ref.read(lineCustomerFilterProvider));
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final linesAsync = ref.watch(issuedLinesProvider);
    final operatorFilter = ref.watch(lineOperatorFilterProvider);
    final endsFrom = ref.watch(lineEndsFromProvider);
    final endsTo = ref.watch(lineEndsToProvider);
    final df = DateFormat('d MMM y', 'tr_TR');

    String dateLabel(DateTime? d) => d == null ? 'Seç' : df.format(d);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 980;
                final operatorField = SizedBox(
                  width: narrow ? double.infinity : 220,
                  child: DropdownButtonFormField<LineOperatorFilter>(
                    initialValue: operatorFilter,
                    items: const [
                      DropdownMenuItem(
                        value: LineOperatorFilter.all,
                        child: Text('Tüm Operatörler'),
                      ),
                      DropdownMenuItem(
                        value: LineOperatorFilter.turkcell,
                        child: Text('TURKCELL'),
                      ),
                      DropdownMenuItem(
                        value: LineOperatorFilter.telsim,
                        child: Text('TELSİM'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(lineOperatorFilterProvider.notifier).set(v);
                    },
                    decoration: const InputDecoration(labelText: 'Operatör'),
                  ),
                );

                final customerField = SizedBox(
                  width: narrow ? double.infinity : 320,
                  child: TextField(
                    controller: _customerController,
                    onChanged: ref.read(lineCustomerFilterProvider.notifier).set,
                    decoration: const InputDecoration(
                      labelText: 'Müşteri',
                      hintText: 'Müşteri adına göre',
                      prefixIcon: Icon(Icons.storefront_rounded),
                    ),
                  ),
                );

                final fromBtn = SizedBox(
                  width: narrow ? double.infinity : 200,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endsFrom ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      ref
                          .read(lineEndsFromProvider.notifier)
                          .set(DateTime(picked.year, picked.month, picked.day));
                    },
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text('Bitiş ≥ ${dateLabel(endsFrom)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                );
                final toBtn = SizedBox(
                  width: narrow ? double.infinity : 200,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endsTo ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      ref
                          .read(lineEndsToProvider.notifier)
                          .set(DateTime(picked.year, picked.month, picked.day));
                    },
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text('Bitiş ≤ ${dateLabel(endsTo)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                );

                final clearBtn = OutlinedButton.icon(
                  onPressed: () {
                    _customerController.text = '';
                    ref.read(lineCustomerFilterProvider.notifier).set('');
                    ref.read(lineEndsFromProvider.notifier).set(null);
                    ref.read(lineEndsToProvider.notifier).set(null);
                    ref
                        .read(lineOperatorFilterProvider.notifier)
                        .set(LineOperatorFilter.all);
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Temizle'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                final exportBtn = OutlinedButton.icon(
                  onPressed: widget.exportAll,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Dışarı Aktar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                if (narrow) {
                  return Column(
                    children: [
                      operatorField,
                      const Gap(8),
                      customerField,
                      const Gap(8),
                      fromBtn,
                      const Gap(8),
                      toBtn,
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: clearBtn),
                          const Gap(8),
                          Expanded(child: exportBtn),
                        ],
                      ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      operatorField,
                      const Gap(8),
                      customerField,
                      const Gap(8),
                      fromBtn,
                      const Gap(8),
                      toBtn,
                      const Gap(8),
                      clearBtn,
                      const Gap(8),
                      exportBtn,
                    ],
                  ),
                );
              },
            ),
          ),
          const Gap(8),
          Expanded(
            child: linesAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                if (operatorFilter == LineOperatorFilter.all) {
                  final turkcell = items
                      .where((e) =>
                          (e.operator ?? '').trim().toLowerCase() == 'turkcell')
                      .toList(growable: false);
                  final telsim = items
                      .where((e) =>
                          (e.operator ?? '').trim().toLowerCase() == 'telsim')
                      .toList(growable: false);
                  final other = items
                      .where((e) {
                        final op = (e.operator ?? '').trim().toLowerCase();
                        return op != 'turkcell' && op != 'telsim';
                      })
                      .toList(growable: false);

                  return Scrollbar(
                    thumbVisibility: true,
                    child: ListView(
                      padding: const EdgeInsets.only(bottom: 120),
                      children: [
                        if (turkcell.isNotEmpty) ...[
                          const _SectionHeader(
                            title: 'TURKCELL',
                            tone: AppBadgeTone.primary,
                          ),
                          const Gap(10),
                          for (final item in turkcell) ...[
                            _LineRow(item: item, isAdmin: widget.isAdmin),
                            const Gap(10),
                          ],
                          const Gap(6),
                        ],
                        if (telsim.isNotEmpty) ...[
                          const _SectionHeader(
                            title: 'TELSİM',
                            tone: AppBadgeTone.warning,
                          ),
                          const Gap(10),
                          for (final item in telsim) ...[
                            _LineRow(item: item, isAdmin: widget.isAdmin),
                            const Gap(10),
                          ],
                          const Gap(6),
                        ],
                        if (other.isNotEmpty) ...[
                          const _SectionHeader(
                            title: 'Diğer',
                            tone: AppBadgeTone.neutral,
                          ),
                          const Gap(10),
                          for (final item in other) ...[
                            _LineRow(item: item, isAdmin: widget.isAdmin),
                            const Gap(10),
                          ],
                        ],
                      ],
                    ),
                  );
                }

                return Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Gap(10),
                    itemBuilder: (context, index) => _LineRow(
                      item: items[index],
                      isAdmin: widget.isAdmin,
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Hatlar yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensesTab extends ConsumerStatefulWidget {
  const _LicensesTab({required this.isAdmin, required this.exportAll});

  final bool isAdmin;
  final VoidCallback exportAll;

  @override
  ConsumerState<_LicensesTab> createState() => _LicensesTabState();
}

class _LicensesTabState extends ConsumerState<_LicensesTab> {
  late final TextEditingController _customerController;

  @override
  void initState() {
    super.initState();
    _customerController =
        TextEditingController(text: ref.read(licenseCustomerFilterProvider));
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final licensesAsync = ref.watch(issuedLicensesProvider);
    final companyFilter = ref.watch(licenseCompanyFilterProvider);
    final endsFrom = ref.watch(licenseEndsFromProvider);
    final endsTo = ref.watch(licenseEndsToProvider);
    final companiesAsync = ref.watch(softwareCompaniesProvider);
    final df = DateFormat('d MMM y', 'tr_TR');

    String dateLabel(DateTime? d) => d == null ? 'Seç' : df.format(d);

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 980;
                final customerField = SizedBox(
                  width: narrow ? double.infinity : 320,
                  child: TextField(
                    controller: _customerController,
                    onChanged:
                        ref.read(licenseCustomerFilterProvider.notifier).set,
                    decoration: const InputDecoration(
                      labelText: 'Müşteri',
                      hintText: 'Müşteri adına göre',
                      prefixIcon: Icon(Icons.storefront_rounded),
                    ),
                  ),
                );

                final companies = companiesAsync.asData?.value
                        .where((e) => e.isActive)
                        .toList(growable: false) ??
                    const <SoftwareCompanyDefinition>[];
                final companyField = SizedBox(
                  width: narrow ? double.infinity : 320,
                  child: DropdownButtonFormField<String>(
                    initialValue: companyFilter,
                    items: [
                      const DropdownMenuItem(
                        value: 'all',
                        child: Text('Tüm Firmalar'),
                      ),
                      for (final c in companies)
                        DropdownMenuItem(value: c.id, child: Text(c.name)),
                      const DropdownMenuItem(
                        value: 'unknown',
                        child: Text('Belirsiz'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      ref.read(licenseCompanyFilterProvider.notifier).set(v);
                    },
                    decoration: const InputDecoration(labelText: 'Yazılım Firması'),
                  ),
                );

                final fromBtn = SizedBox(
                  width: narrow ? double.infinity : 200,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endsFrom ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      ref
                          .read(licenseEndsFromProvider.notifier)
                          .set(DateTime(picked.year, picked.month, picked.day));
                    },
                    icon: const Icon(Icons.date_range_rounded, size: 18),
                    label: Text('Bitiş ≥ ${dateLabel(endsFrom)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                );
                final toBtn = SizedBox(
                  width: narrow ? double.infinity : 200,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: endsTo ?? DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (picked == null) return;
                      ref
                          .read(licenseEndsToProvider.notifier)
                          .set(DateTime(picked.year, picked.month, picked.day));
                    },
                    icon: const Icon(Icons.event_rounded, size: 18),
                    label: Text('Bitiş ≤ ${dateLabel(endsTo)}'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                );

                final clearBtn = OutlinedButton.icon(
                  onPressed: () {
                    _customerController.text = '';
                    ref.read(licenseCustomerFilterProvider.notifier).set('');
                    ref.read(licenseEndsFromProvider.notifier).set(null);
                    ref.read(licenseEndsToProvider.notifier).set(null);
                    ref.read(licenseCompanyFilterProvider.notifier).set('all');
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Temizle'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                final exportBtn = OutlinedButton.icon(
                  onPressed: widget.exportAll,
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Dışarı Aktar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                if (narrow) {
                  return Column(
                    children: [
                      customerField,
                      const Gap(8),
                      companyField,
                      const Gap(8),
                      fromBtn,
                      const Gap(8),
                      toBtn,
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: clearBtn),
                          const Gap(8),
                          Expanded(child: exportBtn),
                        ],
                      ),
                    ],
                  );
                }

                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      customerField,
                      const Gap(8),
                      companyField,
                      const Gap(8),
                      fromBtn,
                      const Gap(8),
                      toBtn,
                      const Gap(8),
                      clearBtn,
                      const Gap(8),
                      exportBtn,
                    ],
                  ),
                );
              },
            ),
          ),
          const Gap(8),
          Expanded(
            child: licensesAsync.when(
              data: (items) {
                final gmp3 = items.where((e) => e.licenseType == 'gmp3').toList();
                if (gmp3.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: gmp3.length,
                    separatorBuilder: (_, _) => const Gap(10),
                    itemBuilder: (context, index) => _LicenseRow(
                      item: gmp3[index],
                      isAdmin: widget.isAdmin,
                    ),
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Lisanslar yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _TotalsTab extends ConsumerStatefulWidget {
  const _TotalsTab();

  @override
  ConsumerState<_TotalsTab> createState() => _TotalsTabState();
}

class _TotalsTabState extends ConsumerState<_TotalsTab> {
  late final TextEditingController _customerController;

  excel.CellValue _cell(Object? v) {
    final text = (v ?? '').toString();
    return excel.TextCellValue(text);
  }

  @override
  void initState() {
    super.initState();
    _customerController =
        TextEditingController(text: ref.read(totalsCustomerSearchProvider));
  }

  @override
  void dispose() {
    _customerController.dispose();
    super.dispose();
  }

  Future<void> _export(BuildContext context, List<CustomerTotalsRow> items) async {
    if (!kIsWeb) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışarı aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final book = excel.Excel.createExcel();
    final sheet = book['Müşteri Toplamları'];
    sheet.appendRow([
      _cell('customer_name'),
      _cell('lines_total'),
      _cell('lines_turkcell'),
      _cell('lines_telsim'),
      _cell('gmp3_total'),
    ]);
    for (final r in items) {
      sheet.appendRow([
        _cell(r.customerName),
        _cell(r.linesTotal),
        _cell(r.linesTurkcell),
        _cell(r.linesTelsim),
        _cell(r.gmp3Total),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'musteri_toplamlari.xlsx');
  }

  @override
  Widget build(BuildContext context) {
    final totalsAsync = ref.watch(issuedCustomerTotalsProvider);
    final search = ref.watch(totalsCustomerSearchProvider);

    final items = totalsAsync.asData?.value ?? const <CustomerTotalsRow>[];

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 980;
                final searchField = SizedBox(
                  width: narrow ? double.infinity : 360,
                  child: TextField(
                    controller: _customerController,
                    onChanged: ref.read(totalsCustomerSearchProvider.notifier).set,
                    decoration: const InputDecoration(
                      labelText: 'Müşteri Ara',
                      hintText: 'Müşteri adına göre',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                  ),
                );

                final clearBtn = OutlinedButton.icon(
                  onPressed: () {
                    _customerController.text = '';
                    ref.read(totalsCustomerSearchProvider.notifier).set('');
                  },
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  label: const Text('Temizle'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                final exportBtn = OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : () => _export(context, items),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Dışarı Aktar'),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                );

                if (narrow) {
                  return Column(
                    children: [
                      searchField,
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: clearBtn),
                          const Gap(8),
                          Expanded(child: exportBtn),
                        ],
                      ),
                    ],
                  );
                }

                return Row(
                  children: [
                    searchField,
                    const Gap(8),
                    clearBtn,
                    const Gap(8),
                    exportBtn,
                    if (search.trim().isNotEmpty) const Gap(8),
                    if (search.trim().isNotEmpty)
                      AppBadge(
                        label: 'Sonuç: ${items.length}',
                        tone: AppBadgeTone.neutral,
                        dense: true,
                      ),
                  ],
                );
              },
            ),
          ),
          const Gap(8),
          Expanded(
            child: totalsAsync.when(
              data: (rows) {
                if (rows.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: rows.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (context, index) {
                      final r = rows[index];
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                r.customerName.trim().isEmpty ? '—' : r.customerName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                              ),
                            ),
                            const Gap(8),
                            AppBadge(
                              label: 'Hat: ${r.linesTotal}',
                              tone: AppBadgeTone.primary,
                              dense: true,
                            ),
                            const Gap(6),
                            AppBadge(
                              label: 'T: ${r.linesTurkcell}',
                              tone: AppBadgeTone.primary,
                              dense: true,
                            ),
                            const Gap(6),
                            AppBadge(
                              label: 'V: ${r.linesTelsim}',
                              tone: AppBadgeTone.warning,
                              dense: true,
                            ),
                            const Gap(6),
                            AppBadge(
                              label: 'GMP3: ${r.gmp3Total}',
                              tone: AppBadgeTone.success,
                              dense: true,
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Toplamlar yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LineRow extends ConsumerStatefulWidget {
  const _LineRow({required this.item, required this.isAdmin});

  final IssuedLine item;
  final bool isAdmin;

  @override
  ConsumerState<_LineRow> createState() => _LineRowState();
}

class _LineRowState extends ConsumerState<_LineRow> {
  bool _busy = false;

  String? _operatorLabel(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v == 'turkcell') return 'TURKCELL';
    if (v == 'telsim' || v == 'vodafone') return 'TELSİM';
    return null;
  }

  AppBadgeTone _operatorTone(String? value) {
    final v = (value ?? '').trim().toLowerCase();
    if (v == 'turkcell') return AppBadgeTone.primary;
    if (v == 'telsim' || v == 'vodafone') return AppBadgeTone.warning;
    return AppBadgeTone.neutral;
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
            ? AppBadgeTone.neutral
            : endsAt.isBefore(now)
                ? AppBadgeTone.error
                : endsAt.isBefore(now.add(const Duration(days: 30)))
                    ? AppBadgeTone.warning
                    : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
            ? 'Tarihsiz'
            : endsAt.isBefore(now)
                ? 'Bitmiş'
                : endsAt.isBefore(now.add(const Duration(days: 30)))
                    ? 'Yaklaşıyor'
                    : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  item.number ?? 'Hat',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: item.isActive ? null : TextDecoration.lineThrough,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    [
                      item.customerName ?? '—',
                      if (item.branchName?.trim().isNotEmpty ?? false) item.branchName!,
                      if (item.simNumber?.trim().isNotEmpty ?? false) 'SIM: ${item.simNumber}',
                      if (dateText != '—') 'Bitiş: $dateText',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              if (_operatorLabel(item.operator) != null)
                AppBadge(
                  label: _operatorLabel(item.operator)!,
                  tone: _operatorTone(item.operator),
                  dense: true,
                ),
              AppBadge(label: statusLabel, tone: tone, dense: true),
            ],
          ),
          if (widget.isAdmin) ...[
            const Gap(8),
            MenuAnchor(
              builder: (context, controller, _) => OutlinedButton(
                onPressed: _busy
                    ? null
                    : () => controller.isOpen ? controller.close() : controller.open(),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('İşlem'),
              ),
              menuChildren: [
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _showEditLineDialog(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Düzenle'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _extendLineAndQueueInvoice(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                      ref.invalidate(invoiceItemsProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Süre Uzat'),
                ),
                MenuItemButton(
                  onPressed: () async {
                    if (_busy) return;
                    setState(() => _busy = true);
                    try {
                      await _transferLine(context, ref, line: item);
                      ref.invalidate(issuedLinesProvider);
                    } finally {
                      if (mounted) setState(() => _busy = false);
                    }
                  },
                  child: const Text('Devir Et'),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LicenseRow extends ConsumerStatefulWidget {
  const _LicenseRow({required this.item, required this.isAdmin});

  final IssuedLicense item;
  final bool isAdmin;

  @override
  ConsumerState<_LicenseRow> createState() => _LicenseRowState();
}

class _LicenseRowState extends ConsumerState<_LicenseRow> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final endsAt = item.endsAt;
    final now = DateTime.now();

    final tone = !item.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
            ? AppBadgeTone.neutral
            : endsAt.isBefore(now)
                ? AppBadgeTone.error
                : endsAt.isBefore(now.add(const Duration(days: 30)))
                    ? AppBadgeTone.warning
                    : AppBadgeTone.success;

    final statusLabel = !item.isActive
        ? 'Pasif'
        : endsAt == null
            ? 'Tarihsiz'
            : endsAt.isBefore(now)
                ? 'Bitmiş'
                : endsAt.isBefore(now.add(const Duration(days: 30)))
                    ? 'Yaklaşıyor'
                    : 'Aktif';

    final dateText = endsAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(endsAt);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: item.isActive ? null : TextDecoration.lineThrough,
                        color: const Color(0xFF0F172A),
                      ),
                ),
                const Gap(8),
                Expanded(
                  child: Text(
                    [
                      item.customerName ?? '—',
                      if ((item.softwareCompanyName ?? '').trim().isNotEmpty)
                        'Firma: ${item.softwareCompanyName}',
                      if ((item.registryNumber ?? '').trim().isNotEmpty)
                        'Sicil: ${item.registryNumber}',
                      if (dateText != '—') 'Bitiş: $dateText',
                    ].join(' • '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(8),
          AppBadge(label: statusLabel, tone: tone, dense: true),
          if (widget.isAdmin) ...[
            const Gap(8),
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await _extendLicenseAndQueueInvoice(context, ref, license: item);
                        ref.invalidate(issuedLicensesProvider);
                        ref.invalidate(invoiceItemsProvider);
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(0, 32),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                visualDensity: VisualDensity.compact,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: _busy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Süre Uzat'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showEditLineDialog(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient == null && client == null) return;

  final labelController = TextEditingController(text: line.label ?? '');
  final numberController = TextEditingController(text: line.number ?? '');
  final simController = TextEditingController(text: line.simNumber ?? '');
  String operator = (line.operator ?? '').trim().isEmpty
      ? 'turkcell'
      : (line.operator ?? '').trim().toLowerCase();
  DateTime? startsAt = line.startsAt;
  DateTime? endsAt = line.endsAt;
  bool saving = false;

  Future<void> pickStart(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: startsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => startsAt = picked);
  }

  Future<void> pickEnd(StateSetter setState) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: endsAt ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(DateTime.now().year + 10),
    );
    if (picked == null) return;
    setState(() => endsAt = picked);
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hat Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Hat Numarası',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: simController,
                  decoration: const InputDecoration(
                    labelText: 'SIM Numarası',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: operator,
                  items: const [
                    DropdownMenuItem(value: 'turkcell', child: Text('TURKCELL')),
                    DropdownMenuItem(value: 'telsim', child: Text('TELSİM')),
                  ],
                  onChanged: saving
                      ? null
                      : (v) => setState(() => operator = (v ?? 'turkcell')),
                  decoration: const InputDecoration(labelText: 'Operatör'),
                ),
                const Gap(12),
                TextField(
                  controller: labelController,
                  decoration: const InputDecoration(
                    labelText: 'Etiket',
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickStart(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Başlangıç'),
                          child: Text(
                            startsAt == null
                                ? '—'
                                : DateFormat('d MMM y', 'tr_TR').format(startsAt!),
                          ),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: saving ? null : () => pickEnd(setState),
                        child: InputDecorator(
                          decoration: const InputDecoration(labelText: 'Bitiş'),
                          child: Text(
                            endsAt == null
                                ? '—'
                                : DateFormat('d MMM y', 'tr_TR').format(endsAt!),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final number = numberController.text.trim();
                                if (number.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final endStr = endsAt?.toIso8601String().substring(0, 10);
                                  final values = {
                                    'number': number,
                                    'operator': operator,
                                    'sim_number': simController.text.trim().isEmpty
                                        ? null
                                        : simController.text.trim(),
                                    'label': labelController.text.trim().isEmpty
                                        ? null
                                        : labelController.text.trim(),
                                    'starts_at': startsAt?.toIso8601String().substring(0, 10),
                                    'ends_at': endStr,
                                    'expires_at': endStr,
                                  };

                                  if (apiClient != null) {
                                    await apiClient.postJson(
                                      '/mutate',
                                      body: {
                                        'op': 'updateWhere',
                                        'table': 'lines',
                                        'filters': [
                                          {'col': 'id', 'op': 'eq', 'value': line.id},
                                        ],
                                        'values': values,
                                      },
                                    );
                                  } else {
                                    await client!
                                        .from('lines')
                                        .update(values)
                                        .eq('id', line.id);
                                  }

                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Hat güncellendi.')),
                                  );
                                } catch (_) {
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Hat güncellenemedi.')),
                                  );
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  labelController.dispose();
  numberController.dispose();
  simController.dispose();
}

Future<void> _extendLineAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient == null && client == null) return;

  final now = DateTime.now();
  final baseYear = (line.endsAt != null && line.endsAt!.isAfter(now)) ? line.endsAt!.year : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  final amountController = TextEditingController();
  String currency = 'TRY';

  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Hat Süre Uzat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (opsiyonel)',
                    hintText: '0.00',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Uzat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (confirm != true) {
    amountController.dispose();
    return;
  }

  try {
    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'lines',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': line.id},
          ],
          'values': {'ends_at': newEndStr, 'expires_at': newEndStr},
        },
      );
    } else {
      await client!.from('lines').update({
        'ends_at': newEndStr,
        'expires_at': newEndStr,
      }).eq('id', line.id);
    }

    final amountRaw = amountController.text.trim().replaceAll(',', '.');
    final amount = amountRaw.isEmpty ? null : double.tryParse(amountRaw);

    final invoiceItem = {
      'customer_id': line.customerId,
      'item_type': 'line_renewal',
      'source_table': 'lines',
      'source_id': line.id,
      'description': 'Hat uzatma (${line.number ?? ''}) (yeni bitiş: $newEndStr)',
      'amount': amount,
      'currency': currency,
      'status': 'pending',
      'is_active': true,
    };

    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'insertMany', 'table': 'invoice_items', 'rows': [invoiceItem]},
      );
    } else {
      await client!.from('invoice_items').insert({
        ...invoiceItem,
        'created_by': client.auth.currentUser?.id,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hat uzatıldı ve faturalama listesine eklendi.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem başarısız.')),
      );
    }
  } finally {
    amountController.dispose();
  }
}

Future<void> _transferLine(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLine line,
}) async {
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient == null && client == null) return;

  final customers = await ref.read(customersLookupProvider.future);
  if (!context.mounted) return;

  final selected = await showDialog<CustomerLookup?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransferDialog(
      customers: customers.where((c) => c.id != line.customerId).toList(growable: false),
    ),
  );
  if (!context.mounted) return;
  if (selected == null) return;

  try {
    final transferPayload = {
      'line_id': line.id,
      'from_customer_id': line.customerId,
      'to_customer_id': selected.id,
      'transferred_by': null,
    };

    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'upsert', 'table': 'line_transfers', 'values': transferPayload},
      );
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'lines',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': line.id},
          ],
          'values': {
            'customer_id': selected.id,
            'branch_id': null,
            'transferred_at': DateTime.now().toIso8601String(),
            'transferred_by': null,
          },
        },
      );
    } else {
      await client!.from('line_transfers').insert({
        ...transferPayload,
        'transferred_by': client.auth.currentUser?.id,
      });
      await client.from('lines').update({
        'customer_id': selected.id,
        'branch_id': null,
        'transferred_at': DateTime.now().toIso8601String(),
        'transferred_by': client.auth.currentUser?.id,
      }).eq('id', line.id);
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hat devredildi.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hat devredilemedi.')),
      );
    }
  }
}

Future<void> _extendLicenseAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required IssuedLicense license,
}) async {
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient == null && client == null) return;

  final now = DateTime.now();
  final baseYear =
      (license.endsAt != null && license.endsAt!.isAfter(now)) ? license.endsAt!.year : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  final amountController = TextEditingController();
  String currency = 'TRY';

  final confirm = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Lisans Süre Uzat',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(10),
                Text(
                  'Yeni bitiş tarihi: ${DateFormat('d MMM y', 'tr_TR').format(newEnd)}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
                const Gap(12),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Tutar (opsiyonel)',
                    hintText: '0.00',
                  ),
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: currency,
                  items: const [
                    DropdownMenuItem(value: 'TRY', child: Text('TRY')),
                    DropdownMenuItem(value: 'USD', child: Text('USD')),
                    DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                  ],
                  onChanged: (v) => setState(() => currency = v ?? 'TRY'),
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        child: const Text('Uzat'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  if (confirm != true) {
    amountController.dispose();
    return;
  }

  try {
    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'licenses',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': license.id},
          ],
          'values': {'ends_at': newEndStr, 'expires_at': newEndStr},
        },
      );
    } else {
      await client!.from('licenses').update({
        'ends_at': newEndStr,
        'expires_at': newEndStr,
      }).eq('id', license.id);
    }

    final amountRaw = amountController.text.trim().replaceAll(',', '.');
    final amount = amountRaw.isEmpty ? null : double.tryParse(amountRaw);

    final invoiceItem = {
      'customer_id': license.customerId,
      'item_type': 'gmp3_renewal',
      'source_table': 'licenses',
      'source_id': license.id,
      'description': 'GMP3 uzatma (${license.name}) (yeni bitiş: $newEndStr)',
      'amount': amount,
      'currency': currency,
      'status': 'pending',
      'is_active': true,
    };

    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'insertMany', 'table': 'invoice_items', 'rows': [invoiceItem]},
      );
    } else {
      await client!.from('invoice_items').insert({
        ...invoiceItem,
        'created_by': client.auth.currentUser?.id,
      });
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lisans uzatıldı ve faturalama listesine eklendi.')),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İşlem başarısız.')),
      );
    }
  } finally {
    amountController.dispose();
  }
}

class _TransferDialog extends StatefulWidget {
  const _TransferDialog({required this.customers});

  final List<CustomerLookup> customers;

  @override
  State<_TransferDialog> createState() => _TransferDialogState();
}

class _TransferDialogState extends State<_TransferDialog> {
  CustomerLookup? _selected;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Hat Devir',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(12),
              Autocomplete<CustomerLookup>(
                optionsBuilder: (text) {
                  final q = text.text.trim().toLowerCase();
                  final list =
                      widget.customers.where((c) => c.isActive).toList(growable: false);
                  if (q.isEmpty) return list.take(20);
                  return list.where((c) => c.name.toLowerCase().contains(q)).take(20);
                },
                displayStringForOption: (o) => o.name,
                onSelected: (o) => setState(() => _selected = o),
                fieldViewBuilder: (context, controller, focusNode, _) => TextField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Yeni Müşteri',
                    hintText: 'Firma adı yazın ve seçin',
                  ),
                  onChanged: (_) => setState(() => _selected = null),
                ),
              ),
              const Gap(18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _selected == null
                          ? null
                          : () => Navigator.of(context).pop(_selected),
                      child: const Text('Devir Et'),
                    ),
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

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class IssuedLine {
  const IssuedLine({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.branchId,
    required this.branchName,
    required this.label,
    required this.number,
    required this.simNumber,
    required this.operator,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String? branchId;
  final String? branchName;
  final String? label;
  final String? number;
  final String? simNumber;
  final String? operator;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLine.fromJson(Map<String, dynamic> json) {
    return IssuedLine(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      label: json['label']?.toString(),
      number: json['number']?.toString(),
      simNumber: json['sim_number']?.toString(),
      operator: json['operator']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class IssuedLicense {
  const IssuedLicense({
    required this.id,
    required this.customerId,
    required this.customerName,
    required this.name,
    required this.licenseType,
    required this.softwareCompanyId,
    required this.softwareCompanyName,
    required this.registryNumber,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String customerId;
  final String? customerName;
  final String name;
  final String licenseType;
  final String? softwareCompanyId;
  final String? softwareCompanyName;
  final String? registryNumber;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory IssuedLicense.fromJson(Map<String, dynamic> json) {
    return IssuedLicense(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      name: (json['name'] ?? '').toString(),
      licenseType: (json['license_type'] ?? 'gmp3').toString(),
      softwareCompanyId: json['software_company_id']?.toString(),
      softwareCompanyName: json['software_company_name']?.toString(),
      registryNumber: json['registry_number']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerLookup {
  const CustomerLookup({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory CustomerLookup.fromJson(Map<String, dynamic> json) {
    return CustomerLookup(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
