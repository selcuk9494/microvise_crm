import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import 'application_form_model.dart';
import '../customers/customer_form_dialog.dart';
import '../definitions/definitions_screen.dart';
import 'application_form_print.dart';

final applicationFormCustomersProvider = FutureProvider<List<_CustomerOption>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  const pageSize = 500;
  var from = 0;
  final items = <_CustomerOption>[];

  while (true) {
    final rows = await client
        .from('customers')
        .select('id,name,vkn,tckn_ms,city,address,is_active')
        .range(from, from + pageSize - 1);
    final batch = (rows as List)
        .map((row) => _CustomerOption.fromJson(row as Map<String, dynamic>))
        .toList(growable: false);
    items.addAll(batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }

  items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return items;
});

final applicationFormStockProductsProvider =
    FutureProvider<List<_StockProductOption>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];

      final rows = await client
          .from('products')
          .select('id,code,name,is_active')
          .eq('is_active', true)
          .order('name');

      final items = (rows as List)
          .map(
            (row) => _StockProductOption.fromJson(row as Map<String, dynamic>),
          )
          .toList(growable: false);
      items.sort((a, b) => _sortKey(a.label).compareTo(_sortKey(b.label)));
      return items;
    });

final applicationFormsProvider = FutureProvider<List<ApplicationFormRecord>>((
  ref,
) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('application_forms')
      .select(
        'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,is_active,created_at',
      )
      .order('created_at', ascending: false)
      .limit(500);

  return (rows as List)
      .map((row) => ApplicationFormRecord.fromJson(row as Map<String, dynamic>))
      .toList(growable: false);
});

class ApplicationFormScreen extends ConsumerStatefulWidget {
  const ApplicationFormScreen({super.key});

  @override
  ConsumerState<ApplicationFormScreen> createState() =>
      _ApplicationFormScreenState();
}

class _ApplicationFormScreenState extends ConsumerState<ApplicationFormScreen> {
  final _customerFilterController = TextEditingController();
  final _registryFilterController = TextEditingController();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final Set<String> _selectedRecordIds = <String>{};
  bool _showPassive = false;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void dispose() {
    _customerFilterController.dispose();
    _registryFilterController.dispose();
    super.dispose();
  }

