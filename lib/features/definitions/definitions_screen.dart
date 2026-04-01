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

final workOrderCloseNotesProvider =
    FutureProvider<List<WorkOrderCloseNoteDefinition>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_work_order_close_notes'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WorkOrderCloseNoteDefinition.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('work_order_close_notes')
      .select('id,name,is_active,sort_order,created_at')
      .eq('is_active', true)
      .order('sort_order');
  return (rows as List)
      .map((e) => WorkOrderCloseNoteDefinition.fromJson(e as Map<String, dynamic>))
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

class WorkOrderCloseNoteDefinition {
  const WorkOrderCloseNoteDefinition({
    required this.id,
    required this.name,
    required this.isActive,
    required this.sortOrder,
  });

  final String id;
  final String name;
  final bool isActive;
  final int sortOrder;

  factory WorkOrderCloseNoteDefinition.fromJson(Map<String, dynamic> json) {
    return WorkOrderCloseNoteDefinition(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
    );
  }
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
      length: 6,
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
                      Tab(text: 'Kapanış Açıklaması'),
                      Tab(text: 'KDV Oranları'),
                      Tab(text: 'Faaliyet Türü'),
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
                        _WorkOrderCloseNotesTab(isAdmin: isAdmin),
                        _TaxRatesTab(isAdmin: isAdmin),
                        _BusinessActivityTypesTab(isAdmin: isAdmin),
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
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'device_brands',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.brand.id},
            ],
            'values': {'is_active': !widget.brand.isActive},
          },
        );
      } else {
        await client!
            .from('device_brands')
            .update({'is_active': !widget.brand.isActive})
            .eq('id', widget.brand.id);
      }
      ref.invalidate(deviceBrandsProvider);
      ref.invalidate(deviceModelsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    await _showCreateBrandDialog(context, ref, initial: widget.brand);
    ref.invalidate(deviceBrandsProvider);
    ref.invalidate(deviceModelsProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Markayı Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'device_brands',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.brand.id},
            ],
          },
        );
      } else {
        await client!.from('device_brands').delete().eq('id', widget.brand.id);
      }
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
          if (widget.isAdmin) ...[
            const Gap(8),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
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
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'device_models',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.model.id},
            ],
            'values': {'is_active': !widget.model.isActive},
          },
        );
      } else {
        await client!
            .from('device_models')
            .update({'is_active': !widget.model.isActive})
            .eq('id', widget.model.id);
      }
      ref.invalidate(deviceModelsProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    final brands = ref.read(deviceBrandsProvider).value ?? const <DeviceBrand>[];
    await _showCreateModelDialog(context, ref, brands: brands, initial: widget.model);
    ref.invalidate(deviceModelsProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Modeli Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'device_models',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.model.id},
            ],
          },
        );
      } else {
        await client!.from('device_models').delete().eq('id', widget.model.id);
      }
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
          if (widget.isAdmin) ...[
            const Gap(8),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showCreateBrandDialog(
  BuildContext context,
  WidgetRef ref, {
  DeviceBrand? initial,
}) async {
  final controller = TextEditingController(text: initial?.name ?? '');
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
                        initial == null ? 'Marka Ekle' : 'Marka Düzenle',
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
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;
                                setState(() => saving = true);
                                try {
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'device_brands',
                                          'rows': [
                                            {'name': name, 'is_active': true},
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'device_brands',
                                          'filters': [
                                            {
                                              'col': 'id',
                                              'op': 'eq',
                                              'value': initial.id,
                                            },
                                          ],
                                          'values': {'name': name},
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!.from('device_brands').insert({
                                        'name': name,
                                        'is_active': true,
                                      });
                                    } else {
                                      await client!
                                          .from('device_brands')
                                          .update({'name': name})
                                          .eq('id', initial.id);
                                    }
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

  controller.dispose();
}

Future<void> _showCreateModelDialog(
  BuildContext context,
  WidgetRef ref, {
  required List<DeviceBrand> brands,
  DeviceModel? initial,
}) async {
  final controller = TextEditingController(text: initial?.name ?? '');
  String? brandId = initial?.brandId ?? (brands.isEmpty ? null : brands.first.id);
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
                        initial == null ? 'Model Ekle' : 'Model Düzenle',
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
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;
                                setState(() => saving = true);
                                try {
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'device_models',
                                          'rows': [
                                            {
                                              'brand_id': selected,
                                              'name': name,
                                              'is_active': true,
                                            },
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'device_models',
                                          'filters': [
                                            {
                                              'col': 'id',
                                              'op': 'eq',
                                              'value': initial.id,
                                            },
                                          ],
                                          'values': {
                                            'brand_id': selected,
                                            'name': name,
                                          },
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!.from('device_models').insert({
                                        'brand_id': selected,
                                        'name': name,
                                        'is_active': true,
                                      });
                                    } else {
                                      await client!
                                          .from('device_models')
                                          .update({
                                            'brand_id': selected,
                                            'name': name,
                                          })
                                          .eq('id', initial.id);
                                    }
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

class _WorkOrderCloseNotesTab extends ConsumerWidget {
  const _WorkOrderCloseNotesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemsAsync = ref.watch(workOrderCloseNotesProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Kapanış Açıklamaları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCreateWorkOrderCloseNoteDialog(context, ref);
                        ref.invalidate(workOrderCloseNotesProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) => _WorkOrderCloseNoteRow(
                    item: items[index],
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

class _WorkOrderCloseNoteRow extends ConsumerStatefulWidget {
  const _WorkOrderCloseNoteRow({required this.item, required this.isAdmin});

  final WorkOrderCloseNoteDefinition item;
  final bool isAdmin;

  @override
  ConsumerState<_WorkOrderCloseNoteRow> createState() =>
      _WorkOrderCloseNoteRowState();
}

class _WorkOrderCloseNoteRowState extends ConsumerState<_WorkOrderCloseNoteRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'work_order_close_notes',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.item.id},
            ],
            'values': {'is_active': !widget.item.isActive},
          },
        );
      } else {
        await client!
            .from('work_order_close_notes')
            .update({'is_active': !widget.item.isActive})
            .eq('id', widget.item.id);
      }
      ref.invalidate(workOrderCloseNotesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    await _showCreateWorkOrderCloseNoteDialog(
      context,
      ref,
      initial: widget.item,
    );
    ref.invalidate(workOrderCloseNotesProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kayıt Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'work_order_close_notes',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.item.id},
            ],
          },
        );
      } else {
        await client!
            .from('work_order_close_notes')
            .delete()
            .eq('id', widget.item.id);
      }
      ref.invalidate(workOrderCloseNotesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
              item.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
          if (widget.isAdmin) ...[
            IconButton(
              tooltip: item.isActive ? 'Pasife Al' : 'Aktifleştir',
              onPressed: _saving ? null : _toggleActive,
              icon: Icon(
                item.isActive
                    ? Icons.pause_circle_outline_rounded
                    : Icons.play_circle_outline_rounded,
              ),
            ),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showCreateWorkOrderCloseNoteDialog(
  BuildContext context,
  WidgetRef ref, {
  WorkOrderCloseNoteDefinition? initial,
}) async {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final sortController =
      TextEditingController(text: initial == null ? '' : initial.sortOrder.toString());
  bool saving = false;

  final ok = await showDialog<bool>(
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
                        initial == null ? 'Kayıt Ekle' : 'Kayıt Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed:
                          saving ? null : () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    hintText: 'Örn: Kurulum tamamlandı',
                  ),
                ),
                const Gap(12),
                TextField(
                  controller: sortController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Sıra',
                    hintText: '0',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: FilledButton(
                        onPressed: saving
                            ? null
                            : () async {
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;

                                final name = nameController.text.trim();
                                if (name.isEmpty) return;
                                final sortOrder =
                                    int.tryParse(sortController.text.trim()) ?? 0;

                                setState(() => saving = true);
                                try {
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'work_order_close_notes',
                                          'rows': [
                                            {
                                              'name': name,
                                              'sort_order': sortOrder,
                                              'is_active': true,
                                            },
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'work_order_close_notes',
                                          'filters': [
                                            {'col': 'id', 'op': 'eq', 'value': initial.id},
                                          ],
                                          'values': {
                                            'name': name,
                                            'sort_order': sortOrder,
                                          },
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!.from('work_order_close_notes').insert({
                                        'name': name,
                                        'sort_order': sortOrder,
                                        'is_active': true,
                                      });
                                    } else {
                                      await client!.from('work_order_close_notes').update({
                                        'name': name,
                                        'sort_order': sortOrder,
                                      }).eq('id', initial.id);
                                    }
                                  }
                                  if (!context.mounted) return;
                                  Navigator.of(context).pop(true);
                                } finally {
                                  setState(() => saving = false);
                                }
                              },
                        child: Text(initial == null ? 'Ekle' : 'Kaydet'),
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
  sortController.dispose();

  if (ok == true) {
    ref.invalidate(workOrderCloseNotesProvider);
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
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'work_order_types',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.type.id},
            ],
            'values': {'is_active': !widget.type.isActive},
          },
        );
      } else {
        await client!
            .from('work_order_types')
            .update({'is_active': !widget.type.isActive})
            .eq('id', widget.type.id);
      }
      ref.invalidate(workOrderTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    await _showCreateWorkOrderTypeDialog(context, ref, initial: widget.type);
    ref.invalidate(workOrderTypesProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('İş Emri Tipini Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'work_order_types',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.type.id},
            ],
          },
        );
      } else {
        await client!
            .from('work_order_types')
            .delete()
            .eq('id', widget.type.id);
      }
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
          if (widget.isAdmin) ...[
            const Gap(8),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
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
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'tax_rates',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.rate.id},
            ],
            'values': {'is_active': !widget.rate.isActive},
          },
        );
      } else {
        await client!
            .from('tax_rates')
            .update({'is_active': !widget.rate.isActive})
            .eq('id', widget.rate.id);
      }
      ref.invalidate(taxRatesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setDefault() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      // Clear existing defaults
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'tax_rates',
            'filters': [
              {'col': 'is_default', 'op': 'eq', 'value': true},
            ],
            'values': {'is_default': false},
          },
        );
      } else {
        await client!
            .from('tax_rates')
            .update({'is_default': false})
            .eq('is_default', true);
      }
      // Set new default
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'tax_rates',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.rate.id},
            ],
            'values': {'is_default': true},
          },
        );
      } else {
        await client!
            .from('tax_rates')
            .update({'is_default': true})
            .eq('id', widget.rate.id);
      }
      ref.invalidate(taxRatesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    await _showCreateTaxRateDialog(context, ref, initial: widget.rate);
    ref.invalidate(taxRatesProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('KDV Oranını Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'tax_rates',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.rate.id},
            ],
          },
        );
      } else {
        await client!.from('tax_rates').delete().eq('id', widget.rate.id);
      }
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
            const Gap(6),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

