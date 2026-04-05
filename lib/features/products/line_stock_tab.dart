import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import '../stock/line_stock.dart';

class LineStockTab extends ConsumerStatefulWidget {
  const LineStockTab({super.key});

  @override
  ConsumerState<LineStockTab> createState() => _LineStockTabState();
}

class _LineStockTabState extends ConsumerState<LineStockTab> {
  late final TextEditingController _searchController;

  excel.CellValue _cell(Object? v) => excel.TextCellValue((v ?? '').toString());

  String _normalizeHeader(String value) {
    var t = value.trim().toLowerCase();
    t = t
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll('ğ', 'g')
        .replaceAll('Ğ', 'g')
        .replaceAll('ş', 's')
        .replaceAll('Ş', 's')
        .replaceAll('ç', 'c')
        .replaceAll('Ç', 'c')
        .replaceAll('ö', 'o')
        .replaceAll('Ö', 'o')
        .replaceAll('ü', 'u')
        .replaceAll('Ü', 'u');
    t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    t = t.replaceAll(RegExp(r'_+'), '_');
    t = t.replaceAll(RegExp(r'^_+|_+$'), '');
    return t;
  }

  String _coerceNumberLike(String raw) {
    final t = raw.trim();
    if (t.isEmpty) return '';
    final lowered = t.toLowerCase();
    if (lowered.contains('e')) {
      final d = double.tryParse(lowered.replaceAll('+', ''));
      if (d != null && d.isFinite) {
        return d.round().toString();
      }
    }
    if (RegExp(r'^\d+\.0+$').hasMatch(t)) {
      return t.split('.').first;
    }
    return t;
  }

  String? _toIsoDateTime(Object? raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toUtc().toIso8601String();
    if (raw is num && raw.isFinite) {
      final days = raw.round();
      if (days > 0) {
        final base = DateTime(1899, 12, 30);
        return base.add(Duration(days: days)).toUtc().toIso8601String();
      }
    }
    final text = _coerceNumberLike(raw.toString());
    if (text.isEmpty) return null;
    final normalized = text.replaceAll('/', '.');
    final dt = DateTime.tryParse(normalized);
    if (dt != null) return dt.toUtc().toIso8601String();
    final parts = normalized.split('.');
    if (parts.length == 3) {
      final d = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      final y = int.tryParse(parts[2]);
      if (d != null && m != null && y != null) {
        return DateTime(y, m, d).toUtc().toIso8601String();
      }
    }
    return null;
  }

