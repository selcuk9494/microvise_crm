import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:signature/signature.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'service_definitions.dart';
import 'service_share.dart';

final serviceDetailProvider =
    FutureProvider.family<ServiceDetail, String>((ref, serviceId) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) throw Exception('API bağlantısı yok.');
  final row = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'service_detail', 'serviceId': serviceId},
  );
  if (row.isEmpty) throw Exception('Servis kaydı bulunamadı.');
  return ServiceDetail.fromJson(row);
});

class ServiceDetailScreen extends ConsumerStatefulWidget {
  const ServiceDetailScreen({super.key, required this.serviceId});

  final String serviceId;

  @override
  ConsumerState<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends ConsumerState<ServiceDetailScreen> {
  final _bodyKey = GlobalKey<_BodyState>();

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(serviceDetailProvider(widget.serviceId));

    return detailAsync.when(
      data: (detail) => AppPageLayout(
        title: 'Servis',
        subtitle: detail.title,
        actions: [
          Builder(
            builder: (context) {
              final accessoryAsync = ref.watch(serviceAccessoryTypesProvider);
              final accessoryNames = accessoryAsync.asData?.value
                      .where((e) => detail.accessoryTypeIds.contains(e.id))
                      .map((e) => e.name)
                      .toList(growable: false) ??
                  detail.accessoryTypeIds.toList(growable: false);

              return OutlinedButton.icon(
                onPressed: () async {
                  try {
                    await shareServicePdf(
                      detail: detail,
                      accessoryNames: accessoryNames,
                    );
                  } catch (_) {}
                },
                icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                label: const Text('PDF'),
              );
            },
          ),
          FilledButton.icon(
            onPressed: () async {
              await _bodyKey.currentState?._captureSignatures(delivery: true);
              ref.invalidate(serviceDetailProvider(widget.serviceId));
            },
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Teslim'),
          ),
        ],
        body: SingleChildScrollView(
          primary: true,
          child: _Body(
            key: _bodyKey,
            detail: detail,
            onChanged: () => ref.invalidate(serviceDetailProvider(widget.serviceId)),
          ),
        ),
      ),
      loading: () => const AppPageLayout(
        title: 'Servis',
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => AppPageLayout(
        title: 'Servis',
        body: AppCard(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Servis kaydı yüklenemedi.',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: const Color(0xFF64748B)),
            ),
          ),
        ),
      ),
    );
  }

  
}

class _Body extends ConsumerStatefulWidget {
  const _Body({super.key, required this.detail, required this.onChanged});

  final ServiceDetail detail;
  final VoidCallback onChanged;

  @override
  ConsumerState<_Body> createState() => _BodyState();
}

class _BodyState extends ConsumerState<_Body> {
  late List<TextEditingController> _stepControllers;
  late List<_LineItemDraft> _parts;
  late List<_LineItemDraft> _labor;
  late final TextEditingController _registryController;
  late final TextEditingController _notesController;
  String? _faultTypeId;
  bool _accessoriesReceived = false;
  final Set<String> _selectedAccessoryTypeIds = {};
  List<String> _deviceImages = const [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _stepControllers = [
      for (final s in widget.detail.steps) TextEditingController(text: s),
    ];
    _parts = widget.detail.parts.map(_LineItemDraft.from).toList();
    _labor = widget.detail.labor.map(_LineItemDraft.from).toList();
    _registryController = TextEditingController(text: widget.detail.registryNumber ?? '');
    _notesController = TextEditingController(text: widget.detail.notes ?? '');
    _faultTypeId = (widget.detail.faultTypeId ?? '').trim().isEmpty
        ? null
        : widget.detail.faultTypeId;
    _accessoriesReceived = widget.detail.accessoriesReceived;
    _selectedAccessoryTypeIds
      ..clear()
      ..addAll(widget.detail.accessoryTypeIds);
    _deviceImages = widget.detail.deviceImageDataUrls;
  }

