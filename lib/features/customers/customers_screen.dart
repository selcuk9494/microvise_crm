import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart'
    if (dart.library.io) 'io_download_helper.dart';

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  bool _handledCreateQuery = false;
  late final TextEditingController _searchController;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_handledCreateQuery) return;
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['yeni'] != '1') return;

    _handledCreateQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.go('/musteriler');
      await _showCustomerForm(context, ref, openDetail: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);
    final filters = ref.watch(customerFiltersProvider);

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle:
          'Müşteri kayıtlarını yönetin, filtreleyin ve yeni müşteri ekleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(customersProvider);
            ref.invalidate(customerCitiesProvider);
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () => _exportCustomersToExcel(context, ref),
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('Dışa Aktar'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () => _importExcel(context, ref),
          icon: const Icon(Icons.upload_rounded, size: 18),
          label: const Text('İçe Aktar'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _showCustomerForm(context, ref, openDetail: true),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _searchController,
                        onChanged: ref
                            .read(customerFiltersProvider.notifier)
                            .setSearch,
                        decoration: const InputDecoration(
                          labelText: 'Müşteri Ara',
                          hintText: 'Firma adına göre arayın',
                          prefixIcon: Icon(Icons.search_rounded),
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: citiesAsync.when(
                        data: (cities) => DropdownButtonFormField<String?>(
                          initialValue: filters.city,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Tüm Şehirler'),
                            ),
                            ...cities.map(
                              (city) => DropdownMenuItem<String?>(
                                value: city,
                                child: Text(city),
                              ),
                            ),
                          ],
                          onChanged: ref
                              .read(customerFiltersProvider.notifier)
                              .setCity,
                          decoration: const InputDecoration(
                            labelText: 'Şehir',
                            prefixIcon: Icon(Icons.location_city_rounded),
                          ),
                        ),
                        loading: () => const TextField(
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'Şehir',
                            prefixIcon: Icon(Icons.location_city_rounded),
                          ),
                        ),
                        error: (error, stackTrace) => const TextField(
                          enabled: false,
                          decoration: InputDecoration(
                            labelText: 'Şehir yüklenemedi',
                            prefixIcon: Icon(Icons.error_outline_rounded),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (filters.search.isNotEmpty || filters.city != null) ...[
                  const Gap(12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (filters.search.isNotEmpty)
                          AppBadge(
                            label: 'Arama: ${filters.search}',
                            tone: AppBadgeTone.primary,
                          ),
                        if (filters.city != null)
                          AppBadge(
                            label: 'Şehir: ${filters.city}',
                            tone: AppBadgeTone.neutral,
                          ),
                        TextButton.icon(
                          onPressed: () {
                            _searchController.clear();
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setSearch('');
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setCity(null);
                          },
                          icon: const Icon(Icons.clear_rounded, size: 18),
                          label: const Text('Filtreleri Temizle'),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const Gap(16),
          customersAsync.when(
            data: (customers) {
              if (customers.isEmpty) {
                return AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.groups_2_rounded,
                          size: 52,
                          color: Color(0xFF94A3B8),
                        ),
                        const Gap(12),
                        Text(
                          'Henüz müşteri kaydı yok',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(8),
                        Text(
                          'Yeni müşteri ekleyerek listeyi oluşturmaya başlayın.',
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        const Gap(16),
                        FilledButton.icon(
                          onPressed: () => _showCustomerForm(
                            context,
                            ref,
                            openDetail: true,
                          ),
                          icon: const Icon(Icons.add_rounded, size: 18),
                          label: const Text('İlk Müşteriyi Ekle'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              return Column(
                children: [
                  _SummaryRow(customers: customers),
                  const Gap(12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${customers.length} müşteri bulundu',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () =>
                            _showCustomerForm(context, ref, openDetail: false),
                        icon: const Icon(Icons.add_rounded, size: 18),
                        label: const Text('Hızlı Ekle'),
                      ),
                    ],
                  ),
                  const Gap(12),
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: customers.length,
                    separatorBuilder: (context, index) => const Gap(12),
                    itemBuilder: (context, index) {
                      final customer = customers[index];
                      return _CustomerCard(
                        customer: customer,
                        onChanged: () => _refreshCustomerData(ref),
                      );
                    },
                  ),
                ],
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Müşteriler yüklenemedi',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
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

class _SummaryRow extends StatelessWidget {
  const _SummaryRow({required this.customers});

  final List<Customer> customers;

  @override
  Widget build(BuildContext context) {
    final active = customers.where((customer) => customer.isActive).length;
    final passive = customers.length - active;
    final totalLines = customers.fold<int>(
      0,
      (sum, customer) => sum + customer.activeLineCount,
    );

    return Row(
      children: [
        Expanded(
          child: _SummaryStat(
            label: 'Toplam',
            value: customers.length.toString(),
            icon: Icons.groups_2_rounded,
            tone: AppBadgeTone.primary,
          ),
        ),
        const Gap(12),
        Expanded(
          child: _SummaryStat(
            label: 'Aktif',
            value: active.toString(),
            icon: Icons.check_circle_outline_rounded,
            tone: AppBadgeTone.success,
          ),
        ),
        const Gap(12),
        Expanded(
          child: _SummaryStat(
            label: 'Pasif',
            value: passive.toString(),
            icon: Icons.pause_circle_outline_rounded,
            tone: AppBadgeTone.neutral,
          ),
        ),
        const Gap(12),
        Expanded(
          child: _SummaryStat(
            label: 'Aktif Hat',
            value: totalLines.toString(),
            icon: Icons.sim_card_outlined,
            tone: AppBadgeTone.warning,
          ),
        ),
      ],
    );
  }
}

class _SummaryStat extends StatelessWidget {
  const _SummaryStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.tone,
  });

  final String label;
  final String value;
  final IconData icon;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    final color = switch (tone) {
      AppBadgeTone.primary => AppTheme.primary,
      AppBadgeTone.success => AppTheme.success,
      AppBadgeTone.warning => AppTheme.warning,
      AppBadgeTone.error => AppTheme.error,
      AppBadgeTone.neutral => const Color(0xFF64748B),
    };

    return AppCard(
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                const Gap(4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
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

class _CustomerCard extends ConsumerWidget {
  const _CustomerCard({required this.customer, required this.onChanged});

  final Customer customer;
  final Future<void> Function() onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      onTap: () => context.go('/musteriler/${customer.id}'),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(Icons.business_rounded, color: AppTheme.primary),
          ),
          const Gap(14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        customer.name,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    AppBadge(
                      label: customer.isActive ? 'Aktif' : 'Pasif',
                      tone: customer.isActive
                          ? AppBadgeTone.success
                          : AppBadgeTone.neutral,
                    ),
                  ],
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if ((customer.city ?? '').trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.location_on_outlined,
                        label: customer.city!,
                      ),
                    _MetaChip(
                      icon: Icons.sim_card_outlined,
                      label: '${customer.activeLineCount} aktif hat',
                    ),
                    _MetaChip(
                      icon: Icons.verified_outlined,
                      label: '${customer.activeGmp3Count} GMP3',
                    ),
                    if ((customer.phone1 ?? '').trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.phone_outlined,
                        label: customer.phone1!,
                      ),
                    if ((customer.email ?? '').trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.alternate_email_rounded,
                        label: customer.email!,
                      ),
                    if ((customer.vkn ?? '').trim().isNotEmpty)
                      _MetaChip(
                        icon: Icons.badge_outlined,
                        label: 'VKN: ${customer.vkn}',
                      ),
                  ],
                ),
              ],
            ),
          ),
          PopupMenuButton<_CustomerAction>(
            tooltip: 'Müşteri işlemleri',
            onSelected: (action) async {
              switch (action) {
                case _CustomerAction.edit:
                  final updated = await showEditCustomerDialog(
                    context,
                    initialData: CustomerFormData(
                      id: customer.id,
                      name: customer.name,
                      city: customer.city,
                      email: customer.email,
                      vkn: customer.vkn,
                      phone1Title: customer.phone1Title,
                      phone1: customer.phone1,
                      phone2Title: customer.phone2Title,
                      phone2: customer.phone2,
                      phone3Title: customer.phone3Title,
                      phone3: customer.phone3,
                      notes: customer.notes,
                      isActive: customer.isActive,
                    ),
                  );
                  if (updated) {
                    await onChanged();
                  }
                case _CustomerAction.toggleActive:
                  await _toggleCustomerActive(context, ref, customer: customer);
                  await onChanged();
                case _CustomerAction.open:
                  if (context.mounted) {
                    context.go('/musteriler/${customer.id}');
                  }
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: _CustomerAction.open,
                child: Text('Detaya Git'),
              ),
              const PopupMenuItem(
                value: _CustomerAction.edit,
                child: Text('Düzenle'),
              ),
              PopupMenuItem(
                value: _CustomerAction.toggleActive,
                child: Text(customer.isActive ? 'Pasife Al' : 'Aktifleştir'),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6),
              child: Icon(Icons.more_vert_rounded, color: Color(0xFF94A3B8)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _CustomerAction { open, edit, toggleActive }

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: const Color(0xFF64748B)),
          const Gap(6),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

Future<void> _showCustomerForm(
  BuildContext context,
  WidgetRef ref, {
  required bool openDetail,
}) async {
  final result = await showCreateCustomerDialog(context);

  if (result == null || !context.mounted) return;
  _refreshCustomerData(ref);
  if (openDetail) {
    context.go('/musteriler/$result');
  }
}

Future<void> _refreshCustomerData(WidgetRef ref) async {
  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
}

Future<void> _toggleCustomerActive(
  BuildContext context,
  WidgetRef ref, {
  required Customer customer,
}) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final messenger = ScaffoldMessenger.of(context);

  try {
    await client
        .from('customers')
        .update({'is_active': !customer.isActive})
        .eq('id', customer.id);
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          customer.isActive
              ? 'Müşteri pasif duruma alındı.'
              : 'Müşteri yeniden aktif edildi.',
        ),
      ),
    );
  } catch (e) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
  }
}

// ================= EXPORT =================
Future<void> _exportCustomersToExcel(
  BuildContext context,
  WidgetRef ref,
) async {
  final client = ref.read(supabaseClientProvider);

  if (client == null) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Supabase bağlantısı yok')));
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final rows = await client.from('customers').select();
    final customers = rows as List;

    final file = excel.Excel.createExcel();
    final sheet = file['Müşteriler'];

    sheet.appendRow([
      excel.TextCellValue('Firma'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('Email'),
      excel.TextCellValue('Telefon'),
    ]);

    for (final c in customers) {
      sheet.appendRow([
        excel.TextCellValue(c['name'] ?? ''),
        excel.TextCellValue(c['city'] ?? ''),
        excel.TextCellValue(c['email'] ?? ''),
        excel.TextCellValue(c['phone_1'] ?? ''),
      ]);
    }

    file.delete('Sheet1');

    final bytes = file.encode();
    if (bytes == null) throw Exception('Excel hata');

    downloadExcelFile(bytes, 'musteriler.xlsx');

    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${customers.length} kayıt indirildi')),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Hata: $e')));
  }
}

// ================= IMPORT =================
Future<void> _importExcel(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );

  if (result == null) return;

  final bytes = result.files.first.bytes!;
  final excelFile = excel.Excel.decodeBytes(bytes);
  final sheet = excelFile.tables.values.first;

  for (int i = 1; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];

    await client.from('customers').insert({
      'name': row[0]?.value?.toString(),
      'city': row[1]?.value?.toString(),
      'email': row[2]?.value?.toString(),
      'phone_1': row[3]?.value?.toString(),
      'is_active': true,
    });
  }

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);

  if (!context.mounted) return;

  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Import tamamlandı')));
}
