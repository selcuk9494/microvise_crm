import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive =
        ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDelete =
        ref.watch(hasActionAccessProvider(kActionDeleteRecords));

    final filters = ref.watch(customerFiltersProvider);
    final pageDataAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);
    final page = ref.watch(customerPageProvider);
    final sort = ref.watch(customerSortProvider);
    final showPassive = ref.watch(customerShowPassiveProvider);

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Müşteri kayıtlarını filtreleyin, görüntüleyin ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(customersProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: canEdit
              ? () async {
                  final id = await showCreateCustomerDialog(context);
                  if (id == null || !context.mounted) return;
                  ref.invalidate(customersProvider);
                  context.go('/musteriler/$id');
                }
              : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Filtreler',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Gap(12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 320,
                      child: TextField(
                        onChanged: (value) {
                          ref
                              .read(customerFiltersProvider.notifier)
                              .setSearch(value);
                          ref.read(customerPageProvider.notifier).reset();
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search_rounded),
                          labelText: 'Ara',
                          hintText: 'Müşteri adı / VKN / telefon',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: citiesAsync.when(
                        data: (cities) => DropdownButtonFormField<String?>(
                          initialValue: filters.city,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Şehir: Tümü'),
                            ),
                            ...cities.map(
                              (c) => DropdownMenuItem<String?>(
                                value: c,
                                child: Text(c),
                              ),
                            ),
                          ],
                          onChanged: (value) {
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setCity(value);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.location_city_rounded),
                            labelText: 'Şehir',
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                    ),
                    SizedBox(
                      width: 240,
                      child: DropdownButtonFormField<CustomerSortOption>(
                        initialValue: sort,
                        items: const [
                          DropdownMenuItem(
                            value: CustomerSortOption.id,
                            child: Text('Sıralama: En eski'),
                          ),
                          DropdownMenuItem(
                            value: CustomerSortOption.nameAsc,
                            child: Text('Sıralama: A-Z'),
                          ),
                          DropdownMenuItem(
                            value: CustomerSortOption.nameDesc,
                            child: Text('Sıralama: Z-A'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          ref.read(customerSortProvider.notifier).set(value);
                        },
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.sort_rounded),
                          labelText: 'Sıralama',
                        ),
                      ),
                    ),
                    FilterChip(
                      selected: showPassive,
                      onSelected: (value) {
                        ref
                            .read(customerShowPassiveProvider.notifier)
                            .set(value);
                        ref.read(customerPageProvider.notifier).reset();
                      },
                      label: const Text('Pasifleri Göster'),
                      visualDensity: VisualDensity.compact,
                    ),
                    OutlinedButton.icon(
                      onPressed: () {
                        ref.read(customerFiltersProvider.notifier).setSearch('');
                        ref.read(customerFiltersProvider.notifier).setCity(null);
                        ref.read(customerShowPassiveProvider.notifier).set(false);
                        ref.read(customerSortProvider.notifier).set(
                              CustomerSortOption.id,
                            );
                        ref.read(customerPageProvider.notifier).reset();
                        ref.invalidate(customersProvider);
                      },
                      icon: const Icon(Icons.cleaning_services_rounded, size: 18),
                      label: const Text('Temizle'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(12),
          Expanded(
            child: pageDataAsync.when(
              data: (pageData) {
                if (pageData.items.isEmpty) {
                  return const EmptyStateCard(
                    icon: Icons.people_alt_rounded,
                    title: 'Müşteri yok',
                    message: 'Filtrelere uygun müşteri bulunamadı.',
                  );
                }

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          padding: EdgeInsets.zero,
                          itemCount: pageData.items.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) => _CustomerRow(
                            customer: pageData.items[index],
                            isAdmin: isAdmin,
                            canEdit: canEdit,
                            canArchive: canArchive,
                            canDelete: canDelete,
                            onChanged: () => ref.invalidate(customersProvider),
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Text(
                              'Toplam ${pageData.totalCount} kayıt',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                            const Spacer(),
                            OutlinedButton.icon(
                              onPressed: page <= 1
                                  ? null
                                  : () => ref
                                      .read(customerPageProvider.notifier)
                                      .previous(),
                              icon: const Icon(Icons.chevron_left_rounded),
                              label: const Text('Önceki'),
                            ),
                            const Gap(8),
                            Text(
                              '${pageData.page} / ${pageData.totalPages}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const Gap(8),
                            OutlinedButton.icon(
                              onPressed: pageData.hasNextPage
                                  ? () => ref
                                      .read(customerPageProvider.notifier)
                                      .next()
                                  : null,
                              icon: const Icon(Icons.chevron_right_rounded),
                              label: const Text('Sonraki'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (_, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Müşteri listesi yüklenemedi.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerRow extends ConsumerStatefulWidget {
  const _CustomerRow({
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final Customer customer;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  ConsumerState<_CustomerRow> createState() => _CustomerRowState();
}

class _CustomerRowState extends ConsumerState<_CustomerRow> {
  bool _saving = false;

  Future<void> _toggleActive(bool next) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.patchJson(
        '/customers',
        body: {'id': widget.customer.id, 'is_active': next},
      );
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri güncellenemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deletePermanently() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kalıcı Sil'),
        content: const Text('Bu müşteri kalıcı olarak silinsin mi?'),
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

    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'delete', 'table': 'customers', 'id': widget.customer.id},
      );
      widget.onChanged();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri silinemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final customer = widget.customer;
    final badge = customer.isActive
        ? const AppBadge(label: 'Aktif', tone: AppBadgeTone.success)
        : const AppBadge(label: 'Pasif', tone: AppBadgeTone.neutral);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  customer.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: customer.isActive
                            ? TextDecoration.none
                            : TextDecoration.lineThrough,
                      ),
                ),
                const Gap(2),
                Text(
                  [
                    customer.city?.trim().isNotEmpty ?? false
                        ? customer.city!.trim()
                        : null,
                    customer.vkn?.trim().isNotEmpty ?? false
                        ? 'VKN: ${customer.vkn!.trim()}'
                        : null,
                    customer.phone1?.trim().isNotEmpty ?? false
                        ? customer.phone1!.trim()
                        : null,
                  ].whereType<String>().join(' • '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Gap(10),
          badge,
          const Gap(10),
          OutlinedButton.icon(
            onPressed: () => context.go('/musteriler/${customer.id}'),
            icon: const Icon(Icons.open_in_new_rounded, size: 18),
            label: const Text('Aç'),
          ),
          const Gap(8),
          PopupMenuButton<String>(
            tooltip: 'İşlemler',
            onSelected: (value) async {
              switch (value) {
                case 'edit':
                  final updated = await showEditCustomerDialog(
                    context,
                    initialData: CustomerFormData(
                      id: customer.id,
                      name: customer.name,
                      city: customer.city,
                      address: customer.address,
                      directorName: customer.directorName,
                      email: customer.email,
                      vkn: customer.vkn,
                      tcknMs: customer.tcknMs,
                      phone1Title: customer.phone1Title,
                      phone1: customer.phone1,
                      phone2Title: customer.phone2Title,
                      phone2: customer.phone2,
                      phone3Title: customer.phone3Title,
                      phone3: customer.phone3,
                      notes: customer.notes,
                      isActive: customer.isActive,
                      locations: const [],
                    ),
                  );
                  if (updated) widget.onChanged();
                  break;
                case 'toggle':
                  await _toggleActive(!customer.isActive);
                  break;
                case 'delete':
                  await _deletePermanently();
                  break;
                default:
                  break;
              }
            },
            itemBuilder: (context) => [
              if (widget.canEdit)
                const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
              if (widget.canArchive)
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(customer.isActive ? 'Pasife Al' : 'Aktifleştir'),
                ),
              if (!customer.isActive && widget.canDelete)
                const PopupMenuItem(value: 'delete', child: Text('Kalıcı Sil')),
            ],
            child: SizedBox(
              width: 44,
              height: 40,
              child: Center(
                child: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.more_horiz_rounded),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
