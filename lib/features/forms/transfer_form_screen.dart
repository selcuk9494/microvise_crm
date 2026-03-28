import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../customers/customer_form_dialog.dart';
import '../definitions/definitions_screen.dart';
import 'transfer_form_model.dart';
import 'transfer_form_print.dart';

final transferFormCustomersProvider =
    FutureProvider<List<_TransferCustomerOption>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
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

final transferFormsProvider = FutureProvider<List<TransferFormRecord>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  try {
    final rows = await client
        .from('transfer_forms')
        .select(
          'id,row_number,transferor_name,transferor_address,transferor_tax_office_and_registry,transferor_approval_date_no,transferee_name,transferee_address,transferee_tax_office_and_registry,transferee_approval_date_no,total_sales_receipt,vat_collected,last_receipt_date_no,z_report_count,other_device_info,brand_model,device_serial_no,fiscal_symbol_company_code,department_count,transfer_date,transfer_reason,created_at',
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
    final settings = await ref.read(transferFormPrintSettingsProvider.future);
    final ok = await printTransferForm(record, settings: settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Devir formu çıktısı hazırlandı.'
              : 'Devir formu çıktısı bu platformda açılamadı.',
        ),
      ),
    );
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
          final filtered = _filter(records);
          return Column(
            children: [
              AppCard(
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
                          text: _fromDate == null
                              ? ''
                              : _dateFormat.format(_fromDate!),
                        ),
                        readOnly: true,
                        onTap: () => _pickDate(
                          currentValue: _fromDate,
                          onSelected: (value) =>
                              setState(() => _fromDate = value),
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
                          text: _toDate == null
                              ? ''
                              : _dateFormat.format(_toDate!),
                        ),
                        readOnly: true,
                        onTap: () => _pickDate(
                          currentValue: _toDate,
                          onSelected: (value) =>
                              setState(() => _toDate = value),
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Bitiş',
                          prefixIcon: Icon(Icons.event_rounded),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const Gap(14),
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
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
              ),
              const Gap(14),
              if (filtered.isEmpty)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Henüz devir formu kaydı yok.')),
                  ),
                )
              else
                ...filtered.map(
                  (record) => Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: AppCard(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 6,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Expanded(
                                child: Text(
                                  '${record.transferorName} -> ${record.transfereeName}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                ),
                              ),
                              const Gap(6),
                              Wrap(
                                spacing: 4,
                                runSpacing: 4,
                                children: [
                                  _TransferMiniActionButton(
                                    onPressed: () => _openEditDialog(record),
                                    icon: Icons.edit_rounded,
                                    label: 'Düzenle',
                                  ),
                                  _TransferMiniActionButton(
                                    onPressed: () =>
                                        _openDuplicateDialog(record),
                                    icon: Icons.copy_rounded,
                                    label: 'Kopya',
                                  ),
                                  _TransferMiniActionButton(
                                    onPressed: () => _print(record),
                                    icon: Icons.print_rounded,
                                    label: 'Yazdır',
                                    primary: true,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Gap(4),
                          Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            children: [
                              _TransferTinyBadge(
                                label: _dateFormat.format(record.transferDate),
                                tone: AppBadgeTone.primary,
                              ),
                              if (record.rowNumber?.trim().isNotEmpty ?? false)
                                _TransferTinyBadge(
                                  label: 'Sıra: ${record.rowNumber}',
                                  tone: AppBadgeTone.neutral,
                                ),
                              if (record.brandModel?.trim().isNotEmpty ?? false)
                                _TransferTinyBadge(
                                  label: record.brandModel!,
                                  tone: AppBadgeTone.warning,
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => const Center(child: Text('Yüklenemedi.')),
      ),
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

class _TransferTinyBadge extends StatelessWidget {
  const _TransferTinyBadge({required this.label, required this.tone});

  final String label;
  final AppBadgeTone tone;

  @override
  Widget build(BuildContext context) {
    return DefaultTextStyle.merge(
      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600),
      child: AppBadge(label: label, tone: tone),
    );
  }
}

class _TransferMiniActionButton extends StatelessWidget {
  const _TransferMiniActionButton({
    required this.onPressed,
    required this.icon,
    required this.label,
    this.primary = false,
  });

  final VoidCallback onPressed;
  final IconData icon;
  final String label;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final style =
        (primary ? FilledButton.styleFrom : OutlinedButton.styleFrom).call(
          minimumSize: const Size(28, 24),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          textStyle: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w700),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        );

    final child = Tooltip(
      message: label,
      child: Icon(icon, size: 12),
    );

    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
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
      _totalSalesController.text = initial.totalSalesReceipt ?? '';
      _vatCollectedController.text = initial.vatCollected ?? '';
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
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
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
      final inserted =
          await (widget.isEdit
                  ? client
                        .from('transfer_forms')
                        .update(payload)
                        .eq('id', widget.initialRecord!.id)
                  : client.from('transfer_forms').insert(payload))
              .select(
                'id,row_number,transferor_name,transferor_address,transferor_tax_office_and_registry,transferor_approval_date_no,transferee_name,transferee_address,transferee_tax_office_and_registry,transferee_approval_date_no,total_sales_receipt,vat_collected,last_receipt_date_no,z_report_count,other_device_info,brand_model,device_serial_no,fiscal_symbol_company_code,department_count,transfer_date,transfer_reason,created_at',
              )
              .single();
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
                          decoration: const InputDecoration(
                            labelText: 'Toplam Hasılat Tutarı',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 200,
                        child: TextFormField(
                          controller: _vatCollectedController,
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
                        child: TextFormField(
                          controller: _deviceSerialController,
                          decoration: const InputDecoration(
                            labelText: 'Cihaz Sicil No',
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
