import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';
import 'customer_model.dart';

final customerFiltersProvider =
    NotifierProvider<CustomerFiltersNotifier, CustomerFilters>(
      CustomerFiltersNotifier.new,
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

class CustomerFilters {
  const CustomerFilters({required this.search, required this.city});

  final String search;
  final String? city;

  CustomerFilters copyWith({String? search, String? city}) {
    return CustomerFilters(search: search ?? this.search, city: city);
  }
}

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final filters = ref.watch(customerFiltersProvider);
  final search = filters.search.trim();
  final city = filters.city;

  var q = client
      .from('customers')
      .select(
        'id,name,city,email,vkn,phone_1,phone_1_title,phone_2,phone_2_title,phone_3,phone_3_title,notes,is_active',
      );

  if (city != null && city.isNotEmpty) {
    q = q.eq('city', city);
  }
  if (search.isNotEmpty) {
    q = q.ilike('name', '%$search%');
  }

  final rows = await q.order('name');
  final customerRows = (rows as List)
      .map((e) => e as Map<String, dynamic>)
      .toList(growable: false);

  if (customerRows.isEmpty) return const [];

  final ids = customerRows
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

  return customerRows
      .map(
        (e) => Customer.fromJson({
          ...e,
          'active_line_count': lineCounts[e['id']?.toString()] ?? 0,
          'active_gmp3_count': gmp3Counts[e['id']?.toString()] ?? 0,
        }),
      )
      .toList(growable: false);
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
