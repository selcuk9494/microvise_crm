import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import 'customers_providers.dart';
import 'customer_form_dialog.dart';

final customerDetailProvider = FutureProvider.family<CustomerDetail, String>((
  ref,
  customerId,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw Exception('Supabase yapılandırılmamış.');

  final row = await client
      .from('customers')
      .select(
        'id,name,city,email,vkn,tckn_ms,notes,phone_1,phone_1_title,phone_2,phone_2_title,phone_3,phone_3_title,is_active,created_at',
      )
      .eq('id', customerId)
      .maybeSingle();

  if (row == null) throw Exception('Müşteri bulunamadı.');
  return CustomerDetail.fromJson(row);
});

final customerLinesProvider = FutureProvider.family<List<CustomerLine>, String>(
  (ref, customerId) async {
    final client = ref.watch(supabaseClientProvider);
    if (client == null) return const [];
    final rows = await client
        .from('lines')
        .select(
          'id,label,number,sim_number,starts_at,ends_at,expires_at,is_active',
        )
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return (rows as List)
        .map((e) => CustomerLine.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  },
);

final customerLicensesProvider =
    FutureProvider.family<List<CustomerLicense>, String>((
      ref,
      customerId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];
      final rows = await client
          .from('licenses')
          .select('id,name,license_type,starts_at,ends_at,expires_at,is_active')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => CustomerLicense.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    });

final customerBranchesProvider =
    FutureProvider.family<List<CustomerBranch>, String>((
      ref,
      customerId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];

      final rows = await client
          .from('branches')
          .select(
            'id,name,city,address,phone,location_lat,location_lng,is_active,created_at',
          )
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);

      return (rows as List)
          .map((e) => CustomerBranch.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    });

final customersForTransferProvider = FutureProvider<List<_CustomerOption>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('customers')
      .select('id,name,is_active')
      .order('name');

  return (rows as List)
      .map((e) => _CustomerOption.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final customerWorkOrdersProvider =
    FutureProvider.family<List<CustomerWorkOrder>, String>((
      ref,
      customerId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];
      final rows = await client
          .from('work_orders')
          .select('id,title,status,scheduled_date,is_active')
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      return (rows as List)
          .map((e) => CustomerWorkOrder.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);
    });

