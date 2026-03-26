import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'work_order_model.dart';
import 'work_orders_providers.dart';

class WorkOrdersKanbanScreen extends ConsumerStatefulWidget {
  const WorkOrdersKanbanScreen({super.key});

  @override
  ConsumerState<WorkOrdersKanbanScreen> createState() =>
      _WorkOrdersKanbanScreenState();
}

class _WorkOrdersKanbanScreenState extends ConsumerState<WorkOrdersKanbanScreen> {
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
      await _showCreateWorkOrderDialog(context, ref);
      ref.read(workOrdersBoardProvider.notifier).refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
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
          onPressed: () async {
            await _showCreateWorkOrderDialog(context, ref);
            ref.read(workOrdersBoardProvider.notifier).refresh();
          },
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

    setState(() => _saving = true);
    try {
      await client.from('work_orders').insert({
        'customer_id': customerId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'status': 'open',
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
                            'Müşteriler yükleniyor…',
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
