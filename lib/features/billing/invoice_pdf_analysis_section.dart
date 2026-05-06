import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';

import '../../app/theme/app_theme.dart';
import '../../core/ui/app_card.dart';
import 'invoice_pdf_analysis_export.dart';
import 'invoice_pdf_analysis_file_save.dart';
import 'invoice_pdf_analysis_model.dart';
import 'invoice_pdf_analysis_parser.dart';
import 'invoice_pdf_analysis_pick_files.dart';
import 'invoice_pdf_analysis_provider.dart';

class InvoicePdfAnalysisSection extends ConsumerStatefulWidget {
  const InvoicePdfAnalysisSection({super.key});

  @override
  ConsumerState<InvoicePdfAnalysisSection> createState() =>
      _InvoicePdfAnalysisSectionState();
}

class _InvoicePdfAnalysisSectionState
    extends ConsumerState<InvoicePdfAnalysisSection> {
  late final TextEditingController _queryController;
  late final TextEditingController _fxRateController;
  bool _exportingExcel = false;
  bool _exportingPdf = false;
  String? _uploadStatusMessage;
  String _selectedPeriod = 'TUMU';
  String _selectedCurrency = 'TUMU';
  String _selectedTaxRate = 'TUMU';
  DateTime? _filterStartDate;
  DateTime? _filterEndDate;
  String _fxCurrency = 'USD';
  DateTime? _fxStartDate;
  DateTime? _fxEndDate;

  @override
  void initState() {
    super.initState();
    _queryController = TextEditingController();
    _fxRateController = TextEditingController();
  }

  @override
  void dispose() {
    _queryController.dispose();
    _fxRateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(invoicePdfAnalysisProvider);
    final notifier = ref.read(invoicePdfAnalysisProvider.notifier);
    final query = _queryController.text.trim().toLowerCase();
    final entries = state.entries.where((entry) {
      if (query.isEmpty) return true;
      final haystack = [
        entry.customerName,
        entry.invoiceNumber,
        entry.fileName,
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
    final sanitizedEntries = entries
        .map(_sanitizeEntryForDisplay)
        .whereType<InvoicePdfAnalysisEntry>()
        .toList(growable: false);
    final allRows = _buildListRows(sanitizedEntries);
    final periodOptions = <String>{
      'TUMU',
      ...allRows
          .where((row) => row.invoiceDate != null)
          .map((row) => _periodKey(row.invoiceDate!)),
    }.toList(growable: false)
      ..sort((a, b) {
        if (a == 'TUMU') return -1;
        if (b == 'TUMU') return 1;
        return b.compareTo(a);
      });
    final currencyOptions = <String>{
      'TUMU',
      ...allRows
          .map((row) => row.currency)
          .where((value) => value.trim().isNotEmpty),
    }.toList(growable: false)
      ..sort();
    final taxRateOptions = <String>{
      'TUMU',
      ...allRows.expand(
        (row) => row.vatBreakdowns.map((item) => _taxRateKey(item.taxRate)),
      ),
    }.toList(growable: false)
      ..sort((a, b) {
        if (a == 'TUMU') return -1;
        if (b == 'TUMU') return 1;
        return double.parse(a).compareTo(double.parse(b));
      });
    final rows = allRows.where((row) {
      final periodOk =
          _selectedPeriod == 'TUMU' ||
          (row.invoiceDate != null &&
              _periodKey(row.invoiceDate!) == _selectedPeriod);
      final currencyOk =
          _selectedCurrency == 'TUMU' || row.currency == _selectedCurrency;
      final taxOk =
          _selectedTaxRate == 'TUMU' ||
          row.vatBreakdowns.any(
            (item) => _taxRateKey(item.taxRate) == _selectedTaxRate,
          );
      final startOk =
          _filterStartDate == null ||
          (row.invoiceDate != null &&
              !_normalizeDate(row.invoiceDate!).isBefore(
                _normalizeDate(_filterStartDate!),
              ));
      final endOk =
          _filterEndDate == null ||
          (row.invoiceDate != null &&
              !_normalizeDate(row.invoiceDate!).isAfter(
                _normalizeDate(_filterEndDate!),
              ));
      return periodOk && currencyOk && taxOk && startOk && endOk;
    }).toList(growable: false);
    final summaries = _buildSummariesForRows(rows, state.fxRules);
    final filteredInvoiceCount = rows
        .map(
          (row) =>
              '${row.invoiceNumber}|${row.currency}|${_formatDate(row.invoiceDate)}',
        )
        .toSet()
        .length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        AppCard(
          padding: const EdgeInsets.all(16),
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
                          'PDF KDV Analizi',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const Gap(4),
                        Text(
                          'Liste fatura numarasi, tarih, fatura tutari, KDV orani ve KDV tutarina gore duzenlenir. Excel ve PDF olarak aktarabilirsiniz.',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Gap(12),
                  if (state.isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                ],
              ),
              const Gap(12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: state.isLoading ? null : _pickAndImportPdfs,
                    icon: const Icon(Icons.upload_file_rounded, size: 18),
                    label: const Text('PDF Yukle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.entries.isEmpty || state.isLoading
                        ? null
                        : _saveCurrentList,
                    icon: const Icon(Icons.save_rounded, size: 18),
                    label: const Text('Listeyi Kaydet'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.isLoading ? null : _loadSavedList,
                    icon: const Icon(Icons.restore_page_rounded, size: 18),
                    label: const Text('Kayitli Listeyi Yukle'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.lastSavedAtMs == null || state.isLoading
                        ? null
                        : _clearSavedList,
                    icon: const Icon(Icons.auto_delete_rounded, size: 18),
                    label: const Text('Kayitli Listeyi Sil'),
                  ),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty || _exportingExcel || state.isLoading
                        ? null
                        : () => _exportExcel(rows),
                    icon: _exportingExcel
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.table_view_rounded, size: 18),
                    label: const Text('Excel Aktar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty || _exportingPdf || state.isLoading
                        ? null
                        : () => _exportPdf(rows),
                    icon: _exportingPdf
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.picture_as_pdf_rounded, size: 18),
                    label: const Text('PDF Aktar'),
                  ),
                  OutlinedButton.icon(
                    onPressed: state.entries.isEmpty || state.isLoading
                        ? null
                        : notifier.clear,
                    icon: const Icon(Icons.delete_sweep_rounded, size: 18),
                    label: const Text('Listeyi Temizle'),
                  ),
                ],
              ),
              if (_uploadStatusMessage?.trim().isNotEmpty ?? false) ...[
                const Gap(10),
                Text(
                  _uploadStatusMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF0F172A),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const Gap(12),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 320,
                    child: TextField(
                      controller: _queryController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search_rounded),
                        labelText: 'Ara',
                        hintText: 'Fatura no veya musteri',
                        suffixIcon: _queryController.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Temizle',
                                onPressed: () => setState(_queryController.clear),
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: periodOptions.contains(_selectedPeriod)
                          ? _selectedPeriod
                          : 'TUMU',
                      decoration: const InputDecoration(
                        labelText: 'Donem',
                      ),
                      items: periodOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value == 'TUMU'
                                    ? 'Tum don.'
                                    : _periodLabel(value),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _selectedPeriod = value ?? 'TUMU';
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: OutlinedButton(
                      onPressed: () => _pickFilterDate(isStart: true),
                      child: Row(
                        children: [
                          const Icon(Icons.event_rounded, size: 18),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              _filterStartDate == null
                                  ? 'Bas. Tarih'
                                  : _formatDate(_filterStartDate),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: OutlinedButton(
                      onPressed: () => _pickFilterDate(isStart: false),
                      child: Row(
                        children: [
                          const Icon(Icons.event_available_rounded, size: 18),
                          const Gap(8),
                          Expanded(
                            child: Text(
                              _filterEndDate == null
                                  ? 'Bit. Tarih'
                                  : _formatDate(_filterEndDate),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: currencyOptions.contains(_selectedCurrency)
                          ? _selectedCurrency
                          : 'TUMU',
                      decoration: const InputDecoration(
                        labelText: 'Para Birimi',
                      ),
                      items: currencyOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value == 'TUMU' ? 'Tum PB' : value,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _selectedCurrency = value ?? 'TUMU';
                        });
                      },
                    ),
                  ),
                  SizedBox(
                    width: 160,
                    child: DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: taxRateOptions.contains(_selectedTaxRate)
                          ? _selectedTaxRate
                          : 'TUMU',
                      decoration: const InputDecoration(
                        labelText: 'KDV Orani',
                      ),
                      items: taxRateOptions
                          .map(
                            (value) => DropdownMenuItem<String>(
                              value: value,
                              child: Text(
                                value == 'TUMU'
                                    ? 'Tum KDV'
                                    : '%${_formatPercent(double.parse(value))}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: (value) {
                        setState(() {
                          _selectedTaxRate = value ?? 'TUMU';
                        });
                      },
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () {
                      setState(() {
                        _selectedPeriod = 'TUMU';
                        _filterStartDate = null;
                        _filterEndDate = null;
                        _selectedCurrency = 'TUMU';
                        _selectedTaxRate = 'TUMU';
                        _queryController.clear();
                      });
                    },
                    icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                    label: const Text('Filtreleri Sifirla'),
                  ),
                ],
              ),
              const Gap(12),
              _FxRateCard(
                rules: state.fxRules,
                selectedCurrency: _fxCurrency,
                rateController: _fxRateController,
                startDate: _fxStartDate,
                endDate: _fxEndDate,
                onCurrencyChanged: (value) {
                  setState(() => _fxCurrency = value);
                },
                onPickStartDate: () => _pickFxDate(isStart: true),
                onPickEndDate: () => _pickFxDate(isStart: false),
                onSave: _saveFxRule,
                onDelete: _deleteFxRule,
              ),
              if (state.lastSavedAtMs != null) ...[
                const Gap(10),
                Text(
                  'Kayitli liste: ${DateFormat('dd.MM.yyyy HH:mm', 'tr_TR').format(DateTime.fromMillisecondsSinceEpoch(state.lastSavedAtMs!))}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ],
              if (state.errorMessage?.trim().isNotEmpty ?? false) ...[
                const Gap(12),
                Text(
                  state.errorMessage!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const Gap(12),
        if (state.entries.isEmpty)
          const _InvoicePdfEmptyState()
        else ...[
          _PdfOverviewCards(
            invoiceCount: filteredInvoiceCount,
            rowCount: rows.length,
            summaries: summaries,
            fxRules: state.fxRules,
          ),
          const Gap(12),
          _InvoicePdfRowsTable(rows: rows),
        ],
      ],
    );
  }

  Future<void> _exportExcel(List<InvoicePdfAnalysisListRow> rows) async {
    setState(() => _exportingExcel = true);
    try {
      final bytes = await buildInvoicePdfAnalysisExcelBytes(
        rows,
        ref.read(invoicePdfAnalysisProvider).fxRules,
      );
      await saveAnalysisFile(
        bytes: bytes,
        filename: 'kdv_analizi_${DateTime.now().millisecondsSinceEpoch}.xlsx',
        mimeType:
            'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Excel dosyasi hazirlandi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel aktarimi basarisiz: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingExcel = false);
    }
  }

  Future<void> _exportPdf(List<InvoicePdfAnalysisListRow> rows) async {
    setState(() => _exportingPdf = true);
    try {
      final bytes = await buildInvoicePdfAnalysisPdfBytes(
        rows,
        ref.read(invoicePdfAnalysisProvider).fxRules,
      );
      await saveAnalysisFile(
        bytes: bytes,
        filename: 'kdv_analizi_${DateTime.now().millisecondsSinceEpoch}.pdf',
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PDF dosyasi hazirlandi.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF aktarimi basarisiz: $e')),
      );
    } finally {
      if (mounted) setState(() => _exportingPdf = false);
    }
  }

  Future<void> _pickAndImportPdfs() async {
    try {
      setState(() => _uploadStatusMessage = 'PDF secimi bekleniyor...');
      final beforeCount = ref.read(invoicePdfAnalysisProvider).entries.length;
      final files = await pickInvoicePdfFiles();
      if (files.isEmpty) {
        setState(() => _uploadStatusMessage = 'PDF secilmedi.');
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PDF secilmedi.')),
        );
        return;
      }
      setState(() {
        _uploadStatusMessage = '${files.length} PDF secildi, analiz ediliyor...';
      });
      await ref.read(invoicePdfAnalysisProvider.notifier).importPickedFiles(files);
      if (!mounted) return;
      final nextState = ref.read(invoicePdfAnalysisProvider);
      final importedCount = nextState.entries.length - beforeCount;
      final errorMessage = nextState.errorMessage?.trim();
      if (errorMessage != null && errorMessage.isNotEmpty) {
        setState(() => _uploadStatusMessage = errorMessage);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMessage)),
        );
        return;
      }
      setState(() {
        _uploadStatusMessage = importedCount > 0
            ? '$importedCount PDF listeye eklendi.'
            : 'Secilen PDFler listeye eklenmedi.';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            importedCount > 0
                ? '$importedCount PDF listeye eklendi.'
                : 'Secilen PDFler listeye eklenmedi.',
          ),
        ),
      );
    } catch (e) {
      setState(() => _uploadStatusMessage = 'PDF secilemedi: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF secilemedi: $e')),
      );
    }
  }

  Future<void> _saveCurrentList() async {
    final count = await ref
        .read(invoicePdfAnalysisProvider.notifier)
        .saveCurrentEntries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count kayitli fatura listesi saklandi.')),
    );
  }

  Future<void> _loadSavedList() async {
    final count = await ref
        .read(invoicePdfAnalysisProvider.notifier)
        .loadSavedEntries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          count == 0
              ? 'Kayitli liste bulunamadi.'
              : '$count kayitli fatura listeye yuklendi.',
        ),
      ),
    );
  }

  Future<void> _clearSavedList() async {
    await ref.read(invoicePdfAnalysisProvider.notifier).clearSavedEntries();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kayitli liste silindi.')),
    );
  }

  Future<void> _pickFilterDate({required bool isStart}) async {
    final initial = isStart
        ? (_filterStartDate ?? DateTime.now())
        : (_filterEndDate ?? _filterStartDate ?? DateTime.now());
    final picked = await _showAppDatePicker(initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _filterStartDate = picked;
      } else {
        _filterEndDate = picked;
      }
      _selectedPeriod = 'TUMU';
    });
  }

  Future<void> _pickFxDate({required bool isStart}) async {
    final initial = isStart
        ? (_fxStartDate ?? DateTime.now())
        : (_fxEndDate ?? _fxStartDate ?? DateTime.now());
    final picked = await _showAppDatePicker(initial);
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _fxStartDate = picked;
      } else {
        _fxEndDate = picked;
      }
    });
  }

  Future<DateTime?> _showAppDatePicker(DateTime initialDate) {
    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.28),
      builder: (dialogContext) {
        var selectedDate = initialDate;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            return Dialog(
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 24,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tarih Sec',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: AppTheme.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Gap(12),
                      Theme(
                        data: Theme.of(context).copyWith(
                          colorScheme: Theme.of(context).colorScheme.copyWith(
                            primary: AppTheme.primaryDark,
                            onPrimary: Colors.white,
                            onSurface: AppTheme.text,
                            surface: Colors.white,
                          ),
                        ),
                        child: CalendarDatePicker(
                          initialDate: selectedDate,
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                          onDateChanged: (value) {
                            setLocalState(() {
                              selectedDate = value;
                            });
                          },
                        ),
                      ),
                      const Gap(8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(dialogContext).pop(),
                            child: const Text('Iptal'),
                          ),
                          const Gap(8),
                          FilledButton(
                            onPressed: () {
                              Navigator.of(dialogContext).pop(selectedDate);
                            },
                            child: const Text('Tamam'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _saveFxRule() async {
    final rate = double.tryParse(_fxRateController.text.replaceAll(',', '.'));
    if (_fxStartDate == null || _fxEndDate == null || rate == null || rate <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kur, baslangic ve bitis tarihi girin.')),
      );
      return;
    }
    final rule = InvoicePdfFxRateRule(
      id:
          '${_fxCurrency}_${_fxStartDate!.millisecondsSinceEpoch}_${_fxEndDate!.millisecondsSinceEpoch}',
      currency: _fxCurrency,
      startDate: _fxStartDate!,
      endDate: _fxEndDate!,
      rateToTry: rate,
    );
    await ref.read(invoicePdfAnalysisProvider.notifier).addFxRule(rule);
    if (!mounted) return;
    setState(() {
      _fxRateController.clear();
      _fxStartDate = null;
      _fxEndDate = null;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kur bilgisi kaydedildi.')),
    );
  }

  Future<void> _deleteFxRule(String id) async {
    await ref.read(invoicePdfAnalysisProvider.notifier).removeFxRule(id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Kur bilgisi silindi.')),
    );
  }
}

class _InvoicePdfEmptyState extends StatelessWidget {
  const _InvoicePdfEmptyState();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const Icon(
              Icons.picture_as_pdf_rounded,
              size: 42,
              color: Color(0xFF94A3B8),
            ),
            const Gap(12),
            Text(
              'Analiz icin henuz PDF yuklenmedi.',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const Gap(6),
            Text(
              'Yukleme sonrasi KDV oran bazli dashboard ve aktarilabilir muhasebe listesi burada gorunur.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PdfOverviewCards extends StatelessWidget {
  const _PdfOverviewCards({
    required this.invoiceCount,
    required this.rowCount,
    required this.summaries,
    required this.fxRules,
  });

  final int invoiceCount;
  final int rowCount;
  final List<InvoicePdfCurrencySummary> summaries;
  final List<InvoicePdfFxRateRule> fxRules;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _TopStatCard(
              title: 'Toplam PDF',
              value: invoiceCount.toString(),
              subtitle: '$rowCount liste satiri',
              tone: AppTheme.primary,
            ),
            _TopStatCard(
              title: 'TL KDV',
              value: _formatAmount(
                _findCurrency(summaries, 'TRY')?.taxTotal ?? 0,
                'TRY',
              ),
              subtitle: 'Oran toplamlarindan',
              tone: AppTheme.warning,
            ),
            _TopStatCard(
              title: 'USD KDV',
              value: _formatAmount(
                _findCurrency(summaries, 'USD')?.taxTotal ?? 0,
                'USD',
              ),
              subtitle: 'Oran toplamlarindan',
              tone: AppTheme.success,
            ),
            _TopStatCard(
              title: 'TL Karsiligi',
              value: _formatAmount(
                summaries.fold<double>(0, (sum, item) => sum + item.tlEquivalent),
                'TRY',
              ),
              subtitle: 'Kur tanimlarina gore',
              tone: AppTheme.primary,
            ),
          ],
        ),
        const Gap(12),
        _VatRateOverviewWrap(summaries: summaries, fxRules: fxRules),
      ],
    );
  }
}

