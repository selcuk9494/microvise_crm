import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/format/currency_format.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'fault_form_model.dart';
import 'fault_form_print.dart';

final faultFormCustomersProvider =
    FutureProvider<List<_FaultCustomerOption>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'form_application_customers'},
    );
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_FaultCustomerOption.fromJson)
        .toList(growable: false);
    items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
    return items;
  }

  if (client == null) return const [];
  const pageSize = 500;
  var from = 0;
  final items = <_FaultCustomerOption>[];
  while (true) {
    final rows = await client
        .from('customers')
        .select('id,name,vkn,city,address,is_active')
        .range(from, from + pageSize - 1);
    final batch = (rows as List)
        .map((row) => _FaultCustomerOption.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
    items.addAll(batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }
  items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return items;
});

final faultCustomerDeviceRegistriesProvider =
    FutureProvider.family<List<_DeviceRegistryOption>, String>((
  ref,
  customerId,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'customer_device_registries',
        'customerId': customerId,
        'showPassive': 'false',
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_DeviceRegistryOption.fromJson)
        .where((e) => e.registryNumber.trim().isNotEmpty)
        .toList(growable: false);
  }
  if (client == null) return const [];
  final rows = await client
      .from('device_registries')
      .select('registry_number,model,is_active')
      .eq('customer_id', customerId)
      .eq('is_active', true)
      .order('registry_number', ascending: true)
      .limit(1000);
  return (rows as List)
      .map((e) => _DeviceRegistryOption.fromJson(e as Map<String, dynamic>))
      .where((e) => e.registryNumber.trim().isNotEmpty)
      .toList(growable: false);
});