  @override
  void didUpdateWidget(covariant _Body oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.detail.id != widget.detail.id) return;
    final nextReg = widget.detail.registryNumber ?? '';
    if (_registryController.text != nextReg) {
      _registryController.text = nextReg;
    }
    final nextNotes = widget.detail.notes ?? '';
    if (_notesController.text != nextNotes) {
      _notesController.text = nextNotes;
    }
    if (oldWidget.detail.steps != widget.detail.steps) {
      for (final c in _stepControllers) {
        c.dispose();
      }
      _stepControllers = [
        for (final s in widget.detail.steps) TextEditingController(text: s),
      ];
    }
    _faultTypeId = (widget.detail.faultTypeId ?? '').trim().isEmpty
        ? null
        : widget.detail.faultTypeId;
    _accessoriesReceived = widget.detail.accessoriesReceived;
    _selectedAccessoryTypeIds
      ..clear()
      ..addAll(widget.detail.accessoryTypeIds);
    _deviceImages = widget.detail.deviceImageDataUrls;
  }

  @override
  void dispose() {
    for (final c in _stepControllers) {
      c.dispose();
    }
    _registryController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  double get _total {
    double sum = 0;
    for (final p in _parts) {
      sum += p.total;
    }
    for (final l in _labor) {
      sum += l.total;
    }
    return sum;
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    setState(() => _saving = true);
    try {
      final steps = _stepControllers
          .map((e) => e.text.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'service_records',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
          ],
          'values': {
            'steps': steps,
            'parts': _parts.map((e) => e.toJson()).toList(),
            'labor': _labor.map((e) => e.toJson()).toList(),
            'total_amount': _total,
          },
        },
      );

      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendToApproval() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final steps = _stepControllers
        .map((e) => e.text.trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
    if (steps.isEmpty && _parts.isEmpty && _labor.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce yapılan işlem / parça / işçilik ekleyin.')),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'service_records',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
          ],
          'values': {
            'status': 'approval',
            'steps': steps,
            'parts': _parts.map((e) => e.toJson()).toList(),
            'labor': _labor.map((e) => e.toJson()).toList(),
            'total_amount': _total,
          },
        },
      );
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Onaya gönderildi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _markReady() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'service_records',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
          ],
          'values': {'status': 'ready'},
        },
      );
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hazır durumuna alındı.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveInfo() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'service_records',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
          ],
          'values': {
            'registry_number': _registryController.text.trim().isEmpty
                ? null
                : _registryController.text.trim(),
            'fault_type_id': (_faultTypeId ?? '').trim().isEmpty ? null : _faultTypeId,
            'accessories_received': _accessoriesReceived,
            'accessory_type_ids': _selectedAccessoryTypeIds.toList(growable: false),
            'notes':
                _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
            'device_images': _deviceImages
                .map((e) => {'data_url': e})
                .toList(growable: false),
          },
        },
      );
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kaydedilemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setStatus(String status) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'service_records',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
          ],
          'values': {'status': status},
        },
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _dataUrl(Uint8List bytes, String mimeType) =>
      'data:$mimeType;base64,${base64Encode(bytes)}';

  Future<void> _addImage(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source,
      imageQuality: 75,
      maxWidth: 1400,
    );
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (bytes.isEmpty) return;

    final name = picked.name.toLowerCase();
    final mime = name.endsWith('.png') ? 'image/png' : 'image/jpeg';
    final url = _dataUrl(bytes, mime);
    setState(() => _deviceImages = [..._deviceImages, url]);
    await _saveInfo();
  }

  Future<void> _captureSignatures({required bool delivery}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final left = SignatureController(
      penStrokeWidth: 2.5,
      penColor: const Color(0xFF0F172A),
    );
    final right = SignatureController(
      penStrokeWidth: 2.5,
      penColor: const Color(0xFF0F172A),
    );
    bool markDone = delivery;

    try {
      final saved = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => Dialog(
          insetPadding: const EdgeInsets.all(24),
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: AppCard(
              padding: const EdgeInsets.all(16),
              child: StatefulBuilder(
                builder: (context, setState) {
                  final leftTitle = delivery ? 'Teslim Eden (Personel)' : 'Teslim Eden (Müşteri)';
                  final rightTitle = delivery ? 'Teslim Alan (Müşteri)' : 'Teslim Alan (Personel)';
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              delivery ? 'Teslim İmzaları' : 'Teslim Alma İmzaları',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                          ),
                          IconButton(
                            tooltip: 'Kapat',
                            onPressed: () => Navigator.of(context).pop(false),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                      const Gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: _SignaturePad(
                              title: leftTitle,
                              controller: left,
                              enabled: !_saving,
                            ),
                          ),
                          const Gap(12),
                          Expanded(
                            child: _SignaturePad(
                              title: rightTitle,
                              controller: right,
                              enabled: !_saving,
                            ),
                          ),
                        ],
                      ),
                      if (delivery) ...[
                        const Gap(8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: markDone,
                          onChanged: (v) => setState(() => markDone = v),
                          title: const Text('Servisi Teslim Et (Durum: Teslim)'),
                        ),
                      ],
                      const Gap(12),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () {
                                left.clear();
                                right.clear();
                              },
                              child: const Text('Temizle'),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: FilledButton(
                              onPressed: () => Navigator.of(context).pop(true),
                              child: const Text('Kaydet'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      );
      if (saved != true) return;

      final leftBytes = await left.toPngBytes();
      final rightBytes = await right.toPngBytes();
      final leftUrl =
          leftBytes == null || leftBytes.isEmpty ? null : _dataUrl(leftBytes, 'image/png');
      final rightUrl =
          rightBytes == null || rightBytes.isEmpty ? null : _dataUrl(rightBytes, 'image/png');

      setState(() => _saving = true);
      try {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'service_records',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.detail.id},
            ],
            'values': {
              if (delivery) ...{
                'delivery_personnel_signature_data_url': leftUrl,
                'delivery_customer_signature_data_url': rightUrl,
                if (markDone) 'status': 'done',
              } else ...{
                'intake_customer_signature_data_url': leftUrl,
                'intake_personnel_signature_data_url': rightUrl,
              },
            },
          },
        );
        widget.onChanged();
      } finally {
        if (mounted) setState(() => _saving = false);
      }

      final accessoryAsync = ref.read(serviceAccessoryTypesProvider);
      final accessoryNames = accessoryAsync.asData?.value
              .where((e) => widget.detail.accessoryTypeIds.contains(e.id))
              .map((e) => e.name)
              .toList(growable: false) ??
          widget.detail.accessoryTypeIds.toList(growable: false);
      try {
        await shareServicePdf(detail: widget.detail, accessoryNames: accessoryNames);
      } catch (_) {}
    } finally {
      left.dispose();
      right.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final date = DateFormat('d MMM y', 'tr_TR').format(widget.detail.createdAt);
    final status = switch (widget.detail.status) {
      'open' || 'waiting' => ('Bekliyor', AppBadgeTone.warning),
      'in_progress' || 'approval' => ('Onayda', AppBadgeTone.primary),
      'ready' => ('Hazır', AppBadgeTone.success),
      'done' => ('Teslim', AppBadgeTone.neutral),
      _ => (widget.detail.status, AppBadgeTone.neutral),
    };

    return Column(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.detail.customerName ?? '—',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  AppBadge(label: status.$1, tone: status.$2),
                  if (widget.detail.status == 'waiting' || widget.detail.status == 'open') ...[
                    const Gap(8),
                    FilledButton.tonal(
                      onPressed: _saving ? null : _sendToApproval,
                      child: const Text('Onaya Gönder'),
                    ),
                  ],
                  if (widget.detail.status == 'approval' || widget.detail.status == 'in_progress') ...[
                    const Gap(8),
                    FilledButton.tonal(
                      onPressed: _saving ? null : _markReady,
                      child: const Text('Hazır'),
                    ),
                  ],
                  const Gap(8),
                  PopupMenuButton<String>(
                    tooltip: 'Durum Değiştir',
                    enabled: !_saving,
                    onSelected: (v) async {
                      await _setStatus(v);
                    },
                    itemBuilder: (context) => const [
                      PopupMenuItem(value: 'waiting', child: Text('Bekliyor')),
                      PopupMenuItem(value: 'approval', child: Text('Onayda')),
                      PopupMenuItem(value: 'ready', child: Text('Hazır')),
                      PopupMenuItem(value: 'done', child: Text('Teslim')),
                    ],
                    child: const SizedBox(
                      width: 36,
                      height: 34,
                      child: Icon(Icons.more_horiz_rounded),
                    ),
                  ),
                ],
              ),
              const Gap(6),
              Text(
                date,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: const Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Servis Bilgileri',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  OutlinedButton(
                    onPressed: _saving ? null : _saveInfo,
                    child: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Kaydet'),
                  ),
                ],
              ),
              const Gap(10),
              TextField(
                controller: _registryController,
                decoration: const InputDecoration(
                  labelText: 'Sicil No',
                  hintText: 'SN...',
                ),
              ),
              const Gap(10),
              ref.watch(serviceFaultTypesProvider).when(
                    data: (items) => DropdownButtonFormField<String?>(
                      initialValue: (_faultTypeId ?? '').trim().isEmpty ? null : _faultTypeId,
                      items: [
                        const DropdownMenuItem<String?>(
                          value: null,
                          child: Text('Arıza Tipi (opsiyonel)'),
                        ),
                        for (final t in items)
                          DropdownMenuItem<String?>(
                            value: t.id,
                            child: Text(t.name),
                          ),
                      ],
                      onChanged:
                          _saving ? null : (v) => setState(() => _faultTypeId = v),
                      decoration: const InputDecoration(labelText: 'Arıza Tipi'),
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (_, _) => const SizedBox.shrink(),
                  ),
              const Gap(8),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                value: _accessoriesReceived,
                onChanged: _saving
                    ? null
                    : (v) => setState(() {
                          _accessoriesReceived = v;
                          if (!v) _selectedAccessoryTypeIds.clear();
                        }),
                title: const Text('Aksesuar Teslim Alındı'),
              ),
              if (_accessoriesReceived) ...[
                ref.watch(serviceAccessoryTypesProvider).when(
                      data: (items) => Column(
                        children: [
                          for (final t in items)
                            CheckboxListTile(
                              contentPadding: EdgeInsets.zero,
                              value: _selectedAccessoryTypeIds.contains(t.id),
                              onChanged: _saving
                                  ? null
                                  : (v) => setState(() {
                                        if (v == true) {
                                          _selectedAccessoryTypeIds.add(t.id);
                                        } else {
                                          _selectedAccessoryTypeIds.remove(t.id);
                                        }
                                      }),
                              title: Text(t.name),
                            ),
                        ],
                      ),
                      loading: () => const SizedBox.shrink(),
                      error: (_, _) => const SizedBox.shrink(),
                    ),
              ],
              const Gap(10),
              TextField(
                controller: _notesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Not',
                ),
              ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fotoğraflar & İmzalar',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _captureSignatures(delivery: false),
                    icon: const Icon(Icons.edit_rounded, size: 18),
                    label: const Text('Teslim Alım İmza'),
                  ),
                  const Gap(8),
                  FilledButton.icon(
                    onPressed: _saving ? null : () => _captureSignatures(delivery: true),
                    icon: const Icon(Icons.check_rounded, size: 18),
                    label: const Text('Teslim İmza'),
                  ),
                ],
              ),
              const Gap(10),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _addImage(ImageSource.camera),
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Kamera'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _addImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Galeri'),
                  ),
                ],
              ),
              const Gap(10),
              if (_deviceImages.isEmpty)
                Text(
                  'Fotoğraf yok.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                )
              else
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (int i = 0; i < _deviceImages.length; i++)
                      _ImageThumb(
                        dataUrl: _deviceImages[i],
                        onRemove: _saving
                            ? null
                            : () async {
                                setState(() {
                                  _deviceImages = [
                                    for (int j = 0; j < _deviceImages.length; j++)
                                      if (j != i) _deviceImages[j],
                                  ];
                                });
                                await _saveInfo();
                              },
                      ),
                  ],
                ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text('Adımlar', style: Theme.of(context).textTheme.titleSmall),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving
                        ? null
                        : () => setState(() => _stepControllers.add(TextEditingController(text: 'Yeni adım'))),
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
              const Gap(10),
              for (int i = 0; i < _stepControllers.length; i++) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 26,
                      height: 26,
                      decoration: BoxDecoration(
                        color: AppTheme.primary.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.18)),
                      ),
                      child: Center(
                        child: Text(
                          '${i + 1}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: AppTheme.primary,
                              ),
                        ),
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextField(
                        controller: _stepControllers[i],
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                        ),
                      ),
                    ),
                    const Gap(10),
                    IconButton(
                      tooltip: 'Sil',
                      onPressed: _saving
                          ? null
                          : () => setState(() {
                                _stepControllers[i].dispose();
                                _stepControllers.removeAt(i);
                              }),
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
                if (i != _stepControllers.length - 1) const Gap(10),
              ],
              const Gap(12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(12),
        _CostCard(
          title: 'Parçalar',
          items: _parts,
          onAdd: _saving ? null : () => setState(() => _parts.add(_LineItemDraft.empty())),
          onRemove: _saving
              ? null
              : (i) => setState(() {
                    _parts[i].dispose();
                    _parts.removeAt(i);
                  }),
        ),
        const Gap(12),
        _CostCard(
          title: 'İşçilik',
          items: _labor,
          onAdd: _saving ? null : () => setState(() => _labor.add(_LineItemDraft.empty())),
          onRemove: _saving
              ? null
              : (i) => setState(() {
                    _labor[i].dispose();
                    _labor.removeAt(i);
                  }),
        ),
        const Gap(12),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Toplam',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              Text(
                NumberFormat.currency(locale: 'tr_TR', symbol: '₺', decimalDigits: 2)
                    .format(_total),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({required this.dataUrl, required this.onRemove});

  final String dataUrl;
  final VoidCallback? onRemove;

  Uint8List? _decode() {
    final raw = dataUrl.trim();
    final idx = raw.indexOf('base64,');
    if (idx < 0) return null;
    final b64 = raw.substring(idx + 'base64,'.length).trim();
    if (b64.isEmpty) return null;
    try {
      return base64Decode(b64);
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = _decode();
    return Stack(
      children: [
        Container(
          width: 140,
          height: 110,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
            color: const Color(0xFFF8FAFC),
          ),
          child: bytes == null
              ? const Center(child: Icon(Icons.image_not_supported_outlined))
              : ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(bytes, fit: BoxFit.cover),
                ),
        ),
        if (onRemove != null)
          Positioned(
            right: 6,
            top: 6,
            child: InkWell(
              onTap: onRemove,
              borderRadius: BorderRadius.circular(14),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: const Icon(Icons.close_rounded, size: 18),
              ),
            ),
          ),
      ],
    );
  }
}

