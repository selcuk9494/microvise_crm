import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

// Hat modeli
class Line {
  final String id;
  final String customerId;
  final String? customerName;
  final String? branchId;
  final String number;
  final String? simNumber;
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
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.isActive = true,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExpiringSoon => expiresAt != null && 
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
    this.startsAt,
    this.endsAt,
    this.expiresAt,
    this.isActive = true,
  });

  bool get isExpired => expiresAt != null && expiresAt!.isBefore(DateTime.now());
  bool get isExpiringSoon => expiresAt != null && 
      expiresAt!.isAfter(DateTime.now()) && 
      expiresAt!.isBefore(DateTime.now().add(const Duration(days: 30)));

  factory License.fromJson(Map<String, dynamic> json) {
    return License(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customers']?['name']?.toString(),
      name: json['name']?.toString() ?? '',
      licenseType: json['license_type']?.toString() ?? '',
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

  return (rows as List).map((e) => Line.fromJson(e as Map<String, dynamic>)).toList();
});

final licensesProvider = FutureProvider.autoDispose<List<License>>((ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return [];

  final rows = await client
      .from('licenses')
      .select('*, customers(name)')
      .eq('is_active', true)
      .order('expires_at', ascending: true);

  return (rows as List).map((e) => License.fromJson(e as Map<String, dynamic>)).toList();
});

class SubscriptionsScreen extends ConsumerStatefulWidget {
  const SubscriptionsScreen({super.key});

  @override
  ConsumerState<SubscriptionsScreen> createState() => _SubscriptionsScreenState();
}

class _SubscriptionsScreenState extends ConsumerState<SubscriptionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _dateFormat = DateFormat('d MMM y', 'tr_TR');

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
    return AppPageLayout(
      title: 'Hat & Lisans Takibi',
      subtitle: 'Hat ve GMP3 lisanslarını yönetin',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(linesProvider);
            ref.invalidate(licensesProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        children: [
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

    return linesAsync.when(
      data: (lines) {
        if (lines.isEmpty) {
          return Center(
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.phone_android_rounded, size: 48, color: const Color(0xFF94A3B8)),
                    const Gap(12),
                    Text(
                      'Hat kaydı bulunmuyor',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final expired = lines.where((l) => l.isExpired).toList();
        final expiringSoon = lines.where((l) => l.isExpiringSoon).toList();
        final active = lines.where((l) => !l.isExpired && !l.isExpiringSoon).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          children: [
            // Summary
            Row(
              children: [
                Expanded(child: _SummaryCard(title: 'Toplam', value: lines.length.toString(), color: AppTheme.primary)),
                const Gap(12),
                Expanded(child: _SummaryCard(title: 'Süresi Dolan', value: expired.length.toString(), color: AppTheme.error)),
                const Gap(12),
                Expanded(child: _SummaryCard(title: 'Yaklaşan', value: expiringSoon.length.toString(), color: AppTheme.warning)),
              ],
            ),
            const Gap(16),
            if (expired.isNotEmpty) ...[
              _SectionHeader(title: 'Süresi Dolanlar', color: AppTheme.error),
              const Gap(8),
              ...expired.map((l) => _LineCard(line: l, dateFormat: dateFormat)),
              const Gap(16),
            ],
            if (expiringSoon.isNotEmpty) ...[
              _SectionHeader(title: '30 Gün İçinde Dolacaklar', color: AppTheme.warning),
              const Gap(8),
              ...expiringSoon.map((l) => _LineCard(line: l, dateFormat: dateFormat)),
              const Gap(16),
            ],
            if (active.isNotEmpty) ...[
              _SectionHeader(title: 'Aktif Hatlar', color: AppTheme.success),
              const Gap(8),
              ...active.map((l) => _LineCard(line: l, dateFormat: dateFormat)),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Hatlar yüklenemedi')),
    );
  }
}

class _LicensesTab extends ConsumerWidget {
  const _LicensesTab({required this.dateFormat});

  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licensesAsync = ref.watch(licensesProvider);

    return licensesAsync.when(
      data: (licenses) {
        if (licenses.isEmpty) {
          return Center(
            child: AppCard(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.key_rounded, size: 48, color: const Color(0xFF94A3B8)),
                    const Gap(12),
                    Text(
                      'Lisans kaydı bulunmuyor',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
          );
        }

        final expired = licenses.where((l) => l.isExpired).toList();
        final expiringSoon = licenses.where((l) => l.isExpiringSoon).toList();
        final active = licenses.where((l) => !l.isExpired && !l.isExpiringSoon).toList();

        return ListView(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          children: [
            Row(
              children: [
                Expanded(child: _SummaryCard(title: 'Toplam', value: licenses.length.toString(), color: AppTheme.primary)),
                const Gap(12),
                Expanded(child: _SummaryCard(title: 'Süresi Dolan', value: expired.length.toString(), color: AppTheme.error)),
                const Gap(12),
                Expanded(child: _SummaryCard(title: 'Yaklaşan', value: expiringSoon.length.toString(), color: AppTheme.warning)),
              ],
            ),
            const Gap(16),
            if (expired.isNotEmpty) ...[
              _SectionHeader(title: 'Süresi Dolanlar', color: AppTheme.error),
              const Gap(8),
              ...expired.map((l) => _LicenseCard(license: l, dateFormat: dateFormat)),
              const Gap(16),
            ],
            if (expiringSoon.isNotEmpty) ...[
              _SectionHeader(title: '30 Gün İçinde Dolacaklar', color: AppTheme.warning),
              const Gap(8),
              ...expiringSoon.map((l) => _LicenseCard(license: l, dateFormat: dateFormat)),
              const Gap(16),
            ],
            if (active.isNotEmpty) ...[
              _SectionHeader(title: 'Aktif Lisanslar', color: AppTheme.success),
              const Gap(8),
              ...active.map((l) => _LicenseCard(license: l, dateFormat: dateFormat)),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, __) => const Center(child: Text('Lisanslar yüklenemedi')),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.title, required this.value, required this.color});

  final String title;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: [
          Text(title, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B))),
          const Gap(4),
          Text(value, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: color)),
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
        Container(width: 4, height: 20, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const Gap(10),
        Text(title, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _LineCard extends StatelessWidget {
  const _LineCard({required this.line, required this.dateFormat});

  final Line line;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    final (statusLabel, statusTone) = line.isExpired
        ? ('Süresi Doldu', AppBadgeTone.error)
        : line.isExpiringSoon
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
                color: (line.isExpired ? AppTheme.error : AppTheme.primary).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.phone_android_rounded, color: line.isExpired ? AppTheme.error : AppTheme.primary, size: 22),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.number, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap(2),
                  Text(line.customerName ?? '-', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B))),
                  if (line.expiresAt != null) ...[
                    const Gap(2),
                    Text('Bitiş: ${dateFormat.format(line.expiresAt!)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8))),
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
                color: (license.isExpired ? AppTheme.error : AppTheme.success).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.key_rounded, color: license.isExpired ? AppTheme.error : AppTheme.success, size: 22),
            ),
            const Gap(14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(license.name, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                  const Gap(2),
                  Text(license.customerName ?? '-', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B))),
                  if (license.expiresAt != null) ...[
                    const Gap(2),
                    Text('Bitiş: ${dateFormat.format(license.expiresAt!)}', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8))),
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
