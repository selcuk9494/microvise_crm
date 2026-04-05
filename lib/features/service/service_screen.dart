import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/search_normalize.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'service_definitions.dart';
import 'service_detail_screen.dart';
import 'service_share.dart';
import 'service_technicians.dart';

class ServiceListQuery {
  const ServiceListQuery({
    this.search = '',
    this.status = 'all',
    this.priority = 'all',
    this.technicianId = 'all',
    this.range,
    this.page = 1,
    this.pageSize = 50,
  });

  final String search;
  final String status;
  final String priority;
  final String technicianId;
  final DateTimeRange? range;
  final int page;
  final int pageSize;

  ServiceListQuery copyWith({
    String? search,
    String? status,
    String? priority,
    String? technicianId,
    DateTimeRange? range,
    bool clearRange = false,
    int? page,
    int? pageSize,
  }) {
    return ServiceListQuery(
      search: search ?? this.search,
      status: status ?? this.status,
      priority: priority ?? this.priority,
      technicianId: technicianId ?? this.technicianId,
      range: clearRange ? null : (range ?? this.range),
      page: page ?? this.page,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  Map<String, String> toQueryParams() {
    final start = range?.start.toUtc().toIso8601String();
    final end = range?.end.toUtc().toIso8601String();
    return {
      'resource': 'service_list',
      'page': page.toString(),
      'pageSize': pageSize.toString(),
      if (search.trim().isNotEmpty) 'search': search.trim(),
      if (status.trim().isNotEmpty) 'status': status.trim(),
      if (priority.trim().isNotEmpty) 'priority': priority.trim(),
      if (technicianId.trim().isNotEmpty) 'technicianId': technicianId.trim(),
      ...?(start == null ? null : {'startDate': start}),
      ...?(end == null ? null : {'endDate': end}),
    };
  }
}

class ServicePageData {
  const ServicePageData({
    required this.items,
    required this.totalCount,
    required this.page,
    required this.pageSize,
  });

  final List<ServiceRecord> items;
  final int totalCount;
  final int page;
  final int pageSize;

  int get totalPages => totalCount <= 0 ? 1 : ((totalCount - 1) ~/ pageSize) + 1;
  bool get hasPrev => page > 1;
  bool get hasNext => page < totalPages;
}

final serviceRecordsProvider =
    FutureProvider.autoDispose.family<ServicePageData, ServiceListQuery>((ref, query) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) {
    return const ServicePageData(items: [], totalCount: 0, page: 1, pageSize: 50);
  }
  final response = await apiClient.getJson(
    '/data',
    queryParameters: query.toQueryParams(),
  );
  final items = ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ServiceRecord.fromJson)
      .toList(growable: false);
  int? toIntAny(Object? v) {
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v?.toString() ?? '');
  }

  final totalCount = toIntAny(response['totalCount']) ?? items.length;
  final page = toIntAny(response['page']) ?? query.page;
  final pageSize = toIntAny(response['pageSize']) ?? query.pageSize;
  return ServicePageData(items: items, totalCount: totalCount, page: page, pageSize: pageSize);
});

class ServiceScreen extends ConsumerStatefulWidget {
  const ServiceScreen({super.key});

  @override
  ConsumerState<ServiceScreen> createState() => _ServiceScreenState();
}

class _ServiceScreenState extends ConsumerState<ServiceScreen> {
  final _searchController = TextEditingController();
  ServiceListQuery _query = const ServiceListQuery();
  String? _selectedServiceId;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(serviceRecordsProvider(_query));
    const allowedStatuses = {'all', 'waiting', 'approval', 'ready', 'done', 'cancelled'};
    if (!allowedStatuses.contains(_query.status)) {
      _query = _query.copyWith(status: 'all');
    }

