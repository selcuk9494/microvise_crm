import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/auth/user_profile_provider.dart';
import '../../core/storage/app_cache.dart';

const kNavFavoritesCacheKeyPrefix = 'nav_favorites';

const kDefaultNavFavoritePaths = <String>[
  '/panel',
  '/musteriler',
  '/formlar/basvuru',
  '/e-fatura/satis',
  '/e-fatura/teklif',
];

class NavFavoriteTarget {
  const NavFavoriteTarget({
    required this.path,
    required this.label,
    required this.icon,
    required this.pageKey,
  });

  final String path;
  final String label;
  final IconData icon;
  final String pageKey;
}

String navFavoritesCacheKey(String? userId) {
  final id = (userId ?? '').trim();
  return '$kNavFavoritesCacheKeyPrefix:${id.isEmpty ? 'anon' : id}';
}

List<String> decodeNavFavoritePaths(Object json) {
  if (json is! List) return const [];
  return json
      .map((item) => item.toString().trim())
      .where((item) => item.isNotEmpty)
      .toList();
}

List<String> toggleNavFavoritePath(List<String> current, String path) {
  final target = path.trim();
  if (target.isEmpty) return List<String>.of(current);
  final next = List<String>.of(current);
  final index = next.indexOf(target);
  if (index >= 0) {
    next.removeAt(index);
  } else {
    next.add(target);
  }
  return next;
}

List<String> reorderNavFavoritePaths(
  List<String> current,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= current.length) {
    return List<String>.of(current);
  }
  var target = newIndex;
  if (target > oldIndex) target -= 1;
  if (target < 0) target = 0;
  final next = List<String>.of(current);
  final item = next.removeAt(oldIndex);
  if (target > next.length) target = next.length;
  next.insert(target, item);
  return next;
}

List<NavFavoriteTarget> resolveNavFavorites({
  required List<String> paths,
  required List<NavFavoriteTarget> catalog,
}) {
  final byPath = {for (final item in catalog) item.path: item};
  return [
    for (final path in paths)
      if (byPath[path] != null) byPath[path]!,
  ];
}

class NavFavoritesNotifier extends Notifier<List<String>> {
  String _cacheKey() {
    final id = ref.read(currentUserProfileProvider).value?.id;
    return navFavoritesCacheKey(id);
  }

  @override
  List<String> build() {
    final profile = ref.watch(currentUserProfileProvider).value;
    final stored = AppCache.readJson<List<String>>(
      navFavoritesCacheKey(profile?.id),
      decode: decodeNavFavoritePaths,
    );
    if (stored == null) {
      return profile?.isBankLike == true
          ? const <String>[]
          : List<String>.of(kDefaultNavFavoritePaths);
    }
    return stored.value;
  }

  Future<void> toggle(String path) async {
    await _persist(toggleNavFavoritePath(state, path));
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    await _persist(reorderNavFavoritePaths(state, oldIndex, newIndex));
  }

  Future<void> _persist(List<String> next) async {
    state = next;
    await AppCache.writeJson(_cacheKey(), next);
  }
}

final navFavoritesProvider =
    NotifierProvider<NavFavoritesNotifier, List<String>>(
      NavFavoritesNotifier.new,
    );
