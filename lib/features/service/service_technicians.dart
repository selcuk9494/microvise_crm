import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

class ServiceTechnician {
  const ServiceTechnician({
    required this.id,
    required this.fullName,
    required this.canSeeService,
  });

  final String id;
  final String fullName;
  final bool canSeeService;

  factory ServiceTechnician.fromJson(Map<String, dynamic> json) {
    final pages = json['page_permissions'];
    final pageList = pages is List ? pages.map((e) => e.toString()).toList() : const <String>[];
    return ServiceTechnician(
      id: json['id']?.toString() ?? '',
      fullName: (json['full_name'] ?? '').toString(),
      canSeeService: pageList.contains('servis'),
    );
  }
}

final serviceTechniciansProvider = FutureProvider.autoDispose<List<ServiceTechnician>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'personnel_users'},
  );
  final users = ((response['items'] as List?) ?? const [])
      .whereType<Map<String, dynamic>>()
      .map(ServiceTechnician.fromJson)
      .where((u) => u.id.trim().isNotEmpty && u.canSeeService)
      .toList(growable: false);
  users.sort((a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
  return users;
});