    return AppPageLayout(
      title: 'Servis',
      subtitle: 'Adım adım süreç, parça + işçilik ayrımı.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(serviceRecordsProvider(_query)),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () async {
            await _showCreateServiceDialog(context, ref);
            ref.invalidate(serviceRecordsProvider(_query));
          },
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Servis'),
        ),
      ],
      body: recordsAsync.when(
        data: (pageData) {
          final items = pageData.items;

          final isWebWide = kIsWeb && MediaQuery.sizeOf(context).width >= 1200;
          String mapStatus(String v) => switch (v) {
                'open' => 'waiting',
                'in_progress' => 'approval',
                _ => v,
              };
          final waitingCount =
              items.where((e) => mapStatus(e.status) == 'waiting').length;
          final approvalCount =
              items.where((e) => mapStatus(e.status) == 'approval').length;
          final readyCount = items.where((e) => mapStatus(e.status) == 'ready').length;
          final doneCount = items.where((e) => mapStatus(e.status) == 'done').length;
          final cancelledCount =
              items.where((e) => mapStatus(e.status) == 'cancelled').length;

          if (isWebWide && _selectedServiceId == null && items.isNotEmpty) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (_selectedServiceId != null) return;
              setState(() => _selectedServiceId = items.first.id);
            });
          }

          return Column(
            children: [
              if (isWebWide) ...[
                Row(
                  children: [
                    Expanded(
                      child: _MetricCard(
                        title: 'Toplam Kayıt',
                        value: pageData.totalCount.toString(),
                        tone: AppBadgeTone.primary,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Bekliyor',
                        value: waitingCount.toString(),
                        tone: AppBadgeTone.warning,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Onayda',
                        value: approvalCount.toString(),
                        tone: AppBadgeTone.primary,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Hazır',
                        value: readyCount.toString(),
                        tone: AppBadgeTone.success,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _MetricCard(
                        title: 'Teslim',
                        value: doneCount.toString(),
                        tone: AppBadgeTone.neutral,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: _MetricCard(
                        title: 'İptal',
                        value: cancelledCount.toString(),
                        tone: AppBadgeTone.neutral,
                      ),
                    ),
                  ],
                ),
                const Gap(12),
              ],
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
                            onChanged: (v) => setState(() {
                              _query = _query.copyWith(search: v, page: 1);
                            }),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search_rounded),
                              hintText: 'Ara (servis no, müşteri, sicil, seri)',
                            ),
                          ),
                        ),
                        _StatusPill(
                          label: 'Durum: ${_statusLabel(_query.status)}',
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
                                      value: 'waiting',
                                      label: 'Beklemede',
                                    ),
                                    _StatusSheetItem(
                                      value: 'approval',
                                      label: 'Onayda',
                                    ),
                                    _StatusSheetItem(
                                      value: 'ready',
                                      label: 'Hazır',
                                    ),
                                    _StatusSheetItem(
                                      value: 'done',
                                      label: 'Tamamlandı',
                                    ),
                                    _StatusSheetItem(
                                      value: 'cancelled',
                                      label: 'İptal',
                                    ),
                                  ],
                                ),
                              ),
                            );
                            if (next == null || next.trim().isEmpty) return;
                            setState(() {
                              _query = _query.copyWith(status: next.trim(), page: 1);
                            });
                          },
                        ),
                        _StatusPill(
                          label: 'Öncelik: ${_priorityLabel(_query.priority)}',
                          backgroundColor:
                              const Color(0xFF0EA5E9).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF0C4A6E),
                          icon: Icons.flag_rounded,
                          onTap: () async {
                            final next = await showModalBottomSheet<String>(
                              context: context,
                              showDragHandle: true,
                              builder: (context) => SafeArea(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: const [
                                    _StatusSheetItem(value: 'all', label: 'Tümü'),
                                    _StatusSheetItem(value: 'low', label: 'Düşük'),
                                    _StatusSheetItem(value: 'medium', label: 'Orta'),
                                    _StatusSheetItem(value: 'high', label: 'Yüksek'),
                                  ],
                                ),
                              ),
                            );
                            if (next == null || next.trim().isEmpty) return;
                            setState(() {
                              _query = _query.copyWith(priority: next.trim(), page: 1);
                            });
                          },
                        ),
                        Consumer(
                          builder: (context, ref, _) {
                            final techAsync = ref.watch(serviceTechniciansProvider);
                            final selectedId = _query.technicianId;
                            final selected = techAsync.asData?.value.where((e) => e.id == selectedId);
                            final selectedName = selectedId == 'all'
                                ? 'Tümü'
                                : (selected == null || selected.isEmpty)
                                    ? 'Seç'
                                    : selected.first.fullName;
                            return _StatusPill(
                              label: 'Teknisyen: $selectedName',
                              backgroundColor:
                                  const Color(0xFF16A34A).withValues(alpha: 0.12),
                              foregroundColor: const Color(0xFF14532D),
                              icon: Icons.person_rounded,
                              onTap: () async {
                                final techs = techAsync.asData?.value ?? const <ServiceTechnician>[];
                                final next = await showModalBottomSheet<String>(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (context) => SafeArea(
                                    child: ListView(
                                      shrinkWrap: true,
                                      children: [
                                        const _StatusSheetItem(value: 'all', label: 'Tümü'),
                                        for (final t in techs)
                                          _StatusSheetItem(value: t.id, label: t.fullName),
                                      ],
                                    ),
                                  ),
                                );
                                if (next == null || next.trim().isEmpty) return;
                                setState(() {
                                  _query = _query.copyWith(technicianId: next.trim(), page: 1);
                                });
                              },
                            );
                          },
                        ),
                        _StatusPill(
                          label: _query.range == null
                              ? 'Tarih: Tümü'
                              : 'Tarih: ${DateFormat('d MMM', 'tr_TR').format(_query.range!.start)} - ${DateFormat('d MMM', 'tr_TR').format(_query.range!.end)}',
                          backgroundColor:
                              const Color(0xFFF59E0B).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF7C2D12),
                          icon: Icons.date_range_rounded,
                          onTap: () async {
                            final picked = await showDateRangePicker(
                              context: context,
                              firstDate: DateTime(2020, 1, 1),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              initialDateRange: _query.range,
                            );
                            if (picked == null) return;
                            setState(() {
                              _query = _query.copyWith(range: picked, page: 1);
                            });
                          },
                        ),
                        if (_query.range != null)
                          OutlinedButton(
                            onPressed: () => setState(() {
                              _query = _query.copyWith(clearRange: true, page: 1);
                            }),
                            child: const Text('Tarih Temizle'),
                          ),
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _searchController.clear();
                            setState(() {
                              _query = const ServiceListQuery();
                            });
                          },
                          icon:
                              const Icon(Icons.delete_outline_rounded, size: 18),
                          label: const Text('Sıfırla'),
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
                        IconButton(
                          tooltip: 'Önceki',
                          onPressed: pageData.hasPrev
                              ? () => setState(() {
                                    _query = _query.copyWith(page: pageData.page - 1);
                                  })
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Text(
                          '${pageData.page} / ${pageData.totalPages}',
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: const Color(0xFF64748B)),
                        ),
                        IconButton(
                          tooltip: 'Sonraki',
                          onPressed: pageData.hasNext
                              ? () => setState(() {
                                    _query = _query.copyWith(page: pageData.page + 1);
                                  })
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    );

                    final stats = AppBadge(
                      label: 'Toplam: ${pageData.totalCount}',
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
                child: items.isEmpty
                    ? const AppCard(
                        child: Center(child: Text('Kayıt bulunamadı.')),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) {
                          final showPanel = kIsWeb && constraints.maxWidth >= 1200;
                          if (!showPanel) {
                            return AppCard(
                              padding: EdgeInsets.zero,
                              child: ListView.separated(
                                itemCount: items.length,
                                separatorBuilder: (context, index) => const Divider(height: 1),
                                itemBuilder: (context, index) => _ServiceRow(item: items[index]),
                              ),
                            );
                          }

                          final selectedId = (_selectedServiceId ?? '').trim().isEmpty
                              ? items.first.id
                              : _selectedServiceId!;

                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 3,
                                child: AppCard(
                                  padding: EdgeInsets.zero,
                                  child: ListView.separated(
                                    itemCount: items.length + 1,
                                    separatorBuilder: (context, index) => const Divider(height: 1),
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        return const _ServiceTableHeader();
                                      }
                                      final item = items[index - 1];
                                      return _ServiceRow(
                                        item: item,
                                        selected: item.id == selectedId,
                                        onTap: () => setState(() => _selectedServiceId = item.id),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              const Gap(16),
                              Expanded(
                                flex: 2,
                                child: _ServiceDetailPanel(serviceId: selectedId),
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
                  serviceNo: 20240001 + index,
                  title: 'Yerinde servis ziyareti',
                  customerName: 'ACME Teknoloji',
                  status: 'in_progress',
                  priority: 'high',
                  createdAt: DateTime.now(),
                  appointmentAt: DateTime.now().add(const Duration(days: 1)),
                  registryNumber: 'AR12TXHQBWK',
                  faultTypeName: 'Soğutmuyor',
                  faultDescription: 'Soğutmuyor, fan çalışıyor.',
                  deviceBrand: 'Samsung',
                  deviceModel: 'Klima',
                  deviceSerial: '0AJC4EWB00123F',
                  technicianId: 't$index',
                  technicianName: 'Teknisyen $index',
                  accessoriesReceived: true,
                  totalAmount: 1250,
                  currency: 'TRY',
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
    case 'waiting':
      return 'Beklemede';
    case 'approval':
      return 'Onayda';
    case 'ready':
      return 'Hazır';
    case 'done':
      return 'Tamamlandı';
    case 'cancelled':
      return 'İptal';
    default:
      return 'Tümü';
  }
}

String _priorityLabel(String value) {
  switch (value) {
    case 'low':
      return 'Düşük';
    case 'medium':
      return 'Orta';
    case 'high':
      return 'Yüksek';
    default:
      return 'Tümü';
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.tone,
  });

  final String title;
  final String value;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          AppBadge(label: ' ', tone: tone, dense: true),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
                const Gap(2),
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
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

class _ServiceTableHeader extends StatelessWidget {
  const _ServiceTableHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(
              'Kayıt',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Müşteri',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              'Sicil / Arıza',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Tutar',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Durum',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              'Tarih',
              textAlign: TextAlign.right,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF64748B),
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceDetailPanel extends ConsumerWidget {
  const _ServiceDetailPanel({required this.serviceId});

  final String serviceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(serviceDetailProvider(serviceId));
    final accessoryTypesAsync = ref.watch(serviceAccessoryTypesProvider);

    return AppCard(
      child: detailAsync.when(
        data: (detail) {
          final statusLabel = switch (detail.status) {
            'open' || 'waiting' => 'Bekliyor',
            'in_progress' || 'approval' => 'Onayda',
            'ready' => 'Hazır',
            'done' => 'Teslim',
            _ => detail.status,
          };

          final accessoryNames = accessoryTypesAsync.asData?.value
                  .where((e) => detail.accessoryTypeIds.contains(e.id))
                  .map((e) => e.name)
                  .toList(growable: false) ??
              detail.accessoryTypeIds.toList(growable: false);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Kayıt Detayı',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  AppBadge(label: statusLabel, tone: AppBadgeTone.primary, dense: true),
                  const Gap(8),
                  PopupMenuButton<String>(
                    tooltip: 'İşlemler',
                    onSelected: (v) async {
                      final apiClient = ref.read(apiClientProvider);
                      if (apiClient == null) return;

                      if (v == 'edit') {
                        if (context.mounted) context.go('/servis/${detail.id}');
                        return;
                      }
                      if (v == 'toggle_active') {
                        final next = !detail.isActive;
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'updateWhere',
                            'table': 'service_records',
                            'filters': [
                              {'col': 'id', 'op': 'eq', 'value': detail.id},
                            ],
                            'values': {'is_active': next},
                          },
                        );
                        ref.invalidate(serviceDetailProvider(detail.id));
                        ref.invalidate(serviceRecordsProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(next ? 'Kayıt aktifleştirildi.' : 'Kayıt pasife alındı.'),
                            ),
                          );
                        }
                        return;
                      }
                      if (v == 'delete') {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Kaydı Sil'),
                            content: const Text('Bu işlem geri alınamaz. Devam edilsin mi?'),
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
                        if (ok != true) return;
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'delete',
                            'table': 'service_records',
                            'id': detail.id,
                          },
                        );
                        ref.invalidate(serviceRecordsProvider);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Kayıt silindi.')),
                          );
                        }
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                      PopupMenuItem(
                        value: 'toggle_active',
                        child: Text(detail.isActive ? 'Pasife Al' : 'Aktif Yap'),
                      ),
                      const PopupMenuDivider(),
                      const PopupMenuItem(value: 'delete', child: Text('Sil')),
                    ],
                    child: const SizedBox(
                      width: 36,
                      height: 34,
                      child: Icon(Icons.more_horiz_rounded),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              Text(
                detail.customerName ?? '—',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if ((detail.customerEmail ?? '').trim().isNotEmpty) ...[
                const Gap(4),
                Text(
                  detail.customerEmail!,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
              const Divider(height: 24),
              _kv(context, 'Başlık', detail.title),
              _kv(context, 'Sicil No', (detail.registryNumber ?? '').trim().isEmpty ? '—' : detail.registryNumber!),
              _kv(context, 'Arıza Tipi', (detail.faultTypeName ?? '').trim().isEmpty ? '—' : detail.faultTypeName!),
              if (detail.accessoriesReceived && accessoryNames.isNotEmpty)
                _kv(context, 'Aksesuar', accessoryNames.join(', ')),
              if ((detail.notes ?? '').trim().isNotEmpty) _kv(context, 'Not', detail.notes!),
              const Divider(height: 24),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        try {
                          await shareServicePdf(detail: detail, accessoryNames: accessoryNames);
                        } catch (_) {}
                      },
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text('PDF'),
                    ),
                  ),
                  const Gap(10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => context.go('/servis/${detail.id}'),
                      icon: const Icon(Icons.open_in_new_rounded, size: 18),
                      label: const Text('Aç'),
                    ),
                  ),
                ],
              ),
              const Gap(10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final next = await showModalBottomSheet<String>(
                          context: context,
                          showDragHandle: true,
                          builder: (context) => SafeArea(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                _StatusSheetItem(value: 'waiting', label: 'Bekliyor'),
                                _StatusSheetItem(value: 'approval', label: 'Onayda'),
                                _StatusSheetItem(value: 'ready', label: 'Hazır'),
                                _StatusSheetItem(value: 'done', label: 'Teslim'),
                              ],
                            ),
                          ),
                        );
                        if (next == null || next.trim().isEmpty) return;
                        final apiClient = ref.read(apiClientProvider);
                        if (apiClient == null) return;
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'updateWhere',
                            'table': 'service_records',
                            'filters': [
                              {'col': 'id', 'op': 'eq', 'value': detail.id},
                            ],
                            'values': {'status': next},
                          },
                        );
                        ref.invalidate(serviceDetailProvider(detail.id));
                        ref.invalidate(serviceRecordsProvider);
                      },
                      icon: const Icon(Icons.sync_rounded, size: 18),
                      label: const Text('Durum'),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Detay yüklenemedi.')),
      ),
    );
  }

  Widget _kv(BuildContext context, String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              k,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Text(
              v,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceRow extends StatelessWidget {
  const _ServiceRow({
    required this.item,
    this.selected = false,
    this.onTap,
  });

  final ServiceRecord item;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = switch (item.status) {
      'open' => ('Bekliyor', AppBadgeTone.warning),
      'waiting' => ('Bekliyor', AppBadgeTone.warning),
      'in_progress' => ('Onayda', AppBadgeTone.primary),
      'approval' => ('Onayda', AppBadgeTone.primary),
      'ready' => ('Hazır', AppBadgeTone.success),
      'done' => ('Teslim', AppBadgeTone.neutral),
      _ => ('—', AppBadgeTone.neutral),
    };
    final date = DateFormat('d MMM', 'tr_TR').format(item.createdAt);
    final serviceNoText = item.serviceNo == null ? 'SRV' : 'SRV-${item.serviceNo}';
    final registry = (item.registryNumber ?? '').trim();
    final fault = (item.faultTypeName ?? '').trim();
    final hasInfo = registry.isNotEmpty || fault.isNotEmpty;
    final amountText = item.totalAmount == null
        ? '—'
        : NumberFormat.currency(
            locale: 'tr_TR',
            symbol: item.currency == 'USD'
                ? r'$'
                : item.currency == 'EUR'
                    ? '€'
                    : '₺',
            decimalDigits: 2,
          ).format(item.totalAmount);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap ?? () => context.go('/servis/${item.id}'),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF2563EB).withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? const Color(0xFF2563EB).withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: Text(
                  item.title.trim().isEmpty ? serviceNoText : '$serviceNoText • ${item.title.trim()}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  item.customerName ?? '—',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  hasInfo
                      ? [
                          if (registry.isNotEmpty) registry,
                          if (fault.isNotEmpty) fault,
                          if (item.accessoriesReceived) 'Aksesuar',
                        ].join(' • ')
                      : (item.accessoriesReceived ? 'Aksesuar' : '—'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  amountText,
                  textAlign: TextAlign.right,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF94A3B8)),
                ),
              ),
              Expanded(
                flex: 2,
                child: Align(
                  alignment: Alignment.centerRight,
                  child: AppBadge(label: status.$1, tone: status.$2, dense: true),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  date,
                  textAlign: TextAlign.right,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF94A3B8)),
                ),
              ),
            ],
          ),
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
  TextEditingController? _customerFieldController;
  final _titleController = TextEditingController(text: 'Servis Kaydı');
  final _serialController = TextEditingController();
  final _deviceBrandController = TextEditingController();
  final _deviceModelController = TextEditingController();
  final _faultDescriptionController = TextEditingController();
  final _notesController = TextEditingController();
  String _priority = 'medium';
  String _technicianId = 'all';
  DateTime? _appointmentAt;
  String? _selectedFaultTypeId;
  bool _accessoriesReceived = false;
  final Set<String> _selectedAccessoryTypeIds = {};
  bool _saving = false;

  List<_CustomerOption> _customers = const [];
  String? _selectedCustomerId;
  List<_RegistryOption> _registries = const [];

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
        queryParameters: {'resource': 'customers_basic'},
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

  Future<void> _loadRegistries(String customerId) async {
    try {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'service_customer_device_registries',
          'customerId': customerId,
        },
      );
      final rows = (response['items'] as List?) ?? const [];
      if (!mounted) return;
      setState(() {
        _registries = rows
            .whereType<Map<String, dynamic>>()
            .map(_RegistryOption.fromJson)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _registries = const []);
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _titleController.dispose();
    _serialController.dispose();
    _deviceBrandController.dispose();
    _deviceModelController.dispose();
    _faultDescriptionController.dispose();
    _notesController.dispose();
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
      final deviceBrand =
          _deviceBrandController.text.trim().isEmpty ? null : _deviceBrandController.text.trim();
      final deviceModel =
          _deviceModelController.text.trim().isEmpty ? null : _deviceModelController.text.trim();
      final faultDescription = _faultDescriptionController.text.trim().isEmpty
          ? null
          : _faultDescriptionController.text.trim();
      final notes =
          _notesController.text.trim().isEmpty ? null : _notesController.text.trim();

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

      final created = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'service_records',
          'returning': 'row',
          'values': {
            'customer_id': customerId,
            'device_id': deviceId,
            'title': title.isEmpty ? 'Servis Kaydı' : title,
            'status': 'waiting',
            'priority': _priority,
            'technician_id': _technicianId == 'all' ? null : _technicianId,
            'appointment_at': _appointmentAt?.toUtc().toIso8601String(),
            'registry_number': serial.isEmpty ? null : serial,
            'fault_type_id': _selectedFaultTypeId,
            'fault_description': faultDescription,
            'device_brand': deviceBrand,
            'device_model': deviceModel,
            'device_serial': serial.isEmpty ? null : serial,
            'accessories_received': _accessoriesReceived,
            'accessory_type_ids': _selectedAccessoryTypeIds.toList(growable: false),
            'notes': notes,
            'steps': const [],
            'parts': const [],
            'labor': const [],
            'currency': 'TRY',
            'is_active': true,
          },
        },
      );
      final createdId = (created['id'] ?? '').toString().trim();

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Servis kaydı oluşturuldu.')),
      );

      if (createdId.isNotEmpty) {
        try {
          final detailJson = await apiClient.getJson(
            '/data',
            queryParameters: {'resource': 'service_detail', 'serviceId': createdId},
          );
          final detail = ServiceDetail.fromJson(detailJson);
          final accessoryDefs = await ref.read(serviceAccessoryTypesProvider.future);
          final accessoryNames = accessoryDefs
              .where((e) => detail.accessoryTypeIds.contains(e.id))
              .map((e) => e.name)
              .toList(growable: false);
          await shareServicePdf(detail: detail, accessoryNames: accessoryNames);
        } catch (_) {}
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Servis kaydı oluşturulamadı: $e')),
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
        constraints: BoxConstraints(
          maxWidth: 640,
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
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
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(right: 4),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
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
                              final q = normalizeSearchText(text.text);
                              if (q.isEmpty) return _customers.take(20);
                              return _customers
                                  .where((c) => normalizeSearchText(c.name).contains(q))
                                  .take(20);
                            },
                            displayStringForOption: (o) => o.name,
                            onSelected: (o) {
                              setState(() {
                                _selectedCustomerId = o.id;
                                _registries = const [];
                              });
                              _customerFieldController?.text = o.name;
                              _customerController.text = o.name;
                              _loadRegistries(o.id);
                            },
                            fieldViewBuilder: (context, controller, focusNode, _) {
                              _customerFieldController = controller;
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
                                onChanged: (v) => setState(() {
                                  _selectedCustomerId = null;
                                  _registries = const [];
                                  _customerController.text = v;
                                }),
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
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _priority,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'low',
                                    child: Text('Öncelik: Düşük'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'medium',
                                    child: Text('Öncelik: Orta'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'high',
                                    child: Text('Öncelik: Yüksek'),
                                  ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() => _priority = v ?? 'medium'),
                                decoration: const InputDecoration(labelText: 'Öncelik'),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: Consumer(
                                builder: (context, ref, _) {
                                  final techAsync = ref.watch(serviceTechniciansProvider);
                                  final techs = techAsync.asData?.value ??
                                      const <ServiceTechnician>[];
                                  return DropdownButtonFormField<String>(
                                    initialValue: _technicianId,
                                    items: [
                                      const DropdownMenuItem(
                                        value: 'all',
                                        child: Text('Teknisyen: Seçilmedi'),
                                      ),
                                      for (final t in techs)
                                        DropdownMenuItem(value: t.id, child: Text(t.fullName)),
                                    ],
                                    onChanged: _saving
                                        ? null
                                        : (v) => setState(() => _technicianId = v ?? 'all'),
                                    decoration:
                                        const InputDecoration(labelText: 'Teknisyen'),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const Gap(12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _saving
                                    ? null
                                    : () async {
                                        final now = DateTime.now();
                                        final picked = await showDatePicker(
                                          context: context,
                                          firstDate: DateTime(2020, 1, 1),
                                          lastDate: now.add(const Duration(days: 365)),
                                          initialDate: _appointmentAt ?? now,
                                        );
                                        if (picked == null) return;
                                        setState(() => _appointmentAt =
                                            DateTime(picked.year, picked.month, picked.day));
                                      },
                                icon: const Icon(Icons.event_rounded, size: 18),
                                label: Text(
                                  _appointmentAt == null
                                      ? 'Randevu Tarihi (opsiyonel)'
                                      : 'Randevu: ${DateFormat('d MMM y', 'tr_TR').format(_appointmentAt!)}',
                                ),
                              ),
                            ),
                            if (_appointmentAt != null) ...[
                              const Gap(12),
                              OutlinedButton(
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _appointmentAt = null),
                                child: const Text('Temizle'),
                              ),
                            ],
                          ],
                        ),
                        const Gap(12),
                        TextFormField(
                          controller: _deviceBrandController,
                          decoration: const InputDecoration(
                            labelText: 'Cihaz Marka (opsiyonel)',
                            hintText: 'Örn: Samsung',
                          ),
                        ),
                        const Gap(12),
                        TextFormField(
                          controller: _deviceModelController,
                          decoration: const InputDecoration(
                            labelText: 'Cihaz Model (opsiyonel)',
                            hintText: 'Örn: Klima',
                          ),
                        ),
                        const Gap(12),
                        DropdownButtonFormField<String?>(
                          initialValue: null,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Sicil listeden seç (opsiyonel)'),
                            ),
                            for (final r in _registries)
                              DropdownMenuItem<String?>(
                                value: r.registryNumber,
                                child: Text(
                                  [
                                    r.registryNumber,
                                    if (r.model.trim().isNotEmpty) r.model.trim(),
                                  ].join(' • '),
                                ),
                              ),
                          ],
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _serialController.text = v ?? ''),
                          decoration: const InputDecoration(labelText: 'Sicil No'),
                        ),
                        const Gap(12),
                        TextFormField(
                          controller: _serialController,
                          decoration: const InputDecoration(
                            labelText: 'Cihaz Sicil No (manuel)',
                            hintText: 'SN...',
                          ),
                        ),
                        const Gap(12),
                        TextFormField(
                          controller: _faultDescriptionController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Arıza Açıklaması (opsiyonel)',
                            hintText: 'Örn: Soğutmuyor, fan çalışıyor...',
                          ),
                        ),
                        const Gap(12),
                        Consumer(
                          builder: (context, ref, _) {
                            final faultTypesAsync = ref.watch(serviceFaultTypesProvider);
                            return faultTypesAsync.when(
                              data: (items) => DropdownButtonFormField<String?>(
                                initialValue: (_selectedFaultTypeId ?? '').trim().isEmpty
                                    ? null
                                    : _selectedFaultTypeId,
                                items: [
                                  const DropdownMenuItem<String?>(
                                    value: null,
                                    child: Text('Arıza Tipi (opsiyonel)'),
                                  ),
                                  for (final t in items)
                                    DropdownMenuItem<String?>(
                                      value: t.id,
                                      child: Text(t.name),
                                    ),
                                ],
                                onChanged: _saving
                                    ? null
                                    : (v) => setState(() => _selectedFaultTypeId = v),
                                decoration:
                                    const InputDecoration(labelText: 'Arıza Tipi'),
                              ),
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            );
                          },
                        ),
                        const Gap(12),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _accessoriesReceived,
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _accessoriesReceived = v),
                          title: const Text('Aksesuar Teslim Alındı'),
                        ),
                        if (_accessoriesReceived) ...[
                          Consumer(
                            builder: (context, ref, _) {
                              final accessoryAsync = ref.watch(serviceAccessoryTypesProvider);
                              return accessoryAsync.when(
                                data: (items) => Column(
                                  children: [
                                    for (final t in items)
                                      CheckboxListTile(
                                        contentPadding: EdgeInsets.zero,
                                        value: _selectedAccessoryTypeIds.contains(t.id),
                                        onChanged: _saving
                                            ? null
                                            : (v) => setState(() {
                                                  if (v == true) {
                                                    _selectedAccessoryTypeIds.add(t.id);
                                                  } else {
                                                    _selectedAccessoryTypeIds.remove(t.id);
                                                  }
                                                }),
                                        title: Text(t.name),
                                      ),
                                  ],
                                ),
                                loading: () => const SizedBox.shrink(),
                                error: (_, _) => const SizedBox.shrink(),
                              );
                            },
                          ),
                        ],
                        const Gap(12),
                        TextFormField(
                          controller: _notesController,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Not (opsiyonel)',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(12),
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

class _RegistryOption {
  const _RegistryOption({
    required this.id,
    required this.registryNumber,
    required this.model,
  });

  final String id;
  final String registryNumber;
  final String model;

  factory _RegistryOption.fromJson(Map<String, dynamic> json) {
    return _RegistryOption(
      id: json['id']?.toString() ?? '',
      registryNumber: (json['registry_number'] ?? '').toString(),
      model: (json['model'] ?? '').toString(),
    );
  }
}

class ServiceRecord {
  const ServiceRecord({
    required this.id,
    required this.serviceNo,
    required this.title,
    required this.customerName,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.appointmentAt,
    required this.registryNumber,
    required this.faultTypeName,
    required this.faultDescription,
    required this.deviceBrand,
    required this.deviceModel,
    required this.deviceSerial,
    required this.technicianId,
    required this.technicianName,
    required this.accessoriesReceived,
    required this.totalAmount,
    required this.currency,
  });

  final String id;
  final int? serviceNo;
  final String title;
  final String? customerName;
  final String status;
  final String? priority;
  final DateTime createdAt;
  final DateTime? appointmentAt;
  final String? registryNumber;
  final String? faultTypeName;
  final String? faultDescription;
  final String? deviceBrand;
  final String? deviceModel;
  final String? deviceSerial;
  final String? technicianId;
  final String? technicianName;
  final bool accessoriesReceived;
  final double? totalAmount;
  final String? currency;

  factory ServiceRecord.fromJson(Map<String, dynamic> json) {
    int? toIntAny(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    double? toDoubleAny(Object? v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '');
    }

    return ServiceRecord(
      id: json['id'].toString(),
      serviceNo: toIntAny(json['service_no']),
      title: (json['title'] ?? '').toString(),
      customerName: json['customer_name']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: json['priority']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      appointmentAt: DateTime.tryParse(json['appointment_at']?.toString() ?? ''),
      registryNumber: json['registry_number']?.toString(),
      faultTypeName: json['fault_type_name']?.toString(),
      faultDescription: json['fault_description']?.toString(),
      deviceBrand: json['device_brand']?.toString(),
      deviceModel: json['device_model']?.toString(),
      deviceSerial: json['device_serial']?.toString(),
      technicianId: json['technician_id']?.toString(),
      technicianName: json['technician_name']?.toString(),
      accessoriesReceived: json['accessories_received'] as bool? ?? false,
      totalAmount: toDoubleAny(json['total_amount']),
      currency: json['currency']?.toString(),
    );
  }
}
