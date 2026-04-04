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
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import '../definitions/definitions_screen.dart';

final subscriptionsFiltersProvider =
    NotifierProvider<SubscriptionsFiltersNotifier, SubscriptionsFilters>(
      SubscriptionsFiltersNotifier.new,
    );

class SubscriptionsFiltersNotifier extends Notifier<SubscriptionsFilters> {
  @override
  SubscriptionsFilters build() => const SubscriptionsFilters();

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setStatus(SubscriptionStatusFilter value) {
    state = state.copyWith(status: value);
  }

  void setOperator(LineOperatorFilter value) {
    state = state.copyWith(operator: value);
  }

  void setSoftwareCompanyId(String? value) {
    state = state.copyWith(softwareCompanyId: (value ?? '').trim().isEmpty ? 'all' : value);
  }
}

enum SubscriptionStatusFilter { all, active, expiringSoon, expired }
enum LineOperatorFilter { all, turkcell, telsim }

class SubscriptionsFilters {
  const SubscriptionsFilters({
    this.query = '',
    this.status = SubscriptionStatusFilter.all,
    this.operator = LineOperatorFilter.all,
    this.softwareCompanyId = 'all',
  });

  final String query;
  final SubscriptionStatusFilter status;
  final LineOperatorFilter operator;
  final String softwareCompanyId;

  SubscriptionsFilters copyWith({
    String? query,
    SubscriptionStatusFilter? status,
    LineOperatorFilter? operator,
    String? softwareCompanyId,
  }) {
    return SubscriptionsFilters(
      query: query ?? this.query,
      status: status ?? this.status,
      operator: operator ?? this.operator,
      softwareCompanyId: softwareCompanyId ?? this.softwareCompanyId,
    );
  }
}

// Hat modeli
class Line {
  final String id;
  final String customerId;
  final String? customerName;
  final String? branchId;
  final String number;
  final String? simNumber;
  final String? operator;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? expiresAt;
  final bool isActive;

