import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/utils/app_time.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/format/search_normalize.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_create_dialog.dart';
import 'work_order_detail_sheet.dart';
import 'work_order_model.dart';
import 'work_order_region_colors.dart';
import 'work_orders_providers.dart';

String _shortId(String id) {
  final trimmed = id.trim();
  if (trimmed.length <= 6) return trimmed;
  return trimmed.substring(0, 6);
}

Color _cityAccentColor(
  String? city, {
  required int fallbackIndex,
  required WorkOrderRegionThemeResolver resolver,
}) {
  return resolver.accent(city, fallbackIndex: fallbackIndex);
}

Color? _cityBackgroundColor(String? city, {required WorkOrderRegionThemeResolver resolver}) {
  return resolver.background(city);
}

Widget _compactStatusPill(String status) {
  final color = _statusColor(status);
  final label = switch (status) {
    'open' => 'BEKLEYEN',
    'in_progress' => 'YAPILIYOR',
    'approval_pending' => 'ONAY',
    'done' => 'KAPALI',
    'cancelled' => 'İPTAL',
    _ => status.toUpperCase(),
  };
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(999),
      border: Border.all(color: color.withValues(alpha: 0.30)),
    ),
    child: Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w900,
        color: color,
      ),
    ),
  );
}

Widget _statusBadge(String status) {
  switch (status) {
    case 'open':
      return const AppBadge(label: 'BEKLEYEN', tone: AppBadgeTone.warning);
    case 'in_progress':
      return const AppBadge(label: 'YAPILIYOR', tone: AppBadgeTone.primary);
    case 'approval_pending':
      return const AppBadge(label: 'ONAY BEKLİYOR', tone: AppBadgeTone.primary);
    case 'done':
      return const AppBadge(label: 'TAMAMLANDI', tone: AppBadgeTone.success);
    case 'cancelled':
      return const AppBadge(label: 'İPTAL', tone: AppBadgeTone.error);
    default:
      return AppBadge(label: status.toUpperCase(), tone: AppBadgeTone.neutral);
  }
}

class WorkOrdersListScreen extends ConsumerStatefulWidget {
  const WorkOrdersListScreen({super.key});

  @override
  ConsumerState<WorkOrdersListScreen> createState() =>
      _WorkOrdersListScreenState();
}

