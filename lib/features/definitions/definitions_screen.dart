import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

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

class WorkOrderType {
  final String id;
  final String name;
  final String? description;
  final String color;
  final bool isActive;

  WorkOrderType({
    required this.id,
    required this.name,
    this.description,
    this.color = '#6366F1',
    this.isActive = true,
  });

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
    return DefaultTabController(
      length: 5,
      child: AppPageLayout(
        title: 'Tanımlamalar',
        subtitle: 'Sistem tanımları ve ayarları',
        body: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _DefinitionStatCard(
                    label: 'Markalar',
                    value: brandsAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.copyright_rounded,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DefinitionStatCard(
                    label: 'Modeller',
                    value: modelsAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.memory_rounded,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DefinitionStatCard(
                    label: 'İş Emri Tipi',
                    value: typesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.widgets_outlined,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DefinitionStatCard(
                    label: 'KDV Oranı',
                    value: ratesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.percent_rounded,
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: _DefinitionStatCard(
                    label: 'Şehir',
                    value: citiesAsync.asData?.value.length.toString() ?? '—',
                    icon: Icons.location_city_rounded,
                  ),
                ),
              ],
            ),
            const Gap(16),
            AppCard(
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
                      Tab(text: 'Markalar'),
                      Tab(text: 'Modeller'),
                      Tab(text: 'İş Emri Tipleri'),
                      Tab(text: 'KDV Oranları'),
                      Tab(text: 'Şehirler'),
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
                        _CitiesTab(isAdmin: isAdmin),
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
                child: Text(
                  'Cihaz Markaları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) =>
                      _BrandRow(brand: items[index], isAdmin: isAdmin),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
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
                child: Text(
                  'Cihaz Modelleri',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        final brands =
                            brandsAsync.value ?? const <DeviceBrand>[];
                        await _showCreateModelDialog(
                          context,
                          ref,
                          brands: brands,
                        );
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
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) =>
                      _ModelRow(model: items[index], isAdmin: isAdmin),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
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
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'İş Emri Tipleri',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) =>
                      _WorkOrderTypeRow(type: items[index], isAdmin: isAdmin),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
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
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
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
          if (widget.isAdmin) ...[
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      await _showEditWorkOrderTypeDialog(context, ref, t);
                      ref.invalidate(workOrderTypesProvider);
                    },
              child: const Text('Düzenle'),
            ),
            const Gap(6),
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t.isActive ? 'Pasif Yap' : 'Aktif Yap'),
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
                child: Text(
                  'KDV Oranları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
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
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) =>
                      _TaxRateRow(rate: items[index], isAdmin: isAdmin),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
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
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Şehir Tanımları',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              FilledButton.icon(
                onPressed: isAdmin
                    ? () async {
                        await _showCityDialog(context, ref);
                        ref.invalidate(cityDefinitionsProvider);
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(12),
          Expanded(
            child: citiesAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Gap(10),
                  itemBuilder: (context, index) =>
                      _CityRow(city: items[index], isAdmin: isAdmin),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, stackTrace) => const _Empty(text: 'Yüklenemedi.'),
            ),
          ),
        ],
      ),
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
                  city.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: city.isActive
                        ? null
                        : TextDecoration.lineThrough,
                  ),
                ),
                if (city.code?.trim().isNotEmpty ?? false) ...[
                  const Gap(2),
                  Text(
                    city.code!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ],
              ],
            ),
          ),
          AppBadge(
            label: city.isActive ? 'Aktif' : 'Pasif',
            tone: city.isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
          ),
          const Gap(10),
          if (widget.isAdmin) ...[
            OutlinedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      await _showCityDialog(context, ref, city: city);
                      ref.invalidate(cityDefinitionsProvider);
                    },
              child: const Text('Düzenle'),
            ),
            const Gap(6),
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(city.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
          ],
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
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: r.isDefault ? AppTheme.primary : AppTheme.border,
        ),
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
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Varsayılan Yap'),
              ),
            const Gap(6),
            OutlinedButton(
              onPressed: _saving ? null : _toggleActive,
              child: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(r.isActive ? 'Pasif Yap' : 'Aktif Yap'),
            ),
          ],
        ],
      ),
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

Color _parseColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

class _DefinitionStatCard extends StatelessWidget {
  const _DefinitionStatCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppTheme.primary, size: 18),
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
