import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/providers/provider_cache.dart';
import 'quote_settings_model.dart';

final quoteDocumentSettingsProvider =
    FutureProvider<QuoteDocumentSettings>((ref) async {
      keepProviderAliveFor(ref, const Duration(minutes: 15));
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null) return QuoteDocumentSettings.defaults();
      try {
        final response = await apiClient.getJson(
          '/data',
          queryParameters: {'resource': 'quote_document_settings'},
        );
        return QuoteDocumentSettings.fromJson(response);
      } catch (_) {
        return QuoteDocumentSettings.defaults();
      }
    });
