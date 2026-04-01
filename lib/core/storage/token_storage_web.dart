import 'package:web/web.dart' as web;

class TokenStorage {
  static const _key = 'microvise_api_token';

  static String? read() {
    final value = web.window.localStorage.getItem(_key);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static void write(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      web.window.localStorage.removeItem(_key);
      return;
    }
    web.window.localStorage.setItem(_key, trimmed);
  }
}