class _SignaturePad extends StatelessWidget {
  const _SignaturePad({
    required this.title,
    required this.controller,
    required this.enabled,
  });

  final String title;
  final SignatureController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: Theme.of(context).textTheme.titleSmall),
        const Gap(8),
        Container(
          height: 160,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.border),
            color: const Color(0xFFF8FAFC),
          ),
          child: IgnorePointer(
            ignoring: !enabled,
            child: Signature(
              controller: controller,
              backgroundColor: Colors.transparent,
            ),
          ),
        ),
      ],
    );
  }
}

class _CostCard extends StatelessWidget {
  const _CostCard({
    required this.title,
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final String title;
  final List<_LineItemDraft> items;
  final VoidCallback? onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(title, style: Theme.of(context).textTheme.titleSmall),
              ),
              OutlinedButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Ekle'),
              ),
            ],
          ),
          const Gap(10),
          if (items.isEmpty)
            Text(
              'Kayıt yok.',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: const Color(0xFF64748B)),
            )
          else
            for (int i = 0; i < items.length; i++) ...[
              _LineItemEditor(
                item: items[i],
                onRemove: onRemove == null ? null : () => onRemove!(i),
              ),
              if (i != items.length - 1) const Gap(10),
            ],
        ],
      ),
    );
  }
}

