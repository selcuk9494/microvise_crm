import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import 'finance_open_link.dart';

String _text(dynamic value) => value?.toString().trim() ?? '';

String _dayParam(DateTime day) => DateFormat('yyyy-MM-dd').format(day);

class FinanceLogScreen extends ConsumerStatefulWidget {
  const FinanceLogScreen({super.key});

  @override
  ConsumerState<FinanceLogScreen> createState() => _FinanceLogScreenState();
}

class _FinanceLogScreenState extends ConsumerState<FinanceLogScreen> {
  bool _loading = false;
  String? _error;
  DateTime _day = DateTime.now();
  List<Map<String, dynamic>> _items = const [];
  String? _openedLogId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _readQueryAndLoad();
    });
  }

  void _readQueryAndLoad() {
    final q = GoRouterState.of(context).uri.queryParameters;
    final gun = q['gun'];
    if (gun != null && gun.isNotEmpty) {
      final parsed = DateTime.tryParse(gun);
      if (parsed != null) _day = parsed;
    }
    _openedLogId = q['id'];
    _load();
  }

  Future<void> _load() async {
    final api = ref.read(apiClientProvider);
    if (api == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final response = await api.getJson(
        '/data',
        queryParameters: {
          'resource': 'finance_operation_logs',
          'day': _dayParam(_day),
          if ((_openedLogId ?? '').isNotEmpty) 'id': _openedLogId!,
        },
      );
      final items = ((response['items'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (!mounted) return;
      setState(() {
        _items = items;
        _loading = false;
      });
      final openId = _openedLogId;
      if (openId != null && openId.isNotEmpty) {
        _openedLogId = null;
        Map<String, dynamic>? match;
        for (final row in items) {
          if (_text(row['id']) == openId) {
            match = row;
            break;
          }
        }
        if (match != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openLog(match!);
          });
        }
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  String _actionLabel(String action) {
    return switch (action) {
      'create' => 'Eklendi',
      'update' => 'Güncellendi',
      'delete' => 'Silindi',
      'correct' => 'Düzeltildi',
      _ => action,
    };
  }

  String _entityLabel(String type) {
    return switch (type) {
      'bank' => 'Banka',
      'account' => 'Hesap',
      'movement' => 'Hareket',
      'transfer' => 'Transfer',
      'kasa' => 'Kasa',
      'masraf' => 'Masraf',
      _ => type,
    };
  }

  AppBadgeTone _tone(String action) {
    return switch (action) {
      'create' => AppBadgeTone.success,
      'delete' => AppBadgeTone.error,
      'correct' => AppBadgeTone.warning,
      _ => AppBadgeTone.primary,
    };
  }

  String _targetLocation(Map<String, dynamic> row) {
    final type = _text(row['entity_type']);
    final entityId = _text(row['entity_id']);
    final account = row['finance_accounts'] as Map?;
    final hesap =
        _text(account?['akinsoft_source_id']).isNotEmpty
        ? _text(account?['akinsoft_source_id'])
        : _text(row['account_id']);
    if (type == 'movement' || type == 'transfer' || type == 'masraf') {
      return '/finans/akinsoft/bankalar?hesap=${Uri.encodeQueryComponent(hesap)}&hareket=${Uri.encodeQueryComponent(entityId)}';
    }
    if (type == 'account') {
      return '/finans/akinsoft/bankalar?hesap=${Uri.encodeQueryComponent(hesap.isEmpty ? entityId : hesap)}';
    }
    return '/finans/akinsoft/bankalar';
  }

  Future<void> _openLog(Map<String, dynamic> row) async {
    final location = _targetLocation(row);
    if (!mounted) return;
    context.go(location);
  }

  Future<void> _pickDay() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _day,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => _day = picked);
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return AppPageLayout(
      title: 'Finans İşlem Günlüğü',
      subtitle:
          'Günlük CRM finans işlemleri. Satıra basınca ilgili hareket açılır; sağ tık ile yeni sekmede açabilirsiniz.',
      compactHeader: true,
      actions: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _pickDay,
          icon: const Icon(LucideIcons.calendarDays, size: 18),
          label: Text(DateFormat('dd.MM.yyyy').format(_day)),
        ),
        OutlinedButton.icon(
          onPressed: _loading ? null : _load,
          icon: const Icon(LucideIcons.refreshCw, size: 18),
          label: const Text('Yenile'),
        ),
      ],
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          if (_error != null) ...[
            const Gap(8),
            Text(
              _error!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.error),
            ),
          ],
          const Gap(8),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(AppTheme.radiusMd),
                border: Border.all(
                  color: AppTheme.border.withValues(alpha: 0.7),
                ),
              ),
              child: _items.isEmpty && !_loading
                  ? Center(
                      child: Text(
                        'Bu günde işlem yok.',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: AppTheme.textMuted,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final row = _items[index];
                        final at = DateTime.tryParse(
                          _text(row['occurred_at']),
                        )?.toLocal();
                        final time = at == null
                            ? '—'
                            : DateFormat('HH:mm').format(at);
                        return FinanceOpenLink(
                          location: _targetLocation(row),
                          child: Container(
                            color: AppDenseList.rowFill(index),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppDenseList.rowH,
                              vertical: AppDenseList.rowV,
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 52,
                                  child: Text(
                                    time,
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelLarge
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                ),
                                AppBadge(
                                  dense: true,
                                  label: _entityLabel(
                                    _text(row['entity_type']),
                                  ),
                                  tone: AppBadgeTone.neutral,
                                ),
                                const Gap(8),
                                AppBadge(
                                  dense: true,
                                  label: _actionLabel(_text(row['action'])),
                                  tone: _tone(_text(row['action'])),
                                ),
                                const Gap(10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        _text(row['summary']).isEmpty
                                            ? 'İşlem'
                                            : _text(row['summary']),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                      ),
                                      Text(
                                        [
                                          _text(row['created_by_name']),
                                          _text(
                                            (row['finance_accounts']
                                                as Map?)?['name'],
                                          ),
                                        ].where((e) => e.isNotEmpty).join(' · '),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: AppTheme.textMuted,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Hareketi aç',
                                  visualDensity: VisualDensity.compact,
                                  onPressed: () => _openLog(row),
                                  icon: const Icon(
                                    LucideIcons.arrowUpRight,
                                    size: 18,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
