import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import '../../design_system/status_tone.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import '../definitions/bkm_acquirer_definition.dart';
import '../definitions/bkm_acquirer_editor.dart';
import 'tsm_log_parser.dart';

class TsmLogScreen extends ConsumerStatefulWidget {
  const TsmLogScreen({super.key});

  @override
  ConsumerState<TsmLogScreen> createState() => _TsmLogScreenState();
}

class _TsmLogScreenState extends ConsumerState<TsmLogScreen> {
  final _searchController = TextEditingController();
  TsmLogParseResult? _result;
  bool _loading = false;
  String _resultFilter = 'TUMU';
  String _resultMessageFilter = '';
  String _operationFilter = 'TUMU';
  String _bankFilter = '';
  String _orderKindFilter = 'TUMU';
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _dateFormat = DateFormat('dd.MM.yyyy');
  final _dateTimeFormat = DateFormat('dd.MM.yyyy HH:mm');
  Map<String, String> _bkmNames = const {};
  List<BkmAcquirerDefinition> _bkmItems = const [];
  final _selectedSerials = <String>{};
  bool _queryMode = false;
  int _queryIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<TsmLogSerial> get _filteredSerials {
    final serials = _result?.uniqueSerials ?? const <TsmLogSerial>[];
    final query = _searchController.text.trim().toLowerCase();
    return serials.where((item) {
      final queryOk =
          query.isEmpty || _searchHaystack(item).contains(query);
      return queryOk &&
          tsmLogSerialMatchesFilters(
            item,
            resultFilter: _resultFilter,
            resultMessageFilter: _resultMessageFilter,
            operationFilter: _operationFilter,
            orderKindFilter: _orderKindFilter,
            bankFilter: _bankFilter,
            dateFrom: _dateFrom,
            dateTo: _dateTo,
            fileHasDates: _fileHasDates,
            bkmNames: _bkmNames,
          );
    }).toList(growable: false);
  }

  List<String> get _selectedInOrder => _filteredSerials
      .map((item) => item.serialNumber)
      .where(_selectedSerials.contains)
      .toList(growable: false);

  bool get _allFilteredSelected {
    final serials = _filteredSerials;
    return serials.isNotEmpty &&
        serials.every((item) => _selectedSerials.contains(item.serialNumber));
  }

  bool? get _selectAllValue {
    if (_filteredSerials.isEmpty) return false;
    if (_allFilteredSelected) return true;
    if (_filteredSerials.any(
      (item) => _selectedSerials.contains(item.serialNumber),
    )) {
      return null;
    }
    return false;
  }

  void _toggleSelectAll() {
    final ids = _filteredSerials.map((item) => item.serialNumber);
    setState(() {
      if (_allFilteredSelected) {
        _selectedSerials.removeAll(ids);
      } else {
        _selectedSerials.addAll(ids);
      }
    });
  }

  void _toggleSerial(String serial) {
    setState(() {
      if (!_selectedSerials.add(serial)) {
        _selectedSerials.remove(serial);
      }
      final queue = _selectedInOrder;
      if (_queryMode && queue.isEmpty) {
        _queryMode = false;
        _queryIndex = 0;
      } else if (_queryIndex >= queue.length) {
        _queryIndex = queue.isEmpty ? 0 : queue.length - 1;
      }
    });
  }

  Future<void> _copyOneSerial(String serial) async {
    await Clipboard.setData(ClipboardData(text: serial));
  }

