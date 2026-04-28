import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_cache.dart';
import 'invoice_pdf_analysis_model.dart';
import 'invoice_pdf_analysis_parser.dart';
import 'invoice_pdf_analysis_pick_files.dart';

final invoicePdfAnalysisProvider =
    NotifierProvider<InvoicePdfAnalysisNotifier, InvoicePdfAnalysisState>(
      InvoicePdfAnalysisNotifier.new,
    );

class InvoicePdfAnalysisNotifier extends Notifier<InvoicePdfAnalysisState> {
  static const _cacheKey = 'invoice_pdf_analysis_saved_entries_v1';
  static const _fxCacheKey = 'invoice_pdf_analysis_fx_rules_v1';

  @override
  InvoicePdfAnalysisState build() {
    final fxRules = _readSavedFxRules();
    return InvoicePdfAnalysisState(fxRules: fxRules);
  }

  Future<void> pickAndImportPdfs() async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final files = await pickInvoicePdfFiles();
      if (files.isEmpty) {
        state = state.copyWith(isLoading: false);
        return;
      }
      await importPickedFiles(files);
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'PDF secilemedi: $e',
      );
    }
  }

  Future<void> importPickedFiles(List<PickedPdfFile> files) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final parsed = <InvoicePdfAnalysisEntry>[];
      final seenKeys = {
        for (final entry in state.entries) _invoiceIdentityKey(entry),
      };
      for (final file in files) {
        final entry = await InvoicePdfAnalysisParser.parse(
          bytes: Uint8List.fromList(file.bytes),
          fileName: file.name,
        );
        if (entry != null) {
          final key = _invoiceIdentityKey(entry);
          if (seenKeys.contains(key)) continue;
          seenKeys.add(key);
          parsed.add(entry);
        }
      }
      final combined = [...state.entries, ...parsed]
        ..sort((a, b) {
          final customerCompare = a.customerName.toLowerCase().compareTo(
            b.customerName.toLowerCase(),
          );
          if (customerCompare != 0) return customerCompare;
          return a.invoiceNumber.compareTo(b.invoiceNumber);
        });
      state = state.copyWith(
        entries: combined,
        isLoading: false,
        lastSavedAtMs: state.lastSavedAtMs,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'PDF analiz edilemedi: $e',
      );
    }
  }

  void removeEntry(InvoicePdfAnalysisEntry entry) {
    state = state.copyWith(
      entries: state.entries.where((item) => item != entry).toList(),
    );
  }

  void clear() {
    state = state.copyWith(entries: const [], clearError: true);
  }

  Future<int> saveCurrentEntries() async {
    final sanitized = state.entries
        .map(_sanitizeEntryFromRawText)
        .whereType<InvoicePdfAnalysisEntry>()
        .toList(growable: false);
    final payload = sanitized.map((entry) => entry.toJson()).toList();
    final savedAtMs = DateTime.now().millisecondsSinceEpoch;
    await AppCache.writeJson(_cacheKey, payload, savedAtMs: savedAtMs);
    state = state.copyWith(lastSavedAtMs: savedAtMs);
    return sanitized.length;
  }

  Future<int> loadSavedEntries() async {
    final cached = AppCache.readJson<List<InvoicePdfAnalysisEntry>>(
      _cacheKey,
      decode: (json) {
        final list = (json as List?) ?? const [];
        return list
            .whereType<Map>()
            .map(
              (item) => InvoicePdfAnalysisEntry.fromJson(
                item.map((key, value) => MapEntry('$key', value)),
              ),
            )
            .toList(growable: false);
      },
    );
    if (cached == null) return 0;
    final merged = <InvoicePdfAnalysisEntry>[];
    final seenKeys = <String>{};
    final sanitized = [
      ...cached.value.map(_sanitizeEntryFromRawText).whereType<InvoicePdfAnalysisEntry>(),
      ...state.entries.map(_sanitizeEntryFromRawText).whereType<InvoicePdfAnalysisEntry>(),
    ];
    for (final entry in sanitized) {
      final key = _invoiceIdentityKey(entry);
      if (seenKeys.add(key)) {
        merged.add(entry);
      }
    }
    merged.sort((a, b) {
      final customerCompare = a.customerName.toLowerCase().compareTo(
        b.customerName.toLowerCase(),
      );
      if (customerCompare != 0) return customerCompare;
      return a.invoiceNumber.compareTo(b.invoiceNumber);
    });
    state = state.copyWith(
      entries: merged,
      lastSavedAtMs: cached.savedAtMs,
      clearError: true,
    );
    return merged.length;
  }

  Future<void> clearSavedEntries() async {
    await AppCache.remove(_cacheKey);
    state = state.copyWith(clearLastSavedAtMs: true);
  }

  Future<void> addFxRule(InvoicePdfFxRateRule rule) async {
    final next = [...state.fxRules.where((item) => item.id != rule.id), rule]
      ..sort((a, b) {
        final currencyCompare = a.currency.compareTo(b.currency);
        if (currencyCompare != 0) return currencyCompare;
        return a.startDate.compareTo(b.startDate);
      });
    await AppCache.writeJson(
      _fxCacheKey,
      next.map((item) => item.toJson()).toList(growable: false),
    );
    state = state.copyWith(fxRules: next);
  }

  Future<void> removeFxRule(String id) async {
    final next = state.fxRules.where((item) => item.id != id).toList(growable: false);
    await AppCache.writeJson(
      _fxCacheKey,
      next.map((item) => item.toJson()).toList(growable: false),
    );
    state = state.copyWith(fxRules: next);
  }
}

