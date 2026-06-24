import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:http/http.dart' as http;

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../application_forms/application_document_scan.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';

class FormDocumentInfo {
  const FormDocumentInfo({
    required this.name,
    required this.mimeType,
    required this.bucket,
    required this.path,
    required this.url,
    required this.uploadedAt,
  });

  final String? name;
  final String? mimeType;
  final String? bucket;
  final String? path;
  final String? url;
  final DateTime? uploadedAt;

  bool get hasDocument => (url ?? '').trim().isNotEmpty;

  String get displayName {
    final value = (name ?? '').trim();
    return value.isEmpty ? 'Form belgesi' : value;
  }

  String get downloadName {
    final safe = displayName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9ğüşöçıİĞÜŞÖÇ._-]+', unicode: true), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (safe.contains('.')) return safe;
    final mime = (mimeType ?? '').toLowerCase();
    final ext = mime == 'application/pdf'
        ? 'pdf'
        : mime == 'image/png'
        ? 'png'
        : 'jpg';
    return '$safe.$ext';
  }
}

Future<void> handleFormDocumentAction({
  required BuildContext context,
  required WidgetRef ref,
  required String table,
  required String recordId,
  required String defaultFilename,
  required VoidCallback onChanged,
}) async {
  final action = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.document_scanner_rounded),
            title: const Text('Belge tara'),
            subtitle: const Text('Kamera ile belge yakala'),
            onTap: () => Navigator.of(context).pop('scan'),
          ),
          ListTile(
            leading: const Icon(Icons.attach_file_rounded),
            title: const Text('Dosya yükle'),
            subtitle: const Text('PDF, JPG veya PNG seç'),
            onTap: () => Navigator.of(context).pop('file'),
          ),
        ],
      ),
    ),
  );
  if (!context.mounted) return;
  if (action == 'scan') {
    await scanAndUploadFormDocument(
      context: context,
      ref: ref,
      table: table,
      recordId: recordId,
      defaultFilename: defaultFilename,
      onChanged: onChanged,
    );
  } else if (action == 'file') {
    await pickAndUploadFormDocument(
      context: context,
      ref: ref,
      table: table,
      recordId: recordId,
      defaultFilename: defaultFilename,
      onChanged: onChanged,
    );
  }
}

Future<void> scanAndUploadFormDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String table,
  required String recordId,
  required String defaultFilename,
  required VoidCallback onChanged,
}) async {
  try {
    final bytes = await scanSingleDocumentPage();
    if (bytes == null || bytes.isEmpty) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Tarama bu platformda kullanılamadı.')),
      );
      return;
    }
    if (!context.mounted) return;
    await uploadFormDocumentBytes(
      context: context,
      ref: ref,
      table: table,
      recordId: recordId,
      filename: _ensureExtension(defaultFilename, 'jpg'),
      mimeType: 'image/jpeg',
      bytes: bytes,
      onChanged: onChanged,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Belge taranamadı: $e')));
  }
}

Future<void> pickAndUploadFormDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String table,
  required String recordId,
  required String defaultFilename,
  required VoidCallback onChanged,
}) async {
  try {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf', 'jpg', 'jpeg', 'png'],
      withData: true,
    );
    final file = result?.files.single;
    final bytes = file?.bytes;
    if (file == null || bytes == null) return;
    if (!context.mounted) return;
    final ext = (file.extension ?? '').toLowerCase();
    final mimeType = ext == 'pdf'
        ? 'application/pdf'
        : ext == 'png'
        ? 'image/png'
        : 'image/jpeg';
    await uploadFormDocumentBytes(
      context: context,
      ref: ref,
      table: table,
      recordId: recordId,
      filename: file.name.trim().isEmpty ? defaultFilename : file.name,
      mimeType: mimeType,
      bytes: Uint8List.fromList(bytes),
      onChanged: onChanged,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Belge seçilemedi: $e')));
  }
}

Future<void> uploadFormDocumentBytes({
  required BuildContext context,
  required WidgetRef ref,
  required String table,
  required String recordId,
  required String filename,
  required String mimeType,
  required Uint8List bytes,
  required VoidCallback onChanged,
}) async {
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Belge yüklemek için API bağlantısı gerekir.'),
      ),
    );
    return;
  }
  if (bytes.length > 10 * 1024 * 1024) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Belge en fazla 10 MB olabilir.')),
    );
    return;
  }

  final uploaded = await apiClient.postJson(
    '/mutate',
    body: {
      'op': 'uploadFormDocument',
      'table': table,
      'recordId': recordId,
      'filename': filename,
      'contentType': mimeType,
      'data': base64Encode(bytes),
    },
  );
  await apiClient.postJson(
    '/mutate',
    body: {
      'op': 'updateWhere',
      'table': table,
      'filters': [
        {'col': 'id', 'op': 'eq', 'value': recordId},
      ],
      'values': {
        'document_name': filename,
        'document_mime_type': mimeType,
        'document_storage_bucket': uploaded['bucket'],
        'document_storage_path': uploaded['path'],
        'document_url': uploaded['url'],
        'document_uploaded_at': DateTime.now().toIso8601String(),
      },
    },
  );
  onChanged();
  if (!context.mounted) return;
  ScaffoldMessenger.of(
    context,
  ).showSnackBar(const SnackBar(content: Text('Belge yüklendi.')));
}