class _BusinessActivityTypesTab extends ConsumerWidget {
  const _BusinessActivityTypesTab({required this.isAdmin});

  final bool isAdmin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(businessActivityTypesProvider);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Faaliyet Türleri',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCreateBusinessActivityTypeDialog(
                          context,
                          ref,
                        );
                        ref.invalidate(businessActivityTypesProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: activitiesAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) => _BusinessActivityTypeRow(
                    item: items[index],
                    isAdmin: isAdmin,
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => _Empty(text: 'Yüklenemedi: $error'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BusinessActivityTypeRow extends ConsumerStatefulWidget {
  const _BusinessActivityTypeRow({required this.item, required this.isAdmin});

  final BusinessActivityTypeDefinition item;
  final bool isAdmin;

  @override
  ConsumerState<_BusinessActivityTypeRow> createState() =>
      _BusinessActivityTypeRowState();
}

class _BusinessActivityTypeRowState
    extends ConsumerState<_BusinessActivityTypeRow> {
  bool _saving = false;

  Future<void> _toggleActive() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'business_activity_types',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.item.id},
            ],
            'values': {'is_active': !widget.item.isActive},
          },
        );
      } else {
        await client!
            .from('business_activity_types')
            .update({'is_active': !widget.item.isActive})
            .eq('id', widget.item.id);
      }
      ref.invalidate(businessActivityTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit() async {
    await _showCreateBusinessActivityTypeDialog(
      context,
      ref,
      initial: widget.item,
    );
    ref.invalidate(businessActivityTypesProvider);
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Faaliyet Türünü Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
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
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'deleteWhere',
            'table': 'business_activity_types',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.item.id},
            ],
          },
        );
      } else {
        await client!
            .from('business_activity_types')
            .delete()
            .eq('id', widget.item.id);
      }
      ref.invalidate(businessActivityTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
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
              item.name,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration:
                        item.isActive ? null : TextDecoration.lineThrough,
                  ),
            ),
          ),
          AppBadge(
            label: item.isActive ? 'Aktif' : 'Pasif',
            tone: item.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
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
                  : Text(item.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
          if (widget.isAdmin) ...[
            const Gap(8),
            IconButton(
              tooltip: 'Düzenle',
              onPressed: _saving ? null : _edit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Sil',
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
            ),
          ],
        ],
      ),
    );
  }
}

