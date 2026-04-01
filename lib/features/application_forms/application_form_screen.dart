import 'package:excel/excel.dart' as excel;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../billing/invoice_queue_helper.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import 'application_form_model.dart';
import '../customers/customer_form_dialog.dart';
import '../definitions/definitions_screen.dart';
import 'application_form_print.dart';
import '../work_orders/work_orders_providers.dart';

final applicationFormCustomersProvider = FutureProvider<List<_CustomerOption>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'form_application_customers'},
    );
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(_CustomerOption.fromJson)
        .toList(growable: false);
    items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
    return items;
  }
  if (client == null) return const [];

  const pageSize = 500;
  var from = 0;
  final items = <_CustomerOption>[];

  while (true) {
    List<Map<String, dynamic>> rows;
    try {
      rows = await client
          .from('customers')
          .select('id,name,vkn,tckn_ms,city,address,director_name,is_active')
          .range(from, from + pageSize - 1);
    } catch (_) {
      final fallbackRows = await client
          .from('customers')
          .select('id,name,vkn,tckn_ms,city,address,is_active')
          .range(from, from + pageSize - 1);
      rows = (fallbackRows as List)
          .map((row) => {...row as Map<String, dynamic>, 'director_name': null})
          .toList(growable: false);
    }
    final batch = rows
        .map((row) => _CustomerOption.fromJson(row))
        .toList(growable: false);
    items.addAll(batch);
    if (batch.length < pageSize) break;
    from += pageSize;
  }

  items.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return items;
});

