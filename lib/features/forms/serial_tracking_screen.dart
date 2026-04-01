import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

class SerialTrackingItem {
  const SerialTrackingItem({
    required this.id,
    required this.productName,
    required this.serialNumber,
    required this.isActive,
    required this.createdAt,
  });

  final String id;
  final String productName;
  final String serialNumber;
  final bool isActive;
  final DateTime? createdAt;

  factory SerialTrackingItem.fromJson(Map<String, dynamic> json) {
    return SerialTrackingItem(
      id: json['id']?.toString() ?? '',
      productName: (json['product_name'] ?? '').toString(),
      serialNumber: (json['serial_number'] ?? '').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString()),
    );
  }
}

final serialTrackingProvider =
    FutureProvider<List<SerialTrackingItem>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'serial_tracking'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => e.cast<String, dynamic>())
      .map(SerialTrackingItem.fromJson)
      .toList(growable: false);
});

class SerialTrackingScreen extends ConsumerStatefulWidget {
  const SerialTrackingScreen({super.key});

  @override
  ConsumerState<SerialTrackingScreen> createState() =>
      _SerialTrackingScreenState();
}

class _SerialTrackingScreenState extends ConsumerState<SerialTrackingScreen> {
  final _searchController = TextEditingController();
  bool _showPassive = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(serialTrackingProvider);
    final search = _searchController.text.trim().toLowerCase();

