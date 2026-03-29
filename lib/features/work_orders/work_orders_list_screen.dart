import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/format/app_date_time.dart';
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
  bool _showPassive = false;
  bool _mobileReorderMode = false;
  DateTime? _closedFilterDate;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _closedFilterDate = normalizeAppDate(appNow());
    _tabController.addListener(_handleTabChanged);
  }

  @override
  void dispose() {
    _tabController.removeListener(_handleTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  void _handleTabChanged() {
    if (!mounted) return;
    setState(() {
      if (_tabController.index != 0) {
        _mobileReorderMode = false;
      }
      if (_tabController.index == 2 && _closedFilterDate == null) {
        _closedFilterDate = normalizeAppDate(appNow());
      }
    });
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
    final height = MediaQuery.sizeOf(context).height;
    final isCompact = width < 720;
    final listHeight = isCompact
        ? (height * 0.72).clamp(440.0, 760.0).toDouble()
        : (height * 0.58).clamp(360.0, 760.0).toDouble();
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDeletePermanently = ref.watch(
      hasActionAccessProvider(kActionDeleteRecords),
    );

    return AppPageLayout(
      title: 'İş Emirleri',
      subtitle: isCompact
          ? 'Açık işleri hızlıca görün, gerekirse sıralama modunu açın.'
          : 'İş emri akışını sıkı ve temiz görünümde yönetin.',
      actions: [
        if (isCompact) ...[
          OutlinedButton(
            onPressed: () =>
                ref.read(workOrdersBoardProvider.notifier).refresh(),
            child: const Icon(Icons.refresh_rounded, size: 20),
          ),
          FilledButton(
            onPressed: () async {
              await showCreateWorkOrderDialog(context, ref);
              ref.read(workOrdersBoardProvider.notifier).refresh();
            },
            child: const Icon(Icons.add_rounded, size: 20),
          ),
        ] else ...[
          OutlinedButton.icon(
            onPressed: () =>
                ref.read(workOrdersBoardProvider.notifier).refresh(),
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
      ],
      body: Column(
        children: [
          if (isCompact)
            boardAsync.when(
              data: (items) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _MobileBoardStrip(items: items, showPassive: _showPassive),
              ),
              loading: () => const SizedBox.shrink(),
              error: (error, stackTrace) => const SizedBox.shrink(),
            ),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                FilterChip(
                  selected: _showPassive,
                  label: const Text('Pasifleri Göster'),
                  avatar: Icon(
                    _showPassive
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    size: 16,
                  ),
                  onSelected: (value) {
                    setState(() => _showPassive = value);
                  },
                ),
              ],
            ),
          ),
          Gap(isCompact ? 8 : 8),
          AppSectionCard(
            padding: const EdgeInsets.all(6),
            child: TabBar(
              controller: _tabController,
              isScrollable: isCompact,
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              tabAlignment: isCompact ? TabAlignment.start : TabAlignment.fill,
              labelPadding: EdgeInsets.symmetric(
                horizontal: isCompact ? 12 : 18,
              ),
              tabs: [
                _StatusTab(
                  label: 'Açık',
                  icon: Icons.radio_button_unchecked_rounded,
                  tone: AppBadgeTone.warning,
                  count: boardAsync.whenOrNull(
                    data: (items) =>
                        items.where((e) => e.status == 'open').length,
                  ),
                ),
                _StatusTab(
                  label: 'Devam Ediyor',
                  icon: Icons.timelapse_rounded,
                  tone: AppBadgeTone.primary,
                  count: boardAsync.whenOrNull(
                    data: (items) =>
                        items.where((e) => e.status == 'in_progress').length,
                  ),
                ),
                _StatusTab(
                  label: 'Kapalı',
                  icon: Icons.check_circle_outline_rounded,
                  tone: AppBadgeTone.success,
                  count: boardAsync.whenOrNull(
                    data: (items) =>
                        items.where((e) => e.status == 'done').length,
                  ),
                ),
              ],
            ),
          ),
          Gap(isCompact ? 10 : 10),
          if (_tabController.index == 2) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Bugün'),
                    selected: _closedFilterDate != null &&
                        normalizeAppDate(_closedFilterDate!) ==
                            normalizeAppDate(appNow()),
                    onSelected: (_) {
                      setState(() {
                        _closedFilterDate = normalizeAppDate(appNow());
                      });
                    },
                  ),
                  ChoiceChip(
                    label: const Text('Tümü'),
                    selected: _closedFilterDate == null,
                    onSelected: (_) {
                      setState(() => _closedFilterDate = null);
                    },
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _closedFilterDate ?? normalizeAppDate(appNow()),
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2100),
                        locale: const Locale('tr', 'TR'),
                      );
                      if (picked == null || !mounted) return;
                      setState(() {
                        _closedFilterDate = normalizeAppDate(picked);
                      });
                    },
                    icon: const Icon(Icons.calendar_month_rounded, size: 16),
                    label: Text(
                      _closedFilterDate == null
                          ? 'Tarih seç'
                          : DateFormat('d MMM y', 'tr_TR').format(_closedFilterDate!),
                    ),
                  ),
                ],
              ),
            ),
            const Gap(10),
          ],
          if (isCompact && _tabController.index == 0) ...[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: () {
                  setState(() {
                    _mobileReorderMode = !_mobileReorderMode;
                  });
                },
                icon: Icon(
                  _mobileReorderMode
                      ? Icons.checklist_rtl_rounded
                      : Icons.drag_indicator_rounded,
                  size: 16,
                ),
                label: Text(
                  _mobileReorderMode ? 'Sıralamayı Bitir' : 'Sıralama Modu',
                ),
              ),
            ),
            const Gap(10),
          ],
          SizedBox(
            height: listHeight,
            child: boardAsync.when(
              data: (items) {
                final visibleItems = items
                    .where((e) => _showPassive || e.isActive)
                    .toList(growable: false);
                final closedFilterDate = _closedFilterDate == null
                    ? null
                    : normalizeAppDate(_closedFilterDate!);
                return TabBarView(
                  controller: _tabController,
                  children: [
                    _WorkOrderList(
                      items: visibleItems
                          .where((e) => e.status == 'open')
                          .toList(),
                      emptyText: _showPassive
                          ? 'Açık veya pasif iş emri bulunmuyor.'
                          : 'Açık iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                      onToggleActive: _setWorkOrderActive,
                      canArchive: canArchive,
                      canDeletePermanently: canDeletePermanently,
                      onDeletePermanently: _deleteWorkOrderPermanently,
                      reorderModeEnabled: !isCompact || _mobileReorderMode,
                    ),
                    _WorkOrderList(
                      items: visibleItems
                          .where((e) => e.status == 'in_progress')
                          .toList(),
                      emptyText: _showPassive
                          ? 'Devam eden veya pasif iş emri bulunmuyor.'
                          : 'Devam eden iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                      onToggleActive: _setWorkOrderActive,
                      canArchive: canArchive,
                      canDeletePermanently: canDeletePermanently,
                      onDeletePermanently: _deleteWorkOrderPermanently,
                      reorderModeEnabled: false,
                    ),
                    _WorkOrderList(
                      items: visibleItems.where((e) {
                        if (e.status != 'done') return false;
                        if (closedFilterDate == null) return true;
                        final candidate = e.closedAt ?? e.createdAt ?? e.scheduledDate;
                        if (candidate == null) return false;
                        return normalizeAppDate(candidate) == closedFilterDate;
                      }).toList(),
                      emptyText: _showPassive
                          ? 'Kapalı veya pasif iş emri bulunmuyor.'
                          : 'Kapatılmış iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                      onToggleActive: _setWorkOrderActive,
                      canArchive: canArchive,
                      canDeletePermanently: canDeletePermanently,
                      onDeletePermanently: _deleteWorkOrderPermanently,
                      reorderModeEnabled: false,
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
                  onToggleActive: (order, active) async {},
                  canArchive: true,
                  canDeletePermanently: true,
                  onDeletePermanently: (order) async {},
                  reorderModeEnabled: false,
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

  Future<void> _setWorkOrderActive(WorkOrder order, bool active) async {
    await ref
        .read(workOrdersBoardProvider.notifier)
        .setActive(workOrderId: order.id, isActive: active);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          active
              ? 'İş emri yeniden aktifleştirildi.'
              : 'İş emri pasife alındı.',
        ),
      ),
    );
  }

  Future<void> _deleteWorkOrderPermanently(WorkOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İş emrini kalıcı sil'),
        content: Text(
          '"${order.title}" kaydı kalıcı olarak silinecek. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kalıcı Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      await client.from('payments').delete().eq('work_order_id', order.id);
      await client.from('work_orders').delete().eq('id', order.id);
      await ref.read(workOrdersBoardProvider.notifier).refresh();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş emri kalıcı olarak silindi.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İş emri silinemedi: $error')),
      );
    }
  }
}

class _WorkOrderList extends StatelessWidget {
  const _WorkOrderList({
    required this.items,
    required this.emptyText,
    required this.onTap,
    required this.onToggleActive,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.onDeletePermanently,
    required this.reorderModeEnabled,
  });

  final List<WorkOrder> items;
  final String emptyText;
  final ValueChanged<WorkOrder> onTap;
  final Future<void> Function(WorkOrder order, bool active) onToggleActive;
  final bool canArchive;
  final bool canDeletePermanently;
  final Future<void> Function(WorkOrder order) onDeletePermanently;
  final bool reorderModeEnabled;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    if (items.isEmpty) {
      return Center(
        child: EmptyStateCard(
          icon: Icons.inbox_rounded,
          title: 'Kayıt bulunamadı',
          message: emptyText,
        ),
      );
    }

    final ref = ProviderScope.containerOf(context);
    final canReorder =
        reorderModeEnabled &&
        items.every((item) => item.status == 'open' && item.isActive);
    if (!canReorder) {
      return ListView.separated(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 0 : 2,
          vertical: 2,
        ),
        itemCount: items.length,
        separatorBuilder: (context, index) => Gap(isMobile ? 8 : 6),
        itemBuilder: (context, index) {
          final order = items[index];
          return _WorkOrderCard(
            order: order,
            onTap: () => onTap(order),
            reorderEnabled: false,
            reorderIndex: index,
            onToggleActive: (active) => onToggleActive(order, active),
            canArchive: canArchive,
            canDeletePermanently: canDeletePermanently,
            onDeletePermanently: () => onDeletePermanently(order),
          );
        },
      );
    }

    return Column(
      children: [
        if (isMobile && reorderModeEnabled)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Yalnızca tutma alanından sürükleyerek sırala.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: const Color(0xFF64748B)),
              ),
            ),
          ),
        Expanded(
          child: ReorderableListView.builder(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 0 : 2,
              vertical: 2,
            ),
            itemCount: items.length,
            buildDefaultDragHandles: false,
            onReorder: (oldIndex, newIndex) async {
              final reordered = [...items];
              if (newIndex > oldIndex) newIndex -= 1;
              final item = reordered.removeAt(oldIndex);
              reordered.insert(newIndex, item);
              await ref
                  .read(workOrdersBoardProvider.notifier)
                  .reorderOpenOrders(reordered);
            },
            itemBuilder: (context, index) {
              final order = items[index];
              return Padding(
                key: ValueKey(order.id),
                padding: EdgeInsets.only(
                  bottom: index == items.length - 1 ? 0 : (isMobile ? 8 : 6),
                ),
                child: _WorkOrderCard(
                  order: order,
                  onTap: () => onTap(order),
                  reorderEnabled: true,
                  reorderIndex: index,
                  onToggleActive: (active) => onToggleActive(order, active),
                  canArchive: canArchive,
                  canDeletePermanently: canDeletePermanently,
                  onDeletePermanently: () => onDeletePermanently(order),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StatusTab extends StatelessWidget {
  const _StatusTab({
    required this.label,
    required this.icon,
    required this.tone,
    required this.count,
  });

  final String label;
  final IconData icon;
  final AppBadgeTone tone;
  final int? count;

  @override
  Widget build(BuildContext context) {
    return Tab(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15),
          const Gap(6),
          Text(label),
          if ((count ?? 0) > 0)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: AppBadge(label: count.toString(), tone: tone),
            ),
        ],
      ),
    );
  }
}

