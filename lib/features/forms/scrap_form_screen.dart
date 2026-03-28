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
import 'scrap_form_model.dart';
import 'scrap_form_print.dart';

final scrapFormCustomersProvider = FutureProvider<List<_ScrapCustomerOption>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  const pageSize = 500;
  var from = 0;
  final items = <_ScrapCustomerOption>[];

  while (true) {
    final rows = await client
        .from('customers')
        .select('id,name,vkn,city,address,is_active,branches(address)')
        .range(from, from + pageSize - 1);
    final batch = (rows as List)
        .map(
          (row) => _ScrapCustomerOption.fromJson(row as Map<String, dynamic>),
        )
        .toList(growable: false);
    items.addAll(batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }

  items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return items;
});

final scrapFormsProvider = FutureProvider<List<ScrapFormRecord>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  try {
    final rows = await client
        .from('scrap_forms')
        .select(
          'id,form_date,row_number,customer_id,customer_name,customer_address,customer_tax_office_and_number,device_brand_model_registry,okc_start_date,last_used_date,z_report_count,total_vat_collection,total_collection,intervention_purpose,other_findings,is_active,created_at',
        )
        .order('created_at', ascending: false)
        .limit(500);
    return (rows as List)
        .map((row) => ScrapFormRecord.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

class ScrapFormScreen extends ConsumerStatefulWidget {
  const ScrapFormScreen({super.key});

  @override
  ConsumerState<ScrapFormScreen> createState() => _ScrapFormScreenState();
}

class _ScrapFormScreenState extends ConsumerState<ScrapFormScreen> {
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
    final saved = await showDialog<ScrapFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ScrapFormDialog(),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(scrapFormsProvider.future);
    await _print(saved);
  }

  Future<void> _openEditDialog(ScrapFormRecord record) async {
    final saved = await showDialog<ScrapFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ScrapFormDialog(initialRecord: record),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(scrapFormsProvider.future);
  }

  Future<void> _openDuplicateDialog(ScrapFormRecord record) async {
    final saved = await showDialog<ScrapFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ScrapFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(scrapFormsProvider.future);
    await _print(saved);
  }

  Future<void> _print(ScrapFormRecord record) async {
    final settings = await ref.read(scrapFormPrintSettingsProvider.future);
    final ok = await printScrapForm(record, settings: settings);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'Hurda formu çıktısı hazırlandı.'
              : 'Hurda formu çıktısı bu platformda açılamadı.',
        ),
      ),
    );
  }

  Future<void> _setRecordActive(ScrapFormRecord record, bool active) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    await client
        .from('scrap_forms')
        .update({'is_active': active})
        .eq('id', record.id);
    ref.invalidate(scrapFormsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(active ? 'Hurda formu aktifleştirildi.' : 'Hurda formu pasife alındı.'),
      ),
    );
  }

  List<ScrapFormRecord> _filter(List<ScrapFormRecord> records) {
    final customerQuery = _sortKey(_customerFilterController.text);
    final deviceQuery = _sortKey(_deviceFilterController.text);

    return records
        .where((item) {
          if (customerQuery.isNotEmpty &&
              !_sortKey(item.customerName).contains(customerQuery)) {
            return false;
          }
          if (deviceQuery.isNotEmpty &&
              !_sortKey(
                item.deviceBrandModelRegistry ?? '',
              ).contains(deviceQuery)) {
            return false;
          }
          if (_fromDate != null && item.formDate.isBefore(_fromDate!)) {
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
            if (item.formDate.isAfter(inclusive)) return false;
          }
          return true;
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 820;
    final recordsAsync = ref.watch(scrapFormsProvider);

    return AppPageLayout(
      title: 'Hurda Formları',
      subtitle:
          'Hurdaya ayrılan cihaz kayıtlarını girin, listeleyin ve yazdırın.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(scrapFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: _openCreateDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Hurda Formu'),
        ),
      ],
      body: recordsAsync.when(
        data: (records) {
          final filtered = _filter(records)
              .where((item) => _showPassive || item.isActive)
              .toList(growable: false);
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
                          labelText: 'Müşteri',
                          hintText: 'Ad / ünvan ara',
                          prefixIcon: Icon(Icons.person_search_rounded),
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
                          hintText: 'Marka model veya sicil no',
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
                          hintText: 'Tarih seçin',
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
                          hintText: 'Tarih seçin',
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
                        });
                      },
                      icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                      label: const Text('Temizle'),
                    ),
                    FilterChip(
                      selected: _showPassive,
                      onSelected: (value) =>
                          setState(() => _showPassive = value),
                      label: const Text('Pasifleri Göster'),
                      visualDensity: VisualDensity.compact,
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
                    AppBadge(
                      label:
                          'Bugün: ${records.where((item) => _isSameDay(item.formDate, DateTime.now())).length}',
                      tone: AppBadgeTone.success,
                    ),
                  ],
                ),
              ),
              const Gap(14),
              if (filtered.isEmpty)
                const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(child: Text('Henüz hurda formu kaydı yok.')),
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
                                  record.customerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium?.copyWith(
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
                                  _MiniActionButton(
                                    onPressed: () => _openEditDialog(record),
                                    icon: Icons.edit_rounded,
                                    label: 'Düzenle',
                                  ),
                                  _MiniActionButton(
                                    onPressed: () =>
                                        _openDuplicateDialog(record),
                                    icon: Icons.copy_rounded,
                                    label: 'Kopya',
                                  ),
                                  _MiniActionButton(
                                    onPressed: () => _print(record),
                                    icon: Icons.print_rounded,
                                    label: 'Yazdır',
                                    primary: true,
                                  ),
                                  _MiniActionButton(
                                    onPressed: () => _setRecordActive(
                                      record,
                                      !record.isActive,
                                    ),
                                    icon: record.isActive
                                        ? Icons.delete_outline_rounded
                                        : Icons.restore_rounded,
                                    label: record.isActive ? 'Sil' : 'Aktif',
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
                              _TinyBadge(
                                label: _dateFormat.format(record.formDate),
                                tone: AppBadgeTone.primary,
                              ),
                              if (record.rowNumber?.trim().isNotEmpty ?? false)
                                _TinyBadge(
                                  label: 'Sıra: ${record.rowNumber}',
                                  tone: AppBadgeTone.neutral,
                                ),
                              if (record.deviceBrandModelRegistry?.trim().isNotEmpty ??
                                  false)
                                _TinyBadge(
                                  label: record.deviceBrandModelRegistry!,
                                  tone: AppBadgeTone.warning,
                                ),
                              if (record.interventionPurpose?.trim().isNotEmpty ??
                                  false)
                                _TinyBadge(
                                  label: record.interventionPurpose!,
                                  tone: AppBadgeTone.success,
                                ),
                              if (!record.isActive)
                                const _TinyBadge(
                                  label: 'Pasif',
                                  tone: AppBadgeTone.neutral,
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

class _ScrapFormDialog extends ConsumerStatefulWidget {
  const _ScrapFormDialog({this.initialRecord, this.duplicateMode = false});

  final ScrapFormRecord? initialRecord;
  final bool duplicateMode;

  bool get isEdit => initialRecord != null && !duplicateMode;

  @override
  ConsumerState<_ScrapFormDialog> createState() => _ScrapFormDialogState();
}

class _TinyBadge extends StatelessWidget {
  const _TinyBadge({required this.label, required this.tone});

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

class _MiniActionButton extends StatelessWidget {
  const _MiniActionButton({
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

class _ScrapFormDialogState extends ConsumerState<_ScrapFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final _customerController = TextEditingController();
  final _rowNumberController = TextEditingController();
  final _addressController = TextEditingController();
  final _taxOfficeNumberController = TextEditingController();
  final _deviceController = TextEditingController();
  final _zReportController = TextEditingController();
  final _vatCollectionController = TextEditingController();
  final _totalCollectionController = TextEditingController();
  final _purposeController = TextEditingController();
  final _otherFindingsController = TextEditingController();

  DateTime _formDate = DateTime.now();
  DateTime? _okcStartDate;
  DateTime? _lastUsedDate;
  String? _selectedCustomerId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial != null) {
      _formDate = initial.formDate;
      _okcStartDate = initial.okcStartDate;
      _lastUsedDate = initial.lastUsedDate;
      _selectedCustomerId = initial.customerId;
      _customerController.text = initial.customerName;
      _rowNumberController.text = initial.rowNumber ?? '';
      _addressController.text = initial.customerAddress ?? '';
      _taxOfficeNumberController.text =
          initial.customerTaxOfficeAndNumber ?? '';
      _deviceController.text = initial.deviceBrandModelRegistry ?? '';
      _zReportController.text = initial.zReportCount ?? '';
      _vatCollectionController.text = initial.totalVatCollection ?? '';
      _totalCollectionController.text = initial.totalCollection ?? '';
      _purposeController.text = initial.interventionPurpose ?? '';
      _otherFindingsController.text = initial.otherFindings ?? '';
    }
  }

  @override
  void dispose() {
    _customerController.dispose();
    _rowNumberController.dispose();
    _addressController.dispose();
    _taxOfficeNumberController.dispose();
    _deviceController.dispose();
    _zReportController.dispose();
    _vatCollectionController.dispose();
    _totalCollectionController.dispose();
    _purposeController.dispose();
    _otherFindingsController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime initialDate,
    required ValueChanged<DateTime> onSelected,
  }) async {
    DateTime tempDate = initialDate;
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Tarih Seç'),
        content: SizedBox(
          width: 320,
          height: 360,
          child: CalendarDatePicker(
            initialDate: initialDate,
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
    onSelected(picked);
  }

  Future<void> _createCustomer() async {
    final newCustomerId = await showCreateCustomerDialog(context);
    if (newCustomerId == null) return;
    ref.invalidate(scrapFormCustomersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final customers = await ref.read(scrapFormCustomersProvider.future);
    _ScrapCustomerOption? created;
    for (final item in customers) {
      if (item.id == newCustomerId) {
        created = item;
        break;
      }
    }
    if (created == null || !mounted) return;
    final selectedCustomer = created;
    setState(() {
      _selectedCustomerId = selectedCustomer.id;
      _customerController.text = selectedCustomer.name;
      _taxOfficeNumberController.text = [
        if ((selectedCustomer.city ?? '').trim().isNotEmpty)
          selectedCustomer.city!.trim(),
        if ((selectedCustomer.vkn ?? '').trim().isNotEmpty)
          selectedCustomer.vkn!.trim(),
      ].join(' ');
      if ((selectedCustomer.address ?? '').trim().isNotEmpty) {
        _addressController.text = selectedCustomer.address!.trim();
      }
    });
  }

  Future<void> _pickCustomer(List<_ScrapCustomerOption> customers) async {
    final selected = await showDialog<_ScrapCustomerOption>(
      context: context,
      builder: (context) => _ScrapCustomerPickerDialog(
        customers: customers,
        initialSelectedId: _selectedCustomerId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedCustomerId = selected.id;
      _customerController.text = selected.name;
      _taxOfficeNumberController.text = [
        if ((selected.city ?? '').trim().isNotEmpty) selected.city!.trim(),
        if ((selected.vkn ?? '').trim().isNotEmpty) selected.vkn!.trim(),
      ].join(' ');
      if ((selected.address ?? '').trim().isNotEmpty) {
        _addressController.text = selected.address!.trim();
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
        'form_date': DateFormat('yyyy-MM-dd').format(_formDate),
        'row_number': _rowNumberController.text.trim().isEmpty
            ? null
            : _rowNumberController.text.trim(),
        'customer_id': _selectedCustomerId,
        'customer_name': _customerController.text.trim(),
        'customer_address': _addressController.text.trim().isEmpty
            ? null
            : _addressController.text.trim(),
        'customer_tax_office_and_number':
            _taxOfficeNumberController.text.trim().isEmpty
            ? null
            : _taxOfficeNumberController.text.trim(),
        'device_brand_model_registry': _deviceController.text.trim().isEmpty
            ? null
            : _deviceController.text.trim(),
        'okc_start_date': _okcStartDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_okcStartDate!),
        'last_used_date': _lastUsedDate == null
            ? null
            : DateFormat('yyyy-MM-dd').format(_lastUsedDate!),
        'z_report_count': _zReportController.text.trim().isEmpty
            ? null
            : _zReportController.text.trim(),
        'total_vat_collection': _vatCollectionController.text.trim().isEmpty
            ? null
            : _vatCollectionController.text.trim(),
        'total_collection': _totalCollectionController.text.trim().isEmpty
            ? null
            : _totalCollectionController.text.trim(),
        'intervention_purpose': _purposeController.text.trim().isEmpty
            ? null
            : _purposeController.text.trim(),
        'other_findings': _otherFindingsController.text.trim().isEmpty
            ? null
            : _otherFindingsController.text.trim(),
      };

      final inserted =
          await (widget.isEdit
                  ? client
                        .from('scrap_forms')
                        .update(payload)
                        .eq('id', widget.initialRecord!.id)
                  : client.from('scrap_forms').insert(payload))
              .select(
                'id,form_date,row_number,customer_id,customer_name,customer_address,customer_tax_office_and_number,device_brand_model_registry,okc_start_date,last_used_date,z_report_count,total_vat_collection,total_collection,intervention_purpose,other_findings,is_active,created_at',
              )
              .single();

      if (!mounted) return;
      Navigator.of(context).pop(ScrapFormRecord.fromJson(inserted));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 720;
    final customersAsync = ref.watch(scrapFormCustomersProvider);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isMobile ? 560 : 860),
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
                              ? 'Hurda Formunu Düzenle'
                              : 'Yeni Hurda Formu',
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
                          readOnly: true,
                          controller: TextEditingController(
                            text: _dateFormat.format(_formDate),
                          ),
                          onTap: () => _pickDate(
                            initialDate: _formDate,
                            onSelected: (value) =>
                                setState(() => _formDate = value),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Tarih',
                            prefixIcon: Icon(Icons.calendar_today_rounded),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          controller: _rowNumberController,
                          decoration: const InputDecoration(
                            labelText: 'Sıra No',
                            prefixIcon: Icon(Icons.tag_rounded),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  customersAsync.when(
                    data: (customers) => Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _customerController,
                            readOnly: true,
                            validator: (value) =>
                                (value?.trim().isEmpty ?? true)
                                ? 'Müşteri seçin'
                                : null,
                            onTap: () => _pickCustomer(customers),
                            decoration: const InputDecoration(
                              labelText: 'Adı, Soyadı veya Ünvanı',
                              hintText: 'Müşteriyi seçin',
                              prefixIcon: Icon(Icons.business_rounded),
                            ),
                          ),
                        ),
                        const Gap(8),
                        OutlinedButton(
                          onPressed: _saving ? null : _createCustomer,
                          child: const Text('Yeni Müşteri'),
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
                  TextFormField(
                    controller: _addressController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: 'Adres'),
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _taxOfficeNumberController,
                    decoration: const InputDecoration(
                      labelText: 'Vergi Dairesi ve Numarası',
                    ),
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _deviceController,
                    decoration: const InputDecoration(
                      labelText: 'Cihazın Marka Model ve Sicil No',
                    ),
                  ),
                  const Gap(12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: isMobile ? double.infinity : 250,
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: _okcStartDate == null
                                ? ''
                                : _dateFormat.format(_okcStartDate!),
                          ),
                          onTap: () => _pickDate(
                            initialDate: _okcStartDate ?? _formDate,
                            onSelected: (value) =>
                                setState(() => _okcStartDate = value),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cihazın Kullanılmaya Başlandığı Tarih',
                            prefixIcon: Icon(Icons.event_available_rounded),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 250,
                        child: TextFormField(
                          readOnly: true,
                          controller: TextEditingController(
                            text: _lastUsedDate == null
                                ? ''
                                : _dateFormat.format(_lastUsedDate!),
                          ),
                          onTap: () => _pickDate(
                            initialDate: _lastUsedDate ?? _formDate,
                            onSelected: (value) =>
                                setState(() => _lastUsedDate = value),
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cihazın En Son Kullanıldığı Tarih',
                            prefixIcon: Icon(Icons.event_busy_rounded),
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
                        width: isMobile ? double.infinity : 180,
                        child: TextFormField(
                          controller: _zReportController,
                          decoration: const InputDecoration(
                            labelText: "Z' Rapor Sayısı",
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          controller: _vatCollectionController,
                          decoration: const InputDecoration(
                            labelText: 'Toplam KDV Tahsilatı',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: isMobile ? double.infinity : 220,
                        child: TextFormField(
                          controller: _totalCollectionController,
                          decoration: const InputDecoration(
                            labelText: 'Toplam Hasılat',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _purposeController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Müdahalenin Amacı',
                    ),
                  ),
                  const Gap(12),
                  TextFormField(
                    controller: _otherFindingsController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Varsa Diğer Tespitler',
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

class _ScrapCustomerPickerDialog extends StatefulWidget {
  const _ScrapCustomerPickerDialog({
    required this.customers,
    required this.initialSelectedId,
  });

  final List<_ScrapCustomerOption> customers;
  final String? initialSelectedId;

  @override
  State<_ScrapCustomerPickerDialog> createState() =>
      _ScrapCustomerPickerDialogState();
}

class _ScrapCustomerPickerDialogState
    extends State<_ScrapCustomerPickerDialog> {
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
          final haystack = _sortKey(
            '${item.name} ${item.vkn ?? ''} ${item.city ?? ''}',
          );
          return haystack.contains(query);
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

class _ScrapCustomerOption {
  const _ScrapCustomerOption({
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

  factory _ScrapCustomerOption.fromJson(Map<String, dynamic> json) {
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
    return _ScrapCustomerOption(
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

bool _isSameDay(DateTime a, DateTime b) {
  return a.year == b.year && a.month == b.month && a.day == b.day;
}
