import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../application_forms/application_form_model.dart';
import '../forms/scrap_form_model.dart';
import '../forms/transfer_form_model.dart';

final deviceBrandsProvider = FutureProvider<List<DeviceBrand>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_device_brands'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DeviceBrand.fromJson)
        .toList(growable: false);
  }

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
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_device_models'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(DeviceModel.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('device_models')
      .select('id,name,is_active,brand_id,device_brands(name)')
      .order('name');
  return (rows as List).map((e) {
    final map = e as Map<String, dynamic>;
    final brand = map['device_brands'] as Map<String, dynamic>?;
    return DeviceModel.fromJson({
      ...map,
      'brand_name': brand?['name'],
    });
  }).toList(growable: false);
});

// İş Emri Tipleri Provider
final workOrderTypesProvider = FutureProvider<List<WorkOrderType>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_work_order_types'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WorkOrderType.fromJson)
        .toList(growable: false);
  }

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
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_tax_rates'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TaxRate.fromJson)
        .toList(growable: false);
  }

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

final cityDefinitionsProvider = FutureProvider<List<CityDefinition>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_cities'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(CityDefinition.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('cities')
      .select('id,name,code,is_active,created_at')
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map((e) => CityDefinition.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final fiscalSymbolsProvider = FutureProvider<List<FiscalSymbolDefinition>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_fiscal_symbols'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FiscalSymbolDefinition.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('fiscal_symbols')
      .select('id,name,code,is_active,created_at')
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map((e) => FiscalSymbolDefinition.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final businessActivityTypesProvider =
    FutureProvider<List<BusinessActivityTypeDefinition>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_business_activity_types'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BusinessActivityTypeDefinition.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('business_activity_types')
      .select('id,name,is_active,created_at')
      .eq('is_active', true)
      .order('name');
  return (rows as List)
      .map(
        (e) => BusinessActivityTypeDefinition.fromJson(e as Map<String, dynamic>),
      )
      .toList(growable: false);
});

final applicationFormPrintSettingsProvider =
    FutureProvider<ApplicationFormPrintSettings>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'application_form_print_settings'},
    );
    return ApplicationFormPrintSettings.fromJson(row);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return ApplicationFormPrintSettings.defaults;
  final row = await client
      .from('application_form_settings')
      .select()
      .eq('id', 'default')
      .maybeSingle();
  if (row == null) return ApplicationFormPrintSettings.defaults;
  return ApplicationFormPrintSettings.fromJson(row);
});

final scrapFormPrintSettingsProvider =
    FutureProvider<ScrapFormPrintSettings>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'scrap_form_print_settings'},
    );
    return ScrapFormPrintSettings.fromJson(row);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return ScrapFormPrintSettings.defaults;
  final row = await client
      .from('scrap_form_settings')
      .select()
      .eq('id', 'default')
      .maybeSingle();
  if (row == null) return ScrapFormPrintSettings.defaults;
  return ScrapFormPrintSettings.fromJson(row);
});

final transferFormPrintSettingsProvider =
    FutureProvider<TransferFormPrintSettings>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'transfer_form_print_settings'},
    );
    return TransferFormPrintSettings.fromJson(row);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return TransferFormPrintSettings.defaults;
  final row = await client
      .from('transfer_form_settings')
      .select()
      .eq('id', 'default')
      .maybeSingle();
  if (row == null) return TransferFormPrintSettings.defaults;
  return TransferFormPrintSettings.fromJson(row);
});

class WorkOrderType {
  final String id;
  final String name;
  final String? description;
  final String color;
  final bool isActive;

  WorkOrderType({required this.id, required this.name, this.description, this.color = '#6366F1', this.isActive = true});

