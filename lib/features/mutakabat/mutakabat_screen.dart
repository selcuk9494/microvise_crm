import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/feature_access_gate.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import 'mutakabat_model.dart';

final mutakabatListProvider = FutureProvider<List<MutakabatRecord>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'mutakabat_list'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(MutakabatRecord.fromJson)
      .toList(growable: false);
});

final mutakabatDetailProvider = FutureProvider.family<MutakabatRecord?, String>((
  ref,
  id,
) async {
  if (id.trim().isEmpty) return null;
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return null;
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'mutakabat_detail', 'id': id},
  );
  final item = response['item'];
  if (item is! Map<String, dynamic>) return null;
  return MutakabatRecord.fromJson(item);
});

final mutakabatPriceSettingsProvider =
    FutureProvider<List<MutakabatPriceSetting>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null) return const [];
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'mutakabat_price_settings_list'},
      );
      return ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MutakabatPriceSetting.fromJson)
          .toList(growable: false);
    });

class MutakabatScreen extends ConsumerStatefulWidget {
  const MutakabatScreen({super.key, this.openPrices = false});

  final bool openPrices;

  @override
  ConsumerState<MutakabatScreen> createState() => _MutakabatScreenState();
}

class _MutakabatScreenState extends ConsumerState<MutakabatScreen> {
  String? _selectedId;
  bool _creating = false;
  bool _busy = false;

  bool get _showPrices => widget.openPrices;

  @override
  Widget build(BuildContext context) {
    return FeatureAccessGate(
      pageKey: kPageMutakabat,
      child: AppPageLayout(
        title: _showPrices ? 'Birim Fiyatlar' : 'Mutakabat',
        subtitle: _showPrices
            ? 'INGENICO / PAX kademeli fiyatları ve YKB tek banka fiyatını buradan girin.'
            : 'Aylık Worldline / Microvise banka ve entegrasyon mutabakatını yönetin.',
        actions: [
          if (!_showPrices)
            FilledButton.icon(
              onPressed: _busy ? null : () => context.go('/mutakabat/fiyatlar'),
              icon: const Icon(LucideIcons.badgeCent, size: 18),
              label: const Text('Birim Fiyatlar'),
            )
          else
            OutlinedButton.icon(
              onPressed: _busy ? null : () => context.go('/mutakabat'),
              icon: const Icon(LucideIcons.arrowLeft, size: 18),
              label: const Text('Kayıtlara Dön'),
            ),
          if (!_showPrices)
            OutlinedButton.icon(
              onPressed: _busy
                  ? null
                  : () {
                      setState(() {
                        _creating = true;
                        _selectedId = null;
                      });
                    },
              icon: const Icon(LucideIcons.plus, size: 18),
              label: const Text('Yeni Mutakabat'),
            ),
          OutlinedButton.icon(
            onPressed: () {
              ref.invalidate(mutakabatListProvider);
              ref.invalidate(mutakabatPriceSettingsProvider);
            },
            icon: const Icon(LucideIcons.refreshCw, size: 18),
            label: const Text('Yenile'),
          ),
        ],
        body: _showPrices
            ? _MutakabatPriceSettingsPane(
                busy: _busy,
                onBusyChanged: (value) => setState(() => _busy = value),
              )
            : ref.watch(mutakabatListProvider).when(
          data: (records) {
            final effectiveId = _effectiveSelectedId(records);
            if (!_creating &&
                records.isNotEmpty &&
                effectiveId != null &&
                effectiveId != _selectedId) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!mounted) return;
                setState(() => _selectedId = effectiveId);
              });
            }
            if (_creating) {
              return _MutakabatEditor(
                busy: _busy,
                onBusyChanged: (value) => setState(() => _busy = value),
                onSaved: _handleSaved,
                onCancel: () => setState(() {
                  _creating = false;
                  if (_selectedId == null && records.isNotEmpty) {
                    _selectedId = records.first.id;
                  }
                }),
              );
            }
            if (records.isEmpty) {
              return EmptyStateCard(
                icon: LucideIcons.calendarDays,
                title: 'Kayıt yok',
                message:
                    'Önce birim fiyatları girin, sonra Yeni Mutakabat ile Excel yükleyin.',
                action: FilledButton.icon(
                  onPressed: () => context.go('/mutakabat/fiyatlar'),
                  icon: const Icon(LucideIcons.badgeCent, size: 18),
                  label: const Text('Birim Fiyatları Gir'),
                ),
              );
            }
            if (effectiveId == null) {
              return const Center(child: CircularProgressIndicator());
            }
            return _MutakabatDetailPane(
              recordId: effectiveId,
              records: records,
              busy: _busy,
              onBusyChanged: (value) => setState(() => _busy = value),
              onSelectPeriod: (id) => setState(() {
                _selectedId = id;
                _creating = false;
              }),
              onDeleted: () {
                ref.invalidate(mutakabatListProvider);
                setState(() => _selectedId = null);
              },
              onUpdated: _handleSaved,
            );
          },
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, _) => const Center(child: Text('Mutakabat listesi yüklenemedi.')),
        ),
      ),
    );
  }

  String? _effectiveSelectedId(List<MutakabatRecord> records) {
    if (records.isEmpty) return null;
    if (_selectedId != null &&
        records.any((record) => record.id == _selectedId)) {
      return _selectedId;
    }
    return records.first.id;
  }

  void _handleSaved(String id) {
    ref.invalidate(mutakabatListProvider);
    ref.invalidate(mutakabatDetailProvider(id));
    setState(() {
      _selectedId = id;
      _creating = false;
    });
  }
}

class _MutakabatDetailPane extends ConsumerWidget {
  const _MutakabatDetailPane({
    required this.recordId,
    required this.records,
    required this.busy,
    required this.onBusyChanged,
    required this.onDeleted,
    required this.onUpdated,
    required this.onSelectPeriod,
  });