final faultFormsProvider = FutureProvider<List<FaultFormRecord>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'form_fault_list', 'showPassive': 'true'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(FaultFormRecord.fromJson)
        .toList(growable: false);
  }
  if (client == null) return const [];

  try {
    final rows = await client
        .from('fault_forms')
        .select(
          'id,form_date,customer_id,customer_name,customer_address,customer_tax_office,customer_vkn,device_brand_model,company_code_and_registry,okc_approval_date_and_number,fault_date_time_text,fault_description,last_z_report_date_and_number,last_z_report_date,last_z_report_no,total_revenue,total_vat,is_active,created_at',
        )
        .order('created_at', ascending: false)
        .limit(800);

    return (rows as List)
        .map((row) => FaultFormRecord.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

class FaultFormScreen extends ConsumerStatefulWidget {
  const FaultFormScreen({super.key});

  @override
  ConsumerState<FaultFormScreen> createState() => _FaultFormScreenState();
}

class _FaultFormScreenState extends ConsumerState<FaultFormScreen> {
  final _customerFilterController = TextEditingController();
  final _deviceFilterController = TextEditingController();
  bool _showPassive = false;

  @override
  void dispose() {
    _customerFilterController.dispose();
    _deviceFilterController.dispose();
    super.dispose();
  }

  Future<void> _openCreateDialog() async {
    final saved = await showDialog<FaultFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _FaultFormDialog(),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(faultFormsProvider.future);
    await _print(saved);
  }

  Future<void> _openEditDialog(FaultFormRecord record) async {
    final saved = await showDialog<FaultFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _FaultFormDialog(initialRecord: record),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(faultFormsProvider.future);
  }

  Future<void> _openDuplicateDialog(FaultFormRecord record) async {
    final saved = await showDialog<FaultFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _FaultFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(faultFormsProvider.future);
    await _print(saved);
  }

  Future<void> _print(FaultFormRecord record) async {
    final ok = await printFaultForm(record);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok ? 'Arıza formu çıktısı hazırlandı.' : 'Bu platformda çıktı açılamadı.',
        ),
      ),
    );
  }

  List<FaultFormRecord> _filter(List<FaultFormRecord> input) {
    final qCustomer = _sortKey(_customerFilterController.text);
    final qDevice = _sortKey(_deviceFilterController.text);

    return input.where((r) {
      if (!_showPassive && !r.isActive) return false;
      if (qCustomer.isNotEmpty && !_sortKey(r.customerName).contains(qCustomer)) {
        return false;
      }
      if (qDevice.isNotEmpty) {
        final hay = _sortKey(
          '${r.deviceBrandModel ?? ''} ${r.companyCodeAndRegistry ?? ''}',
        );
        if (!hay.contains(qDevice)) return false;
      }
      return true;
    }).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDeletePermanently =
        ref.watch(hasActionAccessProvider(kActionDeleteRecords));
    final formsAsync = ref.watch(faultFormsProvider);

    final isMobile = MediaQuery.sizeOf(context).width < 900;

    final filterCard = AppCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filtreler', style: Theme.of(context).textTheme.titleSmall),
          const Gap(12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              SizedBox(
                width: isMobile ? double.infinity : 260,
                child: TextField(
                  controller: _customerFilterController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.person_rounded),
                    labelText: 'Müşteri',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              SizedBox(
                width: isMobile ? double.infinity : 260,
                child: TextField(
                  controller: _deviceFilterController,
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.memory_rounded),
                    labelText: 'Cihaz / Sicil',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() {
                  _customerFilterController.clear();
                  _deviceFilterController.clear();
                  _showPassive = false;
                }),
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Temizle'),
              ),
              OutlinedButton.icon(
                onPressed: () => setState(() => _showPassive = !_showPassive),
                icon: Icon(
                  _showPassive ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  size: 18,
                ),
                label: Text(_showPassive ? 'Pasifleri Gizle' : 'Pasifleri Göster'),
              ),
            ],
          ),
        ],
      ),
    );

    return AppPageLayout(
      title: 'Arıza Formları',
      subtitle: 'KDV 15A - Arıza bildirim kayıtları.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(faultFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: canEdit ? _openCreateDialog : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Arıza'),
        ),
      ],
      body: formsAsync.when(
        data: (items) {
          final filtered = _filter(items);
          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: filtered.length + 1,
            separatorBuilder: (_, _) => const Gap(12),
            itemBuilder: (context, index) {
              if (index == 0) return filterCard;
              final record = filtered[index - 1];
              return _FaultRecordCard(
                record: record,
                canEdit: canEdit,
                canArchive: canArchive,
                canDeletePermanently: canDeletePermanently,
                onEdit: () => _openEditDialog(record),
                onDuplicate: () => _openDuplicateDialog(record),
                onPrint: () => _print(record),
                onToggleActive: canArchive
                    ? () => _setActive(record, !record.isActive)
                    : null,
                onDeletePermanently:
                    canDeletePermanently ? () => _deletePermanently(record) : null,
              );
            },
          );
        },
        loading: () => const AppCard(child: SizedBox(height: 240)),
        error: (e, _) => AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text('Yüklenemedi: $e'),
          ),
        ),
      ),
    );
  }

  Future<void> _setActive(FaultFormRecord record, bool active) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'fault_forms',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': record.id},
            ],
            'values': {'is_active': active},
          },
        );
      } else {
        if (client == null) return;
        await client
            .from('fault_forms')
            .update({'is_active': active})
            .eq('id', record.id);
      }
      ref.invalidate(faultFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(active ? 'Form aktifleştirildi.' : 'Form pasife alındı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem başarısız: $e')),
      );
    }
  }

  Future<void> _deletePermanently(FaultFormRecord record) async {
    if (record.isActive) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce kaydı pasife alın.')),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arıza formunu kalıcı sil'),
        content: Text(
          '"${record.customerName}" kaydı kalıcı olarak silinecek. Bu işlem geri alınamaz.',
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

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {'op': 'delete', 'table': 'fault_forms', 'id': record.id},
        );
      } else {
        if (client == null) return;
        await client.from('fault_forms').delete().eq('id', record.id);
      }
      ref.invalidate(faultFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kayıt kalıcı olarak silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }
}

class _FaultRecordCard extends StatelessWidget {
  const _FaultRecordCard({
    required this.record,
    required this.canEdit,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.onEdit,
    required this.onDuplicate,
    required this.onPrint,
    required this.onToggleActive,
    required this.onDeletePermanently,
  });

  final FaultFormRecord record;
  final bool canEdit;
  final bool canArchive;
  final bool canDeletePermanently;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onPrint;
  final VoidCallback? onToggleActive;
  final VoidCallback? onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    final badgeLabel = record.isActive ? 'KDV 15A' : 'Pasif';
    final badgeTone = record.isActive ? AppBadgeTone.primary : AppBadgeTone.neutral;
    final dateText = DateFormat('d MMM y', 'tr_TR').format(record.formDate);