  factory WorkOrderType.fromJson(Map<String, dynamic> json) => WorkOrderType(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString(),
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

  TaxRate({required this.id, required this.name, required this.rate, this.isDefault = false, this.isActive = true});

  factory TaxRate.fromJson(Map<String, dynamic> json) => TaxRate(
        id: json['id'].toString(),
        name: json['name']?.toString() ?? '',
        rate: (json['rate'] as num?)?.toDouble() ?? 0,
        isDefault: json['is_default'] as bool? ?? false,
        isActive: json['is_active'] as bool? ?? true,
      );
}

class CityDefinition {
  const CityDefinition({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? code;
  final bool isActive;

  factory CityDefinition.fromJson(Map<String, dynamic> json) {
    return CityDefinition(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      code: json['code']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class FiscalSymbolDefinition {
  const FiscalSymbolDefinition({
    required this.id,
    required this.name,
    required this.code,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? code;
  final bool isActive;

  factory FiscalSymbolDefinition.fromJson(Map<String, dynamic> json) {
    return FiscalSymbolDefinition(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      code: json['code']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class BusinessActivityTypeDefinition {
  const BusinessActivityTypeDefinition({
    required this.id,
    required this.name,
    required this.isActive,
  });

  final String id;
  final String name;
  final bool isActive;

  factory BusinessActivityTypeDefinition.fromJson(Map<String, dynamic> json) {
    return BusinessActivityTypeDefinition(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class DefinitionsScreen extends ConsumerWidget {
  const DefinitionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    return DefaultTabController(
      length: 4,
      child: AppPageLayout(
        title: 'Tanımlamalar',
        subtitle: 'Sistem tanımları ve ayarları',
        body: Column(
          children: [
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  const TabBar(
                    isScrollable: true,
                    tabAlignment: TabAlignment.start,
                    labelPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    tabs: [
                      Tab(text: 'Markalar'),
                      Tab(text: 'Modeller'),
                      Tab(text: 'İş Emri Tipleri'),
                      Tab(text: 'KDV Oranları'),
                    ],
                  ),
                  const Divider(height: 1),
                  SizedBox(
                    height: 720,
                    child: TabBarView(
                      children: [
                        _BrandsTab(isAdmin: isAdmin),
                        _ModelsTab(isAdmin: isAdmin),
                        _WorkOrderTypesTab(isAdmin: isAdmin),
                        _TaxRatesTab(isAdmin: isAdmin),
                      ],
                    ),
                  ),
                ],
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Cihaz Markaları', style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCreateBrandDialog(context, ref);
                        ref.invalidate(deviceBrandsProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: brandsAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) => _BrandRow(
                    brand: items[index],
                    isAdmin: isAdmin,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
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

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Cihaz Modelleri', style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        final brands = brandsAsync.value ?? const <DeviceBrand>[];
                        await _showCreateModelDialog(context, ref, brands: brands);
                        ref.invalidate(deviceModelsProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: modelsAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) => _ModelRow(
                    model: items[index],
                    isAdmin: isAdmin,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
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
            child: Text(
              b.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: b.isActive ? null : TextDecoration.lineThrough,
                  ),
            ),
          ),
          AppBadge(
            label: b.isActive ? 'Aktif' : 'Pasif',
            tone: b.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
          const Gap(10),
          if (widget.isAdmin)
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(b.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
        ],
      ),
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
                  m.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: m.isActive ? null : TextDecoration.lineThrough,
                      ),
                ),
                const Gap(4),
                Text(
                  m.brandName ?? '—',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          AppBadge(
            label: m.isActive ? 'Aktif' : 'Pasif',
            tone: m.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
          const Gap(10),
          if (widget.isAdmin)
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(m.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
        ],
      ),
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
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
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
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
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
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
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
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('İş Emri Tipleri', style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCreateWorkOrderTypeDialog(context, ref);
                        ref.invalidate(workOrderTypesProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: typesAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) => _WorkOrderTypeRow(
                    type: items[index],
                    isAdmin: isAdmin,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: t.isActive ? null : TextDecoration.lineThrough,
                      ),
                ),
                if (t.description != null && t.description!.isNotEmpty) ...[
                  const Gap(2),
                  Text(
                    t.description!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
                  ),
                ],
              ],
            ),
          ),
          AppBadge(
            label: t.isActive ? 'Aktif' : 'Pasif',
            tone: t.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
          const Gap(10),
          if (widget.isAdmin)
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(t.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
        ],
      ),
    );
  }
}

class _TaxRatesTab extends ConsumerWidget {
  const _TaxRatesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ratesAsync = ref.watch(taxRatesProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text('KDV Oranları', style: Theme.of(context).textTheme.titleMedium),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCreateTaxRateDialog(context, ref);
                        ref.invalidate(taxRatesProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: ratesAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) => _TaxRateRow(
                    rate: items[index],
                    isAdmin: isAdmin,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
      ),
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
      await client.from('tax_rates').update({'is_default': false}).eq('is_default', true);
      // Set new default
      await client.from('tax_rates').update({'is_default': true}).eq('id', widget.rate.id);
      ref.invalidate(taxRatesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.rate;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: r.isDefault ? AppTheme.primary : AppTheme.border),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 32,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '%${r.rate.toStringAsFixed(0)}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AppTheme.primary,
                    ),
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Text(
              r.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: r.isActive ? null : TextDecoration.lineThrough,
                  ),
            ),
          ),
          if (r.isDefault) ...[
            AppBadge(label: 'Varsayılan', tone: AppBadgeTone.primary),
            const Gap(8),
          ],
          AppBadge(
            label: r.isActive ? 'Aktif' : 'Pasif',
            tone: r.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
          const Gap(10),
          if (widget.isAdmin) ...[
            if (!r.isDefault)
              OutlinedButton(
                onPressed: _saving ? null : _setDefault,
                child: _saving
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Varsayılan Yap'),
              ),
            const Gap(6),
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : Text(r.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showCreateWorkOrderTypeDialog(BuildContext context, WidgetRef ref) async {
  final nameController = TextEditingController();
  final descController = TextEditingController();
  String selectedColor = '#6366F1';
  bool saving = false;

  final colors = ['#6366F1', '#22C55E', '#F59E0B', '#EF4444', '#3B82F6', '#8B5CF6', '#EC4899', '#14B8A6'];

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
                    Expanded(child: Text('İş Emri Tipi Ekle', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Tip Adı', hintText: 'Örn: Bakım'),
                ),
                const Gap(12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(labelText: 'Açıklama (opsiyonel)'),
                ),
                const Gap(12),
                Text('Renk Seçin', style: Theme.of(context).textTheme.bodySmall),
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
                          border: isSelected ? Border.all(color: Colors.black, width: 2) : null,
                        ),
                        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 18) : null,
                      ),
                    );
                  }).toList(),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
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
                                  await client.from('work_order_types').insert({
                                    'name': name,
                                    'description': descController.text.trim().isEmpty ? null : descController.text.trim(),
                                    'color': selectedColor,
                                    'is_active': true,
                                  });
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop();
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: saving
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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
}

Future<void> _showCreateTaxRateDialog(BuildContext context, WidgetRef ref) async {
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
                    Expanded(child: Text('KDV Oranı Ekle', style: Theme.of(context).textTheme.titleMedium)),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Oran Adı', hintText: 'Örn: Standart KDV'),
                ),
                const Gap(12),
                TextField(
                  controller: rateController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Oran (%)', hintText: 'Örn: 20'),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving ? null : () => Navigator.of(context).pop(),
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
                                final rate = double.tryParse(rateController.text.trim());
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
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
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

Color _parseColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

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

class DeviceBrand {
  const DeviceBrand({required this.id, required this.name, required this.isActive});

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
