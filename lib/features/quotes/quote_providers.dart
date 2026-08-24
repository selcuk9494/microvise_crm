import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/provider_cache.dart';
import 'quote_model.dart';

final quotesProvider = FutureProvider.family<List<Quote>, QuoteFilter>((
  ref,
  filter,
) async {
  keepProviderAliveFor(ref, const Duration(minutes: 10));
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return const [];

  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'quotes_list',
      'activeFilter': filter.activeFilter,
      if (filter.status != null) 'status': filter.status!,
      if (filter.customerId != null) 'customerId': filter.customerId!,
    },
  );

  return ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(Quote.fromJson)
      .toList(growable: false);
});

final quoteDetailProvider = FutureProvider.autoDispose.family<Quote?, String>((
  ref,
  quoteId,
) async {
  if (quoteId.trim().isEmpty) return null;
  final apiClient = ref.read(apiClientProvider);
  if (apiClient == null) return null;

  try {
    final row = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'quote_detail', 'quoteId': quoteId},
    );
    if (row.isEmpty || row['id'] == null) return null;
    return Quote.fromJson(row);
  } catch (_) {
    return null;
  }
});