class _WorkOrderCard extends StatefulWidget {
  const _WorkOrderCard({
    required this.order,
    required this.onTap,
    required this.reorderEnabled,
    required this.reorderIndex,
    required this.onToggleActive,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.onDeletePermanently,
  });

  final WorkOrder order;
  final VoidCallback onTap;
  final bool reorderEnabled;
  final int reorderIndex;
  final ValueChanged<bool> onToggleActive;
  final bool canArchive;
  final bool canDeletePermanently;
  final Future<void> Function() onDeletePermanently;

  @override
  State<_WorkOrderCard> createState() => _WorkOrderCardState();
}

class _WorkOrderCardState extends State<_WorkOrderCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    final money = NumberFormat.currency(
      locale: 'tr_TR',
      symbol: '',
      decimalDigits: 2,
    );
    final dateText = order.scheduledDate != null
        ? DateFormat('d MMM y', 'tr_TR').format(order.scheduledDate!)
        : 'Tarih belirlenmedi';

    final (statusLabel, statusTone) = switch (order.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Devam Ediyor', AppBadgeTone.primary),
      'done' => ('Kapalı', AppBadgeTone.success),
      _ => ('Bilinmiyor', AppBadgeTone.neutral),
    };

    if (isMobile) {
      return _MobileWorkOrderCard(
        order: order,
        hovered: _hovered,
        reorderEnabled: widget.reorderEnabled,
        reorderIndex: widget.reorderIndex,
        onTap: widget.onTap,
        onToggleActive: widget.onToggleActive,
        canArchive: widget.canArchive,
        canDeletePermanently: widget.canDeletePermanently,
        onDeletePermanently: widget.onDeletePermanently,
      );
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.surface,
            borderRadius: BorderRadius.circular(isMobile ? 12 : 14),
            border: Border.all(
              color: _hovered
                  ? AppTheme.primary.withValues(alpha: 0.24)
                  : AppTheme.border,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: _hovered ? 0.05 : 0.025),
                blurRadius: _hovered ? 14 : 10,
                offset: const Offset(0, 4),
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
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            order.title,
                            maxLines: isMobile ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  decoration: order.isActive
                                      ? TextDecoration.none
                                      : TextDecoration.lineThrough,
                                ),
                          ),
                        ),
                        if (widget.reorderEnabled)
                          ReorderableDragStartListener(
                            index: widget.reorderIndex,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Icon(
                                Icons.drag_indicator_rounded,
                                size: isMobile ? 18 : 18,
                                color: const Color(0xFF94A3B8),
                              ),
                            ),
                          ),
                      ],
                    ),
                    const Gap(3),
                    if (isMobile &&
                        (order.customerName?.trim().isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text(
                          order.customerName!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: const Color(0xFF64748B),
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              ),
                        ),
                      ),
                    Wrap(
                      spacing: 5,
                      runSpacing: 5,
                      children: [
                        if (!isMobile)
                          _WorkOrderMetaChip(
                            icon: Icons.business_rounded,
                            label: order.customerName ?? '-',
                          ),
                        if (order.city?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.location_city_rounded,
                            label: order.city!,
                            backgroundColor: _cityTone(
                              order.city!,
                            ).withValues(alpha: 0.12),
                            borderColor: _cityTone(
                              order.city!,
                            ).withValues(alpha: 0.24),
                            foregroundColor: _cityTone(order.city!),
                            emphasize: true,
                          ),
                        if (order.workOrderTypeName?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.category_rounded,
                            label: order.workOrderTypeName!,
                            emphasize: true,
                            compact: isMobile,
                          ),
                        if (order.branchName?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.account_tree_rounded,
                            label: order.branchName!,
                            compact: isMobile,
                          ),
                        _WorkOrderMetaChip(
                          icon: Icons.calendar_today_rounded,
                          label: dateText,
                          compact: isMobile,
                        ),
                        if (order.contactPhone?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.phone_rounded,
                            label: order.contactPhone!,
                            compact: isMobile,
                          ),
                        if (order.locationLink?.trim().isNotEmpty ?? false)
                          _WorkOrderMetaChip(
                            icon: Icons.link_rounded,
                            label: 'Konum',
                            compact: isMobile,
                          ),
                        if (order.status == 'done' && order.payments.isNotEmpty)
                          _WorkOrderMetaChip(
                            icon: Icons.payments_rounded,
                            label: _paymentSummary(order, money),
                            backgroundColor: AppTheme.success.withValues(
                              alpha: 0.10,
                            ),
                            borderColor: AppTheme.success.withValues(
                              alpha: 0.18,
                            ),
                            foregroundColor: AppTheme.success,
                            emphasize: true,
                            compact: isMobile,
                          ),
                        if (order.status == 'done' && order.payments.isNotEmpty)
                          for (final chip in _paymentMethodChips(order))
                            _WorkOrderMetaChip(
                              icon: chip.icon,
                              label: chip.label,
                              backgroundColor: chip.backgroundColor,
                              borderColor: chip.borderColor,
                              foregroundColor: chip.foregroundColor,
                              compact: isMobile,
                            ),
                      ],
                    ),
                    if (order.description?.trim().isNotEmpty ?? false) ...[
                      const Gap(6),
                      Text(
                        order.description!,
                        maxLines: isMobile ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.3,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (widget.canArchive ||
                      (!order.isActive && widget.canDeletePermanently))
                    PopupMenuButton<String>(
                      tooltip: 'İşlemler',
                      onSelected: (value) async {
                        if (value == 'toggle_active') {
                          widget.onToggleActive(!order.isActive);
                        } else if (value == 'delete') {
                          await widget.onDeletePermanently();
                        }
                      },
                      itemBuilder: (context) => [
                        if (widget.canArchive)
                          PopupMenuItem<String>(
                            value: 'toggle_active',
                            child: Text(
                              order.isActive ? 'Pasife Al' : 'Aktifleştir',
                            ),
                          ),
                        if (!order.isActive && widget.canDeletePermanently)
                          const PopupMenuItem<String>(
                            value: 'delete',
                            child: Text('Kalıcı Sil'),
                          ),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.only(bottom: 8),
                        child: Icon(
                          Icons.more_vert_rounded,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                  AppBadge(label: statusLabel, tone: statusTone),
                  if (!order.isActive) ...[
                    const Gap(6),
                    const AppBadge(label: 'Pasif', tone: AppBadgeTone.neutral),
                  ],
                  if (widget.canArchive || (!order.isActive && widget.canDeletePermanently)) ...[
                    const Gap(8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      alignment: WrapAlignment.end,
                      children: [
                        if (widget.canArchive)
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () =>
                                widget.onToggleActive(!order.isActive),
                            icon: Icon(
                              order.isActive
                                  ? Icons.delete_outline_rounded
                                  : Icons.restore_rounded,
                              size: 16,
                            ),
                            label: Text(order.isActive ? 'Sil' : 'Geri Al'),
                          ),
                        if (!order.isActive && widget.canDeletePermanently)
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: AppTheme.error,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              minimumSize: Size.zero,
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: widget.onDeletePermanently,
                            icon: const Icon(
                              Icons.delete_forever_rounded,
                              size: 16,
                            ),
                            label: const Text('Kalıcı Sil'),
                          ),
                      ],
                    ),
                  ],
                  if (!widget.reorderEnabled) ...[
                    const Gap(8),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 20,
                      color: const Color(0xFF94A3B8),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MobileBoardStrip extends StatelessWidget {
  const _MobileBoardStrip({required this.items, required this.showPassive});

  final List<WorkOrder> items;
  final bool showPassive;

  @override
  Widget build(BuildContext context) {
    final visible = items.where((e) => showPassive || e.isActive).toList();
    final open = visible.where((e) => e.status == 'open').length;
    final progress = visible.where((e) => e.status == 'in_progress').length;
    final done = visible.where((e) => e.status == 'done').length;
    return Row(
      children: [
        Expanded(
          child: _MiniBoardStat(
            label: 'Açık',
            value: open.toString(),
            color: AppTheme.warning,
          ),
        ),
        const Gap(8),
        Expanded(
          child: _MiniBoardStat(
            label: 'Devam',
            value: progress.toString(),
            color: AppTheme.primary,
          ),
        ),
        const Gap(8),
        Expanded(
          child: _MiniBoardStat(
            label: 'Kapalı',
            value: done.toString(),
            color: AppTheme.success,
          ),
        ),
      ],
    );
  }
}

class _MiniBoardStat extends StatelessWidget {
  const _MiniBoardStat({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.border),
        boxShadow: AppTheme.cardShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
          const Gap(6),
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const Gap(8),
              Text(
                value,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MobileWorkOrderCard extends StatelessWidget {
  const _MobileWorkOrderCard({
    required this.order,
    required this.hovered,
    required this.reorderEnabled,
    required this.reorderIndex,
    required this.onTap,
    required this.onToggleActive,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.onDeletePermanently,
  });

  final WorkOrder order;
  final bool hovered;
  final bool reorderEnabled;
  final int reorderIndex;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggleActive;
  final bool canArchive;
  final bool canDeletePermanently;
  final Future<void> Function() onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final scheduled = order.scheduledDate == null
        ? 'Plan yok'
        : DateFormat('d MMM', 'tr_TR').format(order.scheduledDate!);
    final (statusLabel, statusTone) = switch (order.status) {
      'open' => ('Açık', AppBadgeTone.warning),
      'in_progress' => ('Sahada', AppBadgeTone.primary),
      'done' => ('Kapalı', AppBadgeTone.success),
      _ => ('Bilinmiyor', AppBadgeTone.neutral),
    };

    Widget content = InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: hovered
                ? AppTheme.primary.withValues(alpha: 0.24)
                : AppTheme.border,
          ),
          boxShadow: AppTheme.cardShadow,
        ),
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
                        order.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Gap(2),
                      Text(
                        order.customerName ?? '-',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(8),
                AppBadge(label: statusLabel, tone: statusTone),
              ],
            ),
            const Gap(8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                _WorkOrderMetaChip(
                  icon: Icons.calendar_today_rounded,
                  label: scheduled,
                  compact: true,
                ),
                if (order.city?.trim().isNotEmpty ?? false)
                  _WorkOrderMetaChip(
                    icon: Icons.location_city_rounded,
                    label: order.city!,
                    compact: true,
                    emphasize: true,
                    backgroundColor: _cityTone(order.city!).withValues(alpha: 0.12),
                    borderColor: _cityTone(order.city!).withValues(alpha: 0.24),
                    foregroundColor: _cityTone(order.city!),
                  ),
                if (order.workOrderTypeName?.trim().isNotEmpty ?? false)
                  _WorkOrderMetaChip(
                    icon: Icons.category_rounded,
                    label: order.workOrderTypeName!,
                    compact: true,
                    emphasize: true,
                  ),
                if (order.contactPhone?.trim().isNotEmpty ?? false)
                  _WorkOrderMetaChip(
                    icon: Icons.phone_rounded,
                    label: order.contactPhone!,
                    compact: true,
                  ),
              ],
            ),
            if (order.address?.trim().isNotEmpty ?? false) ...[
              const Gap(6),
              Text(
                order.address!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.3,
                  fontSize: 12,
                ),
              ),
            ] else if (order.description?.trim().isNotEmpty ?? false) ...[
              const Gap(6),
              Text(
                order.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: const Color(0xFF475569),
                  height: 1.3,
                  fontSize: 12,
                ),
              ),
            ],
            const Gap(8),
            Row(
              children: [
                if (reorderEnabled)
                  ReorderableDragStartListener(
                    index: reorderIndex,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FAFC),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.drag_indicator_rounded,
                            size: 14,
                            color: Color(0xFF64748B),
                          ),
                          Gap(4),
                          Text('Sırala'),
                        ],
                      ),
                    ),
                  ),
                const Spacer(),
                if (canArchive)
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => onToggleActive(!order.isActive),
                    icon: Icon(
                      order.isActive
                          ? Icons.delete_outline_rounded
                          : Icons.restore_rounded,
                      size: 16,
                    ),
                    label: Text(order.isActive ? 'Sil' : 'Geri Al'),
                  ),
                if (canArchive) const Gap(8),
                if (!order.isActive && canDeletePermanently) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.error,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      minimumSize: Size.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onDeletePermanently,
                    icon: const Icon(Icons.delete_forever_rounded, size: 16),
                    label: const Text('Kalıcı Sil'),
                  ),
                  const Gap(8),
                ],
                if (canArchive || (!order.isActive && canDeletePermanently))
                  PopupMenuButton<String>(
                    tooltip: 'İşlemler',
                    onSelected: (value) async {
                      if (value == 'toggle_active') {
                        onToggleActive(!order.isActive);
                      } else if (value == 'delete') {
                        await onDeletePermanently();
                      }
                    },
                    itemBuilder: (context) => [
                      if (canArchive)
                        PopupMenuItem<String>(
                          value: 'toggle_active',
                          child: Text(order.isActive ? 'Pasife Al' : 'Aktifleştir'),
                        ),
                      if (!order.isActive && canDeletePermanently)
                        const PopupMenuItem<String>(
                          value: 'delete',
                          child: Text('Kalıcı Sil'),
                        ),
                    ],
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6),
                      child: Icon(
                        Icons.more_horiz_rounded,
                        size: 20,
                        color: Color(0xFF94A3B8),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );

    return content;
  }
}