class CustomerDetailScreen extends ConsumerWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(customerDetailProvider(customerId));

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        bottom: false,
        child: detailAsync.when(
          data: (detail) => _Content(detail: detail),
          loading: () => Skeletonizer(
            enabled: true,
            child: _Content(
              detail: CustomerDetail(
                id: customerId,
                name: 'Microvise Teknoloji A.Ş.',
                city: 'İstanbul',
                email: 'ornek@firma.com',
                vkn: '1234567890',
                tcknMs: 'MS-1001',
                notes: 'Notlar burada görünür.',
                phone1: '0 555 555 55 55',
                phone1Title: 'Yetkili',
                phone2: '0 212 000 00 00',
                phone2Title: 'Muhasebe',
                phone3: null,
                phone3Title: null,
                isActive: true,
                createdAt: DateTime.now(),
              ),
            ),
          ),
          error: (error, stackTrace) => Center(
            child: AppCard(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Müşteri detayları yüklenemedi.',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const Gap(10),
                  Text(
                    'Yetki, bağlantı veya kayıt kontrolü yapın.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                  const Gap(14),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: const Text('Geri Dön'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Content extends ConsumerWidget {
  const _Content({required this.detail});

  final CustomerDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 5,
      child: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Geri',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back_rounded),
                  ),
                  const Gap(8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          detail.name,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Gap(4),
                        Row(
                          children: [
                            AppBadge(
                              label: detail.isActive ? 'Aktif' : 'Pasif',
                              tone: detail.isActive
                                  ? AppBadgeTone.success
                                  : AppBadgeTone.neutral,
                            ),
                            if (detail.city != null) ...[
                              const Gap(10),
                              Text(
                                detail.city!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () async {
                      await _showEditCustomerDialog(
                        context,
                        ref,
                        detail: detail,
                      );
                    },
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Düzenle'),
                  ),
                ],
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 14),
            sliver: SliverToBoxAdapter(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      tabs: [
                        Tab(text: 'Genel'),
                        Tab(text: 'Şubeler'),
                        Tab(text: 'Hatlar'),
                        Tab(text: 'Lisanslar'),
                        Tab(text: 'İş Emirleri'),
                      ],
                    ),
                    const Divider(height: 1),
                    SizedBox(
                      height: 620,
                      child: TabBarView(
                        children: [
                          _GeneralTab(detail: detail),
                          _BranchesTab(customerId: detail.id),
                          _LinesTab(customerId: detail.id),
                          _LicensesTab(customerId: detail.id),
                          _WorkOrdersTab(customerId: detail.id),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _GeneralTab extends ConsumerWidget {
  const _GeneralTab({required this.detail});

  final CustomerDetail detail;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final date = DateFormat('d MMMM y', 'tr_TR').format(detail.createdAt);
    final locationsAsync = ref.watch(customerLocationsProvider(detail.id));

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Genel Bilgiler',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const Gap(14),
          _InfoRow(label: 'Firma Adı', value: detail.name),
          const Gap(10),
          _InfoRow(label: 'Şehir', value: detail.city ?? '—'),
          const Gap(10),
          _InfoRow(label: 'E-posta', value: detail.email ?? '—'),
          const Gap(10),
          _InfoRow(label: 'VKN', value: detail.vkn ?? '—'),
          const Gap(10),
          _InfoRow(label: 'TCKN-MŞ', value: detail.tcknMs ?? '—'),
          const Gap(10),
          _InfoRow(
            label: detail.phone1Title ?? 'Telefon 1',
            value: detail.phone1 ?? '—',
          ),
          const Gap(10),
          _InfoRow(
            label: detail.phone2Title ?? 'Telefon 2',
            value: detail.phone2 ?? '—',
          ),
          const Gap(10),
          _InfoRow(
            label: detail.phone3Title ?? 'Telefon 3',
            value: detail.phone3 ?? '—',
          ),
          const Gap(10),
          _InfoRow(label: 'Kayıt Tarihi', value: date),
          const Gap(16),
          Text('Konumlar', style: Theme.of(context).textTheme.titleSmall),
          const Gap(10),
          locationsAsync.when(
            data: (locations) {
              if (locations.isEmpty) {
                return Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    'Henüz müşteri konumu eklenmemiş.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  for (final location in locations) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            location.title,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          if (location.description?.trim().isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                location.description!,
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF475569)),
                              ),
                            ),
                          if (location.address?.trim().isNotEmpty ?? false)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                location.address!,
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ),
                          if (location.locationLat != null ||
                              location.locationLng != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'Konum: ${location.locationLat?.toStringAsFixed(5) ?? '-'}, ${location.locationLng?.toStringAsFixed(5) ?? '-'}',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const Gap(10),
                  ],
                ],
              );
            },
            loading: () => const LinearProgressIndicator(minHeight: 2),
            error: (error, stackTrace) => const SizedBox.shrink(),
          ),
          if (detail.notes?.trim().isNotEmpty ?? false) ...[
            const Gap(16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                detail.notes!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFF0F172A),
                ),
              ),
            ),
          ],
          const Gap(18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.18),
                    ),
                  ),
                  child: const Icon(
                    Icons.flash_on_rounded,
                    color: AppTheme.primary,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Hızlı Aksiyonlar',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        'Yeni iş emri açın, hat/ lisans ekleyin veya servis kaydı başlatın.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
                      ),
                    ],
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