  bool _toBool(String raw, {required bool defaultValue}) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return defaultValue;
    if (t == 'true' || t == '1' || t == 'aktif' || t == 'yes') return true;
    if (t == 'false' || t == '0' || t == 'pasif' || t == 'no') return false;
    return defaultValue;
  }

  @override
  void initState() {
    super.initState();
    _searchController =
        TextEditingController(text: ref.read(lineStockSearchProvider));
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _exportExcel(List<LineStockItem> items) async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışarı aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final book = excel.Excel.createExcel();
    final sheet = book['Hat Stok'];
    sheet.appendRow([
      _cell('operator'),
      _cell('line_number'),
      _cell('sim_number'),
      _cell('status'),
      _cell('is_active'),
      _cell('created_at'),
      _cell('consumed_at'),
    ]);
    for (final r in items) {
      sheet.appendRow([
        _cell(r.operatorName),
        _cell(r.lineNumber),
        _cell(r.simNumber ?? ''),
        _cell(r.isConsumed ? 'consumed' : 'available'),
        _cell(r.isActive.toString()),
        _cell(r.createdAt?.toIso8601String() ?? ''),
        _cell(r.consumedAt?.toIso8601String() ?? ''),
      ]);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'hat_stok.xlsx');
  }

  Future<void> _importExcel() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bağlantı bulunamadı.')),
      );
      return;
    }

    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İçe aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final picked = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
    );
    final bytes = picked?.files.single.bytes;
    if (bytes == null) return;

    final book = excel.Excel.decodeBytes(bytes);
    excel.Sheet? sheet;
    for (final name in book.tables.keys) {
      final key = name.trim().toLowerCase();
      if (key.contains('hat') && key.contains('stok')) {
        sheet = book.tables[name];
        break;
      }
      if (key == 'hat stok' || key == 'hat_stok' || key == 'line_stock') {
        sheet = book.tables[name];
        break;
      }
    }
    sheet ??= book.tables.values.isEmpty ? null : book.tables.values.first;
    if (sheet == null || sheet.rows.length < 2) return;

    final headerRow = sheet.rows.first;
    final header = <String, int>{};
    for (var i = 0; i < headerRow.length; i++) {
      final k = _normalizeHeader((headerRow[i]?.value ?? '').toString());
      if (k.isEmpty) continue;
      header.putIfAbsent(k, () => i);
    }

    int idxAny(List<String> keys) {
      for (final k in keys) {
        final normalized = _normalizeHeader(k);
        final index = header[normalized];
        if (index != null) return index;
      }
      return -1;
    }

    String cellString(List<excel.Data?> row, int index) {
      if (index < 0 || index >= row.length) return '';
      return _coerceNumberLike((row[index]?.value ?? '').toString()).trim();
    }

    Object? cellValue(List<excel.Data?> row, int index) {
      if (index < 0 || index >= row.length) return null;
      return row[index]?.value;
    }

    final opIndex = idxAny(['operator', 'operatör']);
    final numberIndex = idxAny(['line_number', 'number', 'hat_no', 'hat_numarasi', 'hat']);
    final simIndex = idxAny(['sim_number', 'sim_no', 'sim']);
    final activeIndex = idxAny(['is_active', 'aktif']);
    final statusIndex = idxAny(['status', 'durum']);
    final createdAtIndex = idxAny(['created_at', 'created']);
    final consumedAtIndex = idxAny(['consumed_at', 'kullanildi_at', 'used_at']);

    if (numberIndex < 0) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel kolonları bulunamadı: line_number')),
      );
      return;
    }

    final profile = await ref.read(currentUserProfileProvider.future);
    int imported = 0;
    final errors = <String>[];
    for (var i = 1; i < sheet.rows.length; i++) {
      final row = sheet.rows[i];
      final excelRowNo = i + 1;
      final lineNumber = cellString(row, numberIndex);
      if (lineNumber.isEmpty) continue;
      final operator = opIndex < 0 ? 'turkcell' : cellString(row, opIndex);
      final sim = simIndex < 0 ? '' : cellString(row, simIndex);
      final status = statusIndex < 0 ? '' : cellString(row, statusIndex);
      final statusNorm = status.trim().toLowerCase();

      final isActive = activeIndex < 0
          ? statusNorm == 'passive'
              ? false
              : true
          : _toBool(cellString(row, activeIndex), defaultValue: true);

      final createdAtIso = createdAtIndex < 0
          ? null
          : _toIsoDateTime(cellValue(row, createdAtIndex));
      final consumedAtIso = consumedAtIndex < 0
          ? null
          : _toIsoDateTime(cellValue(row, consumedAtIndex));

      final values = <String, dynamic>{
        'operator': normalizeOperator(operator),
        'line_number': lineNumber,
        'sim_number': sim.trim().isEmpty ? null : sim.trim(),
        'is_active': isActive,
        'created_by': profile?.id,
        ...?(() {
          if (createdAtIso == null) return null;
          return {'created_at': createdAtIso};
        })(),
      };
      if (consumedAtIso != null) {
        values['consumed_at'] = consumedAtIso;
      } else if (statusNorm == 'consumed') {
        values['consumed_at'] = DateTime.now().toUtc().toIso8601String();
      }

      try {
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {'op': 'upsert', 'table': 'line_stock', 'values': values},
          );
        } else {
          await client!.from('line_stock').upsert(
                values,
                onConflict: 'line_number_norm',
              );
        }
        imported += 1;
      } catch (e) {
        errors.add('Satır $excelRowNo: $e');
      }
    }

    ref.invalidate(lineStockProvider);
    ref.invalidate(lineStockAvailableProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'İçe aktarılan kayıt: $imported${errors.isEmpty ? '' : ' • Hata: ${errors.length}'}',
        ),
      ),
    );
  }

  Future<void> _showEditDialog({LineStockItem? initial}) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final operatorController = TextEditingController(
      text: initial == null ? 'turkcell' : normalizeOperator(initial.operatorName),
    );
    final lineController = TextEditingController(text: initial?.lineNumber ?? '');
    final simController = TextEditingController(text: initial?.simNumber ?? '');
    bool isActive = initial?.isActive ?? true;
    bool saving = false;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(initial == null ? 'Hat Stok Ekle' : 'Hat Stok Düzenle'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: operatorController.text,
                  items: const [
                    DropdownMenuItem(value: 'turkcell', child: Text('TURKCELL')),
                    DropdownMenuItem(value: 'telsim', child: Text('TELSİM')),
                  ],
                  onChanged: saving ? null : (v) => operatorController.text = v ?? 'turkcell',
                  decoration: const InputDecoration(labelText: 'Operatör'),
                ),
                const Gap(10),
                TextField(
                  controller: lineController,
                  decoration: const InputDecoration(labelText: 'Hat Numarası'),
                ),
                const Gap(10),
                TextField(
                  controller: simController,
                  decoration: const InputDecoration(labelText: 'SIM Numarası'),
                ),
                const Gap(10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: isActive,
                  onChanged: saving ? null : (v) => setState(() => isActive = v),
                  title: const Text('Aktif'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.of(context).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final lineNumber = lineController.text.trim();
                      if (lineNumber.isEmpty) return;
                      setState(() => saving = true);
                      try {
                        final profile =
                            await ref.read(currentUserProfileProvider.future);
                        await apiClient.postJson(
                          '/mutate',
                          body: {
                            'op': 'upsert',
                            'table': 'line_stock',
                            'values': {
                              if (initial != null) 'id': initial.id,
                              'operator': normalizeOperator(operatorController.text),
                              'line_number': lineNumber,
                              'sim_number': simController.text.trim().isEmpty
                                  ? null
                                  : simController.text.trim(),
                              'is_active': isActive,
                              'created_by': profile?.id,
                            },
                          },
                        );
                        if (!context.mounted) return;
                        Navigator.of(context).pop(true);
                      } catch (e) {
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Hata: $e')),
                        );
                        setState(() => saving = false);
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );

    if (result == true && mounted) {
      ref.invalidate(lineStockProvider);
    }
  }

  Future<void> _markAvailable(LineStockItem item) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'updateWhere',
        'table': 'line_stock',
        'filters': [
          {'col': 'id', 'op': 'eq', 'value': item.id},
        ],
        'values': {
          'consumed_at': null,
          'consumed_by': null,
          'consumed_customer_id': null,
          'consumed_work_order_id': null,
          'consumed_line_id': null,
        },
      },
    );
    ref.invalidate(lineStockProvider);
    ref.invalidate(lineStockAvailableProvider);
  }

  Future<void> _setActive(LineStockItem item, bool active) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'updateWhere',
        'table': 'line_stock',
        'filters': [
          {'col': 'id', 'op': 'eq', 'value': item.id},
        ],
        'values': {'is_active': active},
      },
    );
    ref.invalidate(lineStockProvider);
    ref.invalidate(lineStockAvailableProvider);
  }

  Future<void> _delete(LineStockItem item) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hat stok silinsin mi?'),
        content: Text(
          [
            item.lineNumber,
            if ((item.simNumber ?? '').trim().isNotEmpty) 'SIM: ${item.simNumber}',
          ].join('\n'),
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
    if (ok != true) return;
    await apiClient.postJson(
      '/mutate',
      body: {'op': 'delete', 'table': 'line_stock', 'id': item.id},
    );
    ref.invalidate(lineStockProvider);
    ref.invalidate(lineStockAvailableProvider);
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(lineStockProvider);
    final status = ref.watch(lineStockStatusProvider);
    final operatorName = ref.watch(lineStockOperatorProvider);
    final items = itemsAsync.asData?.value ?? const <LineStockItem>[];

    final totalCount = items.length;
    final activeCount = items.where((e) => e.isActive).length;
    final availableCount = items.where((e) => e.isActive && !e.isConsumed).length;
    final consumedCount = items.where((e) => e.isConsumed).length;

    return Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.all(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 980;
                final searchField = SizedBox(
                  width: narrow ? double.infinity : 320,
                  child: TextField(
                    controller: _searchController,
                    onChanged: ref.read(lineStockSearchProvider.notifier).set,
                    decoration: const InputDecoration(
                      hintText: 'Ara (hat, sim, müşteri...)',
                      prefixIcon: Icon(Icons.search_rounded),
                      isDense: true,
                    ),
                  ),
                );

                final statusField = SizedBox(
                  width: narrow ? double.infinity : 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: status,
                    items: const [
                      DropdownMenuItem(value: 'available', child: Text('Hazır')),
                      DropdownMenuItem(value: 'consumed', child: Text('Kullanıldı')),
                      DropdownMenuItem(value: 'passive', child: Text('Pasif')),
                      DropdownMenuItem(value: 'all', child: Text('Tümü')),
                    ],
                    onChanged: (v) => ref
                        .read(lineStockStatusProvider.notifier)
                        .set(v ?? 'available'),
                    decoration: const InputDecoration(labelText: 'Durum', isDense: true),
                  ),
                );

                final operatorField = SizedBox(
                  width: narrow ? double.infinity : 220,
                  child: DropdownButtonFormField<String>(
                    initialValue: operatorName,
                    items: const [
                      DropdownMenuItem(value: 'all', child: Text('Tüm Operatörler')),
                      DropdownMenuItem(value: 'turkcell', child: Text('TURKCELL')),
                      DropdownMenuItem(value: 'telsim', child: Text('TELSİM')),
                    ],
                    onChanged: (v) => ref
                        .read(lineStockOperatorProvider.notifier)
                        .set(v ?? 'all'),
                    decoration: const InputDecoration(labelText: 'Operatör', isDense: true),
                  ),
                );

                final addBtn = FilledButton.icon(
                  onPressed: () => _showEditDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Hat Ekle'),
                );

                final importBtn = OutlinedButton.icon(
                  onPressed: _importExcel,
                  icon: const Icon(Icons.upload_file_rounded, size: 18),
                  label: const Text('İçe Aktar'),
                );

                final exportBtn = OutlinedButton.icon(
                  onPressed: items.isEmpty ? null : () => _exportExcel(items),
                  icon: const Icon(Icons.download_rounded, size: 18),
                  label: const Text('Dışarı Aktar'),
                );

                final summary = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AppBadge(
                      label: 'Toplam: $totalCount',
                      tone: AppBadgeTone.neutral,
                      dense: true,
                    ),
                    AppBadge(
                      label: 'Aktif: $activeCount',
                      tone: AppBadgeTone.primary,
                      dense: true,
                    ),
                    AppBadge(
                      label: 'Hazır: $availableCount',
                      tone: AppBadgeTone.success,
                      dense: true,
                    ),
                    AppBadge(
                      label: 'Kullanıldı: $consumedCount',
                      tone: AppBadgeTone.warning,
                      dense: true,
                    ),
                  ],
                );

                if (narrow) {
                  return Column(
                    children: [
                      searchField,
                      const Gap(8),
                      statusField,
                      const Gap(8),
                      operatorField,
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: addBtn),
                          const Gap(8),
                          Expanded(child: exportBtn),
                        ],
                      ),
                      const Gap(8),
                      Row(
                        children: [
                          Expanded(child: importBtn),
                          const Gap(8),
                          Expanded(child: summary),
                        ],
                      ),
                    ],
                  );
                }

                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    searchField,
                    statusField,
                    operatorField,
                    addBtn,
                    importBtn,
                    exportBtn,
                    summary,
                  ],
                );
              },
            ),
          ),
          const Gap(8),
          Expanded(
            child: itemsAsync.when(
              data: (items) {
                if (items.isEmpty) return const _Empty(text: 'Kayıt yok.');
                return Scrollbar(
                  thumbVisibility: true,
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: items.length,
                    separatorBuilder: (_, _) => const Gap(8),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      final op = normalizeOperator(item.operatorName);
                      final opLabel = op == 'turkcell'
                          ? 'TURKCELL'
                          : op == 'telsim'
                              ? 'TELSİM'
                              : (item.operatorName.trim().isEmpty ? '-' : item.operatorName);
                      final isAvailable = item.isActive && !item.isConsumed;
                      return Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF8FAFC),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                [
                                  item.lineNumber,
                                  if ((item.simNumber ?? '').trim().isNotEmpty)
                                    'SIM: ${item.simNumber}',
                                ].join(' • '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: const Color(0xFF0F172A),
                                    ),
                              ),
                            ),
                            const Gap(8),
                            AppBadge(
                              label: opLabel,
                              tone: op == 'turkcell'
                                  ? AppBadgeTone.primary
                                  : op == 'telsim'
                                      ? AppBadgeTone.warning
                                      : AppBadgeTone.neutral,
                              dense: true,
                            ),
                            const Gap(6),
                            AppBadge(
                              label: isAvailable ? 'Hazır' : (item.isConsumed ? 'Kullanıldı' : 'Pasif'),
                              tone: isAvailable
                                  ? AppBadgeTone.success
                                  : (item.isConsumed ? AppBadgeTone.warning : AppBadgeTone.neutral),
                              dense: true,
                            ),
                            const Gap(8),
                            PopupMenuButton<String>(
                              tooltip: 'İşlem',
                              onSelected: (value) async {
                                if (value == 'edit') {
                                  await _showEditDialog(initial: item);
                                }
                                if (value == 'available') {
                                  await _markAvailable(item);
                                }
                                if (value == 'passive') {
                                  await _setActive(item, false);
                                }
                                if (value == 'active') {
                                  await _setActive(item, true);
                                }
                                if (value == 'delete') {
                                  await _delete(item);
                                }
                              },
                              itemBuilder: (context) => [
                                const PopupMenuItem(
                                  value: 'edit',
                                  child: Text('Düzenle'),
                                ),
                                if (item.isConsumed)
                                  const PopupMenuItem(
                                    value: 'available',
                                    child: Text('Hazır Yap'),
                                  ),
                                if (item.isActive)
                                  const PopupMenuItem(
                                    value: 'passive',
                                    child: Text('Pasife Al'),
                                  )
                                else
                                  const PopupMenuItem(
                                    value: 'active',
                                    child: Text('Aktif Yap'),
                                  ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: Text('Sil'),
                                ),
                              ],
                              child: const SizedBox(
                                width: 36,
                                height: 34,
                                child: Icon(Icons.more_horiz_rounded),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const _Empty(text: 'Hat stok yüklenemedi.'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AppCard(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            text,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: const Color(0xFF64748B)),
          ),
        ),
      ),
    );
  }
}
