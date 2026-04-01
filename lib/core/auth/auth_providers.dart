import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';
import '../storage/token_storage.dart';

final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  return client.auth.onAuthStateChange;
});

final sessionChangesProvider = StreamProvider<Session?>((ref) async* {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) {
    yield null;
    return;
  }

  yield client.auth.currentSession;
  yield* client.auth.onAuthStateChange.map((event) => event.session);
});

final sessionProvider = Provider<Session?>((ref) {
  return ref.watch(sessionChangesProvider).maybeWhen(
    data: (session) => session,
    orElse: () => ref.watch(supabaseClientProvider)?.auth.currentSession,
  );
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
  if (apiToken != null && apiToken.isNotEmpty) return apiToken;
  return ref.watch(sessionProvider)?.accessToken;
});
