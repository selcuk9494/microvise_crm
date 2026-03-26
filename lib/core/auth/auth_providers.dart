import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../supabase/supabase_providers.dart';

final authStateProvider = StreamProvider<AuthState?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const Stream.empty();
  return client.auth.onAuthStateChange;
});

final sessionProvider = Provider<Session?>((ref) {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return null;
  return client.auth.currentSession;
});