  Future<void> _pickFilterDate({
    required DateTime? currentValue,
    required ValueChanged<DateTime?> onSelected,
  }) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _ApplicationDatePickerDialog(
        initialDate: currentValue ?? DateTime.now(),
      ),
    );
    if (picked == null) return;
    onSelected(picked);
  }

  Future<void> _openCreateDialog() async {
    final saved = await showDialog<ApplicationFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ApplicationFormDialog(),
    );
    if (saved == null || !mounted) return;

    final _ = await ref.refresh(applicationFormsProvider.future);
    await _showPrintOptions(saved);
  }

  Future<void> _openEditDialog(ApplicationFormRecord record) async {
    final saved = await showDialog<ApplicationFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ApplicationFormDialog(initialRecord: record),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(applicationFormsProvider.future);
  }

  Future<void> _openDuplicateDialog(ApplicationFormRecord record) async {
    final saved = await showDialog<ApplicationFormRecord>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ApplicationFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (saved == null || !mounted) return;
    final _ = await ref.refresh(applicationFormsProvider.future);
    await _showPrintOptions(saved);
  }

  Future<void> _showPrintOptions(ApplicationFormRecord record) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazdırma Seçenekleri'),
        content: const Text(
          'Kayıt tamamlandı. İstersen KDV4 veya KDV4A çıktısını hemen alabilirsin.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Sonra'),
          ),
          OutlinedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _print(record, kind: ApplicationPrintKind.kdv);
            },
            child: const Text('KDV4 Yazdır'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await _print(record, kind: ApplicationPrintKind.kdv4a);
            },
            child: const Text('KDV4A Yazdır'),
          ),
        ],
      ),
    );
  }

  Future<void> _print(
    ApplicationFormRecord record, {
    required ApplicationPrintKind kind,
  }) async {
    final settings = await ref.read(
      applicationFormPrintSettingsProvider.future,
    );
    final ok = await printApplicationForm(
      record,
      kind: kind,
      settings: settings,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? '${kind.label} çıktısı hazırlandı.'
              : '${kind.label} çıktısı bu platformda açılamadı.',
        ),
      ),
    );
  }

  Future<void> _setRecordActive(
    ApplicationFormRecord record,
    bool active,
  ) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;
    await client
        .from('application_forms')
        .update({'is_active': active})
        .eq('id', record.id);
    ref.invalidate(applicationFormsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(active ? 'Başvuru yeniden aktifleştirildi.' : 'Başvuru pasife alındı.'),
      ),
    );
  }

  Future<void> _exportForTaxOffice(List<ApplicationFormRecord> records) async {
    if (records.isEmpty) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null || !mounted) return;

    final customerIds = records
        .map((record) => record.customerId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final customerMap = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      final rows = await client
          .from('customers')
          .select('id,vkn,tckn_ms')
          .inFilter('id', customerIds);
      for (final row in rows as List) {
        final item = row as Map<String, dynamic>;
        customerMap[item['id'].toString()] = item;
      }
    }

    final file = excel.Excel.createExcel();
    final sheet = file.tables[file.getDefaultSheet()]!;

    sheet.appendRow([
      excel.TextCellValue('VERGI SICIL NO'),
      excel.TextCellValue('UNVAN / AD'),
      excel.TextCellValue('ADRES'),
      excel.TextCellValue('BAGLI OLD. VERGI DAIRESI'),
      excel.TextCellValue('MARKA'),
      excel.TextCellValue('MODEL'),
      excel.TextCellValue(''),
      excel.TextCellValue(''),
      excel.TextCellValue('FIRMA KODU'),
      excel.TextCellValue('SICIL NOSU'),
      excel.TextCellValue(''),
      excel.TextCellValue(''),
      excel.TextCellValue('BAKIM ONARIM YAPAN FIRMA'),
      excel.TextCellValue('VKN'),
    ]);

    for (final record in records) {
      final customer = record.customerId == null
          ? null
          : customerMap[record.customerId!];
      final tcknMs = (customer?['tckn_ms'] ?? record.customerTcknMs ?? '')
          .toString();
      final vkn = _formatVkn((customer?['vkn'] ?? '').toString());
      final taxRegistry = _formatTaxRegistry(tcknMs);
      final brand = (record.brandName ?? '').trim();
      final model = (record.modelName ?? '').trim();
      final companyCode = _resolveCompanyCode(
        brand: brand,
        fallback: (record.fiscalSymbolName ?? '').trim(),
      );
      final serialNumber = _formatDeviceSerialNumber(
        record.stockRegistryNumber,
      );

      sheet.appendRow([
        excel.TextCellValue(taxRegistry),
        excel.TextCellValue(record.customerName),
        excel.TextCellValue((record.workAddress ?? '').trim()),
        excel.TextCellValue((record.taxOfficeCityName ?? '').trim()),
        excel.TextCellValue(brand),
        excel.TextCellValue(model),
        excel.TextCellValue(''),
        excel.TextCellValue(''),
        excel.TextCellValue(companyCode),
        excel.TextCellValue(serialNumber),
        excel.TextCellValue(''),
        excel.TextCellValue(''),
        excel.TextCellValue(
          ApplicationFormPrintSettings.defaults.serviceCompanyName,
        ),
        excel.TextCellValue(vkn),
      ]);
    }

    final bytes = file.encode();
    if (bytes == null || !mounted) return;

    downloadExcelFile(
      bytes,
      'vergi_dairesine_gonder_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${records.length} kayit icin Excel disa aktarildi.'),
      ),
    );
  }

  Future<void> _exportForTsm(List<ApplicationFormRecord> records) async {
    if (records.isEmpty) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null || !mounted) return;

    final customerIds = records
        .map((record) => record.customerId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final customerMap = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      final rows = await client
          .from('customers')
          .select('id,vkn,tckn_ms,phone_1,phone_2,phone_3')
          .inFilter('id', customerIds);
      for (final row in rows as List) {
        final item = row as Map<String, dynamic>;
        customerMap[item['id'].toString()] = item;
      }
    }

    final templateData = await rootBundle.load('assets/templates/tsm_template.xlsx');
    final file = excel.Excel.decodeBytes(templateData.buffer.asUint8List());
    const sheetName = 'Tsm';
    final sheet = file[sheetName];
    final templateStyles = <int, excel.CellStyle?>{};
    final templateValues = <int, excel.CellValue?>{};
    for (var col = 0; col < 43; col++) {
      final templateCell = sheet.cell(
        excel.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: 1),
      );
      templateStyles[col] = templateCell.cellStyle;
      templateValues[col] = templateCell.value;
    }

    for (final record in records) {
      final customer = record.customerId == null
          ? null
          : customerMap[record.customerId!];
      final splitName = _splitCustomerName(record.customerName);
      final phone = _pickCustomerPhone(customer);
      final taxOffice = (record.taxOfficeCityName ?? '').trim();
      final vkn = (customer?['vkn'] ?? '').toString().trim();
      final tcknMs =
          (customer?['tckn_ms'] ?? record.customerTcknMs ?? '').toString().trim();
      final serialRaw = (record.stockRegistryNumber ?? '').trim().toUpperCase();
      final serialNumber = serialRaw;
      final modelCode = _resolveTsmModel(serialRaw);
      final address = (record.workAddress ?? '').trim();
      final invoiceDate = record.applicationDate.toIso8601String().split('T').first;

      final overrides = <int, excel.CellValue?>{
        0: excel.TextCellValue('V3'),
        1: excel.TextCellValue('3'),
        2: excel.TextCellValue(serialNumber),
        3: excel.TextCellValue('MICROVISE'),
        4: excel.TextCellValue(modelCode),
        9: excel.TextCellValue(address),
        10: excel.IntCellValue(98),
        11: excel.TextCellValue(taxOffice),
        12: excel.TextCellValue('0'),
        13: excel.TextCellValue(splitName.$1),
        14: excel.TextCellValue(splitName.$2),
        15: excel.TextCellValue(address),
        16: excel.IntCellValue(98),
        17: excel.TextCellValue(taxOffice),
        18: excel.TextCellValue(taxOffice),
        19: _excelCellFromRaw(vkn, preferText: false),
        20: _excelCellFromRaw(tcknMs, preferText: false),
        23: _excelCellFromRaw(phone, preferText: false),
        24: _excelCellFromRaw(phone, preferText: false),
        25: excel.TextCellValue(record.customerName),
        28: excel.TextCellValue('2'),
        29: excel.IntCellValue(561101),
        33: excel.TextCellValue('2'),
        34: excel.TextCellValue('1111'),
        35: excel.TextCellValue(invoiceDate),
        36: excel.TextCellValue('a123'),
        37: excel.IntCellValue(2),
        38: excel.TextCellValue('MICROVISE'),
        40: excel.TextCellValue('19660'),
        41: excel.TextCellValue('Microvise Innovation Ltd. Sti'),
        42: _excelCellFromRaw('1210404319', preferText: false),
      };
      final rowIndex = 1 + records.indexOf(record);
      for (var col = 0; col < 43; col++) {
        file.updateCell(
          sheetName,
          excel.CellIndex.indexByColumnRow(columnIndex: col, rowIndex: rowIndex),
          overrides.containsKey(col) ? overrides[col] : templateValues[col],
          cellStyle: templateStyles[col],
        );
      }
    }

    final bytes = file.encode();
    if (bytes == null || !mounted) return;
    downloadExcelFile(
      bytes,
      'tsm_gonder_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${records.length} kayit icin TSM Excel disa aktarildi.'),
      ),
    );
  }

  String _formatTaxRegistry(String raw) {
    var text = raw.trim().toUpperCase();
    if (text.isEmpty) return '';
    if (text.startsWith('MŞ')) return text;
    if (text.startsWith('MS')) {
      text = 'MŞ${text.substring(2)}';
    }
    if (!text.startsWith('MŞ')) {
      text = text.replaceFirst(RegExp(r'^0+'), '');
      if (text.length == 5) return 'MŞ$text';
    }
    return text;
  }

  (String, String) _splitCustomerName(String raw) {
    final words = raw
        .trim()
        .split(RegExp(r'\s+'))
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (words.isEmpty) return ('', '');
    if (words.length == 1) return (words.first, '');
    final splitIndex = (words.length / 2).ceil();
    return (
      words.take(splitIndex).join(' '),
      words.skip(splitIndex).join(' '),
    );
  }

  String _pickCustomerPhone(Map<String, dynamic>? customer) {
    if (customer == null) return '';
    for (final key in ['phone_1', 'phone_2', 'phone_3']) {
      final value = (customer[key] ?? '').toString().trim();
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  String _resolveTsmModel(String serialNumber) {
    final upper = serialNumber.toUpperCase();
    if (upper.startsWith('2C')) return '4';
    if (upper.startsWith('2D')) return '6';
    return '';
  }

  String _resolveCompanyCode({
    required String brand,
    required String fallback,
  }) {
    final normalized = _sortKey(brand);
    if (normalized.contains('pax')) return '2D';
    if (normalized.contains('ingenico')) return '2C';
    return fallback;
  }

  String _formatDeviceSerialNumber(String? raw) {
    final text = (raw ?? '').trim().toUpperCase();
    if (text.startsWith('2C') || text.startsWith('2D')) {
      return text.substring(2);
    }
    return text;
  }

  String _formatVkn(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    final trimmed = digits.replaceFirst(RegExp(r'^0+'), '');
    final normalized = trimmed.isEmpty ? '0' : trimmed;
    if (normalized.length <= 10) return normalized.padLeft(10, '0');
    return normalized.substring(normalized.length - 10);
  }

  excel.CellValue _excelCellFromRaw(String raw, {bool preferText = true}) {
    final text = raw.trim();
    if (text.isEmpty) return excel.TextCellValue('');
    if (!preferText &&
        RegExp(r'^[0-9]+$').hasMatch(text) &&
        !text.startsWith('0')) {
      return excel.IntCellValue(int.parse(text));
    }
    return excel.TextCellValue(text);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 820;
    final recordsAsync = ref.watch(applicationFormsProvider);

    return AppPageLayout(
      title: 'Başvuru Formları',
      subtitle: 'Başvuru kayıtlarını filtreleyin, listeleyin ve yazdırın.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(applicationFormsProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        FilledButton.icon(
          onPressed: _openCreateDialog,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Başvuru'),
        ),
      ],
      body: recordsAsync.when(
        data: (records) {
          final filtered = _filterRecords(records)
              .where((item) => _showPassive || item.isActive)
              .toList(growable: false);
          final selectedRecords = filtered
              .where((record) => _selectedRecordIds.contains(record.id))
              .toList(growable: false);
          final allFilteredSelected = filtered.isNotEmpty &&
              selectedRecords.length == filtered.length;
          return Column(
            children: [
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Filtreler',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const Gap(12),
                    Wrap(
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
                              hintText: 'Müşteri adına göre ara',
                              prefixIcon: Icon(Icons.person_search_rounded),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? double.infinity : 240,
                          child: TextField(
                            controller: _registryFilterController,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              labelText: 'Cihaz / Sicil No',
                              hintText: 'Dosya veya cihaz sicili',
                              prefixIcon: Icon(Icons.confirmation_num_rounded),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? double.infinity : 180,
                          child: _FilterDateField(
                            label: 'Başlangıç Tarihi',
                            value: _fromDate,
                            format: _dateFormat,
                            onTap: () => _pickFilterDate(
                              currentValue: _fromDate,
                              onSelected: (value) =>
                                  setState(() => _fromDate = value),
                            ),
                            onClear: _fromDate == null
                                ? null
                                : () => setState(() => _fromDate = null),
                          ),
                        ),
                        SizedBox(
                          width: isMobile ? double.infinity : 180,
                          child: _FilterDateField(
                            label: 'Bitiş Tarihi',
                            value: _toDate,
                            format: _dateFormat,
                            onTap: () => _pickFilterDate(
                              currentValue: _toDate,
                              onSelected: (value) =>
                                  setState(() => _toDate = value),
                            ),
                            onClear: _toDate == null
                                ? null
                                : () => setState(() => _toDate = null),
                          ),
                        ),
                        if (isMobile)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () {
                                setState(() {
                                  _customerFilterController.clear();
                                  _registryFilterController.clear();
                                  _fromDate = null;
                                  _toDate = null;
                                });
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text('Temizle'),
                            ),
                          )
                        else
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _customerFilterController.clear();
                                _registryFilterController.clear();
                                _fromDate = null;
                                _toDate = null;
                              });
                            },
                            icon: const Icon(Icons.filter_alt_off_rounded),
                            label: const Text('Temizle'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _CompactStat(
                          label: 'Toplam',
                          value: records.length.toString(),
                          icon: Icons.description_outlined,
                        ),
                        _CompactStat(
                          label: 'Filtrelenen',
                          value: filtered.length.toString(),
                          icon: Icons.filter_alt_rounded,
                        ),
                        _CompactStat(
                          label: 'Bugün',
                          value: filtered
                              .where(
                                (item) => _isSameDay(
                                  item.applicationDate,
                                  DateTime.now(),
                                ),
                              )
                              .length
                              .toString(),
                          icon: Icons.today_rounded,
                        ),
                      ],
                    ),
                  ),
                  const Gap(8),
                  if (filtered.isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                        if (allFilteredSelected) {
                            for (final record in filtered) {
                              _selectedRecordIds.remove(record.id);
                            }
                          } else {
                            for (final record in filtered) {
                              _selectedRecordIds.add(record.id);
                            }
                          }
                        });
                      },
                      icon: Icon(
                        allFilteredSelected
                            ? Icons.deselect_rounded
                            : Icons.select_all_rounded,
                        size: 18,
                      ),
                      label: Text(
                        allFilteredSelected ? 'Secimi Temizle' : 'Tumunu Sec',
                      ),
                    ),
                  if (filtered.isNotEmpty) const Gap(8),
                  FilterChip(
                    selected: _showPassive,
                    onSelected: (value) =>
                        setState(() => _showPassive = value),
                    label: const Text('Pasifleri Göster'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (filtered.isNotEmpty) const Gap(8),
                  if (selectedRecords.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        FilledButton.icon(
                          onPressed: () => _exportForTaxOffice(selectedRecords),
                          icon: const Icon(Icons.download_rounded, size: 18),
                          label: Text(
                            'Vergi Dairesine Gonder (${selectedRecords.length})',
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _exportForTsm(selectedRecords),
                          icon: const Icon(Icons.table_chart_rounded, size: 18),
                          label: Text('TSM\'e Gonder (${selectedRecords.length})'),
                        ),
                      ],
                    ),
                ],
              ),
              const Gap(12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text('Filtreye uygun başvuru bulunamadı.'),
                  ),
                )
              else
                Column(
                  children: [
                    for (var index = 0; index < filtered.length; index++) ...[
                      _ApplicationRecordCard(
                        record: filtered[index],
                        selected: _selectedRecordIds.contains(filtered[index].id),
                        onSelectionChanged: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedRecordIds.add(filtered[index].id);
                            } else {
                              _selectedRecordIds.remove(filtered[index].id);
                            }
                          });
                        },
                        onPrintKdv: () => _print(
                          filtered[index],
                          kind: ApplicationPrintKind.kdv,
                        ),
                        onPrintKdv4a: () => _print(
                          filtered[index],
                          kind: ApplicationPrintKind.kdv4a,
                        ),
                        onEdit: () => _openEditDialog(filtered[index]),
                        onDuplicate: () =>
                            _openDuplicateDialog(filtered[index]),
                        onToggleActive: () => _setRecordActive(
                          filtered[index],
                          !filtered[index].isActive,
                        ),
                      ),
                      if (index != filtered.length - 1) const Gap(12),
                    ],
                  ],
                ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Başvuru kayıtları yüklenemedi.')),
      ),
    );
  }

  List<ApplicationFormRecord> _filterRecords(
    List<ApplicationFormRecord> input,
  ) {
    final customerQuery = _sortKey(_customerFilterController.text);
    final registryQuery = _sortKey(_registryFilterController.text);

    return input
        .where((item) {
          if (customerQuery.isNotEmpty &&
              !_sortKey(item.customerName).contains(customerQuery)) {
            return false;
          }

          if (registryQuery.isNotEmpty) {
            final haystack = _sortKey(
              '${item.fileRegistryNumber ?? ''} ${item.stockRegistryNumber ?? ''} ${item.stockProductName ?? ''}',
            );
            if (!haystack.contains(registryQuery)) return false;
          }

          if (_fromDate != null) {
            final from = DateTime(
              _fromDate!.year,
              _fromDate!.month,
              _fromDate!.day,
            );
            final target = DateTime(
              item.applicationDate.year,
              item.applicationDate.month,
              item.applicationDate.day,
            );
            if (target.isBefore(from)) return false;
          }

          if (_toDate != null) {
            final to = DateTime(_toDate!.year, _toDate!.month, _toDate!.day);
            final target = DateTime(
              item.applicationDate.year,
              item.applicationDate.month,
              item.applicationDate.day,
            );
            if (target.isAfter(to)) return false;
          }

          return true;
        })
        .toList(growable: false);
  }
}