  Future<void> _copyQueryCurrent() async {
    final queue = _selectedInOrder;
    if (queue.isEmpty) return;
    final index = _queryIndex.clamp(0, queue.length - 1);
    final serial = queue[index];
    await _copyOneSerial(serial);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          '$serial kopyalandı (${index + 1}/${queue.length}). '
          'Diğer sekmeye yapıştırıp sorgulayın, sonra Sonraki.',
        ),
      ),
    );
  }

  Future<void> _startSequentialQuery() async {
    if (_filteredSerials.isEmpty) return;
    setState(() {
      if (_selectedInOrder.isEmpty) {
        _selectedSerials.addAll(
          _filteredSerials.map((item) => item.serialNumber),
        );
      }
      _queryMode = true;
      _queryIndex = 0;
    });
    await _copyQueryCurrent();
  }

  Future<void> _queryStep(int delta) async {
    final queue = _selectedInOrder;
    if (queue.isEmpty) return;
    final next = (_queryIndex + delta).clamp(0, queue.length - 1);
    if (next == _queryIndex && delta > 0 && _queryIndex == queue.length - 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Sıra bitti.')),
      );
      return;
    }
    setState(() => _queryIndex = next);
    await _copyQueryCurrent();
  }

  bool get _fileHasDates =>
      _result?.uniqueSerials.any((item) => item.occurredAt != null) ?? false;

  DateTime _defaultDateFor(TsmLogParseResult parsed) {
    final today = DateUtils.dateOnly(DateTime.now());
    final dates = parsed.uniqueSerials
        .map((item) => item.occurredAt)
        .whereType<DateTime>()
        .map((date) => DateUtils.dateOnly(date.toLocal()))
        .toList(growable: false);
    if (dates.any((date) => DateUtils.isSameDay(date, today))) return today;
    if (dates.isEmpty) return today;
    dates.sort((a, b) => b.compareTo(a));
    return dates.first;
  }

  void _setDefaultDateRange(TsmLogParseResult parsed) {
    if (!parsed.uniqueSerials.any((item) => item.occurredAt != null)) {
      _dateFrom = null;
      _dateTo = null;
      return;
    }
    final day = _defaultDateFor(parsed);
    _dateFrom = day;
    _dateTo = day;
  }

  String? get _dateRangeEmptyMessage {
    if (_dateFrom == null && _dateTo == null) return null;
    if (_dateFrom != null &&
        _dateTo != null &&
        DateUtils.isSameDay(_dateFrom!, _dateTo!)) {
      return '${_dateFormat.format(_dateFrom!)} tarihinde filtrelere uyan kayıt yok. Tarihi değiştirerek diğer günleri görebilirsiniz.';
    }
    final fromText = _dateFrom == null ? '…' : _dateFormat.format(_dateFrom!);
    final toText = _dateTo == null ? '…' : _dateFormat.format(_dateTo!);
    return '$fromText – $toText aralığında filtrelere uyan kayıt yok. Tarihi değiştirerek diğer günleri görebilirsiniz.';
  }

  void _toggleOperation(String value) {
    _operationFilter = _operationFilter == value ? 'TUMU' : value;
    if (!_resultMessageOptions.contains(_resultMessageFilter)) {
      _resultMessageFilter = '';
    }
  }

  List<String> get _resultMessageOptions {
    return tsmResultMessagesForOperation(
      _result?.uniqueSerials ?? const <TsmLogSerial>[],
      tsmOperationFromFilter(_operationFilter),
      catalog: _result?.resultMessageOptions ?? const [],
    );
  }

  void _selectResultMessage(String value) {
    _resultMessageFilter = _resultMessageFilter == value ? '' : value;
  }

  void _toggleOrderKind(String value) {
    _orderKindFilter = _orderKindFilter == value ? 'TUMU' : value;
  }

  List<String> get _banks {
    final names = <String>{};
    for (final item in _result?.uniqueSerials ?? const <TsmLogSerial>[]) {
      final bank = tsmDisplayBankName(item.workOrder, _bkmNames);
      if (bank.isNotEmpty) names.add(bank);
    }
    final list = names.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  String _searchHaystack(TsmLogSerial item) {
    final order = item.workOrder;
    return [
      item.serialNumber,
      tsmDisplayBankName(order, _bkmNames),
      order?.acquirerId,
      order?.bankName,
      order?.terminalId,
      order?.merchantName,
      order?.merchantNo,
      order?.bkmMerchantId,
      order?.displayAddress,
      order?.phone,
      order?.description,
      tsmOrderKindLabel(order?.orderKind ?? TsmOrderKind.unknown),
      ...item.resultMessages,
    ].whereType<String>().join(' ').toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    _bkmItems = ref.watch(bkmAcquirersProvider).asData?.value ?? const [];
    _bkmNames = bkmAcquirerNameMap(_bkmItems);
    final result = _result;
    final serials = _filteredSerials;
    final uniqueCount = serials.length;
    final approvedCount = _countMatchingKind(TsmLogResultKind.approved);
    final mismatchCount = _countMatchingKind(TsmLogResultKind.serialMismatch);
    final kurulumCount = serials
        .where((item) => item.workOrder?.orderKind == TsmOrderKind.kurulum)
        .length;
    final geriAlimCount = serials
        .where((item) => item.workOrder?.orderKind == TsmOrderKind.geriAlim)
        .length;

    return AppPageLayout(
      compactHeader: true,
      title: 'TSM Log',
      subtitle:
          'TERMINAL_SORGU ve ISEMRI_ACMA kayıtlarından 2 ile başlayan sicilleri listeler.',
      actions: [
        FilledButton.tonalIcon(
          onPressed: () => showBkmAcquirersManager(context, ref),
          icon: const Icon(LucideIcons.plus, size: 18),
          label: const Text('BKM Tanımla'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: result == null || result.isEmpty ? null : _copySerials,
          icon: const Icon(LucideIcons.copy, size: 18),
          label: const Text('Kopyala'),
        ),
        const Gap(10),
        OutlinedButton.icon(
          onPressed: result == null || result.isEmpty ? null : _exportSerials,
          icon: const Icon(LucideIcons.fileSpreadsheet, size: 18),
          label: const Text('Excel Aktar'),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: _loading ? null : _pickExcel,
          icon: _loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(LucideIcons.upload, size: 18),
          label: Text(_loading ? 'Okunuyor' : 'Excel Yükle'),
        ),
      ],
      body: Column(
        children: [
          AppCard(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _searchController,
                        onChanged: (_) => setState(() {}),
                        style: Theme.of(context).textTheme.bodyMedium,
                        decoration: const InputDecoration(
                          isDense: true,
                          prefixIcon: Icon(LucideIcons.search, size: 18),
                          hintText: 'Sicil, banka, işyeri ara',
                        ),
                      ),
                    ),
                    const Gap(10),
                    SizedBox(
                      width: 220,
                      child: _DateFilterField(
                        label: 'Tarih aralığı',
                        from: _dateFrom,
                        to: _dateTo,
                        format: _dateFormat,
                        onTap: _pickDateRange,
                        onClear: () => setState(() {
                          _dateFrom = null;
                          _dateTo = null;
                        }),
                      ),
                    ),
                    if (result != null) ...[
                      const Gap(10),
                      SizedBox(
                        width: 200,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(
                            'bank-${_result?.fileName}-$_bankFilter',
                          ),
                          initialValue:
                              _bankFilter == kTsmBankFilterEmpty ||
                                  _banks.contains(_bankFilter)
                              ? _bankFilter
                              : '',
                          isDense: true,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Banka',
                            isDense: true,
                          ),
                          items: [
                            const DropdownMenuItem(
                              value: '',
                              child: Text('Tüm bankalar'),
                            ),
                            const DropdownMenuItem(
                              value: kTsmBankFilterEmpty,
                              child: Text('Boş olanlar'),
                            ),
                            for (final bank in _banks)
                              DropdownMenuItem(
                                value: bank,
                                child: Text(
                                  bank,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                          onChanged: (value) =>
                              setState(() => _bankFilter = value ?? ''),
                        ),
                      ),
                      const Gap(12),
                      Flexible(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            AppBadge(
                              label: '$uniqueCount sicil',
                              tone: AppBadgeTone.primary,
                              dense: true,
                            ),
                            AppBadge(
                              label: '$approvedCount onay',
                              tone: AppBadgeTone.success,
                              dense: true,
                            ),
                            AppBadge(
                              label: '$mismatchCount eşleşmedi',
                              tone: AppBadgeTone.warning,
                              dense: true,
                            ),
                            if (kurulumCount > 0)
                              AppBadge(
                                label: '$kurulumCount kurulum',
                                tone: AppBadgeTone.success,
                                dense: true,
                              ),
                            if (geriAlimCount > 0)
                              AppBadge(
                                label: '$geriAlimCount geri alım',
                                tone: AppBadgeTone.warning,
                                dense: true,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const Gap(12),
                Divider(
                  height: 1,
                  thickness: 1,
                  color: AppTheme.border.withValues(alpha: 0.9),
                ),
                const Gap(10),
                _FilterGroup(
                  label: 'İşlem',
                  children: [
                    _FilterChip(
                      label: 'Tümü',
                      selected: _operationFilter == 'TUMU',
                      onTap: () => setState(() {
                        _operationFilter = 'TUMU';
                        if (!_resultMessageOptions.contains(
                          _resultMessageFilter,
                        )) {
                          _resultMessageFilter = '';
                        }
                      }),
                    ),
                    _FilterChip(
                      label: 'TERMINAL_SORGU',
                      selected: _operationFilter == 'TERMINAL_SORGU',
                      onTap: () =>
                          setState(() => _toggleOperation('TERMINAL_SORGU')),
                    ),
                    _FilterChip(
                      label: 'ISEMRI_ACMA',
                      selected: _operationFilter == 'ISEMRI_ACMA',
                      onTap: () =>
                          setState(() => _toggleOperation('ISEMRI_ACMA')),
                    ),
                  ],
                ),
                const Gap(8),
                _FilterGroup(
                  label: 'İş Emri',
                  children: [
                    _FilterChip(
                      label: 'Tümü',
                      selected: _orderKindFilter == 'TUMU',
                      onTap: () =>
                          setState(() => _orderKindFilter = 'TUMU'),
                    ),
                    _FilterChip(
                      label: 'Kurulum',
                      selected: _orderKindFilter == 'KURULUM',
                      onTap: () => setState(() => _toggleOrderKind('KURULUM')),
                    ),
                    _FilterChip(
                      label: 'Geri Alım',
                      selected: _orderKindFilter == 'GERI_ALIM',
                      onTap: () =>
                          setState(() => _toggleOrderKind('GERI_ALIM')),
                    ),
                    _FilterChip(
                      label: 'Ekleme',
                      selected: _orderKindFilter == 'EKLEME',
                      onTap: () => setState(() => _toggleOrderKind('EKLEME')),
                    ),
                    _FilterChip(
                      label: 'Boş',
                      selected: _orderKindFilter == kTsmOrderKindFilterEmpty,
                      onTap: () => setState(
                        () => _toggleOrderKind(kTsmOrderKindFilterEmpty),
                      ),
                    ),
                  ],
                ),
                if (result != null) ...[
                  const Gap(8),
                  _FilterGroup(
                    label: 'Sonuç',
                    children: [
                      _FilterChip(
                        label: 'Tümü',
                        selected: _resultMessageFilter.isEmpty,
                        onTap: () =>
                            setState(() => _resultMessageFilter = ''),
                      ),
                      for (final message in _resultMessageOptions)
                        _FilterChip(
                          label: message,
                          selected: _resultMessageFilter == message,
                          maxWidth: 260,
                          onTap: () =>
                              setState(() => _selectResultMessage(message)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Gap(10),
          if (result != null) _buildQueryBar(),
          if (result != null) const Gap(8),
          Expanded(child: _buildBody(serials)),
        ],
      ),
    );
  }

  Widget _buildQueryBar() {
    final queue = _selectedInOrder;
    final current = _queryMode && queue.isNotEmpty
        ? queue[_queryIndex.clamp(0, queue.length - 1)]
        : null;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Checkbox(
            tristate: true,
            value: _selectAllValue,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            onChanged: _filteredSerials.isEmpty
                ? null
                : (_) => _toggleSelectAll(),
          ),
          Text(
            _selectedSerials.isEmpty
                ? 'Sicil seçin'
                : '${queue.length} sicil seçili',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Gap(10),
          TextButton(
            onPressed: _filteredSerials.isEmpty ? null : _toggleSelectAll,
            child: Text(_allFilteredSelected ? 'Seçimi kaldır' : 'Tümünü seç'),
          ),
          const Spacer(),
          if (current != null) ...[
            SelectableText(
              current,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: AppTheme.primary,
              ),
            ),
            const Gap(8),
            Text(
              '${_queryIndex + 1} / ${queue.length}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppTheme.textMuted,
              ),
            ),
            const Gap(8),
            OutlinedButton(
              onPressed: _queryIndex <= 0 ? null : () => _queryStep(-1),
              child: const Text('Önceki'),
            ),
            const Gap(6),
            FilledButton(
              onPressed: () => _queryStep(1),
              child: const Text('Sonraki'),
            ),
            const Gap(10),
          ],
          FilledButton.tonalIcon(
            onPressed: _filteredSerials.isEmpty
                ? null
                : _startSequentialQuery,
            icon: const Icon(LucideIcons.search, size: 16),
            label: Text(
              _queryMode ? 'Sırayı baştan al' : 'Sıralı sorgula',
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyPane(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(child: child),
          ),
        );
      },
    );
  }

  Widget _buildBody(List<TsmLogSerial> serials) {
    final result = _result;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (result == null) {
      return _emptyPane(
        EmptyStateCard(
          icon: LucideIcons.fileSpreadsheet,
          title: 'TSM log Excel yükleyin',
          message: 'TERMINAL_SORGU ve ISEMRI_ACMA sicillerini çıkarmak için Excel yükleyin.',
          action: FilledButton.icon(
            onPressed: _pickExcel,
            icon: const Icon(LucideIcons.upload, size: 16),
            label: const Text('Excel Yükle'),
          ),
        ),
      );
    }
    if (result.error != null && result.isEmpty) {
      return _emptyPane(
        EmptyStateCard(
          icon: LucideIcons.circleAlert,
          title: 'Excel okunamadı',
          message: result.error!,
          action: OutlinedButton.icon(
            onPressed: _pickExcel,
            icon: const Icon(LucideIcons.upload, size: 16),
            label: const Text('Tekrar Dene'),
          ),
        ),
      );
    }
    if (serials.isEmpty) {
      return _emptyPane(
        EmptyStateCard(
          icon: LucideIcons.qrCode,
          title: 'Sicil numarası bulunamadı',
          message: _dateRangeEmptyMessage ??
              (result.fileName.isEmpty
                  ? 'Filtrelere uyan bir sicil kaydı yok.'
                  : '${result.fileName} içinde filtrelere uyan sicil numarası yok.'),
        ),
      );
    }

    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minWidth = _TsmLogCols.minWidth;
          final tableWidth = constraints.maxWidth < minWidth
              ? minWidth
              : constraints.maxWidth;
          return ClipRRect(
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusLg),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: tableWidth,
                  height: constraints.maxHeight,
                  child: Column(
                    children: [
                      Container(
                        height: AppDenseList.headerH,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppDenseList.rowH,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.tableHeaderBg,
                          border: Border(bottom: AppDenseList.hairline),
                        ),
                        child: Row(
                          children: [
                            _TsmCell(
                              width: _TsmLogCols.check,
                              child: Checkbox(
                                tristate: true,
                                value: _selectAllValue,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: _filteredSerials.isEmpty
                                    ? null
                                    : (_) => _toggleSelectAll(),
                              ),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.date,
                              child: const _HeaderCell('Tarih'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.sicil,
                              child: const _HeaderCell('Sicil No'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.kind,
                              child: const _HeaderCell('İş Emri'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.bank,
                              child: const _HeaderCell('Banka'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.terminal,
                              child: const _HeaderCell('Terminal'),
                            ),
                            const _TsmCell(
                              flex: 3,
                              child: _HeaderCell('Üye İşyeri'),
                            ),
                            const _TsmCell(
                              flex: 4,
                              child: _HeaderCell('Adres'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.operation,
                              child: const _HeaderCell('İşlem'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.result,
                              child: const _HeaderCell('Sonuç'),
                            ),
                            _TsmCell(
                              width: _TsmLogCols.count,
                              child: const _HeaderCell('Adet'),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          clipBehavior: Clip.hardEdge,
                          itemExtent: 42,
                          itemCount: serials.length,
                          itemBuilder: (context, index) {
                            final item = serials[index];
                            final order = item.workOrder;
                            final currentQuery = _queryMode &&
                                _selectedInOrder.isNotEmpty &&
                                _selectedInOrder[_queryIndex.clamp(
                                      0,
                                      _selectedInOrder.length - 1,
                                    )] ==
                                    item.serialNumber;
                            return _TsmStripeRow(
                              index: index,
                              highlighted: currentQuery,
                              child: Row(
                                children: [
                                  _TsmCell(
                                    width: _TsmLogCols.check,
                                    child: Checkbox(
                                      value: _selectedSerials.contains(
                                        item.serialNumber,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                      onChanged: (_) =>
                                          _toggleSerial(item.serialNumber),
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.date,
                                    child: _PlainCell(
                                      _formatOccurredAt(item.occurredAt),
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.sicil,
                                    child: InkWell(
                                      onTap: () =>
                                          _toggleSerial(item.serialNumber),
                                      child: Text(
                                        item.serialNumber,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.5,
                                              height: 1.15,
                                              color: AppTheme.primary,
                                            ),
                                      ),
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.kind,
                                    child: _OrderKindCell(order: order),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.bank,
                                    child: _BankCell(
                                      name: tsmDisplayBankName(
                                        order,
                                        _bkmNames,
                                      ),
                                      acquirerId: order?.acquirerId ?? '',
                                      onEdit:
                                          (order?.acquirerId ?? '').isEmpty
                                          ? null
                                          : () => _editBkmFor(
                                              order!.acquirerId,
                                              tsmDisplayBankName(
                                                order,
                                                _bkmNames,
                                              ),
                                            ),
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.terminal,
                                    child: _PlainCell(order?.terminalId ?? ''),
                                  ),
                                  _TsmCell(
                                    flex: 3,
                                    child: _MerchantCell(order: order),
                                  ),
                                  _TsmCell(
                                    flex: 4,
                                    child: _AddressCell(order: order),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.operation,
                                    child: _TsmBadgeLine(
                                      badges: [
                                        if (_showsOperation(
                                          item,
                                          TsmLogOperation.terminalSorgu,
                                        ))
                                          _TsmTag(
                                            label: 'Sorgu',
                                            color: AppTheme.primary,
                                          ),
                                        if (_showsOperation(
                                          item,
                                          TsmLogOperation.isemriAcma,
                                        ))
                                          _TsmTag(
                                            label: 'İş emri',
                                            color: AppTheme.textMuted,
                                          ),
                                      ],
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.result,
                                    child: _TsmBadgeLine(
                                      badges: [
                                        for (final message
                                            in _resultBadgesFor(item))
                                          _TsmTag(
                                            label: message.$1,
                                            color: dsStatusToneColor(message.$2),
                                          ),
                                      ],
                                    ),
                                  ),
                                  _TsmCell(
                                    width: _TsmLogCols.count,
                                    child: Text(
                                      '${item.count}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppTheme.textMuted,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final firstDate = DateTime(now.year - 5);
    final lastDate = DateTime(now.year + 1, 12, 31);
    final picked = await showDialog<(DateTime?, DateTime?)>(
      context: context,
      builder: (context) => _TsmRangeCalendarDialog(
        firstDate: firstDate,
        lastDate: lastDate,
        start: _dateFrom,
        end: _dateTo,
        format: _dateFormat,
      ),
    );
    if (!mounted || picked == null) return;
    setState(() {
      _dateFrom = picked.$1 == null ? null : DateUtils.dateOnly(picked.$1!);
      _dateTo = picked.$2 == null ? null : DateUtils.dateOnly(picked.$2!);
    });
  }

  Future<void> _pickExcel() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx', 'xls'],
      withData: true,
    );
    final file = picked?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return;

    setState(() => _loading = true);
    try {
      final fileName = file?.name ?? 'tsm.xls';
      TsmLogParseResult? apiParsed;
      Object? apiError;
      try {
        apiParsed = await _parseViaApi(Uint8List.fromList(bytes), fileName);
      } catch (error) {
        apiError = error;
        apiParsed = null;
      }
      final local = parseTsmLogExcel(
        Uint8List.fromList(bytes),
        fileName: fileName,
      );
      final apiHasDates =
          apiParsed != null &&
          apiParsed.uniqueSerials.any((item) => item.occurredAt != null);
      final parsed = (apiHasDates ? apiParsed : null) ?? local;
      if (!mounted) return;
      setState(() {
        _result = parsed;
        _searchController.clear();
        _resultFilter = 'TUMU';
        _resultMessageFilter = '';
        _operationFilter = 'TUMU';
        _bankFilter = '';
        _orderKindFilter = 'TUMU';
        _selectedSerials.clear();
        _queryMode = false;
        _queryIndex = 0;
        _setDefaultDateRange(parsed);
      });
      final messenger = ScaffoldMessenger.of(context);
      if (parsed.error != null && parsed.isEmpty) {
        messenger.showSnackBar(SnackBar(content: Text(parsed.error!)));
        return;
      }
      final dateCount = parsed.uniqueSerials
          .where((item) => item.occurredAt != null)
          .length;
      if (dateCount == 0 && apiError != null) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Tarih okunamadı (API: $apiError). Excel’i tekrar yükleyin.',
            ),
          ),
        );
      } else {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              '${parsed.uniqueSerials.length} sicil numarası bulundu.',
            ),
          ),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel okunamadı: $error')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<TsmLogParseResult?> _parseViaApi(
    Uint8List bytes,
    String fileName,
  ) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      throw Exception('API bağlantısı yok.');
    }
    final response = await apiClient.postJson(
      '/mutate',
      body: {
        'op': 'parseTsmLog',
        'fileName': fileName,
        'fileBase64': base64Encode(bytes),
      },
    );
    return _parseResultFromJson(response, fileName);
  }

  DateTime? _occurredAtFromJson(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw.toLocal();
    if (raw is num) {
      return parseTsmLogDateTime(raw.toString());
    }
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null') return null;
    final iso = DateTime.tryParse(text);
    if (iso != null) return iso.toLocal();
    return parseTsmLogDateTime(text);
  }

  Future<void> _editBkmFor(String acquirerId, String name) async {
    final id = int.tryParse(acquirerId.trim());
    BkmAcquirerDefinition? existing;
    for (final item in _bkmItems) {
      if ('${item.bkmId}' == acquirerId.trim()) {
        existing = item;
        break;
      }
    }
    await showBkmAcquirerEditor(
      context,
      ref,
      initial: existing,
      presetBkmId: existing == null ? id : null,
      presetName: existing == null && name.isNotEmpty && !name.startsWith('BKM ')
          ? name
          : null,
    );
    ref.invalidate(bkmAcquirersProvider);
  }

  int _countMatchingKind(TsmLogResultKind kind) {
    final operation = tsmOperationFromFilter(_operationFilter);
    return _filteredSerials.where((item) {
      if (item.outcomes.isNotEmpty) {
        return item.outcomes.any((outcome) {
          if (operation != null && outcome.operation != operation) {
            return false;
          }
          if (!tsmOutcomeMatchesResultMessage(
            outcome,
            _resultMessageFilter,
          )) {
            return false;
          }
          return parseTsmLogResultKind(outcome.resultMessage) == kind;
        });
      }
      return item.resultKinds.contains(kind) &&
          tsmSerialHasResultMessage(
            item,
            resultMessageFilter: _resultMessageFilter,
            operation: operation,
          );
    }).length;
  }

  bool _showsOperation(TsmLogSerial item, TsmLogOperation operation) {
    if (!item.operations.contains(operation)) return false;
    final selected = tsmOperationFromFilter(_operationFilter);
    if (selected != null && selected != operation) return false;
    if (_resultMessageFilter.isEmpty) return true;
    if (item.outcomes.isNotEmpty) {
      return item.outcomes.any(
        (outcome) =>
            outcome.operation == operation &&
            tsmOutcomeMatchesResultMessage(outcome, _resultMessageFilter),
      );
    }
    return tsmSerialHasResultMessage(
      item,
      resultMessageFilter: _resultMessageFilter,
      operation: operation,
    );
  }

  List<(String, DsStatusTone)> _resultBadgesFor(TsmLogSerial item) {
    final selectedOperation = tsmOperationFromFilter(_operationFilter);
    final badges = <(String, DsStatusTone)>[];
    final seen = <String>{};
    final outcomes = item.outcomes.isNotEmpty
        ? item.outcomes
        : {
            for (final operation in item.operations)
              for (final kind in item.resultKinds)
                TsmLogOutcome(
                  operation: operation,
                  resultMessage: tsmResultKindLabel(kind),
                ),
          };
    for (final outcome in outcomes) {
      if (selectedOperation != null &&
          outcome.operation != selectedOperation) {
        continue;
      }
      if (!tsmOutcomeMatchesResultMessage(outcome, _resultMessageFilter)) {
        continue;
      }
      final kind = parseTsmLogResultKind(outcome.resultMessage);
      final label = switch (kind) {
        TsmLogResultKind.approved => 'Onay',
        TsmLogResultKind.serialMismatch => 'Eşleşmedi',
        _ => _shortResultMessage(outcome.resultMessage),
      };
      if (label.isEmpty || !seen.add(label)) continue;
      badges.add((
        label,
        switch (kind) {
          TsmLogResultKind.approved => DsStatusTone.success,
          TsmLogResultKind.serialMismatch => DsStatusTone.warning,
          _ => DsStatusTone.neutral,
        },
      ));
    }
    return badges;
  }

  String _shortResultMessage(String value) {
    if (value.length <= 36) return value;
    return '${value.substring(0, 33)}…';
  }

  Set<TsmLogOutcome> _outcomesFromJson(Map<String, dynamic> map) {
    final parsed = <TsmLogOutcome>{};
    final raw = map['outcomes'];
    if (raw is List) {
      for (final value in raw) {
        if (value is! Map) continue;
        final row = Map<String, dynamic>.from(value);
        final message = (row['resultMessage'] ?? '').toString().trim();
        if (message.isEmpty) continue;
        parsed.add(
          TsmLogOutcome(
            operation: row['operation']?.toString() == 'ISEMRI_ACMA'
                ? TsmLogOperation.isemriAcma
                : TsmLogOperation.terminalSorgu,
            resultMessage: message,
          ),
        );
      }
    }
    if (parsed.isNotEmpty) return parsed;
    final messages = ((map['resultMessages'] as List?) ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty);
    final operations = <TsmLogOperation>{
      for (final value in (map['operations'] as List?) ?? const [])
        value.toString() == 'ISEMRI_ACMA'
            ? TsmLogOperation.isemriAcma
            : TsmLogOperation.terminalSorgu,
    };
    if (operations.isEmpty) {
      operations.add(TsmLogOperation.terminalSorgu);
    }
    if (messages.isNotEmpty) {
      return {
        for (final operation in operations)
          for (final message in messages)
            TsmLogOutcome(operation: operation, resultMessage: message),
      };
    }
    final kinds = ((map['resultKinds'] as List?) ?? const [])
        .map((value) => value.toString());
    return {
      for (final operation in operations)
        for (final kind in kinds)
          TsmLogOutcome(
            operation: operation,
            resultMessage: kind == 'serialMismatch'
                ? tsmResultKindLabel(TsmLogResultKind.serialMismatch)
                : kind == 'other'
                ? tsmResultKindLabel(TsmLogResultKind.other)
                : tsmResultKindLabel(TsmLogResultKind.approved),
          ),
    };
  }

  String _formatOccurredAt(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    if (local.hour == 0 && local.minute == 0 && local.second == 0) {
      return _dateFormat.format(local);
    }
    return _dateTimeFormat.format(local);
  }

  TsmLogParseResult _parseResultFromJson(
    Map<String, dynamic> json,
    String fileName,
  ) {
    final unique = ((json['uniqueSerials'] as List?) ??
            ((json['data'] is Map
                    ? (json['data'] as Map)['uniqueSerials']
                    : null)
                as List?) ??
            const [])
        .whereType<Map>()
        .map((item) {
          final map = Map<String, dynamic>.from(item);
          return TsmLogSerial(
            serialNumber: (map['serialNumber'] ?? '').toString(),
            operations: {
              for (final value in (map['operations'] as List?) ?? const [])
                if (value.toString() == 'ISEMRI_ACMA')
                  TsmLogOperation.isemriAcma
                else
                  TsmLogOperation.terminalSorgu,
            },
            resultKinds: {
              for (final value in (map['resultKinds'] as List?) ?? const [])
                if (value.toString() == 'serialMismatch')
                  TsmLogResultKind.serialMismatch
                else if (value.toString() == 'other')
                  TsmLogResultKind.other
                else
                  TsmLogResultKind.approved,
            },
            outcomes: _outcomesFromJson(map),
            count: (map['count'] as num?)?.toInt() ?? 1,
            workOrder: _workOrderFromJson(map['workOrder']),
            occurredAt: _occurredAtFromJson(map['occurredAt']),
          );
        })
        .where((item) => item.serialNumber.isNotEmpty)
        .toList(growable: false);
    final catalog = ((json['resultMessageOptions'] as List?) ?? const [])
        .map((value) => value.toString().trim())
        .where((value) => value.isNotEmpty);
    return TsmLogParseResult(
      fileName: (json['fileName'] ?? fileName).toString(),
      totalRows: (json['totalRows'] as num?)?.toInt() ?? 0,
      matchedRows: (json['matchedRows'] as num?)?.toInt() ?? 0,
      skippedRows: (json['skippedRows'] as num?)?.toInt() ?? 0,
      entries: const [],
      uniqueSerials: unique,
      resultMessageOptions: tsmSortedResultMessages([
        ...catalog,
        for (final item in unique) ...item.resultMessages,
      ]),
      error: json['error']?.toString(),
    );
  }

  Future<void> _copySerials() async {
    final serials = _selectedInOrder.isNotEmpty
        ? _selectedInOrder
        : _filteredSerials
              .map((item) => item.serialNumber)
              .toList(growable: false);
    if (serials.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: serials.join('\n')));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedInOrder.isNotEmpty
              ? '${serials.length} seçili sicil kopyalandı.'
              : '${serials.length} sicil numarası kopyalandı.',
        ),
      ),
    );
  }

  Future<void> _exportSerials() async {
    final serials = _filteredSerials;
    if (serials.isEmpty) return;
    final book = excel.Excel.createExcel();
    final sheet = book['TSM Log'];
    sheet.appendRow([
      excel.TextCellValue('Tarih'),
      excel.TextCellValue('Sicil No'),
      excel.TextCellValue('İş Emri'),
      excel.TextCellValue('Banka'),
      excel.TextCellValue('BKM ID'),
      excel.TextCellValue('Terminal ID'),
      excel.TextCellValue('Üye İşyeri'),
      excel.TextCellValue('Üye İşyeri No'),
      excel.TextCellValue('BKM Merchant ID'),
      excel.TextCellValue('Adres'),
      excel.TextCellValue('İl'),
      excel.TextCellValue('İlçe'),
      excel.TextCellValue('Telefon'),
      excel.TextCellValue('Açıklama'),
      excel.TextCellValue('İşlem'),
      excel.TextCellValue('Sonuç'),
      excel.TextCellValue('Adet'),
    ]);
    for (final item in serials) {
      final order = item.workOrder;
      sheet.appendRow([
        excel.TextCellValue(_formatOccurredAt(item.occurredAt)),
        excel.TextCellValue(item.serialNumber),
        excel.TextCellValue(
          tsmOrderKindLabel(order?.orderKind ?? TsmOrderKind.unknown),
        ),
        excel.TextCellValue(tsmDisplayBankName(order, _bkmNames)),
        excel.TextCellValue(order?.acquirerId ?? ''),
        excel.TextCellValue(order?.terminalId ?? ''),
        excel.TextCellValue(order?.merchantName ?? ''),
        excel.TextCellValue(order?.merchantNo ?? ''),
        excel.TextCellValue(order?.bkmMerchantId ?? ''),
        excel.TextCellValue(order?.displayAddress ?? ''),
        excel.TextCellValue(order?.city ?? ''),
        excel.TextCellValue(order?.district ?? ''),
        excel.TextCellValue(order?.phone ?? ''),
        excel.TextCellValue(order?.description ?? ''),
        excel.TextCellValue(
          item.operations.map(_operationLabel).join(', '),
        ),
        excel.TextCellValue(
          item.resultMessages.isEmpty
              ? item.resultKinds.map(_resultLabel).join(', ')
              : item.resultMessages.join(' | '),
        ),
        excel.IntCellValue(item.count),
      ]);
    }
    final defaultSheet = book.getDefaultSheet();
    if (defaultSheet != null && defaultSheet != 'TSM Log') {
      book.delete(defaultSheet);
    }
    final bytes = book.encode();
    if (bytes == null) return;
    await downloadExcelFile(
      bytes,
      'tsm_log_sicil_${DateTime.now().millisecondsSinceEpoch}.xlsx',
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${serials.length} sicil Excel olarak aktarıldı.')),
    );
  }
}

String _operationLabel(TsmLogOperation operation) {
  return switch (operation) {
    TsmLogOperation.terminalSorgu => 'TERMINAL_SORGU',
    TsmLogOperation.isemriAcma => 'ISEMRI_ACMA',
  };
}

String _resultLabel(TsmLogResultKind kind) => tsmResultKindLabel(kind);

TsmWorkOrderDetails? _workOrderFromJson(dynamic raw) {
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  final kindRaw = (map['orderKind'] ?? '').toString();
  final kind = switch (kindRaw) {
    'kurulum' => TsmOrderKind.kurulum,
    'ekleme' => TsmOrderKind.ekleme,
    'geriAlim' => TsmOrderKind.geriAlim,
    _ => TsmOrderKind.unknown,
  };
  final details = TsmWorkOrderDetails(
    bankName: (map['bankName'] ?? '').toString().trim(),
    acquirerId: normalizeBkmAcquirerId(
      (map['acquirerId'] ?? '').toString(),
    ),
    terminalId: (map['terminalId'] ?? '').toString().trim(),
    merchantName: (map['merchantName'] ?? '').toString().trim(),
    merchantNo: (map['merchantNo'] ?? '').toString().trim(),
    bkmMerchantId: (map['bkmMerchantId'] ?? '').toString().trim(),
    address: (map['address'] ?? '').toString().trim(),
    city: (map['city'] ?? '').toString().trim(),
    district: (map['district'] ?? '').toString().trim(),
    phone: (map['phone'] ?? '').toString().trim(),
    orderCode: (map['orderCode'] ?? '').toString().trim(),
    description: (map['description'] ?? '').toString().trim(),
    orderKind: kind,
  );
  return details.isEmpty ? null : details;
}

class _TsmLogCols {
  static const check = 36.0;
  static const date = 118.0;
  static const sicil = 118.0;
  static const kind = 96.0;
  static const bank = 140.0;
  static const terminal = 88.0;
  static const merchantMin = 150.0;
  static const addressMin = 170.0;
  static const operation = 128.0;
  static const result = 148.0;
  static const count = 44.0;

  static const minWidth =
      check +
      date +
      sicil +
      kind +
      bank +
      terminal +
      merchantMin +
      addressMin +
      operation +
      result +
      count +
      16;
}

class _TsmCell extends StatelessWidget {
  const _TsmCell({
    this.width,
    this.flex,
    required this.child,
  });

  final double? width;
  final int? flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final padded = Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ClipRect(
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
    if (flex != null) {
      return Expanded(flex: flex!, child: padded);
    }
    return SizedBox(width: width, child: padded);
  }
}

class _TsmBadgeLine extends StatelessWidget {
  const _TsmBadgeLine({required this.badges});

  final List<Widget> badges;

  @override
  Widget build(BuildContext context) {
    if (badges.isEmpty) return const _PlainCell('');
    if (badges.length == 1) return badges.first;
    return Row(
      children: [
        Flexible(child: badges.first),
        const SizedBox(width: 4),
        Text(
          '+${badges.length - 1}',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Color(0xFF64748B),
          ),
        ),
      ],
    );
  }
}

class _TsmTag extends StatelessWidget {
  const _TsmTag({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.softTint(color, alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          height: 1.1,
          fontWeight: FontWeight.w600,
          color: AppTheme.softFg(color),
        ),
      ),
    );
  }
}

class _PlainCell extends StatelessWidget {
  const _PlainCell(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    if (value.isEmpty) {
      return Text(
        '—',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: AppTheme.textMuted,
          height: 1.15,
        ),
      );
    }
    return Text(
      value,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: AppTheme.text,
        height: 1.15,
      ),
    );
  }
}

class _BankCell extends StatelessWidget {
  const _BankCell({
    required this.name,
    required this.acquirerId,
    this.onEdit,
  });

  final String name;
  final String acquirerId;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    if (name.isEmpty && acquirerId.isEmpty) {
      return const _PlainCell('');
    }
    final body = Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                name.isEmpty ? 'BKM $acquirerId' : name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: AppTheme.text,
                ),
              ),
              if (name.isNotEmpty && acquirerId.isNotEmpty)
                Text(
                  'BKM $acquirerId',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                    fontSize: 11,
                  ),
                ),
            ],
          ),
        ),
        if (onEdit != null)
          Icon(
            LucideIcons.pencil,
            size: 12,
            color: AppTheme.textMuted,
          ),
      ],
    );
    if (onEdit == null) return body;
    return InkWell(onTap: onEdit, child: body);
  }
}

class _MerchantCell extends StatelessWidget {
  const _MerchantCell({required this.order});

  final TsmWorkOrderDetails? order;

  @override
  Widget build(BuildContext context) {
    final name = order?.merchantName ?? '';
    final extras = [
      if ((order?.merchantNo ?? '').isNotEmpty) order!.merchantNo,
      if ((order?.bkmMerchantId ?? '').isNotEmpty)
        'BKM ${order!.bkmMerchantId}',
    ].join(' · ');
    if (name.isEmpty && extras.isEmpty) {
      return const _PlainCell('');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (name.isNotEmpty)
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.text,
            ),
          ),
        if (extras.isNotEmpty)
          Text(
            extras,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

class _AddressCell extends StatelessWidget {
  const _AddressCell({required this.order});

  final TsmWorkOrderDetails? order;

  @override
  Widget build(BuildContext context) {
    final address = order?.displayAddress ?? '';
    final phone = order?.phone ?? '';
    if (address.isEmpty && phone.isEmpty) {
      return const _PlainCell('');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (address.isNotEmpty)
          Text(
            address,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.text,
            ),
          ),
        if (phone.isNotEmpty)
          Text(
            phone,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textMuted,
              fontSize: 11,
            ),
          ),
      ],
    );
  }
}

class _OrderKindCell extends StatelessWidget {
  const _OrderKindCell({required this.order});

  final TsmWorkOrderDetails? order;

  @override
  Widget build(BuildContext context) {
    final kind = order?.orderKind ?? TsmOrderKind.unknown;
    if (kind == TsmOrderKind.unknown) {
      return const _PlainCell('');
    }
    final badge = _TsmTag(
      label: tsmOrderKindLabel(kind),
      color: switch (kind) {
        TsmOrderKind.kurulum => AppTheme.success,
        TsmOrderKind.ekleme => AppTheme.primary,
        TsmOrderKind.geriAlim => AppTheme.warning,
        TsmOrderKind.unknown => AppTheme.textMuted,
      },
    );
    final description = order?.description.trim() ?? '';
    if (description.isEmpty) return badge;
    return Tooltip(message: description, child: badge);
  }
}

class _TsmStripeRow extends StatefulWidget {
  const _TsmStripeRow({
    required this.index,
    required this.child,
    this.highlighted = false,
  });

  final int index;
  final Widget child;
  final bool highlighted;

  @override
  State<_TsmStripeRow> createState() => _TsmStripeRowState();
}

class _TsmStripeRowState extends State<_TsmStripeRow> {
  bool _hovered = false;

  Color get _fill {
    if (widget.highlighted) {
      return AppTheme.softTint(AppTheme.primary, alpha: 0.16);
    }
    if (_hovered) {
      return AppTheme.softTint(AppTheme.primary, alpha: 0.10);
    }
    return widget.index.isOdd ? AppTheme.surfaceSoft : AppTheme.surface;
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: ColoredBox(
        color: _fill,
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: AppDenseList.hairline),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppDenseList.rowH),
            child: ClipRect(child: widget.child),
          ),
        ),
      ),
    );
  }
}

