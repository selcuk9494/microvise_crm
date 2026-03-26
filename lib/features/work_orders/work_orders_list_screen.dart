import 'package:flutter/foundation.dart';
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
      await _showCreateWorkOrderDialog(context, ref);
      ref.read(workOrdersBoardProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    final boardAsync = ref.watch(workOrdersBoardProvider);

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
            await _showCreateWorkOrderDialog(context, ref);
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
              indicatorSize: TabBarIndicatorSize.tab,
              dividerColor: Colors.transparent,
              labelPadding: const EdgeInsets.symmetric(horizontal: 24),
              tabs: [
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.radio_button_unchecked_rounded, size: 16),
                      const Gap(8),
                      const Text('Açık'),
                      boardAsync.whenOrNull(
                        data: (items) {
                          final count =
                              items.where((e) => e.status == 'open').length;
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
                      ) ?? const SizedBox.shrink(),
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
                          final count =
                              items.where((e) => e.status == 'in_progress').length;
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
                      ) ?? const SizedBox.shrink(),
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
                          final count =
                              items.where((e) => e.status == 'done').length;
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
                      ) ?? const SizedBox.shrink(),
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
                      items: items.where((e) => e.status == 'in_progress').toList(),
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
              error: (_, __) => Center(
                child: AppCard(
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
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
      separatorBuilder: (_, __) => const Gap(10),
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
              color: _hovered ? AppTheme.primary.withValues(alpha: 0.3) : AppTheme.border,
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
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
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

Future<void> _showCreateWorkOrderDialog(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supabase bağlantısı bulunamadı.')),
    );
    return;
  }

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const _CreateWorkOrderDialog(),
  );
}

class _CreateWorkOrderDialog extends ConsumerStatefulWidget {
  const _CreateWorkOrderDialog();

  @override
  ConsumerState<_CreateWorkOrderDialog> createState() =>
      _CreateWorkOrderDialogState();
}

class _CreateWorkOrderDialogState extends ConsumerState<_CreateWorkOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _titleController = TextEditingController();
  final _descController = TextEditingController();
  bool _saving = false;

  List<_CustomerOption> _customers = const [];
  String? _selectedCustomerId;
  List<_BranchOption> _branches = const [];
  String? _selectedBranchId;
  DateTime? _scheduledDate;

  bool _usersLoaded = false;
  List<_UserOption> _users = const [];
  String? _assignedTo;

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

      final items = (rows as List)
          .map((e) => _CustomerOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _customers = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _customers = const []);
    }
  }

  Future<void> _loadBranches(String customerId) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final rows = await client
          .from('branches')
          .select('id,name,is_active')
          .eq('customer_id', customerId)
          .eq('is_active', true)
          .order('name')
          .limit(100);

      final items = (rows as List)
          .map((e) => _BranchOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _branches = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _branches = const []);
    }
  }

  Future<void> _loadUsers() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final rows = await client
          .from('users')
          .select('id,full_name,role')
          .order('full_name')
          .limit(200);

      final items = (rows as List)
          .map((e) => _UserOption.fromJson(e as Map<String, dynamic>))
          .where((u) => u.role != 'admin')
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _users = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _users = const []);
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _titleController.dispose();
    _descController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final customerId = _selectedCustomerId;
    if (customerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Müşteri seçin.')),
      );
      return;
    }

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final profile = await ref.read(currentUserProfileProvider.future);
    if (!mounted) return;
    final isAdmin = profile?.role == 'admin';

    final assignedTo = isAdmin ? _assignedTo : client.auth.currentUser?.id;
    if (assignedTo == null || assignedTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel ataması gerekli.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await client.from('work_orders').insert({
        'customer_id': customerId,
        'branch_id': _selectedBranchId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'status': 'open',
        'assigned_to': assignedTo,
        'scheduled_date': _scheduledDate == null
            ? null
            : _scheduledDate!.toIso8601String().substring(0, 10),
        'is_active': true,
        'created_by': client.auth.currentUser?.id,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş emri oluşturuldu.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İş emri oluşturulamadı.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingCustomers = _customers.isEmpty;
    final isAdmin = ref.watch(isAdminProvider);

    if (isAdmin && !_usersLoaded) {
      _usersLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
    }

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
                        'Yeni İş Emri',
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
                if (loadingCustomers)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: Row(
                      children: [
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        const Gap(10),
                        Expanded(
                          child: Text(
                            'Müşteriler yükleniyor...',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: const Color(0xFF64748B)),
                          ),
                        ),
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
                      _selectedBranchId = null;
                      _branches = const [];
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        _loadBranches(o.id);
                      });
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
                        validator: (v) {
                          if ((_selectedCustomerId ?? '').isEmpty) {
                            return 'Müşteri seçin.';
                          }
                          return null;
                        },
                        onChanged: (_) => _selectedCustomerId = null,
                      );
                    },
                  ),
                const Gap(12),
                if (_branches.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    value: _selectedBranchId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Şube seç (opsiyonel)'),
                      ),
                      ..._branches.map(
                        (b) => DropdownMenuItem<String?>(
                          value: b.id,
                          child: Text(b.name),
                        ),
                      ),
                    ],
                    onChanged: _saving ? null : (v) => setState(() => _selectedBranchId = v),
                    decoration: const InputDecoration(labelText: 'Şube'),
                  ),
                  const Gap(12),
                ],
                Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: _saving
                            ? null
                            : () async {
                                final initial = _scheduledDate ?? DateTime.now();
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: initial,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(DateTime.now().year + 5),
                                );
                                if (picked == null) return;
                                setState(() => _scheduledDate = picked);
                              },
                        child: InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Planlanan Tarih',
                          ),
                          child: Text(
                            _scheduledDate == null
                                ? 'Seçilmedi'
                                : '${_scheduledDate!.day}.${_scheduledDate!.month}.${_scheduledDate!.year}',
                          ),
                        ),
                      ),
                    ),
                    if (isAdmin) ...[
                      const Gap(12),
                      Expanded(
                        child: DropdownButtonFormField<String?>(
                          value: _assignedTo,
                          items: [
                            const DropdownMenuItem<String?>(
                              value: null,
                              child: Text('Personel seç'),
                            ),
                            ..._users.map(
                              (u) => DropdownMenuItem<String?>(
                                value: u.id,
                                child: Text(u.fullName ?? 'Personel'),
                              ),
                            ),
                          ],
                          onChanged: _saving ? null : (v) => setState(() => _assignedTo = v),
                          decoration: const InputDecoration(labelText: 'Atanan Personel'),
                          validator: (v) {
                            if (!isAdmin) return null;
                            if ((v ?? '').isEmpty) return 'Personel gerekli.';
                            return null;
                          },
                        ),
                      ),
                    ],
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Örn: Hat yenileme',
                  ),
                  validator: (v) {
                    if (v == null || v.trim().length < 2) return 'Başlık gerekli.';
                    return null;
                  },
                ),
                const Gap(12),
                TextFormField(
                  controller: _descController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama',
                    hintText: 'İsteğe bağlı',
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
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
                            : const Text('Kaydet'),
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

class _BranchOption {
  const _BranchOption({required this.id, required this.name});

  final String id;
  final String name;

  factory _BranchOption.fromJson(Map<String, dynamic> json) {
    return _BranchOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class _UserOption {
  const _UserOption({required this.id, required this.fullName, required this.role});

  final String id;
  final String? fullName;
  final String? role;

  factory _UserOption.fromJson(Map<String, dynamic> json) {
    return _UserOption(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: json['role']?.toString(),
    );
  }
}