    return AppCard(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 10 : 12, vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 10,
            height: 48,
            decoration: BoxDecoration(
              color: record.isActive
                  ? AppTheme.primary.withValues(alpha: 0.16)
                  : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: record.isActive
                    ? AppTheme.primary.withValues(alpha: 0.25)
                    : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        record.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                              fontSize: isMobile ? 14 : 15,
                            ),
                      ),
                    ),
                    const Gap(8),
                    AppBadge(label: badgeLabel, tone: badgeTone),
                  ],
                ),
                const Gap(6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _InfoChip(icon: Icons.calendar_today_rounded, text: dateText),
                    if ((record.companyCodeAndRegistry ?? '').trim().isNotEmpty)
                      _InfoChip(
                        icon: Icons.badge_rounded,
                        text: record.companyCodeAndRegistry!.trim(),
                      ),
                    if ((record.deviceBrandModel ?? '').trim().isNotEmpty)
                      _InfoChip(
                        icon: Icons.memory_rounded,
                        text: record.deviceBrandModel!.trim(),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Gap(10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              IconButton.filledTonal(
                tooltip: 'Yazdır',
                onPressed: onPrint,
                icon: const Icon(Icons.print_rounded, size: 18),
              ),
              if (canEdit)
                IconButton.filledTonal(
                  tooltip: 'Düzenle',
                  onPressed: onEdit,
                  icon: const Icon(Icons.edit_rounded, size: 18),
                ),
              if (canEdit)
                IconButton.filledTonal(
                  tooltip: 'Kopya',
                  onPressed: onDuplicate,
                  icon: const Icon(Icons.content_copy_rounded, size: 18),
                ),
              if (canArchive && onToggleActive != null)
                IconButton.filledTonal(
                  tooltip: record.isActive ? 'Pasife Al' : 'Aktifleştir',
                  onPressed: onToggleActive,
                  icon: Icon(
                    record.isActive
                        ? Icons.delete_outline_rounded
                        : Icons.restore_rounded,
                    size: 18,
                  ),
                ),
              if (canDeletePermanently && onDeletePermanently != null)
                IconButton.filledTonal(
                  tooltip: 'Kalıcı Sil',
                  onPressed: onDeletePermanently,
                  icon: const Icon(Icons.delete_forever_rounded, size: 18),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const Gap(6),
          Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: const Color(0xFF475569)),
          ),
        ],
      ),
    );
  }
}

