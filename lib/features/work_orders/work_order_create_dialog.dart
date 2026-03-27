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
  final _contactPhoneController = TextEditingController();
  final _locationLinkController = TextEditingController();
  bool _saving = false;

  List<_CustomerOption> _customers = const [];
  String? _selectedCustomerId;
  List<String> _cities = const [];
  String? _selectedCity;
  List<_BranchOption> _branches = const [];
  String? _selectedBranchId;
  List<_WorkOrderTypeOption> _workOrderTypes = const [];
  String? _selectedWorkOrderTypeId;
  DateTime? _scheduledDate;

  bool _usersLoaded = false;
  List<_UserOption> _users = const [];
  String? _assignedTo;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
      _loadCities();
      _loadWorkOrderTypes();
    });
  }

  Future<void> _loadCustomers() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final items = <_CustomerOption>[];
      var from = 0;
      const pageSize = 500;

      while (true) {
        final rows = await client
            .from('customers')
            .select('id,name,city,is_active')
            .eq('is_active', true)
            .order('name')
            .range(from, from + pageSize - 1);

        final page = (rows as List)
            .map((e) => _CustomerOption.fromJson(e as Map<String, dynamic>))
            .toList(growable: false);
        items.addAll(page);

        if (page.length < pageSize) break;
        from += pageSize;
      }

      items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));

      if (!mounted) return;
      setState(() => _customers = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _customers = const []);
    }
  }

  Future<void> _loadCities() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final rows = await client
          .from('cities')
          .select('name')
          .eq('is_active', true)
          .order('name');

      final items = (rows as List)
          .map((row) => row['name']?.toString().trim())
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList(growable: false);

      if (!mounted) return;
      setState(() => _cities = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _cities = const []);
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

  Future<void> _loadWorkOrderTypes() async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    try {
      final rows = await client
          .from('work_order_types')
          .select(
            'id,name,description,location_info,contact_name,contact_phone',
          )
          .eq('is_active', true)
          .order('sort_order')
          .order('name')
          .limit(100);

      final items = (rows as List)
          .map((e) => _WorkOrderTypeOption.fromJson(e as Map<String, dynamic>))
          .toList(growable: false);

      if (!mounted) return;
      setState(() {
        _workOrderTypes = items;
        if (items.length == 1) {
          _selectedWorkOrderTypeId = items.first.id;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _workOrderTypes = const []);
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _titleController.dispose();
    _descController.dispose();
    _contactPhoneController.dispose();
    _locationLinkController.dispose();
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
        'work_order_type_id': _selectedWorkOrderTypeId,
        'title': _titleController.text.trim(),
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'status': 'open',
        'assigned_to': assignedTo,
        'scheduled_date': _scheduledDate?.toIso8601String().substring(0, 10),
        'city': _selectedCity,
        'contact_phone': _contactPhoneController.text.trim().isEmpty
            ? null
            : _contactPhoneController.text.trim(),
        'location_link': _locationLinkController.text.trim().isEmpty
            ? null
            : _locationLinkController.text.trim(),
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
                      final q = _sortKey(text.text.trim());
                      if (q.isEmpty) return _customers.take(20);
                      return _customers
                          .where((c) => _sortKey(c.name).contains(q))
                          .take(20);
                    },
                    displayStringForOption: (o) => o.name,
                    onSelected: (o) {
                      setState(() {
                        _selectedCustomerId = o.id;
                        _customerController.text = o.name;
                        _selectedCity = o.city ?? _selectedCity;
                        _selectedBranchId = null;
                        _branches = const [];
                      });
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
                DropdownButtonFormField<String?>(
                  initialValue: _selectedCity,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Şehir seç'),
                    ),
                    ..._cities.map(
                      (city) => DropdownMenuItem<String?>(
                        value: city,
                        child: Text(city),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) => setState(() => _selectedCity = value),
                  decoration: const InputDecoration(labelText: 'Şehir'),
                ),
                const Gap(12),
                DropdownButtonFormField<String?>(
                  initialValue: _selectedWorkOrderTypeId,
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('İş emri tipi seç'),
                    ),
                    ..._workOrderTypes.map(
                      (type) => DropdownMenuItem<String?>(
                        value: type.id,
                        child: Text(type.name),
                      ),
                    ),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          _WorkOrderTypeOption? selected;
                          for (final type in _workOrderTypes) {
                            if (type.id == value) {
                              selected = type;
                              break;
                            }
                          }
                          setState(() {
                            _selectedWorkOrderTypeId = value;
                            if ((_contactPhoneController.text.trim().isEmpty) &&
                                (selected?.contactPhone?.trim().isNotEmpty ??
                                    false)) {
                              _contactPhoneController.text =
                                  selected!.contactPhone!;
                            }
                            if ((_locationLinkController.text.trim().isEmpty) &&
                                (selected?.locationInfo?.trim().isNotEmpty ??
                                    false)) {
                              _locationLinkController.text =
                                  selected!.locationInfo!;
                            }
                          });
                        },
                  decoration: const InputDecoration(labelText: 'İş Emri Tipi'),
                  validator: (value) {
                    if (_workOrderTypes.isEmpty) return null;
                    if ((value ?? '').isEmpty) {
                      return 'İş emri tipi seçin.';
                    }
                    return null;
                  },
                ),
                const Gap(12),
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
                const Gap(12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _contactPhoneController,
                        keyboardType: TextInputType.phone,
                        decoration: const InputDecoration(
                          labelText: 'İrtibat Numarası',
                          hintText: '0 5xx xxx xx xx',
                        ),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: TextFormField(
                        controller: _locationLinkController,
                        decoration: const InputDecoration(
                          labelText: 'Konum Linki',
                          hintText: 'https://maps.google.com/...',
                        ),
                      ),
                    ),
                  ],
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

String _sortKey(String value) {
  return value
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u')
      .trim();
}

class _CustomerOption {
  const _CustomerOption({
    required this.id,
    required this.name,
    required this.city,
  });

  final String id;
  final String name;
  final String? city;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
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

class _WorkOrderTypeOption {
  const _WorkOrderTypeOption({
    required this.id,
    required this.name,
    required this.description,
    required this.locationInfo,
    required this.contactName,
    required this.contactPhone,
  });

  final String id;
  final String name;
  final String? description;
  final String? locationInfo;
  final String? contactName;
  final String? contactPhone;

  factory _WorkOrderTypeOption.fromJson(Map<String, dynamic> json) {
    return _WorkOrderTypeOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      locationInfo: json['location_info']?.toString(),
      contactName: json['contact_name']?.toString(),
      contactPhone: json['contact_phone']?.toString(),
    );
  }
}
