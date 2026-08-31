import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/format/search_normalize.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_dense_list.dart';
import '../../core/ui/app_phosphor_icons.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';
import 'quote_model.dart';
import 'quote_pdf.dart';
import 'quote_providers.dart';
import 'quote_settings_provider.dart';

/// E-Fatura > Teklif sekmesi — satış faturaları listesiyle aynı yoğun tablo düzeni.
class QuotesTab extends ConsumerStatefulWidget {
  const QuotesTab({super.key});

  @override
  ConsumerState<QuotesTab> createState() => QuotesTabState();
}

class QuotesTabState extends ConsumerState<QuotesTab> {
  static const _renderStep = 30;

  QuoteFilter _filter = const QuoteFilter(status: null);
  String _searchQuery = '';
  int _visibleLimit = _renderStep;
  List<Quote> _lastQuotes = const [];
  void startNewQuote() => _openEditor();

  QuoteFilter get filter => _filter;

  List<Quote> _filterQuotes(List<Quote> quotes) {
    final q = _searchQuery.trim();
    if (q.isEmpty) return quotes;
    return quotes
        .where(
          (quote) => matchesSearchQuery(
            [quote.quoteNumber, quote.customerName ?? ''].join(' '),
            q,
          ),
        )
        .toList(growable: false);
  }

  Future<void> _openEditor({Quote? quote}) async {
    final path = quote == null
        ? '/e-fatura/teklif/yeni'
        : '/e-fatura/teklif/duzenle/${quote.id}';
    context.go(path);
    if (mounted) ref.invalidate(quotesProvider(_filter));
  }

