import 'dart:convert';
import 'dart:async';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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
import '../customers/customer_model.dart';
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
      queryParameters: {
        'resource': 'form_application_list',
        'showPassive': 'true',
      },
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
        'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,customer_phone,customer_email,taxpayer_registration_document_name,taxpayer_registration_document_mime_type,taxpayer_registration_document_data,taxpayer_registration_document_storage_bucket,taxpayer_registration_document_storage_path,taxpayer_registration_document_url,approval_document_name,approval_document_mime_type,approval_document_storage_bucket,approval_document_storage_path,approval_document_url,approval_document_uploaded_at,approval_status,approved_at,approved_by,created_by,is_active,created_at',
      )
      .order('created_at', ascending: false)
      .limit(1200);

  return (rows as List)
      .map((row) => ApplicationFormRecord.fromJson(row as Map<String, dynamic>))
      .toList(growable: false);
});

final applicationFormLogsProvider =
    FutureProvider.family<List<ApplicationFormLogEntry>, String>((
      ref,
      formId,
    ) async {
      final apiClient = ref.watch(apiClientProvider);
      final client = ref.watch(supabaseClientProvider);
      if (apiClient != null) {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {
            'resource': 'application_form_logs',
            'formId': formId,
          },
        );
        return ((response['items'] as List?) ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ApplicationFormLogEntry.fromJson)
            .toList(growable: false);
      }
      if (client == null) return const [];
      final rows = await client
          .from('application_form_activity_logs')
          .select(
            'id,application_form_id,action,actor_id,actor_name,changes,created_at',
          )
          .eq('application_form_id', formId)
          .order('created_at', ascending: false)
          .limit(200);
      return (rows as List)
          .map(
            (row) => ApplicationFormLogEntry.fromJson(
              (row as Map).cast<String, dynamic>(),
            ),
          )
          .toList(growable: false);
    });

class ApplicationFormLogEntry {
  const ApplicationFormLogEntry({
    required this.id,
    required this.action,
    required this.actorName,
    required this.createdAt,
    required this.changes,
  });

  final String id;
  final String action;
  final String? actorName;
  final DateTime createdAt;
  final List<ApplicationFormLogChange> changes;