class _FilterGroup extends StatelessWidget {
  const _FilterGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 78,
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: children,
          ),
        ),
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.maxWidth,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      widthFactor: 1,
      child: Material(
        color: selected
            ? AppTheme.softTint(AppTheme.primary, alpha: 0.14)
            : AppTheme.surfaceSoft,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(
            color: selected
                ? AppTheme.softBorder(AppTheme.primary, alpha: 0.45)
                : AppTheme.border,
          ),
        ),
        clipBehavior: Clip.antiAlias,
          child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: ConstrainedBox(
              constraints: maxWidth == null
                  ? const BoxConstraints()
                  : BoxConstraints(maxWidth: maxWidth!),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.1,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.primary : AppTheme.textSoft,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateFilterField extends StatelessWidget {
  const _DateFilterField({
    required this.label,
    required this.from,
    required this.to,
    required this.format,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? from;
  final DateTime? to;
  final DateFormat format;
  final VoidCallback onTap;
  final VoidCallback onClear;

  String get _display {
    if (from == null && to == null) return 'Tüm tarihler';
    if (from != null && to != null && DateUtils.isSameDay(from!, to!)) {
      return format.format(from!);
    }
    final start = from == null ? '…' : format.format(from!);
    final end = to == null ? '…' : format.format(to!);
    return '$start – $end';
  }

  @override
  Widget build(BuildContext context) {
    final hasValue = from != null || to != null;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSm),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          suffixIcon: hasValue
              ? IconButton(
                  tooltip: 'Tüm tarihler',
                  onPressed: onClear,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 32,
                    height: 32,
                  ),
                  iconSize: 16,
                  icon: const Icon(LucideIcons.x),
                )
              : const Icon(LucideIcons.calendarDays, size: 16),
        ),
        child: Text(_display),
      ),
    );
  }
}

