import 'package:flutter_riverpod/flutter_riverpod.dart';

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

final currentUserProfileProvider = FutureProvider<UserProfile?>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  final user = client?.auth.currentUser;
  if (client == null || user == null) return null;

  final row = await client
      .from('users')
      .select('id,full_name,role,email,page_permissions')
      .eq('id', user.id)
      .maybeSingle();

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

Set<String> resolveAllowedPages(UserProfile? profile) {
  if (profile == null) return allPagePermissions;
  if (profile.role == 'admin') return allPagePermissions;
  if (profile.pagePermissions.isEmpty) {
    return defaultPersonnelPagePermissions;
  }
  return profile.pagePermissions.toSet();
}

class UserProfile {
  const UserProfile({
    required this.id,
    required this.fullName,
    required this.role,
    required this.email,
    required this.pagePermissions,
  });

  final String id;
  final String? fullName;
  final String role;
  final String? email;
  final List<String> pagePermissions;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: (json['role'] ?? 'personel').toString(),
      email: json['email']?.toString(),
      pagePermissions: ((json['page_permissions'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}
