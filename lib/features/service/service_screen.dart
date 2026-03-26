import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final serviceRecordsProvider = FutureProvider<List<ServiceRecord>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('service_records')
      .select('id,title,status,created_at,customers(name)')
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(25);

  return (rows as List).map((e) {
    final map = e as Map<String, dynamic>;
    final customers = map['customers'] as Map<String, dynamic>?;
    return ServiceRecord.fromJson({
      ...map,
      'customer_name': customers?['name'],
    });
  }).toList(growable: false);
});

class ServiceScreen extends ConsumerWidget {
  const ServiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(serviceRecordsProvider);

    return AppPageLayout(
      title: 'Servis',
      subtitle: 'Adım adım süreç, parça + işçilik ayrımı.',
      actions: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Servis'),
        ),
      ],
      body: recordsAsync.when(
        data: (items) {
          if (items.isEmpty) {
            return AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Henüz servis kaydı yok.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            );
          }

          return LayoutBuilder(
            builder: (context, constraints) {
              final twoCols = constraints.maxWidth >= 980;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    flex: twoCols ? 2 : 1,
                    child: AppCard(
                      padding: EdgeInsets.zero,
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (context, index) => _ServiceRow(item: items[index]),
                      ),
                    ),
                  ),
                  if (twoCols) const Gap(16),
                  if (twoCols)
                    Expanded(
                      flex: 3,
                      child: AppCard(
                        child: const _ServiceTimelinePreview(),
                      ),
                    ),
                ],
              );
            },
          );
        },
        loading: () => Skeletonizer(
          enabled: true,
          child: AppCard(
            padding: EdgeInsets.zero,
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: 8,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) => _ServiceRow(
                item: ServiceRecord(
                  id: '$index',
                  title: 'Yerinde servis ziyareti',
                  customerName: 'ACME Teknoloji',
                  status: 'in_progress',
                  createdAt: DateTime.now(),
                ),
              ),
            ),
          ),
        ),
        error: (_, __) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'Servis kayıtları yüklenemedi.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.item});

  final ServiceRecord item;

  @override
  Widget build(BuildContext context) {
    final status = switch (item.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Devam', AppBadgeTone.primary),
      'done' => ('Tamam', AppBadgeTone.success),
      _ => ('—', AppBadgeTone.neutral),
    };
    final date = DateFormat('d MMM', 'tr_TR').format(item.createdAt);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Gap(4),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.customerName ?? '—',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ),
                    Text(
                      date,
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
          AppBadge(label: status.$1, tone: status.$2),
        ],
      ),
    );
  }
}

class _ServiceTimelinePreview extends StatelessWidget {
  const _ServiceTimelinePreview();

  @override
  Widget build(BuildContext context) {
    final steps = const [
      ('Kayıt Açıldı', 'Talep alındı ve iş emri oluşturuldu.'),
      ('Yönlendirme', 'Teknisyen atandı ve planlama yapıldı.'),
      ('Yerinde Müdahale', 'Parça + işçilik ayrı işlendi.'),
      ('Kapanış', 'Ödeme ve imza tamamlandı.'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Süreç Önizleme', style: Theme.of(context).textTheme.titleMedium),
        const Gap(6),
        Text(
          'Servis kaydı kapanış akışı; ödeme + imza ekranı bu akışa bağlanır.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: const Color(0xFF64748B)),
        ),
        const Gap(16),
        for (int i = 0; i < steps.length; i++)
          Padding(
            padding: EdgeInsets.only(bottom: i == steps.length - 1 ? 0 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                  ),
                  child: Center(
                    child: Text(
                      '${i + 1}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: AppTheme.primary,
                          ),
                    ),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        steps[i].$1,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const Gap(3),
                      Text(
                        steps[i].$2,
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
        const Gap(16),
        Container(
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
                      'Parça + İşçilik',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const Gap(2),
                    Text(
                      'Raporlar için ayrı kalemler halinde kaydedilir.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: const Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              const Gap(10),
              AppBadge(label: 'Standart', tone: AppBadgeTone.neutral),
            ],
          ),
        ),
      ],
    );
  }
}

class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.title,
    required this.customerName,
    required this.status,
    required this.createdAt,
  });

  final String id;
  final String title;
  final String? customerName;
  final String status;
  final DateTime createdAt;

  factory ServiceRecord.fromJson(Map<String, dynamic> json) {
    return ServiceRecord(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerName: json['customer_name']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
