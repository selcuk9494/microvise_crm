import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/ui/smart_filter_bar.dart';

final serviceFiltersProvider =
    NotifierProvider<ServiceFiltersNotifier, ServiceFilters>(
      ServiceFiltersNotifier.new,
    );

class ServiceFiltersNotifier extends Notifier<ServiceFilters> {
  @override
  ServiceFilters build() => const ServiceFilters(search: '', status: 'all');

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void setStatus(String value) {
    state = state.copyWith(status: value);
  }
}

class ServiceFilters {
  const ServiceFilters({required this.search, required this.status});

  final String search;
  final String status;

  ServiceFilters copyWith({String? search, String? status}) {
    return ServiceFilters(
      search: search ?? this.search,
      status: status ?? this.status,
    );
  }
}

final serviceRecordsProvider = FutureProvider<List<ServiceRecord>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('service_records')
      .select('id,title,status,created_at,customers(name)')
      .eq('is_active', true)
      .order('created_at', ascending: false)
      .limit(100);

  return (rows as List)
      .map((e) {
        final map = e as Map<String, dynamic>;
        final customers = map['customers'] as Map<String, dynamic>?;
        return ServiceRecord.fromJson({
          ...map,
          'customer_name': customers?['name'],
        });
      })
      .toList(growable: false);
});

