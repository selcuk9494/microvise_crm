import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/api_client.dart';
import 'reports_models.dart';

final reportsFiltersProvider =
    NotifierProvider<ReportsFiltersNotifier, ReportsFilters>(
      ReportsFiltersNotifier.new,
    );

class ReportsFiltersNotifier extends Notifier<ReportsFilters> {
  @override
  ReportsFilters build() => ReportsFilters.last30Days();

  void setPreset(ReportsPreset preset) {
    state = state.copyWith(preset: preset);
  }

  void setCustomRange(DateTime from, DateTime to) {
    state = state.copyWith(
      preset: ReportsPreset.custom,
      customFrom: DateTime(from.year, from.month, from.day),
      customTo: DateTime(to.year, to.month, to.day),
    );
  }

  void setUser(String? userId) {
    final empty = userId == null || userId.trim().isEmpty;
    state = state.copyWith(userId: empty ? null : userId, clearUser: empty);
  }
}

final reportsUsersProvider = FutureProvider<List<ReportUser>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return const [];
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {'resource': 'reports_users'},
  );
  return ((response['items'] as List?) ?? const [])
      .whereType<Map>()
      .map((e) => ReportUser.fromJson(Map<String, dynamic>.from(e)))
      .toList(growable: false);
});

final reportsDataProvider = FutureProvider<SystemReports>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient == null) return SystemReports.empty();

  final filters = ref.watch(reportsFiltersProvider);
  final fmt = DateFormat('yyyy-MM-dd');
  final response = await apiClient.getJson(
    '/data',
    queryParameters: {
      'resource': 'reports_system',
      'from': fmt.format(filters.from),
      'to': fmt.format(filters.to),
      if (filters.userId != null) 'userId': filters.userId!,
    },
  );
  return SystemReports.fromJson(response);
});
