import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_create_dialog.dart';
import 'work_order_model.dart';
import 'work_order_detail_sheet.dart';
import 'work_orders_providers.dart';

class WorkOrdersListScreen extends ConsumerStatefulWidget {
  const WorkOrdersListScreen({super.key});

  @override
  ConsumerState<WorkOrdersListScreen> createState() =>
      _WorkOrdersListScreenState();
}

class _WorkOrdersListScreenState extends ConsumerState<WorkOrdersListScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  bool _handledCreateQuery = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

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
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 720;

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: 'Tüm iş emirlerini yönetin',
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
      body: Column(
        children: [
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppTheme.border),
            ),
            child: TabBar(
              controller: _tabController,
              isScrollable: isCompact,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
              labelPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 16 : 24,
              ),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.radio_button_unchecked_rounded,
                        size: 16,
                      ),
                      const Gap(8),
                      const Text('Açık'),
                      boardAsync.whenOrNull(
                            data: (items) {
                              final count = items
                                  .where((e) => e.status == 'open')
                                  .length;
                              return count > 0
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: AppBadge(
                                        label: count.toString(),
                                        tone: AppBadgeTone.warning,
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            },
                          ) ??
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.timelapse_rounded, size: 16),
                      const Gap(8),
                      const Text('Devam Ediyor'),
                      boardAsync.whenOrNull(
                            data: (items) {
                              final count = items
                                  .where((e) => e.status == 'in_progress')
                                  .length;
                              return count > 0
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: AppBadge(
                                        label: count.toString(),
                                        tone: AppBadgeTone.primary,
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            },
                          ) ??
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.check_circle_outline_rounded, size: 16),
                      const Gap(8),
                      const Text('Kapalı'),
                      boardAsync.whenOrNull(
                            data: (items) {
                              final count = items
                                  .where((e) => e.status == 'done')
                                  .length;
                              return count > 0
                                  ? Padding(
                                      padding: const EdgeInsets.only(left: 8),
                                      child: AppBadge(
                                        label: count.toString(),
                                        tone: AppBadgeTone.success,
                                      ),
                                    )
                                  : const SizedBox.shrink();
                            },
                          ) ??
                          const SizedBox.shrink(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Gap(16),
          Expanded(
            child: boardAsync.when(
              data: (items) {
                debugPrint('WorkOrders loaded: ${items.length} items');
                for (final item in items) {
                  debugPrint('  - ${item.title}: status=${item.status}');
                }
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _WorkOrderList(
                      items: items.where((e) => e.status == 'open').toList(),
                      emptyText: 'Açık iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                    ),
                    _WorkOrderList(
                      items: items
                          .where((e) => e.status == 'in_progress')
                          .toList(),
                      emptyText: 'Devam eden iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                    ),
                    _WorkOrderList(
                      items: items.where((e) => e.status == 'done').toList(),
                      emptyText: 'Kapatılmış iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                    ),
                  ],
                );
              },
              loading: () => Skeletonizer(
                enabled: true,
                child: _WorkOrderList(
                  items: [
                    WorkOrder(
                      id: '1',
                      title: 'Örnek iş emri başlığı',
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
                      title: 'Diğer iş emri',
                      customerId: 'c2',
                      customerName: 'Orion Endüstri',
                      status: 'open',
                      branchId: null,
                      assignedTo: null,
                      scheduledDate: null,
                      isActive: true,
                    ),
                  ],
                  emptyText: '',
                  onTap: (_) {},
                ),
              ),
              error: (error, stackTrace) => Center(
                child: AppCard(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Text(
                      'İş emirleri yüklenemedi. Yetki ve bağlantı ayarlarını kontrol edin.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openWorkOrderDetail(WorkOrder order) async {
    await showWorkOrderDetailSheet(context, ref, order: order);
    ref.read(workOrdersBoardProvider.notifier).refresh();
  }
}

class _WorkOrderList extends StatelessWidget {
  const _WorkOrderList({
    required this.items,
    required this.emptyText,
    required this.onTap,
  });

  final List<WorkOrder> items;
  final String emptyText;
  final ValueChanged<WorkOrder> onTap;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.inbox_rounded,
                  size: 48,
                  color: const Color(0xFF94A3B8),
                ),
                const Gap(12),
                Text(
                  emptyText,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      itemCount: items.length,
      separatorBuilder: (context, index) => const Gap(10),
      itemBuilder: (context, index) {
        final order = items[index];
        return _WorkOrderCard(order: order, onTap: () => onTap(order));
      },
    );
  }
}

class _WorkOrderCard extends StatefulWidget {
  const _WorkOrderCard({required this.order, required this.onTap});

  final WorkOrder order;
  final VoidCallback onTap;

  @override
  State<_WorkOrderCard> createState() => _WorkOrderCardState();
}

class _WorkOrderCardState extends State<_WorkOrderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final dateText = order.scheduledDate != null
        ? DateFormat('d MMM y', 'tr_TR').format(order.scheduledDate!)
        : 'Tarih belirlenmedi';

    final (statusLabel, statusTone) = switch (order.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Devam Ediyor', AppBadgeTone.primary),
      'done' => ('Kapalı', AppBadgeTone.success),
      _ => ('Bilinmiyor', AppBadgeTone.neutral),
    };

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.3)
                  : AppTheme.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.08 : 0.04),
                blurRadius: _hovered ? 20 : 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        decoration: order.isActive
                            ? TextDecoration.none
                            : TextDecoration.lineThrough,
                      ),
                    ),
                    const Gap(6),
                    Row(
                      children: [
                        Icon(
                          Icons.business_rounded,
                          size: 14,
                          color: const Color(0xFF64748B),
                        ),
                        const Gap(6),
                        Expanded(
                          child: Text(
                            order.customerName ?? '-',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ),
                      ],
                    ),
                    const Gap(4),
                    Row(
                      children: [
                        Icon(
                          Icons.calendar_today_rounded,
                          size: 14,
                          color: const Color(0xFF94A3B8),
                        ),
                        const Gap(6),
                        Text(
                          dateText,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: const Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  AppBadge(label: statusLabel, tone: statusTone),
                  const Gap(8),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
