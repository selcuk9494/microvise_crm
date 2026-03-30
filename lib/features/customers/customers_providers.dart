import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';
import '../../core/supabase/supabase_providers.dart';
import 'customer_model.dart';

const customerPageSize = 50;
const _customerBaseSelect =
    'id,name,city,address,email,vkn,tckn_ms,phone_1,phone_1_title,phone_2,phone_2_title,phone_3,phone_3_title,notes,is_active,created_at';
const _customerDirectorSelect = '$_customerBaseSelect,director_name';

final customerFiltersProvider =
    NotifierProvider<CustomerFiltersNotifier, CustomerFilters>(
      CustomerFiltersNotifier.new,
    );
final customerPageProvider = NotifierProvider<CustomerPageNotifier, int>(
  CustomerPageNotifier.new,
);
final customerSortProvider =
    NotifierProvider<CustomerSortNotifier, CustomerSortOption>(
      CustomerSortNotifier.new,
    );
final customerShowPassiveProvider =
    NotifierProvider<CustomerShowPassiveNotifier, bool>(
      CustomerShowPassiveNotifier.new,
    );

class CustomerFiltersNotifier extends Notifier<CustomerFilters> {
  @override
  CustomerFilters build() => const CustomerFilters(search: '', city: null);

  void setSearch(String value) {
    state = state.copyWith(search: value);
  }

  void setCity(String? value) {
    state = state.copyWith(city: value?.trim().isEmpty ?? true ? null : value);
  }
}

class CustomerPageNotifier extends Notifier<int> {
  @override
  int build() => 1;

  void set(int page) => state = page < 1 ? 1 : page;

  void next() => state = state + 1;

  void previous() => state = state > 1 ? state - 1 : 1;

  void reset() => state = 1;
}

enum CustomerSortOption { id, nameAsc, nameDesc }

class CustomerSortNotifier extends Notifier<CustomerSortOption> {
  @override
  CustomerSortOption build() => CustomerSortOption.id;

  void set(CustomerSortOption value) => state = value;
}

class CustomerShowPassiveNotifier extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

class CustomerFilters {
  const CustomerFilters({required this.search, required this.city});

  final String search;
  final String? city;

  CustomerFilters copyWith({String? search, String? city}) {
    return CustomerFilters(search: search ?? this.search, city: city);
  }
}

class CustomerPageData {
  const CustomerPageData({
    required this.items,
    required this.page,
    required this.hasNextPage,
    required this.totalCount,
  });

  final List<Customer> items;
  final int page;
  final bool hasNextPage;
  final int totalCount;

  int get totalPages =>
      totalCount == 0 ? 1 : (totalCount / customerPageSize).ceil();
}

final customersProvider = FutureProvider<CustomerPageData>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  final client = ref.watch(supabaseClientProvider);
  final filters = ref.watch(customerFiltersProvider);
  final page = ref.watch(customerPageProvider);
  final sort = ref.watch(customerSortProvider);
  final showPassive = ref.watch(customerShowPassiveProvider);
  final search = filters.search.trim();
  final city = filters.city;

  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/customers',
      queryParameters: {
        'page': '$page',
        'pageSize': '$customerPageSize',
        'sort': sort.name,
        'showPassive': showPassive.toString(),
        if (search.isNotEmpty) 'search': search,
        if (city != null && city.isNotEmpty) 'city': city,
      },
    );

    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(Customer.fromJson)
        .toList(growable: false);

    return CustomerPageData(
      items: items,
      page: (response['page'] as num?)?.toInt() ?? page,
      hasNextPage: response['hasNextPage'] as bool? ?? false,
      totalCount: (response['totalCount'] as num?)?.toInt() ?? items.length,
    );
  }

  if (client == null) {
    return const CustomerPageData(
      items: [],
      page: 1,
      hasNextPage: false,
      totalCount: 0,
    );
  }

  final start = (page - 1) * customerPageSize;

  var totalCountQuery = client.from('customers').count();
  totalCountQuery = _applyCustomerFilters(
    totalCountQuery,
    search: search,
    city: city,
    showPassive: showPassive,
  );
  final totalCount = await totalCountQuery;
  final hasAnyRows = totalCount > 0 && start < totalCount;
  if (!hasAnyRows) {
    return CustomerPageData(
      items: const [],
      page: page,
      hasNextPage: false,
      totalCount: totalCount,
    );
  }

  final rows = await _selectCustomersWithFallback(
    client,
    search: search,
    city: city,
    showPassive: showPassive,
    sort: sort,
    from: start,
    to: start + customerPageSize - 1,
  );
  final currentPageIds = rows
      .map((row) => row['id']?.toString())
      .whereType<String>()
      .toList(growable: false);
  final hasNextPage = start + currentPageIds.length < totalCount;

  if (currentPageIds.isEmpty) {
    return CustomerPageData(
      items: const [],
      page: page,
      hasNextPage: false,
      totalCount: totalCount,
    );
  }
  final ids = currentPageIds;

  final lineRows = await client
      .from('lines')
      .select('customer_id')
      .eq('is_active', true)
      .inFilter('customer_id', ids);

  final gmp3Rows = await client
      .from('licenses')
      .select('customer_id')
      .eq('is_active', true)
      .eq('license_type', 'gmp3')
      .inFilter('customer_id', ids);

  final lineCounts = <String, int>{};
  for (final row in (lineRows as List)) {
    final id = row['customer_id']?.toString();
    if (id == null) continue;
    lineCounts.update(id, (v) => v + 1, ifAbsent: () => 1);
  }

  final gmp3Counts = <String, int>{};
  for (final row in (gmp3Rows as List)) {
    final id = row['customer_id']?.toString();
    if (id == null) continue;
    gmp3Counts.update(id, (v) => v + 1, ifAbsent: () => 1);
  }

  return CustomerPageData(
    page: page,
    hasNextPage: hasNextPage,
    totalCount: totalCount,
    items: rows
        .map(
          (e) => Customer.fromJson({
            ...e,
            'active_line_count': lineCounts[e['id']?.toString()] ?? 0,
            'active_gmp3_count': gmp3Counts[e['id']?.toString()] ?? 0,
          }),
        )
        .toList(growable: false),
  );
});

final customerCitiesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  try {
    final rows = await client
        .from('cities')
        .select('name,is_active')
        .eq('is_active', true)
        .order('name');

    return (rows as List)
        .map((row) => row['name']?.toString().trim())
        .whereType<String>()
        .where((name) => name.isNotEmpty)
        .toList(growable: false);
  } catch (_) {
    return const [];
  }
});

final customerLocationsProvider =
    FutureProvider.family<List<CustomerLocation>, String>((
      ref,
      customerId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];

      try {
        final rows = await client
            .from('customer_locations')
            .select(
              'id,customer_id,title,description,address,location_link,location_lat,location_lng,is_active,created_at',
            )
            .eq('customer_id', customerId)
            .eq('is_active', true)
            .order('created_at', ascending: false);

        return (rows as List)
            .map(
              (row) => CustomerLocation.fromJson(row as Map<String, dynamic>),
            )
            .toList(growable: false);
      } catch (_) {
        return const [];
      }
    });

dynamic _applyCustomerFilters(
  dynamic query, {
  required String search,
  required String? city,
  required bool showPassive,
}) {
  if (city != null && city.isNotEmpty) {
    query = query.eq('city', city);
  }
  if (!showPassive) {
    query = query.eq('is_active', true);
  }
  if (search.isNotEmpty) {
    query = query.ilike('name', '%$search%');
  }
  return query;
}

dynamic _applyCustomerSort(dynamic query, CustomerSortOption sort) {
  return switch (sort) {
    CustomerSortOption.id => query.order('created_at', ascending: true),
    CustomerSortOption.nameAsc => query.order('name', ascending: true),
    CustomerSortOption.nameDesc => query.order('name', ascending: false),
  };
}

Future<List<Map<String, dynamic>>> _selectCustomersWithFallback(
  dynamic client, {
  required String search,
  required String? city,
  required bool showPassive,
  required CustomerSortOption sort,
  required int from,
  required int to,
}) async {
  try {
    var query = client.from('customers').select(_customerDirectorSelect);
    query = _applyCustomerFilters(
      query,
      search: search,
      city: city,
      showPassive: showPassive,
    );
    query = _applyCustomerSort(query, sort);
    final rows = await query.range(from, to);
    return (rows as List).cast<Map<String, dynamic>>();
  } catch (_) {
    var query = client.from('customers').select(_customerBaseSelect);
    query = _applyCustomerFilters(
      query,
      search: search,
      city: city,
      showPassive: showPassive,
    );
    query = _applyCustomerSort(query, sort);
    final rows = await query.range(from, to);
    return (rows as List)
        .cast<Map<String, dynamic>>()
        .map((row) => {...row, 'director_name': null})
        .toList(growable: false);
  }
}