class _LineItemEditor extends StatelessWidget {
  const _LineItemEditor({required this.item, required this.onRemove});

  final _LineItemDraft item;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: TextField(
            controller: item.nameController,
            decoration: const InputDecoration(labelText: 'Kalem'),
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 2,
          child: TextField(
            controller: item.qtyController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Adet/Saat'),
          ),
        ),
        const Gap(10),
        Expanded(
          flex: 3,
          child: TextField(
            controller: item.unitPriceController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Birim Fiyat'),
          ),
        ),
        const Gap(10),
        if (onRemove != null)
          IconButton(
            tooltip: 'Sil',
            onPressed: onRemove,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
      ],
    );
  }
}

class _LineItemDraft {
  _LineItemDraft({
    required this.nameController,
    required this.qtyController,
    required this.unitPriceController,
  });

  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;

  factory _LineItemDraft.empty() => _LineItemDraft(
        nameController: TextEditingController(),
        qtyController: TextEditingController(text: '1'),
        unitPriceController: TextEditingController(text: '0'),
      );

  factory _LineItemDraft.from(Map<String, dynamic> json) {
    return _LineItemDraft(
      nameController: TextEditingController(text: json['name']?.toString() ?? ''),
      qtyController: TextEditingController(text: json['qty']?.toString() ?? '1'),
      unitPriceController:
          TextEditingController(text: json['unit_price']?.toString() ?? '0'),
    );
  }