class _WorkOrdersListScreenState extends ConsumerState<WorkOrdersListScreen> {
  final _searchController = TextEditingController();
  String _statusFilter = 'open';
  bool _showPassive = false;
  bool _reorderMode = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(workOrdersBoardProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDelete = ref.watch(hasActionAccessProvider(kActionDeleteRecords));
    const allowedStatuses = {
      'all',
      'open',
      'in_progress',
      'approval_pending',
      'done',
      'cancelled',
    };
    if (!allowedStatuses.contains(_statusFilter)) {
      _statusFilter = 'all';
    }
    if (_statusFilter != 'open') _reorderMode = false;
    if (!canEdit) _reorderMode = false;

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: _reorderMode ? null : 'Tüm iş emirlerini tek ekranda arayın ve yönetin.',
      actions: _reorderMode
          ? [
              FilledButton.tonalIcon(
                onPressed: () => setState(() => _reorderMode = false),
                icon: const Icon(Icons.check_circle_outline_rounded, size: 18),
                label: const Text('Sıralama Bitti'),
              ),
            ]
          : [
              OutlinedButton.icon(
                onPressed: () =>
                    ref.read(workOrdersBoardProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Yenile'),
              ),
              const Gap(10),
              OutlinedButton.icon(
                onPressed: () => context.go('/is-emirleri/tahsilatlar'),
                icon: const Icon(Icons.payments_outlined, size: 18),
                label: const Text('Tahsilatlar'),
              ),
              const Gap(10),
              FilledButton.icon(
                onPressed: canEdit
                    ? () async {
                        await showCreateWorkOrderDialog(context, ref);
                        ref.read(workOrdersBoardProvider.notifier).refresh();
                      }
                    : null,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Yeni İş Emri'),
              ),
            ],
      body: boardAsync.when(
        data: (items) {
          int byStatus(String status) =>
              items.where((item) => item.status == status).length;

          if (items.isEmpty) {
            return AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'İş emri bulunamadı.',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const Gap(8),
                    Text(
                      'Bu hesapta iş emri yok veya yetki/bağlantı nedeniyle liste boş geliyor.',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted),
                    ),
                    const Gap(12),
                    profileAsync.when(
                      data: (p) => Text(
                        'Rol: ${p?.role ?? '-'}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textMuted),
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (error, stackTrace) => const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            );
          }

          final search = normalizeSearchText(_searchController.text);
          final filtered = items.where((item) {
            if (!_showPassive && !item.isActive) return false;
            if (_statusFilter != 'all' && item.status != _statusFilter) {
              return false;
            }
            if (_fromDate != null) {
              final d = _statusFilter == 'done'
                  ? (item.closedAt ?? item.createdAt ?? item.scheduledDate)
                  : (item.createdAt ?? item.scheduledDate);
              if (d == null) return false;
              final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
              if (d.isBefore(start)) return false;
            }
            if (_toDate != null) {
              final d = _statusFilter == 'done'
                  ? (item.closedAt ?? item.createdAt ?? item.scheduledDate)
                  : (item.createdAt ?? item.scheduledDate);
              if (d == null) return false;
              final end = DateTime(_toDate!.year, _toDate!.month, _toDate!.day, 23, 59, 59);
              if (d.isAfter(end)) return false;
            }
            if (search.isEmpty) return true;
            final haystack = [
              item.id,
              item.title,
              item.customerName ?? '',
              item.branchName ?? '',
            ].join(' ');
            final hay = normalizeSearchText(haystack);
            return hay.contains(search);
          }).toList(growable: false);

          final isMobile = MediaQuery.sizeOf(context).width < 720;
          final headerCard = AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
                  builder: (context, constraints) {
                    final wide = constraints.maxWidth >= 980;
                    final compact = constraints.maxWidth < 720;

                    Future<void> openFiltersSheet() async {
                      await showModalBottomSheet<void>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (context) => StatefulBuilder(
                          builder: (context, setSheetState) => SafeArea(
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Filtreler',
                                    style:
                                        Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const Gap(12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate:
                                                  _fromDate ?? DateTime.now(),
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked == null) return;
                                            setState(() => _fromDate = picked);
                                            setSheetState(() {});
                                          },
                                          icon: const Icon(Icons.event_rounded,
                                              size: 18),
                                          label: Text(
                                            _fromDate == null
                                                ? 'Başlangıç'
                                                : DateFormat('y-MM-dd')
                                                    .format(_fromDate!),
                                          ),
                                        ),
                                      ),
                                      const Gap(10),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () async {
                                            final picked = await showDatePicker(
                                              context: context,
                                              initialDate: _toDate ??
                                                  (_fromDate ?? DateTime.now()),
                                              firstDate: DateTime(2020),
                                              lastDate: DateTime(2100),
                                            );
                                            if (picked == null) return;
                                            setState(() => _toDate = picked);
                                            setSheetState(() {});
                                          },
                                          icon: const Icon(
                                              Icons.event_available_rounded,
                                              size: 18),
                                          label: Text(
                                            _toDate == null
                                                ? 'Bitiş'
                                                : DateFormat('y-MM-dd')
                                                    .format(_toDate!),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Gap(10),
                                  SwitchListTile(
                                    value: _showPassive,
                                    onChanged: (v) {
                                      setState(() => _showPassive = v);
                                      setSheetState(() {});
                                    },
                                    title: const Text('Pasif kayıtları göster'),
                                    contentPadding: EdgeInsets.zero,
                                  ),
                                  if (canEdit && _statusFilter == 'open') ...[
                                    SwitchListTile(
                                      value: _reorderMode,
                                      onChanged: (v) {
                                        setState(() => _reorderMode = v);
                                        setSheetState(() {});
                                      },
                                      title: const Text('Sürükle-bırak sıralama'),
                                      contentPadding: EdgeInsets.zero,
                                    ),
                                  ],
                                  const Gap(10),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: () {
                                            _searchController.clear();
                                            setState(() => _statusFilter = 'open');
                                            setState(() => _showPassive = false);
                                            setState(() => _reorderMode = false);
                                            setState(() {
                                              _fromDate = null;
                                              _toDate = null;
                                            });
                                            Navigator.of(context).pop();
                                          },
                                          icon: const Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18),
                                          label: const Text('Temizle'),
                                          style: FilledButton.styleFrom(
                                            backgroundColor:
                                                const Color(0xFFEF4444)
                                                    .withValues(alpha: 0.12),
                                            foregroundColor:
                                                const Color(0xFF7F1D1D),
                                            minimumSize: const Size(0, 44),
                                          ),
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

                    final controls = compact
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 10,
                                runSpacing: 10,
                                children: [
                                  _StatusPill(
                                    label:
                                        'Durum: ${_statusLabel(_statusFilter)}',
                                    backgroundColor: const Color(0xFF7C3AED)
                                        .withValues(alpha: 0.12),
                                    foregroundColor: const Color(0xFF4C1D95),
                                    icon: Icons.circle_rounded,
                                    onTap: () async {
                                      final next =
                                          await showModalBottomSheet<String>(
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
                                                label: 'Yapılıyor',
                                              ),
                                              _StatusSheetItem(
                                                value: 'approval_pending',
                                                label: 'Onay Bekliyor',
                                              ),
                                              _StatusSheetItem(
                                                value: 'done',
                                                label: 'Kapalı',
                                              ),
                                              _StatusSheetItem(
                                                value: 'cancelled',
                                                label: 'İptal',
                                              ),
                                            ],
                                          ),
                                        ),
                                      );
                                      if (next == null ||
                                          next.trim().isEmpty) {
                                        return;
                                      }
                                      setState(() {
                                        _statusFilter = next.trim();
                                        if (_statusFilter == 'done' &&
                                            _fromDate == null &&
                                            _toDate == null) {
                                          final today = DateTime.now();
                                          _fromDate = DateTime(today.year, today.month, today.day);
                                          _toDate = DateTime(today.year, today.month, today.day);
                                        }
                                      });
                                    },
                                  ),
                                  if (_showPassive)
                                    const AppBadge(
                                      label: 'Pasif: Açık',
                                      tone: AppBadgeTone.neutral,
                                    ),
                                  if (_fromDate != null)
                                    AppBadge(
                                      label:
                                          'Baş: ${DateFormat('y-MM-dd').format(_fromDate!)}',
                                      tone: AppBadgeTone.neutral,
                                    ),
                                  if (_toDate != null)
                                    AppBadge(
                                      label:
                                          'Bit: ${DateFormat('y-MM-dd').format(_toDate!)}',
                                      tone: AppBadgeTone.neutral,
                                    ),
                                ],
                              ),
                              const Gap(10),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _searchController,
                                      onChanged: (_) => setState(() {}),
                                      decoration: const InputDecoration(
                                        prefixIcon: Icon(Icons.search_rounded),
                                        hintText: 'Ara',
                                      ),
                                    ),
                                  ),
                                  const Gap(10),
                                  IconButton.filledTonal(
                                    onPressed: openFiltersSheet,
                                    icon: const Icon(Icons.tune_rounded),
                                  ),
                                ],
                              ),
                            ],
                          )
                        : Wrap(
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
                                backgroundColor: const Color(0xFF7C3AED)
                                    .withValues(alpha: 0.12),
                                foregroundColor: const Color(0xFF4C1D95),
                                icon: Icons.circle_rounded,
                                onTap: () async {
                                  final next =
                                      await showModalBottomSheet<String>(
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
                                            label: 'Yapılıyor',
                                          ),
                                          _StatusSheetItem(
                                            value: 'approval_pending',
                                            label: 'Onay Bekliyor',
                                          ),
                                          _StatusSheetItem(
                                            value: 'done',
                                            label: 'Kapalı',
                                          ),
                                          _StatusSheetItem(
                                            value: 'cancelled',
                                            label: 'İptal',
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                  if (next == null || next.trim().isEmpty) {
                                    return;
                                  }
                                  setState(() {
                                    _statusFilter = next.trim();
                                    if (_statusFilter == 'done' &&
                                        _fromDate == null &&
                                        _toDate == null) {
                                      final today = DateTime.now();
                                      _fromDate = DateTime(today.year, today.month, today.day);
                                      _toDate = DateTime(today.year, today.month, today.day);
                                    }
                                  });
                                },
                              ),
                              if (_statusFilter == 'open')
                                FilledButton.tonalIcon(
                                  onPressed: () =>
                                      setState(() => _reorderMode = !_reorderMode),
                                  icon: Icon(
                                    _reorderMode
                                        ? Icons.check_circle_outline_rounded
                                        : Icons.drag_handle_rounded,
                                    size: 18,
                                  ),
                                  label: Text(
                                    _reorderMode
                                        ? 'Sıralama: Açık'
                                        : 'Sıralama: Kapalı',
                                  ),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFF0EA5E9)
                                        .withValues(alpha: 0.12),
                                    foregroundColor: const Color(0xFF0C4A6E),
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate: _fromDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked == null) return;
                                  setState(() => _fromDate = picked);
                                },
                                icon: const Icon(Icons.event_rounded, size: 18),
                                label: Text(
                                  _fromDate == null
                                      ? 'Başlangıç'
                                      : DateFormat('y-MM-dd').format(_fromDate!),
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: () async {
                                  final picked = await showDatePicker(
                                    context: context,
                                    initialDate:
                                        _toDate ?? (_fromDate ?? DateTime.now()),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime(2100),
                                  );
                                  if (picked == null) return;
                                  setState(() => _toDate = picked);
                                },
                                icon: const Icon(Icons.event_available_rounded,
                                    size: 18),
                                label: Text(
                                  _toDate == null
                                      ? 'Bitiş'
                                      : DateFormat('y-MM-dd').format(_toDate!),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () =>
                                    setState(() => _showPassive = !_showPassive),
                                icon:
                                    const Icon(Icons.visibility_rounded, size: 18),
                                label: Text(
                                  _showPassive ? 'Kayıt: Tümü' : 'Kayıt: Aktif',
                                ),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFF16A34A)
                                      .withValues(alpha: 0.12),
                                  foregroundColor: const Color(0xFF14532D),
                                  minimumSize: const Size(0, 40),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 10,
                                  ),
                                ),
                              ),
                              FilledButton.tonalIcon(
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _statusFilter = 'open');
                                  setState(() => _showPassive = false);
                                  setState(() => _reorderMode = false);
                                  setState(() {
                                    _fromDate = null;
                                    _toDate = null;
                                  });
                                },
                                icon: const Icon(Icons.delete_outline_rounded,
                                    size: 18),
                                label: const Text('Temizle'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: const Color(0xFFEF4444)
                                      .withValues(alpha: 0.12),
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

                    final stats = Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        AppBadge(
                          label: 'Toplam: ${items.length}',
                          tone: AppBadgeTone.primary,
                        ),
                        AppBadge(
                          label: 'Açık: ${byStatus('open')}',
                          tone: AppBadgeTone.warning,
                        ),
                        AppBadge(
                          label: 'Yapılıyor: ${byStatus('in_progress')}',
                          tone: AppBadgeTone.primary,
                        ),
                                        AppBadge(
                                          label:
                                              'Onay: ${byStatus('approval_pending')}',
                                          tone: AppBadgeTone.primary,
                                        ),
                        AppBadge(
                          label: 'Kapalı: ${byStatus('done')}',
                          tone: AppBadgeTone.success,
                        ),
                        AppBadge(
                          label: 'İptal: ${byStatus('cancelled')}',
                          tone: AppBadgeTone.error,
                        ),
                      ],
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
          );

          Widget buildList({Widget? header}) {
            if (filtered.isEmpty) {
              return ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  if (header != null) ...[header, const Gap(12)],
                  AppCard(
                    child: Center(
                      child: Text(
                        'Kayıt bulunamadı.',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                ],
              );
            }

            return _WorkOrdersList(
              header: header,
              items: filtered,
              canReorder:
                  _reorderMode && _statusFilter == 'open' && search.trim().isEmpty,
              preferGrid: (kIsWeb && !isMobile) || isMobile,
              canEdit: canEdit,
              canArchive: canArchive,
              canDelete: canDelete,
              onReorder: (nextOpenOrderList) => ref
                  .read(workOrdersBoardProvider.notifier)
                  .reorderOpenOrders(nextOpenOrderList),
              onOpen: (order) async {
                await showWorkOrderDetailSheet(
                  context,
                  ref,
                  order: order,
                );
                ref.read(workOrdersBoardProvider.notifier).refresh();
              },
              onEdit: (order) async {
                await showCreateWorkOrderDialog(
                  context,
                  ref,
                  initialOrder: order,
                );
                ref.read(workOrdersBoardProvider.notifier).refresh();
              },
              onApprovalPending: (order) {
                if (!canEdit) return;
                ref.read(workOrdersBoardProvider.notifier).updateStatus(
                      workOrderId: order.id,
                      newStatus: 'approval_pending',
                    );
              },
              onMarkOpen: (order) {
                if (!canEdit) return;
                ref
                    .read(workOrdersBoardProvider.notifier)
                    .updateStatus(workOrderId: order.id, newStatus: 'open');
              },
              onCancel: (order) {
                if (!canEdit) return;
                ref
                    .read(workOrdersBoardProvider.notifier)
                    .updateStatus(workOrderId: order.id, newStatus: 'cancelled');
              },
              onToggleActive: (order) {
                if (!canArchive) return;
                ref
                    .read(workOrdersBoardProvider.notifier)
                    .setActive(workOrderId: order.id, isActive: !order.isActive);
              },
              onDelete: (order) async {
                if (!canDelete) return;
                final confirm = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    title: const Text('Silme Onayı'),
                    content: Text('#${_shortId(order.id)} silinsin mi?'),
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
                if (confirm == true) {
                  await ref
                      .read(workOrdersBoardProvider.notifier)
                      .deleteWorkOrder(order.id);
                }
              },
            );
          }

          if (isMobile) {
            return RefreshIndicator(
              onRefresh: () => ref.read(workOrdersBoardProvider.notifier).refresh(),
              child: buildList(header: _reorderMode ? null : headerCard),
            );
          }

          return Column(
            children: [
              headerCard,
              const Gap(12),
              Expanded(child: buildList()),
            ],
          );
        },
        loading: () => Skeletonizer(
          enabled: true,
          child: Column(
            children: [
              AppCard(
                child: TextField(
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search_rounded),
                    labelText: 'Ara',
                  ),
                ),
              ),
              const Gap(12),
              Expanded(
                child: ListView.separated(
                  padding: EdgeInsets.zero,
                  itemCount: 8,
                  separatorBuilder: (context, index) => const Gap(8),
                  itemBuilder: (context, index) => AppCard(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: AppTheme.border,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                height: 12,
                                width: 240,
                                color: AppTheme.surfaceMuted,
                              ),
                              const Gap(8),
                              Container(
                                height: 10,
                                width: 180,
                                color: AppTheme.surfaceMuted,
                              ),
                            ],
                          ),
                        ),
                        const Gap(12),
                        Container(
                          height: 28,
                          width: 86,
                          decoration: BoxDecoration(
                            color: AppTheme.surfaceMuted,
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        error: (error, _) => Center(
          child: AppCard(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Text(
                'İş emirleri yüklenemedi: $error',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: AppTheme.textMuted),
              ),
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
      return 'Yapılıyor';
    case 'approval_pending':
      return 'Onay Bekliyor';
    case 'done':
      return 'Kapalı';
    case 'cancelled':
      return 'İptal';
    default:
      return 'Tümü';
  }
}

class _WorkOrdersList extends StatelessWidget {
  const _WorkOrdersList({
    required this.header,
    required this.items,
    required this.canReorder,
    required this.preferGrid,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onReorder,
    required this.onOpen,
    required this.onEdit,
    required this.onApprovalPending,
    required this.onMarkOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
  });

  final Widget? header;
  final List<WorkOrder> items;
  final bool canReorder;
  final bool preferGrid;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final ValueChanged<List<WorkOrder>> onReorder;
  final ValueChanged<WorkOrder> onOpen;
  final ValueChanged<WorkOrder> onEdit;
  final ValueChanged<WorkOrder> onApprovalPending;
  final ValueChanged<WorkOrder> onMarkOpen;
  final ValueChanged<WorkOrder> onCancel;
  final ValueChanged<WorkOrder> onToggleActive;
  final ValueChanged<WorkOrder> onDelete;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        if (byOrder != 0) return byOrder;
        final aDate = a.createdAt ?? a.scheduledDate;
        final bDate = b.createdAt ?? b.scheduledDate;
        final byDate = (bDate ?? DateTime.fromMillisecondsSinceEpoch(0))
            .compareTo(aDate ?? DateTime.fromMillisecondsSinceEpoch(0));
        if (byDate != 0) return byDate;
        return a.id.compareTo(b.id);
      });

    final hasHeader = header != null;
    final headerCount = hasHeader ? 1 : 0;
    final openIndexMap = <String, int>{};
    var openCounter = 0;
    for (final w in sorted) {
      if (w.status == 'open') {
        openCounter += 1;
        openIndexMap[w.id] = openCounter;
      }
    }

    if (canReorder && preferGrid) {
      return _ReorderableWorkOrdersGrid(
        items: sorted,
        openIndexMap: openIndexMap,
        onReorder: onReorder,
        onOpen: onOpen,
        onEdit: onEdit,
        onApprovalPending: onApprovalPending,
        onMarkOpen: onMarkOpen,
        onCancel: onCancel,
        onToggleActive: onToggleActive,
        onDelete: onDelete,
        showEdit: canEdit,
        showCancel: canEdit,
        showToggleActive: canArchive,
        showDelete: canDelete,
      );
    }

    if (canReorder) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 120),
        itemCount: sorted.length + headerCount,
        onReorder: (oldIndex, newIndex) {
          if (hasHeader) {
            if (oldIndex == 0) return;
            if (newIndex == 0) newIndex = 1;
            final from = oldIndex - 1;
            var to = newIndex - 1;
            if (to > from) to -= 1;
            final next = [...sorted];
            final item = next.removeAt(from);
            next.insert(to, item);
            onReorder(next);
            return;
          }

          if (newIndex > oldIndex) newIndex -= 1;
          final next = [...sorted];
          final item = next.removeAt(oldIndex);
          next.insert(newIndex, item);
          onReorder(next);
        },
        itemBuilder: (context, index) {
          if (hasHeader && index == 0) {
            return KeyedSubtree(
              key: const ValueKey('wo:list:header'),
              child: header!,
            );
          }
          final effectiveIndex = index - headerCount;
          final order = sorted[effectiveIndex];
          return _WorkOrderCard(
            key: ValueKey('wo:${order.id}'),
            order: order,
            indexNumber: effectiveIndex + 1,
            reorderIndex: effectiveIndex,
            reorderable: true,
            onOpen: () => onOpen(order),
            onEdit: canEdit ? () => onEdit(order) : null,
            onApprovalPending: () => onApprovalPending(order),
            onMarkOpen: () => onMarkOpen(order),
            onCancel: () => onCancel(order),
            onToggleActive: () => onToggleActive(order),
            onDelete: () => onDelete(order),
            showEdit: canEdit,
            showCancel: canEdit,
            showToggleActive: canArchive,
            showDelete: canDelete,
          );
        },
      );
    }

    if (preferGrid) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final maxColumns = width < 520
              ? 2
              : width < 820
                  ? 3
                  : 6;
          final targetTileWidth = width < 520
              ? 170.0
              : width < 820
                  ? 200.0
                  : 220.0;
          final crossAxisCount =
              (width / targetTileWidth).floor().clamp(2, maxColumns);
          final childAspectRatio = width < 520
              ? 0.74
              : width < 1000
                  ? 0.98
                  : 1.18;

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              if (header != null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: header!,
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 120),
                sliver: SliverGrid(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                    childAspectRatio: childAspectRatio,
                  ),
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final order = sorted[index];
                      final indexNumber = openIndexMap[order.id];
                      return _WorkOrderGridCard(
                        order: order,
                        indexNumber: indexNumber,
                        colorIndex: index,
                        onOpen: () => onOpen(order),
                        onEdit: canEdit ? () => onEdit(order) : null,
                        onApprovalPending: () => onApprovalPending(order),
                        onMarkOpen: () => onMarkOpen(order),
                        onCancel: () => onCancel(order),
                        onToggleActive: () => onToggleActive(order),
                        onDelete: () => onDelete(order),
                        showEdit: canEdit,
                        showCancel: canEdit,
                        showToggleActive: canArchive,
                        showDelete: canDelete,
                      );
                    },
                    childCount: sorted.length,
                  ),
                ),
              ),
            ],
          );
        },
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(bottom: 120),
      itemCount: sorted.length + headerCount,
      separatorBuilder: (context, index) {
        if (hasHeader && index == 0) return const Gap(12);
        return const Gap(10);
      },
      itemBuilder: (context, index) {
        if (hasHeader && index == 0) return header!;
        final effectiveIndex = index - headerCount;
        final order = sorted[effectiveIndex];
        final indexNumber = openIndexMap[order.id];
        return _WorkOrderCard(
          order: order,
          indexNumber: indexNumber,
          reorderIndex: effectiveIndex,
          reorderable: false,
          onOpen: () => onOpen(order),
          onEdit: canEdit ? () => onEdit(order) : null,
          onApprovalPending: () => onApprovalPending(order),
          onMarkOpen: () => onMarkOpen(order),
          onCancel: () => onCancel(order),
          onToggleActive: () => onToggleActive(order),
          onDelete: () => onDelete(order),
          showEdit: canEdit,
          showCancel: canEdit,
          showToggleActive: canArchive,
          showDelete: canDelete,
        );
      },
    );
  }
}