  final String recordId;
  final List<MutakabatRecord> records;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final VoidCallback onDeleted;
  final ValueChanged<String> onUpdated;
  final ValueChanged<String> onSelectPeriod;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(mutakabatDetailProvider(recordId));
    return detailAsync.when(
      data: (record) {
        if (record == null) {
          return const EmptyStateCard(
            icon: LucideIcons.circleAlert,
            title: 'Kayıt bulunamadı',
            message: 'Seçilen mutakabat kaydı silinmiş olabilir.',
          );
        }
        return ListView(
          children: [
            _MutakabatHeader(
              record: record,
              records: records,
              busy: busy,
              onSelectPeriod: onSelectPeriod,
              onExport: () => _exportRecord(context, ref, record),
              onDelete: () => _deleteRecord(context, ref, record.id),
              onEdit: () async {
                await showDialog<void>(
                  context: context,
                  builder: (context) => Dialog(
                    insetPadding: const EdgeInsets.all(24),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 980),
                      child: _MutakabatEditor(
                        initialRecord: record,
                        busy: busy,
                        onBusyChanged: onBusyChanged,
                        onSaved: onUpdated,
                        onCancel: () => Navigator.of(context).pop(),
                      ),
                    ),
                  ),
                );
              },
            ),
            const Gap(12),
            _MutakabatDashboardWithFilters(summary: record.summary),
            if (record.notes.trim().isNotEmpty) ...[
              const Gap(12),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Notlar',
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Gap(8),
                    Text(record.notes),
                  ],
                ),
              ),
            ],
          ],
        );
      },
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) => const Center(child: Text('Mutakabat detayı yüklenemedi.')),
    );
  }

  Future<void> _exportRecord(
    BuildContext context,
    WidgetRef ref,
    MutakabatRecord record,
  ) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    onBusyChanged(true);
    try {
      final response = await apiClient.postJson('/mutate', body: {
        'op': 'exportMutakabatExcel',
        'id': record.id,
      });
      final bytes = base64Decode(response['dataBase64']?.toString() ?? '');
      await downloadExcelFile(
        bytes,
        response['filename']?.toString() ??
            'mutakabat_${record.periodYear}_${record.periodMonth}.xlsx',
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel dosyası hazırlandı.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel dışa aktarılamadı.')),
      );
    } finally {
      onBusyChanged(false);
    }
  }

  Future<void> _deleteRecord(
    BuildContext context,
    WidgetRef ref,
    String id,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mutakabat silinsin mi?'),
        content: const Text(
          'Kayıt pasife alınır ve listeden kaldırılır. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    onBusyChanged(true);
    try {
      await apiClient.postJson('/mutate', body: {
        'op': 'updateWhere',
        'table': 'mutakabat_records',
        'filters': [
          {'col': 'id', 'op': 'eq', 'value': id},
        ],
        'values': {'is_active': false},
      });
      onDeleted();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mutakabat kaydı silindi.')),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Silme işlemi başarısız.')),
      );
    } finally {
      onBusyChanged(false);
    }
  }
}

class _MutakabatHeader extends StatelessWidget {
  const _MutakabatHeader({
    required this.record,
    required this.records,
    required this.busy,
    required this.onExport,
    required this.onDelete,
    required this.onEdit,
    required this.onSelectPeriod,
  });

  final MutakabatRecord record;
  final List<MutakabatRecord> records;
  final bool busy;
  final VoidCallback onExport;
  final VoidCallback onDelete;
  final VoidCallback onEdit;
  final ValueChanged<String> onSelectPeriod;