  factory ApplicationFormLogEntry.fromJson(Map<String, dynamic> json) {
    return ApplicationFormLogEntry(
      id: (json['id'] ?? '').toString(),
      action: (json['action'] ?? 'update').toString(),
      actorName: json['actor_name']?.toString(),
      createdAt:
          DateTime.tryParse((json['created_at'] ?? '').toString()) ??
          DateTime.now(),
      changes: ((json['changes'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                ApplicationFormLogChange.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }
}

class ApplicationFormLogChange {
  const ApplicationFormLogChange({
    required this.label,
    required this.oldValue,
    required this.newValue,
  });

  final String label;
  final String? oldValue;
  final String? newValue;

  factory ApplicationFormLogChange.fromJson(Map<String, dynamic> json) {
    return ApplicationFormLogChange(
      label: (json['label'] ?? json['field'] ?? 'Alan').toString(),
      oldValue: json['old']?.toString(),
      newValue: json['new']?.toString(),
    );
  }
}

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
  Timer? _autoRefreshTimer;
  bool _showPassive = false;
  bool _todayOnly = false;
  String _approvalFilter = 'pending';
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      _refreshApplicationsSoon();
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _customerFilterController.dispose();
    _registryFilterController.dispose();
    super.dispose();
  }

  void _refreshApplicationsSoon() {
    if (!mounted) return;
    if (ModalRoute.of(context)?.isCurrent != true) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (ModalRoute.of(context)?.isCurrent != true) return;
      ref.invalidate(applicationFormsProvider);
    });
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
    final profile = ref.read(currentUserProfileProvider).value;
    final isBankUser = profile?.isBankLike ?? false;
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => isBankUser
          ? const _BankApplicationFormDialog()
          : const _ApplicationFormDialog(),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;

    _refreshApplicationsSoon();
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
    if (record.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onaylanan başvuru düzenlenemez.')),
      );
      return;
    }
    final profile = ref.read(currentUserProfileProvider).value;
    final isBankUser = profile?.isBankLike ?? false;
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) => isBankUser
          ? _BankApplicationFormDialog(initialRecord: record)
          : _ApplicationFormDialog(initialRecord: record),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;
    _refreshApplicationsSoon();
  }

  Future<void> _downloadTaxpayerDocument(ApplicationFormRecord record) async {
    final data = (record.taxpayerRegistrationDocumentData ?? '').trim();
    final url = (record.taxpayerRegistrationDocumentUrl ?? '').trim();
    if (data.isEmpty && url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu başvuruda belge bulunmuyor.')),
      );
      return;
    }
    try {
      final bytes = url.isNotEmpty
          ? (await http.get(Uri.parse(url))).bodyBytes
          : base64Decode(data);
      final rawName =
          (record.taxpayerRegistrationDocumentName ?? '').trim().isEmpty
          ? 'yukumlu-kayit-belgesi.pdf'
          : record.taxpayerRegistrationDocumentName!.trim();
      await downloadBinaryFile(
        bytes,
        rawName,
        mimeType:
            record.taxpayerRegistrationDocumentMimeType ??
            'application/octet-stream',
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Belge açılamadı: $e')));
    }
  }

  Future<Uint8List> _buildApprovalDocumentPdfFromImage({
    required Uint8List imageBytes,
    required ApplicationFormRecord record,
  }) async {
    final doc = pw.Document(
      title: 'Onay Belgesi - ${record.customerName}',
      author: 'Microvise CRM',
      creator: 'Microvise CRM',
    );
    final image = pw.MemoryImage(imageBytes);
    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(18),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Text(
              'Onay Belgesi',
              style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              record.customerName,
              style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
            ),
            pw.SizedBox(height: 10),
            pw.Expanded(child: pw.Image(image, fit: pw.BoxFit.contain)),
          ],
        ),
      ),
    );
    return doc.save();
  }

  String _approvalDocumentFilename(ApplicationFormRecord record) {
    final customer = record.customerName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9ğüşöçıİĞÜŞÖÇ]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    final suffix = DateTime.now().toIso8601String().substring(0, 10);
    final name = customer.isEmpty ? 'onay-belgesi' : 'onay-belgesi-$customer';
    return '$name-$suffix.pdf';
  }

  Future<void> _uploadApprovalDocumentFromCamera(
    ApplicationFormRecord record,
  ) async {
    if (!record.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Onay belgesi yalnızca onaylı kayda yüklenir.'),
        ),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API bağlantısı yok.')));
      return;
    }

    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 88,
        maxWidth: 1800,
      );
      if (picked == null) return;
      final imageBytes = await picked.readAsBytes();
      if (imageBytes.isEmpty) return;

      final pdfBytes = await _buildApprovalDocumentPdfFromImage(
        imageBytes: imageBytes,
        record: record,
      );
      final filename = _approvalDocumentFilename(record);
      final uploaded = await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'uploadApplicationApprovalDocument',
          'applicationFormId': record.id,
          'filename': filename,
          'contentType': 'application/pdf',
          'data': base64Encode(pdfBytes),
        },
      );
      final nowIso = DateTime.now().toIso8601String();
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'application_forms',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': record.id},
          ],
          'values': {
            'approval_document_name': filename,
            'approval_document_mime_type': 'application/pdf',
            'approval_document_storage_bucket': uploaded['bucket'],
            'approval_document_storage_path': uploaded['path'],
            'approval_document_url': uploaded['url'],
            'approval_document_uploaded_at': nowIso,
          },
        },
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Onay belgesi yüklendi.')));
      await reloadCurrentPage();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Onay belgesi yüklenemedi: $e')));
    }
  }

  Future<void> _shareApprovalDocument(ApplicationFormRecord record) async {
    final url = (record.approvalDocumentUrl ?? '').trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu kayıtta onay belgesi yok.')),
      );
      return;
    }

    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Belge indirilemedi (${response.statusCode}).');
      }
      final filename = (record.approvalDocumentName ?? '').trim().isEmpty
          ? _approvalDocumentFilename(record)
          : record.approvalDocumentName!.trim();
      if (!mounted) return;
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [
          XFile.fromData(
            response.bodyBytes,
            mimeType: 'application/pdf',
            name: filename,
          ),
        ],
        text: '${record.customerName} onay belgesi',
        subject: '${record.customerName} onay belgesi',
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Belge paylaşılamadı: $e')));
    }
  }

  Future<void> _openRecordLogs(ApplicationFormRecord record) async {
    ref.invalidate(applicationFormLogsProvider(record.id));
    await showDialog<void>(
      context: context,
      builder: (context) => _ApplicationFormLogsDialog(record: record),
    );
  }

  Future<void> _openDuplicateDialog(ApplicationFormRecord record) async {
    final savedRecords = await showDialog<List<ApplicationFormRecord>>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _ApplicationFormDialog(initialRecord: record, duplicateMode: true),
    );
    if (savedRecords == null || savedRecords.isEmpty || !mounted) return;
    _refreshApplicationsSoon();
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
    final profile = ref.read(currentUserProfileProvider).value;
    final isBankUser = profile?.isBankLike ?? false;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yazdırma Seçenekleri'),
        content: Text(
          isBankUser
              ? 'Kayıt tamamlandı. KDV4 çıktısını hemen alabilirsin.'
              : 'Kayıt tamamlandı. İstersen KDV4 veya KDV4A çıktısını hemen alabilirsin.',
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
          if (!isBankUser)
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
    final settings = ref
        .read(applicationFormPrintSettingsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => ApplicationFormPrintSettings.defaults,
        );
    bool ok = false;
    Object? error;
    try {
      ok = await printApplicationForm(record, kind: kind, settings: settings);
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? '${kind.label} yazdırma hatası: $error'
              : ok
              ? '${kind.label} çıktısı hazırlandı.'
              : '${kind.label} çıktısı bu platformda açılamadı.',
        ),
      ),
    );
  }

  Future<void> _printBulk(
    List<ApplicationFormRecord> records, {
    required ApplicationPrintKind kind,
  }) async {
    final settings = ref
        .read(applicationFormPrintSettingsProvider)
        .maybeWhen(
          data: (value) => value,
          orElse: () => ApplicationFormPrintSettings.defaults,
        );
    bool ok = false;
    Object? error;
    try {
      ok = await printApplicationFormsBulk(
        records,
        kind: kind,
        settings: settings,
      );
    } catch (e) {
      error = e;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error != null
              ? '${kind.label} toplu yazdırma hatası: $error'
              : ok
              ? '${kind.label} toplu çıktısı hazırlandı.'
              : '${kind.label} toplu çıktısı bu platformda açılamadı.',
        ),
      ),
    );
  }

  Future<void> _setRecordActive(
    ApplicationFormRecord record,
    bool active,
  ) async {
    if (record.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onaylanan başvuru değiştirilemez.')),
      );
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      final nowIso = DateTime.now().toIso8601String();
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

        final registry = record.stockRegistryNumber?.trim() ?? '';
        final customerId = record.customerId?.trim() ?? '';
        if (registry.isNotEmpty) {
          if (!active) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'device_registries',
                'filters': [
                  {'col': 'registry_number', 'op': 'eq', 'value': registry},
                  {
                    'col': 'application_form_id',
                    'op': 'eq',
                    'value': record.id,
                  },
                ],
                'values': {
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                },
              },
            );
          } else if (customerId.isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'upsert',
                'table': 'device_registries',
                'values': {
                  'registry_number': registry,
                  'model': record.modelName,
                  'customer_id': customerId,
                  'application_form_id': record.id,
                  'is_active': true,
                  'assigned_at': nowIso,
                  'released_at': null,
                },
              },
            );
          }
        }
      } else {
        if (client == null) return;
        await client
            .from('application_forms')
            .update({'is_active': active})
            .eq('id', record.id);

        final registry = record.stockRegistryNumber?.trim() ?? '';
        final customerId = record.customerId?.trim() ?? '';
        if (registry.isNotEmpty) {
          if (!active) {
            await client
                .from('device_registries')
                .update({
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                })
                .eq('registry_number', registry)
                .eq('application_form_id', record.id);
          } else if (customerId.isNotEmpty) {
            await client.from('device_registries').upsert({
              'registry_number': registry,
              'model': record.modelName,
              'customer_id': customerId,
              'application_form_id': record.id,
              'is_active': true,
              'assigned_at': nowIso,
              'released_at': null,
            });
          }
        }
      }
      if (!mounted) return;
      _refreshApplicationsSoon();
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İşlem başarısız: $e')));
    }
  }

  Future<void> _setRecordsPassiveBulk(
    List<ApplicationFormRecord> records,
  ) async {
    final profile = ref.read(currentUserProfileProvider).value;
    if (profile?.role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu işlemi yalnızca admin yapabilir.')),
      );
      return;
    }
    final targets = records
        .where((record) => record.isActive && !record.isApproved)
        .toList(growable: false);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pasife alınacak uygun kayıt yok.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Seçili kayıtları pasife al'),
        content: Text(
          '${targets.length} başvuru pasife alınacak. Onaylanmış kayıtlar bu işleme dahil edilmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Pasife Al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      final nowIso = DateTime.now().toIso8601String();
      for (final record in targets) {
        final registry = record.stockRegistryNumber?.trim() ?? '';
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'application_forms',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': record.id},
              ],
              'values': {'is_active': false},
            },
          );
          if (registry.isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'device_registries',
                'filters': [
                  {'col': 'registry_number', 'op': 'eq', 'value': registry},
                  {
                    'col': 'application_form_id',
                    'op': 'eq',
                    'value': record.id,
                  },
                ],
                'values': {
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                },
              },
            );
          }
        } else {
          if (client == null) return;
          await client
              .from('application_forms')
              .update({'is_active': false})
              .eq('id', record.id);
          if (registry.isNotEmpty) {
            await client
                .from('device_registries')
                .update({
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                })
                .eq('registry_number', registry)
                .eq('application_form_id', record.id);
          }
        }
      }
      if (!mounted) return;
      setState(() => _selectedRecordIds.removeAll(targets.map((r) => r.id)));
      _refreshApplicationsSoon();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${targets.length} başvuru pasife alındı.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Toplu pasife alma başarısız: $e')),
      );
    }
  }

  Future<void> _deletePassiveRecordsBulk(
    List<ApplicationFormRecord> records,
  ) async {
    final profile = ref.read(currentUserProfileProvider).value;
    if (profile?.role != 'admin') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu işlemi yalnızca admin yapabilir.')),
      );
      return;
    }
    final targets = records
        .where((record) => !record.isActive && !record.isApproved)
        .toList(growable: false);
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silinecek pasif kayıt yok.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Pasif kayıtları kalıcı sil'),
        content: Text(
          '${targets.length} pasif başvuru kalıcı olarak silinecek. Bu işlem geri alınamaz.',
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
      final nowIso = DateTime.now().toIso8601String();
      for (final record in targets) {
        final registry = record.stockRegistryNumber?.trim() ?? '';
        if (apiClient != null) {
          if (registry.isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'device_registries',
                'filters': [
                  {'col': 'registry_number', 'op': 'eq', 'value': registry},
                  {
                    'col': 'application_form_id',
                    'op': 'eq',
                    'value': record.id,
                  },
                ],
                'values': {
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                },
              },
            );
          }
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'delete',
              'table': 'application_forms',
              'id': record.id,
            },
          );
        } else {
          if (client == null) return;
          if (registry.isNotEmpty) {
            await client
                .from('device_registries')
                .update({
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                })
                .eq('registry_number', registry)
                .eq('application_form_id', record.id);
          }
          await client.from('application_forms').delete().eq('id', record.id);
        }
      }
      if (!mounted) return;
      setState(() => _selectedRecordIds.removeAll(targets.map((r) => r.id)));
      _refreshApplicationsSoon();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${targets.length} pasif başvuru silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toplu silme başarısız: $e')));
    }
  }

  Future<void> _deleteRecordPermanently(ApplicationFormRecord record) async {
    if (record.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onaylanan başvuru silinemez.')),
      );
      return;
    }
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
      final nowIso = DateTime.now().toIso8601String();
      final registry = record.stockRegistryNumber?.trim() ?? '';
      if (apiClient != null) {
        if (registry.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'device_registries',
              'filters': [
                {'col': 'registry_number', 'op': 'eq', 'value': registry},
                {'col': 'application_form_id', 'op': 'eq', 'value': record.id},
              ],
              'values': {
                'customer_id': null,
                'application_form_id': null,
                'released_at': nowIso,
                'is_active': true,
              },
            },
          );
        }
        await apiClient.postJson(
          '/mutate',
          body: {'op': 'delete', 'table': 'application_forms', 'id': record.id},
        );
      } else {
        if (client == null) return;
        if (registry.isNotEmpty) {
          await client
              .from('device_registries')
              .update({
                'customer_id': null,
                'application_form_id': null,
                'released_at': nowIso,
                'is_active': true,
              })
              .eq('registry_number', registry)
              .eq('application_form_id', record.id);
        }
        await client.from('application_forms').delete().eq('id', record.id);
      }
      if (!mounted) return;
      _refreshApplicationsSoon();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Başvuru kalıcı olarak silindi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Silinemedi: $e')));
    }
  }

  Future<void> _approveRecord(ApplicationFormRecord record) async {
    if (record.isApproved) return;

    final registryController = TextEditingController(
      text: record.stockRegistryNumber?.trim() ?? '',
    );
    final registryNumber = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final current = registryController.text.trim();
          return AlertDialog(
            title: const Text('Başvuruyu onayla'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '"${record.customerName}" başvurusu onaylanmış başvurulara taşınacak.',
                ),
                const Gap(14),
                TextField(
                  controller: registryController,
                  textCapitalization: TextCapitalization.characters,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9-]')),
                  ],
                  onChanged: (_) => setDialogState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Cihaz sicil numarası',
                    hintText: 'Onaylanan sicil no',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: current.isEmpty
                    ? null
                    : () => Navigator.of(context).pop(current.toUpperCase()),
                child: const Text('Onayla'),
              ),
            ],
          );
        },
      ),
    );
    registryController.dispose();
    if (registryNumber == null) return;
    final approvedRegistry = registryNumber.trim().toUpperCase();
    if (approvedRegistry.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sicil numarası girmeden onaylanamaz.')),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final profile = await ref.read(currentUserProfileProvider.future);
    final approverId = (profile?.id ?? '').trim();
    final nowIso = DateTime.now().toIso8601String();

    try {
      final values = {
        'stock_registry_number': approvedRegistry,
        'approval_status': 'approved',
        'approved_at': nowIso,
        'approved_by': approverId.isEmpty ? null : approverId,
      };
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'application_forms',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': record.id},
            ],
            'values': values,
          },
        );
        if ((record.customerId ?? '').trim().isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'upsert',
              'table': 'device_registries',
              'values': {
                'registry_number': approvedRegistry,
                'model': record.modelName,
                'customer_id': record.customerId,
                'application_form_id': record.id,
                'is_active': true,
                'assigned_at': nowIso,
                'released_at': null,
              },
            },
          );
        }
      } else {
        if (client == null) return;
        await client
            .from('application_forms')
            .update(values)
            .eq('id', record.id);
        if ((record.customerId ?? '').trim().isNotEmpty) {
          await client.from('device_registries').upsert({
            'registry_number': approvedRegistry,
            'model': record.modelName,
            'customer_id': record.customerId,
            'application_form_id': record.id,
            'is_active': true,
            'assigned_at': nowIso,
            'released_at': null,
          });
        }
      }
      if (!mounted) return;
      await reloadCurrentPage();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Onaylanamadı: $e')));
    }
  }

  Future<void> _approveRecordsBulk(List<ApplicationFormRecord> records) async {
    final pendingRecords = records
        .where((record) => record.isPendingApproval)
        .toList(growable: false);
    if (pendingRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Seçili kayıtlarda onay bekleyen başvuru yok.'),
        ),
      );
      return;
    }

    final controllers = {
      for (final record in pendingRecords)
        record.id: TextEditingController(
          text: record.stockRegistryNumber?.trim() ?? '',
        ),
    };
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final allFilled = pendingRecords.every(
            (record) => controllers[record.id]!.text.trim().isNotEmpty,
          );
          return AlertDialog(
            title: const Text('Toplu Onayla'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final record in pendingRecords) ...[
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: Text(
                                record.customerName,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                            ),
                          ),
                          const Gap(12),
                          SizedBox(
                            width: 220,
                            child: TextField(
                              controller: controllers[record.id],
                              textCapitalization: TextCapitalization.characters,
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                  RegExp(r'[a-zA-Z0-9-]'),
                                ),
                              ],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'Sicil no',
                                hintText: 'Örn: PAX123456',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const Gap(10),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Vazgeç'),
              ),
              FilledButton(
                onPressed: allFilled
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: Text('Onayla (${pendingRecords.length})'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final profile = await ref.read(currentUserProfileProvider.future);
    final approverId = (profile?.id ?? '').trim();
    final nowIso = DateTime.now().toIso8601String();

    try {
      for (final record in pendingRecords) {
        final registry = controllers[record.id]!.text.trim().toUpperCase();
        final values = {
          'stock_registry_number': registry,
          'approval_status': 'approved',
          'approved_at': nowIso,
          'approved_by': approverId.isEmpty ? null : approverId,
        };
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'application_forms',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': record.id},
              ],
              'values': values,
            },
          );
          if ((record.customerId ?? '').trim().isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'upsert',
                'table': 'device_registries',
                'values': {
                  'registry_number': registry,
                  'model': record.modelName,
                  'customer_id': record.customerId,
                  'application_form_id': record.id,
                  'is_active': true,
                  'assigned_at': nowIso,
                  'released_at': null,
                },
              },
            );
          }
        } else {
          if (client == null) return;
          await client
              .from('application_forms')
              .update(values)
              .eq('id', record.id);
          if ((record.customerId ?? '').trim().isNotEmpty) {
            await client.from('device_registries').upsert({
              'registry_number': registry,
              'model': record.modelName,
              'customer_id': record.customerId,
              'application_form_id': record.id,
              'is_active': true,
              'assigned_at': nowIso,
              'released_at': null,
            });
          }
        }
      }
      if (!mounted) return;
      await reloadCurrentPage();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toplu onaylanamadı: $e')));
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _unapproveRecord(ApplicationFormRecord record) async {
    if (!record.isApproved) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Onayı geri al'),
        content: Text(
          '"${record.customerName}" başvurusu yeniden onay bekleyenlere alınacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Onayı Geri Al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final nowIso = DateTime.now().toIso8601String();
    final registry = record.stockRegistryNumber?.trim() ?? '';

    try {
      final values = {
        'approval_status': 'pending',
        'approved_at': null,
        'approved_by': null,
      };
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'application_forms',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': record.id},
            ],
            'values': values,
          },
        );
        if (registry.isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'device_registries',
              'filters': [
                {'col': 'registry_number', 'op': 'eq', 'value': registry},
                {'col': 'application_form_id', 'op': 'eq', 'value': record.id},
              ],
              'values': {
                'customer_id': null,
                'application_form_id': null,
                'released_at': nowIso,
                'is_active': true,
              },
            },
          );
        }
      } else {
        if (client == null) return;
        await client
            .from('application_forms')
            .update(values)
            .eq('id', record.id);
        if (registry.isNotEmpty) {
          await client
              .from('device_registries')
              .update({
                'customer_id': null,
                'application_form_id': null,
                'released_at': nowIso,
                'is_active': true,
              })
              .eq('registry_number', registry)
              .eq('application_form_id', record.id);
        }
      }
      if (!mounted) return;
      await reloadCurrentPage();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Onay geri alınamadı: $e')));
    }
  }

  Future<void> _unapproveRecordsBulk(
    List<ApplicationFormRecord> records,
  ) async {
    final approvedRecords = records
        .where((record) => record.isApproved)
        .toList(growable: false);
    if (approvedRecords.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Seçili kayıtlarda onaylı başvuru yok.')),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Toplu onayı geri al'),
        content: Text(
          '${approvedRecords.length} başvuru yeniden onay bekleyenlere alınacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Onayları Geri Al'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final nowIso = DateTime.now().toIso8601String();

    try {
      const values = {
        'approval_status': 'pending',
        'approved_at': null,
        'approved_by': null,
      };
      for (final record in approvedRecords) {
        final registry = record.stockRegistryNumber?.trim() ?? '';
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'application_forms',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': record.id},
              ],
              'values': values,
            },
          );
          if (registry.isNotEmpty) {
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'device_registries',
                'filters': [
                  {'col': 'registry_number', 'op': 'eq', 'value': registry},
                  {
                    'col': 'application_form_id',
                    'op': 'eq',
                    'value': record.id,
                  },
                ],
                'values': {
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                },
              },
            );
          }
        } else {
          if (client == null) return;
          await client
              .from('application_forms')
              .update(values)
              .eq('id', record.id);
          if (registry.isNotEmpty) {
            await client
                .from('device_registries')
                .update({
                  'customer_id': null,
                  'application_form_id': null,
                  'released_at': nowIso,
                  'is_active': true,
                })
                .eq('registry_number', registry)
                .eq('application_form_id', record.id);
          }
        }
      }
      if (!mounted) return;
      await reloadCurrentPage();
      return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Toplu onay geri alınamadı: $e')));
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

    final uniqueCustomerIds = linkedRecords
        .map((r) => (r.customerId ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final customerIdForRegistry = uniqueCustomerIds.length == 1
        ? uniqueCustomerIds.first
        : null;
    final distinctRegistries = linkedRecords
        .map((r) => (r.stockRegistryNumber ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toSet();
    final initialRegistryNumber = distinctRegistries.length == 1
        ? distinctRegistries.first
        : null;

    final config = await showDialog<_WorkOrderCreationConfig>(
      context: context,
      builder: (context) => _ApplicationWorkOrderDialog(
        recordCount: linkedRecords.length,
        customerIdForRegistry: customerIdForRegistry,
        initialRegistryNumber: initialRegistryNumber,
      ),
    );
    if (config == null) return;

    final profile = await ref.read(currentUserProfileProvider.future);
    final currentUserId = profile?.id;
    if (!mounted) return;
    if ((currentUserId ?? '').isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Oturum bulunamadı.')));
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
    final chosenRegistry = (config.registryNumber ?? '').trim();

    var createdCount = 0;
    var failedCount = 0;

    for (final record in linkedRecords) {
      final recordRegistry = (record.stockRegistryNumber ?? '').trim();
      final effectiveRegistry = chosenRegistry.isNotEmpty
          ? chosenRegistry
          : recordRegistry;
      final baseDescription = descriptionTemplate.isNotEmpty
          ? descriptionTemplate
          : _defaultWorkOrderDescription(record);
      final description = effectiveRegistry.isNotEmpty
          ? 'Sicil: $effectiveRegistry • $baseDescription'
          : baseDescription;
      final payload = <String, dynamic>{
        'customer_id': record.customerId,
        'branch_id': null,
        'work_order_type_id': config.workOrderTypeId,
        'title': config.workOrderTypeName,
        'description': description,
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
        'payment_required': config.paymentRequired,
        'status': config.status,
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(segments.join(' • '))));
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
          'payment_required': payload['payment_required'],
          'status': payload['status'],
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
      'payment_required',
      'status',
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

    try {
      await downloadExcelFile(
        bytes,
        'vergi_dairesine_gonder_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${records.length} kayit icin Excel disa aktarildi.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Excel dışa aktarılamadı: $e')));
    }
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
    try {
      await downloadExcelFile(
        bytes,
        'tsm_gonder_${DateTime.now().millisecondsSinceEpoch}.xlsx',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${records.length} kayit icin TSM Excel disa aktarildi.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('TSM Excel dışa aktarılamadı: $e')),
      );
    }
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
    final profile = ref.watch(currentUserProfileProvider).value;
    final isAdmin = profile?.role == 'admin';
    final isBankUser = profile?.isBankLike ?? false;
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive = ref.watch(
      hasActionAccessProvider(kActionArchiveRecords),
    );
    final canDeletePermanently = ref.watch(
      hasActionAccessProvider(kActionDeleteRecords),
    );
    final canApprove = !isBankUser && canEdit;
    final canUseInternalApplicationActions = !isBankUser;

    return AppPageLayout(
      title: isBankUser ? 'Capital Bank ÖKC Talep' : 'Başvuru Formları',
      subtitle: isBankUser
          ? 'ÖKC taleplerinizi oluşturun ve KDV4 çıktısını alın.'
          : 'Başvuru kayıtlarını filtreleyin, listeleyin ve yazdırın.',
      actions: [
        OutlinedButton.icon(
          onPressed: _refreshApplicationsSoon,
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
          final visibleRecords = bankVisibleApplicationRecords(
            records: records,
            profile: profile,
            isBankUser: isBankUser,
          );
          final activeFiltered =
              _filterRecords(visibleRecords, includeTodayOnly: false)
                  .where(
                    (item) => _showPassive ? !item.isActive : item.isActive,
                  )
                  .toList(growable: false);
          final baseFiltered = activeFiltered
              .where(
                (item) =>
                    _approvalFilter == 'all' ||
                    item.approvalStatus == _approvalFilter,
              )
              .toList(growable: false);
          final today = DateTime.now();
          final filtered = _todayOnly
              ? baseFiltered
                    .where((item) => _isSameDay(item.applicationDate, today))
                    .toList(growable: false)
              : baseFiltered;
          final selectedRecords = filtered
              .where((record) => _selectedRecordIds.contains(record.id))
              .toList(growable: false);
          final selectedActiveRecords = selectedRecords
              .where((record) => record.isActive && !record.isApproved)
              .toList(growable: false);
          final selectedPassiveRecords = selectedRecords
              .where((record) => !record.isActive && !record.isApproved)
              .toList(growable: false);
          final selectedApprovedRecords = selectedRecords
              .where((record) => record.isApproved)
              .toList(growable: false);
          final allFilteredSelected =
              filtered.isNotEmpty && selectedRecords.length == filtered.length;
          final canEditRecords = isBankUser ? true : canEdit;
          final todayCount = baseFiltered
              .where((item) => _isSameDay(item.applicationDate, today))
              .length;
          final pendingCount = activeFiltered
              .where((item) => item.isPendingApproval)
              .length;
          final approvedCount = activeFiltered
              .where((item) => item.isApproved)
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
                                onSelected: (value) => setState(() {
                                  _fromDate = value;
                                  _todayOnly = false;
                                }),
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
                                onSelected: (value) => setState(() {
                                  _toDate = value;
                                  _todayOnly = false;
                                }),
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
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 300,
                        child: TextField(
                          controller: _customerFilterController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.person_search_rounded),
                            hintText: 'Müşteri ara',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 250,
                        child: TextField(
                          controller: _registryFilterController,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.confirmation_num_rounded),
                            hintText: 'Cihaz / sicil no',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: _FilterDateField(
                          label: 'Başlangıç',
                          value: _fromDate,
                          format: _dateFormat,
                          onTap: () => _pickFilterDate(
                            currentValue: _fromDate,
                            onSelected: (value) => setState(() {
                              _fromDate = value;
                              _todayOnly = false;
                            }),
                          ),
                          onClear: _fromDate == null
                              ? null
                              : () => setState(() => _fromDate = null),
                        ),
                      ),
                      SizedBox(
                        width: 190,
                        child: _FilterDateField(
                          label: 'Bitiş',
                          value: _toDate,
                          format: _dateFormat,
                          onTap: () => _pickFilterDate(
                            currentValue: _toDate,
                            onSelected: (value) => setState(() {
                              _toDate = value;
                              _todayOnly = false;
                            }),
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
                      onTap: () => setState(() {
                        _todayOnly = !_todayOnly;
                        if (_todayOnly) {
                          _fromDate = null;
                          _toDate = null;
                        }
                      }),
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
                      FilterChip(
                        selected: _approvalFilter == 'pending',
                        onSelected: (_) =>
                            setState(() => _approvalFilter = 'pending'),
                        label: Text('Onay Bekleyen ($pendingCount)'),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilterChip(
                        selected: _approvalFilter == 'approved',
                        onSelected: (_) =>
                            setState(() => _approvalFilter = 'approved'),
                        label: Text('Onaylanmış ($approvedCount)'),
                        visualDensity: VisualDensity.compact,
                      ),
                      FilterChip(
                        selected: _approvalFilter == 'all',
                        onSelected: (_) =>
                            setState(() => _approvalFilter = 'all'),
                        label: const Text('Tümü'),
                        visualDensity: VisualDensity.compact,
                      ),
                      if (selectedRecords.isNotEmpty) ...[
                        if (canApprove &&
                            selectedRecords.any(
                              (record) => record.isPendingApproval,
                            ))
                          FilledButton.icon(
                            onPressed: () =>
                                _approveRecordsBulk(selectedRecords),
                            icon: const Icon(Icons.verified_rounded, size: 18),
                            label: Text(
                              'Toplu Onayla (${selectedRecords.where((record) => record.isPendingApproval).length})',
                            ),
                          ),
                        if (canApprove && selectedApprovedRecords.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _unapproveRecordsBulk(selectedRecords),
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: Text(
                              'Onayı Geri Al (${selectedApprovedRecords.length})',
                            ),
                          ),
                        if (isAdmin &&
                            canArchive &&
                            selectedActiveRecords.isNotEmpty)
                          OutlinedButton.icon(
                            onPressed: () =>
                                _setRecordsPassiveBulk(selectedRecords),
                            icon: const Icon(Icons.archive_rounded, size: 18),
                            label: Text(
                              'Pasife Al (${selectedActiveRecords.length})',
                            ),
                          ),
                        if (isAdmin &&
                            canDeletePermanently &&
                            selectedPassiveRecords.isNotEmpty)
                          FilledButton.icon(
                            onPressed: () =>
                                _deletePassiveRecordsBulk(selectedRecords),
                            icon: const Icon(
                              Icons.delete_forever_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'Pasifleri Sil (${selectedPassiveRecords.length})',
                            ),
                          ),
                        if (canUseInternalApplicationActions)
                          FilledButton.icon(
                            onPressed: () =>
                                _openCreateWorkOrdersDialog(selectedRecords),
                            icon: const Icon(
                              Icons.playlist_add_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'İş Emri Oluştur (${selectedRecords.length})',
                            ),
                          ),
                        OutlinedButton.icon(
                          onPressed: () => _printBulk(
                            selectedRecords,
                            kind: ApplicationPrintKind.kdv,
                          ),
                          icon: const Icon(Icons.print_rounded, size: 18),
                          label: Text(
                            'KDV4 Yazdır (${selectedRecords.length})',
                          ),
                        ),
                        if (canUseInternalApplicationActions) ...[
                          OutlinedButton.icon(
                            onPressed: () => _printBulk(
                              selectedRecords,
                              kind: ApplicationPrintKind.kdv4a,
                            ),
                            icon: const Icon(Icons.print_rounded, size: 18),
                            label: Text(
                              'KDV4A Yazdır (${selectedRecords.length})',
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
                            icon: const Icon(
                              Icons.table_chart_rounded,
                              size: 18,
                            ),
                            label: Text(
                              'TSM\'e Gönder (${selectedRecords.length})',
                            ),
                          ),
                        ],
                      ],
                    ] else ...[
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          await showModalBottomSheet<void>(
                            context: context,
                            showDragHandle: true,
                            isScrollControlled: true,
                            useSafeArea: true,
                            builder: (context) {
                              final bottomInset = MediaQuery.viewInsetsOf(
                                context,
                              ).bottom;
                              final bottomSafe = MediaQuery.viewPaddingOf(
                                context,
                              ).bottom;
                              final maxHeight =
                                  MediaQuery.sizeOf(context).height * 0.82;

                              return SafeArea(
                                top: false,
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: maxHeight,
                                  ),
                                  child: SingleChildScrollView(
                                    padding: EdgeInsets.fromLTRB(
                                      16,
                                      8,
                                      16,
                                      96 + bottomSafe + bottomInset,
                                    ),
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'İşlemler',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleMedium,
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
                                        ListTile(
                                          leading: Icon(
                                            _approvalFilter == 'pending'
                                                ? Icons.pending_actions_rounded
                                                : Icons
                                                      .pending_actions_outlined,
                                          ),
                                          title: Text(
                                            'Onay Bekleyen ($pendingCount)',
                                          ),
                                          selected:
                                              _approvalFilter == 'pending',
                                          onTap: () {
                                            setState(
                                              () => _approvalFilter = 'pending',
                                            );
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        ListTile(
                                          leading: Icon(
                                            _approvalFilter == 'approved'
                                                ? Icons.verified_rounded
                                                : Icons.verified_outlined,
                                          ),
                                          title: Text(
                                            'Onaylanmış ($approvedCount)',
                                          ),
                                          selected:
                                              _approvalFilter == 'approved',
                                          onTap: () {
                                            setState(
                                              () =>
                                                  _approvalFilter = 'approved',
                                            );
                                            Navigator.of(context).pop();
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(
                                            Icons.list_alt_rounded,
                                          ),
                                          title: const Text('Tüm Başvurular'),
                                          selected: _approvalFilter == 'all',
                                          onTap: () {
                                            setState(
                                              () => _approvalFilter = 'all',
                                            );
                                            Navigator.of(context).pop();
                                          },
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
                                                  for (final record
                                                      in filtered) {
                                                    _selectedRecordIds.remove(
                                                      record.id,
                                                    );
                                                  }
                                                } else {
                                                  for (final record
                                                      in filtered) {
                                                    _selectedRecordIds.add(
                                                      record.id,
                                                    );
                                                  }
                                                }
                                              });
                                              Navigator.of(context).pop();
                                            },
                                          ),
                                        ],
                                        if (selectedRecords.isNotEmpty) ...[
                                          if (canApprove &&
                                              selectedRecords.any(
                                                (record) =>
                                                    record.isPendingApproval,
                                              ))
                                            ListTile(
                                              leading: const Icon(
                                                Icons.verified_rounded,
                                              ),
                                              title: Text(
                                                'Toplu Onayla (${selectedRecords.where((record) => record.isPendingApproval).length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _approveRecordsBulk(
                                                  selectedRecords,
                                                );
                                              },
                                            ),
                                          if (canApprove &&
                                              selectedApprovedRecords
                                                  .isNotEmpty)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.undo_rounded,
                                              ),
                                              title: Text(
                                                'Onayı Geri Al (${selectedApprovedRecords.length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _unapproveRecordsBulk(
                                                  selectedRecords,
                                                );
                                              },
                                            ),
                                          if (isAdmin &&
                                              canArchive &&
                                              selectedActiveRecords.isNotEmpty)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.archive_rounded,
                                              ),
                                              title: Text(
                                                'Pasife Al (${selectedActiveRecords.length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _setRecordsPassiveBulk(
                                                  selectedRecords,
                                                );
                                              },
                                            ),
                                          if (isAdmin &&
                                              canDeletePermanently &&
                                              selectedPassiveRecords.isNotEmpty)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.delete_forever_rounded,
                                              ),
                                              title: Text(
                                                'Pasifleri Kalıcı Sil (${selectedPassiveRecords.length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _deletePassiveRecordsBulk(
                                                  selectedRecords,
                                                );
                                              },
                                            ),
                                          if (canUseInternalApplicationActions)
                                            ListTile(
                                              leading: const Icon(
                                                Icons.playlist_add_rounded,
                                              ),
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
                                              Icons.print_rounded,
                                            ),
                                            title: Text(
                                              'KDV4 Yazdır (${selectedRecords.length})',
                                            ),
                                            onTap: () {
                                              Navigator.of(context).pop();
                                              _printBulk(
                                                selectedRecords,
                                                kind: ApplicationPrintKind.kdv,
                                              );
                                            },
                                          ),
                                          if (canUseInternalApplicationActions) ...[
                                            ListTile(
                                              leading: const Icon(
                                                Icons.print_rounded,
                                              ),
                                              title: Text(
                                                'KDV4A Yazdır (${selectedRecords.length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _printBulk(
                                                  selectedRecords,
                                                  kind: ApplicationPrintKind
                                                      .kdv4a,
                                                );
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(
                                                Icons.download_rounded,
                                              ),
                                              title: Text(
                                                'Vergi Dairesine Gönder (${selectedRecords.length})',
                                              ),
                                              onTap: () {
                                                Navigator.of(context).pop();
                                                _exportForTaxOffice(
                                                  selectedRecords,
                                                );
                                              },
                                            ),
                                            ListTile(
                                              leading: const Icon(
                                                Icons.table_chart_rounded,
                                              ),
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
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
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
                  colorIndex: index - 2,
                  canEdit: canEditRecords,
                  canApprove: canApprove,
                  canArchive: canArchive,
                  canDeletePermanently: canDeletePermanently,
                  canPrintKdv4a: canUseInternalApplicationActions,
                  canCreateWorkOrder: canUseInternalApplicationActions,
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
                  onViewDocument: () => _downloadTaxpayerDocument(r),
                  onUploadApprovalDocument: () =>
                      _uploadApprovalDocumentFromCamera(r),
                  onShareApprovalDocument: () => _shareApprovalDocument(r),
                  onViewLogs: () => _openRecordLogs(r),
                  onPrintKdv4a: () =>
                      _print(r, kind: ApplicationPrintKind.kdv4a),
                  onCreateWorkOrder: () => _openCreateWorkOrdersDialog([r]),
                  onApprove: () => _approveRecord(r),
                  onUnapprove: () => _unapproveRecord(r),
                  onEdit: () => _openEditDialog(r),
                  onDuplicate: () => _openDuplicateDialog(r),
                  onToggleActive: () => _setRecordActive(r, !r.isActive),
                  onDeletePermanently: () => _deleteRecordPermanently(r),
                );
              },
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 96),
            itemCount: filtered.isEmpty ? 3 : filtered.length + 2,
            separatorBuilder: (context, index) => const Gap(8),
            itemBuilder: (context, index) {
              if (index == 0) return filterCard;
              if (index == 1) return statsCard;

              if (filtered.isEmpty) {
                return const AppCard(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text('Filtreye uygun başvuru bulunamadı.'),
                    ),
                  ),
                );
              }

              final recordIndex = index - 2;
              final r = filtered[recordIndex];
              return _ApplicationRecordCard(
                record: r,
                colorIndex: recordIndex,
                canEdit: canEditRecords,
                canApprove: canApprove,
                canArchive: canArchive,
                canDeletePermanently: canDeletePermanently,
                canPrintKdv4a: canUseInternalApplicationActions,
                canCreateWorkOrder: canUseInternalApplicationActions,
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
                onViewDocument: () => _downloadTaxpayerDocument(r),
                onUploadApprovalDocument: () =>
                    _uploadApprovalDocumentFromCamera(r),
                onShareApprovalDocument: () => _shareApprovalDocument(r),
                onViewLogs: () => _openRecordLogs(r),
                onPrintKdv4a: () => _print(r, kind: ApplicationPrintKind.kdv4a),
                onCreateWorkOrder: () => _openCreateWorkOrdersDialog([r]),
                onApprove: () => _approveRecord(r),
                onUnapprove: () => _unapproveRecord(r),
                onEdit: () => _openEditDialog(r),
                onDuplicate: () => _openDuplicateDialog(r),
                onToggleActive: () => _setRecordActive(r, !r.isActive),
                onDeletePermanently: () => _deleteRecordPermanently(r),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) =>
            const Center(child: Text('Başvuru kayıtları yüklenemedi.')),
      ),
    );
  }

  List<ApplicationFormRecord> _filterRecords(
    List<ApplicationFormRecord> input, {
    bool includeTodayOnly = true,
  }) {
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

String _logActionLabel(String action) {
  return switch (action) {
    'create' => 'Oluşturuldu',
    'approve' => 'Onaylandı',
    'delete' => 'Silindi',
    'status' => 'Durum',
    _ => 'Güncellendi',
  };
}

AppBadgeTone _logActionTone(String action) {
  return switch (action) {
    'create' => AppBadgeTone.primary,
    'approve' => AppBadgeTone.success,
    'delete' => AppBadgeTone.error,
    'status' => AppBadgeTone.warning,
    _ => AppBadgeTone.neutral,
  };
}

String _logValue(String? value) {
  final text = (value ?? '').trim();
  if (text.isEmpty) return '-';
  if (text.length <= 80) return text;
  return '${text.substring(0, 80)}...';
}

List<ApplicationFormRecord> bankVisibleApplicationRecords({
  required List<ApplicationFormRecord> records,
  required UserProfile? profile,
  required bool isBankUser,
}) {
  if (!isBankUser) return records;
  if (profile?.isBankAdminLike ?? false) {
    return records
        .where((record) => (record.createdBy ?? '').trim().isNotEmpty)
        .toList(growable: false);
  }
  final userId = (profile?.id ?? '').trim();
  if (userId.isEmpty) return const [];

  return records
      .where((record) => (record.createdBy ?? '').trim() == userId)
      .toList(growable: false);
}

List<BusinessActivityTypeDefinition> bankBusinessActivitiesFromRecords(
  List<ApplicationFormRecord> records,
) {
  final byKey = <String, BusinessActivityTypeDefinition>{};
  for (final record in records) {
    final name = (record.businessActivityName ?? '').trim();
    if (name.isEmpty) continue;
    final key = _sortKey(name);
    if (key.isEmpty || byKey.containsKey(key)) continue;
    byKey[key] = BusinessActivityTypeDefinition(
      id: 'record-$key',
      name: name,
      isActive: true,
    );
  }
  final result = byKey.values.toList(growable: false);
  result.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return result;
}

List<BusinessActivityTypeDefinition> _mergeBusinessActivities(
  List<List<BusinessActivityTypeDefinition>> groups,
) {
  final byKey = <String, BusinessActivityTypeDefinition>{};
  for (final group in groups) {
    for (final item in group) {
      if (!item.isActive) continue;
      final key = _sortKey(item.name);
      if (key.isEmpty || byKey.containsKey(key)) continue;
      byKey[key] = item;
    }
  }
  final result = byKey.values.toList(growable: false);
  result.sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
  return result;
}

String _formatPhoneForDisplay(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.isEmpty) return '';
  final normalized = digits.length == 12 && digits.startsWith('90')
      ? '0${digits.substring(2)}'
      : digits.length > 11
      ? digits.substring(digits.length - 11)
      : digits;
  final parts = <String>[];
  var index = 0;
  for (final size in const [4, 3, 2, 2]) {
    if (index >= normalized.length) break;
    final end = index + size > normalized.length
        ? normalized.length
        : index + size;
    parts.add(normalized.substring(index, end));
    index = end;
  }
  return parts.join(' ');
}