class _ApplicationFormDialog extends ConsumerStatefulWidget {
  const _ApplicationFormDialog({
    this.initialRecord,
    this.duplicateMode = false,
  });

  final ApplicationFormRecord? initialRecord;
  final bool duplicateMode;

  bool get isEdit => initialRecord != null && !duplicateMode;

  @override
  ConsumerState<_ApplicationFormDialog> createState() =>
      _ApplicationFormDialogState();
}

class _ApplicationFormDialogState
    extends ConsumerState<_ApplicationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  late final TextEditingController _customerController;
  late final TextEditingController _workAddressController;
  late final TextEditingController _fileRegistryController;
  late final TextEditingController _customerTcknMsController;
  late final TextEditingController _directorController;
  late final TextEditingController _accountingOfficeController;
  late final TextEditingController _stockRegistryNumberController;
  late final TextEditingController _invoiceNumberController;
  DateTime _applicationDate = DateTime.now();
  DateTime _okcStartDate = DateTime.now();
  final String _documentType = 'VKN';
  String? _selectedCustomerId;
  String? _selectedCityId;
  String? _selectedModelId;
  String? _selectedFiscalSymbolId;
  String? _selectedStockProductId;
  String? _selectedBusinessActivityId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    _customerController = TextEditingController(
      text: initial?.customerName ?? '',
    );
    _workAddressController = TextEditingController(
      text: initial?.workAddress ?? '',
    );
    _fileRegistryController = TextEditingController(
      text: initial?.fileRegistryNumber ?? '',
    );
    _customerTcknMsController = TextEditingController(
      text: initial?.customerTcknMs ?? '',
    );
    _directorController = TextEditingController(text: initial?.director ?? '');
    _accountingOfficeController = TextEditingController(
      text: initial?.accountingOffice ?? '',
    );
    _stockRegistryNumberController = TextEditingController(
      text: initial?.stockRegistryNumber ?? '',
    );
    _invoiceNumberController = TextEditingController(
      text: initial?.invoiceNumber ?? '',
    );
    _applicationDate = initial?.applicationDate ?? DateTime.now();
    _okcStartDate = initial?.okcStartDate ?? DateTime.now();
    _selectedCustomerId = initial?.customerId;
    _loadInitialSelections();
  }

  Future<void> _loadInitialSelections() async {
    final initial = widget.initialRecord;
    if (initial == null) return;

    final customers = await ref.read(applicationFormCustomersProvider.future);
    final cities = await ref.read(cityDefinitionsProvider.future);
    final models = await ref.read(deviceModelsProvider.future);
    final fiscalSymbols = await ref.read(fiscalSymbolsProvider.future);
    final stockProducts = await ref.read(
      applicationFormStockProductsProvider.future,
    );
    final activities = await ref.read(businessActivityTypesProvider.future);

    if (!mounted) return;
    setState(() {
      _selectedCustomerId ??= customers
          .where((item) => item.id == initial.customerId)
          .map((item) => item.id)
          .firstOrNull;
      _selectedCityId ??= cities
          .where(
            (item) =>
                _sortKey(item.name) ==
                _sortKey(initial.taxOfficeCityName ?? ''),
          )
          .map((item) => item.id)
          .firstOrNull;
      _selectedModelId ??= models
          .where(
            (item) =>
                _sortKey(item.name) == _sortKey(initial.modelName ?? '') &&
                _sortKey(item.brandName ?? '') ==
                    _sortKey(initial.brandName ?? ''),
          )
          .map((item) => item.id)
          .firstOrNull;
      _selectedFiscalSymbolId ??= fiscalSymbols
          .where(
            (item) =>
                _sortKey(item.name) ==
                    _sortKey(initial.fiscalSymbolName ?? '') ||
                _sortKey(item.code ?? '') ==
                    _sortKey(initial.fiscalSymbolName ?? ''),
          )
          .map((item) => item.id)
          .firstOrNull;
      _selectedStockProductId ??= stockProducts
          .where(
            (item) =>
                _sortKey(item.name) ==
                    _sortKey(initial.stockProductName ?? '') ||
                _sortKey(item.code ?? '') ==
                    _sortKey(initial.stockRegistryNumber ?? ''),
          )
          .map((item) => item.id)
          .firstOrNull;
      _selectedBusinessActivityId ??= activities
          .where(
            (item) =>
                _sortKey(item.name) ==
                _sortKey(initial.businessActivityName ?? ''),
          )
          .map((item) => item.id)
          .firstOrNull;
    });
  }

  @override
  void dispose() {
    _customerController.dispose();
    _workAddressController.dispose();
    _fileRegistryController.dispose();
    _customerTcknMsController.dispose();
    _directorController.dispose();
    _accountingOfficeController.dispose();
    _stockRegistryNumberController.dispose();
    _invoiceNumberController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({
    required DateTime currentValue,
    required ValueChanged<DateTime> onSelected,
  }) async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) =>
          _ApplicationDatePickerDialog(initialDate: currentValue),
    );
    if (picked == null) return;
    onSelected(picked);
  }

  Future<void> _createCustomer() async {
    final newCustomerId = await showCreateCustomerDialog(context);
    if (newCustomerId == null) return;
    ref.invalidate(applicationFormCustomersProvider);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final customers = await ref.read(applicationFormCustomersProvider.future);
    final created = customers
        .where((item) => item.id == newCustomerId)
        .firstOrNull;
    if (created == null || !mounted) return;
    setState(() {
      _selectedCustomerId = created.id;
      _customerController.text = created.name;
      _workAddressController.text = (created.address ?? '').trim();
      if (_fileRegistryController.text.trim().isEmpty) {
        _fileRegistryController.text = created.vkn ?? '';
      }
      _customerTcknMsController.text = created.tcknMs ?? '';
      final city = ref
          .read(cityDefinitionsProvider)
          .asData
          ?.value
          .where((item) => _sortKey(item.name) == _sortKey(created.city ?? ''))
          .firstOrNull;
      if (city != null) {
        _selectedCityId = city.id;
      }
    });
  }

  Future<void> _pickCustomer(List<_CustomerOption> customers) async {
    final selected = await showDialog<_CustomerOption>(
      context: context,
      builder: (context) => _CustomerPickerDialog(
        customers: customers,
        initialSelectedId: _selectedCustomerId,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      _selectedCustomerId = selected.id;
      _customerController.text = selected.name;
      _workAddressController.text = (selected.address ?? '').trim();
      _fileRegistryController.text = selected.vkn ?? '';
      _customerTcknMsController.text = selected.tcknMs ?? '';
      final city = ref
          .read(cityDefinitionsProvider)
          .asData
          ?.value
          .where((item) => _sortKey(item.name) == _sortKey(selected.city ?? ''))
          .firstOrNull;
      if (city != null) {
        _selectedCityId = city.id;
      }
    });
  }

  void _applyModelSelection(
    String? value,
    List<DeviceModel> models,
    List<FiscalSymbolDefinition> fiscalSymbols,
  ) {
    final model = models.where((item) => item.id == value).firstOrNull;
    final brand = _sortKey(model?.brandName ?? '');

    String? matchingFiscalId;
    if (brand.contains('ingenico')) {
      matchingFiscalId = fiscalSymbols
          .where(
            (item) =>
                _sortKey(item.code ?? '') == _sortKey('MF 2C') ||
                _sortKey(item.code ?? '') == _sortKey('MF-2C') ||
                _sortKey(item.name) == _sortKey('MF 2C') ||
                _sortKey(item.name) == _sortKey('MF-2C'),
          )
          .firstOrNull
          ?.id;
    } else if (brand.contains('pax')) {
      matchingFiscalId = fiscalSymbols
          .where(
            (item) =>
                _sortKey(item.code ?? '') == _sortKey('MF 2D') ||
                _sortKey(item.code ?? '') == _sortKey('MF-2D') ||
                _sortKey(item.name) == _sortKey('MF 2D') ||
                _sortKey(item.name) == _sortKey('MF-2D'),
          )
          .firstOrNull
          ?.id;
    }

    setState(() {
      _selectedModelId = value;
      if (matchingFiscalId != null) {
        _selectedFiscalSymbolId = matchingFiscalId;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    final customers = ref.read(applicationFormCustomersProvider).asData?.value;
    final cities = ref.read(cityDefinitionsProvider).asData?.value;
    final models = ref.read(deviceModelsProvider).asData?.value;
    final fiscalSymbols = ref.read(fiscalSymbolsProvider).asData?.value;
    final stockProducts = ref
        .read(applicationFormStockProductsProvider)
        .asData
        ?.value;
    final activities = ref.read(businessActivityTypesProvider).asData?.value;

    final customer = customers
        ?.where((item) => item.id == _selectedCustomerId)
        .firstOrNull;
    final city = cities
        ?.where((item) => item.id == _selectedCityId)
        .firstOrNull;
    final model = models
        ?.where((item) => item.id == _selectedModelId)
        .firstOrNull;
    final fiscal = fiscalSymbols
        ?.where((item) => item.id == _selectedFiscalSymbolId)
        .firstOrNull;
    final stockProduct = stockProducts
        ?.where((item) => item.id == _selectedStockProductId)
        .firstOrNull;
    final activity = activities
        ?.where((item) => item.id == _selectedBusinessActivityId)
        .firstOrNull;

    setState(() => _saving = true);
    try {
      final payload = {
        'application_date': DateFormat('yyyy-MM-dd').format(_applicationDate),
        'customer_id': customer?.id,
        'customer_name': _customerController.text.trim(),
        'customer_tckn_ms': _customerTcknMsController.text.trim().isEmpty
            ? null
            : _customerTcknMsController.text.trim(),
        'work_address': _workAddressController.text.trim(),
        'tax_office_city_id': city?.id.isEmpty ?? true ? null : city?.id,
        'tax_office_city_name': city?.name,
        'document_type': _documentType,
        'file_registry_number': _fileRegistryController.text.trim().isEmpty
            ? null
            : _fileRegistryController.text.trim(),
        'director': _directorController.text.trim().isEmpty
            ? null
            : _directorController.text.trim(),
        'brand_id': model?.brandId,
        'brand_name': model?.brandName,
        'model_id': model?.id,
        'model_name': model?.name,
        'fiscal_symbol_id': fiscal?.id,
        'fiscal_symbol_name': fiscal?.code?.trim().isNotEmpty ?? false
            ? fiscal!.code!.trim()
            : fiscal?.name,
        'stock_product_id': stockProduct?.id,
        'stock_product_name': stockProduct?.name,
        'stock_registry_number':
            _stockRegistryNumberController.text.trim().isEmpty
            ? null
            : _stockRegistryNumberController.text.trim(),
        'accounting_office': _accountingOfficeController.text.trim().isEmpty
            ? null
            : _accountingOfficeController.text.trim(),
        'okc_start_date': DateFormat('yyyy-MM-dd').format(_okcStartDate),
        'business_activity_type_id': activity?.id,
        'business_activity_name': activity?.name,
        'invoice_number': _invoiceNumberController.text.trim().isEmpty
            ? null
            : _invoiceNumberController.text.trim(),
      };

      final inserted =
          await (widget.isEdit
                  ? client
                        .from('application_forms')
                        .update(payload)
                        .eq('id', widget.initialRecord!.id)
                  : client.from('application_forms').insert(payload))
              .select(
                'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,is_active,created_at',
              )
              .single();

      ref.invalidate(applicationFormsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(ApplicationFormRecord.fromJson(inserted));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 860;
    final customersAsync = ref.watch(applicationFormCustomersProvider);
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    final modelsAsync = ref.watch(deviceModelsProvider);
    final fiscalSymbolsAsync = ref.watch(fiscalSymbolsProvider);
    final stockProductsAsync = ref.watch(applicationFormStockProductsProvider);
    final activitiesAsync = ref.watch(businessActivityTypesProvider);

    final formRows = <Widget>[
      _FormRow(
        label: "Satışa Ait faturanın Tarih ve No' su",
        first: true,
        child: _ResponsiveFieldGroup(
          left: _DateField(
            value: _applicationDate,
            format: _dateFormat,
            onTap: () => _pickDate(
              currentValue: _applicationDate,
              onSelected: (value) => setState(() => _applicationDate = value),
            ),
          ),
          right: _ApplicationTextField(controller: _invoiceNumberController),
        ),
      ),
      _FormRow(
        label: 'Adı - Soyadı / Ünvanı',
        child: customersAsync.when(
          data: (items) => _CustomerPickerField(
            controller: _customerController,
            selectedCustomerId: _selectedCustomerId,
            onPickCustomer: () => _pickCustomer(items),
            onCreateCustomer: _createCustomer,
          ),
          loading: () => const _ContentLoading(),
          error: (error, stackTrace) => const _ContentError(),
        ),
      ),
      _FormRow(
        label: 'İşyeri Adresi',
        child: _ApplicationTextField(
          controller: _workAddressController,
          minLines: 1,
          maxLines: 2,
          validator: (value) =>
              value == null || value.trim().isEmpty
              ? 'İş adresi zorunlu.'
              : null,
        ),
      ),
      _FormRow(
        label: 'Bağlı olduğu Vergi Dairesi',
        child: _ResponsiveFieldGroup(
          left: citiesAsync.when(
            data: (items) => _ApplicationDropdown<String>(
              value: _selectedCityId,
              items: items
                  .where((item) => item.isActive)
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _selectedCityId = value),
              validator: (value) =>
                  value == null ? 'Vergi dairesi seçin.' : null,
            ),
            loading: () => const _ContentLoading(),
            error: (error, stackTrace) => const _ContentError(),
          ),
          right: _ApplicationDropdown<String>(
            value: _documentType,
            items: const [
              DropdownMenuItem(value: 'VKN', child: Text('VKN')),
            ],
            onChanged: null,
          ),
        ),
      ),
      _FormRow(
        label: 'Dosya Sicil No',
        child: _ResponsiveFieldGroup(
          left: _ApplicationTextField(controller: _fileRegistryController),
          right: _ApplicationTextField(controller: _customerTcknMsController),
        ),
      ),
      _FormRow(
        label: 'Direktör',
        child: _ResponsiveFieldGroup(
          left: _ApplicationTextField(controller: _directorController),
          right: _ApplicationTextField(controller: _accountingOfficeController),
        ),
      ),
      _FormRow(
        label: 'Markası ve Modeli',
        child: modelsAsync.when(
          data: (items) => fiscalSymbolsAsync.when(
            data: (fiscalSymbols) => _ApplicationDropdown<String>(
              value: _selectedModelId,
              hintText: 'Tanımlamalardan model seçin',
              items: items
                  .where((item) => item.isActive)
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        item.brandName?.trim().isNotEmpty ?? false
                            ? '${item.brandName} / ${item.name}'
                            : item.name,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  _applyModelSelection(value, items, fiscalSymbols),
              validator: (value) => value == null ? 'Model seçin.' : null,
            ),
            loading: () => const _ContentLoading(),
            error: (error, stackTrace) => const _ContentError(),
          ),
          loading: () => const _ContentLoading(),
          error: (error, stackTrace) => const _ContentError(),
        ),
      ),
      _FormRow(
        label: 'Cihaz Sicil No',
        child: _ResponsiveFieldGroup(
          left: stockProductsAsync.when(
            data: (items) => _ApplicationDropdown<String>(
              value: _selectedStockProductId,
              hintText: 'Stok listesinden seçin',
              items: items
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.label),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) {
                setState(() {
                  _selectedStockProductId = value;
                  final selected = items.where((item) => item.id == value).firstOrNull;
                  if (selected != null) {
                    _stockRegistryNumberController.text =
                        selected.code?.trim().isNotEmpty ?? false
                        ? selected.code!.trim()
                        : selected.name;
                  }
                });
              },
            ),
            loading: () => const _ContentLoading(),
            error: (error, stackTrace) => const _ContentError(),
          ),
          right: _ApplicationTextField(controller: _stockRegistryNumberController),
        ),
      ),
      _FormRow(
        label: 'Mali Sembol ve Firma Kodu',
        child: _ResponsiveFieldGroup(
          left: fiscalSymbolsAsync.when(
            data: (items) => _ApplicationDropdown<String>(
              value: _selectedFiscalSymbolId,
              items: items
                  .where((item) => item.isActive)
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(
                        item.code?.trim().isNotEmpty ?? false
                            ? '${item.code} - ${item.name}'
                            : item.name,
                      ),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _selectedFiscalSymbolId = value),
              validator: (value) => value == null ? 'Mali sembol seçin.' : null,
            ),
            loading: () => const _ContentLoading(),
            error: (error, stackTrace) => const _ContentError(),
          ),
          right: activitiesAsync.when(
            data: (items) => _ApplicationDropdown<String>(
              value: _selectedBusinessActivityId,
              items: items
                  .where((item) => item.isActive)
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) =>
                  setState(() => _selectedBusinessActivityId = value),
              validator: (value) => value == null ? 'Meslek türü seçin.' : null,
            ),
            loading: () => const _ContentLoading(),
            error: (error, stackTrace) => const _ContentError(),
          ),
        ),
      ),
      _FormRow(
        label: 'Muhasebe Ofisi',
        last: true,
        child: _ResponsiveFieldGroup(
          left: _ApplicationTextField(controller: _accountingOfficeController),
          right: _DateField(
            value: _okcStartDate,
            format: _dateFormat,
            onTap: () => _pickDate(
              currentValue: _okcStartDate,
              onSelected: (value) => setState(() => _okcStartDate = value),
            ),
          ),
        ),
      ),
    ];
    final splitIndex = (formRows.length / 2).ceil();

    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 12 : 20),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: isMobile ? 520 : 1160,
          maxHeight: MediaQuery.sizeOf(context).height * 0.96,
        ),
        child: AppCard(
          padding: EdgeInsets.all(isMobile ? 10 : 12),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.isEdit
                                  ? 'Başvuru Düzenle'
                                  : widget.duplicateMode
                                  ? 'Başvuru Kopyası Oluştur'
                                  : 'Yeni Başvuru',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(fontSize: isMobile ? 19 : 21),
                            ),
                            const Gap(4),
                            Text(
                              widget.isEdit
                                  ? 'Kaydı güncelleyin.'
                                  : 'Belge düzeninde formu doldurun. Kayıt sonrası KDV4 ve KDV4A yazdırma seçenekleri açılır.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.textMuted,
                                    fontSize: 11,
                                  ),
                            ),
                          ],
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
                  const Gap(8),
                  isMobile
                      ? Container(
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Column(children: formRows),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: formRows
                                      .sublist(0, splitIndex)
                                      .map((row) => row)
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                            const Gap(12),
                            Expanded(
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                clipBehavior: Clip.antiAlias,
                                child: Column(
                                  children: formRows
                                      .sublist(splitIndex)
                                      .map((row) => row)
                                      .toList(growable: false),
                                ),
                              ),
                            ),
                          ],
                        ),
                  const Gap(12),
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
      ),
    );
  }
}