class _BranchesTab extends ConsumerWidget {
  const _BranchesTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final branchesAsync = ref.watch(customerBranchesProvider(customerId));

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Şubeler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _showAddBranchDialog(
                    context,
                    ref,
                    customerId: customerId,
                  );
                  ref.invalidate(customerBranchesProvider(customerId));
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Şube Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: branchesAsync.when(
              data: (branches) {
                if (branches.isEmpty) {
                  return const _TabEmpty(
                    text: 'Bu müşteriye ait şube bulunamadı.',
                  );
                }
                return ListView.separated(
                  itemCount: branches.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) => _BranchItem(
                    branch: branches[index],
                    onEdit: () async {
                      await _showBranchDialog(
                        context,
                        ref,
                        customerId: customerId,
                        branch: branches[index],
                      );
                      ref.invalidate(customerBranchesProvider(customerId));
                    },
                    onToggleActive: () async {
                      final client = ref.read(supabaseClientProvider);
                      if (client == null) return;
                      await client
                          .from('branches')
                          .update({'is_active': !branches[index].isActive})
                          .eq('id', branches[index].id);
                      ref.invalidate(customerBranchesProvider(customerId));
                    },
                  ),
                );
              },
              loading: () => const _ListSkeleton(),
              error: (error, stackTrace) =>
                  const _TabError(text: 'Şubeler yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinesTab extends ConsumerWidget {
  const _LinesTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(customerLinesProvider(customerId));
    final isAdmin = ref.watch(isAdminProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Hatlar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _showSellLineDialog(
                    context,
                    ref,
                    customerId: customerId,
                  );
                  ref.invalidate(customerLinesProvider(customerId));
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Hat Sat'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: linesAsync.when(
              data: (lines) {
                if (lines.isEmpty) {
                  return const _TabEmpty(
                    text: 'Bu müşteriye ait hat bulunamadı.',
                  );
                }
                return ListView.separated(
                  itemCount: lines.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) => _LineItem(
                    line: lines[index],
                    customerId: customerId,
                    canTransfer: isAdmin,
                  ),
                );
              },
              loading: () => const _ListSkeleton(),
              error: (error, stackTrace) =>
                  const _TabError(text: 'Hatlar yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _LicensesTab extends ConsumerWidget {
  const _LicensesTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final licensesAsync = ref.watch(customerLicensesProvider(customerId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'GMP3 Lisansları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await _showSellGmp3Dialog(
                    context,
                    ref,
                    customerId: customerId,
                  );
                  ref.invalidate(customerLicensesProvider(customerId));
                },
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('GMP3 Sat'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: licensesAsync.when(
              data: (items) {
                final gmp3 = items
                    .where((e) => e.licenseType == 'gmp3')
                    .toList();
                if (gmp3.isEmpty) {
                  return const _TabEmpty(
                    text: 'Bu müşteriye ait GMP3 lisansı bulunamadı.',
                  );
                }
                return ListView.separated(
                  itemCount: gmp3.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) => _LicenseItem(
                    customerId: customerId,
                    license: gmp3[index],
                  ),
                );
              },
              loading: () => const _ListSkeleton(),
              error: (error, stackTrace) =>
                  const _TabError(text: 'Lisanslar yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkOrdersTab extends ConsumerWidget {
  const _WorkOrdersTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workOrdersAsync = ref.watch(customerWorkOrdersProvider(customerId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: workOrdersAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return const _TabEmpty(
              text: 'Bu müşteriye ait iş emri bulunamadı.',
            );
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(10),
            itemBuilder: (context, index) {
              final w = items[index];
              final status = switch (w.status) {
                'open' => ('Açık', AppBadgeTone.warning),
                'in_progress' => ('Devam Ediyor', AppBadgeTone.primary),
                'done' => ('Tamamlandı', AppBadgeTone.success),
                _ => ('Bilinmiyor', AppBadgeTone.neutral),
              };
              final when = w.scheduledDate == null
                  ? 'Planlanmadı'
                  : DateFormat('d MMM', 'tr_TR').format(w.scheduledDate!);

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            w.title,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: w.isActive
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                          const Gap(4),
                          Text(
                            when,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    AppBadge(label: status.$1, tone: status.$2),
                  ],
                ),
              );
            },
          );
        },
        loading: () => const _ListSkeleton(),
        error: (error, stackTrace) =>
            const _TabError(text: 'İş emirleri yüklenemedi.'),
      ),
    );
  }
}

class _BranchItem extends StatelessWidget {
  const _BranchItem({
    required this.branch,
    required this.onEdit,
    required this.onToggleActive,
  });

  final CustomerBranch branch;
  final Future<void> Function() onEdit;
  final Future<void> Function() onToggleActive;

  @override
  Widget build(BuildContext context) {
    final title = branch.name;
    final subtitle = [
      if (branch.city?.trim().isNotEmpty ?? false) branch.city!,
      if (branch.phone?.trim().isNotEmpty ?? false) branch.phone!,
    ].join(' • ');

    final location = branch.locationLat != null && branch.locationLng != null
        ? '${branch.locationLat!.toStringAsFixed(5)}, ${branch.locationLng!.toStringAsFixed(5)}'
        : null;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: branch.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
              ),
              AppBadge(
                label: branch.isActive ? 'Aktif' : 'Pasif',
                tone: branch.isActive
                    ? AppBadgeTone.success
                    : AppBadgeTone.neutral,
              ),
              const Gap(8),
              PopupMenuButton<String>(
                onSelected: (value) async {
                  if (value == 'edit') {
                    await onEdit();
                    return;
                  }
                  await onToggleActive();
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(branch.isActive ? 'Pasif Yap' : 'Aktif Yap'),
                  ),
                ],
              ),
            ],
          ),
          if (subtitle.isNotEmpty) ...[
            const Gap(6),
            Text(
              subtitle,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
            ),
          ],
          if (branch.address?.trim().isNotEmpty ?? false) ...[
            const Gap(8),
            Text(
              branch.address!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF475569)),
            ),
          ],
          if (location != null) ...[
            const Gap(8),
            Text(
              'Konum: $location',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
            ),
          ],
        ],
      ),
    );
  }
}

