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
    final currentPage = ref.watch(customerPageProvider);

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle:
          'Müşteri kayıtlarını yönetin, filtreleyin ve yeni müşteri ekleyin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () {
            ref.invalidate(customersProvider);
            ref.invalidate(customerCitiesProvider);
            ref.read(customerPageProvider.notifier).reset();
          },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () => _downloadCustomerImportTemplate(context),
          icon: const Icon(Icons.file_download_outlined, size: 18),
          label: const Text('Şablon İndir'),
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
                        onChanged: (value) {
                          ref
                              .read(customerFiltersProvider.notifier)
                              .setSearch(value);
                          ref.read(customerPageProvider.notifier).reset();
                        },
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
                          onChanged: (value) {
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setCity(value);
                            ref.read(customerPageProvider.notifier).reset();
                          },
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
                            ref.read(customerPageProvider.notifier).reset();
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
            data: (pageData) {
              final customers = pageData.items;
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
                          onPressed: () =>
                              _showCustomerForm(context, ref, openDetail: true),
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
                          'Toplam ${pageData.totalCount} müşteri • Sayfa $currentPage • ${customers.length} kayıt gösteriliyor',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: currentPage > 1
                            ? () => ref
                                  .read(customerPageProvider.notifier)
                                  .previous()
                            : null,
                        icon: const Icon(Icons.chevron_left_rounded, size: 18),
                        label: const Text('Önceki'),
                      ),
                      const Gap(8),
                      OutlinedButton.icon(
                        onPressed: pageData.hasNextPage
                            ? () =>
                                  ref.read(customerPageProvider.notifier).next()
                            : null,
                        icon: const Icon(Icons.chevron_right_rounded, size: 18),
                        label: const Text('Sonraki'),
                      ),
                      const Gap(8),
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
                  const Gap(12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'Her sayfada $customerPageSize kayıt gösterilir.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
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

Future<void> _downloadCustomerImportTemplate(BuildContext context) async {
  try {
    final file = excel.Excel.createExcel();
    final sheet = file['Müşteri Şablonu'];

    sheet.appendRow([
      excel.TextCellValue('Müşteri ID'),
      excel.TextCellValue('Firma Adı'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('E-posta'),
      excel.TextCellValue('VKN / TCKN'),
      excel.TextCellValue('Telefon 1 Başlığı'),
      excel.TextCellValue('Telefon 1'),
      excel.TextCellValue('Telefon 2 Başlığı'),
      excel.TextCellValue('Telefon 2'),
      excel.TextCellValue('Telefon 3 Başlığı'),
      excel.TextCellValue('Telefon 3'),
      excel.TextCellValue('Aktif Müşteri'),
      excel.TextCellValue('Notlar'),
    ]);

    sheet.appendRow([
      excel.TextCellValue(''),
      excel.TextCellValue('Microvise Teknoloji'),
      excel.TextCellValue('Istanbul'),
      excel.TextCellValue('info@microvise.com'),
      excel.TextCellValue('1234567890'),
      excel.TextCellValue('Yetkili'),
      excel.TextCellValue('05551234567'),
      excel.TextCellValue('Muhasebe'),
      excel.TextCellValue('02121234567'),
      excel.TextCellValue('Destek'),
      excel.TextCellValue('08501234567'),
      excel.TextCellValue('Evet'),
      excel.TextCellValue('Ornek musteri kaydi'),
    ]);

    file.delete('Sheet1');

    final bytes = file.encode();
    if (bytes == null) throw Exception('Excel hata');

    downloadExcelFile(bytes, 'musteri_import_sablonu.xlsx');

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Müşteri import şablonu indirildi.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Şablon indirilemedi: $e')));
  }
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
      excel.TextCellValue('Müşteri ID'),
      excel.TextCellValue('Firma Adı'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('E-posta'),
      excel.TextCellValue('VKN / TCKN'),
      excel.TextCellValue('Telefon 1 Başlığı'),
      excel.TextCellValue('Telefon 1'),
      excel.TextCellValue('Telefon 2 Başlığı'),
      excel.TextCellValue('Telefon 2'),
      excel.TextCellValue('Telefon 3 Başlığı'),
      excel.TextCellValue('Telefon 3'),
      excel.TextCellValue('Aktif Müşteri'),
      excel.TextCellValue('Notlar'),
    ]);

    for (final c in customers) {
      sheet.appendRow([
        excel.TextCellValue((c['id'] ?? '').toString()),
        excel.TextCellValue((c['name'] ?? '').toString()),
        excel.TextCellValue((c['city'] ?? '').toString()),
        excel.TextCellValue((c['email'] ?? '').toString()),
        excel.TextCellValue((c['vkn'] ?? '').toString()),
        excel.TextCellValue((c['phone_1_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_1'] ?? '').toString()),
        excel.TextCellValue((c['phone_2_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_2'] ?? '').toString()),
        excel.TextCellValue((c['phone_3_title'] ?? '').toString()),
        excel.TextCellValue((c['phone_3'] ?? '').toString()),
        excel.TextCellValue(
          ((c['is_active'] as bool?) ?? true) ? 'Evet' : 'Hayır',
        ),
        excel.TextCellValue((c['notes'] ?? '').toString()),
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
  if (sheet.rows.isEmpty) return;

  final headers = sheet.rows.first
      .map((cell) => cell?.value?.toString().trim().toLowerCase() ?? '')
      .toList(growable: false);

  int columnOf(List<String> keys) {
    for (final key in keys) {
      final index = headers.indexOf(key.toLowerCase());
      if (index != -1) return index;
    }
    return -1;
  }

  String? readText(List<excel.Data?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    final value = row[index]?.value?.toString().trim();
    if (value == null || value.isEmpty) return null;
    return value;
  }

  bool readBool(List<excel.Data?> row, int index) {
    final raw = readText(row, index)?.toLowerCase();
    if (raw == null) return true;
    return raw == 'evet' ||
        raw == 'true' ||
        raw == '1' ||
        raw == 'aktif' ||
        raw == 'yes';
  }

  final nameIndex = columnOf(['firma adı', 'firma', 'name']);
  final idIndex = columnOf(['müşteri id', 'musteri id', 'customer id', 'id']);
  final cityIndex = columnOf(['şehir', 'city']);
  final emailIndex = columnOf(['e-posta', 'email']);
  final vknIndex = columnOf(['vkn / tckn', 'vkn', 'tckn']);
  final phone1TitleIndex = columnOf(['telefon 1 başlığı', 'phone 1 title']);
  final phone1Index = columnOf(['telefon 1', 'telefon', 'phone 1']);
  final phone2TitleIndex = columnOf(['telefon 2 başlığı', 'phone 2 title']);
  final phone2Index = columnOf(['telefon 2', 'phone 2']);
  final phone3TitleIndex = columnOf(['telefon 3 başlığı', 'phone 3 title']);
  final phone3Index = columnOf(['telefon 3', 'phone 3']);
  final isActiveIndex = columnOf(['aktif müşteri', 'aktif', 'is_active']);
  final notesIndex = columnOf(['notlar', 'not', 'notes']);

  if (nameIndex == -1) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Excel dosyasında Firma Adı kolonu yok.')),
    );
    return;
  }

  String normalize(String? value) => (value ?? '').trim().toLowerCase();

  final existingRows = await client
      .from('customers')
      .select('id,name,city,email,vkn');

  final existingByVkn = <String, String>{};
  final existingByEmail = <String, String>{};
  final existingIds = <String>{};

  for (final row in (existingRows as List)) {
    final map = row as Map<String, dynamic>;
    final id = map['id']?.toString();
    if (id == null || id.isEmpty) continue;
    existingIds.add(id);

    final normalizedVkn = normalize(map['vkn']?.toString());
    final normalizedEmail = normalize(map['email']?.toString());
    if (normalizedVkn.isNotEmpty) existingByVkn[normalizedVkn] = id;
    if (normalizedEmail.isNotEmpty) existingByEmail[normalizedEmail] = id;
  }

  var createdCount = 0;
  var updatedCount = 0;
  var skippedCount = 0;
  final seenImportKeys = <String>{};

  for (int i = 1; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];
    final importedId = readText(row, idIndex);
    final name = readText(row, nameIndex);
    if (name == null) {
      skippedCount++;
      continue;
    }

    final city = readText(row, cityIndex);
    final email = readText(row, emailIndex);
    final vkn = readText(row, vknIndex);
    final payload = {
      'name': name,
      'city': city,
      'email': email,
      'vkn': vkn,
      'phone_1_title': readText(row, phone1TitleIndex),
      'phone_1': readText(row, phone1Index),
      'phone_2_title': readText(row, phone2TitleIndex),
      'phone_2': readText(row, phone2Index),
      'phone_3_title': readText(row, phone3TitleIndex),
      'phone_3': readText(row, phone3Index),
      'notes': readText(row, notesIndex),
      'is_active': readBool(row, isActiveIndex),
    };

    final normalizedEmail = normalize(email);
    final normalizedVkn = normalize(vkn);
    final importKey = importedId != null && importedId.isNotEmpty
        ? 'id:$importedId'
        : normalizedVkn.isNotEmpty
        ? 'vkn:$normalizedVkn'
        : normalizedEmail.isNotEmpty
        ? 'email:$normalizedEmail'
        : 'row:$i';

    if (!seenImportKeys.add(importKey)) {
      skippedCount++;
      continue;
    }

    final existingId =
        (importedId != null && existingIds.contains(importedId)
            ? importedId
            : null) ??
        (normalizedVkn.isNotEmpty ? existingByVkn[normalizedVkn] : null) ??
        (normalizedEmail.isNotEmpty ? existingByEmail[normalizedEmail] : null);

    if (existingId != null) {
      await client.from('customers').update(payload).eq('id', existingId);
      updatedCount++;
      continue;
    }

    final inserted = await client
        .from('customers')
        .insert(payload)
        .select('id')
        .single();
    final insertedId = inserted['id']?.toString();
    if (insertedId == null || insertedId.isEmpty) {
      skippedCount++;
      continue;
    }

    existingIds.add(insertedId);
    if (normalizedVkn.isNotEmpty) {
      existingByVkn[normalizedVkn] = insertedId;
    }
    if (normalizedEmail.isNotEmpty) {
      existingByEmail[normalizedEmail] = insertedId;
    }
    createdCount++;
  }

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        '$createdCount yeni, $updatedCount güncellendi, $skippedCount atlandı.',
      ),
    ),
  );
}