class _TsmRangeCalendarDialog extends StatefulWidget {
  const _TsmRangeCalendarDialog({
    required this.firstDate,
    required this.lastDate,
    required this.start,
    required this.end,
    required this.format,
  });

  final DateTime firstDate;
  final DateTime lastDate;
  final DateTime? start;
  final DateTime? end;
  final DateFormat format;

  @override
  State<_TsmRangeCalendarDialog> createState() =>
      _TsmRangeCalendarDialogState();
}

class _TsmRangeCalendarDialogState extends State<_TsmRangeCalendarDialog> {
  late DateTime _visibleMonth;
  DateTime? _start;
  DateTime? _end;

  static const _weekdays = ['Pt', 'Sa', 'Ça', 'Pe', 'Cu', 'Ct', 'Pz'];

  @override
  void initState() {
    super.initState();
    _start = widget.start == null ? null : DateUtils.dateOnly(widget.start!);
    _end = widget.end == null ? null : DateUtils.dateOnly(widget.end!);
    _visibleMonth = DateTime(
      (_start ?? DateTime.now()).year,
      (_start ?? DateTime.now()).month,
    );
  }

  void _selectDay(DateTime day) {
    final date = DateUtils.dateOnly(day);
    setState(() {
      if (_start == null || (_start != null && _end != null)) {
        _start = date;
        _end = null;
        return;
      }
      if (date.isBefore(_start!)) {
        _end = _start;
        _start = date;
      } else {
        _end = date;
      }
    });
  }