    return AppPageLayout(
      title: 'Seri Takip',
      subtitle: 'Ürün adı ve sicil no kayıtlarını yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(serialTrackingProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: () => _openBulkEditor(),
          icon: const Icon(Icons.playlist_add_rounded, size: 18),
          label: const Text('Toplu Giriş'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: () => _openEditor(),
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Kayıt'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: 'Ara',
                    ),
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: () => setState(() => _showPassive = !_showPassive),
                  icon: const Icon(Icons.circle_rounded, size: 12),
                  label: Text(_showPassive ? 'Durum: Tümü' : 'Durum: Aktif'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        const Color(0xFF7C3AED).withValues(alpha: 0.12),
                    foregroundColor: const Color(0xFF4C1D95),
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Gap(12),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                final filtered = items.where((item) {
                  if (!_showPassive && !item.isActive) return false;
                  if (search.isEmpty) return true;
                  final haystack = '${item.serialNumber} ${item.productName}'
                      .toLowerCase();
                  return haystack.contains(search);
                }).toList(growable: false);

                if (filtered.isEmpty) {
                  return const AppCard(
                    child: Center(child: Text('Kayıt bulunamadı.')),
                  );
                }

                return AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Container(
                        height: 42,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceMuted,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(AppTheme.radiusMd),
                          ),
                          border:
                              Border(bottom: BorderSide(color: AppTheme.border)),
                        ),
                        child: Row(
                          children: const [
                            SizedBox(width: 260, child: _HeaderCell('Sicil No')),
                            SizedBox(width: 520, child: _HeaderCell('Ürün İsmi')),
                            SizedBox(width: 120, child: _HeaderCell('Durum')),
                            Spacer(),
                            SizedBox(width: 120, child: _HeaderCell('İşlem')),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: filtered.length,
                          itemBuilder: (context, index) => _SerialTableRow(
                            item: filtered[index],
                            onChanged: () =>
                                ref.invalidate(serialTrackingProvider),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (error, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Seri takip yüklenemedi: $error',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditor({SerialTrackingItem? initial}) async {
    final productController =
        TextEditingController(text: initial?.productName ?? '');
    final serialController =
        TextEditingController(text: initial?.serialNumber ?? '');
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          initial == null ? 'Seri Ekle' : 'Seri Düzenle',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed:
                            saving ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(12),
                  TextField(
                    controller: productController,
                    decoration: const InputDecoration(
                      labelText: 'Ürün İsmi',
                      hintText: 'Örn: Yazarkasa POS',
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: serialController,
                    decoration: const InputDecoration(
                      labelText: 'Ürün Sicil No',
                      hintText: 'Örn: 123456789',
                    ),
                  ),
                  const Gap(18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final productName =
                                      productController.text.trim();
                                  final serialNumber =
                                      serialController.text.trim();
                                  if (productName.isEmpty) return;
                                  if (serialNumber.isEmpty) return;

                                  final apiClient = ref.read(apiClientProvider);
                                  if (apiClient == null) return;

                                  setState(() => saving = true);
                                  try {
                                    final profile = await ref
                                        .read(currentUserProfileProvider.future);
                                    await apiClient.postJson(
                                      '/mutate',
                                      body: {
                                        'op': 'upsert',
                                        'table': 'serial_tracking',
                                        'values': {
                                          if (initial != null) 'id': initial.id,
                                          'product_name': productName,
                                          'serial_number': serialNumber,
                                          'is_active': initial?.isActive ?? true,
                                          'created_by': profile?.id,
                                        },
                                      },
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(true);
                                  } finally {
                                    setState(() => saving = false);
                                  }
                                },
                          child: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : Text(initial == null ? 'Ekle' : 'Kaydet'),
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

    productController.dispose();
    serialController.dispose();

    if (saved == true) {
      ref.invalidate(serialTrackingProvider);
    }
  }

  Future<void> _openBulkEditor() async {
    final productController = TextEditingController(text: 'ÖKC');
    final serialsController = TextEditingController();
    bool saving = false;
    int savedCount = 0;

    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Toplu Seri Girişi',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed:
                            saving ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(12),
                  TextField(
                    controller: productController,
                    decoration: const InputDecoration(
                      labelText: 'Ürün İsmi',
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: serialsController,
                    minLines: 6,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: 'Ürün Sicil No(ları)',
                      hintText: 'Alt alta veya virgülle yapıştırın',
                      alignLabelWithHint: true,
                    ),
                  ),
                  const Gap(12),
                  if (saving)
                    Text(
                      'Kaydediliyor: $savedCount',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: AppTheme.textMuted),
                    ),
                  const Gap(18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final productName =
                                      productController.text.trim();
                                  final raw = serialsController.text;
                                  final serials = raw
                                      .split(RegExp(r'[\n,;]+'))
                                      .map((e) => e.trim().toUpperCase())
                                      .where((e) => e.isNotEmpty)
                                      .toSet()
                                      .toList(growable: false);
                                  if (productName.isEmpty || serials.isEmpty) {
                                    return;
                                  }

                                  final apiClient = ref.read(apiClientProvider);
                                  if (apiClient == null) return;

                                  setState(() {
                                    saving = true;
                                    savedCount = 0;
                                  });

                                  try {
                                    for (final serial in serials) {
                                      await apiClient.postJson(
                                        '/mutate',
                                        body: {
                                          'op': 'upsert',
                                          'table': 'serial_tracking',
                                          'values': {
                                            'product_name': productName,
                                            'serial_number': serial,
                                            'is_active': true,
                                          },
                                        },
                                      );
                                      setState(() => savedCount += 1);
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(true);
                                  } finally {
                                    setState(() => saving = false);
                                  }
                                },
                          child: const Text('Kaydet'),
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

    productController.dispose();
    serialsController.dispose();

    if (ok == true) {
      ref.invalidate(serialTrackingProvider);
    }
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
          ),
    );
  }
}

class _SerialTableRow extends ConsumerStatefulWidget {
  const _SerialTableRow({required this.item, required this.onChanged});

  final SerialTrackingItem item;
  final VoidCallback onChanged;

  @override
  ConsumerState<_SerialTableRow> createState() => _SerialTableRowState();
}

class _SerialTableRowState extends ConsumerState<_SerialTableRow> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final badge = item.isActive
        ? const AppBadge(label: 'Aktif', tone: AppBadgeTone.success)
        : const AppBadge(label: 'Pasif', tone: AppBadgeTone.neutral);

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 260,
            child: Text(
              item.serialNumber,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: AppTheme.primary,
                  ),
            ),
          ),
          SizedBox(
            width: 520,
            child: Text(
              item.productName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
            ),
          ),
          SizedBox(
            width: 120,
            child: Align(alignment: Alignment.centerLeft, child: badge),
          ),
          const Spacer(),
          SizedBox(
            width: 120,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: 'Düzenle',
                  onPressed: _saving
                      ? null
                      : () => (context.findAncestorStateOfType<
                              _SerialTrackingScreenState>())
                          ?._openEditor(initial: item),
                  icon: const Icon(Icons.edit_outlined),
                ),
                IconButton(
                  tooltip: item.isActive ? 'Pasife Al' : 'Aktifleştir',
                  onPressed: _saving ? null : _toggleActive,
                  icon: Icon(item.isActive
                      ? Icons.pause_circle_outline_rounded
                      : Icons.play_circle_outline_rounded),
                ),
                IconButton(
                  tooltip: 'Sil',
                  onPressed: _saving ? null : _delete,
                  icon: const Icon(Icons.delete_outline_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleActive() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'serial_tracking',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.item.id},
          ],
          'values': {'is_active': !widget.item.isActive},
        },
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Sil'),
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

    setState(() => _saving = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'delete', 'table': 'serial_tracking', 'id': widget.item.id},
      );
      widget.onChanged();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
