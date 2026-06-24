import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../application_forms/application_form_model.dart';
import '../application_forms/application_form_screen.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import '../forms/fault_form_model.dart';
import '../forms/fault_form_screen.dart';
import '../forms/scrap_form_model.dart';
import '../forms/scrap_form_screen.dart';
import '../forms/transfer_form_model.dart';
import '../forms/transfer_form_screen.dart';

class DocumentLibraryScreen extends ConsumerStatefulWidget {
  const DocumentLibraryScreen({super.key});

  @override
  ConsumerState<DocumentLibraryScreen> createState() =>
      _DocumentLibraryScreenState();
}

class _DocumentLibraryScreenState extends ConsumerState<DocumentLibraryScreen> {
  final _searchController = TextEditingController();
  final _selectedKeys = <String>{};
  String _typeFilter = 'all';
  String _storageFilter = 'all';
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final recordsAsync = ref.watch(applicationFormsProvider);
    final scrapAsync = ref.watch(scrapFormsProvider);
    final faultAsync = ref.watch(faultFormsProvider);
    final transferAsync = ref.watch(transferFormsProvider);
    return AppPageLayout(
      title: 'Belgeler',
      subtitle: 'Yüklenen belgeleri filtreleyin, indirin veya silin.',
      actions: [
        OutlinedButton.icon(
          onPressed: _busy
              ? null
              : () {
                  ref.invalidate(applicationFormsProvider);
                  ref.invalidate(scrapFormsProvider);
                  ref.invalidate(faultFormsProvider);
                  ref.invalidate(transferFormsProvider);
                },
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: recordsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) =>
            Center(child: Text('Belgeler yüklenemedi: $error')),
        data: (records) {
          final formItems = <_DocumentItem>[
            ...((scrapAsync.asData?.value ?? const <ScrapFormRecord>[]).expand(
              _DocumentItem.fromScrapForm,
            )),
            ...((faultAsync.asData?.value ?? const <FaultFormRecord>[]).expand(
              _DocumentItem.fromFaultForm,
            )),
            ...((transferAsync.asData?.value ?? const <TransferFormRecord>[])
                .expand(_DocumentItem.fromTransferForm)),
          ];
          return _buildBody(context, records, formItems);
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    List<ApplicationFormRecord> records,
    List<_DocumentItem> formItems,
  ) {
    final allItems = [
      ...records.expand(_DocumentItem.fromRecord),
      ...formItems,
    ];
    final query = _searchController.text.trim().toLowerCase();
    final items = allItems.where((item) {
      final typeOk = _typeFilter == 'all' || item.typeKey == _typeFilter;
      final storageOk =
          _storageFilter == 'all' || item.storageKey == _storageFilter;
      final text = [
        item.customerName,
        item.fileName,
        item.registryNumber,
        item.typeLabel,
      ].join(' ').toLowerCase();
      return typeOk && storageOk && (query.isEmpty || text.contains(query));
    }).toList();
    _selectedKeys.removeWhere((key) => !items.any((item) => item.key == key));
    final selectedItems = items
        .where((item) => _selectedKeys.contains(item.key))
        .toList(growable: false);

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final fieldWidth = compact
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 20) / 3;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: compact ? constraints.maxWidth : fieldWidth,
                        child: TextField(
                          controller: _searchController,
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Firma, dosya no veya belge adı ara',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      _FilterMenu(
                        width: compact ? constraints.maxWidth : fieldWidth,
                        value: _typeFilter,
                        icon: Icons.description_rounded,
                        items: const {
                          'all': 'Tüm Belgeler',
                          'taxpayer': 'Yükümlü Belgesi',
                          'approval': 'Onay Belgesi',
                          'scrap': 'Hurda Formu',
                          'fault': 'Arıza Formu',
                          'transfer': 'Devir Formu',
                        },
                        onChanged: (value) =>
                            setState(() => _typeFilter = value),
                      ),
                      _FilterMenu(
                        width: compact ? constraints.maxWidth : fieldWidth,
                        value: _storageFilter,
                        icon: Icons.storage_rounded,
                        items: const {
                          'all': 'Tüm Kaynaklar',
                          'storage': 'Storage',
                          'database': 'Veritabanı',
                        },
                        onChanged: (value) =>
                            setState(() => _storageFilter = value),
                      ),
                    ],
                  );
                },
              ),
              const Gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  AppBadge(
                    label: 'Toplam: ${items.length}',
                    tone: AppBadgeTone.primary,
                  ),
                  AppBadge(
                    label: 'Seçili: ${selectedItems.length}',
                    tone: selectedItems.isEmpty
                        ? AppBadgeTone.neutral
                        : AppBadgeTone.success,
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || items.isEmpty
                        ? null
                        : () => setState(() {
                            if (selectedItems.length == items.length) {
                              _selectedKeys.clear();
                            } else {
                              _selectedKeys
                                ..clear()
                                ..addAll(items.map((item) => item.key));
                            }
                          }),
                    icon: const Icon(Icons.select_all_rounded, size: 18),
                    label: Text(
                      selectedItems.length == items.length && items.isNotEmpty
                          ? 'Seçimi Kaldır'
                          : 'Tümünü Seç',
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: _busy || selectedItems.isEmpty
                        ? null
                        : () => _downloadZip(selectedItems),
                    icon: const Icon(Icons.download_rounded, size: 18),
                    label: const Text('Toplu İndir'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy || selectedItems.isEmpty
                        ? null
                        : () => _deleteItems(selectedItems),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: const Text('Toplu Sil'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(12),
        if (items.isEmpty)
          const AppCard(
            child: Padding(
              padding: EdgeInsets.all(18),
              child: Center(child: Text('Filtreye uygun belge bulunamadı.')),
            ),
          )
        else
          for (final item in items) ...[
            _DocumentRow(
              item: item,
              selected: _selectedKeys.contains(item.key),
              busy: _busy,
              onSelected: (selected) => setState(() {
                if (selected) {
                  _selectedKeys.add(item.key);
                } else {
                  _selectedKeys.remove(item.key);
                }
              }),
              onDownload: () => _downloadItem(item),
              onDelete: () => _deleteItems([item]),
            ),
            const Gap(8),
          ],
      ],
    );
  }

  Future<Uint8List> _readItemBytes(_DocumentItem item) async {
    if (item.url.trim().isNotEmpty) {
      final response = await http.get(Uri.parse(item.url));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Dosya indirilemedi (${response.statusCode}).');
      }
      return response.bodyBytes;
    }
    final data = item.base64Data.trim();
    if (data.isEmpty) throw Exception('Dosya içeriği bulunamadı.');
    return base64Decode(data.replaceFirst(RegExp(r'^data:[^;]+;base64,'), ''));
  }

  Future<void> _downloadItem(_DocumentItem item) async {
    await _runBusy(() async {
      final bytes = await _readItemBytes(item);
      await downloadBinaryFile(
        bytes,
        item.downloadName,
        mimeType: item.mimeType,
      );
    });
  }

  Future<void> _downloadZip(List<_DocumentItem> items) async {
    await _runBusy(() async {
      final archive = Archive();
      for (final item in items) {
        final bytes = await _readItemBytes(item);
        archive.addFile(ArchiveFile(item.downloadName, bytes.length, bytes));
      }
      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null || zipBytes.isEmpty) {
        throw Exception('ZIP oluşturulamadı.');
      }
      final date = DateFormat('yyyy-MM-dd').format(DateTime.now());
      await downloadBinaryFile(
        zipBytes,
        'belgeler-$date.zip',
        mimeType: 'application/zip',
      );
    });
  }

  Future<void> _deleteItems(List<_DocumentItem> items) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Belgeleri sil'),
        content: Text(
          '${items.length} belge Storage/veritabanı kaydından silinecek. Devam edilsin mi?',
        ),
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

    await _runBusy(() async {
      final apiClient = ref.read(apiClientProvider);
      if (apiClient == null) throw Exception('API bağlantısı yok.');
      for (final item in items) {
        if (item.bucket.trim().isNotEmpty && item.path.trim().isNotEmpty) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'deleteStorageObject',
              'bucket': item.bucket,
              'path': item.path,
            },
          );
        }
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': item.sourceTable,
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': item.recordId},
            ],
            'values': item.clearValues,
          },
        );
      }
      _selectedKeys.removeAll(items.map((item) => item.key));
      ref.invalidate(applicationFormsProvider);
      ref.invalidate(scrapFormsProvider);
      ref.invalidate(faultFormsProvider);
      ref.invalidate(transferFormsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${items.length} belge silindi.')));
    });
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('İşlem tamamlanamadı: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _DocumentItem {
  const _DocumentItem({
    required this.key,
    required this.sourceTable,
    required this.recordId,
    required this.customerName,
    required this.registryNumber,
    required this.typeKey,
    required this.typeLabel,
    required this.fileName,
    required this.mimeType,
    required this.bucket,
    required this.path,
    required this.url,
    required this.base64Data,
    required this.clearValues,
  });

  final String key;
  final String sourceTable;
  final String recordId;
  final String customerName;
  final String registryNumber;
  final String typeKey;
  final String typeLabel;
  final String fileName;
  final String mimeType;
  final String bucket;
  final String path;
  final String url;
  final String base64Data;
  final Map<String, dynamic> clearValues;

  bool get inStorage => url.trim().isNotEmpty;
  String get storageKey => inStorage ? 'storage' : 'database';

  String get downloadName {
    final ext = mimeType == 'application/pdf'
        ? 'pdf'
        : mimeType == 'image/png'
        ? 'png'
        : 'jpg';
    final base = fileName.trim().isEmpty
        ? '$typeLabel-$customerName'
        : fileName.trim();
    final safe = base
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9ğüşöçıİĞÜŞÖÇ._-]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return safe.contains('.') ? safe : '$safe.$ext';
  }

  static Iterable<_DocumentItem> fromRecord(
    ApplicationFormRecord record,
  ) sync* {
    final taxpayerUrl = (record.taxpayerRegistrationDocumentUrl ?? '').trim();
    final taxpayerData = (record.taxpayerRegistrationDocumentData ?? '').trim();
    if (taxpayerUrl.isNotEmpty || taxpayerData.isNotEmpty) {
      yield _DocumentItem(
        key: '${record.id}:taxpayer',
        sourceTable: 'application_forms',
        recordId: record.id,
        customerName: record.customerName,
        registryNumber: record.fileRegistryNumber ?? '',
        typeKey: 'taxpayer',
        typeLabel: 'Yükümlü Belgesi',
        fileName:
            record.taxpayerRegistrationDocumentName ?? 'yukumlu-belgesi.pdf',
        mimeType:
            record.taxpayerRegistrationDocumentMimeType ?? 'application/pdf',
        bucket: record.taxpayerRegistrationDocumentStorageBucket ?? '',
        path: record.taxpayerRegistrationDocumentStoragePath ?? '',
        url: taxpayerUrl,
        base64Data: taxpayerData,
        clearValues: const {
          'taxpayer_registration_document_name': null,
          'taxpayer_registration_document_mime_type': null,
          'taxpayer_registration_document_data': null,
          'taxpayer_registration_document_storage_bucket': null,
          'taxpayer_registration_document_storage_path': null,
          'taxpayer_registration_document_url': null,
          'taxpayer_registration_document_uploaded_at': null,
        },
      );
    }
    final approvalUrl = (record.approvalDocumentUrl ?? '').trim();
    if (approvalUrl.isNotEmpty) {
      yield _DocumentItem(
        key: '${record.id}:approval',
        sourceTable: 'application_forms',
        recordId: record.id,
        customerName: record.customerName,
        registryNumber: record.fileRegistryNumber ?? '',
        typeKey: 'approval',
        typeLabel: 'Onay Belgesi',
        fileName: record.approvalDocumentName ?? 'onay-belgesi.pdf',
        mimeType: record.approvalDocumentMimeType ?? 'application/pdf',
        bucket: record.approvalDocumentStorageBucket ?? '',
        path: record.approvalDocumentStoragePath ?? '',
        url: approvalUrl,
        base64Data: '',
        clearValues: const {
          'approval_document_name': null,
          'approval_document_mime_type': null,
          'approval_document_storage_bucket': null,
          'approval_document_storage_path': null,
          'approval_document_url': null,
          'approval_document_uploaded_at': null,
        },
      );
    }
  }

  static Iterable<_DocumentItem> fromScrapForm(ScrapFormRecord record) sync* {
    final item = _fromFormDocument(
      recordId: record.id,
      sourceTable: 'scrap_forms',
      customerName: record.customerName,
      registryNumber: record.deviceBrandModelRegistry ?? '',
      typeKey: 'scrap',
      typeLabel: 'Hurda Formu',
      fallbackName: 'hurda-formu.pdf',
      documentName: record.documentName,
      mimeType: record.documentMimeType,
      bucket: record.documentStorageBucket,
      path: record.documentStoragePath,
      url: record.documentUrl,
    );
    if (item != null) yield item;
  }

  static Iterable<_DocumentItem> fromFaultForm(FaultFormRecord record) sync* {
    final item = _fromFormDocument(
      recordId: record.id,
      sourceTable: 'fault_forms',
      customerName: record.customerName,
      registryNumber: record.companyCodeAndRegistry ?? '',
      typeKey: 'fault',
      typeLabel: 'Arıza Formu',
      fallbackName: 'ariza-formu.pdf',
      documentName: record.documentName,
      mimeType: record.documentMimeType,
      bucket: record.documentStorageBucket,
      path: record.documentStoragePath,
      url: record.documentUrl,
    );
    if (item != null) yield item;
  }

  static Iterable<_DocumentItem> fromTransferForm(
    TransferFormRecord record,
  ) sync* {
    final item = _fromFormDocument(
      recordId: record.id,
      sourceTable: 'transfer_forms',
      customerName: '${record.transferorName} → ${record.transfereeName}',
      registryNumber: record.deviceSerialNo ?? '',
      typeKey: 'transfer',
      typeLabel: 'Devir Formu',
      fallbackName: 'devir-formu.pdf',
      documentName: record.documentName,
      mimeType: record.documentMimeType,
      bucket: record.documentStorageBucket,
      path: record.documentStoragePath,
      url: record.documentUrl,
    );
    if (item != null) yield item;
  }

  static _DocumentItem? _fromFormDocument({
    required String recordId,
    required String sourceTable,
    required String customerName,
    required String registryNumber,
    required String typeKey,
    required String typeLabel,
    required String fallbackName,
    required String? documentName,
    required String? mimeType,
    required String? bucket,
    required String? path,
    required String? url,
  }) {
    final documentUrl = (url ?? '').trim();
    if (documentUrl.isEmpty) return null;
    return _DocumentItem(
      key: '$recordId:$typeKey',
      sourceTable: sourceTable,
      recordId: recordId,
      customerName: customerName,
      registryNumber: registryNumber,
      typeKey: typeKey,
      typeLabel: typeLabel,
      fileName: documentName ?? fallbackName,
      mimeType: mimeType ?? 'application/pdf',
      bucket: bucket ?? '',
      path: path ?? '',
      url: documentUrl,
      base64Data: '',
      clearValues: const {
        'document_name': null,
        'document_mime_type': null,
        'document_storage_bucket': null,
        'document_storage_path': null,
        'document_url': null,
        'document_uploaded_at': null,
      },
    );
  }
}