final applicationFormsProvider = FutureProvider<List<ApplicationFormRecord>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'form_application_list', 'showPassive': 'true'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ApplicationFormRecord.fromJson)
        .toList(growable: false);
  }
  if (client == null) return const [];

  final rows = await client
      .from('application_forms')
      .select(
        'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,is_active,created_at',
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
  bool _todayOnly = true;
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
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _ApplicationFormDialog(),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;

    final _ = await ref.refresh(applicationFormsProvider.future);
    if (!mounted) return;
    if (savedRecords.length == 1) {
      await _showPrintOptions(savedRecords.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${savedRecords.length} ayrı başvuru kaydı oluşturuldu.'),
      ),
    );
  }

  Future<void> _openEditDialog(ApplicationFormRecord record) async {
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _ApplicationFormDialog(initialRecord: record),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;
    final _ = await ref.refresh(applicationFormsProvider.future);
  }

  Future<void> _openDuplicateDialog(ApplicationFormRecord record) async {
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ApplicationFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;
    final _ = await ref.refresh(applicationFormsProvider.future);
    if (!mounted) return;
    if (savedRecords.length == 1) {
      await _showPrintOptions(savedRecords.first);
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('${savedRecords.length} ayrı başvuru kaydı oluşturuldu.'),
      ),
    );
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
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'application_forms',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': record.id},
            ],
            'values': {'is_active': active},
          },
        );
      } else {
        if (client == null) return;
        await client
            .from('application_forms')
            .update({'is_active': active})
            .eq('id', record.id);
      }
      ref.invalidate(applicationFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            active
                ? 'Başvuru yeniden aktifleştirildi.'
                : 'Başvuru pasife alındı.',
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

  Future<void> _deleteRecordPermanently(ApplicationFormRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Başvuruyu kalıcı sil'),
        content: Text(
          '"${record.customerName}" başvurusu kalıcı olarak silinecek. Bu işlem geri alınamaz.',
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
          body: {'op': 'delete', 'table': 'application_forms', 'id': record.id},
        );
      } else {
        if (client == null) return;
        await client.from('application_forms').delete().eq('id', record.id);
      }
      ref.invalidate(applicationFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvuru kalıcı olarak silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Silinemedi: $e')),
      );
    }
  }

  String _defaultWorkOrderDescription(ApplicationFormRecord record) {
    final parts = <String>[
      'Başvuru Formu',
      if (record.brandModel.trim().isNotEmpty) record.brandModel.trim(),
      if (record.businessActivityName?.trim().isNotEmpty ?? false)
        record.businessActivityName!.trim(),
      if (record.fileRegistryNumber?.trim().isNotEmpty ?? false)
        'Dosya: ${record.fileRegistryNumber!.trim()}',
    ];
    return parts.join(' • ');
  }

  Future<void> _openCreateWorkOrdersDialog(
    List<ApplicationFormRecord> records,
  ) async {
    final linkedRecords = records
        .where((record) => (record.customerId ?? '').trim().isNotEmpty)
        .toList(growable: false);
    final skippedCount = records.length - linkedRecords.length;

    if (linkedRecords.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Secili başvurularda bağlı müşteri bulunmadığı için iş emri oluşturulamadı.',
          ),
        ),
      );
      return;
    }

    final config = await showDialog<_WorkOrderCreationConfig>(
      context: context,
      builder: (context) =>
          _ApplicationWorkOrderDialog(recordCount: linkedRecords.length),
    );
    if (config == null) return;

    final profile = await ref.read(currentUserProfileProvider.future);
    final currentUserId = profile?.id;
    if (!mounted) return;
    if ((currentUserId ?? '').isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Oturum bulunamadı.')),
      );
      return;
    }

    final isAdmin = profile?.role == 'admin';
    final assignedTo = isAdmin
        ? (config.assignedTo?.trim().isNotEmpty ?? false
            ? config.assignedTo!.trim()
            : currentUserId!)
        : currentUserId!;
    final scheduledDate = config.scheduledDate == null
        ? null
        : DateFormat('yyyy-MM-dd').format(config.scheduledDate!);
    final descriptionTemplate = config.description.trim();

    var createdCount = 0;
    var failedCount = 0;

    for (final record in linkedRecords) {
      final payload = <String, dynamic>{
        'customer_id': record.customerId,
        'branch_id': null,
        'work_order_type_id': config.workOrderTypeId,
        'title': config.workOrderTypeName,
        'description': descriptionTemplate.isNotEmpty
            ? descriptionTemplate
            : _defaultWorkOrderDescription(record),
        'address': record.workAddress?.trim().isNotEmpty ?? false
            ? record.workAddress!.trim()
            : null,
        'assigned_to': assignedTo,
        'scheduled_date': scheduledDate,
        'city': record.taxOfficeCityName?.trim().isNotEmpty ?? false
            ? record.taxOfficeCityName!.trim()
            : null,
        'contact_phone': null,
        'location_link': null,
      };

      try {
        await _insertWorkOrderPayload(payload: payload);
        createdCount += 1;
      } catch (_) {
        failedCount += 1;
      }
    }

    ref.invalidate(workOrdersBoardProvider);
    if (!mounted) return;

    final segments = <String>[
      if (createdCount > 0) '$createdCount iş emri oluşturuldu',
      if (skippedCount > 0)
        '$skippedCount kayıt müşteri bağlantısı olmadığı için atlandı',
      if (failedCount > 0) '$failedCount kayıt oluşturulamadı',
    ];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(segments.join(' • '))),
    );
  }

  Future<void> _insertWorkOrderPayload({
    required Map<String, dynamic> payload,
  }) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) {
      throw Exception('API bağlantısı bulunamadı.');
    }

    if (apiClient != null) {
      await apiClient.postJson(
        '/work-orders',
        body: {
          'customer_id': payload['customer_id'],
          'branch_id': payload['branch_id'],
          'work_order_type_id': payload['work_order_type_id'],
          'title': payload['title'],
          'description': payload['description'],
          'address': payload['address'],
          'city': payload['city'],
          'assigned_to': payload['assigned_to'],
          'scheduled_date': payload['scheduled_date'],
          'contact_phone': payload['contact_phone'],
          'location_link': payload['location_link'],
        },
      );
      return;
    }

    final safePayload = Map<String, dynamic>.from(payload);
    const fallbackColumns = {
      'address',
      'city',
      'contact_phone',
      'location_link',
      'work_order_type_id',
    };

    while (true) {
      try {
        await client!.from('work_orders').insert(safePayload);
        return;
      } catch (e) {
        final message = e.toString();
        final matchedColumn = fallbackColumns.firstWhere(
          (column) =>
              message.contains("'$column' column") ||
              message.contains('column "$column"') ||
              message.contains("Could not find the '$column' column"),
          orElse: () => '',
        );
        if (matchedColumn.isEmpty || !safePayload.containsKey(matchedColumn)) {
          rethrow;
        }
        safePayload.remove(matchedColumn);
      }
    }
  }

  Future<void> _exportForTaxOffice(List<ApplicationFormRecord> records) async {
    if (records.isEmpty) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if ((apiClient == null && client == null) || !mounted) return;

    final customerIds = records
        .map((record) => record.customerId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final customerMap = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'form_customers_bulk',
            'ids': customerIds.join(','),
          },
        );
        final rows = (response['items'] as List?) ?? const [];
        for (final row in rows) {
          if (row is Map<String, dynamic>) {
            customerMap[row['id'].toString()] = row;
          }
        }
      } else {
        final rows = await client!
            .from('customers')
            .select('id,vkn,tckn_ms')
            .inFilter('id', customerIds);
        for (final row in rows as List) {
          final item = row as Map<String, dynamic>;
          customerMap[item['id'].toString()] = item;
        }
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

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if ((apiClient == null && client == null) || !mounted) return;

    final customerIds = records
        .map((record) => record.customerId)
        .whereType<String>()
        .toSet()
        .toList(growable: false);

    final customerMap = <String, Map<String, dynamic>>{};
    if (customerIds.isNotEmpty) {
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'form_customers_bulk',
            'ids': customerIds.join(','),
          },
        );
        final rows = (response['items'] as List?) ?? const [];
        for (final row in rows) {
          if (row is Map<String, dynamic>) {
            customerMap[row['id'].toString()] = row;
          }
        }
      } else {
        final rows = await client!
            .from('customers')
            .select('id,vkn,tckn_ms,phone_1,phone_2,phone_3')
            .inFilter('id', customerIds);
        for (final row in rows as List) {
          final item = row as Map<String, dynamic>;
          customerMap[item['id'].toString()] = item;
        }
      }
    }

    final templateData = await rootBundle.load(
      'assets/templates/tsm_template.xlsx',
    );
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
      final tcknMs = (customer?['tckn_ms'] ?? record.customerTcknMs ?? '')
          .toString()
          .trim();
      final serialRaw = (record.stockRegistryNumber ?? '').trim().toUpperCase();
      final serialNumber = serialRaw;
      final modelCode = _resolveTsmModel(serialRaw);
      final address = (record.workAddress ?? '').trim();
      final invoiceDate = record.applicationDate
          .toIso8601String()
          .split('T')
          .first;

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
          excel.CellIndex.indexByColumnRow(
            columnIndex: col,
            rowIndex: rowIndex,
          ),
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
    return (words.take(splitIndex).join(' '), words.skip(splitIndex).join(' '));
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
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDeletePermanently = ref.watch(
      hasActionAccessProvider(kActionDeleteRecords),
    );

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
          final baseFiltered = _filterRecords(records, includeTodayOnly: false)
              .where((item) => _showPassive ? !item.isActive : item.isActive)
              .toList(growable: false);
          final filtered = _todayOnly
              ? baseFiltered
                    .where(
                      (item) => _isSameDay(
                        item.applicationDate,
                        DateTime.now(),
                      ),
                    )
                    .toList(growable: false)
              : baseFiltered;
          final selectedRecords = filtered
              .where((record) => _selectedRecordIds.contains(record.id))
              .toList(growable: false);
          final allFilteredSelected =
              filtered.isNotEmpty && selectedRecords.length == filtered.length;
          final todayCount = baseFiltered
              .where((item) => _isSameDay(item.applicationDate, DateTime.now()))
              .length;

          Future<void> openMobileFiltersSheet() async {
            await showModalBottomSheet<void>(
              context: context,
              showDragHandle: true,
              isScrollControlled: true,
              builder: (context) => SafeArea(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    8,
                    16,
                    16 + MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Filtreler',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const Gap(12),
                      TextField(
                        controller: _customerFilterController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Müşteri',
                          hintText: 'Müşteri adına göre ara',
                          prefixIcon: Icon(Icons.person_search_rounded),
                        ),
                      ),
                      const Gap(10),
                      TextField(
                        controller: _registryFilterController,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Cihaz / Sicil No',
                          hintText: 'Dosya veya cihaz sicili',
                          prefixIcon: Icon(Icons.confirmation_num_rounded),
                        ),
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
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
                          const Gap(10),
                          Expanded(
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
                        ],
                      ),
                      const Gap(10),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: () {
                                setState(() {
                                  _customerFilterController.clear();
                                  _registryFilterController.clear();
                                  _fromDate = null;
                                  _toDate = null;
                                  _todayOnly = false;
                                });
                                Navigator.of(context).pop();
                              },
                              icon: const Icon(Icons.filter_alt_off_rounded),
                              label: const Text('Temizle'),
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

          final filterCard = AppCard(
            padding: const EdgeInsets.all(12),
            child: isMobile
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _customerFilterController,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                prefixIcon: Icon(Icons.person_search_rounded),
                                hintText: 'Müşteri ara',
                              ),
                            ),
                          ),
                          const Gap(10),
                          IconButton.filledTonal(
                            onPressed: openMobileFiltersSheet,
                            icon: const Icon(Icons.tune_rounded),
                          ),
                        ],
                      ),
                    ],
                  )
                : Column(
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
                                prefixIcon:
                                    Icon(Icons.confirmation_num_rounded),
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
                          OutlinedButton.icon(
                            onPressed: () {
                              setState(() {
                                _customerFilterController.clear();
                                _registryFilterController.clear();
                                _fromDate = null;
                                _toDate = null;
                                _todayOnly = false;
                              });
                            },
                            icon: const Icon(Icons.filter_alt_off_rounded),
                            label: const Text('Temizle'),
                          ),
                        ],
                      ),
                    ],
                  ),
          );

          final statsCard = AppCard(
            padding: const EdgeInsets.all(12),
            child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Wrap(
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
                          value: todayCount.toString(),
                          icon: Icons.today_rounded,
                          selected: _todayOnly,
                          onTap: () =>
                              setState(() => _todayOnly = !_todayOnly),
                        ),
                      ],
                    ),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (!isMobile) ...[
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
                                allFilteredSelected
                                    ? 'Seçimi Temizle'
                                    : 'Tümünü Seç',
                              ),
                            ),
                          FilterChip(
                            selected: _showPassive,
                            onSelected: (value) =>
                                setState(() => _showPassive = value),
                            label: const Text('Pasifleri Göster'),
                            visualDensity: VisualDensity.compact,
                          ),
                          if (selectedRecords.isNotEmpty) ...[
                            FilledButton.icon(
                              onPressed: () =>
                                  _openCreateWorkOrdersDialog(selectedRecords),
                              icon: const Icon(Icons.playlist_add_rounded,
                                  size: 18),
                              label: Text(
                                'İş Emri Oluştur (${selectedRecords.length})',
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: () =>
                                  _exportForTaxOffice(selectedRecords),
                              icon: const Icon(Icons.download_rounded, size: 18),
                              label: Text(
                                'Vergi Dairesine Gönder (${selectedRecords.length})',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _exportForTsm(selectedRecords),
                              icon: const Icon(Icons.table_chart_rounded,
                                  size: 18),
                              label: Text(
                                'TSM\'e Gönder (${selectedRecords.length})',
                              ),
                            ),
                          ],
                        ] else ...[
                          FilledButton.tonalIcon(
                            onPressed: () async {
                              await showModalBottomSheet<void>(
                                context: context,
                                showDragHandle: true,
                                builder: (context) => SafeArea(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'İşlemler',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium,
                                        ),
                                        const Gap(12),
                                        SwitchListTile(
                                          value: _showPassive,
                                          onChanged: (v) {
                                            setState(() => _showPassive = v);
                                            Navigator.of(context).pop();
                                          },
                                          title: const Text('Pasifleri Göster'),
                                          contentPadding: EdgeInsets.zero,
                                        ),
                                        if (filtered.isNotEmpty) ...[
                                          ListTile(
                                            leading: Icon(
                                              allFilteredSelected
                                                  ? Icons.deselect_rounded
                                                  : Icons.select_all_rounded,
                                            ),
                                            title: Text(
                                              allFilteredSelected
                                                  ? 'Seçimi Temizle'
                                                  : 'Tümünü Seç',
                                            ),
                                            onTap: () {
                                              setState(() {
                                                if (allFilteredSelected) {
                                                  for (final record in filtered) {
                                                    _selectedRecordIds
                                                        .remove(record.id);
                                                  }
                                                } else {
                                                  for (final record in filtered) {
                                                    _selectedRecordIds
                                                        .add(record.id);
                                                  }
                                                }
                                              });
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ],
                                        if (selectedRecords.isNotEmpty) ...[
                                          ListTile(
                                            leading: const Icon(
                                                Icons.playlist_add_rounded),
                                            title: Text(
                                              'İş Emri Oluştur (${selectedRecords.length})',
                                            ),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _openCreateWorkOrdersDialog(
                                                selectedRecords,
                                              );
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                                Icons.download_rounded),
                                            title: Text(
                                              'Vergi Dairesine Gönder (${selectedRecords.length})',
                                            ),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _exportForTaxOffice(selectedRecords);
                                            },
                                          ),
                                          ListTile(
                                            leading: const Icon(
                                                Icons.table_chart_rounded),
                                            title: Text(
                                              'TSM\'e Gönder (${selectedRecords.length})',
                                            ),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _exportForTsm(selectedRecords);
                                            },
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                            icon: const Icon(Icons.more_horiz_rounded, size: 18),
                            label: Text(
                              selectedRecords.isEmpty
                                  ? 'İşlemler'
                                  : 'İşlemler (${selectedRecords.length})',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
          );

          if (isMobile) {
            return ListView.separated(
              padding: const EdgeInsets.only(bottom: 120),
              itemCount: filtered.length + 2,
              separatorBuilder: (context, index) => const Gap(12),
              itemBuilder: (context, index) {
                if (index == 0) return filterCard;
                if (index == 1) return statsCard;
                final r = filtered[index - 2];
                return _ApplicationRecordCard(
                  record: r,
                  canEdit: canEdit,
                  canArchive: canArchive,
                  canDeletePermanently: canDeletePermanently,
                  selected: _selectedRecordIds.contains(r.id),
                  onSelectionChanged: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedRecordIds.add(r.id);
                      } else {
                        _selectedRecordIds.remove(r.id);
                      }
                    });
                  },
                  onPrintKdv: () => _print(r, kind: ApplicationPrintKind.kdv),
                  onPrintKdv4a: () => _print(r, kind: ApplicationPrintKind.kdv4a),
                  onCreateWorkOrder: () => _openCreateWorkOrdersDialog([r]),
                  onEdit: () => _openEditDialog(r),
                  onDuplicate: () => _openDuplicateDialog(r),
                  onToggleActive: () => _setRecordActive(r, !r.isActive),
                  onDeletePermanently: () => _deleteRecordPermanently(r),
                );
              },
            );
          }

          return Column(
            children: [
              filterCard,
              const Gap(12),
              statsCard,
              const Gap(12),
              if (filtered.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Text('Filtreye uygun başvuru bulunamadı.'),
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(bottom: 120),
                  child: Column(
                    children: [
                      for (var index = 0; index < filtered.length; index++) ...[
                        _ApplicationRecordCard(
                          record: filtered[index],
                          canEdit: canEdit,
                          canArchive: canArchive,
                          canDeletePermanently: canDeletePermanently,
                          selected: _selectedRecordIds.contains(
                            filtered[index].id,
                          ),
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
                          onCreateWorkOrder: () =>
                              _openCreateWorkOrdersDialog([filtered[index]]),
                          onEdit: () => _openEditDialog(filtered[index]),
                          onDuplicate: () =>
                              _openDuplicateDialog(filtered[index]),
                          onToggleActive: () => _setRecordActive(
                            filtered[index],
                            !filtered[index].isActive,
                          ),
                          onDeletePermanently: () =>
                              _deleteRecordPermanently(filtered[index]),
                        ),
                        if (index != filtered.length - 1) const Gap(12),
                      ],
                    ],
                  ),
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
    {bool includeTodayOnly = true}
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

          if (includeTodayOnly &&
              _todayOnly &&
              !_isSameDay(item.applicationDate, DateTime.now())) {
            return false;
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
  late final TextEditingController _invoiceNumberController;
  late final TextEditingController _productNameController;
  late final TextEditingController _manualSerialsController;
  DateTime _applicationDate = DateTime.now();
  DateTime _okcStartDate = DateTime.now();
  final String _documentType = 'VKN';
  String? _selectedCustomerId;
  String? _selectedCityId;
  String? _selectedModelId;
  String? _selectedFiscalSymbolId;
  List<String> _selectedBusinessActivityIds = [];
  bool _saving = false;
  String? _autoFilledProductForSerial;

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
    _invoiceNumberController = TextEditingController(
      text: widget.duplicateMode ? '' : (initial?.invoiceNumber ?? ''),
    );
    _productNameController = TextEditingController(text: 'ÖKC');
    _manualSerialsController = TextEditingController();
    _applicationDate =
        widget.duplicateMode ? DateTime.now() : (initial?.applicationDate ?? DateTime.now());
    _okcStartDate =
        widget.duplicateMode ? DateTime.now() : (initial?.okcStartDate ?? DateTime.now());
    _selectedCustomerId = initial?.customerId;
    if (widget.duplicateMode) {
      _fileRegistryController.text = '';
      _manualSerialsController.text = '';
    }
    _loadInitialSelections();
  }

  Future<void> _loadInitialSelections() async {
    final initial = widget.initialRecord;
    if (initial == null) return;

    final customers = await ref.read(applicationFormCustomersProvider.future);
    final cities = await ref.read(cityDefinitionsProvider.future);
    final models = await ref.read(deviceModelsProvider.future);
    final fiscalSymbols = await ref.read(fiscalSymbolsProvider.future);
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
      if (!widget.duplicateMode) {
        if ((initial.stockRegistryNumber?.trim().isNotEmpty ?? false) &&
            _manualSerialsController.text.trim().isEmpty) {
          _manualSerialsController.text = initial.stockRegistryNumber!.trim();
        }
      }
      if (_selectedBusinessActivityIds.isEmpty) {
        final selectedNames = (initial.businessActivityName ?? '')
            .split(',')
            .map((item) => _sortKey(item))
            .where((item) => item.isNotEmpty)
            .toSet();
        _selectedBusinessActivityIds = activities
            .where((item) => selectedNames.contains(_sortKey(item.name)))
            .map((item) => item.id)
            .toList(growable: false);
      }
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
    _invoiceNumberController.dispose();
    _productNameController.dispose();
    _manualSerialsController.dispose();
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
      _directorController.text = (created.directorName ?? '').trim();
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
      _directorController.text = (selected.directorName ?? '').trim();
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

  List<String> get _manualRegistryNumbers => _manualSerialsController.text
      .split(RegExp(r'[\n,;]+'))
      .map((item) => item.trim().toUpperCase())
      .where((item) => item.isNotEmpty)
      .toSet()
      .toList(growable: false);

  String? get _primaryRegistryNumber {
    final items = _manualRegistryNumbers;
    if (items.isEmpty) return null;
    return items.first;
  }

  Future<void> _saveSerialToTracking({
    required String serialNumber,
    required String productName,
  }) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'serial_tracking',
          'values': {
            'product_name': productName.trim(),
            'serial_number': serialNumber.trim().toUpperCase(),
            'is_active': true,
          },
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seri takip kaydı eklendi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Kaydedilemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickSerialFromTracking() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'serial_tracking'},
    );
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(_SerialTrackingOption.fromJson)
        .where((item) => item.isActive)
        .toList(growable: false);

    if (!mounted) return;
    final selected = await showDialog<List<_SerialTrackingOption>>(
      context: context,
      builder: (context) => _SerialTrackingPickerDialog(
        items: items,
        allowMultiple: !widget.isEdit,
        initialSelectedSerials: _manualRegistryNumbers.toSet(),
      ),
    );
    if (selected == null || selected.isEmpty || !mounted) return;

    setState(() {
      _manualSerialsController.text =
          selected.map((e) => e.serialNumber).join('\n');
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final customers = ref.read(applicationFormCustomersProvider).asData?.value;
    final cities = ref.read(cityDefinitionsProvider).asData?.value;
    final models = ref.read(deviceModelsProvider).asData?.value;
    final fiscalSymbols = ref.read(fiscalSymbolsProvider).asData?.value;
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
    final productName = _productNameController.text.trim();
    final registryNumbers = _manualRegistryNumbers;
    final selectedActivities =
        (activities ?? const <BusinessActivityTypeDefinition>[])
            .where((item) => _selectedBusinessActivityIds.contains(item.id))
            .toList(growable: false);

    if (productName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ürün ismi girin.')),
      );
      return;
    }
    if (registryNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az bir sicil numarası seçin.'),
        ),
      );
      return;
    }
    if (widget.isEdit && registryNumbers.length > 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Düzenleme modunda yalnızca tek seri seçilebilir.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final basePayload = {
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
        'stock_product_id': null,
        'stock_product_name': productName,
        'accounting_office': _accountingOfficeController.text.trim().isEmpty
            ? null
            : _accountingOfficeController.text.trim(),
        'okc_start_date': DateFormat('yyyy-MM-dd').format(_okcStartDate),
        'business_activity_type_id': selectedActivities.firstOrNull?.id,
        'business_activity_name': selectedActivities
            .map((item) => item.name.trim())
            .where((item) => item.isNotEmpty)
            .join(', '),
        'invoice_number': _invoiceNumberController.text.trim().isEmpty
            ? null
            : _invoiceNumberController.text.trim(),
      };

      if (widget.isEdit) {
        final primaryRegistry = registryNumbers.first;
        Map<String, dynamic> inserted;
        if (apiClient != null) {
          final response = await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'application_forms',
              'returning': 'row',
              'values': {
                'id': widget.initialRecord!.id,
                ...basePayload,
                'stock_registry_number':
                    primaryRegistry.isEmpty ? null : primaryRegistry,
              },
            },
          );
          inserted = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
        } else {
          inserted = await client!
              .from('application_forms')
              .update({
                ...basePayload,
                'stock_registry_number':
                    primaryRegistry.isEmpty ? null : primaryRegistry,
              })
              .eq('id', widget.initialRecord!.id)
              .select(
                'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,is_active,created_at',
              )
              .single();
        }
        ref.invalidate(applicationFormsProvider);
        if (!mounted) return;
        Navigator.of(context).pop([ApplicationFormRecord.fromJson(inserted)]);
        return;
      }

      final payloads = (registryNumbers.isEmpty
              ? const <String?>[null]
              : registryNumbers.map<String?>((item) => item))
          .map(
            (registry) => {
              ...basePayload,
              'stock_registry_number': registry?.trim().isNotEmpty ?? false
                  ? registry!.trim()
                  : null,
            },
          )
          .toList(growable: false);

      final List<ApplicationFormRecord> insertedRecords;
      if (apiClient != null) {
        final rows = <Map<String, dynamic>>[];
        for (final payload in payloads) {
          final response = await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'application_forms',
              'returning': 'row',
              'values': {...payload, 'is_active': true},
            },
          );
          final row = (response['row'] as Map?)?.cast<String, dynamic>();
          if (row != null && row.isNotEmpty) rows.add(row);
        }
        insertedRecords =
            rows.map(ApplicationFormRecord.fromJson).toList(growable: false);

        final modelName = model?.name.trim();
        for (final inserted in insertedRecords) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'insertMany',
              'table': 'invoice_items',
              'rows': [
                {
                  'customer_id': customer?.id,
                  'item_type': 'application_form',
                  'source_table': 'application_forms',
                  'source_id': inserted.id,
                  'description':
                      'Başvuru Formu - ${_customerController.text.trim()}'
                      '${modelName != null && modelName.isNotEmpty ? ' / $modelName' : ''}'
                      '${inserted.stockRegistryNumber?.trim().isNotEmpty ?? false ? ' / ${inserted.stockRegistryNumber!.trim()}' : ''}',
                  'amount': null,
                  'currency': 'TRY',
                  'status': 'pending',
                  'is_active': true,
                  'source_event': 'application_form_created',
                  'source_label': 'Başvuru Formu',
                },
              ],
            },
          );
        }
      } else {
        final insertedRows = await client!
            .from('application_forms')
            .insert(payloads)
            .select(
              'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,is_active,created_at',
            );

        insertedRecords = (insertedRows as List)
            .map(
              (row) =>
                  ApplicationFormRecord.fromJson(row as Map<String, dynamic>),
            )
            .toList(growable: false);

        for (final inserted in insertedRecords) {
          final modelName = model?.name.trim();
          await enqueueInvoiceItem(
            client,
            customerId: customer?.id,
            itemType: 'application_form',
            sourceTable: 'application_forms',
            sourceId: inserted.id,
            description:
                'Başvuru Formu - ${_customerController.text.trim()}'
                '${modelName != null && modelName.isNotEmpty ? ' / $modelName' : ''}'
                '${inserted.stockRegistryNumber?.trim().isNotEmpty ?? false ? ' / ${inserted.stockRegistryNumber!.trim()}' : ''}',
            sourceEvent: 'application_form_created',
            sourceLabel: 'Başvuru Formu',
          );
        }
      }

      ref.invalidate(applicationFormsProvider);
      if (!mounted) return;
      Navigator.of(context).pop(insertedRecords);
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
    final activitiesAsync = ref.watch(businessActivityTypesProvider);
    final serialLookupAsync = _primaryRegistryNumber == null
        ? const AsyncValue<Map<String, dynamic>?>.data(null)
        : ref.watch(serialTrackingLookupProvider(_primaryRegistryNumber!));

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
          validator: (value) => value == null || value.trim().isEmpty
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
            items: const [DropdownMenuItem(value: 'VKN', child: Text('VKN'))],
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
        label: 'Direktör Ad Soyad',
        child: _ApplicationTextField(controller: _directorController),
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
        label: 'Ürün ve Sicil No',
        child: _ResponsiveFieldGroup(
          left: _ApplicationTextField(
            controller: _productNameController,
            readOnly: true,
            enabled: false,
            validator: (value) => value == null || value.trim().isEmpty
                ? 'Ürün ismi zorunlu.'
                : null,
          ),
          right: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : _pickSerialFromTracking,
                    icon: const Icon(Icons.playlist_add_rounded, size: 18),
                    label: const Text('Seri Seç'),
                  ),
                  const Gap(10),
                  Text(
                    'Kayıtlı seri havuzundan seçebilir veya manuel girebilirsiniz.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ],
              ),
              const Gap(8),
              TextFormField(
                controller: _manualSerialsController,
                minLines: widget.isEdit ? 1 : 2,
                maxLines: widget.isEdit ? 2 : 3,
                onChanged: (_) {
                  _autoFilledProductForSerial = null;
                  setState(() {});
                },
                decoration: InputDecoration(
                  labelText:
                      widget.isEdit ? 'Ürün Sicil No' : 'Ürün Sicil No(ları)',
                  hintText: widget.isEdit
                      ? 'Tek sicil no girin'
                      : 'Sicilleri alt alta veya virgülle girin',
                  alignLabelWithHint: true,
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                ),
                validator: (value) {
                  final raw = value?.trim() ?? '';
                  if (raw.isEmpty) return 'Sicil no zorunlu.';
                  if (widget.isEdit &&
                      raw
                              .split(RegExp(r'[\n,;]+'))
                              .where((e) => e.trim().isNotEmpty)
                              .length >
                          1) {
                    return 'Düzenlemede tek sicil no girin.';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      if (_primaryRegistryNumber != null)
        _FormRow(
          label: 'Seri Takip',
          child: serialLookupAsync.when(
            data: (match) {
              final serial = _primaryRegistryNumber!.trim().toUpperCase();
              if (match != null) {
                final productName = (match['product_name'] ?? '').toString();
                final isActive = (match['is_active'] as bool?) ?? true;

                if (_productNameController.text.trim().isEmpty &&
                    productName.trim().isNotEmpty &&
                    _autoFilledProductForSerial != serial) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (!mounted) return;
                    if (_productNameController.text.trim().isNotEmpty) return;
                    _productNameController.text = productName.trim();
                    _autoFilledProductForSerial = serial;
                  });
                }

                return AppCard(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        isActive
                            ? Icons.check_circle_rounded
                            : Icons.pause_circle_filled_rounded,
                        color: isActive ? const Color(0xFF16A34A) : const Color(0xFF64748B),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seri takipte kayıtlı: $serial',
                              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const Gap(4),
                            Text(
                              productName.trim().isEmpty ? 'Ürün adı yok' : productName.trim(),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      AppBadge(
                        label: isActive ? 'Aktif' : 'Pasif',
                        tone: isActive ? AppBadgeTone.success : AppBadgeTone.neutral,
                      ),
                    ],
                  ),
                );
              }

              final canQuickAdd = _productNameController.text.trim().isNotEmpty;
              return AppCard(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded, color: Color(0xFF64748B)),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Bu sicil numarası seri takipte yok: $serial',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: AppTheme.textMuted),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: canQuickAdd && !_saving
                          ? () => _saveSerialToTracking(
                                serialNumber: serial,
                                productName: _productNameController.text,
                              )
                          : null,
                      icon: const Icon(Icons.add_rounded, size: 18),
                      label: const Text('Seri Takibe Ekle'),
                    ),
                  ],
                ),
              );
            },
            loading: () => const _ContentLoading(),
            error: (error, _) => AppCard(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Seri takip kontrolü yapılamadı: $error',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: AppTheme.textMuted),
                ),
              ),
            ),
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
            data: (items) => _BusinessActivityMultiSelectField(
              items: items
                  .where((item) => item.isActive)
                  .toList(growable: false),
              selectedIds: _selectedBusinessActivityIds,
              onChanged: (value) =>
                  setState(() => _selectedBusinessActivityIds = value),
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
          maxWidth: isMobile ? 720 : 1780,
          maxHeight: MediaQuery.sizeOf(context).height * 0.996,
        ),
        child: AppCard(
          padding: EdgeInsets.symmetric(
            horizontal: isMobile ? 18 : 28,
            vertical: isMobile ? 20 : 30,
          ),
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
                  const Gap(16),
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
                            const Gap(14),
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
                  const Gap(16),
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

final serialTrackingLookupProvider =
    FutureProvider.family<Map<String, dynamic>?, String>((ref, serial) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return null;
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'serial_tracking_lookup', 'serial': serial},
  );
  final item = response['item'];
  return item is Map ? item.cast<String, dynamic>() : null;
});