class _WorkOrderGridCard extends ConsumerWidget {
  const _WorkOrderGridCard({
    required this.order,
    required this.indexNumber,
    required this.colorIndex,
    required this.onOpen,
    required this.onEdit,
    required this.onApprovalPending,
    required this.onMarkOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
    required this.showEdit,
    required this.showCancel,
    required this.showToggleActive,
    required this.showDelete,
  });

  final WorkOrder order;
  final int? indexNumber;
  final int colorIndex;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback onApprovalPending;
  final VoidCallback onMarkOpen;
  final VoidCallback onCancel;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final bool showEdit;
  final bool showCancel;
  final bool showToggleActive;
  final bool showDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver =
        ref.watch(workOrderRegionThemeProvider).value ??
        WorkOrderRegionThemeResolver.defaults();
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 190 || constraints.maxWidth < 210;
        final statusColor = _statusColor(order.status);
        final accent = _cityAccentColor(
          order.city,
          fallbackIndex: colorIndex,
          resolver: resolver,
        );
        final backgroundColor = _cityBackgroundColor(order.city, resolver: resolver);
        final isDarkCard = backgroundColor != null && backgroundColor.computeLuminance() < 0.42;
        final primaryTextColor = isDarkCard ? Colors.white : null;
        final mutedTextColor = isDarkCard ? Colors.white.withValues(alpha: 0.78) : AppTheme.textMuted;
        final iconColor = isDarkCard ? Colors.white.withValues(alpha: 0.86) : null;
        final muted = Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: mutedTextColor);

        final customerName = (order.customerName ?? '').trim();
        final branchName = (order.branchName ?? '').trim();
        final assignedName = (order.assignedPersonnelName ?? '').trim();

        final scheduled = order.scheduledDate == null
            ? null
            : DateFormat('d MMM', 'tr_TR')
                .format(AppTime.toTr(order.scheduledDate!));
        final createdAtTime = order.createdAt == null
            ? null
            : DateFormat('HH:mm', 'tr_TR')
                .format(AppTime.toTr(order.createdAt!));

        final typeName = (order.workOrderTypeName ?? '').trim();
        final city = (order.city ?? '').trim();
        final address = (order.address ?? '').trim();
        final contactPhone = (order.contactPhone ?? '').trim();
        final paymentValue = order.paymentRequired;
        final paymentColor = paymentValue == null
            ? null
            : paymentValue
                ? const Color(0xFF16A34A)
                : const Color(0xFFDC2626);
        final paymentIcon = paymentValue == null
            ? null
            : paymentValue
                ? Icons.payments_rounded
                : Icons.money_off_csred_rounded;

        final meta = [
          if (typeName.isNotEmpty) typeName,
          if (city.isNotEmpty) city,
          if (createdAtTime != null) 'Oluş: $createdAtTime',
          if (scheduled != null) 'Plan: $scheduled',
        ].join(' • ');

        Widget infoLine(String label, String value) {
          final style = (muted ?? const TextStyle()).copyWith(
            fontSize: compact ? 10 : muted?.fontSize,
            height: compact ? 1.02 : muted?.height,
          );
          return Text(
            '$label: $value',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          );
        }

        return AppCard(
          onTap: onOpen,
          padding: EdgeInsets.all(compact ? 6 : 10),
          color: backgroundColor,
          borderColor: accent,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: compact ? 28 : 32,
                    height: compact ? 28 : 32,
                    decoration: BoxDecoration(
                      color: isDarkCard
                          ? Colors.white.withValues(alpha: 0.14)
                          : accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isDarkCard
                            ? Colors.white.withValues(alpha: 0.24)
                            : accent.withValues(alpha: 0.22),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        indexNumber?.toString() ?? _shortId(order.id),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w900,
                              color: isDarkCard ? Colors.white : accent,
                            ),
                      ),
                    ),
                  ),
                  const Gap(8),
                  if (paymentValue != null) ...[
                    Container(
                      width: compact ? 26 : 30,
                      height: compact ? 26 : 30,
                      decoration: BoxDecoration(
                        color: paymentColor!.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: paymentColor.withValues(alpha: 0.30),
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          paymentIcon!,
                          size: 18,
                          color: paymentColor,
                        ),
                      ),
                    ),
                    const Gap(6),
                  ],
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: compact
                          ? FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: Alignment.centerRight,
                              child: _compactStatusPill(order.status),
                            )
                          : _statusBadge(order.status),
                    ),
                  ),
                  PopupMenuButton<String>(
                    padding: EdgeInsets.zero,
                    tooltip: 'İşlemler',
                    icon: Icon(Icons.more_horiz_rounded, color: iconColor),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'detail', child: Text('Detay')),
                      if (showEdit)
                        const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                      if (showEdit &&
                          (order.status == 'open' ||
                              order.status == 'in_progress'))
                        const PopupMenuItem(
                          value: 'approval_pending',
                          child: Text('Onay Bekliyor'),
                        ),
                      if (showEdit && order.status == 'approval_pending')
                        const PopupMenuItem(
                          value: 'mark_open',
                          child: Text('Açığa Al'),
                        ),
                      if (showCancel)
                        const PopupMenuItem(value: 'cancel', child: Text('İptal Et')),
                      if (showToggleActive)
                        PopupMenuItem(
                          value: 'toggle',
                          child: Text(order.isActive ? 'Pasife Al' : 'Aktifleştir'),
                        ),
                      if (showDelete)
                        const PopupMenuItem(value: 'delete', child: Text('Sil')),
                    ],
                    onSelected: (value) {
                      switch (value) {
                        case 'detail':
                          onOpen();
                          break;
                        case 'edit':
                          onEdit?.call();
                          break;
                        case 'approval_pending':
                          onApprovalPending();
                          break;
                        case 'mark_open':
                          onMarkOpen();
                          break;
                        case 'cancel':
                          onCancel();
                          break;
                        case 'toggle':
                          onToggleActive();
                          break;
                        case 'delete':
                          onDelete();
                          break;
                      }
                    },
                  ),
                ],
              ),
              Gap(compact ? 4 : 10),
              Container(
                height: compact ? 3 : 6,
                width: compact ? 40 : 56,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              Gap(compact ? 4 : 10),
              Text(
                customerName.isNotEmpty ? customerName : '—',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontSize: compact ? 13 : null,
                      fontWeight: FontWeight.w900,
                      color: primaryTextColor,
                    ),
              ),
              if (assignedName.isNotEmpty) ...[
                Gap(compact ? 2 : 4),
                Text(
                  assignedName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: (muted ?? const TextStyle()).copyWith(
                    fontSize: compact ? 11 : null,
                    fontWeight: FontWeight.w700,
                    color: mutedTextColor,
                  ),
                ),
              ],
              Gap(compact ? 2 : 6),
              Text(
                order.title,
                maxLines: compact ? 1 : 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: compact ? 12 : null,
                      fontWeight: FontWeight.w700,
                      color: primaryTextColor,
                      decoration: order.isActive ? null : TextDecoration.lineThrough,
                    ),
              ),
              if ((order.description ?? '').trim().isNotEmpty) ...[
                Gap(compact ? 2 : 6),
                Text(
                  (order.description ?? '').trim(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
              if (compact && scheduled != null) ...[
                const Gap(3),
                Text(
                  'PLAN: $scheduled',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w900,
                      ),
                ),
              ],
              Gap(compact ? 2 : 6),
              if (!compact && branchName.isNotEmpty)
                Text(
                  branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              if (compact) ...[
                if (typeName.isNotEmpty) ...[
                  const Gap(2),
                  infoLine('Tip', typeName),
                ],
                if (city.isNotEmpty) ...[
                  const Gap(2),
                  infoLine('Şehir', city),
                ],
                if (address.isNotEmpty) ...[
                  const Gap(2),
                  infoLine('Adres', address),
                ],
                if (contactPhone.isNotEmpty) ...[
                  const Gap(2),
                  infoLine('İrtibat', contactPhone),
                ],
              ] else if (meta.trim().isNotEmpty) ...[
                const Gap(4),
                Text(
                  meta,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: muted,
                ),
              ],
              if (!compact) ...[
                const Spacer(),
                if (scheduled != null)
                  Text(
                    'Plan: $scheduled',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: statusColor,
                          fontWeight: FontWeight.w800,
                        ),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ReorderableWorkOrdersGrid extends StatefulWidget {
  const _ReorderableWorkOrdersGrid({
    required this.items,
    required this.openIndexMap,
    required this.onReorder,
    required this.onOpen,
    required this.onEdit,
    required this.onApprovalPending,
    required this.onMarkOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
    required this.showEdit,
    required this.showCancel,
    required this.showToggleActive,
    required this.showDelete,
  });

  final List<WorkOrder> items;
  final Map<String, int> openIndexMap;
  final ValueChanged<List<WorkOrder>> onReorder;
  final ValueChanged<WorkOrder> onOpen;
  final ValueChanged<WorkOrder> onEdit;
  final ValueChanged<WorkOrder> onApprovalPending;
  final ValueChanged<WorkOrder> onMarkOpen;
  final ValueChanged<WorkOrder> onCancel;
  final ValueChanged<WorkOrder> onToggleActive;
  final ValueChanged<WorkOrder> onDelete;
  final bool showEdit;
  final bool showCancel;
  final bool showToggleActive;
  final bool showDelete;

  @override
  State<_ReorderableWorkOrdersGrid> createState() =>
      _ReorderableWorkOrdersGridState();
}

class _ReorderableWorkOrdersGridState extends State<_ReorderableWorkOrdersGrid> {
  late List<WorkOrder> _items;
  String? _draggingId;

  @override
  void initState() {
    super.initState();
    _items = [...widget.items];
  }

  @override
  void didUpdateWidget(covariant _ReorderableWorkOrdersGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_draggingId != null) return;
    _items = [...widget.items];
  }

  void _move(String fromId, String toId) {
    if (fromId == toId) return;
    final fromIndex = _items.indexWhere((e) => e.id == fromId);
    final toIndex = _items.indexWhere((e) => e.id == toId);
    if (fromIndex < 0 || toIndex < 0) return;
    final next = [..._items];
    final item = next.removeAt(fromIndex);
    next.insert(toIndex, item);
    setState(() => _items = next);
    widget.onReorder(next);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final maxColumns = width < 520
            ? 2
            : width < 820
                ? 3
                : 6;
        final targetTileWidth = width < 520
            ? 170.0
            : width < 820
                ? 200.0
                : 220.0;
        final crossAxisCount = (width / targetTileWidth).floor().clamp(2, maxColumns);
        final childAspectRatio = width < 520
            ? 0.74
            : width < 1000
                ? 0.98
                : 1.18;
        return GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 120),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: _items.length,
          itemBuilder: (context, index) {
            final order = _items[index];
            final indexNumber = widget.openIndexMap[order.id];
            return DragTarget<String>(
              onWillAcceptWithDetails: (details) {
                final fromId = details.data;
                return fromId != order.id;
              },
              onAcceptWithDetails: (details) {
                _move(details.data, order.id);
              },
              builder: (context, candidateData, rejectedData) {
                final highlight = candidateData.isNotEmpty;
                final card = _WorkOrderGridCard(
                  order: order,
                  indexNumber: indexNumber,
                  colorIndex: index,
                  onOpen: () => widget.onOpen(order),
                  onEdit: widget.showEdit ? () => widget.onEdit(order) : null,
                  onApprovalPending: () => widget.onApprovalPending(order),
                  onMarkOpen: () => widget.onMarkOpen(order),
                  onCancel: () => widget.onCancel(order),
                  onToggleActive: () => widget.onToggleActive(order),
                  onDelete: () => widget.onDelete(order),
                  showEdit: widget.showEdit,
                  showCancel: widget.showCancel,
                  showToggleActive: widget.showToggleActive,
                  showDelete: widget.showDelete,
                );

                final draggableChild = AnimatedScale(
                  duration: const Duration(milliseconds: 120),
                  scale: highlight ? 0.98 : 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                      border: highlight
                          ? Border.all(
                              color: AppTheme.primary.withValues(alpha: 0.5),
                              width: 2,
                            )
                          : null,
                    ),
                    child: card,
                  ),
                );

                final feedback = ConstrainedBox(
                  constraints:
                      const BoxConstraints.tightFor(width: 240, height: 190),
                  child: Material(
                    color: Colors.transparent,
                    child: Opacity(
                      opacity: 0.95,
                      child: _WorkOrderGridCard(
                        order: order,
                        indexNumber: indexNumber,
                        colorIndex: index,
                        onOpen: () {},
                        onEdit: null,
                        onApprovalPending: () {},
                        onMarkOpen: () {},
                        onCancel: () {},
                        onToggleActive: () {},
                        onDelete: () {},
                        showEdit: false,
                        showCancel: false,
                        showToggleActive: false,
                        showDelete: false,
                      ),
                    ),
                  ),
                );

                final childWhenDragging = Opacity(opacity: 0.35, child: card);

                if (kIsWeb) {
                  return Draggable<String>(
                    data: order.id,
                    onDragStarted: () => setState(() => _draggingId = order.id),
                    onDragEnd: (_) => setState(() => _draggingId = null),
                    feedback: feedback,
                    childWhenDragging: childWhenDragging,
                    child: draggableChild,
                  );
                }

                return LongPressDraggable<String>(
                  data: order.id,
                  onDragStarted: () => setState(() => _draggingId = order.id),
                  onDraggableCanceled: (velocity, offset) =>
                      setState(() => _draggingId = null),
                  onDragEnd: (_) => setState(() => _draggingId = null),
                  feedback: feedback,
                  childWhenDragging: childWhenDragging,
                  child: draggableChild,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _WorkOrderCard extends ConsumerWidget {
  const _WorkOrderCard({
    super.key,
    required this.order,
    required this.indexNumber,
    required this.reorderIndex,
    required this.reorderable,
    required this.onOpen,
    required this.onEdit,
    required this.onApprovalPending,
    required this.onMarkOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
    required this.showEdit,
    required this.showCancel,
    required this.showToggleActive,
    required this.showDelete,
  });

  final WorkOrder order;
  final int? indexNumber;
  final int reorderIndex;
  final bool reorderable;
  final VoidCallback onOpen;
  final VoidCallback? onEdit;
  final VoidCallback onApprovalPending;
  final VoidCallback onMarkOpen;
  final VoidCallback onCancel;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;
  final bool showEdit;
  final bool showCancel;
  final bool showToggleActive;
  final bool showDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolver =
        ref.watch(workOrderRegionThemeProvider).value ??
        WorkOrderRegionThemeResolver.defaults();
    final scheduled = order.scheduledDate == null
        ? null
        : DateFormat('d MMM y HH:mm', 'tr_TR')
            .format(AppTime.toTr(order.scheduledDate!));

    final line1 = [
      order.customerName?.trim().isNotEmpty ?? false
          ? order.customerName!.trim()
          : null,
      order.branchName?.trim().isNotEmpty ?? false
          ? order.branchName!.trim()
          : null,
    ].whereType<String>().join(' • ');

    final meta = [
      order.workOrderTypeName?.trim().isNotEmpty ?? false
          ? order.workOrderTypeName!.trim()
          : null,
      order.city?.trim().isNotEmpty ?? false ? order.city!.trim() : null,
      order.contactPhone?.trim().isNotEmpty ?? false
          ? order.contactPhone!.trim()
          : null,
    ].whereType<String>().join(' • ');

    final statusColor = _statusColor(order.status);
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppTheme.textMuted);

    final openBackgrounds = [
      const Color(0xFFF0F9FF),
      const Color(0xFFECFDF5),
      const Color(0xFFFFFBEB),
      const Color(0xFFFDF2F8),
      const Color(0xFFF5F3FF),
    ];
    final backgroundColor =
        _cityBackgroundColor(order.city, resolver: resolver) ??
        (order.status == 'open'
            ? openBackgrounds[reorderIndex % openBackgrounds.length]
            : null);
    final isDarkCard = backgroundColor != null && backgroundColor.computeLuminance() < 0.42;
    final primaryTextColor = isDarkCard ? Colors.white : null;
    final iconColor = isDarkCard ? Colors.white.withValues(alpha: 0.86) : null;
    final accent = _cityAccentColor(
      order.city,
      fallbackIndex: reorderIndex,
      resolver: resolver,
    );

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(14),
      color: backgroundColor,
      borderColor: accent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 54,
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.75),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const Gap(12),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDarkCard
                  ? Colors.white.withValues(alpha: 0.14)
                  : accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isDarkCard
                    ? Colors.white.withValues(alpha: 0.24)
                    : accent.withValues(alpha: 0.22),
              ),
            ),
            child: Center(
              child: Text(
                indexNumber?.toString() ?? _shortId(order.id),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDarkCard ? Colors.white : accent,
                    ),
              ),
            ),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        order.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: primaryTextColor,
                              decoration: order.isActive
                                  ? null
                                  : TextDecoration.lineThrough,
                            ),
                      ),
                    ),
                    const Gap(10),
                    _statusBadge(order.status),
                  ],
                ),
                const Gap(6),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (order.paymentRequired != null)
                      _InfoChip(
                        text: order.paymentRequired!
                            ? '₺ Ödeme Alınacak'
                            : '₺ Ödeme Yok',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: order.paymentRequired!
                                  ? const Color(0xFF16A34A)
                                  : const Color(0xFFDC2626),
                              fontWeight: FontWeight.w900,
                            ),
                      ),
                    if (line1.trim().isNotEmpty)
                      _InfoChip(text: line1, style: muted),
                    if ((order.assignedPersonnelName ?? '').trim().isNotEmpty)
                      _InfoChip(
                        text:
                            'Atanan: ${(order.assignedPersonnelName ?? '').trim()}',
                        style: muted,
                      ),
                    if (meta.trim().isNotEmpty) _InfoChip(text: meta, style: muted),
                    if (scheduled != null)
                      _InfoChip(text: 'Plan: $scheduled', style: muted),
                    if ((order.description ?? '').trim().isNotEmpty)
                      _InfoChip(
                        text: (order.description ?? '').trim(),
                        style: muted,
                      ),
                  ],
                ),
              ],
            ),
          ),
          if (reorderable) ...[
            const Gap(10),
            (kIsWeb ? ReorderableDragStartListener.new : ReorderableDelayedDragStartListener.new)(
              index: reorderIndex,
              child: const SizedBox(
                width: 44,
                height: 44,
                child: Center(child: Icon(Icons.drag_handle_rounded)),
              ),
            ),
          ] else ...[
            const Gap(10),
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'detail', child: Text('Detay')),
                if (showEdit)
                  const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                if (showEdit &&
                    (order.status == 'open' || order.status == 'in_progress'))
                  const PopupMenuItem(
                    value: 'approval_pending',
                    child: Text('Onay Bekliyor'),
                  ),
                if (showEdit && order.status == 'approval_pending')
                  const PopupMenuItem(
                    value: 'mark_open',
                    child: Text('Açığa Al'),
                  ),
                if (showCancel)
                  const PopupMenuItem(value: 'cancel', child: Text('İptal Et')),
                if (showToggleActive)
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(order.isActive ? 'Pasife Al' : 'Aktifleştir'),
                  ),
                if (showDelete)
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Sil'),
                  ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'detail':
                    onOpen();
                    break;
                  case 'edit':
                    onEdit?.call();
                    break;
                  case 'approval_pending':
                    onApprovalPending();
                    break;
                  case 'mark_open':
                    onMarkOpen();
                    break;
                  case 'cancel':
                    onCancel();
                    break;
                  case 'toggle':
                    onToggleActive();
                    break;
                  case 'delete':
                    onDelete();
                    break;
                }
              },
              icon: Icon(Icons.more_horiz_rounded, color: iconColor),
            ),
          ]
        ],
      ),
    );
  }
}

Color _statusColor(String status) {
  switch (status) {
    case 'open':
      return const Color(0xFFF59E0B);
    case 'in_progress':
      return const Color(0xFF2563EB);
    case 'approval_pending':
      return const Color(0xFF7C3AED);
    case 'done':
      return const Color(0xFF16A34A);
    case 'cancelled':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF94A3B8);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.text, required this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style,
        ),
      ),
    );
  }
}