class _FilterMenu extends StatelessWidget {
  const _FilterMenu({
    required this.width,
    required this.value,
    required this.icon,
    required this.items,
    required this.onChanged,
  });

  final double width;
  final String value;
  final IconData icon;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(
          prefixIcon: Icon(icon),
          border: const OutlineInputBorder(),
        ),
        items: [
          for (final entry in items.entries)
            DropdownMenuItem(
              value: entry.key,
              child: Text(entry.value, overflow: TextOverflow.ellipsis),
            ),
        ],
        onChanged: (value) {
          if (value != null) onChanged(value);
        },
      ),
    );
  }
}

class _DocumentRow extends StatelessWidget {
  const _DocumentRow({
    required this.item,
    required this.selected,
    required this.busy,
    required this.onSelected,
    required this.onDownload,
    required this.onDelete,
  });

  final _DocumentItem item;
  final bool selected;
  final bool busy;
  final ValueChanged<bool> onSelected;
  final VoidCallback onDownload;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 780;
    return AppCard(
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: _content(context, compact: true),
            )
          : Row(children: _content(context, compact: false)),
    );
  }

  List<Widget> _content(BuildContext context, {required bool compact}) {
    final title = Text(
      item.customerName,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
    final meta = Text(
      [
        item.fileName,
        if (item.registryNumber.trim().isNotEmpty) item.registryNumber.trim(),
      ].join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
    );
    final badges = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        AppBadge(
          label: item.typeLabel,
          tone: item.typeKey == 'approval'
              ? AppBadgeTone.success
              : AppBadgeTone.primary,
        ),
        AppBadge(
          label: item.inStorage ? 'Storage' : 'Veritabanı',
          tone: item.inStorage ? AppBadgeTone.success : AppBadgeTone.warning,
        ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: busy ? null : onDownload,
          icon: const Icon(Icons.download_rounded, size: 18),
          label: const Text('İndir'),
        ),
        OutlinedButton.icon(
          onPressed: busy ? null : onDelete,
          icon: const Icon(Icons.delete_outline_rounded, size: 18),
          label: const Text('Sil'),
        ),
      ],
    );
    if (compact) {
      return [
        Row(
          children: [
            Checkbox(value: selected, onChanged: (v) => onSelected(v ?? false)),
            Expanded(child: title),
          ],
        ),
        const Gap(4),
        meta,
        const Gap(8),
        badges,
        const Gap(10),
        actions,
      ];
    }
    return [
      Checkbox(value: selected, onChanged: (v) => onSelected(v ?? false)),
      const Gap(8),
      Expanded(
        flex: 30,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [title, const Gap(4), meta],
        ),
      ),
      const Gap(8),
      Expanded(flex: 18, child: badges),
      const Gap(8),
      SizedBox(width: 210, child: actions),
    ];
  }
}
