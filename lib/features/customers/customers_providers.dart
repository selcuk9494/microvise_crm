import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'customer_model.dart';

const customerPageSize = 50;

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
final customerShowPassiveProvider = NotifierProvider<CustomerShowPassiveNotifier, bool>(
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
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    return const CustomerPageData(
      items: [],
      page: 1,
      hasNextPage: false,
      totalCount: 0,
    );
  }

  final filters = ref.watch(customerFiltersProvider);
  final page = ref.watch(customerPageProvider);
  final sort = ref.watch(customerSortProvider);
  final showPassive = ref.watch(customerShowPassiveProvider);
  final search = filters.search.trim();
  final city = filters.city;
  final start = (page - 1) * customerPageSize;

  var sortQuery = client.from('customers').select('id,name,created_at');

  if (city != null && city.isNotEmpty) {
    sortQuery = sortQuery.eq('city', city);
  }
  if (!showPassive) {
    sortQuery = sortQuery.eq('is_active', true);
  }
  if (search.isNotEmpty) {
    sortQuery = sortQuery.ilike('name', '%$search%');
  }

  final sortRows = await sortQuery;
  final sortedRows = (sortRows as List)
      .map((e) => e as Map<String, dynamic>)
      .toList(growable: true);

  sortedRows.sort((a, b) {
    return switch (sort) {
      CustomerSortOption.id => _compareCreatedAt(
        a['created_at']?.toString(),
        b['created_at']?.toString(),
      ),
      CustomerSortOption.nameAsc => _normalizeSortText(
        a['name']?.toString() ?? '',
      ).compareTo(_normalizeSortText(b['name']?.toString() ?? '')),
      CustomerSortOption.nameDesc => _normalizeSortText(
        b['name']?.toString() ?? '',
      ).compareTo(_normalizeSortText(a['name']?.toString() ?? '')),
    };
  });

  final totalCount = sortedRows.length;
  final currentPageIds = sortedRows
      .skip(start)
      .take(customerPageSize)
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

  final rows = await client
      .from('customers')
      .select(
        'id,name,city,address,director_name,email,vkn,tckn_ms,phone_1,phone_1_title,phone_2,phone_2_title,phone_3,phone_3_title,notes,is_active,created_at',
      )
      .inFilter('id', currentPageIds);
  final rowById = {
    for (final row in (rows as List).cast<Map<String, dynamic>>())
      row['id']?.toString() ?? '': row,
  };
  final currentPageRows = [
    for (final id in currentPageIds)
      if (rowById.containsKey(id)) rowById[id]!,
  ];

  if (currentPageRows.isEmpty) {
    return CustomerPageData(
      items: const [],
      page: page,
      hasNextPage: false,
      totalCount: totalCount,
    );
  }

  final ids = currentPageRows
      .map((e) => e['id'].toString())
      .toList(growable: false);

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
    items: currentPageRows
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

int _compareCreatedAt(String? left, String? right) {
  final leftDate = DateTime.tryParse(left ?? '');
  final rightDate = DateTime.tryParse(right ?? '');
  if (leftDate == null && rightDate == null) return 0;
  if (leftDate == null) return 1;
  if (rightDate == null) return -1;
  return leftDate.compareTo(rightDate);
}

String _normalizeSortText(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u');
}

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
