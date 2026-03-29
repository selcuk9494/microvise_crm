import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/compact_stat_card.dart';
import '../application_forms/application_form_model.dart';
import '../forms/scrap_form_model.dart';
import '../forms/transfer_form_model.dart';

final deviceBrandsProvider = FutureProvider<List<DeviceBrand>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('device_brands')
      .select('id,name,is_active,created_at')
      .order('name');
  return (rows as List)
      .map((e) => DeviceBrand.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final deviceModelsProvider = FutureProvider<List<DeviceModel>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('device_models')
      .select('id,name,is_active,brand_id,device_brands(name)')
      .order('name');
  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final brand = map['device_brands'] as Map<String, dynamic>?;
        return DeviceModel.fromJson({...map, 'brand_name': brand?['name']});
      })
      .toList(growable: false);
});

// İş Emri Tipleri Provider
final workOrderTypesProvider = FutureProvider<List<WorkOrderType>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('work_order_types')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List)
      .map((e) => WorkOrderType.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

// KDV Oranları Provider
final taxRatesProvider = FutureProvider<List<TaxRate>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('tax_rates')
      .select()
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List)
      .map((e) => TaxRate.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final cityDefinitionsProvider = FutureProvider<List<CityDefinition>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  try {
    final rows = await client
        .from('cities')
        .select('id,name,code,is_active')
        .order('name');
    return (rows as List)
        .map((e) => CityDefinition.fromJson(e as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    final customerRows = await client.from('customers').select('city');
    final branchRows = await client.from('branches').select('city');
    final names = <String>{};
    for (final row in [...(customerRows as List), ...(branchRows as List)]) {
      final name = row['city']?.toString().trim();
      if (name == null || name.isEmpty) continue;
      names.add(name);
    }
    final sorted = names.toList()..sort();
    return [
      for (final name in sorted)
        CityDefinition(id: name, name: name, code: null, isActive: true),
    ];
  }
});

final fiscalSymbolsProvider = FutureProvider<List<FiscalSymbolDefinition>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('fiscal_symbols')
      .select('id,name,code,is_active')
      .order('name');
  return (rows as List)
      .map((e) => FiscalSymbolDefinition.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final businessActivityTypesProvider =
    FutureProvider<List<BusinessActivityTypeDefinition>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];
      final rows = await client
          .from('business_activity_types')
          .select('id,name,is_active')
          .order('name');
      return (rows as List)
          .map(
            (e) => BusinessActivityTypeDefinition.fromJson(
              e as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
    });

final applicationFormPrintSettingsProvider =
    FutureProvider<ApplicationFormPrintSettings>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return ApplicationFormPrintSettings.defaults;
      try {
        final row = await client
            .from('application_form_settings')
            .select(
              'id,office_title,intro_text,optional_power_precaution_text,manual_included_text,service_company_name,service_company_address,applicant_status,office_title_4a,kdv4a_title,kdv4a_serial_number,kdv4a_seller_company_name,kdv4a_seller_address,kdv4a_seller_tax_office_and_registry,kdv4a_seller_license_number,kdv4a_warranty_period,kdv4a_department_count,kdv4a_service_company_name,kdv4a_service_company_address,kdv4a_seal_applicant_name,kdv4a_seal_applicant_title,kdv4a_approval_document_date,kdv4a_approval_document_number,kdv4a_delivery_receiver_name,kdv4a_delivery_receiver_title',
            )
            .eq('id', 'default')
            .maybeSingle();
        if (row == null) return ApplicationFormPrintSettings.defaults;
        return ApplicationFormPrintSettings.fromJson(row);
      } catch (_) {
        return ApplicationFormPrintSettings.defaults;
      }
    });

final scrapFormPrintSettingsProvider = FutureProvider<ScrapFormPrintSettings>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return ScrapFormPrintSettings.defaults;
  try {
    final row = await client
        .from('scrap_form_settings')
        .select(
          'id,form_code,title,date_label,row_number_label,service_section_title,service_company_label,service_identity_label,service_address_label,service_tax_label,service_company_value,service_identity_value,service_address_value,service_tax_value,owner_section_title,owner_name_label,owner_address_label,owner_tax_label,device_section_title,start_date_label,last_used_date_label,summary_title,z_report_label,vat_total_label,gross_total_label,purpose_label,other_findings_label,owner_signature_title,service_signature_title',
        )
        .eq('id', 'default')
        .maybeSingle();
    if (row == null) return ScrapFormPrintSettings.defaults;
    return ScrapFormPrintSettings.fromJson(row);
  } catch (_) {
    return ScrapFormPrintSettings.defaults;
  }
});

final transferFormPrintSettingsProvider =
    FutureProvider<TransferFormPrintSettings>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return TransferFormPrintSettings.defaults;
      try {
        final row = await client
            .from('transfer_form_settings')
            .select(
              'id,title,subtitle,office_title,row_number_label,transferor_section_title,transferor_name_label,transferor_address_label,transferor_tax_label,transferor_approval_label,transferee_section_title,transferee_name_label,transferee_address_label,transferee_tax_label,transferee_approval_label,device_summary_title,total_sales_receipt_label,vat_collected_label,last_receipt_date_no_label,z_report_count_label,other_device_info_label,device_info_title,brand_model_label,device_serial_no_label,fiscal_symbol_company_code_label,department_count_label,transfer_info_title,transfer_date_label,transfer_reason_label,service_company_label,service_company_value,statement_text,transferor_signature_title,transferee_signature_title,office_fill_title,office_fill_text,controller_title,controller_date_label',
            )
            .eq('id', 'default')
            .maybeSingle();
        if (row == null) return TransferFormPrintSettings.defaults;
        return TransferFormPrintSettings.fromJson(row);
      } catch (_) {
        return TransferFormPrintSettings.defaults;
      }
    });

class WorkOrderType {
  final String id;
  final String name;
  final String? description;
  final String? locationInfo;
  final String? contactName;
  final String? contactPhone;
  final String color;
  final bool isActive;

  WorkOrderType({
    required this.id,
    required this.name,
    this.description,
    this.locationInfo,
    this.contactName,
    this.contactPhone,
    this.color = '#6366F1',
    this.isActive = true,
  });

  factory WorkOrderType.fromJson(Map<String, dynamic> json) => WorkOrderType(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    description: json['description']?.toString(),
    locationInfo: json['location_info']?.toString(),
    contactName: json['contact_name']?.toString(),
    contactPhone: json['contact_phone']?.toString(),
    color: json['color']?.toString() ?? '#6366F1',
    isActive: json['is_active'] as bool? ?? true,
  );
}

class TaxRate {
  final String id;
  final String name;
  final double rate;
  final bool isDefault;
  final bool isActive;

  TaxRate({
    required this.id,
    required this.name,
    required this.rate,
    this.isDefault = false,
    this.isActive = true,
  });

  factory TaxRate.fromJson(Map<String, dynamic> json) => TaxRate(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    rate: (json['rate'] as num?)?.toDouble() ?? 0,
    isDefault: json['is_default'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
  );
}

class CityDefinition {
  final String id;
  final String name;
  final String? code;
  final bool isActive;

  CityDefinition({
    required this.id,
    required this.name,
    required this.code,
    this.isActive = true,
  });

  factory CityDefinition.fromJson(Map<String, dynamic> json) => CityDefinition(
    id: json['id'].toString(),
    name: json['name']?.toString() ?? '',
    code: json['code']?.toString(),
    isActive: json['is_active'] as bool? ?? true,
  );
}

class FiscalSymbolDefinition {
  final String id;
  final String name;
  final String? code;
  final bool isActive;

  FiscalSymbolDefinition({
    required this.id,
    required this.name,
    required this.code,
    this.isActive = true,
  });