class _WorkOrderMetaChip extends StatelessWidget {
  const _WorkOrderMetaChip({
    required this.icon,
    required this.label,
    this.emphasize = false,
    this.compact = false,
    this.backgroundColor,
    this.borderColor,
    this.foregroundColor,
  });

  final IconData icon;
  final String label;
  final bool emphasize;
  final bool compact;
  final Color? backgroundColor;
  final Color? borderColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 7 : 9,
        vertical: compact ? 4 : 5,
      ),
      decoration: BoxDecoration(
        color:
            backgroundColor ??
            (emphasize
                ? AppTheme.primary.withValues(alpha: 0.08)
                : const Color(0xFFF8FAFC)),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color:
              borderColor ??
              (emphasize
                  ? AppTheme.primary.withValues(alpha: 0.18)
                  : AppTheme.border),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: compact ? 12 : 14,
            color:
                foregroundColor ??
                (emphasize ? AppTheme.primary : const Color(0xFF64748B)),
          ),
          Gap(compact ? 4 : 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color:
                  foregroundColor ??
                  (emphasize ? AppTheme.primary : const Color(0xFF475569)),
              fontWeight: emphasize ? FontWeight.w600 : FontWeight.w500,
              fontSize: compact ? 11 : 11.5,
            ),
          ),
        ],
      ),
    );
  }
}

