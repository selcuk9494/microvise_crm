import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';

class BkmAcquirerDefinition {
  const BkmAcquirerDefinition({
    required this.id,
    required this.bkmId,
    required this.name,
    required this.isActive,
  });

  final String id;
  final int bkmId;
  final String name;
  final bool isActive;

  String get bkmIdKey => '$bkmId';

  factory BkmAcquirerDefinition.fromJson(Map<String, dynamic> json) {
    return BkmAcquirerDefinition(
      id: json['id'].toString(),
      bkmId: (json['bkm_id'] as num?)?.toInt() ??
          int.tryParse((json['bkm_id'] ?? '').toString()) ??
          0,
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

final bkmAcquirersProvider = FutureProvider<List<BkmAcquirerDefinition>>((
  ref,
) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_bkm_acquirers'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(BkmAcquirerDefinition.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('bkm_acquirers')
      .select('id,bkm_id,name,is_active,created_at')
      .order('bkm_id');
  return (rows as List)
      .map((e) => BkmAcquirerDefinition.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

Map<String, String> bkmAcquirerNameMap(List<BkmAcquirerDefinition> items) {
  return {
    for (final item in items)
      if (item.isActive && item.bkmId > 0) item.bkmIdKey: item.name,
  };
}