class ServiceScreen extends ConsumerWidget {
  const ServiceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recordsAsync = ref.watch(serviceRecordsProvider);
    final filters = ref.watch(serviceFiltersProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;

    return AppPageLayout(
      title: 'Servis',
      subtitle: 'Servis kayıtları, süreç ve durum takibi.',
      actions: [
        FilledButton.icon(
          onPressed: () async {
            final serviceId = await _showCreateServiceDialog(context, ref);
            ref.invalidate(serviceRecordsProvider);
            if (serviceId != null && context.mounted) {
              context.go('/servis/$serviceId');
            }
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Servis'),
        ),
      ],
      body: recordsAsync.when(
        data: (items) {
          final filtered = items
              .where((item) {
                final search = filters.search.trim().toLowerCase();
                final matchesSearch =
                    search.isEmpty ||
                    item.title.toLowerCase().contains(search) ||
                    (item.customerName ?? '').toLowerCase().contains(search);
                final matchesStatus =
                    filters.status == 'all' || item.status == filters.status;
                return matchesSearch && matchesStatus;
              })
              .toList(growable: false);

          if (items.isEmpty) {
            return const EmptyStateCard(
              icon: Icons.build_circle_outlined,
              title: 'Henüz servis kaydı yok',
              message: 'Yeni servis kaydı oluşturarak süreci başlatın.',
            );
          }

          return Column(
            children: [
              _ServiceSummary(items: items),
              const Gap(8),
              SmartFilterBar(
                title: 'Filtreler',
                subtitle: null,
                footer: filters.search.isNotEmpty || filters.status != 'all'
                    ? Align(
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
                            if (filters.status != 'all')
                              AppBadge(
                                label: 'Durum: ${_statusText(filters.status)}',
                                tone: AppBadgeTone.neutral,
                              ),
                            TextButton.icon(
                              onPressed: () {
                                ref
                                    .read(serviceFiltersProvider.notifier)
                                    .setSearch('');
                                ref
                                    .read(serviceFiltersProvider.notifier)
                                    .setStatus('all');
                              },
                              icon: const Icon(Icons.clear_rounded, size: 16),
                              label: const Text('Temizle'),
                            ),
                          ],
                        ),
                      )
                    : null,
                children: [
                  SizedBox(
                    width: isMobile ? double.infinity : width * 0.38,
                    child: TextField(
                      onChanged: ref
                          .read(serviceFiltersProvider.notifier)
                          .setSearch,
                      decoration: const InputDecoration(
                        labelText: 'Servis Ara',
                        hintText: 'Başlık veya müşteri adı',
                        prefixIcon: Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: isMobile ? double.infinity : 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: filters.status,
                      items: const [
                        DropdownMenuItem(
                          value: 'all',
                          child: Text('Tüm Durumlar'),
                        ),
                        DropdownMenuItem(value: 'open', child: Text('Açık')),
                        DropdownMenuItem(
                          value: 'in_progress',
                          child: Text('Devam'),
                        ),
                        DropdownMenuItem(value: 'done', child: Text('Tamam')),
                      ],
                      onChanged: (value) => ref
                          .read(serviceFiltersProvider.notifier)
                          .setStatus(value ?? 'all'),
                      decoration: const InputDecoration(
                        labelText: 'Durum',
                        prefixIcon: Icon(Icons.tune_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              if (isMobile)
                Expanded(
                  child: filtered.isEmpty
                      ? const EmptyStateCard(
                          icon: Icons.search_off_rounded,
                          title: 'Kayıt bulunamadı',
                          message:
                              'Filtrelere uygun servis kaydı bulunamadı.',
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (context, index) => const Gap(10),
                          itemBuilder: (context, index) =>
                              _MobileServiceCard(item: filtered[index]),
                        ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCols = constraints.maxWidth >= 980;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: twoCols ? 2 : 1,
                          child: AppCard(
                            padding: EdgeInsets.zero,
                            child: filtered.isEmpty
                                ? const Padding(
                                    padding: EdgeInsets.all(10),
                                    child: EmptyStateCard(
                                      icon: Icons.search_off_rounded,
                                      title: 'Kayıt bulunamadı',
                                      message:
                                          'Filtrelere uygun servis kaydı bulunamadı.',
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: filtered.length,
                                    separatorBuilder: (context, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, index) =>
                                        _ServiceRow(item: filtered[index]),
                                  ),
                          ),
                        ),
                        if (twoCols) const Gap(16),
                        if (twoCols)
                          Expanded(
                            flex: 3,
                            child: AppSectionCard(
                              title: 'Süreç özeti',
                              subtitle: 'Seçili kayıtların son durum akışı',
                              child: _ServiceTimelinePreview(items: filtered),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          );
        },
        loading: () => Skeletonizer(
          enabled: true,
          child: Column(
            children: [
              const _ServiceSummary(
                items: [
                  ServiceRecord(
                    id: '1',
                    title: 'Yerinde servis ziyareti',
                    customerName: 'ACME Teknoloji',
                    status: 'in_progress',
                    createdAt: null,
                  ),
                  ServiceRecord(
                    id: '2',
                    title: 'Bakım kaydı',
                    customerName: 'Nova Yazılım',
                    status: 'open',
                    createdAt: null,
                  ),
                ],
              ),
              const Gap(10),
              AppCard(
                padding: EdgeInsets.zero,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: 8,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) => _ServiceRow(
                    item: ServiceRecord(
                      id: '$index',
                      title: 'Yerinde servis ziyareti',
                      customerName: 'ACME Teknoloji',
                      status: 'in_progress',
                      createdAt: null,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        error: (error, stackTrace) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'Servis kayıtları yüklenemedi.',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileServiceCard extends StatelessWidget {
  const _MobileServiceCard({required this.item});

  final ServiceRecord item;

  @override
  Widget build(BuildContext context) {
    final status = switch (item.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Sahada', AppBadgeTone.primary),
      'done' => ('Tamam', AppBadgeTone.success),
      _ => ('—', AppBadgeTone.neutral),
    };
    final date = item.createdAt == null
        ? 'Plan yok'
        : DateFormat('d MMM y', 'tr_TR').format(item.createdAt!);

    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => context.go('/servis/${item.id}'),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Gap(4),
                      Text(
                        item.customerName ?? 'Müşteri belirtilmedi',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
                AppBadge(label: status.$1, tone: status.$2),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _ServiceInfoChip(
                  icon: Icons.calendar_today_rounded,
                  label: date,
                ),
                _ServiceInfoChip(
                  icon: Icons.build_circle_outlined,
                  label: item.status == 'done' ? 'Kapanış hazır' : 'İş aktif',
                ),
              ],
            ),
            const Gap(10),
            Row(
              children: [
                Text(
                  'Detayları aç',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF94A3B8),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ServiceInfoChip extends StatelessWidget {
  const _ServiceInfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: const Color(0xFF64748B)),
          const Gap(5),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF475569),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceSummary extends StatelessWidget {
  const _ServiceSummary({required this.items});

  final List<ServiceRecord> items;

  @override
  Widget build(BuildContext context) {
    final open = items.where((item) => item.status == 'open').length;
    final inProgress = items
        .where((item) => item.status == 'in_progress')
        .length;
    final done = items.where((item) => item.status == 'done').length;

    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _ServiceSummaryPill(
            label: 'Toplam',
            value: items.length.toString(),
            icon: Icons.build_circle_outlined,
            color: AppTheme.primary,
          ),
          _ServiceSummaryPill(
            label: 'Açık',
            value: open.toString(),
            icon: Icons.radio_button_unchecked_rounded,
            color: AppTheme.warning,
          ),
          _ServiceSummaryPill(
            label: 'Devam',
            value: inProgress.toString(),
            icon: Icons.timelapse_rounded,
            color: AppTheme.primary,
          ),
          _ServiceSummaryPill(
            label: 'Tamam',
            value: done.toString(),
            icon: Icons.check_circle_outline_rounded,
            color: AppTheme.success,
          ),
        ],
      ),
    );
  }
}

class _ServiceSummaryPill extends StatelessWidget {
  const _ServiceSummaryPill({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 15, color: color),
          ),
          const Gap(8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

String _statusText(String status) {
  return switch (status) {
    'open' => 'Açık',
    'in_progress' => 'Devam',
    'done' => 'Tamam',
    _ => 'Tümü',
  };
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({required this.item});

  final ServiceRecord item;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final status = switch (item.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Devam', AppBadgeTone.primary),
      'done' => ('Tamam', AppBadgeTone.success),
      _ => ('—', AppBadgeTone.neutral),
    };
    final date = item.createdAt == null
        ? '—'
        : DateFormat('d MMM', 'tr_TR').format(item.createdAt!);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/servis/${item.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Gap(6),
              AppBadge(label: status.$1, tone: status.$2),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const Gap(10),
                  AppBadge(label: status.$1, tone: status.$2),
                ],
              ),
            const Gap(2),
            if (isMobile) ...[
              Text(
                item.customerName ?? '—',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
              const Gap(2),
              Text(
                date,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF94A3B8)),
              ),
            ] else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      item.customerName ?? '—',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  Text(
                    date,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

Future<String?> _showCreateServiceDialog(
  BuildContext context,
  WidgetRef ref,
) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return null;

  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CreateServiceDialog(),
  );
}

class _CreateServiceDialog extends ConsumerStatefulWidget {
  const _CreateServiceDialog();

  @override
  ConsumerState<_CreateServiceDialog> createState() =>
      _CreateServiceDialogState();
}

class _CreateServiceDialogState extends ConsumerState<_CreateServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _titleController = TextEditingController(text: 'Servis Kaydı');
  final _serialController = TextEditingController();
  bool _saving = false;

  List<_CustomerOption> _customers = const [];
  String? _selectedCustomerId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadCustomers());
  }

  Future<void> _loadCustomers() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final rows = await client
          .from('customers')
          .select('id,name,is_active')
          .eq('is_active', true)
          .order('name')
          .limit(200);
      if (!mounted) return;
      setState(() {
        _customers = (rows as List)
            .map((e) => _CustomerOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _customers = const []);
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _titleController.dispose();
    _serialController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final customerId = _selectedCustomerId;
    if (customerId == null) return;

    setState(() => _saving = true);
    try {
      final title = _titleController.text.trim();
      final serial = _serialController.text.trim();

      String? deviceId;
      if (serial.isNotEmpty) {
        final existing = await client
            .from('customer_devices')
            .select('id')
            .eq('serial_no', serial)
            .maybeSingle();
        if (existing != null) {
          deviceId = existing['id'].toString();
        } else {
          final inserted = await client
              .from('customer_devices')
              .insert({
                'customer_id': customerId,
                'serial_no': serial,
                'is_active': true,
              })
              .select('id')
              .single();
          deviceId = inserted['id'].toString();
        }
      }

      final inserted = await client
          .from('service_records')
          .insert({
            'customer_id': customerId,
            'device_id': deviceId,
            'title': title.isEmpty ? 'Servis Kaydı' : title,
            'status': 'open',
            'steps': const [],
            'parts': const [],
            'labor': const [],
            'currency': 'TRY',
            'is_active': true,
            'created_by': client.auth.currentUser?.id,
          })
          .select('id')
          .single();

      if (!mounted) return;
      Navigator.of(context).pop(inserted['id'].toString());
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis kaydı oluşturuldu.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis kaydı oluşturulamadı.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loading = _customers.isEmpty;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Yeni Servis',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                if (loading)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: const Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        Gap(10),
                        Expanded(child: Text('Müşteriler yükleniyor…')),
                      ],
                    ),
                  )
                else
                  Autocomplete<_CustomerOption>(
                    optionsBuilder: (text) {
                      final q = text.text.trim().toLowerCase();
                      if (q.isEmpty) return _customers.take(20);
                      return _customers
                          .where((c) => c.name.toLowerCase().contains(q))
                          .take(20);
                    },
                    displayStringForOption: (o) => o.name,
                    onSelected: (o) {
                      _selectedCustomerId = o.id;
                      _customerController.text = o.name;
                    },
                    fieldViewBuilder: (context, controller, focusNode, _) {
                      controller.text = _customerController.text;
                      controller.selection = TextSelection.collapsed(
                        offset: controller.text.length,
                      );
                      return TextFormField(
                        controller: controller,
                        focusNode: focusNode,
                        decoration: const InputDecoration(
                          labelText: 'Müşteri',
                          hintText: 'Firma adı yazın ve seçin',
                        ),
                        validator: (_) => (_selectedCustomerId ?? '').isEmpty
                            ? 'Müşteri seçin.'
                            : null,
                        onChanged: (_) => _selectedCustomerId = null,
                      );
                    },
                  ),
                const Gap(12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Örn: Arızalı cihaz servisi',
                  ),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Başlık gerekli.' : null,
                ),
                const Gap(12),
                TextFormField(
                  controller: _serialController,
                  decoration: const InputDecoration(
                    labelText: 'Cihaz Sicil No (opsiyonel)',
                    hintText: 'SN...',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Oluştur'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CustomerOption {
  const _CustomerOption({required this.id, required this.name});

  final String id;
  final String name;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class _ServiceTimelinePreview extends StatelessWidget {
  const _ServiceTimelinePreview({required this.items});

  final List<ServiceRecord> items;

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
          items.isEmpty
              ? 'Servis kaydı kapanış akışı; ödeme + imza ekranı bu akışa bağlanır.'
              : 'Seçili görünümde ${items.length} servis kaydı var. Son durumları bu akış üzerinden takip edebilirsiniz.',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
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
                    border: Border.all(
                      color: AppTheme.primary.withValues(alpha: 0.18),
                    ),
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
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                        ),
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
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
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
  final DateTime? createdAt;

  factory ServiceRecord.fromJson(Map<String, dynamic> json) {
    return ServiceRecord(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerName: json['customer_name']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      createdAt:
          DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}