class _FaultCustomerOption {
  const _FaultCustomerOption({
    required this.id,
    required this.name,
    required this.vkn,
    required this.city,
    required this.address,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? vkn;
  final String? city;
  final String? address;
  final bool isActive;

  factory _FaultCustomerOption.fromJson(Map<String, dynamic> json) {
    return _FaultCustomerOption(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      vkn: json['vkn']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class _DeviceRegistryOption {
  const _DeviceRegistryOption({required this.registryNumber, required this.model});

  final String registryNumber;
  final String? model;

  factory _DeviceRegistryOption.fromJson(Map<String, dynamic> json) {
    return _DeviceRegistryOption(
      registryNumber: (json['registry_number'] ?? '').toString(),
      model: json['model']?.toString(),
    );
  }
}

class _FaultFormDialog extends ConsumerStatefulWidget {
  const _FaultFormDialog({this.initialRecord, this.duplicateMode = false});

  final FaultFormRecord? initialRecord;
  final bool duplicateMode;

  bool get isEdit => initialRecord != null && !duplicateMode;

  @override
  ConsumerState<_FaultFormDialog> createState() => _FaultFormDialogState();
}

class _FaultFormDialogState extends ConsumerState<_FaultFormDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _selectedCustomerId;
  DateTime? _lastZReportDate;

  late final TextEditingController _customerNameController;
  late final TextEditingController _customerAddressController;
  late final TextEditingController _customerTaxOfficeController;
  late final TextEditingController _customerVknController;
  late final TextEditingController _deviceBrandModelController;
  late final TextEditingController _companyCodeController;
  late final TextEditingController _okcApprovalController;
  late final TextEditingController _faultDateTimeController;
  late final TextEditingController _faultDescriptionController;
  late final TextEditingController _lastZDateController;
  late final TextEditingController _lastZNoController;
  late final TextEditingController _totalRevenueController;
  late final TextEditingController _totalVatController;

  static const _brandModelOptions = <String>[
    'INGENICO IDE280',
    'INGENICO MOVE5000F',
    'PAX A910SF',
  ];
  String? _brandModelPreset;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    _selectedCustomerId = initial?.customerId;
    _lastZReportDate = initial?.lastZReportDate ?? DateTime.now();

    _customerNameController =
        TextEditingController(text: initial?.customerName ?? '');
    _customerAddressController =
        TextEditingController(text: initial?.customerAddress ?? '');
    _customerTaxOfficeController =
        TextEditingController(text: initial?.customerTaxOffice ?? '');
    _customerVknController = TextEditingController(text: initial?.customerVkn ?? '');

    _deviceBrandModelController =
        TextEditingController(text: initial?.deviceBrandModel ?? '');
    final currentBrandModel = _deviceBrandModelController.text.trim();
    _brandModelPreset =
        _brandModelOptions.contains(currentBrandModel) ? currentBrandModel : null;
    _companyCodeController =
        TextEditingController(text: initial?.companyCodeAndRegistry ?? '');
    _okcApprovalController =
        TextEditingController(text: initial?.okcApprovalDateAndNumber ?? '');
    _faultDateTimeController = TextEditingController(
      text: initial?.faultDateTimeText ??
          DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(DateTime.now()),
    );
    _faultDescriptionController =
        TextEditingController(text: initial?.faultDescription ?? '');
    _lastZDateController = TextEditingController(
      text: DateFormat('dd.MM.yyyy', 'tr_TR').format(_lastZReportDate!),
    );
    _lastZNoController = TextEditingController(text: initial?.lastZReportNo ?? '');
    _totalRevenueController =
        TextEditingController(text: initial?.totalRevenue ?? '');
    _totalVatController = TextEditingController(text: initial?.totalVat ?? '');
  }

  @override
  void dispose() {
    _customerNameController.dispose();
    _customerAddressController.dispose();
    _customerTaxOfficeController.dispose();
    _customerVknController.dispose();
    _deviceBrandModelController.dispose();
    _companyCodeController.dispose();
    _okcApprovalController.dispose();
    _faultDateTimeController.dispose();
    _faultDescriptionController.dispose();
    _lastZDateController.dispose();
    _lastZNoController.dispose();
    _totalRevenueController.dispose();
    _totalVatController.dispose();
    super.dispose();
  }

  Future<void> _pickLastZDate() async {
    if (_saving) return;
    final base = _lastZReportDate ?? DateTime.now();
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) {
        var selected = base;
        return AlertDialog(
          title: const Text("Son 'Z' Raporu Tarihi"),
          content: SizedBox(
            width: 420,
            height: 380,
            child: CalendarDatePicker(
              initialDate: base,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
              onDateChanged: (d) => selected = d,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(selected),
              child: const Text('Seç'),
            ),
          ],
        );
      },
    );
    if (picked == null) return;
    setState(() => _lastZReportDate = picked);
    _lastZDateController.text = DateFormat('dd.MM.yyyy', 'tr_TR').format(picked);
  }

  @override
  Widget build(BuildContext context) {
    final customersAsync = ref.watch(faultFormCustomersProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    final todayText = DateFormat('dd.MM.yyyy', 'tr_TR').format(DateTime.now());

    return AlertDialog(
      title: Text(widget.isEdit ? 'Arıza formunu düzenle' : 'Yeni arıza formu'),
      content: SizedBox(
        width: isMobile ? double.infinity : 860,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppCard(
                  padding: const EdgeInsets.all(14),
                  color: const Color(0xFFEEF2FF),
                  child: Row(
                    children: [
                      Icon(Icons.calendar_today_rounded,
                          size: 18, color: AppTheme.primary),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          'Tarih (mavi alan): $todayText',
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: const Color(0xFF1E3A8A),
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Gap(12),
                customersAsync.when(
                  data: (customers) {
                    final selected = customers
                        .where((c) => c.id == _selectedCustomerId)
                        .cast<_FaultCustomerOption?>()
                        .firstWhere((_) => true, orElse: () => null);
                    if (selected != null) {
                      if (_customerNameController.text.trim().isEmpty ||
                          !widget.isEdit) {
                        _customerNameController.text = selected.name;
                      }
                      if (_customerAddressController.text.trim().isEmpty ||
                          !widget.isEdit) {
                        _customerAddressController.text =
                            (selected.address ?? '').trim();
                      }
                      if (_customerTaxOfficeController.text.trim().isEmpty ||
                          !widget.isEdit) {
                        _customerTaxOfficeController.text =
                            (selected.city ?? '').trim();
                      }
                      if (_customerVknController.text.trim().isEmpty ||
                          !widget.isEdit) {
                        _customerVknController.text = (selected.vkn ?? '').trim();
                      }
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DropdownButtonFormField<String>(
                          key: ValueKey(_selectedCustomerId ?? ''),
                          initialValue: _selectedCustomerId ?? '',
                          decoration:
                              const InputDecoration(labelText: 'Müşteri seç'),
                          items: [
                            const DropdownMenuItem<String>(
                              value: '',
                              child: Text('Müşteri seç'),
                            ),
                            ...customers.map(
                              (c) => DropdownMenuItem<String>(
                                value: c.id,
                                child: Text(c.name),
                              ),
                            ),
                          ],
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return 'Müşteri seçin';
                            }
                            return null;
                          },
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _selectedCustomerId =
                                  (value == null || value.isEmpty) ? null : value),
                        ),
                        const Gap(10),
                        if (selected != null)
                          AppCard(
                            padding: const EdgeInsets.all(14),
                            color: const Color(0xFFFEF2F2),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Müşteri Bilgisi (kırmızı alanlar - düzenlenebilir)',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleSmall
                                      ?.copyWith(color: const Color(0xFF7F1D1D)),
                                ),
                                const Gap(10),
                                TextFormField(
                                  controller: _customerNameController,
                                  decoration: const InputDecoration(
                                    labelText: 'Adı Soyadı / Ünvanı',
                                  ),
                                ),
                                const Gap(6),
                                TextFormField(
                                  controller: _customerAddressController,
                                  decoration: const InputDecoration(
                                    labelText: 'Adres',
                                  ),
                                ),
                                const Gap(6),
                                Row(
                                  children: [
                                    Expanded(
                                      child: TextFormField(
                                        controller: _customerVknController,
                                        decoration: const InputDecoration(
                                          labelText: 'Vergi Sicil No.',
                                        ),
                                      ),
                                    ),
                                    const Gap(10),
                                    Expanded(
                                      child: TextFormField(
                                        controller: _customerTaxOfficeController,
                                        decoration: const InputDecoration(
                                          labelText: 'Vergi Dairesi',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                      ],
                    );
                  },
                  loading: () => const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => Text('Müşteriler yüklenemedi: $e'),
                ),
                const Gap(12),
                AppCard(
                  padding: const EdgeInsets.all(14),
                  color: const Color(0xFFFFFBEB),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Form Alanları (sarı alanlar)',
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(color: const Color(0xFF78350F)),
                      ),
                      const Gap(12),
                      DropdownButtonFormField<String>(
                        key: ValueKey(_brandModelPreset ?? ''),
                        initialValue: _brandModelPreset ?? '',
                        items: [
                          const DropdownMenuItem(
                            value: '',
                            child: Text('Seçiniz'),
                          ),
                          for (final e in _brandModelOptions)
                            DropdownMenuItem(value: e, child: Text(e)),
                          const DropdownMenuItem(
                            value: '__other__',
                            child: Text('Diğer'),
                          ),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Marka ve Modeli',
                        ),
                        onChanged: _saving
                            ? null
                            : (value) {
                                setState(() => _brandModelPreset =
                                    (value == null || value.isEmpty || value == '__other__')
                                        ? null
                                        : value);
                                if (value == null || value.isEmpty) {
                                  _deviceBrandModelController.text = '';
                                } else if (value == '__other__') {
                                  _deviceBrandModelController.text = '';
                                } else {
                                  _deviceBrandModelController.text = value;
                                }
                              },
                      ),
                      if (_brandModelPreset == null &&
                          !_brandModelOptions.contains(
                            _deviceBrandModelController.text.trim(),
                          )) ...[
                        const Gap(10),
                        TextFormField(
                          controller: _deviceBrandModelController,
                          decoration: const InputDecoration(
                            labelText: 'Marka/Model (manuel)',
                          ),
                        ),
                      ],
                      const Gap(10),
                      if ((_selectedCustomerId ?? '').trim().isNotEmpty)
                        ref
                            .watch(
                              faultCustomerDeviceRegistriesProvider(
                                _selectedCustomerId!.trim(),
                              ),
                            )
                            .when(
                              data: (items) {
                                if (items.isEmpty) return const SizedBox.shrink();
                                final current = _companyCodeController.text.trim();
                                final initialValue = items.any(
                                  (e) => e.registryNumber.trim() == current,
                                )
                                    ? current
                                    : null;
                                return Column(
                                  children: [
                                    DropdownButtonFormField<String?>(
                                      initialValue: initialValue,
                                      items: [
                                        const DropdownMenuItem<String?>(
                                          value: null,
                                          child: Text('Sicil seç'),
                                        ),
                                        ...items.map(
                                          (e) => DropdownMenuItem<String?>(
                                            value: e.registryNumber.trim(),
                                            child: Text(
                                              [
                                                e.registryNumber.trim(),
                                                if ((e.model ?? '').trim().isNotEmpty)
                                                  e.model!.trim(),
                                              ].join(' • '),
                                            ),
                                          ),
                                        ),
                                      ],
                                      onChanged: _saving
                                          ? null
                                          : (value) {
                                              final v = (value ?? '').trim();
                                              if (v.isEmpty) return;
                                              setState(() {
                                                _companyCodeController.text = v;
                                              });
                                            },
                                      decoration: const InputDecoration(
                                        labelText: 'Müşteri Sicilleri',
                                      ),
                                    ),
                                    const Gap(10),
                                  ],
                                );
                              },
                              loading: () => const SizedBox.shrink(),
                              error: (_, _) => const SizedBox.shrink(),
                            ),
                      TextFormField(
                        controller: _companyCodeController,
                        decoration: const InputDecoration(
                          labelText: 'Firma Kodu ve Sicil No',
                        ),
                      ),
                      const Gap(10),
                      TextFormField(
                        controller: _okcApprovalController,
                        decoration: const InputDecoration(
                          labelText:
                              "Onay Belgesi Tarih ve No'su",
                        ),
                      ),
                      const Gap(10),
                      TextFormField(
                        controller: _faultDateTimeController,
                        decoration: const InputDecoration(
                          labelText: 'Arıza Tarih ve Saati',
                        ),
                      ),
                      const Gap(10),
                      TextFormField(
                        controller: _faultDescriptionController,
                        minLines: 3,
                        maxLines: 6,
                        decoration: const InputDecoration(
                          labelText: 'Arıza Tarifi',
                        ),
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _lastZDateController,
                              readOnly: true,
                              decoration: const InputDecoration(
                                labelText: "Son 'Z' Raporu Tarihi",
                                suffixIcon: Icon(Icons.calendar_today_rounded),
                              ),
                              onTap: _pickLastZDate,
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: TextFormField(
                              controller: _lastZNoController,
                              decoration: const InputDecoration(
                                labelText: "Son 'Z' Raporu No",
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
                            child: TextFormField(
                              controller: _totalRevenueController,
                              decoration: const InputDecoration(
                                labelText: 'Toplam Hasılat',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [CurrencyTextInputFormatter()],
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: TextFormField(
                              controller: _totalVatController,
                              decoration: const InputDecoration(
                                labelText: 'Toplam KDV',
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: const [CurrencyTextInputFormatter()],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;

    final customers = ref.read(faultFormCustomersProvider).value ?? const [];
    final selected = customers.where((c) => c.id == _selectedCustomerId).cast<_FaultCustomerOption?>().firstWhere((_) => true, orElse: () => null);
    if (selected == null) return;

    setState(() => _saving = true);
    try {
      final apiClient = ref.read(apiClientProvider);
      final client = ref.read(supabaseClientProvider);
      final profile = await ref.read(currentUserProfileProvider.future);

      final payload = <String, dynamic>{
        if (widget.isEdit) 'id': widget.initialRecord!.id,
        'form_date': (widget.isEdit
                ? widget.initialRecord!.formDate
                : DateTime.now())
            .toIso8601String(),
        'customer_id': selected.id,
        'customer_name': _customerNameController.text.trim().isEmpty
            ? selected.name
            : _customerNameController.text.trim(),
        'customer_address': _customerAddressController.text.trim().isEmpty
            ? selected.address
            : _customerAddressController.text.trim(),
        'customer_tax_office': _customerTaxOfficeController.text.trim().isEmpty
            ? selected.city
            : _customerTaxOfficeController.text.trim(),
        'customer_vkn': _customerVknController.text.trim().isEmpty
            ? selected.vkn
            : _customerVknController.text.trim(),
        'device_brand_model': _deviceBrandModelController.text.trim().isEmpty
            ? null
            : _deviceBrandModelController.text.trim(),
        'company_code_and_registry': _companyCodeController.text.trim().isEmpty
            ? null
            : _companyCodeController.text.trim(),
        'okc_approval_date_and_number': _okcApprovalController.text.trim().isEmpty
            ? null
            : _okcApprovalController.text.trim(),
        'fault_date_time_text': _faultDateTimeController.text.trim().isEmpty
            ? null
            : _faultDateTimeController.text.trim(),
        'fault_description': _faultDescriptionController.text.trim().isEmpty
            ? null
            : _faultDescriptionController.text.trim(),
        'last_z_report_date':
            _lastZReportDate?.toIso8601String(),
        'last_z_report_no': _lastZNoController.text.trim().isEmpty
            ? null
            : _lastZNoController.text.trim(),
        'last_z_report_date_and_number': [
          if (_lastZReportDate != null)
            DateFormat('dd.MM.yyyy', 'tr_TR').format(_lastZReportDate!),
          if (_lastZNoController.text.trim().isNotEmpty) _lastZNoController.text.trim(),
        ].join('   ').trim().isEmpty
            ? null
            : [
                if (_lastZReportDate != null)
                  DateFormat('dd.MM.yyyy', 'tr_TR').format(_lastZReportDate!),
                if (_lastZNoController.text.trim().isNotEmpty)
                  _lastZNoController.text.trim(),
              ].join('   '),
        'total_revenue': _totalRevenueController.text.trim().isEmpty
            ? null
            : _totalRevenueController.text.trim(),
        'total_vat': _totalVatController.text.trim().isEmpty
            ? null
            : _totalVatController.text.trim(),
        'is_active': true,
        if (profile?.id != null) 'created_by': profile!.id,
      };

      Map<String, dynamic> row;
      if (apiClient != null) {
        final response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'fault_forms',
            'returning': 'row',
            'values': payload,
          },
        );
        row = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
      } else {
        if (client == null) return;
        if (widget.isEdit) {
          row = await client
              .from('fault_forms')
              .update(payload)
              .eq('id', widget.initialRecord!.id)
              .select(
                'id,form_date,customer_id,customer_name,customer_address,customer_tax_office,customer_vkn,device_brand_model,company_code_and_registry,okc_approval_date_and_number,fault_date_time_text,fault_description,last_z_report_date_and_number,last_z_report_date,last_z_report_no,total_revenue,total_vat,is_active,created_at',
              )
              .single();
        } else {
          final inserted = await client
              .from('fault_forms')
              .insert(payload)
              .select(
                'id,form_date,customer_id,customer_name,customer_address,customer_tax_office,customer_vkn,device_brand_model,company_code_and_registry,okc_approval_date_and_number,fault_date_time_text,fault_description,last_z_report_date_and_number,last_z_report_date,last_z_report_no,total_revenue,total_vat,is_active,created_at',
              )
              .single();
          row = inserted;
        }
      }

      if (!mounted) return;
      Navigator.of(context).pop(FaultFormRecord.fromJson(row));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String _sortKey(String input) {
  final text = input.toLowerCase().trim();
  const map = {
    'ç': 'c',
    'ğ': 'g',
    'ı': 'i',
    'ö': 'o',
    'ş': 's',
    'ü': 'u',
  };
  var out = text;
  map.forEach((k, v) => out = out.replaceAll(k, v));
  return out;
}
