import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_section_card.dart';
import 'work_order_model.dart';

Future<void> showCreateWorkOrderDialog(
  BuildContext context,
  WidgetRef ref, {
  WorkOrder? initialOrder,
}) async {
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _CreateWorkOrderDialog(initialOrder: initialOrder),
  );
}

class _CreateWorkOrderDialog extends ConsumerStatefulWidget {
  const _CreateWorkOrderDialog({this.initialOrder});

  final WorkOrder? initialOrder;

  @override
  ConsumerState<_CreateWorkOrderDialog> createState() =>
      _CreateWorkOrderDialogState();
}

class _CreateWorkOrderDialogState
    extends ConsumerState<_CreateWorkOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _addressController = TextEditingController();
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
    final initialOrder = widget.initialOrder;
    if (initialOrder != null) {
      _selectedCustomerId = initialOrder.customerId;
      _customerController.text = initialOrder.customerName ?? '';
      _addressController.text = initialOrder.address ?? '';
      _descController.text = initialOrder.description ?? '';
      _contactPhoneController.text = initialOrder.contactPhone ?? '';
      _locationLinkController.text = initialOrder.locationLink ?? '';
      _selectedCity = initialOrder.city;
      _selectedBranchId = initialOrder.branchId;
      _selectedWorkOrderTypeId = initialOrder.workOrderTypeId;
      _scheduledDate = initialOrder.scheduledDate;
      _assignedTo = initialOrder.assignedTo;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCustomers();
      _loadCities();
      _loadWorkOrderTypes();
      if ((widget.initialOrder?.customerId ?? '').isNotEmpty) {
        _loadBranches(widget.initialOrder!.customerId);
      }
    });
  }

  Future<void> _loadCustomers() async {
    final apiClient = ref.read(apiClientProvider);

    try {
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'customers_basic'},
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_CustomerOption.fromJson)
          .toList(growable: false);
      items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
      if (!mounted) return;
      setState(() => _customers = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _customers = const []);
    }
  }

  Future<void> _loadCities() async {
    final apiClient = ref.read(apiClientProvider);

    try {
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'definition_cities'},
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
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
    final apiClient = ref.read(apiClientProvider);

    try {
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'customer_branches',
          'customerId': customerId,
        },
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_BranchOption.fromJson)
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _branches = items);
    } catch (_) {
      if (!mounted) return;
      setState(() => _branches = const []);
    }
  }

  Future<void> _loadUsers() async {
    final apiClient = ref.read(apiClientProvider);

    try {
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'personnel_users'},
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_UserOption.fromJson)
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
    final apiClient = ref.read(apiClientProvider);

    try {
      if (apiClient == null) return;
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'definition_work_order_types'},
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(_WorkOrderTypeOption.fromJson)
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

  void _applyCustomerSelection(_CustomerOption customer) {
    _selectedCustomerId = customer.id;
    _customerController.text = customer.name;
    _selectedCity = customer.city ?? _selectedCity;
    _addressController.text = (customer.address ?? '').trim();
    _selectedBranchId = null;
    _branches = const [];
  }

  @override
  void dispose() {
    _customerController.dispose();
    _addressController.dispose();
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

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final profile = await ref.read(currentUserProfileProvider.future);
    if (!mounted) return;
    final isAdmin = profile?.role == 'admin';

    final assignedTo = isAdmin
        ? ((_assignedTo ?? '').trim().isNotEmpty ? _assignedTo : profile?.id)
        : profile?.id;
    if (assignedTo == null || assignedTo.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel ataması gerekli.')),
      );
      return;
    }

    final selectedType = _workOrderTypes
        .where((type) => type.id == _selectedWorkOrderTypeId)
        .firstOrNull;
    final fallbackTitle = (selectedType?.name ?? _customerController.text)
        .trim();
    final workOrderTitle = fallbackTitle.isEmpty ? 'İş Emri' : fallbackTitle;

    setState(() => _saving = true);
    try {
      final payload = <String, dynamic>{
        'customer_id': customerId,
        'branch_id': _selectedBranchId,
        'work_order_type_id': _selectedWorkOrderTypeId,
        'title': workOrderTitle,
        'description': _descController.text.trim().isEmpty
            ? null
            : _descController.text.trim(),
        'address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'assigned_to': assignedTo,
        'scheduled_date': _scheduledDate?.toIso8601String().substring(0, 10),
        'city': _selectedCity,
        'contact_phone': _contactPhoneController.text.trim().isEmpty
            ? null
            : _contactPhoneController.text.trim(),
        'location_link': _locationLinkController.text.trim().isEmpty
            ? null
            : _locationLinkController.text.trim(),
      };

      if (widget.initialOrder == null) {
        await apiClient.postJson('/work-orders', body: payload);
      } else {
        await apiClient.patchJson(
          '/work-orders',
          body: {'id': widget.initialOrder!.id, ...payload},
        );
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.initialOrder == null
                ? 'İş emri oluşturuldu.'
                : 'İş emri güncellendi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İş emri oluşturulamadı: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final loadingCustomers = _customers.isEmpty;
    final isAdmin = ref.watch(isAdminProvider);
    final width = MediaQuery.sizeOf(context).width;
    final isWide = width >= 1100;
    final isMedium = width >= 860;

    if (isAdmin && !_usersLoaded) {
      _usersLoaded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadUsers());
    }

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.initialOrder == null
                              ? 'Yeni İş Emri'
                              : 'İş Emrini Düzenle',
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
                  else if (isWide)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: AppSectionCard(
                            title: 'Operasyon Bilgileri',
                            subtitle:
                                'Müşteri, adres ve operasyon lokasyonunu yönetin.',
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                _customerField(),
                                if (_branches.isNotEmpty) ...[
                                  const Gap(12),
                                  _branchField(),
                                ],
                                const Gap(12),
                                TextFormField(
                                  controller: _addressController,
                                  minLines: 2,
                                  maxLines: 3,
                                  decoration: const InputDecoration(
                                    labelText: 'Adres',
                                    hintText:
                                        'Müşteri adresi otomatik gelir, istersen düzenle',
                                  ),
                                ),
                                const Gap(12),
                                Row(
                                  children: [
                                    Expanded(child: _cityField()),
                                    const Gap(12),
                                    Expanded(child: _workOrderTypeField()),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const Gap(12),
                        Expanded(
                          child: AppSectionCard(
                            title: 'Planlama ve İletişim',
                            subtitle:
                                'Personel ataması, tarih ve saha iletişim bilgileri.',
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: _dateField(context)),
                                    if (isAdmin) ...[
                                      const Gap(12),
                                      Expanded(child: _assignedField()),
                                    ],
                                  ],
                                ),
                                const Gap(12),
                                TextFormField(
                                  controller: _descController,
                                  minLines: 3,
                                  maxLines: 5,
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
                                          hintText:
                                              'https://maps.google.com/...',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  else ...[
                    AppSectionCard(
                      title: 'Operasyon Bilgileri',
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          _customerField(),
                          if (_branches.isNotEmpty) ...[
                            const Gap(12),
                            _branchField(),
                          ],
                          const Gap(12),
                          TextFormField(
                            controller: _addressController,
                            minLines: 2,
                            maxLines: 3,
                            decoration: const InputDecoration(
                              labelText: 'Adres',
                              hintText:
                                  'Müşteri adresi otomatik gelir, istersen düzenle',
                            ),
                          ),
                          const Gap(12),
                          if (isMedium)
                            Row(
                              children: [
                                Expanded(child: _cityField()),
                                const Gap(12),
                                Expanded(child: _workOrderTypeField()),
                              ],
                            )
                          else ...[
                            _cityField(),
                            const Gap(12),
                            _workOrderTypeField(),
                          ],
                        ],
                      ),
                    ),
                    const Gap(12),
                    AppSectionCard(
                      title: 'Planlama ve İletişim',
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        children: [
                          if (isAdmin && isMedium)
                            Row(
                              children: [
                                Expanded(child: _dateField(context)),
                                const Gap(12),
                                Expanded(child: _assignedField()),
                              ],
                            )
                          else ...[
                            _dateField(context),
                            if (isAdmin) ...[const Gap(12), _assignedField()],
                          ],
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
                          if (isMedium)
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
                            )
                          else ...[
                            TextFormField(
                              controller: _contactPhoneController,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'İrtibat Numarası',
                                hintText: '0 5xx xxx xx xx',
                              ),
                            ),
                            const Gap(12),
                            TextFormField(
                              controller: _locationLinkController,
                              decoration: const InputDecoration(
                                labelText: 'Konum Linki',
                                hintText: 'https://maps.google.com/...',
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
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
                              : Text(
                                  widget.initialOrder == null
                                      ? 'Kaydet'
                                      : 'Güncelle',
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _customerField() {
    return Autocomplete<_CustomerOption>(
      optionsBuilder: (text) {
        final q = _sortKey(text.text.trim());
        if (q.isEmpty) return _customers.take(20);
        return _customers.where((c) => _sortKey(c.name).contains(q)).take(20);
      },
      displayStringForOption: (o) => o.name,
      onSelected: (o) {
        setState(() {
          _applyCustomerSelection(o);
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _loadBranches(o.id);
        });
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
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
    );
  }

  Widget _branchField() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedBranchId,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('Şube seç (opsiyonel)'),
        ),
        ..._branches.map(
          (b) => DropdownMenuItem<String?>(value: b.id, child: Text(b.name)),
        ),
      ],
      onChanged: _saving ? null : (v) => setState(() => _selectedBranchId = v),
      decoration: const InputDecoration(labelText: 'Şube'),
    );
  }

  Widget _cityField() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedCity,
      items: [
        const DropdownMenuItem<String?>(value: null, child: Text('Şehir seç')),
        ..._cities.map(
          (city) => DropdownMenuItem<String?>(value: city, child: Text(city)),
        ),
      ],
      onChanged: _saving
          ? null
          : (value) => setState(() => _selectedCity = value),
      decoration: const InputDecoration(labelText: 'Şehir'),
    );
  }

  Widget _workOrderTypeField() {
    return DropdownButtonFormField<String?>(
      initialValue: _selectedWorkOrderTypeId,
      items: [
        const DropdownMenuItem<String?>(
          value: null,
          child: Text('İş emri tipi seç'),
        ),
        ..._workOrderTypes.map(
          (type) =>
              DropdownMenuItem<String?>(value: type.id, child: Text(type.name)),
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
                    (selected?.contactPhone?.trim().isNotEmpty ?? false)) {
                  _contactPhoneController.text = selected!.contactPhone!;
                }
                if ((_locationLinkController.text.trim().isEmpty) &&
                    (selected?.locationInfo?.trim().isNotEmpty ?? false)) {
                  _locationLinkController.text = selected!.locationInfo!;
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
    );
  }

  Widget _dateField(BuildContext context) {
    return InkWell(
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
        decoration: const InputDecoration(labelText: 'Planlanan Tarih'),
        child: Text(
          _scheduledDate == null
              ? 'Seçilmedi'
              : '${_scheduledDate!.day}.${_scheduledDate!.month}.${_scheduledDate!.year}',
        ),
      ),
    );
  }

  Widget _assignedField() {
    return DropdownButtonFormField<String?>(
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
      onChanged: _saving ? null : (v) => setState(() => _assignedTo = v),
      decoration: const InputDecoration(labelText: 'Atanan Personel'),
      validator: (v) {
        if (!ref.read(isAdminProvider)) return null;
        if ((v ?? '').isEmpty) return 'Personel gerekli.';
        return null;
      },
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
    required this.address,
  });

  final String id;
  final String name;
  final String? city;
  final String? address;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
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