class _PhoneTextInputFormatter extends TextInputFormatter {
  const _PhoneTextInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final formatted = _formatPhoneForDisplay(newValue.text);
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _BankApplicationFormDialog extends ConsumerStatefulWidget {
  const _BankApplicationFormDialog({this.initialRecord});

  final ApplicationFormRecord? initialRecord;

  @override
  ConsumerState<_BankApplicationFormDialog> createState() =>
      _BankApplicationFormDialogState();
}

const _bankFallbackTaxOfficeCities = <CityDefinition>[
  CityDefinition(
    id: 'fallback-lefkosa',
    name: 'Lefkoşa',
    code: null,
    isActive: true,
  ),
  CityDefinition(
    id: 'fallback-gazimagusa',
    name: 'Gazimağusa',
    code: null,
    isActive: true,
  ),
  CityDefinition(
    id: 'fallback-girne',
    name: 'Girne',
    code: null,
    isActive: true,
  ),
  CityDefinition(
    id: 'fallback-guzelyurt',
    name: 'Güzelyurt',
    code: null,
    isActive: true,
  ),
  CityDefinition(
    id: 'fallback-iskele',
    name: 'İskele',
    code: null,
    isActive: true,
  ),
  CityDefinition(
    id: 'fallback-lefke',
    name: 'Lefke',
    code: null,
    isActive: true,
  ),
];

const _bankFallbackBusinessActivities = <BusinessActivityTypeDefinition>[
  BusinessActivityTypeDefinition(
    id: 'fallback-market',
    name: 'Market',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-restoran',
    name: 'Restoran',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-eczane',
    name: 'Eczane',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-kafe',
    name: 'Kafe',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-kuafor',
    name: 'Kuaför',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-tekstil',
    name: 'Tekstil',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-oto',
    name: 'Oto / Servis',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-turizm',
    name: 'Turizm',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-tirnak',
    name: 'Tırnak Bakım ve Onarım',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-gida',
    name: 'Gıda',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-perakende',
    name: 'Perakende Satış',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-toptan',
    name: 'Toptan Satış',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-bakkal',
    name: 'Bakkal',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-kasap',
    name: 'Kasap',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-pastane',
    name: 'Pastane',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-firin',
    name: 'Fırın',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-bufe',
    name: 'Büfe',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-otel',
    name: 'Otel',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-giyim',
    name: 'Giyim',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-ayakkabi',
    name: 'Ayakkabı',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-elektronik',
    name: 'Elektronik',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-mobilya',
    name: 'Mobilya',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-insaat',
    name: 'İnşaat Malzemeleri',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-kirtasiye',
    name: 'Kırtasiye',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-kozmetik',
    name: 'Kozmetik',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-berber',
    name: 'Berber',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-guzellik',
    name: 'Güzellik Salonu',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-oto-yedek',
    name: 'Oto Yedek Parça',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-akaryakit',
    name: 'Akaryakıt',
    isActive: true,
  ),
  BusinessActivityTypeDefinition(
    id: 'fallback-hirdavat',
    name: 'Hırdavat',
    isActive: true,
  ),
];

class _BankApplicationFormDialogState
    extends ConsumerState<_BankApplicationFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _dateFormat = DateFormat('dd.MM.yyyy', 'tr_TR');
  final _vknController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _directorController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();
  final _businessActivityController = TextEditingController();
  final _businessActivityFocusNode = FocusNode();
  DateTime _applicationDate = DateTime.now();
  String? _selectedTaxOfficeCityId;
  String? _selectedBusinessActivityId;
  String? _documentName;
  String? _documentMimeType;
  String? _documentBase64;
  Uint8List? _documentBytes;
  String? _documentStorageBucket;
  String? _documentStoragePath;
  String? _documentUrl;
  _CustomerOption? _customer;
  bool _lookupDone = false;
  bool _lookupBusy = false;
  bool _saving = false;

