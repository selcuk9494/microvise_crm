import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';

class LineStockItem {
  const LineStockItem({
    required this.id,
    required this.operatorName,
    required this.lineNumber,
    required this.simNumber,
    required this.isActive,
    required this.consumedAt,
    required this.createdAt,
  });

  final String id;
  final String operatorName;
  final String lineNumber;
  final String? simNumber;
  final bool isActive;
  final DateTime? consumedAt;
  final DateTime? createdAt;

  bool get isConsumed => consumedAt != null;

  factory LineStockItem.fromJson(Map<String, dynamic> json) {
    return LineStockItem(
      id: json['id']?.toString() ?? '',
      operatorName: (json['operator'] ?? '').toString(),
      lineNumber: (json['line_number'] ?? '').toString(),
      simNumber: json['sim_number']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      consumedAt: DateTime.tryParse(json['consumed_at']?.toString() ?? ''),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
    );
  }
}

String normalizeOperator(String? value) {
  final v = (value ?? '').trim().toLowerCase();
  if (v == 'turkcell') return 'turkcell';
  if (v == 'telsim' || v == 'vodafone') return 'telsim';
  return v;
}

final lineStockSearchProvider =
    NotifierProvider<LineStockSearchNotifier, String>(LineStockSearchNotifier.new);

class LineStockSearchNotifier extends Notifier<String> {
  @override
  String build() => '';

  void set(String value) => state = value;
}

final lineStockStatusProvider =
    NotifierProvider<LineStockStatusNotifier, String>(LineStockStatusNotifier.new);

class LineStockStatusNotifier extends Notifier<String> {
  @override
  String build() => 'available';

  void set(String value) => state = value;
}

final lineStockOperatorProvider =
    NotifierProvider<LineStockOperatorNotifier, String>(LineStockOperatorNotifier.new);

class LineStockOperatorNotifier extends Notifier<String> {
  @override
  String build() => 'all';

  void set(String value) => state = value.trim().isEmpty ? 'all' : value.trim();
}

final lineStockProvider = FutureProvider.autoDispose<List<LineStockItem>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final search = ref.watch(lineStockSearchProvider).trim();
  final status = ref.watch(lineStockStatusProvider).trim();
  final operatorName = ref.watch(lineStockOperatorProvider).trim();

  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'line_stock',
        if (search.isNotEmpty) 'search': search,
        if (status.isNotEmpty) 'status': status,
        if (operatorName != 'all') 'operator': operatorName,
        'limit': '5000',
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(LineStockItem.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('line_stock')
      .select('id,operator,line_number,sim_number,is_active,consumed_at,created_at')
      .order('created_at', ascending: false)
      .limit(5000);

  final raw = (rows as List)
      .cast<Map<String, dynamic>>()
      .map(LineStockItem.fromJson)
      .toList(growable: false);

  final q = search.toLowerCase();
  final opNorm = operatorName == 'all' ? null : normalizeOperator(operatorName);

  bool matches(LineStockItem item) {
    if (status == 'available') {
      if (!(item.isActive && !item.isConsumed)) return false;
    } else if (status == 'consumed') {
      if (!item.isConsumed) return false;
    } else if (status == 'passive') {
      if (item.isActive) return false;
    }
    if (opNorm != null && normalizeOperator(item.operatorName) != opNorm) {
      return false;
    }
    if (q.isNotEmpty) {
      final hay = [
        item.operatorName,
        item.lineNumber,
        item.simNumber ?? '',
      ].join(' ').toLowerCase();
      if (!hay.contains(q)) return false;
    }
    return true;
  }

  return raw.where(matches).toList(growable: false);
});

final lineStockAvailableProvider =
    FutureProvider.autoDispose<List<LineStockItem>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {
        'resource': 'line_stock',
        'status': 'available',
        'limit': '2000',
      },
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .map(LineStockItem.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('line_stock')
      .select('id,operator,line_number,sim_number,is_active,consumed_at,created_at')
      .eq('is_active', true)
      .isFilter('consumed_at', null)
      .order('created_at', ascending: false)
      .limit(2000);
  return (rows as List)
      .cast<Map<String, dynamic>>()
      .map(LineStockItem.fromJson)
      .toList(growable: false);
});

bool get isExcelSupported => kIsWeb;
