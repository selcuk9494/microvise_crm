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
import '../billing/invoice_queue_helper.dart';
import '../customers/customer_form_dialog.dart';
import '../definitions/definitions_screen.dart';
import 'transfer_form_model.dart';
import 'transfer_form_print.dart';

final transferFormCustomersProvider =
    FutureProvider<List<_TransferCustomerOption>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      final client = ref.watch(supabaseClientProvider);
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {'resource': 'form_transfer_customers'},
        );
        final items = ((response['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(_TransferCustomerOption.fromJson)
            .toList(growable: false);
        items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
        return items;
      }
      if (client == null) return const [];

      const pageSize = 500;
      var from = 0;
      final items = <_TransferCustomerOption>[];

      while (true) {
        final rows = await client
            .from('customers')
            .select('id,name,vkn,city,address,is_active,branches(address)')
            .range(from, from + pageSize - 1);
        final batch = (rows as List)
            .map(
              (row) =>
                  _TransferCustomerOption.fromJson(row as Map<String, dynamic>),
            )
            .toList(growable: false);
        items.addAll(batch);
        if (batch.length < pageSize) break;
        from += pageSize;
      }

      items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
      return items;
    });

final transferCustomerDeviceRegistriesProvider =
    FutureProvider.family<List<_TransferDeviceRegistryOption>, String>((
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
        .map(_TransferDeviceRegistryOption.fromJson)
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
      .map((e) => _TransferDeviceRegistryOption.fromJson(e as Map<String, dynamic>))
      .where((e) => e.registryNumber.trim().isNotEmpty)
      .toList(growable: false);
});