class _ApplicationRecordCard extends StatelessWidget {
  const _ApplicationRecordCard({
    required this.record,
    required this.selected,
    required this.onSelectionChanged,
    required this.onPrintKdv,
    required this.onPrintKdv4a,
    required this.onEdit,
    required this.onDuplicate,
    required this.onToggleActive,
  });

  final ApplicationFormRecord record;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onPrintKdv;
  final VoidCallback onPrintKdv4a;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleActive;

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat(
      'd MMM y',
      'tr_TR',
    ).format(record.applicationDate);
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 7 : 6,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Checkbox(
                  value: selected,
                  visualDensity: VisualDensity(
                    horizontal: -4.5,
                    vertical: -4.5,
                  ),
                  onChanged: (value) => onSelectionChanged(value ?? false),
                ),
              ),
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
              const Gap(4),
              AppBadge(
                label: record.isActive ? record.documentType : 'Pasif',
                tone: record.isActive
                    ? AppBadgeTone.primary
                    : AppBadgeTone.neutral,
              ),
              const Gap(6),
              _ActionButton(
                onPressed: onEdit,
                icon: Icons.edit_rounded,
                label: 'Düzenle',
              ),
              const Gap(4),
              _ActionButton(
                onPressed: onDuplicate,
                icon: Icons.content_copy_rounded,
                label: 'Kopya',
              ),
              const Gap(4),
              _ActionButton(
                onPressed: onPrintKdv,
                icon: Icons.print_rounded,
                label: 'KDV4',
              ),
              const Gap(4),
              _ActionButton(
                onPressed: onPrintKdv4a,
                icon: Icons.picture_as_pdf_rounded,
                label: 'KDV4A',
                primary: true,
              ),
              const Gap(4),
              _ActionButton(
                onPressed: onToggleActive,
                icon: record.isActive
                    ? Icons.delete_outline_rounded
                    : Icons.restore_rounded,
                label: record.isActive ? 'Sil' : 'Aktifleştir',
              ),
            ],
          ),
          const Gap(5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _InfoChip(
                icon: Icons.calendar_today_rounded,
                text: dateText,
              ),
              if (record.fileRegistryNumber?.trim().isNotEmpty ?? false)
                _InfoChip(
                  icon: Icons.folder_open_rounded,
                  text: 'Dosya: ${record.fileRegistryNumber}',
                ),
              if (record.stockRegistryNumber?.trim().isNotEmpty ?? false)
                _InfoChip(
                  icon: Icons.memory_rounded,
                  text: 'Cihaz: ${record.stockRegistryNumber}',
                ),
              if (record.brandModel.isNotEmpty)
                _InfoChip(
                  icon: Icons.developer_board_rounded,
                  text: record.brandModel,
                ),
              if (record.businessActivityName?.trim().isNotEmpty ?? false)
                _InfoChip(
                  icon: Icons.storefront_rounded,
                  text: record.businessActivityName!,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FilterDateField extends StatelessWidget {
  const _FilterDateField({
    required this.label,
    required this.value,
    required this.format,
    required this.onTap,
    this.onClear,
  });

  final String label;
  final DateTime? value;
  final DateFormat format;
  final VoidCallback onTap;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (onClear != null)
                IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.close_rounded, size: 16),
                ),
              const Icon(Icons.calendar_today_rounded, size: 18),
              const Gap(8),
            ],
          ),
        ),
        child: Text(
          value == null ? 'Tarih seçin' : format.format(value!),
          style: value == null
              ? Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted)
              : Theme.of(context).textTheme.bodyMedium,
        ),
      ),
    );
  }
}