class _SerialTrackingOption {
  const _SerialTrackingOption({
    required this.id,
    required this.serialNumber,
    required this.productName,
    required this.isActive,
  });

  final String id;
  final String serialNumber;
  final String productName;
  final bool isActive;

  factory _SerialTrackingOption.fromJson(Map<String, dynamic> json) {
    return _SerialTrackingOption(
      id: json['id']?.toString() ?? '',
      serialNumber: (json['serial_number'] ?? '').toString(),
      productName: (json['product_name'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

class _SerialTrackingPickerDialog extends StatefulWidget {
  const _SerialTrackingPickerDialog({
    required this.items,
    required this.allowMultiple,
    required this.initialSelectedSerials,
  });

  final List<_SerialTrackingOption> items;
  final bool allowMultiple;
  final Set<String> initialSelectedSerials;

  @override
  State<_SerialTrackingPickerDialog> createState() =>
      _SerialTrackingPickerDialogState();
}

class _SerialTrackingPickerDialogState extends State<_SerialTrackingPickerDialog> {
  final _searchController = TextEditingController();
  late Set<String> _selectedSerials;

  @override
  void initState() {
    super.initState();
    _selectedSerials = {...widget.initialSelectedSerials};
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggle(_SerialTrackingOption item, bool selected) {
    final serial = item.serialNumber.trim().toUpperCase();
    if (serial.isEmpty) return;
    setState(() {
      if (!widget.allowMultiple) {
        _selectedSerials = selected ? {serial} : <String>{};
        return;
      }
      if (selected) {
        _selectedSerials.add(serial);
      } else {
        _selectedSerials.remove(serial);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final query = _sortKey(_searchController.text);
    final filtered = widget.items.where((item) {
      if (query.isEmpty) return true;
      final haystack = _sortKey('${item.serialNumber} ${item.productName}');
      return haystack.contains(query);
    }).toList(growable: false);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.allowMultiple ? 'Seri Seç' : 'Seri Seç (Tek)',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(10),
              TextField(
                controller: _searchController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Sicil no veya ürün adı ara',
                ),
              ),
              const Gap(12),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'Uygun seri bulunamadı.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final serial =
                              item.serialNumber.trim().toUpperCase();
                          final selected = _selectedSerials.contains(serial);
                          return ListTile(
                            dense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            onTap: () => _toggle(item, !selected),
                            leading: widget.allowMultiple
                                ? Checkbox(
                                    value: selected,
                                    onChanged: (value) =>
                                        _toggle(item, value ?? false),
                                  )
                                : IconButton(
                                    onPressed: () => _toggle(item, true),
                                    icon: Icon(
                                      selected
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_off_rounded,
                                      color: selected
                                          ? AppTheme.primary
                                          : const Color(0xFF94A3B8),
                                    ),
                                  ),
                            title: Text(
                              item.serialNumber,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            subtitle: item.productName.trim().isNotEmpty
                                ? Text(item.productName.trim())
                                : null,
                          );
                        },
                      ),
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
                  const Gap(10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        final selectedItems = widget.items
                            .where(
                              (item) => _selectedSerials.contains(
                                item.serialNumber.trim().toUpperCase(),
                              ),
                            )
                            .toList(growable: false);
                        Navigator.of(context).pop(selectedItems);
                      },
                      child: Text(
                        widget.allowMultiple ? 'Serileri Seç' : 'Seriyi Seç',
                      ),
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

class _ApplicationRecordCard extends StatelessWidget {
  const _ApplicationRecordCard({
    required this.record,
    required this.canEdit,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.selected,
    required this.onSelectionChanged,
    required this.onPrintKdv,
    required this.onPrintKdv4a,
    required this.onCreateWorkOrder,
    required this.onEdit,
    required this.onDuplicate,
    required this.onToggleActive,
    required this.onDeletePermanently,
  });

  final ApplicationFormRecord record;
  final bool canEdit;
  final bool canArchive;
  final bool canDeletePermanently;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onPrintKdv;
  final VoidCallback onPrintKdv4a;
  final VoidCallback onCreateWorkOrder;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onToggleActive;
  final VoidCallback onDeletePermanently;

  @override
  Widget build(BuildContext context) {
    final dateText = DateFormat(
      'd MMM y',
      'tr_TR',
    ).format(record.applicationDate);
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    final accentColor = record.isActive ? AppTheme.primary : AppTheme.textMuted;
    final badgeLabel = record.isActive ? record.documentType : 'Pasif';
    final badgeTone = record.isActive ? AppBadgeTone.primary : AppBadgeTone.neutral;

    final menuItems = <PopupMenuEntry<String>>[
      if (canEdit)
        const PopupMenuItem(
          value: 'edit',
          child: Text('Düzenle'),
        ),
      if (canEdit)
        const PopupMenuItem(
          value: 'duplicate',
          child: Text('Kopya Oluştur'),
        ),
      const PopupMenuItem(
        value: 'print_kdv4',
        child: Text('KDV4 Yazdır'),
      ),
      const PopupMenuItem(
        value: 'print_kdv4a',
        child: Text('KDV4A Yazdır'),
      ),
      const PopupMenuItem(
        value: 'create_work_order',
        child: Text('İş Emri Oluştur'),
      ),
      if (canArchive)
        PopupMenuItem(
          value: 'toggle_active',
          child: Text(record.isActive ? 'Pasife Al' : 'Aktifleştir'),
        ),
      if (!record.isActive && canDeletePermanently)
        const PopupMenuItem(
          value: 'delete_permanently',
          child: Text('Kalıcı Sil'),
        ),
    ];

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
              Container(
                width: 10,
                height: 42,
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: accentColor.withValues(alpha: 0.25)),
                ),
              ),
              const Gap(6),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Checkbox(
                  value: selected,
                  visualDensity: const VisualDensity(horizontal: -4, vertical: -4),
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
              const Gap(8),
              AppBadge(label: badgeLabel, tone: badgeTone),
              const Gap(6),
              if (isMobile)
                PopupMenuButton<String>(
                  tooltip: 'İşlemler',
                  itemBuilder: (context) => menuItems,
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        onEdit();
                        break;
                      case 'duplicate':
                        onDuplicate();
                        break;
                      case 'print_kdv4':
                        onPrintKdv();
                        break;
                      case 'print_kdv4a':
                        onPrintKdv4a();
                        break;
                      case 'create_work_order':
                        onCreateWorkOrder();
                        break;
                      case 'toggle_active':
                        onToggleActive();
                        break;
                      case 'delete_permanently':
                        onDeletePermanently();
                        break;
                      default:
                        break;
                    }
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.more_horiz_rounded),
                  ),
                )
              else ...[
                if (canEdit) ...[
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
                ],
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
                  onPressed: onCreateWorkOrder,
                  icon: Icons.playlist_add_rounded,
                  label: 'İş Emri',
                ),
                if (canArchive) ...[
                  const Gap(4),
                  _ActionButton(
                    onPressed: onToggleActive,
                    icon: record.isActive
                        ? Icons.delete_outline_rounded
                        : Icons.restore_rounded,
                    label: record.isActive ? 'Pasif' : 'Aktif',
                  ),
                ],
                if (!record.isActive && canDeletePermanently) ...[
                  const Gap(4),
                  _ActionButton(
                    onPressed: onDeletePermanently,
                    icon: Icons.delete_forever_rounded,
                    label: 'Kalıcı Sil',
                  ),
                ],
              ],
            ],
          ),
          const Gap(5),
          Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              _InfoChip(icon: Icons.calendar_today_rounded, text: dateText),
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

class _WorkOrderCreationConfig {
  const _WorkOrderCreationConfig({
    required this.workOrderTypeId,
    required this.workOrderTypeName,
    required this.assignedTo,
    required this.scheduledDate,
    required this.description,
  });

  final String? workOrderTypeId;
  final String workOrderTypeName;
  final String? assignedTo;
  final DateTime? scheduledDate;
  final String description;
}

class _WorkOrderTypeChoice {
  const _WorkOrderTypeChoice({
    required this.id,
    required this.name,
  });

  final String id;
  final String name;

  factory _WorkOrderTypeChoice.fromJson(Map<String, dynamic> json) {
    return _WorkOrderTypeChoice(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
    );
  }
}

class _PersonnelChoice {
  const _PersonnelChoice({
    required this.id,
    required this.fullName,
  });

  final String id;
  final String fullName;

  factory _PersonnelChoice.fromJson(Map<String, dynamic> json) {
    return _PersonnelChoice(
      id: json['id'].toString(),
      fullName: (json['full_name'] ?? 'Personel').toString(),
    );
  }
}

class _ApplicationWorkOrderDialog extends ConsumerStatefulWidget {
  const _ApplicationWorkOrderDialog({required this.recordCount});

  final int recordCount;

  @override
  ConsumerState<_ApplicationWorkOrderDialog> createState() =>
      _ApplicationWorkOrderDialogState();
}

class _ApplicationWorkOrderDialogState
    extends ConsumerState<_ApplicationWorkOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _descriptionController = TextEditingController();
  List<_WorkOrderTypeChoice> _types = const [];
  List<_PersonnelChoice> _personnel = const [];
  String? _selectedTypeId;
  String? _selectedAssignedTo;
  DateTime? _scheduledDate;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  Future<void> _loadData() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final isAdmin = ref.read(isAdminProvider);
    try {
      List<Map<String, dynamic>> typesRows;
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {'resource': 'definition_work_order_types'},
        );
        typesRows = ((response['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false);
      } else {
        if (client == null) {
          if (!mounted) return;
          setState(() => _loading = false);
          return;
        }
        final rows = await client
            .from('work_order_types')
            .select('id,name')
            .eq('is_active', true)
            .order('sort_order')
            .order('name')
            .limit(100);
        typesRows = (rows as List).cast<Map<String, dynamic>>();
      }

      List<_PersonnelChoice> personnel = const [];
      if (isAdmin) {
        if (apiClient != null) {
          final response = await apiClient.getJson(
            '/data',
            queryParameters: {'resource': 'personnel_users'},
          );
          final rows = ((response['items'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .where((row) => (row['role'] ?? '').toString() != 'admin')
              .toList(growable: false);
          personnel =
              rows.map(_PersonnelChoice.fromJson).toList(growable: false);
        } else {
          final userRows = await client!
              .from('users')
              .select('id,full_name,role')
              .order('full_name')
              .limit(200);
          personnel = (userRows as List)
              .map((row) => row as Map<String, dynamic>)
              .where((row) => (row['role'] ?? '').toString() != 'admin')
              .map(_PersonnelChoice.fromJson)
              .toList(growable: false);
        }
      }

      if (!mounted) return;
      final parsedTypes = typesRows
          .map(_WorkOrderTypeChoice.fromJson)
          .toList(growable: false);
      setState(() {
        _types = parsedTypes;
        _personnel = personnel;
        if (_types.length == 1) {
          _selectedTypeId = _types.first.id;
        }
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) => _ApplicationDatePickerDialog(
        initialDate: _scheduledDate ?? DateTime.now(),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() => _scheduledDate = picked);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final selectedType = _types.where((item) => item.id == _selectedTypeId).firstOrNull;
    final fallbackName = selectedType?.name.trim() ?? '';
    setState(() => _saving = true);
    Navigator.of(context).pop(
      _WorkOrderCreationConfig(
        workOrderTypeId: _selectedTypeId,
        workOrderTypeName: fallbackName.isEmpty ? 'İş Emri' : fallbackName,
        assignedTo: _selectedAssignedTo,
        scheduledDate: _scheduledDate,
        description: _descriptionController.text.trim(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
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
                        widget.recordCount == 1
                            ? 'İş Emri Oluştur'
                            : 'Toplu İş Emri Oluştur',
                        style: Theme.of(context).textTheme.titleMedium,
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
                Text(
                  widget.recordCount == 1
                      ? 'Seçili başvuru kaydından iş emri oluşturulacak.'
                      : '${widget.recordCount} başvuru için ayrı iş emri oluşturulacak.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
                const Gap(14),
                if (_loading)
                  const SizedBox(
                    height: 84,
                    child: Center(child: CircularProgressIndicator()),
                  )
                else ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _selectedTypeId,
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('İş emri tipi seç'),
                      ),
                      ..._types.map(
                        (item) => DropdownMenuItem<String?>(
                          value: item.id,
                          child: Text(item.name),
                        ),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _selectedTypeId = value),
                    validator: (value) {
                      if (_types.isNotEmpty && (value ?? '').isEmpty) {
                        return 'İş emri tipi seçin.';
                      }
                      return null;
                    },
                    decoration: const InputDecoration(
                      labelText: 'İş Emri Tipi',
                    ),
                  ),
                  const Gap(12),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Planlanan Tarih',
                        suffixIcon: Icon(Icons.calendar_today_rounded),
                      ),
                      child: Text(
                        _scheduledDate == null
                            ? 'Seçilmedi'
                            : DateFormat('dd.MM.yyyy', 'tr_TR')
                                  .format(_scheduledDate!),
                      ),
                    ),
                  ),
                  if (isAdmin) ...[
                    const Gap(12),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedAssignedTo,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Personel seç'),
                        ),
                        ..._personnel.map(
                          (item) => DropdownMenuItem<String?>(
                            value: item.id,
                            child: Text(item.fullName),
                          ),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedAssignedTo = value),
                      validator: (value) {
                        if ((value ?? '').isEmpty) {
                          return 'Personel seçin.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Atanan Personel',
                      ),
                    ),
                  ],
                  const Gap(12),
                  TextFormField(
                    controller: _descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Açıklama',
                      hintText:
                          'Boş bırakırsan başvuru bilgisinden otomatik açıklama üretilecek.',
                    ),
                  ),
                ],
                const Gap(16),
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
                      child: FilledButton.icon(
                        onPressed: _saving || _loading ? null : _submit,
                        icon: const Icon(Icons.playlist_add_rounded, size: 18),
                        label: Text(
                          widget.recordCount == 1 ? 'Oluştur' : 'Toplu Oluştur',
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
    this.selected = false,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: selected ? AppTheme.primarySoft : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: selected ? AppTheme.primary : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: selected ? AppTheme.primary : AppTheme.primary,
          ),
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

    if (onTap == null) return child;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: child,
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
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
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
    final style = (primary ? FilledButton.styleFrom : OutlinedButton.styleFrom)
        .call(
          minimumSize: const Size(34, 28),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
          textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w700,
            fontSize: 10,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        );

    final child = Tooltip(message: label, child: Icon(icon, size: 14));

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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                fontSize: 12,
                height: 1.12,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(10),
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
          width: 196,
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
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
                  fontSize: 14.5,
                  height: 1.15,
                ),
              ),
            ),
          ),
        ),
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 64),
            padding: const EdgeInsets.all(12),
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
      return Column(children: [left, const Gap(10), right]);
    }
    return Row(
      children: [
        Expanded(child: left),
        const Gap(12),
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
    this.readOnly = false,
    this.enabled = true,
  });

  final TextEditingController controller;
  final int? minLines;
  final int maxLines;
  final String? Function(String?)? validator;
  final bool readOnly;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: maxLines,
      validator: validator,
      readOnly: readOnly,
      enabled: enabled,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: const Color(0xFF111827),
        fontWeight: FontWeight.w600,
        fontSize: 14,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
        border: const OutlineInputBorder(),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
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
        fontSize: 14,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        border: const OutlineInputBorder(),
        hintText: hintText,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 15,
          vertical: 13,
        ),
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
          contentPadding: EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          suffixIcon: Icon(Icons.calendar_today_rounded, size: 16),
        ),
        child: Text(
          format.format(value),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: const Color(0xFF111827),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _BusinessActivityMultiSelectField extends StatelessWidget {
  const _BusinessActivityMultiSelectField({
    required this.items,
    required this.selectedIds,
    required this.onChanged,
  });

  final List<BusinessActivityTypeDefinition> items;
  final List<String> selectedIds;
  final ValueChanged<List<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final selectedItems = items
        .where((item) => selectedIds.contains(item.id))
        .map((item) => item.name)
        .toList(growable: false);
    final label = selectedItems.isEmpty
        ? 'Meslek türü seçin'
        : selectedItems.join(', ');

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final selected = await showDialog<List<String>>(
          context: context,
          builder: (context) => _BusinessActivityPickerDialog(
            items: items,
            selectedIds: selectedIds,
          ),
        );
        if (selected != null) {
          onChanged(selected);
        }
      },
      child: InputDecorator(
        decoration: const InputDecoration(
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          suffixIcon: Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Text(
          label,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: selectedItems.isEmpty
                ? AppTheme.textMuted
                : const Color(0xFF111827),
            fontWeight: FontWeight.w600,
            fontSize: 13.5,
          ),
        ),
      ),
    );
  }
}