  @override
  Widget build(BuildContext context) {
    final quotesAsync = ref.watch(quotesProvider(_filter));

    if (quotesAsync.hasValue) {
      _lastQuotes = quotesAsync.value ?? const [];
    }

    if (quotesAsync.hasError && _lastQuotes.isEmpty) {
      return Center(
        child: AppCard(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Teklifler yüklenemedi.'),
              const Gap(12),
              OutlinedButton.icon(
                onPressed: () => ref.invalidate(quotesProvider(_filter)),
                icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise),
                label: const Text('Yeniden dene'),
              ),
            ],
          ),
        ),
      );
    }

    final rawQuotes = quotesAsync.hasValue
        ? (quotesAsync.value ?? const <Quote>[])
        : _lastQuotes;
    final loadingFresh = quotesAsync.isLoading && _lastQuotes.isNotEmpty;

    return _buildQuotesList(
      rawQuotes: rawQuotes,
      loadingFresh: loadingFresh,
      initialLoading: quotesAsync.isLoading && _lastQuotes.isEmpty,
    );
  }

  Widget _buildQuotesList({
    required List<Quote> rawQuotes,
    required bool loadingFresh,
    required bool initialLoading,
  }) {
    final items = _filterQuotes(rawQuotes);
    final draft = items.where((q) => q.status == 'draft').length;
    final sent = items.where((q) => q.status == 'sent').length;
    final accepted = items
        .where((q) => q.status == 'accepted' || q.status == 'converted')
        .length;
    final tryTotal = items
        .where((q) => q.currency.toUpperCase() == 'TRY')
        .fold<double>(0, (sum, q) => sum + q.grandTotal);
    final usdTotal = items
        .where((q) => q.currency.toUpperCase() == 'USD')
        .fold<double>(0, (sum, q) => sum + q.grandTotal);
    final visibleItems = items.take(_visibleLimit).toList();
    final hasHidden = visibleItems.length < items.length;

    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (loadingFresh || initialLoading)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          ),
        _QuoteMetricsRow(
          metrics: [
            _QuoteMetric(
              'Toplam',
              items.length.toString(),
              LucideIcons.fileText,
              AppTheme.metricBlue,
            ),
            _QuoteMetric(
              'Taslak',
              draft.toString(),
              LucideIcons.pencil,
              AppTheme.textMuted,
            ),
            _QuoteMetric(
              'Gönderildi',
              sent.toString(),
              LucideIcons.send,
              AppTheme.primary,
            ),
            _QuoteMetric(
              'Onaylı',
              accepted.toString(),
              LucideIcons.circleCheck,
              AppTheme.success,
            ),
            _QuoteMetric(
              'TL Toplam',
              QuoteMoney.formatAmount(tryTotal, 'TRY'),
              LucideIcons.banknote,
              AppTheme.primaryDark,
            ),
            if (usdTotal > 0)
              _QuoteMetric(
                'USD Toplam',
                QuoteMoney.formatAmount(usdTotal, 'USD'),
                LucideIcons.dollarSign,
                AppTheme.metricBlue,
              ),
          ],
        ),
        const Gap(8),
        _QuoteFiltersCard(
          filter: _filter,
          onSearchChanged: (value) => setState(() => _searchQuery = value),
          onChanged: (next) => setState(() {
            _filter = next;
            _visibleLimit = _renderStep;
          }),
          onRefresh: () => ref.invalidate(quotesProvider(_filter)),
          onNewQuote: startNewQuote,
        ),
        const Gap(8),
        if (items.isEmpty && !initialLoading)
          AppCard(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Henüz teklif yok. Yeni Teklif ile başlayın.'),
                  ),
                  FilledButton.icon(
                    onPressed: startNewQuote,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Yeni Teklif'),
                  ),
                ],
              ),
            ),
          )
        else
          AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          initialLoading
                              ? 'Teklifler yükleniyor…'
                              : hasHidden
                              ? '${visibleItems.length} / ${items.length} teklif gösteriliyor'
                              : '${items.length} teklif listeleniyor',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (initialLoading)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                    ],
                  ),
                ),
                if (MediaQuery.sizeOf(context).width >= 900)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppDenseList.rowH,
                      0,
                      AppDenseList.rowH,
                      4,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Cari / Teklif No',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(
                          width: _QuoteTableCols.date,
                          child: Text(
                            'Tarih',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(
                          width: _QuoteTableCols.validUntil,
                          child: Text(
                            'Geçerlilik',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(
                          width: _QuoteTableCols.status,
                          child: Text(
                            'Durum',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(
                          width: _QuoteTableCols.currency,
                          child: Text(
                            'Döviz',
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(
                          width: _QuoteTableCols.amount,
                          child: Text(
                            'Tutar',
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(color: AppTheme.textSoft),
                          ),
                        ),
                        SizedBox(width: _QuoteTableCols.actions),
                      ],
                    ),
                  ),
                for (var i = 0; i < visibleItems.length; i++)
                  _QuoteRow(
                    key: ValueKey(visibleItems[i].id),
                    quote: visibleItems[i],
                    index: i,
                    filter: _filter,
                    onEdit: () => _openEditor(quote: visibleItems[i]),
                    onChanged: () {
                      ref.invalidate(quotesProvider(_filter));
                    },
                  ),
                if (hasHidden)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 14, 12, 16),
                    child: Center(
                      child: OutlinedButton.icon(
                        onPressed: () =>
                            setState(() => _visibleLimit += _renderStep),
                        icon: const Icon(AppPhosphorIcons.caretDown),
                        label: Text(
                          'Daha fazla göster (${visibleItems.length} / ${items.length})',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _QuoteTableCols {
  static const double date = 82;
  static const double validUntil = 82;
  static const double status = 140;
  static const double currency = 52;
  static const double amount = 100;
  static const double actions = 168;
}

class _QuoteMetric {
  const _QuoteMetric(this.label, this.value, this.icon, this.accent);

  final String label;
  final String value;
  final IconData icon;
  final Color accent;
}

class _QuoteMetricsRow extends StatelessWidget {
  const _QuoteMetricsRow({required this.metrics});

  final List<_QuoteMetric> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 700;
        return GridView.count(
          crossAxisCount: wide ? 5 : 2,
          mainAxisExtent: 72,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            for (final metric in metrics)
              AppCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Row(
                  children: [
                    AppDenseLeadingIcon(
                      icon: metric.icon,
                      color: metric.accent,
                    ),
                    const Gap(10),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            metric.label,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: AppTheme.textMuted,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 11,
                                ),
                          ),
                          Text(
                            metric.value,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 14,
                                  height: 1.15,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _QuoteFiltersCard extends StatelessWidget {
  const _QuoteFiltersCard({
    required this.filter,
    required this.onSearchChanged,
    required this.onChanged,
    required this.onRefresh,
    required this.onNewQuote,
  });

  final QuoteFilter filter;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<QuoteFilter> onChanged;
  final VoidCallback onRefresh;
  final VoidCallback onNewQuote;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 700;

    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fields = <Widget>[
            SizedBox(
              width: compact ? 260 : 280,
              child: TextField(
                decoration: const InputDecoration(
                  prefixIcon: Icon(AppPhosphorIcons.magnifyingGlass),
                  labelText: 'Teklif no veya cari ara',
                ),
                onChanged: onSearchChanged,
              ),
            ),
            SizedBox(
              width: 160,
              child: DropdownButtonFormField<String>(
                key: ValueKey('active-${filter.activeFilter}'),
                initialValue: filter.activeFilter,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(AppPhosphorIcons.toggleRight),
                  labelText: 'Aktiflik',
                ),
                items: const [
                  DropdownMenuItem(value: 'active', child: Text('Aktif')),
                  DropdownMenuItem(value: 'passive', child: Text('Pasif')),
                  DropdownMenuItem(value: 'all', child: Text('Tümü')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  onChanged(
                    QuoteFilter(
                      status: filter.status,
                      activeFilter: value,
                      customerId: filter.customerId,
                    ),
                  );
                },
              ),
            ),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String?>(
                key: ValueKey('status-${filter.status ?? ''}'),
                initialValue: filter.status,
                isExpanded: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(AppPhosphorIcons.trafficSignal),
                  labelText: 'Durum',
                ),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Durum: Tümü')),
                  DropdownMenuItem(value: 'draft', child: Text('Taslak')),
                  DropdownMenuItem(value: 'sent', child: Text('Gönderildi')),
                  DropdownMenuItem(value: 'accepted', child: Text('Onaylandı')),
                  DropdownMenuItem(
                    value: 'converted',
                    child: Text('Faturaya dönüştü'),
                  ),
                  DropdownMenuItem(
                    value: 'rejected',
                    child: Text('Reddedildi'),
                  ),
                  DropdownMenuItem(
                    value: 'expired',
                    child: Text('Süresi doldu'),
                  ),
                ],
                onChanged: (value) => onChanged(
                  QuoteFilter(
                    status: value,
                    activeFilter: filter.activeFilter,
                    customerId: filter.customerId,
                  ),
                ),
              ),
            ),
            OutlinedButton.icon(
              onPressed: onRefresh,
              icon: const Icon(AppPhosphorIcons.arrowsCounterClockwise),
              label: const Text('Yenile'),
            ),
            TextButton.icon(
              onPressed: () {
                onSearchChanged('');
                onChanged(const QuoteFilter());
              },
              icon: const Icon(AppPhosphorIcons.broom),
              label: const Text('Temizle'),
            ),
          ];

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Teklif kayıtları satış faturaları ile aynı listede filtrelenir.',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: AppTheme.textSoft),
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: onNewQuote,
                    icon: const Icon(LucideIcons.plus, size: 18),
                    label: const Text('Yeni Teklif'),
                  ),
                ],
              ),
              const Gap(12),
              Wrap(spacing: 10, runSpacing: 10, children: fields),
            ],
          );
        },
      ),
    );
  }
}

