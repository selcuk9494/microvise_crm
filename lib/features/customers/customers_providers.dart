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
    return CustomerFilters(
      search: search ?? this.search,
      city: city,
    );
  }
}

final customersProvider = FutureProvider<List<Customer>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final filters = ref.watch(customerFiltersProvider);
  final search = filters.search.trim();
  final city = filters.city;

  var q = client.from('customers').select('id,name,city,is_active');

  if (city != null && city.isNotEmpty) {
    q = q.eq('city', city);
  }
  if (search.isNotEmpty) {
    q = q.ilike('name', '%$search%');
  }

  final rows = await q.order('name');
  return (rows as List)
      .map((e) => Customer.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final customerCitiesProvider = FutureProvider<List<String>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client.from('customers').select('city');

  final set = <String>{};
  for (final row in (rows as List)) {
    final city = row['city']?.toString();
    if (city == null || city.trim().isEmpty) continue;
    set.add(city);
  }

  final cities = set.toList()..sort();
  return cities;
});