class _VatRateOverviewWrap extends StatelessWidget {
  const _VatRateOverviewWrap({
    required this.summaries,
    required this.fxRules,
  });

  final List<InvoicePdfCurrencySummary> summaries;
  final List<InvoicePdfFxRateRule> fxRules;

  @override
  Widget build(BuildContext context) {
    final groups = <_VatRateOverviewItem>[];
    for (final summary in summaries) {
      for (final vat in summary.vatGroups) {
        groups.add(
          _VatRateOverviewItem(
            currency: summary.currency,
            taxRate: vat.taxRate,
            baseAmount: vat.baseAmount,
            taxAmount: vat.taxAmount,
            grandTotal: vat.grandTotal,
            tlEquivalent: vat.tlEquivalent,
          ),
        );
      }
    }

    if (groups.isEmpty) return const SizedBox.shrink();

    groups.sort((a, b) {
      final currencyCompare = a.currency.compareTo(b.currency);
      if (currencyCompare != 0) return currencyCompare;
      return a.taxRate.compareTo(b.taxRate);
    });

    return Align(
      alignment: Alignment.centerLeft,
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: groups
            .map((item) => _VatRateCard(item: item))
            .toList(growable: false),
      ),
    );
  }
}

class _VatRateCard extends StatelessWidget {
  const _VatRateCard({required this.item});