  double get qty => double.tryParse(qtyController.text.trim().replaceAll(',', '.')) ?? 0;
  double get unitPrice =>
      double.tryParse(unitPriceController.text.trim().replaceAll(',', '.')) ?? 0;
  double get total => qty * unitPrice;

  Map<String, dynamic> toJson() {
    return {
      'name': nameController.text.trim(),
      'qty': qty,
      'unit_price': unitPrice,
    };
  }

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
  }
}

class ServiceDetail {
  const ServiceDetail({
    required this.id,
    required this.serviceNo,
    required this.title,
    required this.status,
    required this.priority,
    required this.createdAt,
    required this.appointmentAt,
    required this.isActive,
    required this.notes,
    required this.registryNumber,
    required this.faultTypeId,
    required this.faultTypeName,
    required this.faultDescription,
    required this.deviceBrand,
    required this.deviceModel,
    required this.deviceSerial,
    required this.technicianId,
    required this.technicianName,
    required this.accessoriesReceived,
    required this.accessoryTypeIds,
    required this.deviceImageDataUrls,
    required this.intakeCustomerSignatureDataUrl,
    required this.intakePersonnelSignatureDataUrl,
    required this.deliveryCustomerSignatureDataUrl,
    required this.deliveryPersonnelSignatureDataUrl,
    required this.currency,
    required this.totalAmount,
    required this.steps,
    required this.parts,
    required this.labor,
    required this.customerId,
    required this.workOrderId,
    required this.customerName,
    required this.customerEmail,
  });

