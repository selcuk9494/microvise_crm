import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final serviceRecordsProvider = FutureProvider<List<ServiceRecord>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'service_list'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ServiceRecord.fromJson)
      .toList(growable: false);
});

class ServiceScreen extends ConsumerStatefulWidget {
  const ServiceScreen({super.key});

  @override
  ConsumerState<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends ConsumerState<ServiceScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(serviceRecordsProvider);
    const allowedStatuses = {'all', 'open', 'in_progress', 'done'};
    if (!allowedStatuses.contains(_statusFilter)) _statusFilter = 'all';

    return AppPageLayout(
      title: 'Servis',
      subtitle: 'Adım adım süreç, parça + işçilik ayrımı.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(serviceRecordsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () async {
            await _showCreateServiceDialog(context, ref);
            ref.invalidate(serviceRecordsProvider);
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Servis'),
        ),
      ],
      body: recordsAsync.when(
        data: (items) {
          final search = _searchController.text.trim().toLowerCase();
          final filtered = items.where((item) {
            if (_statusFilter != 'all' && item.status != _statusFilter) {
              return false;
            }
            if (search.isEmpty) return true;
            final haystack = [
              item.title,
              item.customerName ?? '',
              item.id,
            ].join(' ').toLowerCase();
            return haystack.contains(search);
          }).toList(growable: false);

          return Column(
            children: [
              AppCard(
                padding: const EdgeInsets.all(12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;

                    final controls = Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 260,
                          child: TextField(
                            controller: _searchController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Ara',
                            ),
                          ),
                        ),
                        _StatusPill(
                          label: 'Durum: ${_statusLabel(_statusFilter)}',
                          backgroundColor:
                              const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF4C1D95),
                          icon: Icons.circle_rounded,
                          onTap: () async {
                            final next = await showModalBottomSheet<String>(
                              context: context,
                              showDragHandle: true,
                              builder: (context) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    _StatusSheetItem(
                                      value: 'all',
                                      label: 'Tümü',
                                    ),
                                    _StatusSheetItem(
                                      value: 'open',
                                      label: 'Açık',
                                    ),
                                    _StatusSheetItem(
                                      value: 'in_progress',
                                      label: 'Devam',
                                    ),
                                    _StatusSheetItem(
                                      value: 'done',
                                      label: 'Tamam',
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (next == null || next.trim().isEmpty) return;
                            setState(() => _statusFilter = next.trim());
                          },
                        ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _statusFilter = 'all');
                          },
                          icon:
                              const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Temizle'),
                          style: FilledButton.styleFrom(
                            backgroundColor:
                                const Color(0xFFEF4444).withValues(alpha: 0.12),
                            foregroundColor: const Color(0xFF7F1D1D),
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                          ),
                        ),
                      ],
                    );

                    final stats = AppBadge(
                      label: 'Toplam: ${filtered.length}',
                      tone: AppBadgeTone.primary,
                    );

                    if (wide) {
                      return Row(
                        children: [
                          Expanded(child: controls),
                          const Gap(12),
                          stats,
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        controls,
                        const Gap(10),
                        stats,
                      ],
                    );
                  },
                ),
              ),
              const Gap(12),
              Expanded(
                child: filtered.isEmpty
                    ? const AppCard(
                        child: Center(child: Text('Kayıt bulunamadı.')),
                      )
                    : LayoutBuilder(
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
                                  child: AppCard(
                                    child: const _ServiceTimelinePreview(),
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
              ),
            ],
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
              separatorBuilder: (_, _) => const Divider(height: 1),
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
        error: (error, _) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'Servis kayıtları yüklenemedi: $error',
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

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foregroundColor),
            const Gap(8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: foregroundColor, fontWeight: FontWeight.w700),
            ),
            const Gap(6),
            Icon(Icons.expand_more_rounded, size: 18, color: foregroundColor),
          ],
        ),
      ),
    );
  }
}

class _StatusSheetItem extends StatelessWidget {
  const _StatusSheetItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

String _statusLabel(String value) {
  switch (value) {
    case 'open':
      return 'Açık';
    case 'in_progress':
      return 'Devam';
    case 'done':
      return 'Tamam';
    default:
      return 'Tümü';
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
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => context.go('/servis/${item.id}'),
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
      ),
    );
  }
}

Future<void> _showCreateServiceDialog(BuildContext context, WidgetRef ref) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CreateServiceDialog(),
  );
}

class _CreateServiceDialog extends ConsumerStatefulWidget {
  const _CreateServiceDialog();

  @override
  ConsumerState<_CreateServiceDialog> createState() => _CreateServiceDialogState();
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
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'customers_lookup'},
      );
      final rows = (response['items'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _customers = rows
            .whereType<Map<String, dynamic>>()
            .where((e) => (e['is_active'] as bool?) ?? true)
            .map(_CustomerOption.fromJson)
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

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final customerId = _selectedCustomerId;
    if (customerId == null) return;

    setState(() => _saving = true);
    try {
      final title = _titleController.text.trim();
      final serial = _serialController.text.trim();

      String? deviceId;
      if (serial.isNotEmpty) {
        final existing = await apiClient.getJson(
          '/data',
          queryParameters: {'resource': 'customer_device_by_serial', 'serial': serial},
        );
        if (existing.isNotEmpty) {
          deviceId = existing['id']?.toString();
        } else {
          final inserted = await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'customer_devices',
              'returning': 'row',
              'values': {
                'customer_id': customerId,
                'serial_no': serial,
                'is_active': true,
              },
            },
          );
          deviceId = inserted['id']?.toString();
        }
      }

      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'service_records',
          'values': {
            'customer_id': customerId,
            'device_id': deviceId,
            'title': title.isEmpty ? 'Servis Kaydı' : title,
            'status': 'open',
            'steps': const [],
            'parts': const [],
            'labor': const [],
            'currency': 'TRY',
            'is_active': true,
          },
        },
      );
      ref.invalidate(serviceRecordsProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
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
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                        validator: (_) =>
                            (_selectedCustomerId ?? '').isEmpty ? 'Müşteri seçin.' : null,
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
                        onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