  bool get _isEditing => widget.initialRecord != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecord;
    if (initial == null) return;
    _applicationDate = initial.applicationDate;
    _vknController.text = (initial.customerTcknMs ?? '').trim();
    _customerNameController.text = initial.customerName.trim();
    _addressController.text = (initial.workAddress ?? '').trim();
    _directorController.text = (initial.director ?? '').trim();
    _phoneController.text = _formatPhoneForDisplay(
      (initial.customerPhone ?? '').trim(),
    );
    _emailController.text = (initial.customerEmail ?? '').trim();
    _businessActivityController.text = (initial.businessActivityName ?? '')
        .trim();
    _documentName = initial.taxpayerRegistrationDocumentName;
    _documentMimeType = initial.taxpayerRegistrationDocumentMimeType;
    _documentBase64 = initial.taxpayerRegistrationDocumentData;
    _documentStorageBucket = initial.taxpayerRegistrationDocumentStorageBucket;
    _documentStoragePath = initial.taxpayerRegistrationDocumentStoragePath;
    _documentUrl = initial.taxpayerRegistrationDocumentUrl;
    _lookupDone = true;
    _customer = _CustomerOption(
      id: (initial.customerId ?? '').trim(),
      name: initial.customerName.trim(),
      vkn: initial.customerTcknMs,
      tcknMs: initial.customerTcknMs,
      email: initial.customerEmail,
      phone: initial.customerPhone,
      city: initial.taxOfficeCityName,
      address: initial.workAddress,
      directorName: initial.director,
      isActive: initial.isActive,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final city = _currentTaxOfficeCities()
          .where(
            (item) =>
                _sortKey(item.name) ==
                _sortKey(initial.taxOfficeCityName ?? ''),
          )
          .firstOrNull;
      if (city != null) {
        setState(() => _selectedTaxOfficeCityId = city.id);
      }
    });
  }

  @override
  void dispose() {
    _vknController.dispose();
    _customerNameController.dispose();
    _addressController.dispose();
    _directorController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _businessActivityController.dispose();
    _businessActivityFocusNode.dispose();
    super.dispose();
  }

  String get _normalizedVkn =>
      _vknController.text.replaceAll(RegExp(r'\D'), '');

  List<CityDefinition> _taxOfficeCitiesFromAsync(
    AsyncValue<List<CityDefinition>> citiesAsync,
  ) {
    final remote =
        citiesAsync.asData?.value
            .where((item) => item.isActive)
            .toList(growable: false) ??
        const <CityDefinition>[];
    return remote.isNotEmpty ? remote : _bankFallbackTaxOfficeCities;
  }

  List<CityDefinition> _currentTaxOfficeCities() {
    final remote =
        ref
            .read(cityDefinitionsProvider)
            .asData
            ?.value
            .where((item) => item.isActive)
            .toList(growable: false) ??
        const <CityDefinition>[];
    return remote.isNotEmpty ? remote : _bankFallbackTaxOfficeCities;
  }

  CityDefinition? _selectedTaxOfficeCity() {
    return _currentTaxOfficeCities()
        .where((item) => item.id == _selectedTaxOfficeCityId)
        .firstOrNull;
  }

  String? _persistableTaxOfficeCityId(CityDefinition? city) {
    final id = city?.id.trim() ?? '';
    if (id.isEmpty || id.startsWith('fallback-')) return null;
    return id;
  }

  List<BusinessActivityTypeDefinition> _currentBusinessActivities() {
    final remote =
        ref
            .read(businessActivityTypesProvider)
            .asData
            ?.value
            .where((item) => item.isActive)
            .toList(growable: false) ??
        const <BusinessActivityTypeDefinition>[];
    return remote.isNotEmpty ? remote : _bankFallbackBusinessActivities;
  }

  Future<BusinessActivityTypeDefinition?> _ensureBusinessActivity() async {
    final name = _businessActivityController.text.trim();
    if (name.isEmpty) return null;

    final selected = _currentBusinessActivities()
        .where((item) => item.id == _selectedBusinessActivityId)
        .firstOrNull;
    if (selected != null &&
        _sortKey(selected.name) == _sortKey(name) &&
        !selected.id.startsWith('fallback-')) {
      return selected;
    }

    final existing = _currentBusinessActivities()
        .where((item) => _sortKey(item.name) == _sortKey(name))
        .firstOrNull;
    if (existing != null && !existing.id.startsWith('fallback-')) {
      return existing;
    }

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    try {
      if (apiClient != null) {
        final response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'business_activity_types',
            'returning': 'row',
            'values': {'name': name, 'is_active': true},
          },
        );
        final row = (response['row'] as Map?)?.cast<String, dynamic>();
        if (row != null && row.isNotEmpty) {
          ref.invalidate(businessActivityTypesProvider);
          return BusinessActivityTypeDefinition.fromJson(row);
        }
      } else if (client != null) {
        final row = await client
            .from('business_activity_types')
            .upsert({'name': name, 'is_active': true})
            .select('id,name,is_active')
            .single();
        ref.invalidate(businessActivityTypesProvider);
        return BusinessActivityTypeDefinition.fromJson(row);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> _pickDate() async {
    final picked = await showDialog<DateTime>(
      context: context,
      builder: (context) =>
          _ApplicationDatePickerDialog(initialDate: _applicationDate),
    );
    if (picked == null) return;
    setState(() => _applicationDate = picked);
  }

  Future<void> _lookupCustomer() async {
    final vkn = _normalizedVkn;
    if (vkn.length < 10) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('VKN en az 10 haneli olmalı.')),
      );
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() {
      _lookupBusy = true;
      _lookupDone = false;
      _customer = null;
      _customerNameController.clear();
      _addressController.clear();
      _directorController.clear();
      _phoneController.clear();
      _emailController.clear();
      _selectedTaxOfficeCityId = null;
      _businessActivityController.clear();
      _selectedBusinessActivityId = null;
    });

    try {
      Map<String, dynamic>? row;
      if (apiClient != null) {
        try {
          final response = await apiClient.getJson(
            '/data',
            queryParameters: {'resource': 'form_customer_by_vkn', 'vkn': vkn},
          );
          row = (response['item'] as Map?)?.cast<String, dynamic>();
        } catch (e) {
          if (!e.toString().contains('form_customer_by_vkn') &&
              !e.toString().contains('Bilinmeyen resource')) {
            rethrow;
          }
          final response = await apiClient.getJson(
            '/data',
            queryParameters: {'resource': 'form_application_customers'},
          );
          final rows = ((response['items'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>();
          row = rows
              .where(
                (item) =>
                    (item['vkn']?.toString() ?? '').replaceAll(
                      RegExp(r'\D'),
                      '',
                    ) ==
                    vkn,
              )
              .firstOrNull;
        }
      } else {
        final rows = await client!
            .from('customers')
            .select(
              'id,name,vkn,tckn_ms,email,phone_1,city,address,director_name,is_active',
            )
            .eq('vkn', vkn)
            .limit(1);
        row = (rows as List).whereType<Map<String, dynamic>>().firstOrNull;
      }

      final found = row == null ? null : _CustomerOption.fromJson(row);
      if (!mounted) return;
      setState(() {
        _customer = found;
        _lookupDone = true;
        if (found != null) {
          _customerNameController.text = found.name;
          _addressController.text = (found.address ?? '').trim();
          _directorController.text = (found.directorName ?? '').trim();
          _phoneController.text = (found.phone ?? '').trim();
          _emailController.text = (found.email ?? '').trim();
          final city = _currentTaxOfficeCities()
              .where(
                (item) => _sortKey(item.name) == _sortKey(found.city ?? ''),
              )
              .firstOrNull;
          _selectedTaxOfficeCityId = city?.id;
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('VKN sorgulanamadı: $e')));
    } finally {
      if (mounted) setState(() => _lookupBusy = false);
    }
  }

  Future<void> _pickTaxpayerDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      if (bytes.length > 6 * 1024 * 1024) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Belge en fazla 6 MB olabilir.')),
        );
        return;
      }
      final ext = file.extension?.toLowerCase() ?? '';
      setState(() {
        _documentName = file.name;
        _documentMimeType = switch (ext) {
          'pdf' => 'application/pdf',
          'jpg' || 'jpeg' => 'image/jpeg',
          'png' => 'image/png',
          _ => 'application/octet-stream',
        };
        _documentBytes = Uint8List.fromList(bytes);
        _documentBase64 = null;
        _documentStorageBucket = null;
        _documentStoragePath = null;
        _documentUrl = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Belge seçilemedi: $e')));
    }
  }

  DeviceModel? _resolvePaxModel(List<DeviceModel> models) {
    final active = models.where((item) => item.isActive);
    return active
            .where(
              (item) =>
                  _sortKey(item.brandName ?? '').contains('pax') &&
                  _sortKey(item.name).contains('a910sf'),
            )
            .firstOrNull ??
        active
            .where((item) => _sortKey(item.name).contains('a910sf'))
            .firstOrNull ??
        active
            .where(
              (item) =>
                  _sortKey(item.brandName ?? '').contains('pax') ||
                  _sortKey(item.name).contains('pax'),
            )
            .firstOrNull;
  }

  FiscalSymbolDefinition? _resolvePaxFiscal(
    List<FiscalSymbolDefinition> fiscalSymbols,
  ) {
    return fiscalSymbols
        .where(
          (item) =>
              item.isActive &&
              (_sortKey(item.code ?? '') == _sortKey('MF 2D') ||
                  _sortKey(item.code ?? '') == _sortKey('MF-2D') ||
                  _sortKey(item.name) == _sortKey('MF 2D') ||
                  _sortKey(item.name) == _sortKey('MF-2D')),
        )
        .firstOrNull;
  }

  Future<_CustomerOption> _ensureCustomer() async {
    if (_customer != null && _customer!.id.trim().isNotEmpty) {
      return _customer!;
    }

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    final city = _selectedTaxOfficeCity();
    final formattedPhone = _formatPhoneForDisplay(_phoneController.text);
    final values = {
      'name': _customerNameController.text.trim(),
      'vkn': _normalizedVkn,
      'address': _addressController.text.trim(),
      'director_name': _directorController.text.trim(),
      'city': city?.name,
      'email': _emailController.text.trim(),
      'phone_1': formattedPhone,
      'is_active': true,
    };

    Map<String, dynamic>? row;
    try {
      if (apiClient != null) {
        final response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'customers',
            'returning': 'row',
            'values': values,
          },
        );
        row = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
      } else {
        row = await client!
            .from('customers')
            .insert(values)
            .select(
              'id,name,vkn,tckn_ms,email,phone_1,city,address,director_name,is_active',
            )
            .single();
      }
    } catch (_) {
      if (client != null) {
        try {
          row = await client
              .from('customers')
              .insert(values)
              .select(
                'id,name,vkn,tckn_ms,email,phone_1,city,address,director_name,is_active',
              )
              .single();
        } catch (_) {}
      }
    }
    return _CustomerOption.fromJson(
      row ??
          {
            'id': '',
            'name': _customerNameController.text.trim(),
            'vkn': _normalizedVkn,
            'email': _emailController.text.trim(),
            'phone_1': formattedPhone,
            'city': city?.name,
            'address': _addressController.text.trim(),
            'director_name': _directorController.text.trim(),
            'is_active': true,
          },
    );
  }

  Future<void> _save() async {
    if (!_lookupDone) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Önce VKN sorgulayın.')));
      return;
    }
    if ((_documentBase64 ?? '').isEmpty &&
        (_documentUrl ?? '').isEmpty &&
        _documentBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yükümlü kayıt belgesini yükleyin.')),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final customer = await _ensureCustomer();
      final profile = await ref.read(currentUserProfileProvider.future);
      final models = ref.read(deviceModelsProvider).asData?.value ?? const [];
      final fiscalSymbols =
          ref.read(fiscalSymbolsProvider).asData?.value ?? const [];
      final taxOfficeCity = _selectedTaxOfficeCity();
      final businessActivity = await _ensureBusinessActivity();
      final businessActivityName = _businessActivityController.text.trim();
      final paxModel = _resolvePaxModel(models);
      final fiscal = _resolvePaxFiscal(fiscalSymbols);
      final createdBy = _isEditing
          ? (widget.initialRecord?.createdBy ?? '').trim()
          : (profile?.id ?? '').trim();
      final formattedPhone = _formatPhoneForDisplay(_phoneController.text);
      final formId = _isEditing
          ? widget.initialRecord!.id
          : DateTime.now().microsecondsSinceEpoch.toString();
      String? documentData = _documentBase64;
      String? documentBucket = _documentStorageBucket;
      String? documentPath = _documentStoragePath;
      String? documentUrl = _documentUrl;
      if (apiClient != null && _documentBytes != null) {
        final uploaded = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'uploadTaxpayerRegistrationDocument',
            'applicationFormId': formId,
            'filename': _documentName ?? 'yukumlu-kayit-belgesi',
            'contentType': _documentMimeType ?? 'application/octet-stream',
            'data': base64Encode(_documentBytes!),
          },
        );
        documentData = null;
        documentBucket = uploaded['bucket']?.toString();
        documentPath = uploaded['path']?.toString();
        documentUrl = uploaded['url']?.toString();
      } else if (_documentBytes != null) {
        documentData = base64Encode(_documentBytes!);
      }

      final payload = {
        if (_isEditing) 'id': widget.initialRecord!.id,
        'application_date': DateFormat('yyyy-MM-dd').format(_applicationDate),
        'customer_id': customer.id.trim().isEmpty ? null : customer.id,
        'customer_name': _customerNameController.text.trim(),
        'customer_tckn_ms': _normalizedVkn,
        'work_address': _addressController.text.trim(),
        'tax_office_city_id': _persistableTaxOfficeCityId(taxOfficeCity),
        'tax_office_city_name': taxOfficeCity?.name,
        'document_type': 'VKN',
        'file_registry_number': _normalizedVkn,
        'director': _directorController.text.trim(),
        'brand_id': paxModel?.brandId,
        'brand_name': 'PAX',
        'model_id': paxModel?.id,
        'model_name': paxModel?.name ?? 'A910SF',
        'fiscal_symbol_id': fiscal?.id,
        'fiscal_symbol_name': fiscal?.code?.trim().isNotEmpty ?? false
            ? fiscal!.code!.trim()
            : (fiscal?.name ?? 'MF 2D'),
        'stock_product_id': null,
        'stock_product_name': 'ÖKC',
        'stock_registry_number': null,
        'okc_start_date': DateFormat('yyyy-MM-dd').format(_applicationDate),
        'business_activity_type_id': businessActivity?.id,
        'business_activity_name':
            businessActivity?.name ?? businessActivityName,
        'invoice_number': null,
        'customer_phone': formattedPhone,
        'customer_email': _emailController.text.trim(),
        'taxpayer_registration_document_name': _documentName,
        'taxpayer_registration_document_mime_type': _documentMimeType,
        'taxpayer_registration_document_data': documentData,
        'taxpayer_registration_document_storage_bucket': documentBucket,
        'taxpayer_registration_document_storage_path': documentPath,
        'taxpayer_registration_document_url': documentUrl,
        'taxpayer_registration_document_uploaded_at': DateTime.now()
            .toIso8601String(),
        if (createdBy.isNotEmpty) 'created_by': createdBy,
        'is_active': true,
      };

      Map<String, dynamic> inserted;
      if (apiClient != null) {
        final response = await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'upsert',
            'table': 'application_forms',
            'returning': 'row',
            'values': payload,
          },
        );
        inserted = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
      } else {
        inserted = await client!
            .from('application_forms')
            .upsert(payload)
            .select(
              'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,customer_phone,customer_email,taxpayer_registration_document_name,taxpayer_registration_document_mime_type,taxpayer_registration_document_data,taxpayer_registration_document_storage_bucket,taxpayer_registration_document_storage_path,taxpayer_registration_document_url,approval_status,approved_at,approved_by,created_by,is_active,created_at',
            )
            .single();
      }

      if (!mounted) return;
      Navigator.of(context).pop([ApplicationFormRecord.fromJson(inserted)]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Başvuru kaydedilemedi: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final isMobile = width < 840;
    final models = ref.watch(deviceModelsProvider).asData?.value ?? const [];
    final citiesAsync = ref.watch(cityDefinitionsProvider);
    final activitiesAsync = ref.watch(businessActivityTypesProvider);
    final applicationRecords =
        ref.watch(applicationFormsProvider).asData?.value ??
        const <ApplicationFormRecord>[];
    final recordActivities = bankBusinessActivitiesFromRecords(
      applicationRecords,
    );
    final taxOfficeCities = _taxOfficeCitiesFromAsync(citiesAsync);
    final remoteBusinessActivities =
        activitiesAsync.asData?.value
            .where((item) => item.isActive)
            .toList(growable: false) ??
        const <BusinessActivityTypeDefinition>[];
    final businessActivities = _mergeBusinessActivities([
      remoteBusinessActivities,
      recordActivities,
      if (remoteBusinessActivities.isEmpty && recordActivities.isEmpty)
        _bankFallbackBusinessActivities,
    ]);
    final paxModel = _resolvePaxModel(models);
    final existingCustomer = _customer != null;
    final fieldsLocked = existingCustomer && !_isEditing;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 28,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980),
        child: SingleChildScrollView(
          padding: EdgeInsets.all(isMobile ? 18 : 28),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Capital Bank ÖKC Talep',
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const Gap(6),
                          Text(
                            'VKN ile sorgulayın, zorunlu alanları tamamlayın ve talebi gönderin.',
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AppTheme.textMuted),
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
                const Gap(24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _BankTextField(
                          controller: _vknController,
                          label: 'VKN',
                          hintText: 'Örn: 0938010101',
                          enabled: !_saving && !_lookupBusy,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(11),
                          ],
                          validator: (value) {
                            final digits = (value ?? '').replaceAll(
                              RegExp(r'\D'),
                              '',
                            );
                            if (digits.length < 10) {
                              return 'VKN en az 10 haneli olmalı.';
                            }
                            return null;
                          },
                        ),
                      ),
                      const Gap(12),
                      SizedBox(
                        height: 50,
                        child: FilledButton.icon(
                          onPressed: _lookupBusy || _saving
                              ? null
                              : _lookupCustomer,
                          icon: _lookupBusy
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.search_rounded),
                          label: const Text('Sorgula'),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_lookupDone) ...[
                  const Gap(12),
                  AppBadge(
                    label: existingCustomer
                        ? 'Müşteri bulundu, bilgiler getirildi.'
                        : 'Müşteri bulunamadı, kayıt oluşturulacak.',
                    tone: existingCustomer
                        ? AppBadgeTone.success
                        : AppBadgeTone.warning,
                  ),
                ],
                const Gap(20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 760;
                    final left = Column(
                      children: [
                        _BankTextField(
                          controller: _customerNameController,
                          label: 'Ünvan',
                          hintText: 'Örn: Capital Market Ltd.',
                          enabled: !fieldsLocked && !_saving,
                          validator: _requiredValidator,
                        ),
                        const Gap(14),
                        _BankTextField(
                          controller: _addressController,
                          label: 'İş yeri adresi',
                          hintText: 'Örn: Dereboyu Cad. No: 12 Lefkoşa',
                          enabled: !fieldsLocked && !_saving,
                          maxLines: 3,
                          validator: _requiredValidator,
                        ),
                        const Gap(14),
                        _BankTextField(
                          controller: _directorController,
                          label: 'Yetkili / Direktör',
                          hintText: 'Örn: Ahmet Yılmaz',
                          enabled: !fieldsLocked && !_saving,
                          validator: _requiredValidator,
                        ),
                        const Gap(14),
                        _ApplicationDropdown<String>(
                          value:
                              taxOfficeCities.any(
                                (item) => item.id == _selectedTaxOfficeCityId,
                              )
                              ? _selectedTaxOfficeCityId
                              : null,
                          hintText: 'Vergi Dairesi seçin',
                          items: taxOfficeCities
                              .map(
                                (item) => DropdownMenuItem(
                                  value: item.id,
                                  child: Text(item.name),
                                ),
                              )
                              .toList(growable: false),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _selectedTaxOfficeCityId = value,
                                ),
                          validator: (value) =>
                              value == null ? 'Vergi Dairesi seçin.' : null,
                        ),
                      ],
                    );
                    final right = Column(
                      children: [
                        _BankTextField(
                          controller: _phoneController,
                          label: 'Müşteri telefonu',
                          hintText: 'Örn: 0533 890 90 90',
                          enabled: !_saving,
                          keyboardType: TextInputType.phone,
                          inputFormatters: const [_PhoneTextInputFormatter()],
                          validator: _requiredValidator,
                        ),
                        const Gap(14),
                        _BankTextField(
                          controller: _emailController,
                          label: 'Müşteri e-posta',
                          hintText: 'Örn: muhasebe@capital.com',
                          enabled: !_saving,
                          keyboardType: TextInputType.emailAddress,
                          validator: (value) {
                            final text = (value ?? '').trim();
                            if (text.isEmpty) return 'Zorunlu alan.';
                            if (!text.contains('@') || !text.contains('.')) {
                              return 'Geçerli e-posta yazın.';
                            }
                            return null;
                          },
                        ),
                        const Gap(14),
                        _BankBusinessActivityField(
                          controller: _businessActivityController,
                          focusNode: _businessActivityFocusNode,
                          items: businessActivities,
                          enabled: !_saving,
                          onSelected: (item) {
                            _selectedBusinessActivityId = item?.id;
                            if (item != null) {
                              _businessActivityController.text = item.name;
                            }
                          },
                        ),
                        const Gap(14),
                        _BankReadOnlyField(
                          label: 'Model',
                          value: [
                            'PAX',
                            paxModel?.name ?? 'A910SF',
                          ].where((item) => item.trim().isNotEmpty).join(' / '),
                        ),
                        const Gap(14),
                        _BankDocumentField(
                          fileName: _documentName,
                          onPick: _saving ? null : _pickTaxpayerDocument,
                        ),
                        const Gap(14),
                        _BankDateField(
                          label: 'Talep tarihi',
                          value: _dateFormat.format(_applicationDate),
                          onTap: _saving ? null : _pickDate,
                        ),
                      ],
                    );
                    if (!twoColumns) {
                      return Column(children: [left, const Gap(14), right]);
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: left),
                        const Gap(18),
                        Expanded(child: right),
                      ],
                    );
                  },
                ),
                const Gap(24),
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
                    const Gap(14),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_isEditing ? 'Kaydet' : 'Talebi Gönder'),
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

  String? _requiredValidator(String? value) {
    if ((value ?? '').trim().isEmpty) return 'Zorunlu alan.';
    return null;
  }
}

