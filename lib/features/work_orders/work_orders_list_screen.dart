import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_create_dialog.dart';
import 'work_order_detail_sheet.dart';
import 'work_order_model.dart';
import 'work_orders_providers.dart';

String _shortId(String id) {
  final trimmed = id.trim();
  if (trimmed.length <= 6) return trimmed;
  return trimmed.substring(0, 6);
}

Widget _statusBadge(String status) {
  switch (status) {
    case 'open':
      return const AppBadge(label: 'BEKLEYEN', tone: AppBadgeTone.warning);
    case 'in_progress':
      return const AppBadge(label: 'YAPILIYOR', tone: AppBadgeTone.primary);
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
    const allowedStatuses = {'all', 'open', 'in_progress', 'done', 'cancelled'};
    if (!allowedStatuses.contains(_statusFilter)) {
      _statusFilter = 'all';
    }
    if (_statusFilter != 'open') _reorderMode = false;

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: 'Tüm iş emirlerini tek ekranda arayın ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.read(workOrdersBoardProvider.notifier).refresh(),
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
          onPressed: () async {
            await showCreateWorkOrderDialog(context, ref);
            ref.read(workOrdersBoardProvider.notifier).refresh();
          },
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

          final search = _searchController.text.trim().toLowerCase();
          final filtered = items.where((item) {
            if (!_showPassive && !item.isActive) return false;
            if (_statusFilter != 'all' && item.status != _statusFilter) {
              return false;
            }
            if (_fromDate != null) {
              final d = item.createdAt ?? item.scheduledDate;
              if (d == null) return false;
              final start = DateTime(_fromDate!.year, _fromDate!.month, _fromDate!.day);
              if (d.isBefore(start)) return false;
            }
            if (_toDate != null) {
              final d = item.createdAt ?? item.scheduledDate;
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
                                      label: 'Yapılıyor',
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
                            if (next == null || next.trim().isEmpty) return;
                            setState(() => _statusFilter = next.trim());
                          },
                        ),
                    if (_statusFilter == 'open')
                      FilledButton.tonalIcon(
                        onPressed: () => setState(() => _reorderMode = !_reorderMode),
                        icon: Icon(
                          _reorderMode
                              ? Icons.check_circle_outline_rounded
                              : Icons.drag_handle_rounded,
                          size: 18,
                        ),
                        label: Text(
                          _reorderMode ? 'Sıralama: Açık' : 'Sıralama: Kapalı',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF0EA5E9).withValues(alpha: 0.12),
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
                          initialDate: _toDate ?? (_fromDate ?? DateTime.now()),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked == null) return;
                        setState(() => _toDate = picked);
                      },
                      icon: const Icon(Icons.event_available_rounded, size: 18),
                      label: Text(
                        _toDate == null
                            ? 'Bitiş'
                            : DateFormat('y-MM-dd').format(_toDate!),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => setState(() => _showPassive = !_showPassive),
                      icon: const Icon(Icons.visibility_rounded, size: 18),
                      label: Text(_showPassive ? 'Kayıt: Tümü' : 'Kayıt: Aktif'),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF16A34A).withValues(alpha: 0.12),
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
              ),
              const Gap(12),
              Expanded(
                child: filtered.isEmpty
                    ? AppCard(
                        child: Center(
                          child: Text(
                            'Kayıt bulunamadı.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                        ),
                      )
                    : _WorkOrdersList(
                        items: filtered,
                        canReorder:
                            _reorderMode &&
                            _statusFilter == 'open' &&
                            search.trim().isEmpty,
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
                        onCancel: (order) {
                          ref
                              .read(workOrdersBoardProvider.notifier)
                              .updateStatus(workOrderId: order.id, newStatus: 'cancelled');
                        },
                        onToggleActive: (order) {
                          ref
                              .read(workOrdersBoardProvider.notifier)
                              .setActive(workOrderId: order.id, isActive: !order.isActive);
                        },
                        onDelete: (order) async {
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
                      ),
              ),
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
    required this.items,
    required this.canReorder,
    required this.onReorder,
    required this.onOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
  });

  final List<WorkOrder> items;
  final bool canReorder;
  final ValueChanged<List<WorkOrder>> onReorder;
  final ValueChanged<WorkOrder> onOpen;
  final ValueChanged<WorkOrder> onCancel;
  final ValueChanged<WorkOrder> onToggleActive;
  final ValueChanged<WorkOrder> onDelete;

  @override
  Widget build(BuildContext context) {
    final sorted = [...items]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    if (canReorder) {
      return ReorderableListView.builder(
        buildDefaultDragHandles: false,
        padding: EdgeInsets.zero,
        itemCount: sorted.length,
        onReorder: (oldIndex, newIndex) {
          if (newIndex > oldIndex) newIndex -= 1;
          final next = [...sorted];
          final item = next.removeAt(oldIndex);
          next.insert(newIndex, item);
          onReorder(next);
        },
        itemBuilder: (context, index) {
          final order = sorted[index];
          return _WorkOrderCard(
            key: ValueKey('wo:${order.id}'),
            order: order,
            indexNumber: index + 1,
            reorderIndex: index,
            reorderable: true,
            onOpen: () => onOpen(order),
            onCancel: () => onCancel(order),
            onToggleActive: () => onToggleActive(order),
            onDelete: () => onDelete(order),
          );
        },
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: sorted.length,
      separatorBuilder: (context, index) => const Gap(10),
      itemBuilder: (context, index) {
        final order = sorted[index];
        final indexNumber = order.status == 'open' ? order.sortOrder + 1 : null;
        return _WorkOrderCard(
          order: order,
          indexNumber: indexNumber,
          reorderIndex: index,
          reorderable: false,
          onOpen: () => onOpen(order),
          onCancel: () => onCancel(order),
          onToggleActive: () => onToggleActive(order),
          onDelete: () => onDelete(order),
        );
      },
    );
  }
}

class _WorkOrderCard extends StatelessWidget {
  const _WorkOrderCard({
    super.key,
    required this.order,
    required this.indexNumber,
    required this.reorderIndex,
    required this.reorderable,
    required this.onOpen,
    required this.onCancel,
    required this.onToggleActive,
    required this.onDelete,
  });

  final WorkOrder order;
  final int? indexNumber;
  final int reorderIndex;
  final bool reorderable;
  final VoidCallback onOpen;
  final VoidCallback onCancel;
  final VoidCallback onToggleActive;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final scheduled = order.scheduledDate == null
        ? null
        : DateFormat('d MMM y HH:mm', 'tr_TR')
            .format(order.scheduledDate!.toLocal());

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
    final accent = _rowAccentColor(reorderIndex);
    final muted = Theme.of(context)
        .textTheme
        .bodySmall
        ?.copyWith(color: AppTheme.textMuted);

    return AppCard(
      onTap: onOpen,
      padding: const EdgeInsets.all(14),
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
              color: accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accent.withValues(alpha: 0.22)),
            ),
            child: Center(
              child: Text(
                indexNumber?.toString() ?? _shortId(order.id),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: accent,
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
            ReorderableDelayedDragStartListener(
              index: reorderIndex,
              child: const Icon(Icons.drag_handle_rounded),
            ),
          ] else ...[
            const Gap(10),
            PopupMenuButton<String>(
              itemBuilder: (context) => [
                const PopupMenuItem(value: 'open', child: Text('Düzenle')),
                const PopupMenuItem(value: 'cancel', child: Text('İptal Et')),
                PopupMenuItem(
                  value: 'toggle',
                  child: Text(order.isActive ? 'Pasife Al' : 'Aktifleştir'),
                ),
                const PopupMenuItem(
                  value: 'delete',
                  child: Text('Sil'),
                ),
              ],
              onSelected: (value) {
                switch (value) {
                  case 'open':
                    onOpen();
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
    case 'done':
      return const Color(0xFF16A34A);
    case 'cancelled':
      return const Color(0xFFDC2626);
    default:
      return const Color(0xFF94A3B8);
  }
}

Color _rowAccentColor(int index) {
  const palette = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFF59E0B),
    Color(0xFF7C3AED),
    Color(0xFFEF4444),
    Color(0xFF0EA5E9),
  ];
  return palette[index % palette.length];
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
