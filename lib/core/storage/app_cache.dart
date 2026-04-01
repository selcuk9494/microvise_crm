import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class AppCacheEntry<T> {
  const AppCacheEntry({required this.savedAtMs, required this.value});

  final int savedAtMs;
  final T value;
}

class AppCache {
  static SharedPreferences? _prefs;

  static Future<void> init() async {
    _prefs ??= await SharedPreferences.getInstance();
  }

  static AppCacheEntry<T>? readJson<T>(
    String key, {
    required T Function(Object json) decode,
  }) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final raw = prefs.getString(key);
    if (raw == null || raw.trim().isEmpty) return null;

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return null;
      final savedAt = (decoded['t'] as num?)?.toInt();
      final valueJson = decoded['v'];
      if (savedAt == null || valueJson == null) return null;
      return AppCacheEntry<T>(savedAtMs: savedAt, value: decode(valueJson));
    } catch (_) {
      prefs.remove(key);
      return null;
    }
  }

  static Future<void> writeJson(
    String key,
    Object value, {
    int? savedAtMs,
  }) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final payload = {
      't': savedAtMs ?? DateTime.now().millisecondsSinceEpoch,
      'v': value,
    };
    await prefs.setString(key, jsonEncode(payload));
  }

  static Future<void> remove(String key) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.remove(key);
  }

  static String? readString(String key) {
    final prefs = _prefs;
    if (prefs == null) return null;
    final value = prefs.getString(key);
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static Future<void> writeString(String key, String? value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      await prefs.remove(key);
      return;
    }
    await prefs.setString(key, trimmed);
  }

  static bool readBool(String key, {bool defaultValue = false}) {
    final prefs = _prefs;
    if (prefs == null) return defaultValue;
    return prefs.getBool(key) ?? defaultValue;
  }

  static Future<void> writeBool(String key, bool value) async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.setBool(key, value);
  }
}