Future<void> downloadFormDocument({
  required BuildContext context,
  required FormDocumentInfo document,
}) async {
  try {
    final url = (document.url ?? '').trim();
    if (url.isEmpty) throw Exception('Belge URL bilgisi yok.');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Dosya indirilemedi (${response.statusCode}).');
    }
    await downloadBinaryFile(
      response.bodyBytes,
      document.downloadName,
      mimeType: document.mimeType ?? 'application/octet-stream',
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Belge indirilemedi: $e')));
  }
}

Future<void> clearFormDocument({
  required BuildContext context,
  required WidgetRef ref,
  required String table,
  required String recordId,
  required FormDocumentInfo document,
  required VoidCallback onChanged,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Belgeyi sil'),
      content: const Text('Yüklenen belge kaydı silinsin mi?'),
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

  try {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) throw Exception('API bağlantısı yok.');
    final bucket = (document.bucket ?? '').trim();
    final path = (document.path ?? '').trim();
    if (bucket.isNotEmpty && path.isNotEmpty) {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'deleteStorageObject', 'bucket': bucket, 'path': path},
      );
    }
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'updateWhere',
        'table': table,
        'filters': [
          {'col': 'id', 'op': 'eq', 'value': recordId},
        ],
        'values': const {
          'document_name': null,
          'document_mime_type': null,
          'document_storage_bucket': null,
          'document_storage_path': null,
          'document_url': null,
          'document_uploaded_at': null,
        },
      },
    );
    onChanged();
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Belge silindi.')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Belge silinemedi: $e')));
  }
}

class FormDocumentBadge extends StatelessWidget {
  const FormDocumentBadge({super.key, required this.document});

  final FormDocumentInfo document;

  @override
  Widget build(BuildContext context) {
    return AppBadge(
      label: document.hasDocument ? 'Belge Var' : 'Belge Yok',
      tone: document.hasDocument ? AppBadgeTone.success : AppBadgeTone.neutral,
    );
  }
}

class FormDocumentActions extends StatelessWidget {
  const FormDocumentActions({
    super.key,
    required this.document,
    required this.onUpload,
    required this.onDownload,
    required this.onDelete,
  });

  final FormDocumentInfo document;
  final VoidCallback onUpload;
  final VoidCallback? onDownload;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        FormRecordIconAction(
          tooltip: document.hasDocument ? 'Belgeyi Yenile' : 'Belge Tara/Yükle',
          onPressed: onUpload,
          icon: document.hasDocument
              ? Icons.upload_file_rounded
              : Icons.document_scanner_rounded,
        ),
        if (document.hasDocument) ...[
          const Gap(4),
          FormRecordIconAction(
            tooltip: 'Belgeyi İndir',
            onPressed: onDownload,
            icon: Icons.download_rounded,
          ),
          const Gap(4),
          FormRecordIconAction(
            tooltip: 'Belgeyi Sil',
            onPressed: onDelete,
            icon: Icons.delete_sweep_rounded,
          ),
        ],
      ],
    );
  }
}

class FormRecordIconAction extends StatelessWidget {
  const FormRecordIconAction({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.primary = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(width: 34, height: 34),
        style: IconButton.styleFrom(
          backgroundColor: primary ? AppTheme.primary : AppTheme.surfaceMuted,
          foregroundColor: primary ? Colors.white : AppTheme.text,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppTheme.radiusSm),
            side: BorderSide(
              color: primary ? AppTheme.primary : AppTheme.border,
            ),
          ),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
      ),
    );
  }
}

class FormDocumentMetaChip extends StatelessWidget {
  const FormDocumentMetaChip({super.key, required this.document});

  final FormDocumentInfo document;

  @override
  Widget build(BuildContext context) {
    if (!document.hasDocument) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.success.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.attach_file_rounded,
            size: 14,
            color: AppTheme.success,
          ),
          const Gap(6),
          Text(
            document.displayName,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AppTheme.success),
          ),
        ],
      ),
    );
  }
}

String _ensureExtension(String filename, String extension) {
  final clean = filename.trim().isEmpty ? 'form-belgesi' : filename.trim();
  if (clean.toLowerCase().endsWith('.$extension')) return clean;
  return '$clean.$extension';
}

String safeFormDocumentFilePart(String value) {
  final safe = value
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9ğüşöçıİĞÜŞÖÇ._-]+', unicode: true), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-|-$'), '');
  return safe.isEmpty ? 'form-belgesi' : safe;
}