class _ApplicationDatePickerDialog extends StatefulWidget {
  const _ApplicationDatePickerDialog({required this.initialDate});

  final DateTime initialDate;

  @override
  State<_ApplicationDatePickerDialog> createState() =>
      _ApplicationDatePickerDialogState();
}

class _ApplicationDatePickerDialogState
    extends State<_ApplicationDatePickerDialog> {
  late DateTime _selectedDate;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.initialDate;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tarih Seç',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              CalendarDatePicker(
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2100),
                onDateChanged: (value) => setState(() => _selectedDate = value),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(_selectedDate),
                      child: const Text('Seç'),
                    ),
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

class _CompactStat extends StatelessWidget {
  const _CompactStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppTheme.primary),
          const Gap(6),
          Text(
            '$label: $value',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: AppTheme.textMuted),
          const Gap(3),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
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
          minimumSize: const Size(34, 28),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          textStyle: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );

    final child = Tooltip(
      message: label,
      child: Icon(icon, size: 14),
    );

    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
  }
}

class _FormRow extends StatelessWidget {
  const _FormRow({
    required this.label,
    required this.child,
    this.first = false,
    this.last = false,
  });

  final String label;
  final Widget child;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: const BoxDecoration(
              color: Color(0xFFFFF15C),
              border: Border(
                top: BorderSide(color: Color(0xFF111827)),
                left: BorderSide(color: Color(0xFF111827)),
                right: BorderSide(color: Color(0xFF111827)),
              ),
            ),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: const Color(0xFF3E3200),
                fontSize: 10.5,
                height: 1.05,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border.all(color: const Color(0xFF111827)),
            ),
            child: child,
          ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 138,
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF15C),
              border: Border(
                left: const BorderSide(color: Color(0xFF111827)),
                right: const BorderSide(color: Color(0xFF111827)),
                top: const BorderSide(color: Color(0xFF111827)),
                bottom: last
                    ? const BorderSide(color: Color(0xFF111827))
                    : BorderSide.none,
              ),
            ),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF3E3200),
                  fontSize: 10.5,
                  height: 1.0,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 34),
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white,
              border: Border(
                right: const BorderSide(color: Color(0xFF111827)),
                top: const BorderSide(color: Color(0xFF111827)),
                bottom: last
                    ? const BorderSide(color: Color(0xFF111827))
                    : BorderSide.none,
              ),
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}