  factory FiscalSymbolDefinition.fromJson(Map<String, dynamic> json) =>
      FiscalSymbolDefinition(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        code: json['code']?.toString(),
        isActive: json['is_active'] as bool? ?? true,
      );
}

class BusinessActivityTypeDefinition {
  final String id;
  final String name;
  final bool isActive;

  BusinessActivityTypeDefinition({
    required this.id,
    required this.name,
    this.isActive = true,
  });

  factory BusinessActivityTypeDefinition.fromJson(Map<String, dynamic> json) =>
      BusinessActivityTypeDefinition(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        isActive: json['is_active'] as bool? ?? true,
      );
}

class DefinitionsScreen extends ConsumerWidget {
  const DefinitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final brandsAsync = ref.watch(deviceBrandsProvider);
    final modelsAsync = ref.watch(deviceModelsProvider);
    final typesAsync = ref.watch(workOrderTypesProvider);
    final ratesAsync = ref.watch(taxRatesProvider);
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    final fiscalSymbolsAsync = ref.watch(fiscalSymbolsProvider);
    final businessActivitiesAsync = ref.watch(businessActivityTypesProvider);
    final applicationFormSettingsAsync = ref.watch(
      applicationFormPrintSettingsProvider,
    );
    final scrapFormSettingsAsync = ref.watch(scrapFormPrintSettingsProvider);
    final transferFormSettingsAsync = ref.watch(
      transferFormPrintSettingsProvider,
    );
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    return DefaultTabController(
      length: 8,
      child: AppPageLayout(
        title: 'Tanımlamalar',
        subtitle: 'Sistem tanımları, form sabitleri ve operasyon ayarları.',
        body: Column(
          children: [
            AppSectionCard(
              title: 'Tanım Özeti',
              subtitle:
                  'Sık kullanılan tanımları tek yerden yönetin, aktif setleri hızlıca görün.',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  CompactStatCard(
                    label: 'Marka',
                    value: brandsAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.copyright_rounded,
                    color: AppTheme.primary,
                  ),
                  CompactStatCard(
                    label: 'Model',
                    value: modelsAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.memory_rounded,
                    color: const Color(0xFF2563EB),
                  ),
                  CompactStatCard(
                    label: 'İş Emri Tipi',
                    value: typesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.widgets_outlined,
                    color: const Color(0xFF0F766E),
                  ),
                  CompactStatCard(
                    label: 'KDV',
                    value: ratesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.percent_rounded,
                    color: const Color(0xFFEA580C),
                  ),
                  CompactStatCard(
                    label: 'Mali Sembol',
                    value:
                        fiscalSymbolsAsync.asData?.value.length.toString() ??
                        '—',
                    icon: Icons.qr_code_rounded,
                    color: const Color(0xFF7C3AED),
                  ),
                  CompactStatCard(
                    label: 'Meslek Türü',
                    value:
                        businessActivitiesAsync.asData?.value.length
                            .toString() ??
                        '—',
                    icon: Icons.storefront_rounded,
                    color: const Color(0xFF0891B2),
                  ),
                  CompactStatCard(
                    label: 'Şehir',
                    value: citiesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.location_city_rounded,
                    color: const Color(0xFF16A34A),
                  ),
                  CompactStatCard(
                    label: 'Form Çıktısı',
                    value:
                        applicationFormSettingsAsync.hasValue &&
                            scrapFormSettingsAsync.hasValue &&
                            transferFormSettingsAsync.hasValue
                        ? 'Hazır'
                        : '—',
                    icon: Icons.description_rounded,
                    color: const Color(0xFF64748B),
                  ),
                ],
              ),
            ),
            const Gap(14),
            AppSectionCard(
              padding: EdgeInsets.zero,
              title: 'Tanım Kategorileri',
              subtitle:
                  'Sekmeler arasında geçip marka, model, vergi, şehir ve form ayarlarını yönetin.',
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const SizedBox(height: 4),
                    const TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      labelPadding: EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      tabs: [
                        Tab(text: 'Markalar'),
                        Tab(text: 'Modeller'),
                        Tab(text: 'İş Emri Tipleri'),
                        Tab(text: 'KDV Oranları'),
                        Tab(text: 'Mali Semboller'),
                        Tab(text: 'Meslek Türleri'),
                        Tab(text: 'Şehirler'),
                        Tab(text: 'Form Çıktıları'),
                      ],
                    ),
                    const Divider(height: 1),
                    SizedBox(
                      height: isMobile ? 620 : 680,
                      child: TabBarView(
                        children: [
                          _BrandsTab(isAdmin: isAdmin),
                          _ModelsTab(isAdmin: isAdmin),
                          _WorkOrderTypesTab(isAdmin: isAdmin),
                          _TaxRatesTab(isAdmin: isAdmin),
                          _FiscalSymbolsTab(isAdmin: isAdmin),
                          _BusinessActivitiesTab(isAdmin: isAdmin),
                          _CitiesTab(isAdmin: isAdmin),
                          _ApplicationFormSettingsTab(isAdmin: isAdmin),
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

class _BrandsTab extends ConsumerWidget {
  const _BrandsTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final brandsAsync = ref.watch(deviceBrandsProvider);
    return _DefinitionTabScaffold(
      title: 'Cihaz Markaları',
      subtitle: 'Marka listelerini aktif/pasif olarak yönetin.',
      isAdmin: isAdmin,
      actionLabel: 'Marka Ekle',
      onAdd: () async {
        await _showCreateBrandDialog(context, ref);
        ref.invalidate(deviceBrandsProvider);
      },
      child: brandsAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _BrandRow(brand: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _ModelsTab extends ConsumerWidget {
  const _ModelsTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final modelsAsync = ref.watch(deviceModelsProvider);
    final brandsAsync = ref.watch(deviceBrandsProvider);
    return _DefinitionTabScaffold(
      title: 'Cihaz Modelleri',
      subtitle: 'Marka bağlı model tanımlarını burada yönetin.',
      isAdmin: isAdmin,
      actionLabel: 'Model Ekle',
      onAdd: () async {
        final brands = brandsAsync.value ?? const <DeviceBrand>[];
        await _showCreateModelDialog(context, ref, brands: brands);
        ref.invalidate(deviceModelsProvider);
      },
      child: modelsAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _ModelRow(model: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _BrandRow extends ConsumerStatefulWidget {
  const _BrandRow({required this.brand, required this.isAdmin});

  final DeviceBrand brand;
  final bool isAdmin;

  @override
  ConsumerState<_BrandRow> createState() => _BrandRowState();
}

class _BrandRowState extends ConsumerState<_BrandRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('device_brands')
          .update({'is_active': !widget.brand.isActive})
          .eq('id', widget.brand.id);
      ref.invalidate(deviceBrandsProvider);
      ref.invalidate(deviceModelsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final b = widget.brand;
    return _DefinitionListItem(
      leading: _DefinitionLeadingIcon(
        icon: Icons.copyright_rounded,
        color: const Color(0xFF2563EB),
      ),
      title: b.name,
      subtitle: 'Cihaz markası',
      isActive: b.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: b.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

class _ModelRow extends ConsumerStatefulWidget {
  const _ModelRow({required this.model, required this.isAdmin});

  final DeviceModel model;
  final bool isAdmin;

  @override
  ConsumerState<_ModelRow> createState() => _ModelRowState();
}

class _ModelRowState extends ConsumerState<_ModelRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('device_models')
          .update({'is_active': !widget.model.isActive})
          .eq('id', widget.model.id);
      ref.invalidate(deviceModelsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.model;
    return _DefinitionListItem(
      leading: _DefinitionLeadingIcon(
        icon: Icons.memory_rounded,
        color: const Color(0xFF0F766E),
      ),
      title: m.name,
      subtitle: m.brandName ?? 'Marka bilgisi yok',
      isActive: m.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: m.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

Future<void> _showCreateBrandDialog(BuildContext context, WidgetRef ref) async {
  final controller = TextEditingController();
  bool saving = false;

  await showDialog<void>(
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
                        'Marka Ekle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Marka',
                    hintText: 'Örn: HP',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = controller.text.trim();
                                if (name.isEmpty) return;
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                setState(() => saving = true);
                                try {
                                  await client.from('device_brands').insert({
                                    'name': name,
                                    'is_active': true,
                                  });
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
                            : const Text('Ekle'),
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

  controller.dispose();
}

Future<void> _showCreateModelDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<DeviceBrand> brands,
}) async {
  final controller = TextEditingController();
  String? brandId = brands.isEmpty ? null : brands.first.id;
  bool saving = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620),
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
                        'Model Ekle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                DropdownButtonFormField<String?>(
                  initialValue: brandId,
                  items: [
                    for (final b in brands)
                      DropdownMenuItem<String?>(
                        value: b.id,
                        child: Text(b.name),
                      ),
                  ],
                  onChanged: saving ? null : (v) => setState(() => brandId = v),
                  decoration: const InputDecoration(labelText: 'Marka'),
                ),
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Model',
                    hintText: 'Örn: LaserJet 1020',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = controller.text.trim();
                                if (name.isEmpty) return;
                                final selected = brandId;
                                if (selected == null) return;
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                setState(() => saving = true);
                                try {
                                  await client.from('device_models').insert({
                                    'brand_id': selected,
                                    'name': name,
                                    'is_active': true,
                                  });
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
                            : const Text('Ekle'),
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

  controller.dispose();
}

class _WorkOrderTypesTab extends ConsumerWidget {
  const _WorkOrderTypesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typesAsync = ref.watch(workOrderTypesProvider);
    return _DefinitionTabScaffold(
      title: 'İş Emri Tipleri',
      subtitle: 'Konum, irtibat ve renk bilgileriyle tip tanımlarını yönetin.',
      isAdmin: isAdmin,
      actionLabel: 'Tip Ekle',
      onAdd: () async {
        await _showCreateWorkOrderTypeDialog(context, ref);
        ref.invalidate(workOrderTypesProvider);
      },
      child: typesAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _WorkOrderTypeRow(type: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _WorkOrderTypeRow extends ConsumerStatefulWidget {
  const _WorkOrderTypeRow({required this.type, required this.isAdmin});

  final WorkOrderType type;
  final bool isAdmin;

  @override
  ConsumerState<_WorkOrderTypeRow> createState() => _WorkOrderTypeRowState();
}

class _WorkOrderTypeRowState extends ConsumerState<_WorkOrderTypeRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('work_order_types')
          .update({'is_active': !widget.type.isActive})
          .eq('id', widget.type.id);
      ref.invalidate(workOrderTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.type;
    final color = _parseColor(t.color);
    final meta = [
      if (t.description?.trim().isNotEmpty ?? false) t.description!,
      if (t.locationInfo?.trim().isNotEmpty ?? false) 'Konum: ${t.locationInfo!}',
      if ((t.contactName?.trim().isNotEmpty ?? false) ||
          (t.contactPhone?.trim().isNotEmpty ?? false))
        [
          if (t.contactName?.trim().isNotEmpty ?? false) t.contactName!,
          if (t.contactPhone?.trim().isNotEmpty ?? false) t.contactPhone!,
        ].join(' • '),
    ];
    return _DefinitionListItem(
      leading: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Center(
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        ),
      ),
      title: t.name,
      subtitle: meta.isEmpty ? 'İş emri tipi' : meta.join('  •  '),
      isActive: t.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: 'Düzenle',
            onPressed: () async {
              await _showEditWorkOrderTypeDialog(context, ref, t);
              ref.invalidate(workOrderTypesProvider);
            },
          ),
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: t.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

class _TaxRatesTab extends ConsumerWidget {
  const _TaxRatesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(taxRatesProvider);
    return _DefinitionTabScaffold(
      title: 'KDV Oranları',
      subtitle: 'Varsayılan oranları ve aktif vergi setlerini yönetin.',
      isAdmin: isAdmin,
      actionLabel: 'Oran Ekle',
      onAdd: () async {
        await _showCreateTaxRateDialog(context, ref);
        ref.invalidate(taxRatesProvider);
      },
      child: ratesAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _TaxRateRow(rate: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _FiscalSymbolsTab extends ConsumerWidget {
  const _FiscalSymbolsTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(fiscalSymbolsProvider);
    return _DefinitionTabScaffold(
      title: 'Mali Sembol Tanımları',
      subtitle: 'Firma kodu ve sembol karşılıklarını buradan yönetin.',
      isAdmin: isAdmin,
      actionLabel: 'Sembol Ekle',
      onAdd: () async {
        await _showFiscalSymbolDialog(context, ref);
        ref.invalidate(fiscalSymbolsProvider);
      },
      child: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _FiscalSymbolRow(item: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _BusinessActivitiesTab extends ConsumerWidget {
  const _BusinessActivitiesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(businessActivityTypesProvider);
    return _DefinitionTabScaffold(
      title: 'Ticari Faaliyet / Meslek Türleri',
      subtitle: 'Başvuru ve cihaz işlemlerinde kullanılan faaliyet tanımları.',
      isAdmin: isAdmin,
      actionLabel: 'Meslek Türü Ekle',
      onAdd: () async {
        await _showBusinessActivityDialog(context, ref);
        ref.invalidate(businessActivityTypesProvider);
      },
      child: itemsAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _BusinessActivityRow(item: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _CitiesTab extends ConsumerWidget {
  const _CitiesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    return _DefinitionTabScaffold(
      title: 'Şehir Tanımları',
      subtitle: 'Müşteri, şube ve form ekranlarında kullanılan şehir listesi.',
      isAdmin: isAdmin,
      actionLabel: 'Şehir Ekle',
      onAdd: () async {
        await _showCityDialog(context, ref);
        ref.invalidate(cityDefinitionsProvider);
      },
      child: citiesAsync.when(
        data: (items) {
          if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) =>
                _CityRow(city: items[index], isAdmin: isAdmin),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class _FiscalSymbolRow extends ConsumerStatefulWidget {
  const _FiscalSymbolRow({required this.item, required this.isAdmin});

  final FiscalSymbolDefinition item;
  final bool isAdmin;

  @override
  ConsumerState<_FiscalSymbolRow> createState() => _FiscalSymbolRowState();
}

class _FiscalSymbolRowState extends ConsumerState<_FiscalSymbolRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('fiscal_symbols')
          .update({'is_active': !widget.item.isActive})
          .eq('id', widget.item.id);
      ref.invalidate(fiscalSymbolsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DefinitionListItem(
      leading: _DefinitionLeadingIcon(
        icon: Icons.qr_code_rounded,
        color: const Color(0xFF7C3AED),
      ),
      title: widget.item.name,
      subtitle: widget.item.code?.trim().isNotEmpty ?? false
          ? widget.item.code!
          : 'Firma kodu tanımı',
      isActive: widget.item.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: 'Düzenle',
            onPressed: () async {
              await _showFiscalSymbolDialog(context, ref, item: widget.item);
              ref.invalidate(fiscalSymbolsProvider);
            },
          ),
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: widget.item.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

class _BusinessActivityRow extends ConsumerStatefulWidget {
  const _BusinessActivityRow({required this.item, required this.isAdmin});

  final BusinessActivityTypeDefinition item;
  final bool isAdmin;

  @override
  ConsumerState<_BusinessActivityRow> createState() =>
      _BusinessActivityRowState();
}

class _BusinessActivityRowState extends ConsumerState<_BusinessActivityRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('business_activity_types')
          .update({'is_active': !widget.item.isActive})
          .eq('id', widget.item.id);
      ref.invalidate(businessActivityTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _DefinitionListItem(
      leading: _DefinitionLeadingIcon(
        icon: Icons.storefront_rounded,
        color: const Color(0xFF0891B2),
      ),
      title: widget.item.name,
      subtitle: 'Faaliyet / meslek tipi',
      isActive: widget.item.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: 'Düzenle',
            onPressed: () async {
              await _showBusinessActivityDialog(context, ref, item: widget.item);
              ref.invalidate(businessActivityTypesProvider);
            },
          ),
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: widget.item.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

class _CityRow extends ConsumerStatefulWidget {
  const _CityRow({required this.city, required this.isAdmin});

  final CityDefinition city;
  final bool isAdmin;

  @override
  ConsumerState<_CityRow> createState() => _CityRowState();
}

class _CityRowState extends ConsumerState<_CityRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('cities')
          .update({'is_active': !widget.city.isActive})
          .eq('id', widget.city.id);
      ref.invalidate(cityDefinitionsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final city = widget.city;
    return _DefinitionListItem(
      leading: _DefinitionLeadingIcon(
        icon: Icons.location_city_rounded,
        color: const Color(0xFF16A34A),
      ),
      title: city.name,
      subtitle: city.code?.trim().isNotEmpty ?? false
          ? 'Kod: ${city.code!}'
          : 'Şehir tanımı',
      isActive: city.isActive,
      actions: [
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: 'Düzenle',
            onPressed: () async {
              await _showCityDialog(context, ref, city: city);
              ref.invalidate(cityDefinitionsProvider);
            },
          ),
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: city.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

class _TaxRateRow extends ConsumerStatefulWidget {
  const _TaxRateRow({required this.rate, required this.isAdmin});

  final TaxRate rate;
  final bool isAdmin;

  @override
  ConsumerState<_TaxRateRow> createState() => _TaxRateRowState();
}

class _TaxRateRowState extends ConsumerState<_TaxRateRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client
          .from('tax_rates')
          .update({'is_active': !widget.rate.isActive})
          .eq('id', widget.rate.id);
      ref.invalidate(taxRatesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setDefault() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      // Clear existing defaults
      await client
          .from('tax_rates')
          .update({'is_default': false})
          .eq('is_default', true);
      // Set new default
      await client
          .from('tax_rates')
          .update({'is_default': true})
          .eq('id', widget.rate.id);
      ref.invalidate(taxRatesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rate;
    return _DefinitionListItem(
      leading: Container(
        width: 40,
        height: 32,
        decoration: BoxDecoration(
          color: AppTheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: r.isDefault
                ? AppTheme.primary.withValues(alpha: 0.25)
                : AppTheme.border,
          ),
        ),
        child: Center(
          child: Text(
            '%${r.rate.toStringAsFixed(0)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: AppTheme.primary,
            ),
          ),
        ),
      ),
      title: r.name,
      subtitle: r.isDefault ? 'Varsayılan oran' : 'KDV oranı',
      isActive: r.isActive,
      extraBadges: [
        if (r.isDefault) AppBadge(label: 'Varsayılan', tone: AppBadgeTone.primary),
      ],
      actions: [
        if (widget.isAdmin && !r.isDefault)
          _DefinitionActionButton(
            label: 'Varsayılan Yap',
            isBusy: _saving,
            onPressed: _setDefault,
          ),
        if (widget.isAdmin)
          _DefinitionActionButton(
            label: r.isActive ? 'Pasif Yap' : 'Aktif Yap',
            isBusy: _saving,
            onPressed: _toggleActive,
          ),
      ],
    );
  }
}

Future<void> _showCreateWorkOrderTypeDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  await _showEditWorkOrderTypeDialog(context, ref, null);
}

Future<void> _showEditWorkOrderTypeDialog(
  BuildContext context,
  WidgetRef ref,
  WorkOrderType? existing,
) async {
  final nameController = TextEditingController(text: existing?.name ?? '');
  final descController = TextEditingController(
    text: existing?.description ?? '',
  );
  final locationController = TextEditingController(
    text: existing?.locationInfo ?? '',
  );
  final contactNameController = TextEditingController(
    text: existing?.contactName ?? '',
  );
  final contactPhoneController = TextEditingController(
    text: existing?.contactPhone ?? '',
  );
  String selectedColor = existing?.color ?? '#6366F1';
  bool saving = false;

  final colors = [
    '#6366F1',
    '#22C55E',
    '#F59E0B',
    '#EF4444',
    '#3B82F6',
    '#8B5CF6',
    '#EC4899',
    '#14B8A6',
  ];

  await showDialog<void>(
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
                        existing == null
                            ? 'İş Emri Tipi Ekle'
                            : 'İş Emri Tipi Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Tip Adı',
                    hintText: 'Örn: Bakım',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (opsiyonel)',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: locationController,
                  decoration: const InputDecoration(
                    labelText: 'Konum Bilgisi',
                    hintText: 'Örn: Lefkoşa Merkez / Organize Sanayi',
                  ),
                ),
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: contactNameController,
                        decoration: const InputDecoration(
                          labelText: 'İrtibat Kişisi',
                          hintText: 'Örn: Servis Yetkilisi',
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextField(
                        controller: contactPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'İrtibat Telefonu',
                          hintText: '0 5xx xxx xx xx',
                        ),
                      ),
                    ),
                  ],
                ),
                const Gap(12),
                Text(
                  'Renk Seçin',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const Gap(8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: colors.map((c) {
                    final isSelected = c == selectedColor;
                    return InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () => setState(() => selectedColor = c),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: _parseColor(c),
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: Colors.black, width: 2)
                              : null,
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 18,
                              )
                            : null,
                      ),
                    );
                  }).toList(),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = nameController.text.trim();
                                if (name.isEmpty) return;
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                setState(() => saving = true);
                                try {
                                  final payload = {
                                    'name': name,
                                    'description':
                                        descController.text.trim().isEmpty
                                        ? null
                                        : descController.text.trim(),
                                    'location_info':
                                        locationController.text.trim().isEmpty
                                        ? null
                                        : locationController.text.trim(),
                                    'contact_name':
                                        contactNameController.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : contactNameController.text.trim(),
                                    'contact_phone':
                                        contactPhoneController.text
                                            .trim()
                                            .isEmpty
                                        ? null
                                        : contactPhoneController.text.trim(),
                                    'color': selectedColor,
                                    'is_active': existing?.isActive ?? true,
                                  };
                                  if (existing == null) {
                                    await client
                                        .from('work_order_types')
                                        .insert(payload);
                                  } else {
                                    await client
                                        .from('work_order_types')
                                        .update(payload)
                                        .eq('id', existing.id);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
                            : const Text('Ekle'),
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

  nameController.dispose();
  descController.dispose();
  locationController.dispose();
  contactNameController.dispose();
  contactPhoneController.dispose();
}

Future<void> _showCreateTaxRateDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final nameController = TextEditingController();
  final rateController = TextEditingController();
  bool saving = false;

  await showDialog<void>(
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
                        'KDV Oranı Ekle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Oran Adı',
                    hintText: 'Örn: Standart KDV',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Oran (%)',
                    hintText: 'Örn: 20',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final name = nameController.text.trim();
                                final rate = double.tryParse(
                                  rateController.text.trim(),
                                );
                                if (name.isEmpty || rate == null) return;
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                setState(() => saving = true);
                                try {
                                  await client.from('tax_rates').insert({
                                    'name': name,
                                    'rate': rate,
                                    'is_active': true,
                                    'is_default': false,
                                  });
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
                            : const Text('Ekle'),
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

  nameController.dispose();
  rateController.dispose();
}

Future<void> _showFiscalSymbolDialog(
  BuildContext context,
  WidgetRef ref, {
  FiscalSymbolDefinition? item,
}) async {
  final nameController = TextEditingController(text: item?.name ?? '');
  final codeController = TextEditingController(text: item?.code ?? '');
  bool saving = false;

  await showDialog<void>(
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
                        item == null
                            ? 'Mali Sembol Ekle'
                            : 'Mali Sembol Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Sembol Adı',
                    hintText: 'Örn: MF-2D',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Firma Kodu (opsiyonel)',
                    hintText: 'Örn: MF-2D',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                final name = nameController.text.trim();
                                if (name.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final payload = {
                                    'name': name,
                                    'code': codeController.text.trim().isEmpty
                                        ? null
                                        : codeController.text.trim(),
                                    'is_active': item?.isActive ?? true,
                                  };
                                  if (item == null) {
                                    await client
                                        .from('fiscal_symbols')
                                        .insert(payload);
                                  } else {
                                    await client
                                        .from('fiscal_symbols')
                                        .update(payload)
                                        .eq('id', item.id);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
}

Future<void> _showBusinessActivityDialog(
  BuildContext context,
  WidgetRef ref, {
  BusinessActivityTypeDefinition? item,
}) async {
  final nameController = TextEditingController(text: item?.name ?? '');
  bool saving = false;

  await showDialog<void>(
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
                        item == null
                            ? 'Meslek Türü Ekle'
                            : 'Meslek Türü Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Meslek Türü',
                    hintText: 'Örn: Market',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                final name = nameController.text.trim();
                                if (name.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final payload = {
                                    'name': name,
                                    'is_active': item?.isActive ?? true,
                                  };
                                  if (item == null) {
                                    await client
                                        .from('business_activity_types')
                                        .insert(payload);
                                  } else {
                                    await client
                                        .from('business_activity_types')
                                        .update(payload)
                                        .eq('id', item.id);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
}

Color _parseColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

class _DefinitionTabScaffold extends StatelessWidget {
  const _DefinitionTabScaffold({
    required this.title,
    required this.subtitle,
    required this.isAdmin,
    required this.child,
    this.actionLabel,
    this.onAdd,
  });

  final String title;
  final String subtitle;
  final bool isAdmin;
  final Widget child;
  final String? actionLabel;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return Padding(
      padding: EdgeInsets.all(isMobile ? 12 : 14),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (isAdmin && onAdd != null && actionLabel != null)
                FilledButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: Text(actionLabel!),
                ),
            ],
          ),
          const Gap(10),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _DefinitionLeadingIcon extends StatelessWidget {
  const _DefinitionLeadingIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 18, color: color),
    );
  }
}

class _DefinitionActionButton extends StatelessWidget {
  const _DefinitionActionButton({
    required this.label,
    required this.onPressed,
    this.isBusy = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: isBusy ? null : onPressed,
      style: OutlinedButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        minimumSize: const Size(0, 34),
      ),
      child: isBusy
          ? const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(label),
    );
  }
}

class _DefinitionListItem extends StatelessWidget {
  const _DefinitionListItem({
    required this.leading,
    required this.title,
    required this.subtitle,
    required this.isActive,
    this.actions = const [],
    this.extraBadges = const [],
  });

  final Widget leading;
  final String title;
  final String subtitle;
  final bool isActive;
  final List<Widget> actions;
  final List<Widget> extraBadges;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: isActive
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    const Gap(3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Gap(10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              ...extraBadges,
              AppBadge(
                label: isActive ? 'Aktif' : 'Pasif',
                tone: isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
              ),
              ...actions,
            ],
          ),
        ],
      ),
    );
  }
}

Future<void> _showCityDialog(
  BuildContext context,
  WidgetRef ref, {
  CityDefinition? city,
}) async {
  final nameController = TextEditingController(text: city?.name ?? '');
  final codeController = TextEditingController(text: city?.code ?? '');
  bool saving = false;

  await showDialog<void>(
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
                        city == null ? 'Şehir Ekle' : 'Şehir Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Şehir Adı',
                    hintText: 'Örn: İstanbul',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Şehir Kodu',
                    hintText: 'Örn: 34',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final client = ref.read(supabaseClientProvider);
                                if (client == null) return;
                                final name = nameController.text.trim();
                                if (name.isEmpty) return;
                                setState(() => saving = true);
                                try {
                                  final payload = {
                                    'name': name,
                                    'code': codeController.text.trim().isEmpty
                                        ? null
                                        : codeController.text.trim(),
                                    'is_active': city?.isActive ?? true,
                                  };
                                  if (city == null) {
                                    await client.from('cities').insert(payload);
                                  } else {
                                    await client
                                        .from('cities')
                                        .update(payload)
                                        .eq('id', city.id);
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
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
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

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

class _ApplicationFormSettingsTab extends ConsumerStatefulWidget {
  const _ApplicationFormSettingsTab({required this.isAdmin});

  final bool isAdmin;

  @override
  ConsumerState<_ApplicationFormSettingsTab> createState() =>
      _ApplicationFormSettingsTabState();
}

class _ApplicationFormSettingsTabState
    extends ConsumerState<_ApplicationFormSettingsTab> {
  final _officeTitleController = TextEditingController();
  final _introTextController = TextEditingController();
  final _optionalPowerController = TextEditingController();
  final _manualIncludedController = TextEditingController();
  final _serviceCompanyNameController = TextEditingController();
  final _serviceCompanyAddressController = TextEditingController();
  final _applicantStatusController = TextEditingController();
  final _officeTitle4aController = TextEditingController();
  final _kdv4aTitleController = TextEditingController();
  final _kdv4aSerialNumberController = TextEditingController();
  final _kdv4aSellerCompanyNameController = TextEditingController();
  final _kdv4aSellerAddressController = TextEditingController();
  final _kdv4aSellerTaxRegistryController = TextEditingController();
  final _kdv4aSellerLicenseNumberController = TextEditingController();
  final _kdv4aWarrantyPeriodController = TextEditingController();
  final _kdv4aDepartmentCountController = TextEditingController();
  final _kdv4aServiceCompanyNameController = TextEditingController();
  final _kdv4aServiceCompanyAddressController = TextEditingController();
  final _kdv4aSealApplicantNameController = TextEditingController();
  final _kdv4aSealApplicantTitleController = TextEditingController();
  final _kdv4aApprovalDateController = TextEditingController();
  final _kdv4aApprovalNumberController = TextEditingController();
  final _kdv4aDeliveryReceiverNameController = TextEditingController();
  final _kdv4aDeliveryReceiverTitleController = TextEditingController();
  final _scrapFormCodeController = TextEditingController();
  final _scrapTitleController = TextEditingController();
  final _scrapDateLabelController = TextEditingController();
  final _scrapRowNumberLabelController = TextEditingController();
  final _scrapServiceSectionTitleController = TextEditingController();
  final _scrapServiceCompanyLabelController = TextEditingController();
  final _scrapServiceIdentityLabelController = TextEditingController();
  final _scrapServiceAddressLabelController = TextEditingController();
  final _scrapServiceTaxLabelController = TextEditingController();
  final _scrapServiceCompanyValueController = TextEditingController();
  final _scrapServiceIdentityValueController = TextEditingController();
  final _scrapServiceAddressValueController = TextEditingController();
  final _scrapServiceTaxValueController = TextEditingController();
  final _scrapOwnerSectionTitleController = TextEditingController();
  final _scrapOwnerNameLabelController = TextEditingController();
  final _scrapOwnerAddressLabelController = TextEditingController();
  final _scrapOwnerTaxLabelController = TextEditingController();
  final _scrapDeviceSectionTitleController = TextEditingController();
  final _scrapStartDateLabelController = TextEditingController();
  final _scrapLastUsedDateLabelController = TextEditingController();
  final _scrapSummaryTitleController = TextEditingController();
  final _scrapZReportLabelController = TextEditingController();
  final _scrapVatTotalLabelController = TextEditingController();
  final _scrapGrossTotalLabelController = TextEditingController();
  final _scrapPurposeLabelController = TextEditingController();
  final _scrapOtherFindingsLabelController = TextEditingController();
  final _scrapOwnerSignatureTitleController = TextEditingController();
  final _scrapServiceSignatureTitleController = TextEditingController();
  final _transferTitleController = TextEditingController();
  final _transferSubtitleController = TextEditingController();
  final _transferOfficeTitleController = TextEditingController();
  final _transferRowNumberLabelController = TextEditingController();
  final _transferTransferorSectionTitleController = TextEditingController();
  final _transferTransfereeSectionTitleController = TextEditingController();
  final _transferDeviceSummaryTitleController = TextEditingController();
  final _transferDeviceInfoTitleController = TextEditingController();
  final _transferTransferInfoTitleController = TextEditingController();
  final _transferServiceCompanyValueController = TextEditingController();
  final _transferStatementTextController = TextEditingController();
  final _transferOfficeFillTitleController = TextEditingController();
  final _transferOfficeFillTextController = TextEditingController();
  final _transferControllerTitleController = TextEditingController();
  bool _initialized = false;
  bool _saving = false;

  @override
  void dispose() {
    _officeTitleController.dispose();
    _introTextController.dispose();
    _optionalPowerController.dispose();
    _manualIncludedController.dispose();
    _serviceCompanyNameController.dispose();
    _serviceCompanyAddressController.dispose();
    _applicantStatusController.dispose();
    _officeTitle4aController.dispose();
    _kdv4aTitleController.dispose();
    _kdv4aSerialNumberController.dispose();
    _kdv4aSellerCompanyNameController.dispose();
    _kdv4aSellerAddressController.dispose();
    _kdv4aSellerTaxRegistryController.dispose();
    _kdv4aSellerLicenseNumberController.dispose();
    _kdv4aWarrantyPeriodController.dispose();
    _kdv4aDepartmentCountController.dispose();
    _kdv4aServiceCompanyNameController.dispose();
    _kdv4aServiceCompanyAddressController.dispose();
    _kdv4aSealApplicantNameController.dispose();
    _kdv4aSealApplicantTitleController.dispose();
    _kdv4aApprovalDateController.dispose();
    _kdv4aApprovalNumberController.dispose();
    _kdv4aDeliveryReceiverNameController.dispose();
    _kdv4aDeliveryReceiverTitleController.dispose();
    _scrapFormCodeController.dispose();
    _scrapTitleController.dispose();
    _scrapDateLabelController.dispose();
    _scrapRowNumberLabelController.dispose();
    _scrapServiceSectionTitleController.dispose();
    _scrapServiceCompanyLabelController.dispose();
    _scrapServiceIdentityLabelController.dispose();
    _scrapServiceAddressLabelController.dispose();
    _scrapServiceTaxLabelController.dispose();
    _scrapServiceCompanyValueController.dispose();
    _scrapServiceIdentityValueController.dispose();
    _scrapServiceAddressValueController.dispose();
    _scrapServiceTaxValueController.dispose();
    _scrapOwnerSectionTitleController.dispose();
    _scrapOwnerNameLabelController.dispose();
    _scrapOwnerAddressLabelController.dispose();
    _scrapOwnerTaxLabelController.dispose();
    _scrapDeviceSectionTitleController.dispose();
    _scrapStartDateLabelController.dispose();
    _scrapLastUsedDateLabelController.dispose();
    _scrapSummaryTitleController.dispose();
    _scrapZReportLabelController.dispose();
    _scrapVatTotalLabelController.dispose();
    _scrapGrossTotalLabelController.dispose();
    _scrapPurposeLabelController.dispose();
    _scrapOtherFindingsLabelController.dispose();
    _scrapOwnerSignatureTitleController.dispose();
    _scrapServiceSignatureTitleController.dispose();
    _transferTitleController.dispose();
    _transferSubtitleController.dispose();
    _transferOfficeTitleController.dispose();
    _transferRowNumberLabelController.dispose();
    _transferTransferorSectionTitleController.dispose();
    _transferTransfereeSectionTitleController.dispose();
    _transferDeviceSummaryTitleController.dispose();
    _transferDeviceInfoTitleController.dispose();
    _transferTransferInfoTitleController.dispose();
    _transferServiceCompanyValueController.dispose();
    _transferStatementTextController.dispose();
    _transferOfficeFillTitleController.dispose();
    _transferOfficeFillTextController.dispose();
    _transferControllerTitleController.dispose();
    super.dispose();
  }

  void _apply(
    ApplicationFormPrintSettings settings,
    ScrapFormPrintSettings scrapSettings,
    TransferFormPrintSettings transferSettings,
  ) {
    if (_initialized) return;
    _officeTitleController.text = settings.officeTitle;
    _introTextController.text = settings.introText;
    _optionalPowerController.text = settings.optionalPowerPrecautionText;
    _manualIncludedController.text = settings.manualIncludedText;
    _serviceCompanyNameController.text = settings.serviceCompanyName;
    _serviceCompanyAddressController.text = settings.serviceCompanyAddress;
    _applicantStatusController.text = settings.applicantStatus;
    _officeTitle4aController.text = settings.officeTitle4a;
    _kdv4aTitleController.text = settings.kdv4aTitle;
    _kdv4aSerialNumberController.text = settings.kdv4aSerialNumber;
    _kdv4aSellerCompanyNameController.text = settings.kdv4aSellerCompanyName;
    _kdv4aSellerAddressController.text = settings.kdv4aSellerAddress;
    _kdv4aSellerTaxRegistryController.text =
        settings.kdv4aSellerTaxOfficeAndRegistry;
    _kdv4aSellerLicenseNumberController.text =
        settings.kdv4aSellerLicenseNumber;
    _kdv4aWarrantyPeriodController.text = settings.kdv4aWarrantyPeriod;
    _kdv4aDepartmentCountController.text = settings.kdv4aDepartmentCount;
    _kdv4aServiceCompanyNameController.text = settings.kdv4aServiceCompanyName;
    _kdv4aServiceCompanyAddressController.text =
        settings.kdv4aServiceCompanyAddress;
    _kdv4aSealApplicantNameController.text = settings.kdv4aSealApplicantName;
    _kdv4aSealApplicantTitleController.text = settings.kdv4aSealApplicantTitle;
    _kdv4aApprovalDateController.text = settings.kdv4aApprovalDocumentDate;
    _kdv4aApprovalNumberController.text = settings.kdv4aApprovalDocumentNumber;
    _kdv4aDeliveryReceiverNameController.text =
        settings.kdv4aDeliveryReceiverName;
    _kdv4aDeliveryReceiverTitleController.text =
        settings.kdv4aDeliveryReceiverTitle;
    _scrapFormCodeController.text = scrapSettings.formCode;
    _scrapTitleController.text = scrapSettings.title;
    _scrapDateLabelController.text = scrapSettings.dateLabel;
    _scrapRowNumberLabelController.text = scrapSettings.rowNumberLabel;
    _scrapServiceSectionTitleController.text =
        scrapSettings.serviceSectionTitle;
    _scrapServiceCompanyLabelController.text =
        scrapSettings.serviceCompanyLabel;
    _scrapServiceIdentityLabelController.text =
        scrapSettings.serviceIdentityLabel;
    _scrapServiceAddressLabelController.text =
        scrapSettings.serviceAddressLabel;
    _scrapServiceTaxLabelController.text = scrapSettings.serviceTaxLabel;
    _scrapServiceCompanyValueController.text =
        scrapSettings.serviceCompanyValue;
    _scrapServiceIdentityValueController.text =
        scrapSettings.serviceIdentityValue;
    _scrapServiceAddressValueController.text =
        scrapSettings.serviceAddressValue;
    _scrapServiceTaxValueController.text = scrapSettings.serviceTaxValue;
    _scrapOwnerSectionTitleController.text = scrapSettings.ownerSectionTitle;
    _scrapOwnerNameLabelController.text = scrapSettings.ownerNameLabel;
    _scrapOwnerAddressLabelController.text = scrapSettings.ownerAddressLabel;
    _scrapOwnerTaxLabelController.text = scrapSettings.ownerTaxLabel;
    _scrapDeviceSectionTitleController.text = scrapSettings.deviceSectionTitle;
    _scrapStartDateLabelController.text = scrapSettings.startDateLabel;
    _scrapLastUsedDateLabelController.text = scrapSettings.lastUsedDateLabel;
    _scrapSummaryTitleController.text = scrapSettings.summaryTitle;
    _scrapZReportLabelController.text = scrapSettings.zReportLabel;
    _scrapVatTotalLabelController.text = scrapSettings.vatTotalLabel;
    _scrapGrossTotalLabelController.text = scrapSettings.grossTotalLabel;
    _scrapPurposeLabelController.text = scrapSettings.purposeLabel;
    _scrapOtherFindingsLabelController.text = scrapSettings.otherFindingsLabel;
    _scrapOwnerSignatureTitleController.text =
        scrapSettings.ownerSignatureTitle;
    _scrapServiceSignatureTitleController.text =
        scrapSettings.serviceSignatureTitle;
    _transferTitleController.text = transferSettings.title;
    _transferSubtitleController.text = transferSettings.subtitle;
    _transferOfficeTitleController.text = transferSettings.officeTitle;
    _transferRowNumberLabelController.text = transferSettings.rowNumberLabel;
    _transferTransferorSectionTitleController.text =
        transferSettings.transferorSectionTitle;
    _transferTransfereeSectionTitleController.text =
        transferSettings.transfereeSectionTitle;
    _transferDeviceSummaryTitleController.text =
        transferSettings.deviceSummaryTitle;
    _transferDeviceInfoTitleController.text = transferSettings.deviceInfoTitle;
    _transferTransferInfoTitleController.text =
        transferSettings.transferInfoTitle;
    _transferServiceCompanyValueController.text =
        transferSettings.serviceCompanyValue;
    _transferStatementTextController.text = transferSettings.statementText;
    _transferOfficeFillTitleController.text = transferSettings.officeFillTitle;
    _transferOfficeFillTextController.text = transferSettings.officeFillText;
    _transferControllerTitleController.text = transferSettings.controllerTitle;
    _initialized = true;
  }

  Future<void> _save() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    setState(() => _saving = true);
    try {
      await client.from('application_form_settings').upsert({
        'id': 'default',
        'office_title': _officeTitleController.text.trim(),
        'intro_text': _introTextController.text.trim(),
        'optional_power_precaution_text': _optionalPowerController.text.trim(),
        'manual_included_text': _manualIncludedController.text.trim(),
        'service_company_name': _serviceCompanyNameController.text.trim(),
        'service_company_address': _serviceCompanyAddressController.text.trim(),
        'applicant_status': _applicantStatusController.text.trim(),
        'office_title_4a': _officeTitle4aController.text.trim(),
        'kdv4a_title': _kdv4aTitleController.text.trim(),
        'kdv4a_serial_number': _kdv4aSerialNumberController.text.trim(),
        'kdv4a_seller_company_name': _kdv4aSellerCompanyNameController.text
            .trim(),
        'kdv4a_seller_address': _kdv4aSellerAddressController.text.trim(),
        'kdv4a_seller_tax_office_and_registry':
            _kdv4aSellerTaxRegistryController.text.trim(),
        'kdv4a_seller_license_number': _kdv4aSellerLicenseNumberController.text
            .trim(),
        'kdv4a_warranty_period': _kdv4aWarrantyPeriodController.text.trim(),
        'kdv4a_department_count': _kdv4aDepartmentCountController.text.trim(),
        'kdv4a_service_company_name': _kdv4aServiceCompanyNameController.text
            .trim(),
        'kdv4a_service_company_address': _kdv4aServiceCompanyAddressController
            .text
            .trim(),
        'kdv4a_seal_applicant_name': _kdv4aSealApplicantNameController.text
            .trim(),
        'kdv4a_seal_applicant_title': _kdv4aSealApplicantTitleController.text
            .trim(),
        'kdv4a_approval_document_date': _kdv4aApprovalDateController.text
            .trim(),
        'kdv4a_approval_document_number': _kdv4aApprovalNumberController.text
            .trim(),
        'kdv4a_delivery_receiver_name': _kdv4aDeliveryReceiverNameController
            .text
            .trim(),
        'kdv4a_delivery_receiver_title': _kdv4aDeliveryReceiverTitleController
            .text
            .trim(),
      });
      await client.from('scrap_form_settings').upsert({
        'id': 'default',
        'form_code': _scrapFormCodeController.text.trim(),
        'title': _scrapTitleController.text.trim(),
        'date_label': _scrapDateLabelController.text.trim(),
        'row_number_label': _scrapRowNumberLabelController.text.trim(),
        'service_section_title': _scrapServiceSectionTitleController.text
            .trim(),
        'service_company_label': _scrapServiceCompanyLabelController.text
            .trim(),
        'service_identity_label': _scrapServiceIdentityLabelController.text
            .trim(),
        'service_address_label': _scrapServiceAddressLabelController.text
            .trim(),
        'service_tax_label': _scrapServiceTaxLabelController.text.trim(),
        'service_company_value': _scrapServiceCompanyValueController.text
            .trim(),
        'service_identity_value': _scrapServiceIdentityValueController.text
            .trim(),
        'service_address_value': _scrapServiceAddressValueController.text
            .trim(),
        'service_tax_value': _scrapServiceTaxValueController.text.trim(),
        'owner_section_title': _scrapOwnerSectionTitleController.text.trim(),
        'owner_name_label': _scrapOwnerNameLabelController.text.trim(),
        'owner_address_label': _scrapOwnerAddressLabelController.text.trim(),
        'owner_tax_label': _scrapOwnerTaxLabelController.text.trim(),
        'device_section_title': _scrapDeviceSectionTitleController.text.trim(),
        'start_date_label': _scrapStartDateLabelController.text.trim(),
        'last_used_date_label': _scrapLastUsedDateLabelController.text.trim(),
        'summary_title': _scrapSummaryTitleController.text.trim(),
        'z_report_label': _scrapZReportLabelController.text.trim(),
        'vat_total_label': _scrapVatTotalLabelController.text.trim(),
        'gross_total_label': _scrapGrossTotalLabelController.text.trim(),
        'purpose_label': _scrapPurposeLabelController.text.trim(),
        'other_findings_label': _scrapOtherFindingsLabelController.text.trim(),
        'owner_signature_title': _scrapOwnerSignatureTitleController.text
            .trim(),
        'service_signature_title': _scrapServiceSignatureTitleController.text
            .trim(),
      });
      await client.from('transfer_form_settings').upsert({
        'id': 'default',
        'title': _transferTitleController.text.trim(),
        'subtitle': _transferSubtitleController.text.trim(),
        'office_title': _transferOfficeTitleController.text.trim(),
        'row_number_label': _transferRowNumberLabelController.text.trim(),
        'transferor_section_title': _transferTransferorSectionTitleController
            .text
            .trim(),
        'transferee_section_title': _transferTransfereeSectionTitleController
            .text
            .trim(),
        'device_summary_title': _transferDeviceSummaryTitleController.text
            .trim(),
        'device_info_title': _transferDeviceInfoTitleController.text.trim(),
        'transfer_info_title': _transferTransferInfoTitleController.text.trim(),
        'service_company_value': _transferServiceCompanyValueController.text
            .trim(),
        'statement_text': _transferStatementTextController.text.trim(),
        'office_fill_title': _transferOfficeFillTitleController.text.trim(),
        'office_fill_text': _transferOfficeFillTextController.text.trim(),
        'controller_title': _transferControllerTitleController.text.trim(),
      });
      ref.invalidate(applicationFormPrintSettingsProvider);
      ref.invalidate(scrapFormPrintSettingsProvider);
      ref.invalidate(transferFormPrintSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Başvuru formu sabit alanları kaydedildi.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(applicationFormPrintSettingsProvider);
    final scrapSettingsAsync = ref.watch(scrapFormPrintSettingsProvider);
    final transferSettingsAsync = ref.watch(transferFormPrintSettingsProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: settingsAsync.when(
        data: (settings) => scrapSettingsAsync.when(
          data: (scrapSettings) => transferSettingsAsync.when(
            data: (transferSettings) {
              _apply(settings, scrapSettings, transferSettings);
              return SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Resmi Form Sabit Alanları',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(8),
                    Text(
                      'KDV4 / KDV4A / Hurda / Devir çıktılarında formdan gelmeyen sabit metinleri buradan değiştirebilirsiniz.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
                    const Gap(16),
                    TextField(
                      controller: _officeTitleController,
                      minLines: 3,
                      maxLines: 4,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Sol Üst Kurum Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _introTextController,
                      minLines: 3,
                      maxLines: 5,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Açıklama Paragrafı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _optionalPowerController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Güç Kaynağı Önlem Sabit Metni',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _manualIncludedController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Genel Kullanım Kılavuzu Sabit Metni',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _serviceCompanyNameController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Bakım Firması Ünvanı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _serviceCompanyAddressController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Bakım Firması Adresi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _applicantStatusController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Başvuru Sahibi Statüsü',
                      ),
                    ),
                    const Gap(24),
                    Text(
                      'KDV 4A Sabit Alanları',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(12),
                    TextField(
                      controller: _officeTitle4aController,
                      minLines: 3,
                      maxLines: 4,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'KDV 4A Sol Üst Kurum Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aTitleController,
                      minLines: 3,
                      maxLines: 4,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'KDV 4A Başlık',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSerialNumberController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'KDV 4A Sıra No',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSellerCompanyNameController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Satan Firma Ünvanı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSellerAddressController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Satan Firma Adresi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSellerTaxRegistryController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText:
                            'Satan Firma Vergi Dairesi ve Dosya Sicil No',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSellerLicenseNumberController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Ruhsatname No',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aWarrantyPeriodController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Garanti Süresi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aDepartmentCountController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Departman Sayısı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aServiceCompanyNameController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Yetkili Bakım Firması Ünvanı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aServiceCompanyAddressController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Yetkili Bakım Firması Adresi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSealApplicantNameController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mali Mühürü Tatbik Eden Açık İsmi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aSealApplicantTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mali Mühürü Tatbik Eden Makamı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aApprovalDateController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Onay Belgesi Tarihi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aApprovalNumberController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Onay Belgesi Sayısı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aDeliveryReceiverNameController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Teslim Alan Açık İsmi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _kdv4aDeliveryReceiverTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Teslim Alan Makamı',
                      ),
                    ),
                    const Gap(24),
                    Text(
                      'Hurda Formu Sabit Alanları',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapFormCodeController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(labelText: 'Form Kodu'),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapTitleController,
                      minLines: 3,
                      maxLines: 4,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Hurda Başlığı',
                      ),
                    ),
                    const Gap(12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _scrapDateLabelController,
                            enabled: widget.isAdmin && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Tarih Etiketi',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _scrapRowNumberLabelController,
                            enabled: widget.isAdmin && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Sıra No Etiketi',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceSectionTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Yetkili Servis Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceCompanyLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Firma Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceIdentityLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Ünvan / Sicil Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceAddressLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Adres Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceTaxLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Vergi Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceCompanyValueController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Firma Sabit Değeri',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceIdentityValueController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Ünvan / Sicil Sabit Değeri',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceAddressValueController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Adres Sabit Değeri',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceTaxValueController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis Vergi Sabit Değeri',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOwnerSectionTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mükellef Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOwnerNameLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mükellef Ad Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOwnerAddressLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mükellef Adres Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOwnerTaxLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mükellef Vergi Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapDeviceSectionTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Cihaz Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapStartDateLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Başlangıç Tarihi Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapLastUsedDateLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Son Kullanım Tarihi Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapSummaryTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Özet Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapZReportLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Z Rapor Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapVatTotalLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'KDV Tahsilat Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapGrossTotalLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Hasılat Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapPurposeLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Müdahale Amacı Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOtherFindingsLabelController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Diğer Tespitler Etiketi',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapOwnerSignatureTitleController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Mükellef İmza Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _scrapServiceSignatureTitleController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Servis İmza Başlığı',
                      ),
                    ),
                    const Gap(24),
                    Text(
                      'Devir Formu Sabit Alanları',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferTitleController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devir Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferSubtitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devir Alt Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferOfficeTitleController,
                      minLines: 3,
                      maxLines: 4,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devir Kurum Başlığı',
                      ),
                    ),
                    const Gap(12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        SizedBox(
                          width: 220,
                          child: TextField(
                            controller: _transferRowNumberLabelController,
                            enabled: widget.isAdmin && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Sıra No Etiketi',
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _transferServiceCompanyValueController,
                            enabled: widget.isAdmin && !_saving,
                            decoration: const InputDecoration(
                              labelText: 'Yetkili Firma Sabit Değeri',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferTransferorSectionTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devreden Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferTransfereeSectionTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devralan Bölüm Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferDeviceSummaryTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devir Öncesi Bilgi Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferDeviceInfoTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Cihaz Bilgi Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferTransferInfoTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Devir Bilgi Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferStatementTextController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Beyan Metni',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferOfficeFillTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Daire Tarafından Doldurulacaktır Başlığı',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferOfficeFillTextController,
                      minLines: 2,
                      maxLines: 3,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Daire Açıklama Metni',
                      ),
                    ),
                    const Gap(12),
                    TextField(
                      controller: _transferControllerTitleController,
                      enabled: widget.isAdmin && !_saving,
                      decoration: const InputDecoration(
                        labelText: 'Kontrol Eden Başlığı',
                      ),
                    ),
                    const Gap(18),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton.icon(
                        onPressed: widget.isAdmin && !_saving ? _save : null,
                        icon: _saving
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_rounded, size: 18),
                        label: const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              );
            },
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
      ),
    );
  }
}

class DeviceBrand {
  const DeviceBrand({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory DeviceBrand.fromJson(Map<String, dynamic> json) {
    return DeviceBrand(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class DeviceModel {
  const DeviceModel({
    required this.id,
    required this.brandId,
    required this.brandName,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String brandId;
  final String? brandName;
  final String name;
  final bool isActive;

  factory DeviceModel.fromJson(Map<String, dynamic> json) {
    return DeviceModel(
      id: json['id'].toString(),
      brandId: json['brand_id'].toString(),
      brandName: json['brand_name']?.toString(),
      name: (json['name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}
