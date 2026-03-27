import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_card.dart';

Future<void> showCreateWorkOrderDialog(
  BuildContext context,
  WidgetRef ref,
) async {
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

class _CreateWorkOrderDialogState
    extends ConsumerState<_CreateWorkOrderDialog> {
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Müşteri seçin.')));
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
        'scheduled_date': _scheduledDate?.toIso8601String().substring(0, 10),
        'is_active': true,
        'created_by': client.auth.currentUser?.id,
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İş emri oluşturuldu.')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('İş emri oluşturulamadı.')));
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
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
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
                            style: Theme.of(context).textTheme.bodyMedium
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
                    fieldViewBuilder:
                        (context, controller, focusNode, onSubmit) {
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
                            validator: (value) {
                              if ((_selectedCustomerId ?? '').isEmpty) {
                                return 'Müşteri seçin.';
                              }
                              return null;
                            },
                            onChanged: (value) => _selectedCustomerId = null,
                          );
                        },
                  ),
                const Gap(12),
                if (_branches.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedBranchId,
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
                    onChanged: _saving
                        ? null
                        : (v) => setState(() => _selectedBranchId = v),
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
                                final initial =
                                    _scheduledDate ?? DateTime.now();
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
                          initialValue: _assignedTo,
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
                          onChanged: _saving
                              ? null
                              : (v) => setState(() => _assignedTo = v),
                          decoration: const InputDecoration(
                            labelText: 'Atanan Personel',
                          ),
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
                    if (v == null || v.trim().length < 2) {
                      return 'Başlık gerekli.';
                    }
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
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
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
  const _UserOption({
    required this.id,
    required this.fullName,
    required this.role,
  });

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