  Future<void> _pickPeriod(BuildContext context) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dönem seç'),
          content: SizedBox(
            width: 360,
            child: records.isEmpty
                ? const Text('Kayıtlı dönem yok.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: records.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final item = records[index];
                      final isCurrent = item.id == record.id;
                      return ListTile(
                        selected: isCurrent,
                        title: Text(
                          item.periodLabel,
                          style: TextStyle(
                            fontWeight:
                                isCurrent ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                        subtitle: Text(
                          item.title.trim().isEmpty
                              ? 'Microvise / Worldline mutabakatı'
                              : item.title,
                        ),
                        trailing: isCurrent
                            ? Icon(LucideIcons.check, color: AppTheme.primary)
                            : null,
                        onTap: () => Navigator.of(context).pop(item.id),
                      );
                    },
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Kapat'),
            ),
          ],
        );
      },
    );
    if (selected == null || selected == record.id) return;
    onSelectPeriod(selected);
  }

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  onTap: busy ? null : () => _pickPeriod(context),
                  borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            record.periodLabel,
                            style: Theme.of(context)
                                .textTheme
                                .headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        const Gap(6),
                        Icon(
                          LucideIcons.chevronDown,
                          size: 20,
                          color: AppTheme.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                const Gap(4),
                Text(
                  record.title.trim().isEmpty
                      ? 'Worldline / Microvise mutabakat özeti'
                      : record.title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
                const Gap(8),
                OutlinedButton.icon(
                  onPressed: busy ? null : () => _pickPeriod(context),
                  icon: const Icon(LucideIcons.calendarDays, size: 16),
                  label: Text(
                    records.length <= 1
                        ? 'Dönem seç'
                        : 'Dönem seç (${records.length})',
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: busy ? null : onEdit,
                icon: const Icon(LucideIcons.pencil, size: 18),
                label: const Text('Düzenle'),
              ),
              FilledButton.icon(
                onPressed: busy ? null : onExport,
                icon: const Icon(LucideIcons.download, size: 18),
                label: const Text('Excel Aktar'),
              ),
              OutlinedButton.icon(
                onPressed: busy ? null : onDelete,
                icon: const Icon(LucideIcons.trash2, size: 18),
                label: const Text('Sil'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Microvise navy / Worldline teal — Excel dashboard renkleri.
const Color _kMicrovise = Color(0xFF1E3A5F);
const Color _kMicroviseSoft = Color(0xFFE8EEF5);
const Color _kWorldline = Color(0xFF277777);
const Color _kWorldlineSoft = Color(0xFFE3F5F2);

class _MutakabatDashboardWithFilters extends StatefulWidget {
  const _MutakabatDashboardWithFilters({required this.summary});

  final MutakabatSummary summary;

  @override
  State<_MutakabatDashboardWithFilters> createState() =>
      _MutakabatDashboardWithFiltersState();
}

class _MutakabatDashboardWithFiltersState
    extends State<_MutakabatDashboardWithFilters> {
  String _bankGroup = 'ALL';
  String _integrationKey = 'ALL';

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat.currency(locale: 'tr_TR', symbol: '₺');
    final summary = widget.summary;

    List<MutakabatLineItem> linesFor(String group) {
      if (_bankGroup != 'ALL' && _bankGroup != group) return const [];
      var items = summary.lineItems.where((e) => e.group == group).toList();
      if (group == 'YKB (Koop Bank)' && items.isNotEmpty) {
        final qty = items.fold<int>(0, (s, e) => s + e.quantity);
        final unit = items
            .map((e) => e.unitPrice)
            .firstWhere((p) => p > 0, orElse: () => items.first.unitPrice);
        final world = items.fold<double>(0, (s, e) => s + e.worldlineAmount);
        items = [
          MutakabatLineItem(
            group: group,
            bankTier: 1,
            label: '1 Banka',
            quantity: qty,
            unitPrice: unit,
            microviseAmount: 0,
            worldlineAmount: world > 0 ? world : qty * unit,
          ),
        ];
      }
      return items.where((e) => e.quantity > 0).toList(growable: false);
    }

    ({int qty, double micro, double world}) totalsOf(
      List<MutakabatLineItem> items,
    ) {
      return (
        qty: items.fold<int>(0, (s, e) => s + e.quantity),
        micro: items.fold<double>(0, (s, e) => s + e.microviseAmount),
        world: items.fold<double>(0, (s, e) => s + e.worldlineAmount),
      );
    }

    final ingenico = linesFor('INGENICO');
    final pax = linesFor('PAX (A910SF)');
    final ykb = linesFor('YKB (Koop Bank)');
    final ingenicoT = totalsOf(ingenico);
    final paxT = totalsOf(pax);
    final ykbT = totalsOf(ykb);

    final integrations = summary.integrations.where((i) {
      if (_integrationKey == 'ALL') return true;
      return i.key == _integrationKey;
    }).toList(growable: false);

    final integQty = integrations.fold<int>(0, (s, e) => s + e.quantity);
    final integAmount =
        integrations.fold<double>(0, (s, e) => s + e.worldlineAmount);

    final showMicro =
        _bankGroup == 'ALL' ||
        _bankGroup == 'INGENICO' ||
        _bankGroup == 'PAX (A910SF)';
    final showWorldSection =
        _bankGroup == 'ALL' || _bankGroup == 'YKB (Koop Bank)';
    final showYkbRows =
        _bankGroup == 'ALL' || _bankGroup == 'YKB (Koop Bank)';
    final showIntegRows = _bankGroup == 'ALL';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 220,
                child: DropdownButtonFormField<String>(
                  initialValue: _bankGroup,
                  decoration: const InputDecoration(
                    labelText: 'Banka grubu',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tümü')),
                    DropdownMenuItem(
                      value: 'INGENICO',
                      child: Text('INGENICO'),
                    ),
                    DropdownMenuItem(
                      value: 'PAX (A910SF)',
                      child: Text('PAX (A910SF)'),
                    ),
                    DropdownMenuItem(
                      value: 'YKB (Koop Bank)',
                      child: Text('YKB (Koop Bank)'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _bankGroup = value);
                  },
                ),
              ),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _integrationKey,
                  decoration: const InputDecoration(
                    labelText: 'Entegrasyon',
                    isDense: true,
                  ),
                  items: const [
                    DropdownMenuItem(value: 'ALL', child: Text('Tümü')),
                    DropdownMenuItem(value: 'gmp3', child: Text('GMP3')),
                    DropdownMenuItem(value: 'tsm', child: Text('TSM')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _integrationKey = value);
                  },
                ),
              ),
            ],
          ),
          const Gap(16),
          LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= 640;
              final cards = [
                _InvoiceTotalCard(
                  label: 'Microvise Keseceği Fatura',
                  value: money.format(summary.totals.microviseGrand),
                  color: _kMicrovise,
                  soft: _kMicroviseSoft,
                ),
                _InvoiceTotalCard(
                  label: 'Worldline Keseceği Fatura',
                  value: money.format(summary.totals.worldlineGrand),
                  color: _kWorldline,
                  soft: _kWorldlineSoft,
                ),
              ];
              if (wide) {
                return Row(
                  children: [
                    Expanded(child: cards[0]),
                    const Gap(12),
                    Expanded(child: cards[1]),
                  ],
                );
              }
              return Column(
                children: [
                  cards[0],
                  const Gap(12),
                  cards[1],
                ],
              );
            },
          ),
          if (showMicro) ...[
            const Gap(20),
            _SectionBanner(
              title: 'A) Microvise Keseceği Fatura',
              color: _kMicrovise,
            ),
            const Gap(10),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final ingenicoTable = _ExcelSectionTable(
                  title: 'INGENICO BANKA',
                  headerColor: _kMicrovise,
                  softColor: _kMicroviseSoft,
                  amountHeader: 'Microvise',
                  rows: [
                    for (final item in ingenico)
                      [
                        item.label,
                        '${item.quantity}',
                        money.format(item.unitPrice),
                        money.format(item.microviseAmount),
                      ],
                  ],
                  footerLabel: 'INGENICO TOPLAM',
                  footerQty: '${ingenicoT.qty}',
                  footerAmount: money.format(ingenicoT.micro),
                );
                final paxTable = _ExcelSectionTable(
                  title: 'PAX BANKA',
                  headerColor: _kMicrovise,
                  softColor: _kMicroviseSoft,
                  amountHeader: 'Microvise',
                  rows: [
                    for (final item in pax)
                      [
                        item.label,
                        '${item.quantity}',
                        money.format(item.unitPrice),
                        money.format(item.microviseAmount),
                      ],
                  ],
                  footerLabel: 'PAX TOPLAM',
                  footerQty: '${paxT.qty}',
                  footerAmount: money.format(paxT.micro),
                );
                if (_bankGroup == 'INGENICO') return ingenicoTable;
                if (_bankGroup == 'PAX (A910SF)') return paxTable;
                if (wide) {
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: ingenicoTable),
                      const Gap(12),
                      Expanded(child: paxTable),
                    ],
                  );
                }
                return Column(
                  children: [
                    ingenicoTable,
                    const Gap(12),
                    paxTable,
                  ],
                );
              },
            ),
            const Gap(10),
            _GrandTotalBar(
              label: 'A) Microvise Genel Toplam',
              value: money.format(
                _bankGroup == 'INGENICO'
                    ? ingenicoT.micro
                    : _bankGroup == 'PAX (A910SF)'
                        ? paxT.micro
                        : summary.totals.microviseGrand,
              ),
              color: _kMicrovise,
            ),
          ],
          if (showWorldSection) ...[
            const Gap(20),
            _SectionBanner(
              title: 'B) Worldline Keseceği Fatura',
              color: _kWorldline,
            ),
            const Gap(10),
            _ExcelSectionTable(
              title: 'YKB / GMP3 / TSM',
              headerColor: _kWorldline,
              softColor: _kWorldlineSoft,
              columns: const [
                'Banka',
                'Entegrasyon',
                'Adet',
                'Birim Fiyat',
                'Worldline',
              ],
              rows: [
                if (showYkbRows)
                  for (final item in ykb)
                    [
                      'YKB (Koop Bank)',
                      'YKB',
                      '${item.quantity}',
                      money.format(item.unitPrice),
                      money.format(item.worldlineAmount),
                    ],
                if (showIntegRows)
                  for (final item in integrations)
                    [
                      '—',
                      item.label,
                      '${item.quantity}',
                      money.format(item.unitPrice),
                      money.format(item.worldlineAmount),
                    ],
              ],
              footerLabel: 'WORLDLINE TOPLAM',
              footerQty:
                  '${(showYkbRows ? ykbT.qty : 0) + (showIntegRows ? integQty : 0)}',
              footerAmount: money.format(
                (showYkbRows ? ykbT.world : 0) +
                    (showIntegRows ? integAmount : 0),
              ),
              amountColumnIndex: 4,
            ),
            const Gap(10),
            _GrandTotalBar(
              label: 'B) Worldline Genel Toplam',
              value: money.format(
                _bankGroup == 'YKB (Koop Bank)'
                    ? ykbT.world
                    : summary.totals.worldlineGrand,
              ),
              color: _kWorldline,
            ),
          ],
          const Gap(14),
          Text(
            'Not: Tutarlar KDV hariç gösterilmektedir.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
          ),
        ],
      ),
    );
  }
}

