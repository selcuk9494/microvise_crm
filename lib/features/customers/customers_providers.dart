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
  final search = filters.search.trim();
  final city = filters.city;
  final start = (page - 1) * customerPageSize;
  final end = start + customerPageSize;

  var q = client
      .from('customers')
      .select(
        'id,name,city,email,vkn,phone_1,phone_1_title,phone_2,phone_2_title,phone_3,phone_3_title,notes,is_active',
      );
  var totalQuery = client.from('customers').select('id');

  if (city != null && city.isNotEmpty) {
    q = q.eq('city', city);
    totalQuery = totalQuery.eq('city', city);
  }
  if (search.isNotEmpty) {
    q = q.ilike('name', '%$search%');
    totalQuery = totalQuery.ilike('name', '%$search%');
  }

  final totalRows = await totalQuery;
  final totalCount = (totalRows as List).length;
  final rows = await q.order('name').range(start, end);
  final customerRows = (rows as List)
      .map((e) => e as Map<String, dynamic>)
      .toList(growable: false);

  final hasNextPage = customerRows.length > customerPageSize;
  final currentPageRows = hasNextPage
      ? customerRows.take(customerPageSize).toList(growable: false)
      : customerRows;

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
