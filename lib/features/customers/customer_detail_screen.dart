import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';

final customerDetailProvider =
    FutureProvider.family<CustomerDetail, String>((ref, customerId) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) throw Exception('Supabase yapılandırılmamış.');

  final row = await client
      .from('customers')
      .select('id,name,city,is_active,created_at')
      .eq('id', customerId)
      .maybeSingle();

  if (row == null) throw Exception('Müşteri bulunamadı.');
  return CustomerDetail.fromJson(row);
});

final customerLinesProvider =
    FutureProvider.family<List<CustomerLine>, String>((ref, customerId) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('lines')
      .select('id,label,number,expires_at,is_active')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((e) => CustomerLine.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final customerLicensesProvider =
    FutureProvider.family<List<CustomerLicense>, String>((ref, customerId) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('licenses')
      .select('id,name,expires_at,is_active')
      .eq('customer_id', customerId)
      .order('created_at', ascending: false);
  return (rows as List)
      .map((e) => CustomerLicense.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final customerWorkOrdersProvider =
    FutureProvider.family<List<CustomerWorkOrder>, String>((ref, customerId) async {
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
                isActive: true,
                createdAt: DateTime.now(),
              ),
            ),
          ),
          error: (_, __) => Center(
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
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
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
      length: 4,
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
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () {},
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
                      labelPadding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      tabs: [
                        Tab(text: 'Genel'),
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

class _GeneralTab extends StatelessWidget {
  const _GeneralTab({required this.detail});

  final CustomerDetail detail;

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMMM y', 'tr_TR').format(detail.createdAt);

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Genel Bilgiler', style: Theme.of(context).textTheme.titleMedium),
          const Gap(14),
          _InfoRow(label: 'Firma Adı', value: detail.name),
          const Gap(10),
          _InfoRow(label: 'Şehir', value: detail.city ?? '—'),
          const Gap(10),
          _InfoRow(label: 'Kayıt Tarihi', value: date),
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
                    border:
                        Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
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
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
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

class _LinesTab extends ConsumerWidget {
  const _LinesTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linesAsync = ref.watch(customerLinesProvider(customerId));
    return Padding(
      padding: const EdgeInsets.all(16),
      child: linesAsync.when(
        data: (lines) => _ExpiryList(
          emptyText: 'Bu müşteriye ait hat bulunamadı.',
          items: [
            for (final l in lines)
              _ExpiryItem(
                title: l.label ?? l.number ?? 'Hat',
                subtitle: l.number,
                expiresAt: l.expiresAt,
                active: l.isActive,
              ),
          ],
        ),
        loading: () => const _ListSkeleton(),
        error: (_, __) => const _TabError(text: 'Hatlar yüklenemedi.'),
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
      child: licensesAsync.when(
        data: (items) => _ExpiryList(
          emptyText: 'Bu müşteriye ait lisans bulunamadı.',
          items: [
            for (final l in items)
              _ExpiryItem(
                title: l.name,
                subtitle: null,
                expiresAt: l.expiresAt,
                active: l.isActive,
              ),
          ],
        ),
        loading: () => const _ListSkeleton(),
        error: (_, __) => const _TabError(text: 'Lisanslar yüklenemedi.'),
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
            return const _TabEmpty(text: 'Bu müşteriye ait iş emri bulunamadı.');
          }
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Gap(10),
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
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  decoration: w.isActive
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                          const Gap(4),
                          Text(
                            when,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
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
        error: (_, __) => const _TabError(text: 'İş emirleri yüklenemedi.'),
      ),
    );
  }
}

class _ExpiryList extends StatelessWidget {
  const _ExpiryList({required this.emptyText, required this.items});

  final String emptyText;
  final List<_ExpiryItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return _TabEmpty(text: emptyText);
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, __) => const Gap(10),
      itemBuilder: (context, index) => items[index],
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
                        decoration:
                            active ? TextDecoration.none : TextDecoration.lineThrough,
                      ),
                ),
                const Gap(3),
                Row(
                  children: [
                    if (subtitle != null)
                      Expanded(
                        child: Text(
                          subtitle!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      )
                    else
                      Expanded(
                        child: Text(
                          dateText,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                    if (subtitle != null)
                      Text(
                        dateText,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF94A3B8)),
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
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
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
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF64748B)),
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
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: const Color(0xFF64748B)),
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
        separatorBuilder: (_, __) => const Gap(10),
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

class CustomerDetail {
  const CustomerDetail({
    required this.id,
    required this.name,
    required this.city,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String name;
  final String? city;
  final bool isActive;
  final DateTime createdAt;

  factory CustomerDetail.fromJson(Map<String, dynamic> json) {
    return CustomerDetail(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class CustomerLine {
  const CustomerLine({
    required this.id,
    required this.label,
    required this.number,
    required this.expiresAt,
    required this.isActive,
  });

  final String id;
  final String? label;
  final String? number;
  final DateTime? expiresAt;
  final bool isActive;

  factory CustomerLine.fromJson(Map<String, dynamic> json) {
    return CustomerLine(
      id: json['id'].toString(),
      label: json['label']?.toString(),
      number: json['number']?.toString(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class CustomerLicense {
  const CustomerLicense({
    required this.id,
    required this.name,
    required this.expiresAt,
    required this.isActive,
  });

  final String id;
  final String name;
  final DateTime? expiresAt;
  final bool isActive;

  factory CustomerLicense.fromJson(Map<String, dynamic> json) {
    return CustomerLicense(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
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
      scheduledDate: DateTime.tryParse(json['scheduled_date']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