class _InvoiceTotalCard extends StatelessWidget {
  const _InvoiceTotalCard({
    required this.label,
    required this.value,
    required this.color,
    required this.soft,
  });

  final String label;
  final String value;
  final Color color;
  final Color soft;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: soft,
        borderRadius: BorderRadius.circular(AppTheme.radiusMd),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const Gap(8),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _SectionBanner extends StatelessWidget {
  const _SectionBanner({required this.title, required this.color});

  final String title;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
      ),
    );
  }
}

class _GrandTotalBar extends StatelessWidget {
  const _GrandTotalBar({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExcelSectionTable extends StatelessWidget {
  const _ExcelSectionTable({
    required this.title,
    required this.headerColor,
    required this.softColor,
    required this.rows,
    required this.footerLabel,
    required this.footerQty,
    required this.footerAmount,
    this.amountHeader = 'Tutar',
    this.columns,
    this.amountColumnIndex = 3,
  });

  final String title;
  final Color headerColor;
  final Color softColor;
  final List<List<String>> rows;
  final String footerLabel;
  final String footerQty;
  final String footerAmount;
  final String amountHeader;
  final List<String>? columns;
  final int amountColumnIndex;

  @override
  Widget build(BuildContext context) {
    final cols = columns ??
        ['Banka', 'Adet', 'Birim Fiyat', amountHeader];
    final qtyIndex = columns == null ? 1 : 2;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: headerColor.withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            color: softColor,
            child: Text(
              title,
              style: TextStyle(
                color: headerColor,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: DataTable(
                    headingRowColor: WidgetStatePropertyAll(
                      headerColor.withValues(alpha: 0.92),
                    ),
                    headingTextStyle: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
                    ),
                    dataTextStyle: Theme.of(context).textTheme.bodySmall,
                    columns: [
                      for (final c in cols) DataColumn(label: Text(c)),
                    ],
                    rows: [
                      for (final row in rows)
                        DataRow(
                          cells: [
                            for (final cell in row) DataCell(Text(cell)),
                          ],
                        ),
                      DataRow(
                        color: WidgetStatePropertyAll(softColor),
                        cells: [
                          for (var i = 0; i < cols.length; i++)
                            DataCell(
                              Text(
                                i == 0
                                    ? footerLabel
                                    : i == qtyIndex
                                        ? footerQty
                                        : i == amountColumnIndex
                                            ? footerAmount
                                            : '',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: headerColor,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MutakabatPriceSettingsPane extends ConsumerWidget {
  const _MutakabatPriceSettingsPane({
    required this.busy,
    required this.onBusyChanged,
  });

  final bool busy;
  final ValueChanged<bool> onBusyChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(mutakabatPriceSettingsProvider).when(
      data: (settings) => _MutakabatPriceSettingsEditor(
        initial: settings.isEmpty ? null : settings.first,
        busy: busy,
        onBusyChanged: onBusyChanged,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      // API/tablo yoksa bile boş formu göster — fiyat girişi her zaman mümkün olsun.
      error: (error, _) => _MutakabatPriceSettingsEditor(
        initial: null,
        busy: busy,
        onBusyChanged: onBusyChanged,
        loadError: error.toString(),
      ),
    );
  }
}

class _MutakabatPriceSettingsEditor extends ConsumerStatefulWidget {
  const _MutakabatPriceSettingsEditor({
    required this.initial,
    required this.busy,
    required this.onBusyChanged,
    this.loadError,
  });

  final MutakabatPriceSetting? initial;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final String? loadError;

  @override
  ConsumerState<_MutakabatPriceSettingsEditor> createState() =>
      _MutakabatPriceSettingsEditorState();
}

class _MutakabatPriceSettingsEditorState
    extends ConsumerState<_MutakabatPriceSettingsEditor> {
  late TextEditingController _nameController;
  late MutakabatUnitPrices _unitPrices;
  late final Map<int, TextEditingController> _bankControllers;
  late final Map<int, TextEditingController> _ykbControllers;
  late TextEditingController _gmp3Controller;
  late TextEditingController _tsmController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.initial?.name.isNotEmpty == true
          ? widget.initial!.name
          : 'Aktif Fiyatlar',
    );
    _unitPrices = widget.initial?.unitPrices ?? const MutakabatUnitPrices();
    _bankControllers = {};
    _ykbControllers = {};
    for (var i = 1; i <= _unitPrices.maxBankTier; i++) {
      _bankControllers[i] = TextEditingController(
        text: _unitPrices.bankTiers[i] == null || _unitPrices.bankTiers[i] == 0
            ? ''
            : '${_unitPrices.bankTiers[i]}',
      );
      _ykbControllers[i] = TextEditingController(
        text: _unitPrices.ykbTiers[i] == null || _unitPrices.ykbTiers[i] == 0
            ? ''
            : '${_unitPrices.ykbTiers[i]}',
      );
    }
    _gmp3Controller = TextEditingController(
      text: _unitPrices.gmp3 == 0 ? '' : '${_unitPrices.gmp3}',
    );
    _tsmController = TextEditingController(
      text: _unitPrices.tsm == 0 ? '' : '${_unitPrices.tsm}',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _gmp3Controller.dispose();
    _tsmController.dispose();
    for (final controller in _bankControllers.values) {
      controller.dispose();
    }
    for (final controller in _ykbControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  double _parsePrice(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;

  MutakabatUnitPrices _collectUnitPrices() {
    final bankTiers = <int, double>{};
    final ykbTiers = <int, double>{};
    for (final entry in _bankControllers.entries) {
      bankTiers[entry.key] = _parsePrice(entry.value.text);
    }
    // Business kuralı: YKB (Koop Bank) fiyatı tek banka kabul edilir.
    // Bu yüzden tüm banka adedi kademeleri için aynı birim fiyat kullanılır.
    final double ykbUnit = _ykbControllers[1]?.text == null
        ? 0.0
        : _parsePrice(_ykbControllers[1]!.text);
    for (var i = 1; i <= _unitPrices.maxBankTier; i++) {
      ykbTiers[i] = ykbUnit;
    }
    return MutakabatUnitPrices(
      bankTiers: bankTiers,
      ykbTiers: ykbTiers,
      gmp3: _parsePrice(_gmp3Controller.text),
      tsm: _parsePrice(_tsmController.text),
      maxBankTier: _unitPrices.maxBankTier,
    );
  }

  Future<void> _save() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    widget.onBusyChanged(true);
    try {
      await apiClient.postJson('/mutate', body: {
        'op': 'upsert',
        'table': 'mutakabat_price_settings',
        'returning': 'row',
        'values': {
          if (widget.initial?.id.isNotEmpty ?? false) 'id': widget.initial!.id,
          'name': _nameController.text.trim().isEmpty
              ? 'Aktif Fiyatlar'
              : _nameController.text.trim(),
          'unit_prices': _collectUnitPrices().toJson(),
          'is_active': true,
        },
      });
      ref.invalidate(mutakabatPriceSettingsProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birim fiyatlar kaydedildi.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Birim fiyatlar kaydedilemedi.')),
      );
    } finally {
      widget.onBusyChanged(false);
    }
  }

  void _addTier() {
    setState(() {
      final next = _unitPrices.maxBankTier + 1;
      _unitPrices = _unitPrices.copyWith(maxBankTier: next);
      _bankControllers[next] = TextEditingController();
      _ykbControllers[next] = TextEditingController();
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Mutakabat Birim Fiyatları',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: widget.busy ? null : _addTier,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: Text('${_unitPrices.maxBankTier + 1}. Banka Ekle'),
                  ),
                ],
              ),
              if (widget.loadError != null) ...[
                const Gap(10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppTheme.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppTheme.radiusSm),
                    border: Border.all(
                      color: AppTheme.warning.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Text(
                    'Kayıtlı fiyatlar yüklenemedi; yeni fiyat girip kaydedebilirsiniz.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AppTheme.textMuted,
                    ),
                  ),
                ),
              ],
              const Gap(8),
              Text(
                'Bu sayfada yazdığınız tutarlar hesaplamada kullanılır. Kutulara sayı girin.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Fiyat Tanımı'),
              ),
              const Gap(20),
              Text(
                'INGENICO & PAX — Microvise keseceği',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(4),
              Text(
                'Cihazdaki banka adedine göre birim fiyat.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(10),
              for (var i = 1; i <= _unitPrices.maxBankTier; i++) ...[
                _MoneyField(
                  label: '$i Banka',
                  controller: _bankControllers[i]!,
                  enabled: !widget.busy,
                ),
                const Gap(8),
              ],
              const Gap(12),
              Text(
                'YKB (Koop Bank) — Worldline keseceği',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(4),
              Text(
                'Tek banka kabul edilir. Tüm YKB cihazlarına bu birim fiyat uygulanır.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(10),
              _MoneyField(
                label: 'YKB birim fiyat',
                controller: _ykbControllers[1]!,
                enabled: !widget.busy,
              ),
              const Gap(20),
              Text(
                'Entegrasyonlar — Worldline keseceği',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(10),
              _MoneyField(
                label: 'GMP3 kablolu',
                controller: _gmp3Controller,
                enabled: !widget.busy,
              ),
              const Gap(8),
              _MoneyField(
                label: 'TSM kablosuz / Iresto',
                controller: _tsmController,
                enabled: !widget.busy,
              ),
              const Gap(20),
              FilledButton.icon(
                onPressed: widget.busy ? null : _save,
                icon: const Icon(LucideIcons.save, size: 18),
                label: const Text('Fiyatları Kaydet'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MutakabatEditor extends ConsumerStatefulWidget {
  const _MutakabatEditor({
    this.initialRecord,
    required this.busy,
    required this.onBusyChanged,
    required this.onSaved,
    required this.onCancel,
  });

  final MutakabatRecord? initialRecord;
  final bool busy;
  final ValueChanged<bool> onBusyChanged;
  final ValueChanged<String> onSaved;
  final VoidCallback onCancel;

  @override
  ConsumerState<_MutakabatEditor> createState() => _MutakabatEditorState();
}

class _MutakabatEditorState extends ConsumerState<_MutakabatEditor> {
  late int _year;
  late int _month;
  late TextEditingController _titleController;
  late TextEditingController _notesController;
  late MutakabatUnitPrices _unitPrices;
  late final Map<int, TextEditingController> _bankControllers;
  late final Map<int, TextEditingController> _ykbControllers;
  late TextEditingController _gmp3Controller;
  late TextEditingController _tsmController;

  PlatformFile? _bankFile;
  PlatformFile? _gmp3File;
  PlatformFile? _tsmFile;
  MutakabatSummary? _previewSummary;
  Map<String, dynamic>? _previewDetailSheets;
  MutakabatSourceFiles? _previewSourceFiles;
  MutakabatUnitPrices? _activePriceSetting;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    final initial = widget.initialRecord;
    _year = initial?.periodYear ?? now.year;
    _month = initial?.periodMonth ?? now.month;
    _titleController = TextEditingController(text: initial?.title ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _unitPrices = initial?.unitPrices ?? const MutakabatUnitPrices();
    _bankControllers = {};
    _ykbControllers = {};
    for (var i = 1; i <= _unitPrices.maxBankTier; i++) {
      _bankControllers[i] = TextEditingController(
        text: _formatPrice(_unitPrices.bankTiers[i]),
      );
      _ykbControllers[i] = TextEditingController(
        text: _formatPrice(_unitPrices.ykbTiers[i]),
      );
    }
    _gmp3Controller = TextEditingController(text: _formatPrice(_unitPrices.gmp3));
    _tsmController = TextEditingController(text: _formatPrice(_unitPrices.tsm));
    if (initial != null) {
      _previewSummary = initial.summary;
      _previewDetailSheets = initial.detailSheets;
      _previewSourceFiles = initial.sourceFiles;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadActivePrices());
  }

  @override
  void dispose() {
    _titleController.dispose();
    _notesController.dispose();
    _gmp3Controller.dispose();
    _tsmController.dispose();
    for (final controller in _bankControllers.values) {
      controller.dispose();
    }
    for (final controller in _ykbControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _formatPrice(double? value) {
    if (value == null || value == 0) return '';
    return value.toString();
  }

  double _parsePrice(String value) => double.tryParse(value.replaceAll(',', '.')) ?? 0;

  MutakabatUnitPrices _collectUnitPrices() {
    final bankTiers = <int, double>{};
    final ykbTiers = <int, double>{};
    for (final entry in _bankControllers.entries) {
      bankTiers[entry.key] = _parsePrice(entry.value.text);
    }
    for (final entry in _ykbControllers.entries) {
      ykbTiers[entry.key] = _parsePrice(entry.value.text);
    }
    return MutakabatUnitPrices(
      bankTiers: bankTiers,
      ykbTiers: ykbTiers,
      gmp3: _parsePrice(_gmp3Controller.text),
      tsm: _parsePrice(_tsmController.text),
      maxBankTier: _unitPrices.maxBankTier,
    );
  }

  Future<void> _loadActivePrices() async {
    if (widget.initialRecord != null) return;
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    try {
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'mutakabat_price_settings_list'},
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(MutakabatPriceSetting.fromJson)
          .toList(growable: false);
      if (items.isEmpty || !mounted) return;
      _applyUnitPrices(items.first.unitPrices);
      setState(() => _activePriceSetting = items.first.unitPrices);
    } catch (_) {}
  }

  void _applyUnitPrices(MutakabatUnitPrices prices) {
    setState(() {
      _unitPrices = prices;
      // YKB tek banka: tüm kademeler için aynı fiyatı uygula.
      final ykbUnit = prices.ykbTiers[1] ?? 0;
      for (var i = 1; i <= prices.maxBankTier; i++) {
        _bankControllers.putIfAbsent(i, TextEditingController.new);
        _ykbControllers.putIfAbsent(i, TextEditingController.new);
        _bankControllers[i]!.text =
            prices.bankTiers[i] == null || prices.bankTiers[i] == 0
            ? ''
            : '${prices.bankTiers[i]}';
        _ykbControllers[i]!.text = ykbUnit == 0 ? '' : '$ykbUnit';
      }
      _gmp3Controller.text = prices.gmp3 == 0 ? '' : '${prices.gmp3}';
      _tsmController.text = prices.tsm == 0 ? '' : '${prices.tsm}';
    });
  }

  Future<void> _pickFile(String kind) async {
    final result = await FilePicker.platform.pickFiles(
      withData: true,
      type: FileType.custom,
      allowedExtensions: const ['xls', 'xlsx'],
    );
    final file = result?.files.single;
    if (file == null) return;
    setState(() {
      switch (kind) {
        case 'bank':
          _bankFile = file;
        case 'gmp3':
          _gmp3File = file;
        case 'tsm':
          _tsmFile = file;
      }
    });
  }

  Future<void> _openExcelFilesDialog() async {
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return Dialog(
          insetPadding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(LucideIcons.fileSpreadsheet),
                      const Gap(10),
                      Expanded(
                        child: Text(
                          'Excel Dosyalarını Seç',
                          style: Theme.of(dialogContext)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(LucideIcons.x),
                      ),
                    ],
                  ),
                  const Gap(14),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _FilePickTile(
                        label: 'Banka Data',
                        requiredFile: true,
                        fileName: _bankFile?.name ??
                            widget.initialRecord?.sourceFiles.bankFileName,
                        onPick: () => _pickFile('bank'),
                      ),
                      _FilePickTile(
                        label: 'GMP3 Data',
                        fileName: _gmp3File?.name ??
                            widget.initialRecord?.sourceFiles.gmp3FileName,
                        onPick: () => _pickFile('gmp3'),
                      ),
                      _FilePickTile(
                        label: 'TSM Iresto Data',
                        fileName: _tsmFile?.name ??
                            widget.initialRecord?.sourceFiles.tsmFileName,
                        onPick: () => _pickFile('tsm'),
                      ),
                    ],
                  ),
                  const Gap(16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: widget.busy
                          ? null
                          : () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(LucideIcons.check),
                      label: const Text('Tamam'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _exportPreviewExcel() async {
    if (_previewSummary == null || _previewDetailSheets == null) {
      _showMessage('Excel aktarmak için önce hesaplama yapın.');
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];
    widget.onBusyChanged(true);
    try {
      final periodLabel =
          '${months[_month - 1]} $_year';
      final response = await apiClient.postJson('/mutate', body: {
        'op': 'exportMutakabatExcel',
        'summary': _previewSummary!.toJson(),
        'detailSheets': _previewDetailSheets,
        'unitPrices': _collectUnitPrices().toJson(),
        'periodLabel': periodLabel,
        'filename':
            'mutakabat_${_year}_${_month.toString().padLeft(2, '0')}.xlsx',
      });
      final bytes = base64Decode(response['dataBase64']?.toString() ?? '');
      await downloadExcelFile(
        bytes,
        response['filename']?.toString() ??
            'mutakabat_${_year}_${_month.toString().padLeft(2, '0')}.xlsx',
      );
      _showMessage('Excel dosyası hazırlandı.');
    } catch (error) {
      _showMessage(
        'Excel dışa aktarılamadı: ${error.toString().replaceFirst('Exception: ', '')}',
      );
    } finally {
      widget.onBusyChanged(false);
    }
  }

  Future<void> _calculate() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    if (_bankFile?.bytes == null && widget.initialRecord == null) {
      _showMessage('Banka Excel dosyası zorunludur.');
      return;
    }
    widget.onBusyChanged(true);
    try {
      final body = <String, dynamic>{
        'op': 'processMutakabat',
        'unitPrices': _collectUnitPrices().toJson(),
        'sourceFiles': {
          'bankFileName': _bankFile?.name ?? widget.initialRecord?.sourceFiles.bankFileName,
          'gmp3FileName': _gmp3File?.name ?? widget.initialRecord?.sourceFiles.gmp3FileName,
          'tsmFileName': _tsmFile?.name ?? widget.initialRecord?.sourceFiles.tsmFileName,
        },
      };
      if (_bankFile?.bytes != null) {
        body['bankFileBase64'] = base64Encode(_bankFile!.bytes!);
      } else if (widget.initialRecord?.summary.lineItems.isNotEmpty == true) {
        body['summary'] = widget.initialRecord!.summary.toJson();
        body['detailSheets'] = widget.initialRecord!.detailSheets;
      } else {
        throw Exception('Banka Excel dosyası zorunludur.');
      }
      if (_gmp3File?.bytes != null) {
        body['gmp3FileBase64'] = base64Encode(_gmp3File!.bytes!);
      }
      if (_tsmFile?.bytes != null) {
        body['tsmFileBase64'] = base64Encode(_tsmFile!.bytes!);
      }
      final response = await apiClient.postJson('/mutate', body: body);
      setState(() {
        _previewSummary = MutakabatSummary.fromJson(
          (response['summary'] as Map?)?.cast<String, dynamic>(),
        );
        _previewDetailSheets =
            (response['detailSheets'] as Map?)?.cast<String, dynamic>();
        _previewSourceFiles = MutakabatSourceFiles.fromJson(
          (response['sourceFiles'] as Map?)?.cast<String, dynamic>(),
        );
      });
      _showMessage('Mutakabat hesaplandı.');
    } catch (error) {
      _showMessage(error.toString().replaceFirst('Exception: ', ''));
    } finally {
      widget.onBusyChanged(false);
    }
  }

  Future<void> _save() async {
    if (_previewSummary == null || _previewDetailSheets == null) {
      _showMessage('Kaydetmeden önce hesaplama yapın.');
      return;
    }
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    widget.onBusyChanged(true);
    try {
      final record = MutakabatRecord(
        id: widget.initialRecord?.id ?? '',
        periodYear: _year,
        periodMonth: _month,
        title: _titleController.text.trim(),
        notes: _notesController.text.trim(),
        status: 'finalized',
        unitPrices: _collectUnitPrices(),
        summary: _previewSummary!,
        sourceFiles: _previewSourceFiles ?? const MutakabatSourceFiles(),
        isActive: true,
        createdAt: widget.initialRecord?.createdAt,
        updatedAt: widget.initialRecord?.updatedAt,
        detailSheets: _previewDetailSheets,
      );
      final response = await apiClient.postJson('/mutate', body: {
        'op': 'upsert',
        'table': 'mutakabat_records',
        'returning': 'row',
        'values': {
          if (widget.initialRecord?.id.isNotEmpty ?? false)
            'id': widget.initialRecord!.id,
          ...record.toUpsertJson(
            summary: _previewSummary!,
            detailSheets: _previewDetailSheets,
            sourceFiles: _previewSourceFiles,
          ),
        },
      });
      final row = response['row'];
      final id = row is Map ? row['id']?.toString() : widget.initialRecord?.id;
      if (id == null || id.isEmpty) {
        throw Exception('Kayıt oluşturulamadı.');
      }
      widget.onSaved(id);
      _showMessage('Mutakabat kaydedildi.');
      widget.onCancel();
    } catch (error) {
      _showMessage('Kaydetme başarısız: ${error.toString()}');
    } finally {
      widget.onBusyChanged(false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    const months = [
      'Ocak',
      'Şubat',
      'Mart',
      'Nisan',
      'Mayıs',
      'Haziran',
      'Temmuz',
      'Ağustos',
      'Eylül',
      'Ekim',
      'Kasım',
      'Aralık',
    ];

    return ListView(
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.initialRecord == null
                    ? 'Yeni Mutakabat'
                    : 'Mutakabat Düzenle',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(8),
              Text(
                'Dönemi seçin, Excel dosyalarını yükleyin ve hesaplayın. Birim fiyatlar ayrı alandan yönetilir.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
              const Gap(16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.start,
                children: [
                  SizedBox(
                    width: 160,
                    child: DropdownMenu<int>(
                      initialSelection: _month,
                      label: const Text('Ay'),
                      enabled: !widget.busy,
                      expandedInsets: EdgeInsets.zero,
                      inputDecorationTheme: const InputDecorationTheme(
                        isDense: true,
                        contentPadding: EdgeInsets.fromLTRB(12, 10, 8, 10),
                        border: OutlineInputBorder(),
                      ),
                      dropdownMenuEntries: [
                        for (var i = 1; i <= 12; i++)
                          DropdownMenuEntry(value: i, label: months[i - 1]),
                      ],
                      onSelected: widget.busy
                          ? null
                          : (value) {
                              if (value == null) return;
                              setState(() => _month = value);
                            },
                    ),
                  ),
                  SizedBox(
                    width: 120,
                    child: TextFormField(
                      initialValue: '$_year',
                      decoration: const InputDecoration(
                        labelText: 'Yıl',
                        isDense: true,
                        contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                      ),
                      keyboardType: TextInputType.number,
                      onChanged: widget.busy
                          ? null
                          : (value) => _year = int.tryParse(value) ?? _year,
                    ),
                  ),
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Başlık (opsiyonel)',
                        isDense: true,
                        contentPadding: EdgeInsets.fromLTRB(12, 10, 12, 10),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Row(
            children: [
              const Icon(LucideIcons.badgeCent),
              const Gap(12),
              Expanded(
                child: Text(
                  _activePriceSetting == null
                      ? 'Birim fiyat girilmemiş. Önce Birim Fiyatlar sayfasından tutarları kaydedin.'
                      : 'Hesaplama, Birim Fiyatlar sayfasındaki aktif tutarlarla yapılacak.',
                ),
              ),
              const Gap(12),
              OutlinedButton(
                onPressed: widget.busy
                    ? null
                    : () => context.go('/mutakabat/fiyatlar'),
                child: const Text('Fiyatları Aç'),
              ),
            ],
          ),
        ),
        const Gap(12),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Excel Dosyaları',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const Gap(12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  FilledButton.icon(
                    onPressed:
                        widget.busy ? null : _openExcelFilesDialog,
                    icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
                    label: const Text('Dosyaları Yükle'),
                  ),
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Banka',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Gap(4),
                        Text(
                          _bankFile?.name ??
                              widget.initialRecord
                                  ?.sourceFiles.bankFileName ??
                              'Dosya seçilmedi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'GMP3',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Gap(4),
                        Text(
                          _gmp3File?.name ??
                              widget.initialRecord
                                  ?.sourceFiles.gmp3FileName ??
                              'Dosya seçilmedi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 240,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'TSM / Iresto',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: AppTheme.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const Gap(4),
                        Text(
                          _tsmFile?.name ??
                              widget.initialRecord
                                  ?.sourceFiles.tsmFileName ??
                              'Dosya seçilmedi',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: AppTheme.textMuted,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Gap(16),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: widget.busy ? null : _calculate,
                    icon: const Icon(LucideIcons.calculator, size: 18),
                    label: const Text('Hesapla'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.busy ||
                            _previewSummary == null ||
                            _previewDetailSheets == null
                        ? null
                        : _exportPreviewExcel,
                    icon: const Icon(LucideIcons.download, size: 18),
                    label: const Text('Excel Aktar'),
                  ),
                  FilledButton.icon(
                    onPressed: widget.busy ? null : _save,
                    icon: const Icon(LucideIcons.save, size: 18),
                    label: const Text('Kaydet'),
                  ),
                  OutlinedButton(
                    onPressed: widget.busy ? null : widget.onCancel,
                    child: const Text('Vazgeç'),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_previewSummary != null) ...[
          const Gap(12),
          AppCard(
            child: Row(
              children: [
                const Icon(LucideIcons.fileSpreadsheet),
                const Gap(12),
                const Expanded(
                  child: Text(
                                    'Hesaplanan datayı Excel olarak indirin: Dashboard, INGENICO BANKA, PAX BANKA, YKB_KOOP BANKA, GMP3 DATA, TSM IRESTO DATA.',
                  ),
                ),
                const Gap(12),
                FilledButton.icon(
                  onPressed: widget.busy || _previewDetailSheets == null
                      ? null
                      : _exportPreviewExcel,
                  icon: const Icon(LucideIcons.download, size: 18),
                  label: const Text('Excel Aktar'),
                ),
              ],
            ),
          ),
          const Gap(12),
          _MutakabatDashboardWithFilters(summary: _previewSummary!),
        ],
        const Gap(12),
        AppCard(
          child: TextField(
            controller: _notesController,
            minLines: 2,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'Notlar',
              alignLabelWithHint: true,
            ),
          ),
        ),
      ],
    );
  }
}

class _FilePickTile extends StatelessWidget {
  const _FilePickTile({
    required this.label,
    required this.onPick,
    this.fileName,
    this.requiredFile = false,
  });

  final String label;
  final String? fileName;
  final bool requiredFile;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 260,
      child: OutlinedButton(
        onPressed: onPick,
        child: Align(
          alignment: Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                requiredFile ? '$label *' : label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Gap(4),
              Text(
                fileName?.trim().isNotEmpty == true
                    ? fileName!
                    : 'Dosya seçilmedi',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MoneyField extends StatelessWidget {
  const _MoneyField({
    required this.label,
    required this.controller,
    this.enabled = true,
  });

  final String label;
  final TextEditingController controller;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        prefixText: '₺ ',
        hintText: '0,00',
      ),
    );
  }
}
