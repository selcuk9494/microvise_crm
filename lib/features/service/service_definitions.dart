import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';

class ServiceFaultType {
  const ServiceFaultType({required this.id, required this.name, required this.isActive});

  final String id;
  final String name;
  final bool isActive;

  factory ServiceFaultType.fromJson(Map<String, dynamic> json) {
    return ServiceFaultType(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

class ServiceAccessoryType {
  const ServiceAccessoryType({required this.id, required this.name, required this.isActive});

  final String id;
  final String name;
  final bool isActive;

  factory ServiceAccessoryType.fromJson(Map<String, dynamic> json) {
    return ServiceAccessoryType(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

final serviceFaultTypesProvider = FutureProvider<List<ServiceFaultType>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_service_fault_types'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceFaultType.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('service_fault_types')
      .select('id,name,is_active,sort_order,created_at')
      .eq('is_active', true)
      .order('sort_order')
      .order('name');
  return (rows as List)
      .whereType<Map<String, dynamic>>()
      .map(ServiceFaultType.fromJson)
      .toList(growable: false);
});

final serviceAccessoryTypesProvider = FutureProvider<List<ServiceAccessoryType>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_service_accessory_types'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ServiceAccessoryType.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];
  final rows = await client
      .from('service_accessory_types')
      .select('id,name,is_active,sort_order,created_at')
      .eq('is_active', true)
      .order('sort_order')
      .order('name');
  return (rows as List)
      .whereType<Map<String, dynamic>>()
      .map(ServiceAccessoryType.fromJson)
      .toList(growable: false);
});

