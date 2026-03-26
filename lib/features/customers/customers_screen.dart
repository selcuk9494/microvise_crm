import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'customers_providers.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filters = ref.watch(customerFiltersProvider);
    final customersAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Firma kartları ve hızlı filtreleme.',
      actions: [
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      labelText: 'Ara',
                      hintText: 'Firma adı',
                      prefixIcon: Icon(Icons.search_rounded),
                    ),
                    onChanged: (v) => ref
                        .read(customerFiltersProvider.notifier)
                        .setSearch(v),
                  ),
                ),
                const Gap(12),
                SizedBox(
                  width: 220,
                  child: citiesAsync.when(
                    data: (cities) => DropdownButtonFormField<String>(
                      value: filters.city,
                      items: [
                        const DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Şehirler'),
                        ),
                        ...cities.map(
                          (c) => DropdownMenuItem<String>(
                            value: c,
                            child: Text(c),
                          ),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(customerFiltersProvider.notifier)
                          .setCity(v),
                      decoration: const InputDecoration(
                        labelText: 'Şehir',
                      ),
                    ),
                    loading: () => const _DropdownSkeleton(),
                    error: (_, __) => DropdownButtonFormField<String>(
                      value: filters.city,
                      items: const [
                        DropdownMenuItem<String>(
                          value: null,
                          child: Text('Tüm Şehirler'),
                        ),
                      ],
                      onChanged: (v) => ref
                          .read(customerFiltersProvider.notifier)
                          .setCity(v),
                      decoration: const InputDecoration(labelText: 'Şehir'),
                    ),
                  ),
                ),
                const Gap(12),
                OutlinedButton(
                  onPressed: () {
                    ref.read(customerFiltersProvider.notifier).setSearch('');
                    ref.read(customerFiltersProvider.notifier).setCity(null);
                  },
                  child: const Text('Sıfırla'),
                ),
              ],
            ),
          ),
          const Gap(14),
          customersAsync.when(
            data: (customers) {
              if (customers.isEmpty) {
                return AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
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
                            Icons.inbox_rounded,
                            color: AppTheme.primary,
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Kayıt bulunamadı',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const Gap(2),
                              Text(
                                'Filtreleri temizleyin veya yeni müşteri ekleyin.',
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
                );
              }

              return AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _HeaderRow(),
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customers.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final c = customers[index];
                        return _CustomerRow(
                          name: c.name,
                          city: c.city,
                          active: c.isActive,
                          onTap: () => context.go('/musteriler/${c.id}'),
                        );
                      },
                    ),
                  ],
                ),
              );
            },
            loading: () => Skeletonizer(
              enabled: true,
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _HeaderRow(),
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 6,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => const _CustomerRow(
                        name: 'Microvise Teknoloji A.Ş.',
                        city: 'İstanbul',
                        active: true,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            error: (_, __) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Text(
                  'Müşteriler yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderRow extends StatelessWidget {
  const _HeaderRow();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Firma',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
          SizedBox(
            width: 180,
            child: Text(
              'Şehir',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF475569),
                  ),
            ),
          ),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Durum',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: const Color(0xFF475569),
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends StatefulWidget {
  const _CustomerRow({
    required this.name,
    required this.city,
    required this.active,
    this.onTap,
  });

  final String name;
  final String? city;
  final bool active;
  final VoidCallback? onTap;

  @override
  State<_CustomerRow> createState() => _CustomerRowState();
}

class _CustomerRowState extends State<_CustomerRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final clickable = widget.onTap != null;

    return MouseRegion(
      cursor: clickable ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Material(
        color: _hovered ? const Color(0xFFF8FAFC) : Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    widget.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          decoration: widget.active
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                  ),
                ),
                SizedBox(
                  width: 180,
                  child: Text(
                    widget.city ?? '—',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
                  ),
                ),
                SizedBox(
                  width: 110,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: AppBadge(
                      label: widget.active ? 'Aktif' : 'Pasif',
                      tone: widget.active
                          ? AppBadgeTone.success
                          : AppBadgeTone.neutral,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DropdownSkeleton extends StatelessWidget {
  const _DropdownSkeleton();

  @override
  Widget build(BuildContext context) {
    return Skeletonizer(
      enabled: true,
      child: DropdownButtonFormField<String>(
        value: null,
        items: const [
          DropdownMenuItem<String>(value: null, child: Text('Tüm Şehirler')),
        ],
        onChanged: (_) {},
        decoration: const InputDecoration(labelText: 'Şehir'),
      ),
    );
  }
}