  final String id;
  final int? serviceNo;
  final String title;
  final String status;
  final String? priority;
  final DateTime createdAt;
  final DateTime? appointmentAt;
  final bool isActive;
  final String? notes;
  final String? registryNumber;
  final String? faultTypeId;
  final String? faultTypeName;
  final String? faultDescription;
  final String? deviceBrand;
  final String? deviceModel;
  final String? deviceSerial;
  final String? technicianId;
  final String? technicianName;
  final bool accessoriesReceived;
  final List<String> accessoryTypeIds;
  final List<String> deviceImageDataUrls;
  final String? intakeCustomerSignatureDataUrl;
  final String? intakePersonnelSignatureDataUrl;
  final String? deliveryCustomerSignatureDataUrl;
  final String? deliveryPersonnelSignatureDataUrl;
  final String? currency;
  final double? totalAmount;
  final List<String> steps;
  final List<Map<String, dynamic>> parts;
  final List<Map<String, dynamic>> labor;
  final String? customerId;
  final String? workOrderId;
  final String? customerName;
  final String? customerEmail;

  factory ServiceDetail.fromJson(Map<String, dynamic> json) {
    final customers = json['customers'] as Map<String, dynamic>?;
    final stepsRaw = json['steps'];
    final partsRaw = json['parts'];
    final laborRaw = json['labor'];
    final accessoryIdsRaw = json['accessory_type_ids'];
    final deviceImagesRaw = json['device_images'];

    int? toIntAny(Object? v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '');
    }