Future<void> _showCreateBusinessActivityTypeDialog(
  BuildContext context,
  WidgetRef ref, {
  BusinessActivityTypeDefinition? initial,
}) async {
  final controller = TextEditingController(text: initial?.name ?? '');
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
                        initial == null
                            ? 'Faaliyet Türü Ekle'
                            : 'Faaliyet Türü Düzenle',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed:
                          saving ? null : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextField(
                  controller: controller,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Ad',
                    hintText: 'Örn: Perakende',
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
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;
                                setState(() => saving = true);
                                try {
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'business_activity_types',
                                          'rows': [
                                            {'name': name, 'is_active': true},
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'business_activity_types',
                                          'filters': [
                                            {
                                              'col': 'id',
                                              'op': 'eq',
                                              'value': initial.id,
                                            },
                                          ],
                                          'values': {'name': name},
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!
                                          .from('business_activity_types')
                                          .insert({
                                        'name': name,
                                        'is_active': true,
                                      });
                                    } else {
                                      await client!
                                          .from('business_activity_types')
                                          .update({'name': name}).eq(
                                        'id',
                                        initial.id,
                                      );
                                    }
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
                            : Text(initial == null ? 'Ekle' : 'Kaydet'),
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

Future<void> _showCreateWorkOrderTypeDialog(
  BuildContext context,
  WidgetRef ref, {
  WorkOrderType? initial,
}) async {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final descController =
      TextEditingController(text: initial?.description ?? '');
  String selectedColor = initial?.color ?? '#6366F1';
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
                    Expanded(
                      child: Text(
                        initial == null
                            ? 'İş Emri Tipi Ekle'
                            : 'İş Emri Tipi Düzenle',
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
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;
                                setState(() => saving = true);
                                try {
                                  final description =
                                      descController.text.trim().isEmpty
                                          ? null
                                          : descController.text.trim();
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'work_order_types',
                                          'rows': [
                                            {
                                              'name': name,
                                              'description': description,
                                              'color': selectedColor,
                                              'is_active': true,
                                            },
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'work_order_types',
                                          'filters': [
                                            {
                                              'col': 'id',
                                              'op': 'eq',
                                              'value': initial.id,
                                            },
                                          ],
                                          'values': {
                                            'name': name,
                                            'description': description,
                                            'color': selectedColor,
                                          },
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!
                                          .from('work_order_types')
                                          .insert({
                                        'name': name,
                                        'description': description,
                                        'color': selectedColor,
                                        'is_active': true,
                                      });
                                    } else {
                                      await client!
                                          .from('work_order_types')
                                          .update({
                                        'name': name,
                                        'description': description,
                                        'color': selectedColor,
                                      }).eq('id', initial.id);
                                    }
                                  }
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

Future<void> _showCreateTaxRateDialog(
  BuildContext context,
  WidgetRef ref, {
  TaxRate? initial,
}) async {
  final nameController = TextEditingController(text: initial?.name ?? '');
  final rateController = TextEditingController(
    text: initial == null ? '' : initial.rate.toStringAsFixed(0),
  );
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
                        initial == null ? 'KDV Oranı Ekle' : 'KDV Oranı Düzenle',
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
                                final apiClient = ref.read(apiClientProvider);
                                final client = ref.read(supabaseClientProvider);
                                if (apiClient == null && client == null) return;
                                setState(() => saving = true);
                                try {
                                  if (apiClient != null) {
                                    if (initial == null) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'insertMany',
                                          'table': 'tax_rates',
                                          'rows': [
                                            {
                                              'name': name,
                                              'rate': rate,
                                              'is_active': true,
                                              'is_default': false,
                                            },
                                          ],
                                        },
                                      );
                                    } else {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'updateWhere',
                                          'table': 'tax_rates',
                                          'filters': [
                                            {
                                              'col': 'id',
                                              'op': 'eq',
                                              'value': initial.id,
                                            },
                                          ],
                                          'values': {
                                            'name': name,
                                            'rate': rate,
                                          },
                                        },
                                      );
                                    }
                                  } else {
                                    if (initial == null) {
                                      await client!.from('tax_rates').insert({
                                        'name': name,
                                        'rate': rate,
                                        'is_active': true,
                                        'is_default': false,
                                      });
                                    } else {
                                      await client!.from('tax_rates').update({
                                        'name': name,
                                        'rate': rate,
                                      }).eq('id', initial.id);
                                    }
                                  }
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
