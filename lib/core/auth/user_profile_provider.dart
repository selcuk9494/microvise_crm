import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../supabase/supabase_providers.dart';

final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client?.auth.currentUser;
  if (client == null || user == null) return null;

  final row = await client
      .from('users')
      .select('id,full_name,role')
      .eq('id', user.id)
      .maybeSingle();

  if (row == null) return null;
  return UserProfile.fromJson(row);
});

final isAdminProvider = Provider<bool>((ref) {
  final async = ref.watch(currentUserProfileProvider);
  return async.value?.role == 'admin';
});

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
  });

  final String id;
  final String? fullName;
  final String role;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: (json['role'] ?? 'personel').toString(),
    );
  }
}