  final _VatRateOverviewItem item;

  @override
  Widget build(BuildContext context) {
    final accent = item.currency == 'USD'
        ? AppTheme.success
        : item.currency == 'TRY'
            ? AppTheme.warning
            : AppTheme.primary;

    return SizedBox(
      width: 260,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${item.currency} %${_formatPercent(item.taxRate)}',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(10),
            Text(
              'KDV ${_formatAmount(item.taxAmount, item.currency)}',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(4),
            Text(
              'Matrah ${_formatAmount(item.baseAmount, item.currency)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
            const Gap(2),
            Text(
              'Vergili Toplam ${_formatAmount(item.grandTotal, item.currency)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
            const Gap(2),
            Text(
              'TL Karsiligi ${_formatAmount(item.tlEquivalent, 'TRY')}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FxRateCard extends StatelessWidget {
  const _FxRateCard({
    required this.rules,
    required this.selectedCurrency,
    required this.rateController,
    required this.startDate,
    required this.endDate,
    required this.onCurrencyChanged,
    required this.onPickStartDate,
    required this.onPickEndDate,
    required this.onSave,
    required this.onDelete,
  });

  final List<InvoicePdfFxRateRule> rules;
  final String selectedCurrency;
  final TextEditingController rateController;
  final DateTime? startDate;
  final DateTime? endDate;
  final ValueChanged<String> onCurrencyChanged;
  final VoidCallback onPickStartDate;
  final VoidCallback onPickEndDate;
  final VoidCallback onSave;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final sortedRules = [...rules]
      ..sort((a, b) {
        final currencyCompare = a.currency.compareTo(b.currency);
        if (currencyCompare != 0) return currencyCompare;
        return a.startDate.compareTo(b.startDate);
      });

    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Kur Tanimlari',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Gap(6),
          Text(
            'Iki tarih arasina kur girin. Dip toplamda yabanci para faturalarin TL karsiligi ayrica hesaplanir.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: const Color(0xFF64748B),
            ),
          ),
          const Gap(12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 130,
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  initialValue: selectedCurrency,
                  decoration: const InputDecoration(labelText: 'Para Birimi'),
                  items: const ['USD', 'EUR', 'GBP']
                      .map(
                        (value) => DropdownMenuItem<String>(
                          value: value,
                          child: Text(value),
                        ),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value != null) onCurrencyChanged(value);
                  },
                ),
              ),
              SizedBox(
                width: 170,
                child: _DatePickerField(
                  label: 'Kur Baslangic',
                  value: startDate,
                  icon: Icons.date_range_rounded,
                  onTap: onPickStartDate,
                ),
              ),
              SizedBox(
                width: 170,
                child: _DatePickerField(
                  label: 'Kur Bitis',
                  value: endDate,
                  icon: Icons.edit_calendar_rounded,
                  onTap: onPickEndDate,
                ),
              ),
              SizedBox(
                width: 150,
                child: TextField(
                  controller: rateController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Kur',
                    hintText: '36,50',
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: onSave,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Kur Ekle'),
              ),
            ],
          ),
          if (sortedRules.isNotEmpty) ...[
            const Gap(12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: sortedRules
                  .map(
                    (rule) => Chip(
                      label: Text(
                        '${rule.currency} ${_formatDate(rule.startDate)} - ${_formatDate(rule.endDate)} = ${rule.rateToTry.toStringAsFixed(4)}',
                      ),
                      onDeleted: () => onDelete(rule.id),
                    ),
                  )
                  .toList(growable: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _InvoicePdfRowsTable extends StatelessWidget {
  const _InvoicePdfRowsTable({required this.rows});

  final List<InvoicePdfAnalysisListRow> rows;

  @override
  Widget build(BuildContext context) {
    final vatRates = _collectVatRates(rows);
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(
              'Muhasebe Listesi',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const Gap(12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              columns: [
                const DataColumn(label: Text('Fatura No')),
                const DataColumn(label: Text('Musteri')),
                const DataColumn(label: Text('Tarih')),
                const DataColumn(label: Text('PB')),
                const DataColumn(label: Text('Fatura Tutari')),
                ...vatRates.map(
                  (rate) => DataColumn(
                    label: Text('KDV %${_formatPercent(rate)}'),
                  ),
                ),
                const DataColumn(label: Text('Toplam KDV')),
              ],
              rows: rows
                  .map(
                    (row) => DataRow(
                      cells: [
                        DataCell(Text(row.invoiceNumber)),
                        DataCell(Text(row.customerName)),
                        DataCell(Text(_formatDate(row.invoiceDate))),
                        DataCell(Text(row.currency)),
                        DataCell(Text(_formatAmount(row.invoiceTotal, row.currency))),
                        ...vatRates.map(
                          (rate) => DataCell(
                            Text(
                              _formatAmount(
                                row.taxAmountForRate(rate),
                                row.currency,
                              ),
                            ),
                          ),
                        ),
                        DataCell(
                          Text(_formatAmount(row.totalTaxAmount, row.currency)),
                        ),
                      ],
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopStatCard extends StatelessWidget {
  const _TopStatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.tone,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
            const Gap(8),
            Text(
              value,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                color: tone,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Gap(4),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final DateTime? value;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      readOnly: true,
      canRequestFocus: false,
      onTap: onTap,
      decoration: InputDecoration(
        labelText: label,
        hintText: value == null ? 'Tarih sec' : null,
        prefixIcon: Icon(icon, size: 18),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
      ),
      controller: TextEditingController(
        text: value == null ? '' : _formatDate(value),
      ),
    );
  }
}

List<double> _collectVatRates(List<InvoicePdfAnalysisListRow> rows) {
  final rates = <double>{
    for (final row in rows)
      ...row.vatBreakdowns.map((item) => item.taxRate),
  }.toList(growable: false)
    ..sort();
  return rates;
}

List<InvoicePdfAnalysisListRow> _buildListRows(
  List<InvoicePdfAnalysisEntry> entries,
) {
  final rows = <InvoicePdfAnalysisListRow>[];
  for (final entry in entries) {
    final grouped = <double, double>{};
    final baseByRate = <double, double>{};
    final grandByRate = <double, double>{};
    for (final item in entry.items) {
      grouped.update(
        item.taxRate,
        (value) => value + item.taxAmount,
        ifAbsent: () => item.taxAmount,
      );
      baseByRate.update(
        item.taxRate,
        (value) => value + item.lineBaseAmount,
        ifAbsent: () => item.lineBaseAmount,
      );
      grandByRate.update(
        item.taxRate,
        (value) => value + item.lineGrandTotal,
        ifAbsent: () => item.lineGrandTotal,
      );
    }
    if (grouped.isEmpty) {
      rows.add(
        InvoicePdfAnalysisListRow(
          customerName: entry.customerName,
          invoiceNumber: entry.invoiceNumber,
          invoiceDate: entry.invoiceDate,
          currency: entry.currency,
          invoiceTotal: entry.grandTotal,
          vatBreakdowns: [
            InvoicePdfAnalysisVatBreakdown(
              baseAmount: entry.subtotal,
              taxRate: 0,
              taxAmount: entry.taxTotal,
              grandTotal: entry.grandTotal,
            ),
          ],
        ),
      );
      continue;
    }
    final sortedRates = grouped.keys.toList()..sort();
    rows.add(
      InvoicePdfAnalysisListRow(
        customerName: entry.customerName,
        invoiceNumber: entry.invoiceNumber,
        invoiceDate: entry.invoiceDate,
        currency: entry.currency,
        invoiceTotal: entry.grandTotal,
        vatBreakdowns: sortedRates
            .map(
              (rate) => InvoicePdfAnalysisVatBreakdown(
                baseAmount: baseByRate[rate] ?? 0,
                taxRate: rate,
                taxAmount: grouped[rate] ?? 0,
                grandTotal: grandByRate[rate] ?? 0,
              ),
            )
            .toList(growable: false),
      ),
    );
  }
  rows.sort((a, b) {
    final dateA = a.invoiceDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateB = b.invoiceDate ?? DateTime.fromMillisecondsSinceEpoch(0);
    final dateCompare = dateB.compareTo(dateA);
    if (dateCompare != 0) return dateCompare;
    return a.invoiceNumber.compareTo(b.invoiceNumber);
  });
  return rows;
}

List<InvoicePdfCurrencySummary> _buildSummariesForRows(
  List<InvoicePdfAnalysisListRow> rows,
  List<InvoicePdfFxRateRule> fxRules,
) {
  final buckets = <String, _TempCurrencySummary>{};
  final invoiceCounts = <String, Set<String>>{};
  for (final row in rows) {
    final key = row.currency;
    final summary = buckets.putIfAbsent(key, _TempCurrencySummary.new);
    final invoiceKey = '${row.invoiceNumber}|${_formatDate(row.invoiceDate)}';
    final countBucket = invoiceCounts.putIfAbsent(key, () => <String>{});
    countBucket.add(invoiceKey);
    for (final item in row.vatBreakdowns) {
      summary.taxTotal += item.taxAmount;
      summary.subtotal += item.baseAmount;
      summary.grandTotal += item.grandTotal;
      summary.tlEquivalent += _computeTlEquivalentForBreakdown(
        row,
        item,
        fxRules,
      );
      final vat = summary.vatGroups.putIfAbsent(
        item.taxRate,
        _TempVatSummary.new,
      );
      vat.baseAmount += item.baseAmount;
      vat.taxAmount += item.taxAmount;
      vat.grandTotal += item.grandTotal;
      vat.tlEquivalent += _computeTlEquivalentForBreakdown(
        row,
        item,
        fxRules,
      );
    }
  }

  final result = buckets.entries.map((entry) {
    final vatGroups = entry.value.vatGroups.entries
        .map(
          (vatEntry) => InvoicePdfVatGroup(
            taxRate: vatEntry.key,
            baseAmount: vatEntry.value.baseAmount,
            taxAmount: vatEntry.value.taxAmount,
            grandTotal: vatEntry.value.grandTotal,
            tlEquivalent: vatEntry.value.tlEquivalent,
          ),
        )
        .toList()
      ..sort((a, b) => a.taxRate.compareTo(b.taxRate));

    return InvoicePdfCurrencySummary(
      currency: entry.key,
      invoiceCount: invoiceCounts[entry.key]?.length ?? 0,
      subtotal: entry.value.subtotal,
      taxTotal: entry.value.taxTotal,
      grandTotal: entry.value.grandTotal,
      tlEquivalent: entry.value.tlEquivalent,
      vatGroups: vatGroups,
    );
  }).toList()
    ..sort((a, b) => a.currency.compareTo(b.currency));

  return result;
}

InvoicePdfCurrencySummary? _findCurrency(
  List<InvoicePdfCurrencySummary> summaries,
  String currency,
) {
  for (final summary in summaries) {
    if (summary.currency == currency) return summary;
  }
  return null;
}

String _formatAmount(double value, String currency) {
  final symbol = switch (currency) {
    'USD' => '\$',
    'EUR' => '€',
    'GBP' => '£',
    _ => '₺',
  };
  final text = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: symbol,
    decimalDigits: 2,
  ).format(value);
  if (currency == 'TRY') return text;
  return '$text $currency';
}

String _formatDate(DateTime? value) {
  if (value == null) return '-';
  return DateFormat('dd.MM.yyyy', 'tr_TR').format(value);
}

String _formatPercent(double value) {
  final normalized =
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  return normalized.replaceAll('.', ',');
}

String _taxRateKey(double value) => value.toStringAsFixed(4);

String _periodKey(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}';

String _periodLabel(String key) {
  final parts = key.split('-');
  if (parts.length != 2) return key;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  if (year == null || month == null) return key;
  return DateFormat('MMMM yyyy', 'tr_TR').format(DateTime(year, month));
}

DateTime _normalizeDate(DateTime value) => DateTime(value.year, value.month, value.day);

double _computeTlEquivalentForBreakdown(
  InvoicePdfAnalysisListRow row,
  InvoicePdfAnalysisVatBreakdown breakdown,
  List<InvoicePdfFxRateRule> fxRules,
) {
  if (row.currency == 'TRY') return breakdown.grandTotal;
  if (row.invoiceDate == null) return 0;
  for (final rule in fxRules) {
    final sameCurrency = rule.currency.toUpperCase() == row.currency.toUpperCase();
    final startsOk = !_normalizeDate(row.invoiceDate!).isBefore(
      _normalizeDate(rule.startDate),
    );
    final endsOk = !_normalizeDate(row.invoiceDate!).isAfter(
      _normalizeDate(rule.endDate),
    );
    if (sameCurrency && startsOk && endsOk) {
      return breakdown.grandTotal * rule.rateToTry;
    }
  }
  return 0;
}

class _TempCurrencySummary {
  int invoiceCount = 0;
  double subtotal = 0;
  double taxTotal = 0;
  double grandTotal = 0;
  double tlEquivalent = 0;
  final Map<double, _TempVatSummary> vatGroups = <double, _TempVatSummary>{};
}

class _TempVatSummary {
  double baseAmount = 0;
  double taxAmount = 0;
  double grandTotal = 0;
  double tlEquivalent = 0;
}

class _VatRateOverviewItem {
  const _VatRateOverviewItem({
    required this.currency,
    required this.taxRate,
    required this.baseAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.tlEquivalent,
  });

  final String currency;
  final double taxRate;
  final double baseAmount;
  final double taxAmount;
  final double grandTotal;
  final double tlEquivalent;
}

InvoicePdfAnalysisEntry? _sanitizeEntryForDisplay(InvoicePdfAnalysisEntry entry) {
  final marker = InvoicePdfAnalysisParser.detectDocumentMarker(
    entry.rawText,
    fileName: entry.fileName,
  );
  if (marker == 'ALACAK') return null;
  if (marker != 'IPTAL') return entry;

  return InvoicePdfAnalysisEntry(
    fileName: entry.fileName,
    customerName: entry.customerName,
    invoiceNumber: entry.invoiceNumber,
    invoiceDate: entry.invoiceDate,
    currency: entry.currency,
    subtotal: 0,
    taxTotal: 0,
    grandTotal: 0,
    items: entry.items
        .map(
          (item) => InvoicePdfLineItem(
            rowNo: item.rowNo,
            description: item.description,
            quantity: item.quantity,
            unit: item.unit,
            unitPrice: 0,
            currency: item.currency,
            discountRate: item.discountRate,
            discountAmount: 0,
            taxRate: item.taxRate,
            taxAmount: 0,
            lineBaseAmount: 0,
          ),
        )
        .toList(growable: false),
    rawText: entry.rawText,
  );
}