    double? toDoubleAny(Object? v) {
      if (v is double) return v;
      if (v is num) return v.toDouble();
      return double.tryParse(v?.toString() ?? '');
    }

    return ServiceDetail(
      id: json['id'].toString(),
      serviceNo: toIntAny(json['service_no']),
      title: (json['title'] ?? '').toString(),
      status: (json['status'] ?? 'open').toString(),
      priority: json['priority']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ??
          DateTime.now(),
      appointmentAt: DateTime.tryParse(json['appointment_at']?.toString() ?? ''),
      isActive: json['is_active'] as bool? ?? true,
      notes: json['notes']?.toString(),
      registryNumber: json['registry_number']?.toString(),
      faultTypeId: json['fault_type_id']?.toString(),
      faultTypeName: json['fault_type_name']?.toString(),
      faultDescription: json['fault_description']?.toString(),
      deviceBrand: json['device_brand']?.toString(),
      deviceModel: json['device_model']?.toString(),
      deviceSerial: json['device_serial']?.toString(),
      technicianId: json['technician_id']?.toString(),
      technicianName: json['technician_name']?.toString(),
      accessoriesReceived: json['accessories_received'] as bool? ?? false,
      accessoryTypeIds: (accessoryIdsRaw is List)
          ? accessoryIdsRaw.map((e) => e.toString()).toList(growable: false)
          : const [],
      deviceImageDataUrls: (deviceImagesRaw is List)
          ? deviceImagesRaw
              .map((e) {
                if (e is String) return e;
                if (e is Map) {
                  return (e['data_url'] ?? e['url'] ?? '').toString();
                }
                return '';
              })
              .where((e) => e.trim().isNotEmpty)
              .toList(growable: false)
          : const [],
      intakeCustomerSignatureDataUrl:
          json['intake_customer_signature_data_url']?.toString(),
      intakePersonnelSignatureDataUrl:
          json['intake_personnel_signature_data_url']?.toString(),
      deliveryCustomerSignatureDataUrl:
          json['delivery_customer_signature_data_url']?.toString(),
      deliveryPersonnelSignatureDataUrl:
          json['delivery_personnel_signature_data_url']?.toString(),
      currency: json['currency']?.toString(),
      totalAmount: toDoubleAny(json['total_amount']),
      steps: (stepsRaw is List)
          ? stepsRaw.map((e) => e.toString()).toList()
          : const [],
      parts: (partsRaw is List)
          ? partsRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
          : const [],
      labor: (laborRaw is List)
          ? laborRaw.map((e) => (e as Map).cast<String, dynamic>()).toList()
          : const [],
      customerId: json['customer_id']?.toString(),
      workOrderId: json['work_order_id']?.toString(),
      customerName: customers?['name']?.toString(),
      customerEmail: customers?['email']?.toString(),
    );
  }
}
