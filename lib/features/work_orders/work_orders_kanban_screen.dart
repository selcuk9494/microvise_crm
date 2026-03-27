import 'package:intl/intl.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_create_dialog.dart';
import 'work_order_model.dart';
import 'work_order_close_sheet.dart';
import 'work_order_detail_sheet.dart';
import 'work_orders_providers.dart';

class WorkOrdersKanbanScreen extends ConsumerStatefulWidget {
  const WorkOrdersKanbanScreen({super.key});

  @override
  ConsumerState<WorkOrdersKanbanScreen> createState() =>
      _WorkOrdersKanbanScreenState();
}

class _WorkOrderMetaChip extends StatelessWidget {
  const _WorkOrderMetaChip({
    required this.icon,
    required this.label,
    this.emphasize = false,
  });

  final IconData icon;
  final String label;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: emphasize
            ? AppTheme.primary.withValues(alpha: 0.08)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: emphasize
              ? AppTheme.primary.withValues(alpha: 0.18)
              : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: emphasize ? AppTheme.primary : const Color(0xFF64748B),
          ),
          const Gap(6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: emphasize ? AppTheme.primary : const Color(0xFF475569),
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkOrdersKanbanScreenState
    extends ConsumerState<WorkOrdersKanbanScreen> {
  bool _handledCreateQuery = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    if (_handledCreateQuery) return;
    final uri = GoRouterState.of(context).uri;
    final create = uri.queryParameters['yeni'] == '1';
    if (!create) return;

    _handledCreateQuery = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      context.go('/is-emirleri');
      await showCreateWorkOrderDialog(context, ref);
      ref.read(workOrdersBoardProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(workOrdersBoardProvider);

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: 'Açık / Devam Ediyor / Kapalı filtreleri ile tek sayfa.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.read(workOrdersBoardProvider.notifier).refresh(),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
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
        data: (items) => _WorkOrdersStatusView(items: items),
        loading: () => Skeletonizer(
          enabled: true,
          child: _WorkOrdersStatusView(
            items: const [
              WorkOrder(
                id: '1',
                title: 'Hat yenileme / ACME Teknoloji',
                customerId: 'c1',
                customerName: 'ACME Teknoloji',
                status: 'open',
                branchId: null,
                assignedTo: null,
                scheduledDate: null,
                isActive: true,
              ),
              WorkOrder(
                id: '2',
                title: 'Servis kapanış / Orion Endüstri',
                customerId: 'c2',
                customerName: 'Orion Endüstri',
                status: 'in_progress',
                branchId: null,
                assignedTo: null,
                scheduledDate: null,
                isActive: true,
              ),
              WorkOrder(
                id: '3',
                title: 'Lisans uzatma / Nova Yazılım',
                customerId: 'c3',
                customerName: 'Nova Yazılım',
                status: 'done',
                branchId: null,
                assignedTo: null,
                scheduledDate: null,
                isActive: true,
              ),
            ],
          ),
        ),
        error: (error, stackTrace) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Text(
              'İş emirleri yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
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

class _WorkOrdersStatusView extends ConsumerWidget {
  const _WorkOrdersStatusView({required this.items});

  final List<WorkOrder> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final open = items.where((e) => e.status == 'open').toList(growable: false);
    final inProgress = items
        .where((e) => e.status == 'in_progress')
        .toList(growable: false);
    final done = items.where((e) => e.status == 'done').toList(growable: false);

    return DefaultTabController(
      length: 3,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: Column(
          children: [
            const TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              tabs: [
                Tab(text: 'Açık'),
                Tab(text: 'Devam Ediyor'),
                Tab(text: 'Kapalı'),
              ],
            ),
            const Divider(height: 1),
            SizedBox(
              height: 720,
              child: TabBarView(
                children: [
                  _WorkOrdersList(status: 'open', items: open),
                  _WorkOrdersList(status: 'in_progress', items: inProgress),
                  _WorkOrdersList(status: 'done', items: done),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkOrdersList extends ConsumerWidget {
  const _WorkOrdersList({required this.status, required this.items});

  final String status;
  final List<WorkOrder> items;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'Kayıt yok.',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: const Color(0xFF64748B)),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(14),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Gap(10),
      itemBuilder: (context, index) => _WorkOrderListTile(order: items[index]),
    );
  }
}

class _WorkOrderListTile extends ConsumerStatefulWidget {
  const _WorkOrderListTile({required this.order});

  final WorkOrder order;

  @override
  ConsumerState<_WorkOrderListTile> createState() => _WorkOrderListTileState();
}

class _WorkOrderListTileState extends ConsumerState<_WorkOrderListTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final w = widget.order;
    final scheduled = w.scheduledDate == null
        ? null
        : DateFormat('d MMM y', 'tr_TR').format(w.scheduledDate!);

    final tone = switch (w.status) {
      'open' => AppBadgeTone.warning,
      'in_progress' => AppBadgeTone.primary,
      'done' => AppBadgeTone.success,
      _ => AppBadgeTone.neutral,
    };

    final statusLabel = switch (w.status) {
      'open' => 'Açık',
      'in_progress' => 'Devam',
      'done' => 'Kapalı',
      _ => '—',
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () async {
          await showWorkOrderDetailSheet(context, ref, order: w);
          ref.read(workOrdersBoardProvider.notifier).refresh();
        },
        child: AnimatedContainer(
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      w.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        decoration: w.isActive
                            ? null
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _WorkOrderMetaChip(
                          icon: Icons.business_rounded,
                          label: w.customerName ?? '—',
                        ),
                        if (w.workOrderTypeName?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.category_rounded,
                            label: w.workOrderTypeName!,
                            emphasize: true,
                          ),
                        if (w.branchName?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.account_tree_rounded,
                            label: w.branchName!,
                          ),
                        if (scheduled != null)
                          _WorkOrderMetaChip(
                            icon: Icons.calendar_today_rounded,
                            label: scheduled,
                          ),
                        if (w.contactPhone?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.phone_rounded,
                            label: w.contactPhone!,
                          ),
                        if (w.locationLink?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.link_rounded,
                            label: 'Konum',
                          ),
                      ],
                    ),
                    if (w.description?.trim().isNotEmpty ?? false) ...[
                      const Gap(8),
                      Text(
                        w.description!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.4,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(10),
              AppBadge(label: statusLabel, tone: tone),
            ],
          ),
        ),
      ),
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
          Row(
            children: [
              Expanded(
                child: Text(
                  w.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: w.isActive
                        ? TextDecoration.none
                        : TextDecoration.lineThrough,
                  ),
                ),
              ),
              const Gap(8),
              if (w.status == 'done')
                const Icon(
                  Icons.check_circle_rounded,
                  color: AppTheme.success,
                  size: 18,
                )
              else
                const Icon(
                  Icons.open_in_new_rounded,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
            ],
          ),
          const Gap(6),
          Text(
            w.customerName ?? '—',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
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
        child: Consumer(
          builder: (context, ref, _) => InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () async {
              if (w.status == 'done') return;
              await showWorkOrderCloseSheet(context, ref, order: w);
              ref.read(workOrdersBoardProvider.notifier).refresh();
            },
            child: card,
          ),
        ),
      ),
    );
  }
}