  const Line({
    required this.id,
    required this.customerId,
    this.customerName,
    this.branchId,
    required this.number,
    this.simNumber,
    this.operator,
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.isActive = true,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExpiringSoon =>
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

  factory Line.fromJson(Map<String, dynamic> json) {
    return Line(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customers']?['name']?.toString(),
      branchId: json['branch_id']?.toString(),
      number: json['number']?.toString() ?? '',
      simNumber: json['sim_number']?.toString(),
      operator: json['operator']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

// Lisans modeli
class License {
  final String id;
  final String customerId;
  final String? customerName;
  final String name;
  final String licenseType;
  final String? softwareCompanyId;
  final String? softwareCompanyName;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final DateTime? expiresAt;
  final bool isActive;

  const License({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.name,
    required this.licenseType,
    this.softwareCompanyId,
    this.softwareCompanyName,
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.isActive = true,
  });

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExpiringSoon =>
      expiresAt != null &&
      expiresAt!.isAfter(DateTime.now()) &&
      expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

  factory License.fromJson(Map<String, dynamic> json) {
    final softwareCompany =
        (json['software_companies'] as Map?)?.cast<String, dynamic>();
    return License(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customers']?['name']?.toString(),
      name: json['name']?.toString() ?? '',
      licenseType: json['license_type']?.toString() ?? '',
      softwareCompanyId: json['software_company_id']?.toString(),
      softwareCompanyName: softwareCompany?['name']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt: DateTime.tryParse(json['ends_at']?.toString() ?? ''),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

// Providers
final linesProvider = FutureProvider.autoDispose<List<Line>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client
      .from('lines')
      .select('*, customers(name)')
      .eq('is_active', true)
      .order('expires_at', ascending: true);

  return (rows as List)
      .map((e) => Line.fromJson(e as Map<String, dynamic>))
      .toList();
});

final licensesProvider = FutureProvider.autoDispose<List<License>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client
      .from('licenses')
      .select('*, customers(name), software_companies(name)')
      .eq('is_active', true)
      .order('expires_at', ascending: true);

  return (rows as List)
      .map((e) => License.fromJson(e as Map<String, dynamic>))
      .toList();
});

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() =>
      _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _dateFormat = DateFormat('d MMM y', 'tr_TR');

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

  List<Line> _filterLines(List<Line> lines, SubscriptionsFilters filters) {
    return lines
        .where((line) {
          final query = filters.query.trim().toLowerCase();
          final matchesQuery = query.isEmpty ||
              line.number.toLowerCase().contains(query) ||
              (line.simNumber?.toLowerCase().contains(query) ?? false) ||
              (line.customerName?.toLowerCase().contains(query) ?? false);
          final op = (line.operator ?? '').trim().toLowerCase();
          final matchesOperator = switch (filters.operator) {
            LineOperatorFilter.all => true,
            LineOperatorFilter.turkcell => op == 'turkcell',
            LineOperatorFilter.telsim => op == 'telsim' || op == 'vodafone',
          };
          final matchesStatus = switch (filters.status) {
            SubscriptionStatusFilter.all => true,
            SubscriptionStatusFilter.active => !line.isExpired && !line.isExpiringSoon,
            SubscriptionStatusFilter.expiringSoon => line.isExpiringSoon,
            SubscriptionStatusFilter.expired => line.isExpired,
          };
          return matchesQuery && matchesOperator && matchesStatus;
        })
        .toList(growable: false);
  }

  List<License> _filterLicenses(List<License> licenses, SubscriptionsFilters filters) {
    return licenses
        .where((license) {
          final query = filters.query.trim().toLowerCase();
          final matchesQuery = query.isEmpty ||
              license.name.toLowerCase().contains(query) ||
              license.licenseType.toLowerCase().contains(query) ||
              (license.customerName?.toLowerCase().contains(query) ?? false);
          final matchesCompany = filters.softwareCompanyId == 'all' ||
              (license.softwareCompanyId ?? '') == filters.softwareCompanyId;
          final matchesStatus = switch (filters.status) {
            SubscriptionStatusFilter.all => true,
            SubscriptionStatusFilter.active =>
              !license.isExpired && !license.isExpiringSoon,
            SubscriptionStatusFilter.expiringSoon => license.isExpiringSoon,
            SubscriptionStatusFilter.expired => license.isExpired,
          };
          return matchesQuery && matchesCompany && matchesStatus;
        })
        .toList(growable: false);
  }

  Future<void> _exportExcel({
    required List<Line> lines,
    required List<License> licenses,
  }) async {
    if (!kIsWeb) {
      if (!mounted) return;
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
      _cell('expires_at'),
      _cell('status'),
    ]);
    for (final l in lines) {
      hats.appendRow([
        _cell(l.customerName ?? ''),
        _cell(l.number),
        _cell(_operatorLabel(l.operator)),
        _cell(l.simNumber ?? ''),
        _cell(l.expiresAt == null ? '' : l.expiresAt!.toIso8601String().substring(0, 10)),
        _cell(l.isExpired ? 'expired' : l.isExpiringSoon ? 'expiring_soon' : 'active'),
      ]);
    }

    gmp3.appendRow([
      _cell('customer_name'),
      _cell('license_name'),
      _cell('software_company'),
      _cell('starts_at'),
      _cell('ends_at'),
      _cell('expires_at'),
      _cell('status'),
    ]);
    for (final lic in licenses) {
      gmp3.appendRow([
        _cell(lic.customerName ?? ''),
        _cell(lic.name),
        _cell(lic.softwareCompanyName ?? ''),
        _cell(lic.startsAt == null ? '' : lic.startsAt!.toIso8601String().substring(0, 10)),
        _cell(lic.endsAt == null ? '' : lic.endsAt!.toIso8601String().substring(0, 10)),
        _cell(lic.expiresAt == null ? '' : lic.expiresAt!.toIso8601String().substring(0, 10)),
        _cell(lic.isExpired ? 'expired' : lic.isExpiringSoon ? 'expiring_soon' : 'active'),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'hat_lisanslar.xlsx');
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filters = ref.watch(subscriptionsFiltersProvider);
    final linesAsync = ref.watch(linesProvider);
    final licensesAsync = ref.watch(licensesProvider);
    final companiesAsync = ref.watch(softwareCompaniesProvider);

    final lines = linesAsync.asData?.value ?? const <Line>[];
    final licenses = licensesAsync.asData?.value ?? const <License>[];
    final filteredLines = _filterLines(lines, filters);
    final filteredLicenses = _filterLicenses(licenses, filters);

    final companies = companiesAsync.asData?.value
            .where((e) => e.isActive)
            .toList(growable: false) ??
        const <SoftwareCompanyDefinition>[];
    final companyNameById = <String, String>{
      for (final c in companies) c.id: c.name,
    };
    final gmp3Licenses = licenses
        .where((e) => e.licenseType.trim().toLowerCase() == 'gmp3')
        .toList(growable: false);
    final gmp3Counts = <String, int>{};
    for (final lic in gmp3Licenses) {
      final key = (lic.softwareCompanyId ?? '').trim().isEmpty
          ? 'unknown'
          : lic.softwareCompanyId!.trim();
      gmp3Counts.update(key, (v) => v + 1, ifAbsent: () => 1);
    }

    final turkcellAllCount = lines
        .where((e) => (e.operator ?? '').trim().toLowerCase() == 'turkcell')
        .length;
    final telsimAllCount = lines
        .where((e) {
          final op = (e.operator ?? '').trim().toLowerCase();
          return op == 'telsim' || op == 'vodafone';
        })
        .length;

    return AppPageLayout(
      title: 'Hat & Lisans Takibi',
      subtitle: 'Hat ve GMP3 lisanslarını yönetin',
      actions: [
        if (linesAsync is AsyncData) ...[
          AppBadge(
            label: 'TURKCELL: $turkcellAllCount',
            tone: AppBadgeTone.primary,
          ),
          AppBadge(
            label: 'TELSİM: $telsimAllCount',
            tone: AppBadgeTone.warning,
          ),
        ],
        if (licensesAsync is AsyncData) ...[
          AppBadge(
            label: 'GMP3: ${gmp3Licenses.length}',
            tone: AppBadgeTone.success,
          ),
        ],
        if (companiesAsync is AsyncData && gmp3Licenses.isNotEmpty) ...[
          PopupMenuButton<String>(
            tooltip: 'GMP3 Firmaları',
            onSelected: (value) {
              ref
                  .read(subscriptionsFiltersProvider.notifier)
                  .setSoftwareCompanyId(value);
            },
            itemBuilder: (context) {
              final items = <PopupMenuEntry<String>>[
                const PopupMenuItem(
                  value: 'all',
                  child: Text('Tümü'),
                ),
              ];
              for (final c in companies) {
                final count = gmp3Counts[c.id] ?? 0;
                if (count == 0) continue;
                items.add(
                  PopupMenuItem(
                    value: c.id,
                    child: Text('${c.name} ($count)'),
                  ),
                );
              }
              final unknownCount = gmp3Counts['unknown'] ?? 0;
              if (unknownCount > 0) {
                items.add(
                  PopupMenuItem(
                    value: 'unknown',
                    child: Text('Belirsiz ($unknownCount)'),
                  ),
                );
              }
              return items;
            },
            child: AppBadge(
              label: filters.softwareCompanyId == 'all'
                  ? 'Firma: Tümü'
                  : filters.softwareCompanyId == 'unknown'
                      ? 'Firma: Belirsiz'
                      : 'Firma: ${companyNameById[filters.softwareCompanyId] ?? 'Seçili'}',
              tone: AppBadgeTone.neutral,
            ),
          ),
        ],
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(linesProvider);
            ref.invalidate(licensesProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        PopupMenuButton<String>(
          tooltip: 'Dışarı Aktar',
          onSelected: (value) async {
            if (value == 'export') {
              await _exportExcel(lines: filteredLines, licenses: filteredLicenses);
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'export', child: Text('Dışarı Aktar (Excel)')),
          ],
          child: const SizedBox(
            width: 44,
            height: 40,
            child: Icon(Icons.download_rounded),
          ),
        ),
      ],
      body: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  label: 'Aktif Hat',
                  value: linesAsync.asData?.value.length.toString() ?? '—',
                  icon: Icons.sim_card_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _OverviewCard(
                  label: 'Aktif Lisans',
                  value: licensesAsync.asData?.value.length.toString() ?? '—',
                  icon: Icons.key_rounded,
                  color: AppTheme.success,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _OverviewCard(
                  label: 'Yaklaşan Bitiş',
                  value:
                      '${(linesAsync.asData?.value.where((line) => line.isExpiringSoon).length ?? 0) + (licensesAsync.asData?.value.where((license) => license.isExpiringSoon).length ?? 0)}',
                  icon: Icons.schedule_rounded,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const Gap(12),
          Row(
            children: [
              Expanded(
                child: _OverviewCard(
                  label: 'TURKCELL Hat',
                  value: linesAsync.asData == null ? '—' : '$turkcellAllCount',
                  icon: Icons.signal_cellular_alt_rounded,
                  color: AppTheme.primary,
                ),
              ),
              const Gap(12),
              Expanded(
                child: _OverviewCard(
                  label: 'TELSİM Hat',
                  value: linesAsync.asData == null ? '—' : '$telsimAllCount',
                  icon: Icons.signal_cellular_alt_rounded,
                  color: AppTheme.warning,
                ),
              ),
            ],
          ),
          const Gap(16),
          AppCard(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 860;
                final searchField = TextField(
                  onChanged: ref
                      .read(subscriptionsFiltersProvider.notifier)
                      .setQuery,
                  decoration: const InputDecoration(
                    labelText: 'Ara',
                    hintText: 'Müşteri, hat numarası veya lisans adı',
                    prefixIcon: Icon(Icons.search_rounded),
                  ),
                );

                final statusField = DropdownButtonFormField<SubscriptionStatusFilter>(
                  initialValue: filters.status,
                  items: const [
                    DropdownMenuItem(
                      value: SubscriptionStatusFilter.all,
                      child: Text('Tüm Durumlar'),
                    ),
                    DropdownMenuItem(
                      value: SubscriptionStatusFilter.active,
                      child: Text('Aktif'),
                    ),
                    DropdownMenuItem(
                      value: SubscriptionStatusFilter.expiringSoon,
                      child: Text('Yakında Dolacak'),
                    ),
                    DropdownMenuItem(
                      value: SubscriptionStatusFilter.expired,
                      child: Text('Süresi Doldu'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(subscriptionsFiltersProvider.notifier)
                        .setStatus(value);
                  },
                  decoration: const InputDecoration(labelText: 'Durum'),
                );

                final operatorField = DropdownButtonFormField<LineOperatorFilter>(
                  initialValue: filters.operator,
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
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(subscriptionsFiltersProvider.notifier)
                        .setOperator(value);
                  },
                  decoration: const InputDecoration(labelText: 'Operatör'),
                );

                final companyField = DropdownButtonFormField<String>(
                  initialValue: filters.softwareCompanyId,
                  items: [
                    const DropdownMenuItem(
                      value: 'all',
                      child: Text('Tüm Firmalar'),
                    ),
                    for (final c in companies)
                      DropdownMenuItem(value: c.id, child: Text(c.name)),
                    if (gmp3Counts['unknown'] != null)
                      const DropdownMenuItem(
                        value: 'unknown',
                        child: Text('Belirsiz'),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    ref
                        .read(subscriptionsFiltersProvider.notifier)
                        .setSoftwareCompanyId(value);
                  },
                  decoration: const InputDecoration(labelText: 'Yazılım Firması'),
                );

                if (isNarrow) {
                  return Column(
                    children: [
                      searchField,
                      const Gap(12),
                      statusField,
                      const Gap(12),
                      operatorField,
                      const Gap(12),
                      companyField,
                    ],
                  );
                }

                return Row(
                  children: [
                    Expanded(child: searchField),
                    const Gap(12),
                    SizedBox(width: 220, child: statusField),
                    const Gap(12),
                    SizedBox(width: 220, child: operatorField),
                    const Gap(12),
                    SizedBox(width: 260, child: companyField),
                  ],
                );
              },
            ),
          ),
          const Gap(16),
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
                Tab(text: 'Hatlar'),
                Tab(text: 'GMP3 Lisansları'),
              ],
            ),
          ),
          const Gap(16),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _LinesTab(dateFormat: _dateFormat),
                _LicensesTab(dateFormat: _dateFormat),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesTab extends ConsumerWidget {
  const _LinesTab({required this.dateFormat});

  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(linesProvider);
    final filters = ref.watch(subscriptionsFiltersProvider);
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));

    return linesAsync.when(
      data: (lines) {
        final filteredLines = lines
            .where((line) {
              final query = filters.query.trim().toLowerCase();
              final matchesQuery =
                  query.isEmpty ||
                  line.number.toLowerCase().contains(query) ||
                  (line.simNumber?.toLowerCase().contains(query) ?? false) ||
                  (line.customerName?.toLowerCase().contains(query) ?? false);
              final op = (line.operator ?? '').trim().toLowerCase();
              final matchesOperator = switch (filters.operator) {
                LineOperatorFilter.all => true,
                LineOperatorFilter.turkcell => op == 'turkcell',
                LineOperatorFilter.telsim => op == 'telsim' || op == 'vodafone',
              };
              final matchesStatus = switch (filters.status) {
                SubscriptionStatusFilter.all => true,
                SubscriptionStatusFilter.active =>
                  !line.isExpired && !line.isExpiringSoon,
                SubscriptionStatusFilter.expiringSoon => line.isExpiringSoon,
                SubscriptionStatusFilter.expired => line.isExpired,
              };
              return matchesQuery && matchesOperator && matchesStatus;
            })
            .toList(growable: false);

        if (filteredLines.isEmpty) {
          return Center(
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.phone_android_rounded,
                      size: 48,
                      color: const Color(0xFF94A3B8),
                    ),
                    const Gap(12),
                    Text(
                      lines.isEmpty
                          ? 'Hat kaydı bulunmuyor'
                          : 'Filtreye uygun hat bulunamadı',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final expired = filteredLines.where((line) => line.isExpired).toList();
        final expiringSoon = filteredLines
            .where((line) => line.isExpiringSoon)
            .toList();
        final active = filteredLines
            .where((line) => !line.isExpired && !line.isExpiringSoon)
            .toList();

        return Scrollbar(
          thumbVisibility: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 120),
            children: [
            // Summary
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Toplam',
                    value: filteredLines.length.toString(),
                    color: AppTheme.primary,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Süresi Dolan',
                    value: expired.length.toString(),
                    color: AppTheme.error,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Yaklaşan',
                    value: expiringSoon.length.toString(),
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ),
            const Gap(16),
            if (expired.isNotEmpty) ...[
              _SectionHeader(title: 'Süresi Dolanlar', color: AppTheme.error),
              const Gap(8),
              ...expired.map(
                (l) => _LineCard(
                  line: l,
                  dateFormat: dateFormat,
                  canEdit: canEdit,
                  canArchive: canArchive,
                ),
              ),
              const Gap(16),
            ],
            if (expiringSoon.isNotEmpty) ...[
              _SectionHeader(
                title: '30 Gün İçinde Dolacaklar',
                color: AppTheme.warning,
              ),
              const Gap(8),
              ...expiringSoon.map(
                (l) => _LineCard(
                  line: l,
                  dateFormat: dateFormat,
                  canEdit: canEdit,
                  canArchive: canArchive,
                ),
              ),
              const Gap(16),
            ],
            if (active.isNotEmpty) ...[
              _SectionHeader(title: 'Aktif Hatlar', color: AppTheme.success),
              const Gap(8),
              ...active.map(
                (l) => _LineCard(
                  line: l,
                  dateFormat: dateFormat,
                  canEdit: canEdit,
                  canArchive: canArchive,
                ),
              ),
            ],
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Hatlar yüklenemedi')),
    );
  }
}

class _LicensesTab extends ConsumerWidget {
  const _LicensesTab({required this.dateFormat});

  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licensesAsync = ref.watch(licensesProvider);
    final filters = ref.watch(subscriptionsFiltersProvider);

    return licensesAsync.when(
      data: (licenses) {
        final filteredLicenses = licenses
            .where((license) {
              final query = filters.query.trim().toLowerCase();
              final matchesQuery =
                  query.isEmpty ||
                  license.name.toLowerCase().contains(query) ||
                  license.licenseType.toLowerCase().contains(query) ||
                  (license.customerName?.toLowerCase().contains(query) ??
                      false);
              final matchesCompany = filters.softwareCompanyId == 'all' ||
                  (filters.softwareCompanyId == 'unknown'
                      ? (license.softwareCompanyId ?? '').trim().isEmpty
                      : (license.softwareCompanyId ?? '') ==
                          filters.softwareCompanyId);
              final matchesStatus = switch (filters.status) {
                SubscriptionStatusFilter.all => true,
                SubscriptionStatusFilter.active =>
                  !license.isExpired && !license.isExpiringSoon,
                SubscriptionStatusFilter.expiringSoon => license.isExpiringSoon,
                SubscriptionStatusFilter.expired => license.isExpired,
              };
              return matchesQuery && matchesCompany && matchesStatus;
            })
            .toList(growable: false);

        if (filteredLicenses.isEmpty) {
          return Center(
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.key_rounded,
                      size: 48,
                      color: const Color(0xFF94A3B8),
                    ),
                    const Gap(12),
                    Text(
                      licenses.isEmpty
                          ? 'Lisans kaydı bulunmuyor'
                          : 'Filtreye uygun lisans bulunamadı',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final expired = filteredLicenses
            .where((license) => license.isExpired)
            .toList();
        final expiringSoon = filteredLicenses
            .where((license) => license.isExpiringSoon)
            .toList();
        final active = filteredLicenses
            .where((license) => !license.isExpired && !license.isExpiringSoon)
            .toList();

        return Scrollbar(
          thumbVisibility: true,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 120),
            children: [
            Row(
              children: [
                Expanded(
                  child: _SummaryCard(
                    title: 'Toplam',
                    value: filteredLicenses.length.toString(),
                    color: AppTheme.primary,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Süresi Dolan',
                    value: expired.length.toString(),
                    color: AppTheme.error,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _SummaryCard(
                    title: 'Yaklaşan',
                    value: expiringSoon.length.toString(),
                    color: AppTheme.warning,
                  ),
                ),
              ],
            ),
            const Gap(16),
            if (expired.isNotEmpty) ...[
              _SectionHeader(title: 'Süresi Dolanlar', color: AppTheme.error),
              const Gap(8),
              ...expired.map(
                (l) => _LicenseCard(license: l, dateFormat: dateFormat),
              ),
              const Gap(16),
            ],
            if (expiringSoon.isNotEmpty) ...[
              _SectionHeader(
                title: '30 Gün İçinde Dolacaklar',
                color: AppTheme.warning,
              ),
              const Gap(8),
              ...expiringSoon.map(
                (l) => _LicenseCard(license: l, dateFormat: dateFormat),
              ),
              const Gap(16),
            ],
            if (active.isNotEmpty) ...[
              _SectionHeader(title: 'Aktif Lisanslar', color: AppTheme.success),
              const Gap(8),
              ...active.map(
                (l) => _LicenseCard(license: l, dateFormat: dateFormat),
              ),
            ],
            ],
          ),
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, stackTrace) =>
          const Center(child: Text('Lisanslar yüklenemedi')),
    );
  }
}

class _OverviewCard extends StatelessWidget {
  const _OverviewCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color),
          ),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.color,
  });

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
          ),
          const Gap(4),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const Gap(10),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _LineCard extends ConsumerStatefulWidget {
  const _LineCard({
    required this.line,
    required this.dateFormat,
    required this.canEdit,
    required this.canArchive,
  });

  final Line line;
  final DateFormat dateFormat;
  final bool canEdit;
  final bool canArchive;

  @override
  ConsumerState<_LineCard> createState() => _LineCardState();
}

class _LineCardState extends ConsumerState<_LineCard> {
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

  Future<void> _edit() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _showEditLineFromListDialog(context, ref, line: widget.line);
      ref.invalidate(linesProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _archive() async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Hatı Sil'),
        content: const Text('Bu hattı silmek istiyor musunuz?'),
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

    setState(() => _busy = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final client = ref.read(supabaseClientProvider);
      if (apiClient == null && client == null) return;
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'lines',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.line.id},
            ],
            'values': {'is_active': false},
          },
        );
      } else {
        await client!
            .from('lines')
            .update({'is_active': false})
            .eq('id', widget.line.id);
      }
      ref.invalidate(linesProvider);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final (statusLabel, statusTone) = line.isExpired
        ? ('Süresi Doldu', AppBadgeTone.error)
        : line.isExpiringSoon
            ? ('Yakında Dolacak', AppBadgeTone.warning)
            : ('Aktif', AppBadgeTone.success);

    final details = <String>[
      if ((line.simNumber ?? '').trim().isNotEmpty) 'SIM: ${line.simNumber}',
      if (_operatorLabel(line.operator) != null)
        'Operatör: ${_operatorLabel(line.operator)}',
    ].join(' • ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (line.isExpired ? AppTheme.error : AppTheme.primary)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.phone_android_rounded,
                color: line.isExpired ? AppTheme.error : AppTheme.primary,
                size: 22,
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    line.number,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const Gap(2),
                  Text(
                    line.customerName ?? '-',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                  ),
                  if (details.isNotEmpty) ...[
                    const Gap(2),
                    Text(
                      details,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF94A3B8),
                          ),
                    ),
                  ],
                  if (line.expiresAt != null) ...[
                    const Gap(2),
                    Text(
                      'Bitiş: ${widget.dateFormat.format(line.expiresAt!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF94A3B8),
                          ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment: WrapAlignment.end,
                  children: [
                    if (_operatorLabel(line.operator) != null)
                      AppBadge(
                        label: _operatorLabel(line.operator)!,
                        tone: _operatorTone(line.operator),
                      ),
                    AppBadge(label: statusLabel, tone: statusTone),
                  ],
                ),
                if (widget.canEdit || widget.canArchive) ...[
                  const Gap(8),
                  MenuAnchor(
                    builder: (context, controller, _) => OutlinedButton(
                      onPressed: _busy
                          ? null
                          : () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                      child: _busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('İşlem'),
                    ),
                    menuChildren: [
                      if (widget.canEdit)
                        MenuItemButton(
                          onPressed: _edit,
                          child: const Text('Düzenle'),
                        ),
                      if (widget.canArchive)
                        MenuItemButton(
                          onPressed: _archive,
                          child: const Text('Sil'),
                        ),
                    ],
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

class _LicenseCard extends StatelessWidget {
  const _LicenseCard({required this.license, required this.dateFormat});

  final License license;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = license.isExpired
        ? ('Süresi Doldu', AppBadgeTone.error)
        : license.isExpiringSoon
        ? ('Yakında Dolacak', AppBadgeTone.warning)
        : ('Aktif', AppBadgeTone.success);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: (license.isExpired ? AppTheme.error : AppTheme.success)
                    .withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.key_rounded,
                color: license.isExpired ? AppTheme.error : AppTheme.success,
                size: 22,
              ),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    license.name,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Gap(2),
                  Text(
                    license.customerName ?? '-',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  if ((license.softwareCompanyName ?? '').trim().isNotEmpty) ...[
                    const Gap(2),
                    Text(
                      'Firma: ${license.softwareCompanyName}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                  if (license.expiresAt != null) ...[
                    const Gap(2),
                    Text(
                      'Bitiş: ${dateFormat.format(license.expiresAt!)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF94A3B8),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            AppBadge(label: statusLabel, tone: statusTone),
          ],
        ),
      ),
    );
  }
}

Future<void> _showEditLineFromListDialog(
  BuildContext context,
  WidgetRef ref, {
  required Line line,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _EditLineFromListDialog(line: line),
  );
}

class _EditLineFromListDialog extends ConsumerStatefulWidget {
  const _EditLineFromListDialog({required this.line});

  final Line line;

  @override
  ConsumerState<_EditLineFromListDialog> createState() =>
      _EditLineFromListDialogState();
}

class _EditLineFromListDialogState extends ConsumerState<_EditLineFromListDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _numberController;
  late final TextEditingController _simController;
  late String _operator;
  DateTime? _start;
  DateTime? _end;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final l = widget.line;
    _numberController = TextEditingController(text: l.number);
    _simController = TextEditingController(text: (l.simNumber ?? '').trim());
    final op = (l.operator ?? '').trim().toLowerCase();
    _operator = op.isEmpty ? 'turkcell' : op;
    _start = l.startsAt;
    _end = l.endsAt ?? l.expiresAt;
  }