class _BankTextField extends StatelessWidget {
  const _BankTextField({
    required this.controller,
    required this.label,
    this.hintText,
    this.enabled = true,
    this.maxLines = 1,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  final TextEditingController controller;
  final String label;
  final String? hintText;
  final bool enabled;
  final int maxLines;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: enabled ? Colors.white : const Color(0xFFF1F5F9),
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _BankBusinessActivityField extends StatelessWidget {
  const _BankBusinessActivityField({
    required this.controller,
    required this.focusNode,
    required this.items,
    required this.enabled,
    required this.onSelected,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final List<BusinessActivityTypeDefinition> items;
  final bool enabled;
  final ValueChanged<BusinessActivityTypeDefinition?> onSelected;

  @override
  Widget build(BuildContext context) {
    return RawAutocomplete<BusinessActivityTypeDefinition>(
      textEditingController: controller,
      focusNode: focusNode,
      displayStringForOption: (option) => option.name,
      optionsBuilder: (textEditingValue) {
        final query = _sortKey(textEditingValue.text);
        final ordered = [...items]
          ..sort((a, b) => _sortKey(a.name).compareTo(_sortKey(b.name)));
        if (query.isEmpty) {
          return ordered.take(240);
        }
        return ordered
            .where((item) => _sortKey(item.name).contains(query))
            .take(240);
      },
      onSelected: onSelected,
      fieldViewBuilder:
          (context, textEditingController, fieldFocusNode, onFieldSubmitted) {
            return TextFormField(
              controller: textEditingController,
              focusNode: fieldFocusNode,
              enabled: enabled,
              decoration: const InputDecoration(
                labelText: 'Meslek türü',
                hintText: 'Örn: Market / Restoran / Eczane',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(),
                suffixIcon: Icon(Icons.search_rounded, size: 18),
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty) return 'Meslek türü yazın.';
                return null;
              },
              onChanged: (_) => onSelected(null),
              onFieldSubmitted: (_) => onFieldSubmitted(),
            );
          },
      optionsViewBuilder: (context, onSelectedOption, options) {
        final optionsList = options.toList(growable: false);
        if (optionsList.isEmpty) return const SizedBox.shrink();
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 420, maxWidth: 560),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: optionsList.length,
                itemBuilder: (context, index) {
                  final item = optionsList[index];
                  return ListTile(
                    dense: true,
                    title: Text(item.name),
                    onTap: () => onSelectedOption(item),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BankReadOnlyField extends StatelessWidget {
  const _BankReadOnlyField({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        filled: true,
        fillColor: const Color(0xFFF1F5F9),
        border: const OutlineInputBorder(),
      ),
      child: Text(
        value,
        style: Theme.of(
          context,
        ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _BankDocumentField extends StatelessWidget {
  const _BankDocumentField({required this.fileName, required this.onPick});

  final String? fileName;
  final VoidCallback? onPick;

  @override
  Widget build(BuildContext context) {
    final hasFile = fileName?.trim().isNotEmpty ?? false;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: hasFile ? AppTheme.success : AppTheme.borderStrong,
        ),
      ),
      child: Row(
        children: [
          Icon(
            hasFile ? Icons.task_rounded : Icons.upload_file_rounded,
            color: hasFile ? AppTheme.success : AppTheme.textMuted,
          ),
          const Gap(10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Yükümlü kayıt belgesi',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const Gap(3),
                Text(
                  hasFile ? fileName!.trim() : 'PDF, JPG veya PNG yükleyin',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
              ],
            ),
          ),
          const Gap(10),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.attach_file_rounded, size: 18),
            label: Text(hasFile ? 'Değiştir' : 'Yükle'),
          ),
        ],
      ),
    );
  }
}

class _BankDateField extends StatelessWidget {
  const _BankDateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: Colors.white,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
    );
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
    _applicationDate = widget.duplicateMode
        ? DateTime.now()
        : (initial?.applicationDate ?? DateTime.now());
    _okcStartDate = widget.duplicateMode
        ? DateTime.now()
        : (initial?.okcStartDate ?? DateTime.now());
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
      _applyCustomerSelection(created, preserveFileRegistryIfFilled: true);
    });
  }

  void _applyCustomerSelection(
    _CustomerOption customer, {
    bool preserveFileRegistryIfFilled = false,
  }) {
    _selectedCustomerId = customer.id;
    _customerController.text = customer.name;
    _workAddressController.text = (customer.address ?? '').trim();
    _directorController.text = (customer.directorName ?? '').trim();
    if (!preserveFileRegistryIfFilled ||
        _fileRegistryController.text.trim().isEmpty) {
      _fileRegistryController.text = customer.vkn ?? '';
    }
    _customerTcknMsController.text = customer.tcknMs ?? '';
    final city = ref
        .read(cityDefinitionsProvider)
        .asData
        ?.value
        .where((item) => _sortKey(item.name) == _sortKey(customer.city ?? ''))
        .firstOrNull;
    if (city != null) {
      _selectedCityId = city.id;
    }
  }

  Future<CustomerFormData?> _loadCustomerFormData(String customerId) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);

    Map<String, dynamic>? customerRow;
    List<Map<String, dynamic>> locationRows = const [];

    if (apiClient != null) {
      final response = await apiClient.getJson(
        '/customers',
        queryParameters: {'export': 'true', 'showPassive': 'true'},
      );
      final rows = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>();
      customerRow = rows
          .where((row) => row['id']?.toString() == customerId)
          .firstOrNull;
      final locationResponse = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'customer_locations',
          'customerId': customerId,
        },
      );
      locationRows = ((locationResponse['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    } else {
      if (client == null) return null;
      customerRow = await client
          .from('customers')
          .select(
            'id,name,city,address,director_name,email,vkn,tckn_ms,phone_1_title,phone_1,phone_2_title,phone_2,phone_3_title,phone_3,notes,is_active',
          )
          .eq('id', customerId)
          .maybeSingle();
      final locations = await client
          .from('customer_locations')
          .select(
            'id,customer_id,title,description,address,location_link,location_lat,location_lng,is_active',
          )
          .eq('customer_id', customerId)
          .order('created_at', ascending: false);
      locationRows = (locations as List)
          .whereType<Map<String, dynamic>>()
          .toList(growable: false);
    }

    if (customerRow == null) return null;
    final locations = locationRows
        .map(CustomerLocation.fromJson)
        .toList(growable: false);
    return CustomerFormData(
      id: customerRow['id']?.toString(),
      name: (customerRow['name'] ?? '').toString(),
      city: customerRow['city']?.toString(),
      address: customerRow['address']?.toString(),
      directorName: customerRow['director_name']?.toString(),
      email: customerRow['email']?.toString(),
      vkn: customerRow['vkn']?.toString(),
      tcknMs: customerRow['tckn_ms']?.toString(),
      phone1Title: customerRow['phone_1_title']?.toString(),
      phone1: customerRow['phone_1']?.toString(),
      phone2Title: customerRow['phone_2_title']?.toString(),
      phone2: customerRow['phone_2']?.toString(),
      phone3Title: customerRow['phone_3_title']?.toString(),
      phone3: customerRow['phone_3']?.toString(),
      notes: customerRow['notes']?.toString(),
      isActive: customerRow['is_active'] as bool? ?? true,
      locations: locations,
    );
  }

  Future<void> _editSelectedCustomer() async {
    var customerId = (_selectedCustomerId ?? '').trim();
    if (customerId.isEmpty) {
      final currentName = _customerController.text.trim();
      if (currentName.isNotEmpty) {
        final customers = ref
            .read(applicationFormCustomersProvider)
            .asData
            ?.value;
        final matched = customers
            ?.where((item) => _sortKey(item.name) == _sortKey(currentName))
            .firstOrNull;
        if (matched != null) {
          customerId = matched.id;
          _selectedCustomerId = matched.id;
        }
      }
    }
    if (customerId.isEmpty) return;
    try {
      final initialData = await _loadCustomerFormData(customerId);
      if (initialData == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Müşteri bilgisi yüklenemedi.')),
        );
        return;
      }
      if (!mounted) return;
      final updated = await showEditCustomerDialog(
        context,
        initialData: initialData,
      );
      if (!updated) return;
      ref.invalidate(applicationFormCustomersProvider);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      final customers = await ref.read(applicationFormCustomersProvider.future);
      final refreshed = customers
          .where((item) => item.id == customerId)
          .firstOrNull;
      if (refreshed == null || !mounted) return;
      setState(() {
        _applyCustomerSelection(refreshed);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Müşteri düzenleme açılamadı: $e')),
      );
    }
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
      _applyCustomerSelection(selected);
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Kaydedilemedi: $e')));
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
      _manualSerialsController.text = selected
          .map((e) => e.serialNumber)
          .join('\n');
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Ürün ismi girin.')));
      return;
    }
    if (registryNumbers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('En az bir sicil numarası seçin.')),
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

    final profile = await ref.read(currentUserProfileProvider.future);
    final createdBy = widget.isEdit
        ? (widget.initialRecord?.createdBy ?? '').trim()
        : (profile?.id ?? '').trim();
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
        if (createdBy.isNotEmpty) 'created_by': createdBy,
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
                'stock_registry_number': primaryRegistry.isEmpty
                    ? null
                    : primaryRegistry,
              },
            },
          );
          inserted = (response['row'] as Map?)?.cast<String, dynamic>() ?? {};
        } else {
          inserted = await client!
              .from('application_forms')
              .update({
                ...basePayload,
                'stock_registry_number': primaryRegistry.isEmpty
                    ? null
                    : primaryRegistry,
              })
              .eq('id', widget.initialRecord!.id)
              .select(
                'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,customer_phone,customer_email,taxpayer_registration_document_name,taxpayer_registration_document_mime_type,taxpayer_registration_document_data,taxpayer_registration_document_storage_bucket,taxpayer_registration_document_storage_path,taxpayer_registration_document_url,approval_status,approved_at,approved_by,created_by,is_active,created_at',
              )
              .single();
        }

        try {
          final record = ApplicationFormRecord.fromJson(inserted);
          final nowIso = DateTime.now().toIso8601String();
          final registry = record.stockRegistryNumber?.trim() ?? '';
          final oldRegistry =
              widget.initialRecord?.stockRegistryNumber?.trim() ?? '';
          if (apiClient != null) {
            if (oldRegistry.isNotEmpty && oldRegistry != registry) {
              await apiClient.postJson(
                '/mutate',
                body: {
                  'op': 'updateWhere',
                  'table': 'device_registries',
                  'filters': [
                    {
                      'col': 'registry_number',
                      'op': 'eq',
                      'value': oldRegistry,
                    },
                    {
                      'col': 'application_form_id',
                      'op': 'eq',
                      'value': record.id,
                    },
                  ],
                  'values': {
                    'customer_id': null,
                    'application_form_id': null,
                    'released_at': nowIso,
                    'is_active': true,
                  },
                },
              );
            }
            if (registry.isNotEmpty &&
                (record.customerId ?? '').trim().isNotEmpty) {
              await apiClient.postJson(
                '/mutate',
                body: {
                  'op': 'upsert',
                  'table': 'device_registries',
                  'values': {
                    'registry_number': registry,
                    'model': record.modelName,
                    'customer_id': record.customerId,
                    'application_form_id': record.id,
                    'is_active': true,
                    'assigned_at': nowIso,
                    'released_at': null,
                  },
                },
              );
            }
          } else {
            if (client != null) {
              if (oldRegistry.isNotEmpty && oldRegistry != registry) {
                await client
                    .from('device_registries')
                    .update({
                      'customer_id': null,
                      'application_form_id': null,
                      'released_at': nowIso,
                      'is_active': true,
                    })
                    .eq('registry_number', oldRegistry)
                    .eq('application_form_id', record.id);
              }
              if (registry.isNotEmpty &&
                  (record.customerId ?? '').trim().isNotEmpty) {
                await client.from('device_registries').upsert({
                  'registry_number': registry,
                  'model': record.modelName,
                  'customer_id': record.customerId,
                  'application_form_id': record.id,
                  'is_active': true,
                  'assigned_at': nowIso,
                  'released_at': null,
                });
              }
            }
          }
        } catch (_) {}

        if (!mounted) return;
        Navigator.of(context).pop([ApplicationFormRecord.fromJson(inserted)]);
        return;
      }

      final payloads =
          (registryNumbers.isEmpty
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
        insertedRecords = rows
            .map(ApplicationFormRecord.fromJson)
            .toList(growable: false);

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

        try {
          final nowIso = DateTime.now().toIso8601String();
          for (final inserted in insertedRecords) {
            final registry = inserted.stockRegistryNumber?.trim() ?? '';
            final customerId = inserted.customerId?.trim() ?? '';
            if (registry.isEmpty || customerId.isEmpty) continue;
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'upsert',
                'table': 'device_registries',
                'values': {
                  'registry_number': registry,
                  'model': inserted.modelName,
                  'customer_id': customerId,
                  'application_form_id': inserted.id,
                  'is_active': true,
                  'assigned_at': nowIso,
                  'released_at': null,
                },
              },
            );
          }
        } catch (_) {}

        try {
          final profile = await ref.read(currentUserProfileProvider.future);
          final assignedTo = (profile?.id ?? '').trim();
          if (assignedTo.isEmpty) throw Exception('Oturum bulunamadı.');

          for (final inserted in insertedRecords) {
            final customerId = inserted.customerId?.trim() ?? '';
            if (customerId.isEmpty) continue;

            final registry = inserted.stockRegistryNumber?.trim() ?? '';
            final parts = <String>[
              'Başvuru Formu',
              if (inserted.brandModel.trim().isNotEmpty)
                inserted.brandModel.trim(),
              if (inserted.businessActivityName?.trim().isNotEmpty ?? false)
                inserted.businessActivityName!.trim(),
              if (inserted.fileRegistryNumber?.trim().isNotEmpty ?? false)
                'Dosya: ${inserted.fileRegistryNumber!.trim()}',
            ];
            final baseDescription = parts.join(' • ');
            final description = registry.isNotEmpty
                ? 'Sicil: $registry • $baseDescription'
                : baseDescription;

            await apiClient.postJson(
              '/work-orders',
              body: {
                'customer_id': customerId,
                'branch_id': null,
                'work_order_type_id': null,
                'title': 'Başvuru Formu',
                'description': description,
                'address': inserted.workAddress?.trim().isNotEmpty ?? false
                    ? inserted.workAddress!.trim()
                    : null,
                'assigned_to': assignedTo,
                'scheduled_date': null,
                'city': inserted.taxOfficeCityName?.trim().isNotEmpty ?? false
                    ? inserted.taxOfficeCityName!.trim()
                    : null,
                'contact_phone': null,
                'location_link': null,
                'payment_required': false,
                'status': 'approval_pending',
              },
            );
          }
          ref.invalidate(workOrdersBoardProvider);
        } catch (_) {}
      } else {
        final insertedRows = await client!
            .from('application_forms')
            .insert(payloads)
            .select(
              'id,application_date,customer_id,customer_name,customer_tckn_ms,work_address,tax_office_city_name,document_type,file_registry_number,director,brand_name,model_name,fiscal_symbol_name,stock_product_id,stock_product_name,stock_registry_number,accounting_office,okc_start_date,business_activity_name,invoice_number,customer_phone,customer_email,taxpayer_registration_document_name,taxpayer_registration_document_mime_type,taxpayer_registration_document_data,taxpayer_registration_document_storage_bucket,taxpayer_registration_document_storage_path,taxpayer_registration_document_url,approval_status,approved_at,approved_by,created_by,is_active,created_at',
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

        try {
          final nowIso = DateTime.now().toIso8601String();
          for (final inserted in insertedRecords) {
            final registry = inserted.stockRegistryNumber?.trim() ?? '';
            final customerId = inserted.customerId?.trim() ?? '';
            if (registry.isEmpty || customerId.isEmpty) continue;
            await client.from('device_registries').upsert({
              'registry_number': registry,
              'model': inserted.modelName,
              'customer_id': customerId,
              'application_form_id': inserted.id,
              'is_active': true,
              'assigned_at': nowIso,
              'released_at': null,
            });
          }
        } catch (_) {}

        try {
          final assignedTo = (client.auth.currentUser?.id ?? '').trim();
          if (assignedTo.isEmpty) throw Exception('Oturum bulunamadı.');

          for (final inserted in insertedRecords) {
            final customerId = inserted.customerId?.trim() ?? '';
            if (customerId.isEmpty) continue;

            final registry = inserted.stockRegistryNumber?.trim() ?? '';
            final parts = <String>[
              'Başvuru Formu',
              if (inserted.brandModel.trim().isNotEmpty)
                inserted.brandModel.trim(),
              if (inserted.businessActivityName?.trim().isNotEmpty ?? false)
                inserted.businessActivityName!.trim(),
              if (inserted.fileRegistryNumber?.trim().isNotEmpty ?? false)
                'Dosya: ${inserted.fileRegistryNumber!.trim()}',
            ];
            final baseDescription = parts.join(' • ');
            final description = registry.isNotEmpty
                ? 'Sicil: $registry • $baseDescription'
                : baseDescription;

            await client.from('work_orders').insert({
              'customer_id': customerId,
              'branch_id': null,
              'work_order_type_id': null,
              'title': 'Başvuru Formu',
              'description': description,
              'address': inserted.workAddress?.trim().isNotEmpty ?? false
                  ? inserted.workAddress!.trim()
                  : null,
              'assigned_to': assignedTo,
              'scheduled_date': null,
              'city': inserted.taxOfficeCityName?.trim().isNotEmpty ?? false
                  ? inserted.taxOfficeCityName!.trim()
                  : null,
              'contact_phone': null,
              'location_link': null,
              'payment_required': false,
              'status': 'approval_pending',
              'is_active': true,
            });
          }
          ref.invalidate(workOrdersBoardProvider);
        } catch (_) {}
      }

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
        child: _ResponsiveFieldGroup(
          left: _DateField(
            value: _applicationDate,
            format: _dateFormat,
            onTap: () => _pickDate(
              currentValue: _applicationDate,
              onSelected: (value) => setState(() => _applicationDate = value),
            ),
          ),
          right: _ApplicationTextField(
            controller: _invoiceNumberController,
            hintText: 'Fatura no girin',
          ),
        ),
      ),
      _FormRow(
        label: 'Adı - Soyadı / Ünvanı',
        child: customersAsync.when(
          data: (items) => _CustomerPickerField(
            controller: _customerController,
            selectedCustomerId: _selectedCustomerId,
            onPickCustomer: () => _pickCustomer(items),
            onEditCustomer: _editSelectedCustomer,
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
          hintText: 'İşyeri adresini girin',
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
              hintText: 'Vergi dairesi seçin',
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
          left: _ApplicationTextField(
            controller: _fileRegistryController,
            hintText: 'Dosya sicil no girin',
          ),
          right: _ApplicationTextField(
            controller: _customerTcknMsController,
            hintText: 'VKN / MS girin',
          ),
        ),
      ),
      _FormRow(
        label: 'Direktör Ad Soyad',
        child: _ApplicationTextField(
          controller: _directorController,
          hintText: 'Direktör ad soyad girin',
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
        label: 'Ürün ve Sicil No',
        child: _ResponsiveFieldGroup(
          left: _ApplicationTextField(
            controller: _productNameController,
            hintText: 'Model seçilince ürün adı gelir',
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
                  Expanded(
                    child: Text(
                      'Kayıtlı seri havuzundan seçebilir veya manuel girebilirsiniz.',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppTheme.textMuted,
                      ),
                    ),
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
                  labelText: widget.isEdit
                      ? 'Ürün Sicil No'
                      : 'Ürün Sicil No(ları)',
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
                        color: isActive
                            ? const Color(0xFF16A34A)
                            : const Color(0xFF64748B),
                      ),
                      const Gap(10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Seri takipte kayıtlı: $serial',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const Gap(4),
                            Text(
                              productName.trim().isEmpty
                                  ? 'Ürün adı yok'
                                  : productName.trim(),
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      AppBadge(
                        label: isActive ? 'Aktif' : 'Pasif',
                        tone: isActive
                            ? AppBadgeTone.success
                            : AppBadgeTone.neutral,
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
                    const Icon(
                      Icons.info_outline_rounded,
                      color: Color(0xFF64748B),
                    ),
                    const Gap(10),
                    Expanded(
                      child: Text(
                        'Bu sicil numarası seri takipte yok: $serial',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                        ),
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
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
              hintText: 'Mali sembol seçin',
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
          left: _ApplicationTextField(
            controller: _accountingOfficeController,
            hintText: 'Muhasebe ofisi girin',
          ),
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
          maxWidth: isMobile ? 720 : 1180,
          maxHeight: MediaQuery.sizeOf(context).height * 0.94,
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
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    fontSize: isMobile ? 20 : 22,
                                    fontWeight: FontWeight.w800,
                                  ),
                            ),
                            const Gap(6),
                            Text(
                              widget.isEdit
                                  ? 'Kaydı güncelleyin.'
                                  : 'Belge düzeninde formu doldurun. Kayıt sonrası KDV4 ve KDV4A yazdırma seçenekleri açılır.',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: AppTheme.textMuted,
                                    fontSize: 13,
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
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: Column(children: formRows),
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
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
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: AppTheme.border),
                                ),
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
        queryParameters: {
          'resource': 'serial_tracking_lookup',
          'serial': serial,
        },
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

class _SerialTrackingPickerDialogState
    extends State<_SerialTrackingPickerDialog> {
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
    final filtered = widget.items
        .where((item) {
          if (query.isEmpty) return true;
          final haystack = _sortKey('${item.serialNumber} ${item.productName}');
          return haystack.contains(query);
        })
        .toList(growable: false);

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
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      )
                    : ListView.separated(
                        itemCount: filtered.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final serial = item.serialNumber.trim().toUpperCase();
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
                              style: Theme.of(context).textTheme.bodyMedium
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

class _ApplicationFormLogsDialog extends ConsumerWidget {
  const _ApplicationFormLogsDialog({required this.record});

  final ApplicationFormRecord record;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final logsAsync = ref.watch(applicationFormLogsProvider(record.id));
    final isMobile = MediaQuery.sizeOf(context).width < 720;
    return Dialog(
      insetPadding: EdgeInsets.all(isMobile ? 12 : 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820, maxHeight: 680),
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 16 : 22),
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
                          'Form Logları',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const Gap(4),
                        Text(
                          record.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(14),
              Expanded(
                child: logsAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (error, _) =>
                      Center(child: Text('Loglar yüklenemedi: $error')),
                  data: (logs) {
                    if (logs.isEmpty) {
                      return const Center(
                        child: Text('Bu form için henüz log yok.'),
                      );
                    }
                    return ListView.separated(
                      itemCount: logs.length,
                      separatorBuilder: (_, _) => const Gap(10),
                      itemBuilder: (context, index) =>
                          _ApplicationFormLogCard(entry: logs[index]),
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

class _ApplicationFormLogCard extends StatelessWidget {
  const _ApplicationFormLogCard({required this.entry});

  final ApplicationFormLogEntry entry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppBadge(
                label: _logActionLabel(entry.action),
                tone: _logActionTone(entry.action),
              ),
              const Gap(8),
              Expanded(
                child: Text(
                  entry.actorName?.trim().isNotEmpty ?? false
                      ? entry.actorName!.trim()
                      : 'Kullanıcı',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
              Text(
                DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(entry.createdAt),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
              ),
            ],
          ),
          const Gap(10),
          if (entry.changes.isEmpty)
            Text(
              'Alan değişikliği yok.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            )
          else
            for (final change in entry.changes.take(12)) ...[
              _ApplicationFormLogChangeRow(change: change),
              const Gap(6),
            ],
          if (entry.changes.length > 12)
            Text(
              '+${entry.changes.length - 12} değişiklik daha',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
        ],
      ),
    );
  }
}

class _ApplicationFormLogChangeRow extends StatelessWidget {
  const _ApplicationFormLogChangeRow({required this.change});

  final ApplicationFormLogChange change;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 150,
            child: Text(
              change.label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          const Gap(8),
          Expanded(
            child: Text(
              '${_logValue(change.oldValue)} -> ${_logValue(change.newValue)}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationRecordCard extends StatelessWidget {
  const _ApplicationRecordCard({
    required this.record,
    required this.colorIndex,
    required this.canEdit,
    required this.canApprove,
    required this.canArchive,
    required this.canDeletePermanently,
    required this.canPrintKdv4a,
    required this.canCreateWorkOrder,
    required this.selected,
    required this.onSelectionChanged,
    required this.onPrintKdv,
    required this.onViewDocument,
    required this.onUploadApprovalDocument,
    required this.onShareApprovalDocument,
    required this.onViewLogs,
    required this.onPrintKdv4a,
    required this.onCreateWorkOrder,
    required this.onApprove,
    required this.onUnapprove,
    required this.onEdit,
    required this.onDuplicate,
    required this.onToggleActive,
    required this.onDeletePermanently,
  });

  final ApplicationFormRecord record;
  final int colorIndex;
  final bool canEdit;
  final bool canApprove;
  final bool canArchive;
  final bool canDeletePermanently;
  final bool canPrintKdv4a;
  final bool canCreateWorkOrder;
  final bool selected;
  final ValueChanged<bool> onSelectionChanged;
  final VoidCallback onPrintKdv;
  final VoidCallback onViewDocument;
  final VoidCallback onUploadApprovalDocument;
  final VoidCallback onShareApprovalDocument;
  final VoidCallback onViewLogs;
  final VoidCallback onPrintKdv4a;
  final VoidCallback onCreateWorkOrder;
  final VoidCallback onApprove;
  final VoidCallback onUnapprove;
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
    final approvalLabel = record.isApproved ? 'Onaylandı' : 'Onay Bekliyor';
    final approvalTone = record.isApproved
        ? AppBadgeTone.success
        : AppBadgeTone.warning;
    final canModify = canEdit && !record.isApproved;
    final canChangeActive = canArchive && !record.isApproved;
    final canDelete =
        !record.isActive && canDeletePermanently && !record.isApproved;

    final backgrounds = [
      const Color(0xFFF0F9FF),
      const Color(0xFFECFDF5),
      const Color(0xFFFFFBEB),
      const Color(0xFFFDF2F8),
      const Color(0xFFF5F3FF),
    ];
    final backgroundColor = record.isActive
        ? backgrounds[colorIndex % backgrounds.length]
        : null;

    final menuItems = <PopupMenuEntry<String>>[
      if (canModify) const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
      if (canModify && canPrintKdv4a)
        const PopupMenuItem(value: 'duplicate', child: Text('Kopya Oluştur')),
      if (record.hasTaxpayerRegistrationDocument)
        const PopupMenuItem(value: 'document', child: Text('Yükümlü Belgesi')),
      if (canApprove && record.isApproved)
        PopupMenuItem(
          value: 'upload_approval_document',
          child: Text(
            record.hasApprovalDocument
                ? 'Onay Belgesini Yenile'
                : 'Onay Belgesi Yükle',
          ),
        ),
      if (record.hasApprovalDocument)
        const PopupMenuItem(
          value: 'share_approval_document',
          child: Text('Onay Belgesini Paylaş'),
        ),
      const PopupMenuItem(value: 'logs', child: Text('Loglar')),
      if (canApprove && record.isPendingApproval)
        const PopupMenuItem(value: 'approve', child: Text('Onayla')),
      if (canApprove && record.isApproved)
        const PopupMenuItem(value: 'unapprove', child: Text('Onayı Geri Al')),
      const PopupMenuItem(value: 'print_kdv4', child: Text('KDV4 Yazdır')),
      if (canPrintKdv4a)
        const PopupMenuItem(value: 'print_kdv4a', child: Text('KDV4A Yazdır')),
      if (canCreateWorkOrder)
        const PopupMenuItem(
          value: 'create_work_order',
          child: Text('İş Emri Oluştur'),
        ),
      if (canChangeActive)
        PopupMenuItem(
          value: 'toggle_active',
          child: Text(record.isActive ? 'Pasife Al' : 'Aktifleştir'),
        ),
      if (canDelete)
        const PopupMenuItem(
          value: 'delete_permanently',
          child: Text('Kalıcı Sil'),
        ),
    ];

    void handleMenuSelection(String value) {
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
        case 'document':
          onViewDocument();
          break;
        case 'upload_approval_document':
          onUploadApprovalDocument();
          break;
        case 'share_approval_document':
          onShareApprovalDocument();
          break;
        case 'logs':
          onViewLogs();
          break;
        case 'print_kdv4a':
          onPrintKdv4a();
          break;
        case 'create_work_order':
          onCreateWorkOrder();
          break;
        case 'approve':
          onApprove();
          break;
        case 'unapprove':
          onUnapprove();
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
    }

    if (!isMobile) {
      return AppCard(
        padding: EdgeInsets.zero,
        child: IntrinsicHeight(
          child: Row(
            children: [
              Container(
                width: 5,
                decoration: BoxDecoration(
                  color: accentColor.withValues(
                    alpha: record.isActive ? 0.75 : 0.35,
                  ),
                  borderRadius: const BorderRadius.horizontal(
                    left: Radius.circular(AppTheme.radiusMd),
                  ),
                ),
              ),
              SizedBox(
                width: 62,
                child: Center(
                  child: Checkbox(
                    value: selected,
                    visualDensity: VisualDensity.compact,
                    onChanged: (value) => onSelectionChanged(value ?? false),
                  ),
                ),
              ),
              Expanded(
                flex: 36,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(0, 14, 18, 14),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        record.customerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontSize: 14.5,
                          decoration: record.isActive
                              ? TextDecoration.none
                              : TextDecoration.lineThrough,
                        ),
                      ),
                      const Gap(5),
                      Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          if (record.businessActivityName?.trim().isNotEmpty ??
                              false)
                            _InfoChip(
                              icon: Icons.storefront_rounded,
                              text: record.businessActivityName!,
                            ),
                          if (record.brandModel.isNotEmpty)
                            _InfoChip(
                              icon: Icons.developer_board_rounded,
                              text: record.brandModel,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                flex: 15,
                child: _ApplicationListMeta(
                  icon: Icons.calendar_today_rounded,
                  label: 'Tarih',
                  value: dateText,
                ),
              ),
              Expanded(
                flex: 16,
                child: _ApplicationListMeta(
                  icon: Icons.folder_open_rounded,
                  label: 'Dosya',
                  value: record.fileRegistryNumber?.trim().isNotEmpty == true
                      ? record.fileRegistryNumber!.trim()
                      : '-',
                ),
              ),
              Expanded(
                flex: 16,
                child: _ApplicationListMeta(
                  icon: record.isApproved
                      ? Icons.verified_rounded
                      : Icons.memory_rounded,
                  label: record.isApproved ? 'Onaylı Sicil' : 'Cihaz',
                  value: record.stockRegistryNumber?.trim().isNotEmpty == true
                      ? record.stockRegistryNumber!.trim()
                      : '-',
                  highlighted: record.isApproved,
                ),
              ),
              SizedBox(
                width: 154,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      AppBadge(label: approvalLabel, tone: approvalTone),
                      if (record.isApproved)
                        AppBadge(
                          label: record.hasApprovalDocument
                              ? 'Belge Var'
                              : 'Belge Yok',
                          tone: record.hasApprovalDocument
                              ? AppBadgeTone.primary
                              : AppBadgeTone.warning,
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(
                width: 178,
                child: Padding(
                  padding: const EdgeInsets.only(right: 14),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (canApprove && record.isPendingApproval)
                        _RecordPrimaryAction(
                          onPressed: onApprove,
                          icon: Icons.verified_rounded,
                          label: 'Onayla',
                          primary: true,
                        )
                      else if (canApprove && record.isApproved)
                        _RecordPrimaryAction(
                          onPressed: onUnapprove,
                          icon: Icons.undo_rounded,
                          label: 'Geri Al',
                        )
                      else if (canModify)
                        _RecordPrimaryAction(
                          onPressed: onEdit,
                          icon: Icons.edit_rounded,
                          label: 'Düzenle',
                        )
                      else
                        _RecordPrimaryAction(
                          onPressed: onPrintKdv,
                          icon: Icons.print_rounded,
                          label: 'KDV4',
                        ),
                      const Gap(8),
                      PopupMenuButton<String>(
                        tooltip: 'Diğer işlemler',
                        itemBuilder: (context) => menuItems,
                        onSelected: handleMenuSelection,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.border),
                          ),
                          child: const Icon(Icons.more_horiz_rounded, size: 20),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 10,
        vertical: isMobile ? 7 : 6,
      ),
      color: backgroundColor,
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
                  border: Border.all(
                    color: accentColor.withValues(alpha: 0.25),
                  ),
                ),
              ),
              const Gap(6),
              Padding(
                padding: const EdgeInsets.only(right: 2),
                child: Checkbox(
                  value: selected,
                  visualDensity: const VisualDensity(
                    horizontal: -4,
                    vertical: -4,
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
              const Gap(8),
              AppBadge(label: approvalLabel, tone: approvalTone),
              if (record.isApproved) ...[
                const Gap(4),
                AppBadge(
                  label: record.hasApprovalDocument ? 'Belge Var' : 'Belge Yok',
                  tone: record.hasApprovalDocument
                      ? AppBadgeTone.primary
                      : AppBadgeTone.warning,
                ),
              ],
              const Gap(6),
              if (isMobile)
                PopupMenuButton<String>(
                  tooltip: 'İşlemler',
                  itemBuilder: (context) => menuItems,
                  onSelected: handleMenuSelection,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                    child: Icon(Icons.more_horiz_rounded),
                  ),
                )
              else ...[
                if (canModify) ...[
                  _ActionButton(
                    onPressed: onEdit,
                    icon: Icons.edit_rounded,
                    label: 'Düzenle',
                  ),
                  const Gap(4),
                  if (canPrintKdv4a) ...[
                    _ActionButton(
                      onPressed: onDuplicate,
                      icon: Icons.content_copy_rounded,
                      label: 'Kopya',
                    ),
                    const Gap(4),
                  ],
                ],
                _ActionButton(
                  onPressed: onPrintKdv,
                  icon: Icons.print_rounded,
                  label: 'KDV4',
                ),
                const Gap(4),
                if (record.hasTaxpayerRegistrationDocument) ...[
                  _ActionButton(
                    onPressed: onViewDocument,
                    icon: Icons.attach_file_rounded,
                    label: 'Belge',
                  ),
                  const Gap(4),
                ],
                if (canApprove && record.isApproved) ...[
                  _ActionButton(
                    onPressed: onUploadApprovalDocument,
                    icon: Icons.document_scanner_rounded,
                    label: record.hasApprovalDocument ? 'Yenile' : 'Yükle',
                    primary: !record.hasApprovalDocument,
                  ),
                  const Gap(4),
                ],
                if (record.hasApprovalDocument) ...[
                  _ActionButton(
                    onPressed: onShareApprovalDocument,
                    icon: Icons.ios_share_rounded,
                    label: 'Paylaş',
                  ),
                  const Gap(4),
                ],
                _ActionButton(
                  onPressed: onViewLogs,
                  icon: Icons.history_rounded,
                  label: 'Log',
                ),
                const Gap(4),
                if (canPrintKdv4a) ...[
                  _ActionButton(
                    onPressed: onPrintKdv4a,
                    icon: Icons.picture_as_pdf_rounded,
                    label: 'KDV4A',
                    primary: true,
                  ),
                  const Gap(4),
                ],
                if (canApprove && record.isPendingApproval) ...[
                  _ActionButton(
                    onPressed: onApprove,
                    icon: Icons.verified_rounded,
                    label: 'Onayla',
                    primary: true,
                  ),
                  const Gap(4),
                ],
                if (canApprove && record.isApproved) ...[
                  _ActionButton(
                    onPressed: onUnapprove,
                    icon: Icons.undo_rounded,
                    label: 'Geri Al',
                  ),
                  const Gap(4),
                ],
                if (canCreateWorkOrder)
                  _ActionButton(
                    onPressed: onCreateWorkOrder,
                    icon: Icons.playlist_add_rounded,
                    label: 'İş Emri',
                  ),
                if (canChangeActive) ...[
                  const Gap(4),
                  _ActionButton(
                    onPressed: onToggleActive,
                    icon: record.isActive
                        ? Icons.delete_outline_rounded
                        : Icons.restore_rounded,
                    label: record.isActive ? 'Pasif' : 'Aktif',
                  ),
                ],
                if (canDelete) ...[
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
                  icon: record.isApproved
                      ? Icons.verified_rounded
                      : Icons.memory_rounded,
                  text: record.isApproved
                      ? 'Onaylı Sicil: ${record.stockRegistryNumber}'
                      : 'Cihaz: ${record.stockRegistryNumber}',
                  highlighted: record.isApproved,
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
              if (record.isApproved)
                _InfoChip(
                  icon: record.hasApprovalDocument
                      ? Icons.picture_as_pdf_rounded
                      : Icons.upload_file_rounded,
                  text: record.hasApprovalDocument
                      ? 'Onay belgesi var'
                      : 'Onay belgesi yok',
                  highlighted: record.hasApprovalDocument,
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
    required this.registryNumber,
    required this.paymentRequired,
    required this.status,
  });

  final String? workOrderTypeId;
  final String workOrderTypeName;
  final String? assignedTo;
  final DateTime? scheduledDate;
  final String description;
  final String? registryNumber;
  final bool paymentRequired;
  final String status;
}

class _WorkOrderTypeChoice {
  const _WorkOrderTypeChoice({required this.id, required this.name});

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
  const _PersonnelChoice({required this.id, required this.fullName});

  final String id;
  final String fullName;

  factory _PersonnelChoice.fromJson(Map<String, dynamic> json) {
    return _PersonnelChoice(
      id: json['id'].toString(),
      fullName: (json['full_name'] ?? 'Personel').toString(),
    );
  }
}

class _DeviceRegistryChoice {
  const _DeviceRegistryChoice({
    required this.registryNumber,
    required this.model,
  });

  final String registryNumber;
  final String? model;

  factory _DeviceRegistryChoice.fromJson(Map<String, dynamic> json) {
    return _DeviceRegistryChoice(
      registryNumber: (json['registry_number'] ?? '').toString(),
      model: json['model']?.toString(),
    );
  }
}

class _ApplicationWorkOrderDialog extends ConsumerStatefulWidget {
  const _ApplicationWorkOrderDialog({
    required this.recordCount,
    required this.customerIdForRegistry,
    required this.initialRegistryNumber,
  });

  final int recordCount;
  final String? customerIdForRegistry;
  final String? initialRegistryNumber;

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
  List<_DeviceRegistryChoice> _registries = const [];
  String? _selectedTypeId;
  String? _selectedAssignedTo;
  String? _selectedRegistryNumber;
  DateTime? _scheduledDate;
  bool? _paymentRequired;
  String _selectedStatus = 'open';
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
              .toList(growable: false);
          personnel = rows
              .map(_PersonnelChoice.fromJson)
              .toList(growable: false);
        } else {
          final userRows = await client!
              .from('users')
              .select('id,full_name,role')
              .order('full_name')
              .limit(200);
          personnel = (userRows as List)
              .map((row) => row as Map<String, dynamic>)
              .map(_PersonnelChoice.fromJson)
              .toList(growable: false);
        }
      }

      if (!mounted) return;
      List<_DeviceRegistryChoice> registries = const [];
      final customerId = (widget.customerIdForRegistry ?? '').trim();
      if (customerId.isNotEmpty) {
        if (apiClient != null) {
          final response = await apiClient.getJson(
            '/data',
            queryParameters: {
              'resource': 'customer_device_registries',
              'customerId': customerId,
              'showPassive': 'false',
            },
          );
          registries = ((response['items'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .map(_DeviceRegistryChoice.fromJson)
              .where((e) => e.registryNumber.trim().isNotEmpty)
              .toList(growable: false);
        } else if (client != null) {
          final rows = await client
              .from('device_registries')
              .select('registry_number,model,is_active')
              .eq('customer_id', customerId)
              .eq('is_active', true)
              .order('registry_number', ascending: true)
              .limit(1000);
          registries = (rows as List)
              .map(
                (e) =>
                    _DeviceRegistryChoice.fromJson(e as Map<String, dynamic>),
              )
              .where((e) => e.registryNumber.trim().isNotEmpty)
              .toList(growable: false);
        }
        registries = [...registries]
          ..sort((a, b) => a.registryNumber.compareTo(b.registryNumber));
      }
      final parsedTypes = typesRows
          .map(_WorkOrderTypeChoice.fromJson)
          .toList(growable: false);
      setState(() {
        _types = parsedTypes;
        _personnel = personnel;
        _registries = registries;
        if (_types.length == 1) {
          _selectedTypeId = _types.first.id;
        }
        if (_personnel.length == 1) {
          _selectedAssignedTo = _personnel.first.id;
        }
        final initialRegistry = (widget.initialRegistryNumber ?? '').trim();
        if (initialRegistry.isNotEmpty &&
            _registries.any(
              (e) => e.registryNumber.trim() == initialRegistry,
            )) {
          _selectedRegistryNumber = initialRegistry;
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
    final selectedType = _types
        .where((item) => item.id == _selectedTypeId)
        .firstOrNull;
    final fallbackName = selectedType?.name.trim() ?? '';
    setState(() => _saving = true);
    Navigator.of(context).pop(
      _WorkOrderCreationConfig(
        workOrderTypeId: _selectedTypeId,
        workOrderTypeName: fallbackName.isEmpty ? 'İş Emri' : fallbackName,
        assignedTo: _selectedAssignedTo,
        scheduledDate: _scheduledDate,
        description: _descriptionController.text.trim(),
        registryNumber: _selectedRegistryNumber,
        paymentRequired: _paymentRequired!,
        status: _selectedStatus,
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
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: AppTheme.textMuted),
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
                            : DateFormat(
                                'dd.MM.yyyy',
                                'tr_TR',
                              ).format(_scheduledDate!),
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
                        if (_personnel.isNotEmpty && (value ?? '').isEmpty) {
                          return 'Personel seçin.';
                        }
                        return null;
                      },
                      decoration: const InputDecoration(
                        labelText: 'Atanan Personel',
                      ),
                    ),
                  ],
                  if (_registries.isNotEmpty) ...[
                    const Gap(12),
                    DropdownButtonFormField<String?>(
                      initialValue: _selectedRegistryNumber,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Sicil seç (opsiyonel)'),
                        ),
                        ..._registries.map(
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
                          : (value) => setState(() {
                              _selectedRegistryNumber = value;
                            }),
                      decoration: const InputDecoration(
                        labelText: 'Cihaz Sicil',
                      ),
                    ),
                  ],
                  const Gap(12),
                  DropdownButtonFormField<bool?>(
                    initialValue: _paymentRequired,
                    items: const [
                      DropdownMenuItem<bool?>(
                        value: null,
                        child: Text('Ödeme seçiniz'),
                      ),
                      DropdownMenuItem<bool?>(
                        value: true,
                        child: Text('Ödeme alınacak'),
                      ),
                      DropdownMenuItem<bool?>(
                        value: false,
                        child: Text('Ödeme alınmayacak'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _paymentRequired = value),
                    validator: (value) =>
                        value == null ? 'Ödeme seçimi zorunlu.' : null,
                    decoration: const InputDecoration(labelText: 'Ödeme'),
                  ),
                  const Gap(12),
                  DropdownButtonFormField<String>(
                    initialValue: _selectedStatus,
                    items: const [
                      DropdownMenuItem<String>(
                        value: 'open',
                        child: Text('Açık'),
                      ),
                      DropdownMenuItem<String>(
                        value: 'approval_pending',
                        child: Text('Onay Bekliyor'),
                      ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) => setState(() {
                            _selectedStatus = value ?? 'open';
                          }),
                    decoration: const InputDecoration(labelText: 'Durum'),
                  ),
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
  const _InfoChip({
    required this.icon,
    required this.text,
    this.highlighted = false,
  });

  final IconData icon;
  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppTheme.success : AppTheme.textMuted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? AppTheme.success.withValues(alpha: 0.10)
            : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: highlighted
              ? AppTheme.success.withValues(alpha: 0.22)
              : AppTheme.border,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const Gap(3),
          Text(
            text,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: highlighted ? AppTheme.success : null,
              fontSize: 10.5,
              height: 1.0,
            ),
          ),
        ],
      ),
    );
  }
}

class _ApplicationListMeta extends StatelessWidget {
  const _ApplicationListMeta({
    required this.icon,
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? AppTheme.success : AppTheme.textMuted;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const Gap(9),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontWeight: FontWeight.w700,
                    height: 1,
                  ),
                ),
                const Gap(4),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: highlighted ? AppTheme.success : AppTheme.textSoft,
                    fontWeight: FontWeight.w800,
                    height: 1.05,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RecordPrimaryAction extends StatelessWidget {
  const _RecordPrimaryAction({
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
          minimumSize: const Size(96, 38),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        );
    final child = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16),
        const Gap(6),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    return primary
        ? FilledButton(onPressed: onPressed, style: style, child: child)
        : OutlinedButton(onPressed: onPressed, style: style, child: child);
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
  const _FormRow({required this.label, required this.child, this.last = false});

  final String label;
  final Widget child;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 760;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 12),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.all(isMobile ? 12 : 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: AppTheme.text,
                fontSize: isMobile ? 12.5 : 13,
              ),
            ),
            const Gap(9),
            child,
          ],
        ),
      ),
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
    this.hintText,
  });

  final TextEditingController controller;
  final int? minLines;
  final int maxLines;
  final String? Function(String?)? validator;
  final bool readOnly;
  final bool enabled;
  final String? hintText;

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
        hintText: hintText,
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
          builder: (context) =>
              _BusinessActivityPickerDialog(selectedIds: selectedIds),
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

class _BusinessActivityPickerDialog extends ConsumerStatefulWidget {
  const _BusinessActivityPickerDialog({required this.selectedIds});

  final List<String> selectedIds;

  @override
  ConsumerState<_BusinessActivityPickerDialog> createState() =>
      _BusinessActivityPickerDialogState();
}

class _BusinessActivityPickerDialogState
    extends ConsumerState<_BusinessActivityPickerDialog> {
  late final Set<String> _selectedIds;
  late final TextEditingController _searchController;
  String _query = '';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.selectedIds.toSet();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _isAdmin {
    final profile = ref
        .watch(currentUserProfileProvider)
        .maybeWhen(data: (p) => p, orElse: () => null);
    return profile?.role == 'admin';
  }

  Future<void> _upsertActivity({
    BusinessActivityTypeDefinition? initial,
  }) async {
    final controller = TextEditingController(text: initial?.name ?? '');
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          initial == null ? 'Faaliyet Türü Ekle' : 'Faaliyet Türü Düzenle',
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Ad',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(null),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: Text(initial == null ? 'Ekle' : 'Kaydet'),
          ),
        ],
      ),
    );

    controller.dispose();

    final name = (result ?? '').trim();
    if (name.isEmpty) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    setState(() => _saving = true);
    try {
      if (initial == null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'insertMany',
            'table': 'business_activity_types',
            'rows': [
              {'name': name, 'is_active': true},
            ],
          },
        );
      } else {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'business_activity_types',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': initial.id},
            ],
            'values': {'name': name},
          },
        );
      }
      ref.invalidate(businessActivityTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteActivity(BusinessActivityTypeDefinition item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Faaliyet Türünü Sil'),
        content: const Text('Bu kaydı silmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'business_activity_types',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': item.id},
          ],
        },
      );
      _selectedIds.remove(item.id);
      ref.invalidate(businessActivityTypesProvider);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(businessActivityTypesProvider);
    final items = itemsAsync.maybeWhen(
      data: (v) => v.where((e) => e.isActive).toList(growable: false),
      orElse: () => const <BusinessActivityTypeDefinition>[],
    );
    final q = _query.trim().toLowerCase();
    final filteredItems = q.isEmpty
        ? items
        : items
              .where((e) => e.name.toLowerCase().contains(q))
              .toList(growable: false);

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
                  if (_isAdmin)
                    IconButton(
                      onPressed: _saving ? null : () => _upsertActivity(),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.add_rounded),
                    ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const Gap(8),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Ara...',
                  prefixIcon: Icon(Icons.search_rounded),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v),
              ),
              const Gap(8),
              Flexible(
                child: itemsAsync.when(
                  loading: () => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: CircularProgressIndicator(),
                    ),
                  ),
                  error: (e, st) => const Center(
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Yüklenemedi.'),
                    ),
                  ),
                  data: (_) {
                    if (filteredItems.isEmpty) {
                      return const Center(
                        child: Padding(
                          padding: EdgeInsets.all(20),
                          child: Text('Sonuç yok.'),
                        ),
                      );
                    }
                    return ListView.separated(
                      shrinkWrap: true,
                      itemCount: filteredItems.length,
                      separatorBuilder: (context, index) =>
                          const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return CheckboxListTile(
                          value: _selectedIds.contains(item.id),
                          controlAffinity: ListTileControlAffinity.leading,
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(item.name),
                          secondary: _isAdmin
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      onPressed: _saving
                                          ? null
                                          : () =>
                                                _upsertActivity(initial: item),
                                      icon: const Icon(Icons.edit_rounded),
                                    ),
                                    IconButton(
                                      onPressed: _saving
                                          ? null
                                          : () => _deleteActivity(item),
                                      icon: const Icon(
                                        Icons.delete_outline_rounded,
                                      ),
                                    ),
                                  ],
                                )
                              : null,
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
    required this.onEditCustomer,
    required this.onCreateCustomer,
  });

  final TextEditingController controller;
  final String? selectedCustomerId;
  final VoidCallback onPickCustomer;
  final VoidCallback onEditCustomer;
  final VoidCallback onCreateCustomer;

  @override
  Widget build(BuildContext context) {
    final canEditCustomer =
        (selectedCustomerId ?? '').isNotEmpty ||
        controller.text.trim().isNotEmpty;
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
          onPressed: canEditCustomer ? onEditCustomer : null,
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 44),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            textStyle: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
          icon: const Icon(Icons.edit_rounded, size: 16),
          label: const Text('Düzenle'),
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
    required this.email,
    required this.phone,
    required this.city,
    required this.address,
    required this.directorName,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? vkn;
  final String? tcknMs;
  final String? email;
  final String? phone;
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
      email: json['email']?.toString(),
      phone: json['phone_1']?.toString(),
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
