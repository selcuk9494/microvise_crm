import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/api_client.dart';
import '../supabase/supabase_providers.dart';

const kPagePanel = 'panel';
const kPageCustomers = 'musteriler';
const kPageForms = 'formlar';
const kPageWorkOrders = 'is_emirleri';
const kPageService = 'servis';
const kPageReports = 'raporlar';
const kPageProducts = 'urunler';
const kPageBilling = 'faturalama';
const kPageDefinitions = 'tanimlamalar';
const kPagePersonnel = 'personel';

const kActionEditRecords = 'duzenleme';
const kActionArchiveRecords = 'pasife_alma';
const kActionDeleteRecords = 'kalici_silme';

const allPagePermissions = <String>{
  kPagePanel,
  kPageCustomers,
  kPageForms,
  kPageWorkOrders,
  kPageService,
  kPageReports,
  kPageProducts,
  kPageBilling,
  kPageDefinitions,
  kPagePersonnel,
};

const defaultPersonnelPagePermissions = <String>{
  kPagePanel,
  kPageCustomers,
  kPageForms,
  kPageWorkOrders,
  kPageService,
  kPageReports,
  kPageProducts,
  kPageBilling,
};

const pagePermissionLabels = <String, String>{
  kPagePanel: 'Panel',
  kPageCustomers: 'Müşteriler',
  kPageForms: 'Formlar',
  kPageWorkOrders: 'İş Emirleri',
  kPageService: 'Servis',
  kPageReports: 'Raporlar',
  kPageProducts: 'Hat & Lisans',
  kPageBilling: 'Faturalama',
  kPageDefinitions: 'Tanımlamalar',
  kPagePersonnel: 'Personel',
};

const allActionPermissions = <String>{
  kActionEditRecords,
  kActionArchiveRecords,
  kActionDeleteRecords,
};

const actionPermissionLabels = <String, String>{
  kActionEditRecords: 'Düzenleme',
  kActionArchiveRecords: 'Pasife Alma',
  kActionDeleteRecords: 'Kalıcı Silme',
};

final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final row = await apiClient.getJson('/me');
    return UserProfile.fromJson(row);
  }

  final client = ref.watch(supabaseClientProvider);
  final user = client?.auth.currentUser;
  if (client == null || user == null) return null;

  Map<String, dynamic>? row;
  try {
    row = await client
        .from('users')
        .select('id,full_name,role,email,page_permissions,action_permissions')
        .eq('id', user.id)
        .maybeSingle();
  } catch (_) {
    final fallback = await client
        .from('users')
        .select('id,full_name,role,email,page_permissions')
        .eq('id', user.id)
        .maybeSingle();
    if (fallback != null) {
      row = {
        ...fallback,
        'action_permissions': const <String>[],
      };
    }
  }

  if (row == null) return null;
  return UserProfile.fromJson(row);
});

final isAdminProvider = Provider<bool>((ref) {
  final async = ref.watch(currentUserProfileProvider);
  return async.value?.role == 'admin';
});

final currentUserPagePermissionsProvider = Provider<Set<String>>((ref) {
  final async = ref.watch(currentUserProfileProvider);
  final profile = async.value;
  return resolveAllowedPages(profile);
});

final hasPageAccessProvider = Provider.family<bool, String>((ref, pageKey) {
  final pages = ref.watch(currentUserPagePermissionsProvider);
  return pages.contains(pageKey);
});

final currentUserActionPermissionsProvider = Provider<Set<String>>((ref) {
  final async = ref.watch(currentUserProfileProvider);
  final profile = async.value;
  return resolveAllowedActions(profile);
});

final hasActionAccessProvider = Provider.family<bool, String>((ref, actionKey) {
  final actions = ref.watch(currentUserActionPermissionsProvider);
  return actions.contains(actionKey);
});

Set<String> resolveAllowedPages(UserProfile? profile) {
  if (profile == null) return allPagePermissions;
  if (profile.role == 'admin') return allPagePermissions;
  if (profile.pagePermissions.isEmpty) {
    return defaultPersonnelPagePermissions;
  }
  return profile.pagePermissions.toSet();
}

Set<String> resolveAllowedActions(UserProfile? profile) {
  if (profile == null) return allActionPermissions;
  if (profile.role == 'admin') return allActionPermissions;
  return profile.actionPermissions.toSet();
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.email,
    required this.pagePermissions,
    required this.actionPermissions,
  });

  final String id;
  final String? fullName;
  final String role;
  final String? email;
  final List<String> pagePermissions;
  final List<String> actionPermissions;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: (json['role'] ?? 'personel').toString(),
      email: json['email']?.toString(),
      pagePermissions: ((json['page_permissions'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      actionPermissions: ((json['action_permissions'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}