class _QuoteRow extends ConsumerStatefulWidget {
  const _QuoteRow({
    super.key,
    required this.quote,
    required this.index,
    required this.filter,
    required this.onEdit,
    required this.onChanged,
  });

  final Quote quote;
  final int index;
  final QuoteFilter filter;
  final VoidCallback onEdit;
  final VoidCallback onChanged;

  @override
  ConsumerState<_QuoteRow> createState() => _QuoteRowState();
}

class _QuoteRowState extends ConsumerState<_QuoteRow> {
  bool _busy = false;

  AppBadgeTone _statusTone(String status) => switch (status) {
    'accepted' || 'converted' => AppBadgeTone.success,
    'sent' => AppBadgeTone.primary,
    'rejected' || 'expired' => AppBadgeTone.error,
    _ => AppBadgeTone.neutral,
  };

  Future<void> _exportPdf() async {
    setState(() => _busy = true);
    try {
      final detail = await ref.read(
        quoteDetailProvider(widget.quote.id).future,
      );
      if (detail == null) throw Exception('Teklif bulunamadı.');
      final settings = await ref.read(quoteDocumentSettingsProvider.future);
      final bytes = await buildQuotePdfBytes(quote: detail, settings: settings);
      await downloadBinaryFile(
        bytes,
        'teklif_${detail.quoteNumber.replaceAll('/', '-')}.pdf',
        mimeType: 'application/pdf',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Teklif PDF hazırlandı.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('PDF oluşturulamadı: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _approve() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Teklif onaylansın mı?'),
        content: const Text(
          'Teklif onaylanacak ve satış faturası oluşturulacak.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      final response = await apiClient.postJson(
        '/mutate',
        body: {'op': 'convertQuoteToInvoice', 'quoteId': widget.quote.id},
      );
      widget.onChanged();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Satış faturası oluşturuldu: ${response['invoiceNumber'] ?? ''}',
          ),
        ),
      );
      context.go('/e-fatura/satis');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Onay başarısız: $error')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggleActive(bool active) async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;
    setState(() => _busy = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'updateWhere',
          'table': 'quotes',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.quote.id},
          ],
          'values': {'is_active': active},
        },
      );
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Durum güncellenemedi.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Teklif silinsin mi?'),
        content: const Text('Bu işlem geri alınamaz.'),
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
    setState(() => _busy = true);
    try {
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'quote_items',
          'filters': [
            {'col': 'quote_id', 'op': 'eq', 'value': widget.quote.id},
          ],
        },
      );
      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'deleteWhere',
          'table': 'quotes',
          'filters': [
            {'col': 'id', 'op': 'eq', 'value': widget.quote.id},
          ],
        },
      );
      widget.onChanged();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Silme başarısız.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final quote = widget.quote;
    final amountText = QuoteMoney.formatAmount(
      quote.grandTotal,
      quote.currency,
    );
    final dateFmt = DateFormat('dd.MM.yyyy', 'tr_TR');
    final validLabel = quote.validUntil == null
        ? '—'
        : dateFmt.format(quote.validUntil!);

    if (MediaQuery.sizeOf(context).width < 900) {
      return AppDenseListCard(
        leading: AppDenseLeadingIcon(
          icon: LucideIcons.fileText,
          color: AppTheme.primary,
          active: quote.isActive,
        ),
        title: quote.customerName ?? 'Cari',
        subtitle: quote.quoteNumber,
        badge: AppBadge(
          dense: true,
          label: quote.isActive ? Quote.statusLabel(quote.status) : 'Pasif',
          tone: quote.isActive
              ? _statusTone(quote.status)
              : AppBadgeTone.neutral,
        ),
        meta: [
          AppDenseInfoChip(
            icon: LucideIcons.calendar,
            text: dateFmt.format(quote.quoteDate),
          ),
          AppDenseInfoChip(icon: LucideIcons.timer, text: validLabel),
          AppDenseInfoChip(
            icon: LucideIcons.banknote,
            text: amountText,
            color: AppTheme.primary,
          ),
          AppDenseInfoChip(
            icon: LucideIcons.coins,
            text: QuoteMoney.label(quote.currency),
          ),
        ],
        actions: _buildActions(mobile: true),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppDenseList.rowFill(widget.index),
        border: Border(bottom: AppDenseList.hairline),
      ),
      child: SizedBox(
        height: AppDenseList.rowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppDenseList.rowH),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    AppDenseLeadingIcon(
                      icon: LucideIcons.fileText,
                      color: AppTheme.primary,
                      active: quote.isActive,
                    ),
                    const Gap(6),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            quote.customerName ?? 'Cari',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(
                                  fontSize: 12.5,
                                  height: 1.1,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                          Text(
                            quote.quoteNumber,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  fontSize: 11.5,
                                  color: AppTheme.textSoft,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.date,
                child: Text(
                  dateFmt.format(quote.quoteDate),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.validUntil,
                child: Text(
                  validLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSoft,
                  ),
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.status,
                child: AppBadge(
                  dense: true,
                  label: quote.isActive
                      ? Quote.statusLabel(quote.status)
                      : 'Pasif',
                  tone: quote.isActive
                      ? _statusTone(quote.status)
                      : AppBadgeTone.neutral,
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.currency,
                child: Text(
                  QuoteMoney.label(quote.currency),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primary,
                  ),
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.amount,
                child: Text(
                  amountText,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              SizedBox(
                width: _QuoteTableCols.actions,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: _buildActions(mobile: false),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildActions({required bool mobile}) {
    final quote = widget.quote;
    final actions = <Widget>[
      _QuoteIconAction(
        tooltip: 'PDF indir',
        icon: Icons.picture_as_pdf_outlined,
        color: AppTheme.error,
        onPressed: _busy ? null : _exportPdf,
      ),
      if (quote.canEdit)
        _QuoteIconAction(
          tooltip: 'Düzenle',
          icon: Icons.edit_outlined,
          color: AppTheme.purple,
          onPressed: _busy ? null : widget.onEdit,
        ),
      if (quote.canApprove)
        _QuoteIconAction(
          tooltip: 'Onayla → Fatura',
          icon: Icons.check_circle_outline,
          color: AppTheme.success,
          onPressed: _busy ? null : _approve,
        ),
      PopupMenuButton<String>(
        tooltip: 'Diğer işlemler',
        enabled: !_busy,
        padding: EdgeInsets.zero,
        offset: const Offset(0, 36),
        onSelected: (value) {
          switch (value) {
            case 'active':
              _toggleActive(!quote.isActive);
            case 'delete':
              _delete();
            case 'sales':
              context.go('/e-fatura/satis');
          }
        },
        itemBuilder: (context) => [
          if (quote.convertedInvoiceId != null)
            const PopupMenuItem(
              value: 'sales',
              child: Text('Satış faturalarına git'),
            ),
          PopupMenuItem(
            value: 'active',
            child: Text(quote.isActive ? 'Pasife al' : 'Aktifleştir'),
          ),
          if (!quote.isActive)
            const PopupMenuItem(value: 'delete', child: Text('Kalıcı sil')),
        ],
        child: Container(
          width: AppDenseList.action,
          height: AppDenseList.action,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(AppPhosphorIcons.dotsThree, size: 20),
        ),
      ),
    ];

    if (!mobile) return actions;
    return [
      for (var i = 0; i < actions.length; i++) ...[
        if (i > 0) const Gap(4),
        actions[i],
      ],
    ];
  }
}

class _QuoteIconAction extends StatelessWidget {
  const _QuoteIconAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints.tightFor(
          width: AppDenseList.action,
          height: AppDenseList.action,
        ),
        style: IconButton.styleFrom(
          backgroundColor: enabled
              ? AppTheme.softTint(color, alpha: 0.12)
              : AppTheme.surfaceMuted,
          foregroundColor: enabled
              ? AppTheme.softFg(color)
              : AppTheme.textMuted,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: AppDenseList.actionIcon),
      ),
    );
  }
}