  bool _inRange(DateTime day) {
    if (_start == null) return false;
    final end = _end ?? _start!;
    return !day.isBefore(_start!) && !day.isAfter(end);
  }

  @override
  Widget build(BuildContext context) {
    final startText = _start == null ? '—' : widget.format.format(_start!);
    final endText = _end == null
        ? (_start == null ? '—' : widget.format.format(_start!))
        : widget.format.format(_end!);
    final daysInMonth = DateUtils.getDaysInMonth(
      _visibleMonth.year,
      _visibleMonth.month,
    );
    final firstWeekday = DateTime(
      _visibleMonth.year,
      _visibleMonth.month,
      1,
    ).weekday;
    final leading = firstWeekday - 1;
    final monthLabel = DateFormat('MMMM yyyy', 'tr_TR').format(_visibleMonth);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Tarih aralığı',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(LucideIcons.x),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Aynı takvimde önce başlangıç, sonra bitiş gününü seçin.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textMuted,
                  ),
                ),
              ),
              const Gap(12),
              Row(
                children: [
                  Expanded(child: _RangeChip(label: 'Başlangıç', value: startText)),
                  const Gap(8),
                  Expanded(child: _RangeChip(label: 'Bitiş', value: endText)),
                ],
              ),
              const Gap(12),
              Row(
                children: [
                  IconButton(
                    onPressed: () => setState(() {
                      _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month - 1,
                      );
                    }),
                    icon: const Icon(LucideIcons.chevronLeft),
                  ),
                  Expanded(
                    child: Text(
                      monthLabel,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => setState(() {
                      _visibleMonth = DateTime(
                        _visibleMonth.year,
                        _visibleMonth.month + 1,
                      );
                    }),
                    icon: const Icon(LucideIcons.chevronRight),
                  ),
                ],
              ),
              Row(
                children: [
                  for (final day in _weekdays)
                    Expanded(
                      child: Text(
                        day,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppTheme.textMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
              const Gap(6),
              for (var row = 0; row < 6; row++)
                Row(
                  children: [
                    for (var col = 0; col < 7; col++)
                      Expanded(
                        child: _dayCell(
                          cellIndex: row * 7 + col,
                          leading: leading,
                          daysInMonth: daysInMonth,
                        ),
                      ),
                  ],
                ),
              const Gap(14),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () =>
                          Navigator.of(context).pop((null, null)),
                      child: const Text('Tüm tarihler'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _start == null
                          ? null
                          : () => Navigator.of(context).pop((
                              _start,
                              _end ?? _start,
                            )),
                      child: const Text('Uygula'),
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

  Widget _dayCell({
    required int cellIndex,
    required int leading,
    required int daysInMonth,
  }) {
    final dayNum = cellIndex - leading + 1;
    if (dayNum < 1 || dayNum > daysInMonth) {
      return const SizedBox(height: 36);
    }
    final day = DateTime(_visibleMonth.year, _visibleMonth.month, dayNum);
    final enabled =
        !day.isBefore(DateUtils.dateOnly(widget.firstDate)) &&
        !day.isAfter(DateUtils.dateOnly(widget.lastDate));
    final selectedStart =
        _start != null && DateUtils.isSameDay(day, _start!);
    final selectedEnd =
        _end != null && DateUtils.isSameDay(day, _end!);
    final inRange = _inRange(day);
    return Padding(
      padding: const EdgeInsets.all(2),
      child: Material(
        color: selectedStart || selectedEnd
            ? AppTheme.primary
            : inRange
            ? AppTheme.softTint(AppTheme.primary, alpha: 0.16)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: enabled ? () => _selectDay(day) : null,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            height: 36,
            child: Center(
              child: Text(
                '$dayNum',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: !enabled
                      ? AppTheme.textMuted.withValues(alpha: 0.4)
                      : selectedStart || selectedEnd
                      ? Colors.white
                      : AppTheme.text,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  const _RangeChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppTheme.textMuted,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
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
        color: AppTheme.textMuted,
      ),
    );
  }
}
