import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/token_storage.dart';

final authStateProvider = StreamProvider<void>((ref) {
  return const Stream.empty();
});

final apiAccessTokenProvider =
    NotifierProvider<ApiAccessTokenNotifier, String?>(ApiAccessTokenNotifier.new);

class ApiAccessTokenNotifier extends Notifier<String?> {
  @override
  String? build() => TokenStorage.read();

  void set(String? token, {bool persist = true}) {
    final trimmed = token?.trim();
    final value = (trimmed == null || trimmed.isEmpty) ? null : trimmed;
    if (persist) {
      TokenStorage.write(value);
    } else {
      TokenStorage.write(null);
    }
    state = value;
  }

  void clear({bool persist = true}) {
    if (persist) {
      TokenStorage.write(null);
    }
    state = null;
  }
}

final accessTokenProvider = Provider<String?>((ref) {
  final apiToken = ref.watch(apiAccessTokenProvider);
  return (apiToken != null && apiToken.isNotEmpty) ? apiToken : null;
});
