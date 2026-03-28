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
import '../../core/ui/app_section_card.dart';
import '../../core/ui/empty_state_card.dart';
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
      subtitle: isCompact
          ? 'Açık işleri sürükleyip sıralayın.'
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
          Expanded(
            child: boardAsync.when(
              data: (items) {
                final visibleItems = items
                    .where((e) => _showPassive || e.isActive)
                    .toList(growable: false);
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
                    ),
                    _WorkOrderList(
                      items: visibleItems
                          .where((e) => e.status == 'done')
                          .toList(),
                      emptyText: _showPassive
                          ? 'Kapalı veya pasif iş emri bulunmuyor.'
                          : 'Kapatılmış iş emri bulunmuyor.',
                      onTap: (order) => _openWorkOrderDetail(order),
                      onToggleActive: _setWorkOrderActive,
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
}

class _WorkOrderList extends StatelessWidget {
  const _WorkOrderList({
    required this.items,
    required this.emptyText,
    required this.onTap,
    required this.onToggleActive,
  });

  final List<WorkOrder> items;
  final String emptyText;
  final ValueChanged<WorkOrder> onTap;
  final Future<void> Function(WorkOrder order, bool active) onToggleActive;

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
    final canReorder = items.every(
      (item) => item.status == 'open' && item.isActive,
    );
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
          );
        },
      );
    }

    return Column(
      children: [
        if (isMobile)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Açık iş emirlerini tutup sürükleyerek sırala.',
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
  });

  final WorkOrder order;
  final VoidCallback onTap;
  final bool reorderEnabled;
  final int reorderIndex;
  final ValueChanged<bool> onToggleActive;

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
          padding: EdgeInsets.all(isMobile ? 12 : 12),
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
                    Gap(isMobile ? 4 : 4),
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
                              ),
                        ),
                      ),
                    Wrap(
                      spacing: isMobile ? 6 : 6,
                      runSpacing: isMobile ? 6 : 6,
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
                      Gap(isMobile ? 6 : 8),
                      Text(
                        order.description!,
                        maxLines: isMobile ? 2 : 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF64748B),
                          height: 1.35,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const Gap(10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  PopupMenuButton<String>(
                    tooltip: 'İşlemler',
                    onSelected: (value) {
                      if (value == 'toggle_active') {
                        widget.onToggleActive(!order.isActive);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'toggle_active',
                        child: Text(
                          order.isActive ? 'Pasife Al' : 'Aktifleştir',
                        ),
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
        horizontal: compact ? 8 : 10,
        vertical: compact ? 5 : 6,
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
              fontSize: compact ? 11.5 : null,
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