class _ResponsiveFieldGroup extends StatelessWidget {
  const _ResponsiveFieldGroup({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    if (isMobile) {
      return Column(children: [left, const Gap(4), right]);
    }
    return Row(
      children: [
        Expanded(child: left),
        const Gap(4),
        Expanded(child: right),
      ],
    );
  }
}

class _ApplicationTextField extends StatelessWidget {
  const _ApplicationTextField({
    required this.controller,
    this.minLines,
    this.maxLines = 1,
    this.validator,
  });

  final TextEditingController controller;
  final int? minLines;
  final int maxLines;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF111827),
        fontWeight: FontWeight.w600,
        fontSize: 10.5,
      ),
      decoration: const InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(),
        contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

class _ApplicationDropdown<T> extends StatelessWidget {
  const _ApplicationDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    this.validator,
    this.hintText,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?>? onChanged;
  final String? Function(T?)? validator;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      items: items,
      onChanged: onChanged,
      validator: validator,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF111827),
        fontWeight: FontWeight.w600,
        fontSize: 10.5,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.value,
    required this.format,
    required this.onTap,
  });

  final DateTime value;
  final DateFormat format;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
        ),
        child: Text(
          format.format(value),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF111827),
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
          ),
        ),
      ),
    );
  }
}

class _CustomerPickerField extends StatelessWidget {
  const _CustomerPickerField({
    required this.controller,
    required this.selectedCustomerId,
    required this.onPickCustomer,
    required this.onCreateCustomer,
  });