class _BusinessActivityPickerDialog extends StatefulWidget {
  const _BusinessActivityPickerDialog({
    required this.items,
    required this.selectedIds,
  });

  final List<BusinessActivityTypeDefinition> items;
  final List<String> selectedIds;

  @override
  State<_BusinessActivityPickerDialog> createState() =>
      _BusinessActivityPickerDialogState();
}

class _BusinessActivityPickerDialogState
    extends State<_BusinessActivityPickerDialog> {
  late final Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.selectedIds.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Faaliyet Türleri',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(8),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return CheckboxListTile(
                      value: _selectedIds.contains(item.id),
                      controlAffinity: ListTileControlAffinity.leading,
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(item.name),
                      onChanged: (value) {
                        setState(() {
                          if (value ?? false) {
                            _selectedIds.add(item.id);
                          } else {
                            _selectedIds.remove(item.id);
                          }
                        });
                      },
                    );
                  },
                ),
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
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(_selectedIds.toList(growable: false)),
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
              fontSize: 13,
            ),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: Colors.white,
              border: const OutlineInputBorder(),
              hintText: 'Eski ya da yeni müşteri seçin',
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
              suffixIcon: IconButton(
                onPressed: onPickCustomer,
                icon: const Icon(Icons.search_rounded, size: 18),
              ),
            ),
          ),
        ),
        const Gap(8),
        OutlinedButton.icon(
          onPressed: onCreateCustomer,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 16),
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
    required this.directorName,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? vkn;
  final String? tcknMs;
  final String? city;
  final String? address;
  final String? directorName;
  final bool isActive;

  factory _CustomerOption.fromJson(Map<String, dynamic> json) {
    return _CustomerOption(
      id: json['id'].toString(),
      name: json['name']?.toString() ?? '',
      vkn: json['vkn']?.toString(),
      tcknMs: json['tckn_ms']?.toString(),
      city: json['city']?.toString(),
      address: json['address']?.toString(),
      directorName: json['director_name']?.toString(),
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