class _LineItem extends ConsumerStatefulWidget {
  const _LineItem({
    required this.line,
    required this.customerId,
    required this.canTransfer,
  });

  final CustomerLine line;
  final String customerId;
  final bool canTransfer;

  @override
  ConsumerState<_LineItem> createState() => _LineItemState();
}

class _LineItemState extends ConsumerState<_LineItem> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final line = widget.line;
    final endsAt = line.endsAt;
    final startsAt = line.startsAt;

    final now = DateTime.now();
    final tone = !line.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final statusLabel = !line.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final period = (startsAt == null && endsAt == null)
        ? null
        : '${startsAt == null ? '—' : DateFormat('d MMM y', 'tr_TR').format(startsAt)}'
              ' → ${endsAt == null ? '—' : DateFormat('d MMM y', 'tr_TR').format(endsAt)}';

    final subtitle = [
      if (line.number?.trim().isNotEmpty ?? false) 'Hat: ${line.number}',
      if (line.simNumber?.trim().isNotEmpty ?? false) 'SIM: ${line.simNumber}',
    ].join(' • ');

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.label?.trim().isNotEmpty ?? false
                      ? line.label!
                      : (line.number ?? 'Hat'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: line.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const Gap(4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
                if (period != null) ...[
                  const Gap(4),
                  Text(
                    period,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppBadge(label: statusLabel, tone: tone),
              if (widget.canTransfer) ...[
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
                    MenuItemButton(
                      onPressed: () async {
                        if (_busy) return;
                        setState(() => _busy = true);
                        try {
                          await _showTransferLineDialog(
                            context,
                            ref,
                            lineId: line.id,
                            fromCustomerId: widget.customerId,
                          );
                          ref.invalidate(
                            customerLinesProvider(widget.customerId),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                      child: const Text('Devir Et'),
                    ),
                    MenuItemButton(
                      onPressed: () async {
                        if (_busy) return;
                        setState(() => _busy = true);
                        try {
                          await _extendLineAndQueueInvoice(
                            context,
                            ref,
                            lineId: line.id,
                            customerId: widget.customerId,
                            currentEndsAt: line.endsAt,
                          );
                          ref.invalidate(
                            customerLinesProvider(widget.customerId),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                      child: const Text('Uzat + Fatura Listesi'),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _LicenseItem extends ConsumerStatefulWidget {
  const _LicenseItem({required this.customerId, required this.license});

  final String customerId;
  final CustomerLicense license;

  @override
  ConsumerState<_LicenseItem> createState() => _LicenseItemState();
}

class _LicenseItemState extends ConsumerState<_LicenseItem> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final license = widget.license;
    final now = DateTime.now();
    final endsAt = license.endsAt;
    final isAdmin = ref.watch(isAdminProvider);
    final tone = !license.isActive
        ? AppBadgeTone.neutral
        : endsAt == null
        ? AppBadgeTone.neutral
        : endsAt.isBefore(now)
        ? AppBadgeTone.error
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final label = !license.isActive
        ? 'Pasif'
        : endsAt == null
        ? 'Tarihsiz'
        : endsAt.isBefore(now)
        ? 'Bitmiş'
        : endsAt.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final period = (license.startsAt == null && license.endsAt == null)
        ? null
        : '${license.startsAt == null ? '—' : DateFormat('d MMM y', 'tr_TR').format(license.startsAt!)}'
              ' → ${license.endsAt == null ? '—' : DateFormat('d MMM y', 'tr_TR').format(license.endsAt!)}';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  license.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: license.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                if (period != null) ...[
                  const Gap(4),
                  Text(
                    period,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              AppBadge(label: label, tone: tone),
              if (isAdmin) ...[
                const Gap(8),
                OutlinedButton(
                  onPressed: _busy
                      ? null
                      : () async {
                          setState(() => _busy = true);
                          try {
                            await _extendGmp3AndQueueInvoice(
                              context,
                              ref,
                              licenseId: license.id,
                              customerId: widget.customerId,
                              currentEndsAt: license.endsAt,
                              name: license.name,
                            );
                          } finally {
                            if (mounted) setState(() => _busy = false);
                          }
                        },
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Uzat + Fatura'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showAddBranchDialog(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
}) async {
  await _showBranchDialog(context, ref, customerId: customerId);
}

Future<void> _showBranchDialog(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
  CustomerBranch? branch,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) =>
        _AddBranchDialog(customerId: customerId, branch: branch),
  );
}

class _AddBranchDialog extends ConsumerStatefulWidget {
  const _AddBranchDialog({required this.customerId, this.branch});

  final String customerId;
  final CustomerBranch? branch;

  @override
  ConsumerState<_AddBranchDialog> createState() => _AddBranchDialogState();
}

class _AddBranchDialogState extends ConsumerState<_AddBranchDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _cityController;
  late final TextEditingController _addressController;
  late final TextEditingController _phoneController;
  late final TextEditingController _latController;
  late final TextEditingController _lngController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final branch = widget.branch;
    _nameController = TextEditingController(text: branch?.name ?? 'Merkez');
    _cityController = TextEditingController(text: branch?.city ?? '');
    _addressController = TextEditingController(text: branch?.address ?? '');
    _phoneController = TextEditingController(text: branch?.phone ?? '');
    _latController = TextEditingController(
      text: branch?.locationLat?.toString() ?? '',
    );
    _lngController = TextEditingController(
      text: branch?.locationLng?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _cityController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final lat = double.tryParse(_latController.text.trim());
      final lng = double.tryParse(_lngController.text.trim());

      final payload = {
        'customer_id': widget.customerId,
        'name': _nameController.text.trim(),
        'city': _cityController.text.trim().isEmpty
            ? null
            : _cityController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'phone': _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        'location_lat': lat,
        'location_lng': lng,
        'is_active': widget.branch?.isActive ?? true,
      };

      if (widget.branch == null) {
        await client.from('branches').insert(payload);
      } else {
        await client
            .from('branches')
            .update(payload)
            .eq('id', widget.branch!.id);
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.branch == null ? 'Şube eklendi.' : 'Şube güncellendi.',
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.branch == null ? 'Şube eklenemedi.' : 'Şube güncellenemedi.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final citiesAsync = ref.watch(customerCitiesProvider);
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
                        widget.branch == null ? 'Şube Ekle' : 'Şube Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Şube İsmi',
                          hintText: 'Örn: Merkez',
                        ),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) {
                            return 'Şube ismi gerekli.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: citiesAsync.when(
                        data: (cities) => DropdownButtonFormField<String?>(
                          initialValue: _cityController.text.trim().isEmpty
                              ? null
                              : _cityController.text.trim(),
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Şehir seç'),
                            ),
                            ...cities.map(
                              (city) => DropdownMenuItem<String?>(
                                value: city,
                                child: Text(city),
                              ),
                            ),
                          ],
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _cityController.text = value ?? '',
                                ),
                          decoration: const InputDecoration(
                            labelText: 'Şube Şehir',
                          ),
                        ),
                        loading: () => TextFormField(
                          controller: _cityController,
                          enabled: false,
                          decoration: const InputDecoration(
                            labelText: 'Şube Şehir',
                            hintText: 'Şehirler yükleniyor',
                          ),
                        ),
                        error: (error, stackTrace) => TextFormField(
                          controller: _cityController,
                          decoration: const InputDecoration(
                            labelText: 'Şube Şehir',
                            hintText: 'Şehir bulunamadı',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _addressController,
                  minLines: 2,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Adres',
                    hintText: 'Cadde, sokak, no, ilçe...',
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'Şube Telefon',
                          hintText: '0 2xx xxx xx xx',
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextFormField(
                        controller: _latController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Konum Lat',
                          hintText: '41.0',
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextFormField(
                        controller: _lngController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Konum Lng',
                          hintText: '29.0',
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
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
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

Future<void> _showSellLineDialog(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SellLineDialog(customerId: customerId),
  );
}

class _SellLineDialog extends ConsumerStatefulWidget {
  const _SellLineDialog({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_SellLineDialog> createState() => _SellLineDialogState();
}

class _SellLineDialogState extends ConsumerState<_SellLineDialog> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController(text: 'Hat Satışı');
  final _numberController = TextEditingController();
  final _simController = TextEditingController();
  bool _saving = false;

  String? _branchId;

  @override
  void dispose() {
    _labelController.dispose();
    _numberController.dispose();
    _simController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, 12, 31);

      await client.from('lines').insert({
        'customer_id': widget.customerId,
        'branch_id': _branchId,
        'label': _labelController.text.trim().isEmpty
            ? null
            : _labelController.text.trim(),
        'number': _numberController.text.trim(),
        'sim_number': _simController.text.trim().isEmpty
            ? null
            : _simController.text.trim(),
        'starts_at': start.toIso8601String().substring(0, 10),
        'ends_at': end.toIso8601String().substring(0, 10),
        'expires_at': end.toIso8601String().substring(0, 10),
        'is_active': true,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat kaydedildi.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat kaydedilemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final branchesAsync = ref.watch(
      customerBranchesProvider(widget.customerId),
    );
    final now = DateTime.now();
    final startText = DateFormat('d MMM y', 'tr_TR').format(now);
    final endText = DateFormat(
      'd MMM y',
      'tr_TR',
    ).format(DateTime(now.year, 12, 31));

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
                        'Hat Satışı',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                branchesAsync.when(
                  data: (branches) => DropdownButtonFormField<String?>(
                    initialValue: _branchId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Şube seç (opsiyonel)'),
                      ),
                      ...branches.map(
                        (b) => DropdownMenuItem<String?>(
                          value: b.id,
                          child: Text(b.name),
                        ),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _branchId = v),
                    decoration: const InputDecoration(labelText: 'Şube'),
                  ),
                  loading: () => const SizedBox.shrink(),
                  error: (error, stackTrace) => const SizedBox.shrink(),
                ),
                const Gap(12),
                TextFormField(
                  controller: _numberController,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Hat Numarası',
                    hintText: '90555...',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return 'Hat numarası gerekli.';
                    }
                    return null;
                  },
                ),
                const Gap(12),
                TextFormField(
                  controller: _simController,
                  decoration: const InputDecoration(
                    labelText: 'SIM Numarası',
                    hintText: '89...',
                  ),
                ),
                const Gap(12),
                TextFormField(
                  controller: _labelController,
                  decoration: const InputDecoration(
                    labelText: 'Etiket',
                    hintText: 'Örn: Kurumsal Hat',
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          'Başlangıç: $startText\nBitiş: $endText',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF475569)),
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
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
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

Future<void> _showSellGmp3Dialog(
  BuildContext context,
  WidgetRef ref, {
  required String customerId,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _SellGmp3Dialog(customerId: customerId),
  );
}

class _SellGmp3Dialog extends ConsumerStatefulWidget {
  const _SellGmp3Dialog({required this.customerId});

  final String customerId;

  @override
  ConsumerState<_SellGmp3Dialog> createState() => _SellGmp3DialogState();
}

class _SellGmp3DialogState extends ConsumerState<_SellGmp3Dialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController(text: 'GMP3 Lisansı');
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      final start = DateTime(now.year, now.month, now.day);
      final end = DateTime(now.year, 12, 31);

      await client.from('licenses').insert({
        'customer_id': widget.customerId,
        'name': _nameController.text.trim(),
        'license_type': 'gmp3',
        'starts_at': start.toIso8601String().substring(0, 10),
        'ends_at': end.toIso8601String().substring(0, 10),
        'expires_at': end.toIso8601String().substring(0, 10),
        'is_active': true,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GMP3 lisansı kaydedildi.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('GMP3 lisansı kaydedilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startText = DateFormat('d MMM y', 'tr_TR').format(now);
    final endText = DateFormat(
      'd MMM y',
      'tr_TR',
    ).format(DateTime(now.year, 12, 31));

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
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
                        'GMP3 Satışı',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Lisans Adı',
                    hintText: 'Örn: GMP3 Lisansı',
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? 'Lisans adı gerekli.'
                      : null,
                ),
                const Gap(12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    'Başlangıç: $startText\nBitiş: $endText',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF475569),
                    ),
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
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

Future<void> _showTransferLineDialog(
  BuildContext context,
  WidgetRef ref, {
  required String lineId,
  required String fromCustomerId,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final customers = await ref.read(customersForTransferProvider.future);
  if (!context.mounted) return;
  final selected = await showDialog<_CustomerOption?>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _TransferLineDialog(
      customers: customers,
      fromCustomerId: fromCustomerId,
    ),
  );
  if (!context.mounted) return;

  if (selected == null) return;
  if (selected.id == fromCustomerId) return;

  await client.from('line_transfers').insert({
    'line_id': lineId,
    'from_customer_id': fromCustomerId,
    'to_customer_id': selected.id,
    'transferred_by': client.auth.currentUser?.id,
  });

  await client
      .from('lines')
      .update({
        'customer_id': selected.id,
        'branch_id': null,
        'transferred_at': DateTime.now().toIso8601String(),
        'transferred_by': client.auth.currentUser?.id,
      })
      .eq('id', lineId);

  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Hat devredildi.')));
  }
}

Future<void> _extendLineAndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required String lineId,
  required String customerId,
  required DateTime? currentEndsAt,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final now = DateTime.now();
  final baseYear = (currentEndsAt != null && currentEndsAt.isAfter(now))
      ? currentEndsAt.year
      : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  try {
    await client
        .from('lines')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', lineId);

    try {
      await client.from('invoice_items').insert({
        'customer_id': customerId,
        'item_type': 'line_renewal',
        'source_table': 'lines',
        'source_id': lineId,
        'description': 'Hat uzatma (yeni bitiş: $newEndStr)',
        'status': 'pending',
        'created_by': client.auth.currentUser?.id,
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hat uzatıldı; fatura kuyruğuna eklenemedi.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hat uzatıldı ve fatura listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hat uzatılamadı.')));
    }
  }
}

Future<void> _extendGmp3AndQueueInvoice(
  BuildContext context,
  WidgetRef ref, {
  required String licenseId,
  required String customerId,
  required DateTime? currentEndsAt,
  required String name,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final now = DateTime.now();
  final baseYear = (currentEndsAt != null && currentEndsAt.isAfter(now))
      ? currentEndsAt.year
      : now.year;
  final newEnd = DateTime(baseYear + 1, 12, 31);
  final newEndStr = newEnd.toIso8601String().substring(0, 10);

  try {
    await client
        .from('licenses')
        .update({'ends_at': newEndStr, 'expires_at': newEndStr})
        .eq('id', licenseId);

    try {
      await client.from('invoice_items').insert({
        'customer_id': customerId,
        'item_type': 'gmp3_renewal',
        'source_table': 'licenses',
        'source_id': licenseId,
        'description': 'GMP3 uzatma ($name) (yeni bitiş: $newEndStr)',
        'status': 'pending',
        'created_by': client.auth.currentUser?.id,
      });
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('GMP3 uzatıldı; fatura kuyruğuna eklenemedi.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('GMP3 uzatıldı ve fatura listesine eklendi.'),
        ),
      );
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('GMP3 uzatılamadı.')));
    }
  }
}

class _TransferLineDialog extends StatefulWidget {
  const _TransferLineDialog({
    required this.customers,
    required this.fromCustomerId,
  });

  final List<_CustomerOption> customers;
  final String fromCustomerId;

  @override
  State<_TransferLineDialog> createState() => _TransferLineDialogState();
}

class _TransferLineDialogState extends State<_TransferLineDialog> {
  _CustomerOption? _selected;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

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
              Autocomplete<_CustomerOption>(
                optionsBuilder: (text) {
                  final q = text.text.trim().toLowerCase();
                  final list = widget.customers
                      .where((c) => c.id != widget.fromCustomerId)
                      .toList(growable: false);
                  if (q.isEmpty) return list.take(20);
                  return list
                      .where((c) => c.name.toLowerCase().contains(q))
                      .take(20);
                },
                displayStringForOption: (o) => o.name,
                onSelected: (o) {
                  setState(() => _selected = o);
                  _controller.text = o.name;
                },
                fieldViewBuilder: (context, textController, focusNode, _) {
                  textController.text = _controller.text;
                  textController.selection = TextSelection.collapsed(
                    offset: textController.text.length,
                  );
                  return TextField(
                    controller: textController,
                    focusNode: focusNode,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Müşteri',
                      hintText: 'Firma adı yazın ve seçin',
                    ),
                    onChanged: (_) => setState(() => _selected = null),
                  );
                },
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

class _ExpiryItem extends StatelessWidget {
  const _ExpiryItem({
    required this.title,
    required this.subtitle,
    required this.expiresAt,
    required this.active,
  });

  final String title;
  final String? subtitle;
  final DateTime? expiresAt;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final tone = !active
        ? AppBadgeTone.neutral
        : expiresAt == null
        ? AppBadgeTone.neutral
        : expiresAt!.isBefore(now)
        ? AppBadgeTone.error
        : expiresAt!.isBefore(now.add(const Duration(days: 30)))
        ? AppBadgeTone.warning
        : AppBadgeTone.success;

    final label = !active
        ? 'Pasif'
        : expiresAt == null
        ? 'Tarihsiz'
        : expiresAt!.isBefore(now)
        ? 'Bitmiş'
        : expiresAt!.isBefore(now.add(const Duration(days: 30)))
        ? 'Yaklaşıyor'
        : 'Aktif';

    final dateText = expiresAt == null
        ? '—'
        : DateFormat('d MMM y', 'tr_TR').format(expiresAt!);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    decoration: active
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
                const Gap(3),
                Row(
                  children: [
                    if (subtitle != null)
                      Expanded(
                        child: Text(
                          subtitle!,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          dateText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        dateText,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A3B8),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(10),
          AppBadge(label: label, tone: tone),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 140,
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

class _TabEmpty extends StatelessWidget {
  const _TabEmpty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class _TabError extends StatelessWidget {
  const _TabError({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
      ),
    );
  }
}

class _ListSkeleton extends StatelessWidget {
  const _ListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: ListView.separated(
        itemCount: 6,
        separatorBuilder: (context, index) => const Gap(10),
        itemBuilder: (context, index) => const _ExpiryItem(
          title: 'Kurumsal Hat',
          subtitle: '905555555555',
          expiresAt: null,
          active: true,
        ),
      ),
    );
  }
}

Future<void> _showEditCustomerDialog(
  BuildContext context,
  WidgetRef ref, {
  required CustomerDetail detail,
}) async {
  final updated = await showEditCustomerDialog(
    context,
    initialData: CustomerFormData(
      id: detail.id,
      name: detail.name,
      city: detail.city,
      email: detail.email,
      vkn: detail.vkn,
      tcknMs: detail.tcknMs,
      phone1Title: detail.phone1Title,
      phone1: detail.phone1,
      phone2Title: detail.phone2Title,
      phone2: detail.phone2,
      phone3Title: detail.phone3Title,
      phone3: detail.phone3,
      notes: detail.notes,
      isActive: detail.isActive,
    ),
  );

  if (updated != true) return;
  ref.invalidate(customerDetailProvider(detail.id));
  ref.invalidate(customerLocationsProvider(detail.id));
  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
}

class CustomerDetail {
  const CustomerDetail({
    required this.id,
    required this.name,
    required this.city,
    required this.email,
    required this.vkn,
    required this.tcknMs,
    required this.notes,
    required this.phone1,
    required this.phone1Title,
    required this.phone2,
    required this.phone2Title,
    required this.phone3,
    required this.phone3Title,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? city;
  final String? email;
  final String? vkn;
  final String? tcknMs;
  final String? notes;
  final String? phone1;
  final String? phone1Title;
  final String? phone2;
  final String? phone2Title;
  final String? phone3;
  final String? phone3Title;
  final bool isActive;
  final DateTime createdAt;

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    return CustomerDetail(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      email: json['email']?.toString(),
      vkn: json['vkn']?.toString(),
      tcknMs: json['tckn_ms']?.toString(),
      notes: json['notes']?.toString(),
      phone1: json['phone_1']?.toString(),
      phone1Title: json['phone_1_title']?.toString(),
      phone2: json['phone_2']?.toString(),
      phone2Title: json['phone_2_title']?.toString(),
      phone3: json['phone_3']?.toString(),
      phone3Title: json['phone_3_title']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class CustomerLine {
  const CustomerLine({
    required this.id,
    required this.label,
    required this.number,
    required this.simNumber,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String? label;
  final String? number;
  final String? simNumber;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory CustomerLine.fromJson(Map<String, dynamic> json) {
    return CustomerLine(
      id: json['id'].toString(),
      label: json['label']?.toString(),
      number: json['number']?.toString(),
      simNumber: json['sim_number']?.toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerLicense {
  const CustomerLicense({
    required this.id,
    required this.name,
    required this.licenseType,
    required this.startsAt,
    required this.endsAt,
    required this.isActive,
  });

  final String id;
  final String name;
  final String licenseType;
  final DateTime? startsAt;
  final DateTime? endsAt;
  final bool isActive;

  factory CustomerLicense.fromJson(Map<String, dynamic> json) {
    return CustomerLicense(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      licenseType: (json['license_type'] ?? 'gmp3').toString(),
      startsAt: DateTime.tryParse(json['starts_at']?.toString() ?? ''),
      endsAt:
          DateTime.tryParse(json['ends_at']?.toString() ?? '') ??
          DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerWorkOrder {
  const CustomerWorkOrder({
    required this.id,
    required this.title,
    required this.status,
    required this.scheduledDate,
    required this.isActive,
  });

  final String id;
  final String title;
  final String status;
  final DateTime? scheduledDate;
  final bool isActive;

  factory CustomerWorkOrder.fromJson(Map<String, dynamic> json) {
    return CustomerWorkOrder(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      scheduledDate: DateTime.tryParse(
        json['scheduled_date']?.toString() ?? '',
      ),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerBranch {
  const CustomerBranch({
    required this.id,
    required this.name,
    required this.city,
    required this.address,
    required this.phone,
    required this.locationLat,
    required this.locationLng,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? city;
  final String? address;
  final String? phone;
  final double? locationLat;
  final double? locationLng;
  final bool isActive;

  factory CustomerBranch.fromJson(Map<String, dynamic> json) {
    return CustomerBranch(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class _CustomerOption {
  const _CustomerOption({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