final transferFormsProvider = FutureProvider<List<TransferFormRecord>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'form_transfer_list'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(TransferFormRecord.fromJson)
        .toList(growable: false);
  }
  if (client == null) return const [];

  try {
    final rows = await client
        .from('transfer_forms')
        .select(
          'id,row_number,transferor_name,transferor_address,transferor_tax_office_and_registry,transferor_approval_date_no,transferee_name,transferee_address,transferee_tax_office_and_registry,transferee_approval_date_no,total_sales_receipt,vat_collected,last_receipt_date_no,z_report_count,other_device_info,brand_model,device_serial_no,fiscal_symbol_company_code,department_count,transfer_date,transfer_reason,is_active,created_at',
        )
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List)
        .map((row) => TransferFormRecord.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

class TransferFormScreen extends ConsumerStatefulWidget {
  const TransferFormScreen({super.key});

  @override
  ConsumerState<TransferFormScreen> createState() => _TransferFormScreenState();
}

class _TransferFormScreenState extends ConsumerState<TransferFormScreen> {
  final _customerFilterController = TextEditingController();
  final _deviceFilterController = TextEditingController();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  bool _showPassive = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _customerFilterController.dispose();
    _deviceFilterController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime? currentValue,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      locale: const Locale('tr', 'TR'),
    );
    if (picked == null) return;
    onSelected(picked);
  }

  Future<void> _openCreateDialog() async {
    final saved = await showDialog<TransferFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _TransferFormDialog(),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(transferFormsProvider.future);
    await _print(saved);
  }

  Future<void> _openEditDialog(TransferFormRecord record) async {
    final saved = await showDialog<TransferFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _TransferFormDialog(initialRecord: record),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(transferFormsProvider.future);
  }

  Future<void> _openDuplicateDialog(TransferFormRecord record) async {
    final saved = await showDialog<TransferFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _TransferFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(transferFormsProvider.future);
    await _print(saved);
  }

  Future<void> _print(TransferFormRecord record) async {
    final settings = ref.read(transferFormPrintSettingsProvider).maybeWhen(
          data: (value) => value,
          orElse: () => TransferFormPrintSettings.defaults,
        );
    bool ok = false;
    Object? error;
    try {
      ok = await printTransferForm(record, settings: settings);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? 'Devir formu yazdırma hatası: $error'
              : ok
                  ? 'Devir formu çıktısı hazırlandı.'
                  : 'Devir formu çıktısı bu platformda açılamadı.',
        ),
      ),
    );
  }

  Future<void> _setRecordActive(TransferFormRecord record, bool active) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'transfer_forms',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': record.id},
            ],
            'values': {'is_active': active},
          },
        );
      } else {
        if (client == null) return;
        await client
            .from('transfer_forms')
            .update({'is_active': active})
            .eq('id', record.id);
      }
      ref.invalidate(transferFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active ? 'Devir formu aktifleştirildi.' : 'Devir formu pasife alındı.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('İşlem başarısız: $e')),
      );
    }
  }

  Future<void> _deleteRecordPermanently(TransferFormRecord record) async {
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
        title: const Text('Devir formunu kalıcı sil'),
        content: Text(
          '"${record.transferorName} → ${record.transfereeName}" kaydı kalıcı olarak silinecek. Bu işlem geri alınamaz.',
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
          body: {'op': 'delete', 'table': 'transfer_forms', 'id': record.id},
        );
      } else {
        if (client == null) return;
        await client.from('transfer_forms').delete().eq('id', record.id);
      }
      ref.invalidate(transferFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Devir formu kalıcı olarak silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }

  List<TransferFormRecord> _filter(List<TransferFormRecord> records) {
    final customerQuery = _sortKey(_customerFilterController.text);
    final deviceQuery = _sortKey(_deviceFilterController.text);
    return records
        .where((item) {
          if (customerQuery.isNotEmpty &&
              !_sortKey(
                '${item.transferorName} ${item.transfereeName}',
              ).contains(customerQuery)) {
            return false;
          }
          if (deviceQuery.isNotEmpty &&
              !_sortKey(
                '${item.brandModel ?? ''} ${item.deviceSerialNo ?? ''}',
              ).contains(deviceQuery)) {
            return false;
          }
          if (_fromDate != null && item.transferDate.isBefore(_fromDate!)) {
            return false;
          }
          if (_toDate != null) {
            final inclusive = DateTime(
              _toDate!.year,
              _toDate!.month,
              _toDate!.day,
              23,
              59,
              59,
            );
            if (item.transferDate.isAfter(inclusive)) return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 820;
    final recordsAsync = ref.watch(transferFormsProvider);
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDeletePermanently = ref.watch(
      hasActionAccessProvider(kActionDeleteRecords),
    );

    return AppPageLayout(
      title: 'Devir Formları',
      subtitle: 'Kullanılmış ödeme kaydedici cihaz devir kayıtlarını yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(transferFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: _openCreateDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Devir Formu'),
        ),
      ],
      body: recordsAsync.when(
        data: (records) {
          final filtered = _filter(records)
              .where((item) => _showPassive || item.isActive)
              .toList(growable: false);
          final filterCard = AppCard(
            child: Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: TextField(
                    controller: _customerFilterController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Devreden / Devralan',
                      prefixIcon: Icon(Icons.people_alt_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 280,
                  child: TextField(
                    controller: _deviceFilterController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cihaz / Sicil',
                      prefixIcon: Icon(Icons.memory_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 180,
                  child: TextField(
                    controller: TextEditingController(
                      text:
                          _fromDate == null ? '' : _dateFormat.format(_fromDate!),
                    ),
                    readOnly: true,
                    onTap: () => _pickDate(
                      currentValue: _fromDate,
                      onSelected: (value) => setState(() => _fromDate = value),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Başlangıç',
                      prefixIcon: Icon(Icons.calendar_today_rounded),
                    ),
                  ),
                ),
                SizedBox(
                  width: isMobile ? double.infinity : 180,
                  child: TextField(
                    controller: TextEditingController(
                      text: _toDate == null ? '' : _dateFormat.format(_toDate!),
                    ),
                    readOnly: true,
                    onTap: () => _pickDate(
                      currentValue: _toDate,
                      onSelected: (value) => setState(() => _toDate = value),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Bitiş',
                      prefixIcon: Icon(Icons.event_rounded),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _customerFilterController.clear();
                      _deviceFilterController.clear();
                      _fromDate = null;
                      _toDate = null;
                      _showPassive = false;
                    });
                  },
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                  label: const Text('Temizle'),
                ),
                FilterChip(
                  selected: _showPassive,
                  onSelected: (value) => setState(() => _showPassive = value),
                  label: const Text('Pasifleri Göster'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          );

          final statsCard = AppCard(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                AppBadge(
                  label: 'Toplam: ${records.length}',
                  tone: AppBadgeTone.primary,
                ),
                AppBadge(
                  label: 'Filtrelenen: ${filtered.length}',
                  tone: AppBadgeTone.warning,
                ),
              ],
            ),
          );

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 120),
            itemCount: filtered.isEmpty ? 3 : filtered.length + 2,
            separatorBuilder: (_, _) => const Gap(12),
            itemBuilder: (context, index) {
              if (index == 0) return filterCard;
              if (index == 1) return statsCard;
              if (filtered.isEmpty) {
                return const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Henüz devir formu kaydı yok.')),
                  ),
                );
              }
              final record = filtered[index - 2];
              return _TransferRecordCard(
                record: record,
                canEdit: canEdit,
                canArchive: canArchive,
                canDeletePermanently: canDeletePermanently,
                onEdit: () => _openEditDialog(record),
                onDuplicate: () => _openDuplicateDialog(record),
                onPrint: () => _print(record),
                onToggleActive: canArchive
                    ? () => _setRecordActive(record, !record.isActive)
                    : null,
                onDeletePermanently: canDeletePermanently
                    ? () => _deleteRecordPermanently(record)
                    : null,
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Yüklenemedi.')),
      ),
    );
  }
}

class _TransferDeviceRegistryOption {
  const _TransferDeviceRegistryOption({required this.registryNumber, required this.model});

  final String registryNumber;
  final String? model;

  factory _TransferDeviceRegistryOption.fromJson(Map<String, dynamic> json) {
    return _TransferDeviceRegistryOption(
      registryNumber: (json['registry_number'] ?? '').toString(),
      model: json['model']?.toString(),
    );
  }
}

class _TransferFormDialog extends ConsumerStatefulWidget {
  const _TransferFormDialog({this.initialRecord, this.duplicateMode = false});

  final TransferFormRecord? initialRecord;
  final bool duplicateMode;

  bool get isEdit => initialRecord != null && !duplicateMode;

  @override
  ConsumerState<_TransferFormDialog> createState() =>
      _TransferFormDialogState();
}

class _TransferRecordCard extends StatelessWidget {
  const _TransferRecordCard({
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

  final TransferFormRecord record;
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
    final dateText = DateFormat('d MMM y', 'tr_TR').format(record.transferDate);
    final badgeLabel = record.isActive ? 'KDV 15' : 'Pasif';
    final badgeTone =
        record.isActive ? AppBadgeTone.primary : AppBadgeTone.neutral;

    return AppCard(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 10 : 12, vertical: 10),
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
                        '${record.transferorName} → ${record.transfereeName}',
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
                    _TransferInfoChip(
                      icon: Icons.calendar_today_rounded,
                      text: dateText,
                    ),
                    if ((record.rowNumber ?? '').trim().isNotEmpty)
                      _TransferInfoChip(
                        icon: Icons.tag_rounded,
                        text: 'Sıra: ${record.rowNumber!.trim()}',
                      ),
                    if ((record.brandModel ?? '').trim().isNotEmpty)
                      _TransferInfoChip(
                        icon: Icons.memory_rounded,
                        text: record.brandModel!.trim(),
                      ),
                    if ((record.deviceSerialNo ?? '').trim().isNotEmpty)
                      _TransferInfoChip(
                        icon: Icons.badge_rounded,
                        text: record.deviceSerialNo!.trim(),
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

class _TransferInfoChip extends StatelessWidget {
  const _TransferInfoChip({required this.icon, required this.text});

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

class _TransferFormDialogState extends ConsumerState<_TransferFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final _rowNumberController = TextEditingController();
  final _transferorController = TextEditingController();
  final _transferorAddressController = TextEditingController();
  final _transferorTaxController = TextEditingController();
  final _transferorApprovalController = TextEditingController();
  final _transfereeController = TextEditingController();
  final _transfereeAddressController = TextEditingController();
  final _transfereeTaxController = TextEditingController();
  final _transfereeApprovalController = TextEditingController();
  final _totalSalesController = TextEditingController();
  final _vatCollectedController = TextEditingController();
  final _lastReceiptController = TextEditingController();
  final _zReportController = TextEditingController();
  final _otherInfoController = TextEditingController();
  final _brandModelController = TextEditingController();
  final _deviceSerialController = TextEditingController();
  final _fiscalSymbolController = TextEditingController();
  final _departmentCountController = TextEditingController();
  final _transferReasonController = TextEditingController();
  String? _transferorCustomerId;
  String? _transfereeCustomerId;
  DateTime _transferDate = DateTime.now();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial != null) {
      _rowNumberController.text = initial.rowNumber ?? '';
      _transferorController.text = initial.transferorName;
      _transferorAddressController.text = initial.transferorAddress ?? '';
      _transferorTaxController.text =
          initial.transferorTaxOfficeAndRegistry ?? '';
      _transferorApprovalController.text =
          initial.transferorApprovalDateNo ?? '';
      _transfereeController.text = initial.transfereeName;
      _transfereeAddressController.text = initial.transfereeAddress ?? '';
      _transfereeTaxController.text =
          initial.transfereeTaxOfficeAndRegistry ?? '';
      _transfereeApprovalController.text =
          initial.transfereeApprovalDateNo ?? '';
      _totalSalesController.text = formatCurrencyDisplay(
        initial.totalSalesReceipt,
      );
      _vatCollectedController.text = formatCurrencyDisplay(
        initial.vatCollected,
      );
      _lastReceiptController.text = initial.lastReceiptDateNo ?? '';
      _zReportController.text = initial.zReportCount ?? '';
      _otherInfoController.text = initial.otherDeviceInfo ?? '';
      _brandModelController.text = initial.brandModel ?? '';
      _deviceSerialController.text = initial.deviceSerialNo ?? '';
      _fiscalSymbolController.text = initial.fiscalSymbolCompanyCode ?? '';
      _departmentCountController.text = initial.departmentCount ?? '';
      _transferReasonController.text = initial.transferReason ?? '';
      _transferDate = initial.transferDate;
    }
  }

  @override
  void dispose() {
    _rowNumberController.dispose();
    _transferorController.dispose();
    _transferorAddressController.dispose();
    _transferorTaxController.dispose();
    _transferorApprovalController.dispose();
    _transfereeController.dispose();
    _transfereeAddressController.dispose();
    _transfereeTaxController.dispose();
    _transfereeApprovalController.dispose();
    _totalSalesController.dispose();
    _vatCollectedController.dispose();
    _lastReceiptController.dispose();
    _zReportController.dispose();
    _otherInfoController.dispose();
    _brandModelController.dispose();
    _deviceSerialController.dispose();
    _fiscalSymbolController.dispose();
    _departmentCountController.dispose();
    _transferReasonController.dispose();
    super.dispose();
  }

  Future<void> _pickTransferDate() async {
    DateTime tempDate = _transferDate;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Devir Tarihi Seç'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: CalendarDatePicker(
            initialDate: _transferDate,
            firstDate: DateTime(2020),
            lastDate: DateTime(2100),
            onDateChanged: (value) => tempDate = value,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(tempDate),
            child: const Text('Seç'),
          ),
        ],
      ),
    );
    if (picked == null) return;
    setState(() => _transferDate = picked);
  }

  Future<void> _createCustomer() async {
    final id = await showCreateCustomerDialog(context);
    if (id == null) return;
    ref.invalidate(transferFormCustomersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final customers = await ref.read(transferFormCustomersProvider.future);
    final created = customers.where((item) => item.id == id).firstOrNull;
    if (created == null || !mounted) return;
    setState(() {
      _transfereeCustomerId = created.id;
      _transfereeController.text = created.name;
      _transfereeTaxController.text = [
        if ((created.city ?? '').trim().isNotEmpty) created.city!.trim(),
        if ((created.vkn ?? '').trim().isNotEmpty) created.vkn!.trim(),
      ].join(' ');
      if ((created.address ?? '').trim().isNotEmpty) {
        _transfereeAddressController.text = created.address!.trim();
      }
    });
  }

  Future<void> _pickCustomer({
    required List<_TransferCustomerOption> customers,
    required bool isTransferor,
  }) async {
    final selected = await showDialog<_TransferCustomerOption>(
      context: context,
      builder: (context) => _TransferCustomerPickerDialog(
        customers: customers,
        initialSelectedId: isTransferor
            ? _transferorCustomerId
            : _transfereeCustomerId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      final taxText = [
        if ((selected.city ?? '').trim().isNotEmpty) selected.city!.trim(),
        if ((selected.vkn ?? '').trim().isNotEmpty) selected.vkn!.trim(),
      ].join(' ');
      if (isTransferor) {
        _transferorCustomerId = selected.id;
        _transferorController.text = selected.name;
        _transferorTaxController.text = taxText;
        if ((selected.address ?? '').trim().isNotEmpty) {
          _transferorAddressController.text = selected.address!.trim();
        }
      } else {
        _transfereeCustomerId = selected.id;
        _transfereeController.text = selected.name;
        _transfereeTaxController.text = taxText;
        if ((selected.address ?? '').trim().isNotEmpty) {
          _transfereeAddressController.text = selected.address!.trim();
        }
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;
    setState(() => _saving = true);
    try {
      final payload = {
        'row_number': _rowNumberController.text.trim().isEmpty
            ? null
            : _rowNumberController.text.trim(),
        'transferor_customer_id': _transferorCustomerId,
        'transferor_name': _transferorController.text.trim(),
        'transferor_address': _transferorAddressController.text.trim().isEmpty
            ? null
            : _transferorAddressController.text.trim(),
        'transferor_tax_office_and_registry':
            _transferorTaxController.text.trim().isEmpty
            ? null
            : _transferorTaxController.text.trim(),
        'transferor_approval_date_no':
            _transferorApprovalController.text.trim().isEmpty
            ? null
            : _transferorApprovalController.text.trim(),
        'transferee_customer_id': _transfereeCustomerId,
        'transferee_name': _transfereeController.text.trim(),
        'transferee_address': _transfereeAddressController.text.trim().isEmpty
            ? null
            : _transfereeAddressController.text.trim(),
        'transferee_tax_office_and_registry':
            _transfereeTaxController.text.trim().isEmpty
            ? null
            : _transfereeTaxController.text.trim(),
        'transferee_approval_date_no':
            _transfereeApprovalController.text.trim().isEmpty
            ? null
            : _transfereeApprovalController.text.trim(),
        'total_sales_receipt': _totalSalesController.text.trim().isEmpty
            ? null
            : _totalSalesController.text.trim(),
        'vat_collected': _vatCollectedController.text.trim().isEmpty
            ? null
            : _vatCollectedController.text.trim(),
        'last_receipt_date_no': _lastReceiptController.text.trim().isEmpty
            ? null
            : _lastReceiptController.text.trim(),
        'z_report_count': _zReportController.text.trim().isEmpty
            ? null
            : _zReportController.text.trim(),
        'other_device_info': _otherInfoController.text.trim().isEmpty
            ? null
            : _otherInfoController.text.trim(),
        'brand_model': _brandModelController.text.trim().isEmpty
            ? null
            : _brandModelController.text.trim(),
        'device_serial_no': _deviceSerialController.text.trim().isEmpty
            ? null
            : _deviceSerialController.text.trim(),
        'fiscal_symbol_company_code':
            _fiscalSymbolController.text.trim().isEmpty
            ? null
            : _fiscalSymbolController.text.trim(),
        'department_count': _departmentCountController.text.trim().isEmpty
            ? null
            : _departmentCountController.text.trim(),
        'transfer_date': DateFormat('yyyy-MM-dd').format(_transferDate),
        'transfer_reason': _transferReasonController.text.trim().isEmpty
            ? null
            : _transferReasonController.text.trim(),
      };
      Map<String, dynamic> inserted;
      if (apiClient != null) {
        final response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'transfer_forms',
            'returning': 'row',
            'values': {
              if (widget.isEdit) 'id': widget.initialRecord!.id,
              ...payload,
              if (!widget.isEdit) 'is_active': true,
            },
          },
        );
        inserted = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
        final sourceId = (response['id'] ?? '').toString();
        if (!widget.isEdit && sourceId.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'insertMany',
              'table': 'invoice_items',
              'rows': [
                {
                  'customer_id': _transferorCustomerId,
                  'item_type': 'transfer_form',
                  'source_table': 'transfer_forms',
                  'source_id': sourceId,
                  'description':
                      'Devir Formu - ${_transferorController.text.trim()} → ${_transfereeController.text.trim()}',
                  'amount': null,
                  'currency': 'TRY',
                  'status': 'pending',
                  'is_active': true,
                  'source_event': 'transfer_form_created',
                  'source_label': 'Devir Formu',
                },
              ],
            },
          );
        }
      } else {
        inserted =
            await (widget.isEdit
                    ? client!
                        .from('transfer_forms')
                        .update(payload)
                        .eq('id', widget.initialRecord!.id)
                    : client!.from('transfer_forms').insert(payload))
                .select(
                  'id,row_number,transferor_name,transferor_address,transferor_tax_office_and_registry,transferor_approval_date_no,transferee_name,transferee_address,transferee_tax_office_and_registry,transferee_approval_date_no,total_sales_receipt,vat_collected,last_receipt_date_no,z_report_count,other_device_info,brand_model,device_serial_no,fiscal_symbol_company_code,department_count,transfer_date,transfer_reason,is_active,created_at',
                )
                .single();
        if (!widget.isEdit) {
          await enqueueInvoiceItem(
            client,
            itemType: 'transfer_form',
            sourceTable: 'transfer_forms',
            sourceId: inserted['id'].toString(),
            description:
                'Devir Formu - ${_transferorController.text.trim()} → ${_transfereeController.text.trim()}',
            sourceEvent: 'transfer_form_created',
            sourceLabel: 'Devir Formu',
          );
        }
      }
      if (!mounted) return;
      Navigator.of(context).pop(TransferFormRecord.fromJson(inserted));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 760;
    final customersAsync = ref.watch(transferFormCustomersProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? 580 : 920),
        child: AppCard(
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          widget.isEdit
                              ? 'Devir Formunu Düzenle'
                              : 'Yeni Devir Formu',
                          style: Theme.of(context).textTheme.headlineSmall,
                        ),
                      ),
                      IconButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          controller: _rowNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Sıra No',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: _dateFormat.format(_transferDate),
                          ),
                          onTap: _pickTransferDate,
                          decoration: const InputDecoration(
                            labelText: 'Devir Tarihi',
                            prefixIcon: Icon(Icons.event_rounded),
                          ),
                        ),
                      ),
                      OutlinedButton(
                        onPressed: _saving ? null : _createCustomer,
                        child: const Text('Yeni Müşteri'),
                      ),
                    ],
                  ),
                  const Gap(12),
                  customersAsync.when(
                    data: (customers) => Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _transferorController,
                                readOnly: true,
                                validator: (value) =>
                                    (value?.trim().isEmpty ?? true)
                                    ? 'Devreden seçin'
                                    : null,
                                onTap: () => _pickCustomer(
                                  customers: customers,
                                  isTransferor: true,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Devreden Ünvanı',
                                  prefixIcon: Icon(Icons.arrow_upward_rounded),
                                ),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: TextFormField(
                                controller: _transfereeController,
                                readOnly: true,
                                validator: (value) =>
                                    (value?.trim().isEmpty ?? true)
                                    ? 'Devralan seçin'
                                    : null,
                                onTap: () => _pickCustomer(
                                  customers: customers,
                                  isTransferor: false,
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'Devralan Ünvanı',
                                  prefixIcon: Icon(
                                    Icons.arrow_downward_rounded,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    loading: () => const SizedBox(
                      height: 52,
                      child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                    error: (error, stackTrace) =>
                        const Text('Müşteriler yüklenemedi.'),
                  ),
                  const Gap(12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transferorAddressController,
                          decoration: const InputDecoration(
                            labelText: 'Devreden Adres',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transfereeAddressController,
                          decoration: const InputDecoration(
                            labelText: 'Devralan Adres',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transferorTaxController,
                          decoration: const InputDecoration(
                            labelText: 'Devreden Vergi Dairesi ve Sicil No',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transfereeTaxController,
                          decoration: const InputDecoration(
                            labelText: 'Devralan Vergi Dairesi ve Sicil No',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transferorApprovalController,
                          decoration: const InputDecoration(
                            labelText: 'Devreden Onay Belgesi Tarih ve No',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 430,
                        child: TextFormField(
                          controller: _transfereeApprovalController,
                          decoration: const InputDecoration(
                            labelText: 'Devralan Onay Belgesi Tarih ve No',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 200,
                        child: TextFormField(
                          controller: _totalSalesController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [CurrencyTextInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Toplam Hasılat Tutarı',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 200,
                        child: TextFormField(
                          controller: _vatCollectedController,
                          keyboardType: TextInputType.number,
                          inputFormatters: const [CurrencyTextInputFormatter()],
                          decoration: const InputDecoration(
                            labelText: 'Tahsil Edilen KDV Tutarı',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 240,
                        child: TextFormField(
                          controller: _lastReceiptController,
                          decoration: const InputDecoration(
                            labelText: 'Son Fiş Tarih ve No',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 180,
                        child: TextFormField(
                          controller: _zReportController,
                          decoration: const InputDecoration(
                            labelText: 'Z Raporu Sayısı',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 440,
                        child: TextFormField(
                          controller: _otherInfoController,
                          decoration: const InputDecoration(
                            labelText: 'Varsa Diğer Bilgiler',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 340,
                        child: TextFormField(
                          controller: _brandModelController,
                          decoration: const InputDecoration(
                            labelText: 'Marka ve Modeli',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 200,
                        child: (_transferorCustomerId ?? '').trim().isEmpty
                            ? TextFormField(
                                controller: _deviceSerialController,
                                decoration: const InputDecoration(
                                  labelText: 'Cihaz Sicil No',
                                ),
                              )
                            : ref
                                .watch(
                                  transferCustomerDeviceRegistriesProvider(
                                    _transferorCustomerId!.trim(),
                                  ),
                                )
                                .when(
                                  data: (items) {
                                    if (items.isEmpty) {
                                      return TextFormField(
                                        controller: _deviceSerialController,
                                        decoration: const InputDecoration(
                                          labelText: 'Cihaz Sicil No',
                                        ),
                                      );
                                    }
                                    final current =
                                        _deviceSerialController.text.trim();
                                    final initialValue = items.any(
                                      (e) => e.registryNumber.trim() == current,
                                    )
                                        ? current
                                        : null;
                                    return DropdownButtonFormField<String?>(
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
                                              final selected = items.firstWhere(
                                                (e) => e.registryNumber.trim() == v,
                                                orElse: () => items.first,
                                              );
                                              setState(() {
                                                _deviceSerialController.text = v;
                                                if (_brandModelController.text
                                                    .trim()
                                                    .isEmpty) {
                                                  final model =
                                                      (selected.model ?? '').trim();
                                                  if (model.isNotEmpty) {
                                                    _brandModelController.text =
                                                        model;
                                                  }
                                                }
                                              });
                                            },
                                      decoration: const InputDecoration(
                                        labelText: 'Cihaz Sicil No',
                                      ),
                                    );
                                  },
                                  loading: () => const SizedBox(
                                    height: 52,
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                  error: (_, _) => TextFormField(
                                    controller: _deviceSerialController,
                                    decoration: const InputDecoration(
                                      labelText: 'Cihaz Sicil No',
                                    ),
                                  ),
                                ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          controller: _fiscalSymbolController,
                          decoration: const InputDecoration(
                            labelText: 'Mali Sembol ve Firma Kodu',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 180,
                        child: TextFormField(
                          controller: _departmentCountController,
                          decoration: const InputDecoration(
                            labelText: 'Departman Sayısı',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _transferReasonController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Devir Nedeni',
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
                              : Text(widget.isEdit ? 'Güncelle' : 'Kaydet'),
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
}

class _TransferCustomerPickerDialog extends StatefulWidget {
  const _TransferCustomerPickerDialog({
    required this.customers,
    required this.initialSelectedId,
  });

  final List<_TransferCustomerOption> customers;
  final String? initialSelectedId;

  @override
  State<_TransferCustomerPickerDialog> createState() =>
      _TransferCustomerPickerDialogState();
}

class _TransferCustomerPickerDialogState
    extends State<_TransferCustomerPickerDialog> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _sortKey(_searchController.text);
    final items = widget.customers
        .where((item) {
          if (query.isEmpty) return true;
          return _sortKey(
            '${item.name} ${item.vkn ?? ''} ${item.city ?? ''}',
          ).contains(query);
        })
        .toList(growable: false);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 680),
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Müşteri Seç',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(12),
              TextField(
                controller: _searchController,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Ara',
                  hintText: 'Firma adı, VKN veya şehir',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
              const Gap(12),
              Expanded(
                child: items.isEmpty
                    ? const Center(child: Text('Eşleşen müşteri bulunamadı.'))
                    : ListView.separated(
                        itemCount: items.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final selected = item.id == widget.initialSelectedId;
                          return ListTile(
                            selected: selected,
                            selectedTileColor: AppTheme.primary.withValues(
                              alpha: 0.08,
                            ),
                            title: Text(item.name),
                            subtitle: Text(
                              [
                                if (item.vkn?.trim().isNotEmpty ?? false)
                                  item.vkn!,
                                if (item.city?.trim().isNotEmpty ?? false)
                                  item.city!,
                                item.isActive ? 'Aktif' : 'Pasif',
                              ].join(' • '),
                            ),
                            trailing: selected
                                ? const Icon(Icons.check_circle_rounded)
                                : null,
                            onTap: () => Navigator.of(context).pop(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TransferCustomerOption {
  const _TransferCustomerOption({
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

  factory _TransferCustomerOption.fromJson(Map<String, dynamic> json) {
    final customerAddress = json['address']?.toString().trim();
    final branches = (json['branches'] as List?)?.cast<Map<String, dynamic>>();
    String? address;
    if (customerAddress != null && customerAddress.isNotEmpty) {
      address = customerAddress;
    }
    if (branches != null) {
      for (final branch in branches) {
        final candidate = branch['address']?.toString().trim();
        if (candidate != null && candidate.isNotEmpty) {
          address ??= candidate;
          break;
        }
      }
    }
    return _TransferCustomerOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      vkn: json['vkn']?.toString(),
      city: json['city']?.toString(),
      address: address,
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

String _sortKey(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u');
}
