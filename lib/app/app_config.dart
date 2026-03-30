import 'package:flutter/foundation.dart';

class AppConfig {
  static const _defaultSupabaseUrl = 'https://xvbczyhvmmcvqezjjpbn.supabase.co';
  static const _defaultSupabasePublishableKey =
      'sb_publishable_H5LsiU6dSi-8ymL9rYBjIg_NPzJ8hAq';
  static const _envSupabasePublishableKey = String.fromEnvironment(
    'SUPABASE_PUBLISHABLE_KEY',
    defaultValue: '',
  );
  static const _envSupabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );
  static const _envApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: '',
  );

  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _defaultSupabaseUrl,
  );
  static String get supabaseAnonKey {
    if (_envSupabasePublishableKey.isNotEmpty) {
      return _envSupabasePublishableKey;
    }
    if (_envSupabaseAnonKey.isNotEmpty) {
      return _envSupabaseAnonKey;
    }
    return _defaultSupabasePublishableKey;
  }

  static bool get isSupabaseConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

  static String? get apiBaseUrl {
    if (_envApiBaseUrl.isNotEmpty) return _envApiBaseUrl;
    if (kIsWeb) return '/api';
    return null;
  }
}
