import 'app_cache.dart';

class TokenStorage {
  static const _key = 'microvise_api_token';

  static String? read() => AppCache.readString(_key);

  static void write(String? value) {
    AppCache.writeString(_key, value);
  }
}

