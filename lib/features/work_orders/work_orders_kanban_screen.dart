import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_model.dart';
import 'work_orders_providers.dart';

class WorkOrdersKanbanScreen extends ConsumerWidget {
  const WorkOrdersKanbanScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final boardAsync = ref.watch(workOrdersBoardProvider);

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: 'Kanban akışı: Açık → Devam Ediyor → Tamamlandı',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.read(workOrdersBoardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni İş Emri'),
        ),
      ],
      body: boardAsync.when(
        data: (items) => _KanbanBoard(items: items),
        loading: () => Skeletonizer(
          enabled: true,
          child: _KanbanBoard(
            items: const [
              WorkOrder(
                id: '1',
                title: 'Hat yenileme / ACME Teknoloji',
                customerName: 'ACME Teknoloji',
                status: 'open',
                isActive: true,
              ),
              WorkOrder(
                id: '2',
                title: 'Servis kapanış / Orion Endüstri',
                customerName: 'Orion Endüstri',
                status: 'in_progress',
                isActive: true,
              ),
              WorkOrder(
                id: '3',
                title: 'Lisans uzatma / Nova Yazılım',
                customerName: 'Nova Yazılım',
                status: 'done',
                isActive: true,
              ),
            ],
          ),
        ),
        error: (_, __) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'İş emirleri yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
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

class _KanbanBoard extends ConsumerWidget {
  const _KanbanBoard({required this.items});

  final List<WorkOrder> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = items.where((e) => e.status == 'open').toList();
    final inProgress = items.where((e) => e.status == 'in_progress').toList();
    final done = items.where((e) => e.status == 'done').toList();

    return SizedBox(
      height: 700,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          const Gap(2),
          _KanbanColumn(
            title: 'Açık',
            tone: AppBadgeTone.warning,
            status: 'open',
            items: open,
          ),
          const Gap(12),
          _KanbanColumn(
            title: 'Devam Ediyor',
            tone: AppBadgeTone.primary,
            status: 'in_progress',
            items: inProgress,
          ),
          const Gap(12),
          _KanbanColumn(
            title: 'Tamamlandı',
            tone: AppBadgeTone.success,
            status: 'done',
            items: done,
          ),
          const Gap(2),
        ],
      ),
    );
  }
}

class _KanbanColumn extends ConsumerWidget {
  const _KanbanColumn({
    required this.title,
    required this.tone,
    required this.status,
    required this.items,
  });

  final String title;
  final AppBadgeTone tone;
  final String status;
  final List<WorkOrder> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DragTarget<WorkOrder>(
      onWillAcceptWithDetails: (details) => details.data.status != status,
      onAcceptWithDetails: (details) async {
        await ref.read(workOrdersBoardProvider.notifier).updateStatus(
              workOrderId: details.data.id,
              newStatus: status,
            );
      },
      builder: (context, candidateData, rejectedData) {
        final isOver = candidateData.isNotEmpty;
        return SizedBox(
          width: 360,
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    AppBadge(label: items.length.toString(), tone: tone),
                  ],
                ),
                const Gap(10),
                Expanded(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    curve: Curves.easeOut,
                    decoration: BoxDecoration(
                      color: isOver
                          ? AppTheme.primary.withValues(alpha: 0.06)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isOver
                            ? AppTheme.primary.withValues(alpha: 0.22)
                            : AppTheme.border,
                      ),
                    ),
                    padding: const EdgeInsets.all(10),
                    child: items.isEmpty
                        ? Center(
                            child: Text(
                              'Bu sütunda kayıt yok.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: const Color(0xFF64748B)),
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (_, __) => const Gap(10),
                            itemBuilder: (context, index) {
                              final w = items[index];
                              return _WorkOrderCard(order: w);
                            },
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WorkOrderCard extends StatefulWidget {
  const _WorkOrderCard({required this.order});

  final WorkOrder order;

  @override
  State<_WorkOrderCard> createState() => _WorkOrderCardState();
}

class _WorkOrderCardState extends State<_WorkOrderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.order;
    final card = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      curve: Curves.easeOut,
      transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppTheme.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            w.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  decoration:
                      w.isActive ? TextDecoration.none : TextDecoration.lineThrough,
                ),
          ),
          const Gap(6),
          Text(
            w.customerName ?? '—',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF64748B)),
          ),
        ],
      ),
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Draggable<WorkOrder>(
        data: w,
        feedback: SizedBox(width: 340, child: Material(child: card)),
        childWhenDragging: Opacity(opacity: 0.55, child: card),
        child: card,
      ),
    );
  }
}
