import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/features/shell/nav_favorites.dart';

void main() {
  test('favoriye ekler ve cikarir', () {
    const path = '/tsm-log';
    final added = toggleNavFavoritePath(kDefaultNavFavoritePaths, path);
    expect(added, contains(path));
    expect(added.length, kDefaultNavFavoritePaths.length + 1);

    final removed = toggleNavFavoritePath(added, path);
    expect(removed, isNot(contains(path)));
    expect(removed, kDefaultNavFavoritePaths);
  });

  test('surukle birak sirayi korur', () {
    const current = ['/panel', '/musteriler', '/tsm-log'];
    expect(reorderNavFavoritePaths(current, 2, 0), [
      '/tsm-log',
      '/panel',
      '/musteriler',
    ]);
    expect(reorderNavFavoritePaths(current, 0, 3), [
      '/musteriler',
      '/tsm-log',
      '/panel',
    ]);
  });

  test('yetkisiz favorileri katalogdan eler', () {
    const catalog = [
      NavFavoriteTarget(
        path: '/panel',
        label: 'Panel',
        icon: Icons.dashboard,
        pageKey: 'panel',
      ),
      NavFavoriteTarget(
        path: '/tsm-log',
        label: 'TSM Log',
        icon: Icons.search,
        pageKey: 'tsm_log',
      ),
    ];
    final resolved = resolveNavFavorites(
      paths: const ['/panel', '/gizli', '/tsm-log'],
      catalog: catalog,
    );
    expect(resolved.map((item) => item.path), ['/panel', '/tsm-log']);
  });
}