Color _cityTone(String city) {
  const palette = [
    Color(0xFF2563EB),
    Color(0xFF16A34A),
    Color(0xFFEA580C),
    Color(0xFF9333EA),
    Color(0xFFDC2626),
    Color(0xFF0891B2),
    Color(0xFFCA8A04),
    Color(0xFF4F46E5),
  ];
  final normalized = city.trim().toLowerCase();
  final hash = normalized.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
  return palette[hash % palette.length];
}

String _paymentSummary(WorkOrder order, NumberFormat money) {
  final totals = <String, double>{};
  for (final payment in order.payments) {
    totals.update(
      payment.currency,
      (value) => value + payment.amount,
      ifAbsent: () => payment.amount,
    );
  }
  return totals.entries
      .map((entry) => '${money.format(entry.value)} ${entry.key}')
      .join(' + ');
}

List<_PaymentMethodChipData> _paymentMethodChips(WorkOrder order) {
  final counts = <String, int>{};
  for (final payment in order.payments) {
    final method = payment.paymentMethod?.trim();
    if (method == null || method.isEmpty) continue;
    counts.update(method, (value) => value + 1, ifAbsent: () => 1);
  }

  final entries = counts.entries.toList()
    ..sort((a, b) => a.key.compareTo(b.key));
  return entries
      .map((entry) {
        final tone = _paymentMethodTone(entry.key);
        return _PaymentMethodChipData(
          label: '${_paymentMethodText(entry.key)} ${entry.value}',
          icon: tone.icon,
          backgroundColor: tone.background,
          borderColor: tone.border,
          foregroundColor: tone.foreground,
        );
      })
      .toList(growable: false);
}