  final TextEditingController controller;
  final String? selectedCustomerId;
  final VoidCallback onPickCustomer;
  final VoidCallback onCreateCustomer;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            readOnly: true,
            validator: (_) => (selectedCustomerId ?? '').isEmpty
                ? 'Müşteri seçin veya ekleyin.'
                : null,
            onTap: onPickCustomer,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: const Color(0xFF111827),
              fontWeight: FontWeight.w600,
              fontSize: 10.5,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(),
              hintText: 'Eski ya da yeni müşteri seçin',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              suffixIcon: IconButton(
                onPressed: onPickCustomer,
                icon: const Icon(Icons.search_rounded, size: 16),
              ),
            ),
          ),
        ),
        const Gap(6),
        OutlinedButton.icon(
          onPressed: onCreateCustomer,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 34),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
            ),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 14),
          label: const Text('Yeni'),
        ),
      ],
    );
  }
}

class _CustomerPickerDialog extends StatefulWidget {
  const _CustomerPickerDialog({
    required this.customers,
    required this.initialSelectedId,
  });

  final List<_CustomerOption> customers;
  final String? initialSelectedId;

  @override
  State<_CustomerPickerDialog> createState() => _CustomerPickerDialogState();
}

class _CustomerPickerDialogState extends State<_CustomerPickerDialog> {
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
            '${item.name} ${item.vkn ?? ''} ${item.tcknMs ?? ''} ${item.city ?? ''}',
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
                                if (item.tcknMs?.trim().isNotEmpty ?? false)
                                  item.tcknMs!,
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

class _ContentLoading extends StatelessWidget {
  const _ContentLoading();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(
      height: 46,
      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
    );
  }
}

class _ContentError extends StatelessWidget {
  const _ContentError();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 46, child: Text('Veri yüklenemedi.'));
  }
}

class _CustomerOption {
  const _CustomerOption({
    required this.id,
    required this.name,
    required this.vkn,
    required this.tcknMs,
    required this.city,
    required this.address,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? vkn;
  final String? tcknMs;
  final String? city;
  final String? address;
  final bool isActive;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      vkn: json['vkn']?.toString(),
      tcknMs: json['tckn_ms']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class _StockProductOption {
  const _StockProductOption({
    required this.id,
    required this.name,
    required this.code,
  });

  final String id;
  final String name;
  final String? code;

  String get label =>
      code?.trim().isNotEmpty ?? false ? '${code!.trim()} - $name' : name;

  factory _StockProductOption.fromJson(Map<String, dynamic> json) {
    return _StockProductOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      code: json['code']?.toString(),
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
