import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/storage/app_cache.dart';

/// SharedPreferences / AppCache key for the shell theme preference.
const String kThemeModeCacheKey = 'theme_mode';

ThemeMode themeModeFromStorage(String? raw) {
  switch ((raw ?? '').trim().toLowerCase()) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    case 'system':
    case 'oto':
    case 'auto':
      return ThemeMode.system;
    default:
      return ThemeMode.system;
  }
}

String themeModeToStorage(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'light',
    ThemeMode.dark => 'dark',
    ThemeMode.system => 'system',
  };
}

String themeModeLabelTr(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => 'Açık',
    ThemeMode.dark => 'Koyu',
    ThemeMode.system => 'Oto',
  };
}

IconData themeModeIcon(ThemeMode mode) {
  return switch (mode) {
    ThemeMode.light => Icons.light_mode_rounded,
    ThemeMode.dark => Icons.dark_mode_rounded,
    ThemeMode.system => Icons.brightness_auto_rounded,
  };
}

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => themeModeFromStorage(AppCache.readString(kThemeModeCacheKey));

  Future<void> setMode(ThemeMode mode) async {
    if (state == mode) return;
    state = mode;
    await AppCache.writeString(kThemeModeCacheKey, themeModeToStorage(mode));
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);