String _paymentMethodText(String method) {
  return switch (method) {
    'cash' => 'Nakit',
    'bank' => 'Havale',
    'pos' => 'POS',
    'credit_card' => 'Kart',
    'check' => 'Çek',
    'other' => 'Diğer',
    _ => method,
  };
}

_PaymentMethodTone _paymentMethodTone(String method) {
  return switch (method) {
    'cash' => const _PaymentMethodTone(
      icon: Icons.payments_outlined,
      background: Color(0xFFECFDF5),
      border: Color(0xFFA7F3D0),
      foreground: Color(0xFF059669),
    ),
    'bank' => const _PaymentMethodTone(
      icon: Icons.account_balance_rounded,
      background: Color(0xFFEFF6FF),
      border: Color(0xFFBFDBFE),
      foreground: Color(0xFF2563EB),
    ),
    'pos' => const _PaymentMethodTone(
      icon: Icons.point_of_sale_rounded,
      background: Color(0xFFFFF7ED),
      border: Color(0xFFFED7AA),
      foreground: Color(0xFFEA580C),
    ),
    'credit_card' => const _PaymentMethodTone(
      icon: Icons.credit_card_rounded,
      background: Color(0xFFFAF5FF),
      border: Color(0xFFE9D5FF),
      foreground: Color(0xFF9333EA),
    ),
    _ => const _PaymentMethodTone(
      icon: Icons.payments_rounded,
      background: Color(0xFFF8FAFC),
      border: Color(0xFFE2E8F0),
      foreground: Color(0xFF475569),
    ),
  };
}

class _PaymentMethodChipData {
  const _PaymentMethodChipData({
    required this.label,
    required this.icon,
    required this.backgroundColor,
    required this.borderColor,
    required this.foregroundColor,
  });

  final String label;
  final IconData icon;
  final Color backgroundColor;
  final Color borderColor;
  final Color foregroundColor;
}

class _PaymentMethodTone {
  const _PaymentMethodTone({
    required this.icon,
    required this.background,
    required this.border,
    required this.foreground,
  });

  final IconData icon;
  final Color background;
  final Color border;
  final Color foreground;
}