class InvoicePdfAnalysisState {
  const InvoicePdfAnalysisState({
    this.entries = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastSavedAtMs,
    this.fxRules = const [],
  });

  final List<InvoicePdfAnalysisEntry> entries;
  final bool isLoading;
  final String? errorMessage;
  final int? lastSavedAtMs;
  final List<InvoicePdfFxRateRule> fxRules;

  List<InvoicePdfCurrencySummary> get currencySummaries {
    final buckets = <String, _CurrencyAccumulator>{};
    for (final entry in entries) {
      final currency = entry.currency.trim().isEmpty ? 'TRY' : entry.currency;
      final bucket = buckets.putIfAbsent(currency, _CurrencyAccumulator.new);
      bucket.invoiceCount += 1;
      bucket.subtotal += entry.subtotal;
      bucket.taxTotal += entry.taxTotal;
      bucket.grandTotal += entry.grandTotal;

      for (final item in entry.items) {
        final taxBucket = bucket.taxGroups.putIfAbsent(
          item.taxRate,
          _VatAccumulator.new,
        );
        taxBucket.baseAmount += item.lineBaseAmount;
        taxBucket.taxAmount += item.taxAmount;
        taxBucket.grandTotal += item.lineGrandTotal;
      }
    }

    final result = buckets.entries.map((entry) {
      final vatGroups = entry.value.taxGroups.entries
          .map(
            (taxEntry) => InvoicePdfVatGroup(
              taxRate: taxEntry.key,
              baseAmount: taxEntry.value.baseAmount,
              taxAmount: taxEntry.value.taxAmount,
              grandTotal: taxEntry.value.grandTotal,
              tlEquivalent: 0,
            ),
          )
          .toList()
        ..sort((a, b) => a.taxRate.compareTo(b.taxRate));
      return InvoicePdfCurrencySummary(
        currency: entry.key,
        invoiceCount: entry.value.invoiceCount,
        subtotal: entry.value.subtotal,
        taxTotal: entry.value.taxTotal,
        grandTotal: entry.value.grandTotal,
        tlEquivalent: 0,
        vatGroups: vatGroups,
      );
    }).toList()
      ..sort((a, b) => _currencySortValue(a.currency).compareTo(_currencySortValue(b.currency)));

    return result;
  }

  InvoicePdfAnalysisState copyWith({
    List<InvoicePdfAnalysisEntry>? entries,
    bool? isLoading,
    String? errorMessage,
    int? lastSavedAtMs,
    List<InvoicePdfFxRateRule>? fxRules,
    bool clearError = false,
    bool clearLastSavedAtMs = false,
  }) {
    return InvoicePdfAnalysisState(
      entries: entries ?? this.entries,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastSavedAtMs:
          clearLastSavedAtMs ? null : (lastSavedAtMs ?? this.lastSavedAtMs),
      fxRules: fxRules ?? this.fxRules,
    );
  }
}

String _invoiceIdentityKey(InvoicePdfAnalysisEntry entry) {
  final date = entry.invoiceDate?.toIso8601String() ?? '';
  return '${entry.invoiceNumber.trim().toUpperCase()}|${entry.customerName.trim().toUpperCase()}|$date';
}

InvoicePdfAnalysisEntry? _sanitizeEntryFromRawText(InvoicePdfAnalysisEntry entry) {
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

List<InvoicePdfFxRateRule> _readSavedFxRules() {
  final cached = AppCache.readJson<List<InvoicePdfFxRateRule>>(
    InvoicePdfAnalysisNotifier._fxCacheKey,
    decode: (json) {
      final list = (json as List?) ?? const [];
      return list
          .whereType<Map>()
          .map(
            (item) => InvoicePdfFxRateRule.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false);
    },
  );
  return cached?.value ?? const <InvoicePdfFxRateRule>[];
}

int _currencySortValue(String currency) {
  switch (currency.toUpperCase()) {
    case 'TRY':
      return 0;
    case 'USD':
      return 1;
    case 'EUR':
      return 2;
    default:
      return 99;
  }
}

class _CurrencyAccumulator {
  int invoiceCount = 0;
  double subtotal = 0;
  double taxTotal = 0;
  double grandTotal = 0;
  final Map<double, _VatAccumulator> taxGroups = <double, _VatAccumulator>{};
}

class _VatAccumulator {
  double baseAmount = 0;
  double taxAmount = 0;
  double grandTotal = 0;
}