  @override
  void dispose() {
    _numberController.dispose();
    _simController.dispose();
    super.dispose();
  }

  String _isoDate(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  Future<void> _pickStart() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _start ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _start = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _pickEnd() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _end ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    if (!mounted) return;
    setState(() => _end = DateTime(picked.year, picked.month, picked.day));
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final values = <String, dynamic>{
        'number': _numberController.text.trim(),
        'sim_number': _simController.text.trim().isEmpty ? null : _simController.text.trim(),
        'operator': _operator,
        'starts_at': _start == null ? null : _isoDate(_start!),
        'ends_at': _end == null ? null : _isoDate(_end!),
        'expires_at': _end == null ? null : _isoDate(_end!),
      };

      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'lines',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.line.id},
            ],
            'values': values,
          },
        );
      } else {
        await client!.from('lines').update(values).eq('id', widget.line.id);
      }

      ref.invalidate(linesProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hat güncellendi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('d MMM y', 'tr_TR');
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
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
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Hat Numarası',
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Hat numarası gerekli.' : null,
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: _operator,
                  items: const [
                    DropdownMenuItem(value: 'turkcell', child: Text('TURKCELL')),
                    DropdownMenuItem(value: 'telsim', child: Text('TELSİM')),
                  ],
                  onChanged: _saving ? null : (v) => setState(() => _operator = v ?? 'turkcell'),
                  decoration: const InputDecoration(
                    labelText: 'Operatör',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(12),
                TextFormField(
                  controller: _simController,
                  decoration: const InputDecoration(
                    labelText: 'SIM No',
                    border: OutlineInputBorder(),
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickStart,
                        icon: const Icon(Icons.date_range_rounded),
                        label: Text(_start == null ? 'Başlangıç' : df.format(_start!)),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _saving ? null : _pickEnd,
                        icon: const Icon(Icons.event_busy_rounded),
                        label: Text(_end == null ? 'Bitiş' : df.format(_end!)),
                      ),
                    ),
                  ],
                ),
                const Gap(16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
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
    );
  }
}
