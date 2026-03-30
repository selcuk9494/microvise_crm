import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/format/app_date_time.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/app_section_card.dart';
import '../../core/ui/compact_stat_card.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/ui/smart_filter_bar.dart';

final personnelUsersProvider = FutureProvider<List<PersonnelUser>>((ref) async {
  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  List rows;
  try {
    rows = await client
        .from('users')
        .select(
          'id,full_name,role,email,page_permissions,action_permissions,created_at',
        )
        .order('created_at', ascending: false);
  } catch (_) {
    final fallbackRows = await client
        .from('users')
        .select('id,full_name,role,email,page_permissions,created_at')
        .order('created_at', ascending: false);
    rows = (fallbackRows as List)
        .map(
          (row) => {
            ...row as Map<String, dynamic>,
            'action_permissions': const <String>[],
          },
        )
        .toList(growable: false);
  }

  return rows
      .map((e) => PersonnelUser.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

final personnelFiltersProvider =
    NotifierProvider<PersonnelFiltersNotifier, PersonnelFilters>(
      PersonnelFiltersNotifier.new,
    );

class PersonnelFiltersNotifier extends Notifier<PersonnelFilters> {
  @override
  PersonnelFilters build() => const PersonnelFilters();

  void setQuery(String value) {
    state = state.copyWith(query: value);
  }

  void setRole(String value) {
    state = state.copyWith(role: value);
  }
}

class PersonnelFilters {
  const PersonnelFilters({this.query = '', this.role = 'all'});

  final String query;
  final String role;

  PersonnelFilters copyWith({String? query, String? role}) {
    return PersonnelFilters(
      query: query ?? this.query,
      role: role ?? this.role,
    );
  }
}

class PersonnelScreen extends ConsumerWidget {
  const PersonnelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final usersAsync = ref.watch(personnelUsersProvider);
    final filters = ref.watch(personnelFiltersProvider);

    return AppPageLayout(
      title: 'Personel',
      subtitle: 'Kullanıcılar, rol yapısı ve erişim yetkilerini yönetin.',
      actions: [
        FilledButton.icon(
          onPressed: isAdmin ? () => _openCreateDialog(context) : null,
          icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
          label: const Text('Yeni Personel'),
        ),
      ],
      body: Column(
        children: [
          if (!isAdmin)
            AppCard(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Bu sayfa sadece admin için erişilebilir.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
              ),
            )
          else
            usersAsync.when(
              data: (users) {
                final filteredUsers = users
                    .where((user) {
                      final query = filters.query.trim().toLowerCase();
                      final matchesQuery =
                          query.isEmpty ||
                          (user.fullName?.toLowerCase().contains(query) ??
                              false) ||
                          user.id.toLowerCase().contains(query);
                      final matchesRole =
                          filters.role == 'all' || user.role == filters.role;
                      return matchesQuery && matchesRole;
                    })
                    .toList(growable: false);
                final adminCount = users
                    .where((user) => user.role == 'admin')
                    .length;
                final personnelCount = users
                    .where((user) => user.role != 'admin')
                    .length;

                return Column(
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        CompactStatCard(
                          label: 'Toplam Kullanıcı',
                          value: users.length.toString(),
                          icon: Icons.groups_2_rounded,
                          color: AppTheme.primary,
                        ),
                        CompactStatCard(
                          label: 'Admin',
                          value: adminCount.toString(),
                          icon: Icons.verified_user_rounded,
                          color: AppTheme.warning,
                        ),
                        CompactStatCard(
                          label: 'Personel',
                          value: personnelCount.toString(),
                          icon: Icons.badge_rounded,
                          color: AppTheme.success,
                        ),
                      ],
                    ),
                    const Gap(16),
                    SmartFilterBar(
                      title: 'Filtreler',
                      subtitle: 'Kullanıcıları ad ve role göre daraltın.',
                      children: [
                        SizedBox(
                          width: 420,
                          child: TextField(
                            onChanged: ref
                                .read(personnelFiltersProvider.notifier)
                                .setQuery,
                            decoration: const InputDecoration(
                              hintText: 'Ad soyad veya kullanıcı ID',
                              prefixIcon: Icon(Icons.search_rounded),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 220,
                          child: DropdownButtonFormField<String>(
                            initialValue: filters.role,
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('Tüm Roller'),
                              ),
                              DropdownMenuItem(
                                value: 'admin',
                                child: Text('Admin'),
                              ),
                              DropdownMenuItem(
                                value: 'personel',
                                child: Text('Personel'),
                              ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              ref
                                  .read(personnelFiltersProvider.notifier)
                                  .setRole(value);
                            },
                            decoration: const InputDecoration(
                              hintText: 'Rol',
                              prefixIcon: Icon(
                                Icons.admin_panel_settings_rounded,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Gap(16),
                    if (filteredUsers.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.person_search_rounded,
                        title: 'Personel bulunamadı',
                        message: 'Filtreye uyan kullanıcı kaydı görünmüyor.',
                      )
                    else
                      AppSectionCard(
                        title: 'Kullanıcı Listesi',
                        subtitle: '${filteredUsers.length} kayıt gösteriliyor',
                        padding: EdgeInsets.zero,
                        child: Column(
                          children: [
                            const _Header(),
                            const Divider(height: 1),
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: filteredUsers.length,
                              separatorBuilder: (context, index) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) =>
                                  _UserRow(user: filteredUsers[index]),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (error, stackTrace) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Personel listesi yüklenemedi.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _CreatePersonnelDialog(),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFFF8FAFC),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Kullanıcı',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
                color: const Color(0xFF475569),
              ),
            ),
          ),
          const SizedBox(width: 140),
          const SizedBox(width: 170),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Rol',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: const Color(0xFF475569),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends ConsumerStatefulWidget {
  const _UserRow({required this.user});

  final PersonnelUser user;

  @override
  ConsumerState<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends ConsumerState<_UserRow> {
  bool _saving = false;
  final _dateFormat = DateFormat('d MMM y', 'tr_TR');

  Future<void> _setRole(String role) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      await client
          .from('users')
          .update({'role': role})
          .eq('id', widget.user.id);
      ref.invalidate(personnelUsersProvider);
      ref.invalidate(currentUserProfileProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Rol güncellenemedi.')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final tone = user.role == 'admin'
        ? AppBadgeTone.primary
        : AppBadgeTone.neutral;
    final label = user.role == 'admin' ? 'Admin' : 'Personel';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  user.fullName?.trim().isEmpty ?? true ? '—' : user.fullName!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Gap(2),
                Text(
                  user.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF64748B),
                  ),
                ),
                if (user.createdAt != null) ...[
                  const Gap(2),
                  Text(
                    'Eklenme: ${_dateFormat.format(user.createdAt!)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF94A3B8),
                    ),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: 'Düzenle',
            onPressed: _saving
                ? null
                : () async {
                    await showDialog<void>(
                      context: context,
                      builder: (context) => _EditPersonnelDialog(user: user),
                    );
                  },
            icon: const Icon(Icons.edit_outlined),
          ),
          const Gap(8),
          SizedBox(
            width: 140,
            child: Align(
              alignment: Alignment.centerRight,
              child: MenuAnchor(
                builder: (context, controller, _) => OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(label),
                ),
                menuChildren: [
                  MenuItemButton(
                    onPressed: () => _setRole('personel'),
                    child: const Text('Personel'),
                  ),
                  MenuItemButton(
                    onPressed: () => _setRole('admin'),
                    child: const Text('Admin'),
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          SizedBox(
            width: 170,
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 4,
              runSpacing: 4,
              children: user.pagePermissions
                  .take(2)
                  .map((page) {
                    return AppBadge(
                      label: pagePermissionLabels[page] ?? page,
                      tone: AppBadgeTone.neutral,
                    );
                  })
                  .toList(growable: false),
            ),
          ),
          const Gap(10),
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: AppBadge(label: label, tone: tone),
            ),
          ),
        ],
      ),
    );
  }
}

class _CreatePersonnelDialog extends ConsumerStatefulWidget {
  const _CreatePersonnelDialog();

  @override
  ConsumerState<_CreatePersonnelDialog> createState() =>
      _CreatePersonnelDialogState();
}

class _CreatePersonnelDialogState
    extends ConsumerState<_CreatePersonnelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
  String _role = 'personel';
  late final Set<String> _pagePermissions;
  final Set<String> _actionPermissions = <String>{};
  bool _saving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final ok = _formKey.currentState?.validate() ?? false;
    if (!ok) return;

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final fullName = _fullNameController.text.trim();
      await client.rpc(
        'admin_create_personnel',
        params: {
          'p_email': email,
          'p_password': password,
          'p_full_name': fullName,
          'p_role': _role,
          'p_page_permissions': _pagePermissions.toList(growable: false),
          'p_action_permissions': _actionPermissions.toList(growable: false),
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(personnelUsersProvider);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Personel oluşturuldu.')));
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Hata: ${e.message}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(
        SnackBar(content: Text('Personel oluşturulamadı: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void initState() {
    super.initState();
    _pagePermissions = {...defaultPersonnelPagePermissions};
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Yeni Personel',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kapat',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const Gap(12),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(
                    labelText: 'Ad Soyad',
                    hintText: 'Örn: Ahmet Yılmaz',
                  ),
                  validator: (v) => v == null || v.trim().length < 2
                      ? 'Ad soyad gerekli.'
                      : null,
                ),
                const Gap(12),
                TextFormField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-posta',
                    hintText: 'personel@firma.com',
                  ),
                  validator: (v) =>
                      v == null || !v.contains('@') ? 'E-posta gerekli.' : null,
                ),
                const Gap(12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Şifre',
                    hintText: 'Minimum 6 karakter',
                  ),
                  validator: (v) => v == null || v.length < 6
                      ? 'Şifre en az 6 karakter.'
                      : null,
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  items: const [
                    DropdownMenuItem(
                      value: 'personel',
                      child: Text('Personel'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _role = value);
                        },
                  decoration: const InputDecoration(labelText: 'Rol'),
                ),
                const Gap(12),
                _PermissionsEditor(
                  label: 'Sayfa Yetkileri',
                  selected: _pagePermissions,
                  onChanged: (value) {
                    setState(() {
                      _pagePermissions
                        ..clear()
                        ..addAll(value);
                    });
                  },
                ),
                const Gap(12),
                _PermissionsEditor(
                  label: 'İşlem Yetkileri',
                  labels: actionPermissionLabels,
                  selected: _actionPermissions,
                  onChanged: (value) {
                    setState(() {
                      _actionPermissions
                        ..clear()
                        ..addAll(value);
                    });
                  },
                ),
                const Gap(18),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    'Yeni kullanıcı admin yetkili güvenli akış ile oluşturulur; mevcut oturum etkilenmez.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: const Color(0xFF64748B),
                    ),
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _create,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Oluştur'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EditPersonnelDialog extends ConsumerStatefulWidget {
  const _EditPersonnelDialog({required this.user});

  final PersonnelUser user;

  @override
  ConsumerState<_EditPersonnelDialog> createState() =>
      _EditPersonnelDialogState();
}

class _EditPersonnelDialogState extends ConsumerState<_EditPersonnelDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _fullNameController;
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  late Set<String> _pagePermissions;
  late Set<String> _actionPermissions;
  late String _role;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController = TextEditingController(
      text: widget.user.fullName ?? '',
    );
    _emailController = TextEditingController(text: widget.user.email ?? '');
    _pagePermissions = widget.user.pagePermissions.isEmpty
        ? {...defaultPersonnelPagePermissions}
        : {...widget.user.pagePermissions};
    _actionPermissions = {...widget.user.actionPermissions};
    _role = widget.user.role;
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final isSelf = client.auth.currentUser?.id == widget.user.id;
      final newPassword = _passwordController.text.trim();

      try {
        await client
            .from('users')
            .update({
              'full_name': _fullNameController.text.trim(),
              'role': _role,
              'page_permissions': _pagePermissions.toList(growable: false),
              'action_permissions': _actionPermissions.toList(growable: false),
            })
            .eq('id', widget.user.id);
      } catch (_) {
        await client
            .from('users')
            .update({
              'full_name': _fullNameController.text.trim(),
              'role': _role,
              'page_permissions': _pagePermissions.toList(growable: false),
            })
            .eq('id', widget.user.id);
      }

      String? passwordMessage;
      if (newPassword.isNotEmpty && isSelf) {
        try {
          await client.auth.updateUser(UserAttributes(password: newPassword));
          passwordMessage = 'Bilgiler ve şifre güncellendi.';
        } on AuthException catch (e) {
          passwordMessage =
              'Bilgiler güncellendi, şifre değiştirilemedi: ${e.message}';
        } catch (e) {
          passwordMessage = 'Bilgiler güncellendi, şifre değiştirilemedi: $e';
        }
      } else if (newPassword.isNotEmpty &&
          _emailController.text.trim().isNotEmpty) {
        try {
          await client.rpc(
            'admin_update_personnel_password',
            params: {
              'p_user_id': widget.user.id,
              'p_password': newPassword,
            },
          );
          passwordMessage = 'Bilgiler ve şifre güncellendi.';
        } on AuthException catch (e) {
          passwordMessage =
              'Bilgiler güncellendi, şifre değiştirilemedi: ${e.message}';
        } catch (e) {
          passwordMessage =
              'Bilgiler güncellendi, şifre değiştirilemedi: $e';
        }
      }

      ref.invalidate(personnelUsersProvider);
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(passwordMessage ?? 'Personel bilgisi güncellendi.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Personel bilgisi güncellenemedi: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.read(supabaseClientProvider);
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: AppCard(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Personel Düzenle',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Gap(16),
                TextFormField(
                  controller: _emailController,
                  enabled: false,
                  decoration: const InputDecoration(labelText: 'E-posta'),
                ),
                const Gap(12),
                TextFormField(
                  controller: _fullNameController,
                  decoration: const InputDecoration(labelText: 'Ad Soyad'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Ad soyad gerekli.'
                      : null,
                ),
                const Gap(12),
                DropdownButtonFormField<String>(
                  initialValue: _role,
                  items: const [
                    DropdownMenuItem(
                      value: 'personel',
                      child: Text('Personel'),
                    ),
                    DropdownMenuItem(value: 'admin', child: Text('Admin')),
                  ],
                  onChanged: _saving
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() => _role = value);
                        },
                  decoration: const InputDecoration(labelText: 'Rol'),
                ),
                const Gap(12),
                _PermissionsEditor(
                  label: 'Sayfa Yetkileri',
                  selected: _pagePermissions,
                  onChanged: (value) {
                    setState(() {
                      _pagePermissions = value;
                    });
                  },
                ),
                const Gap(12),
                _PermissionsEditor(
                  label: 'İşlem Yetkileri',
                  labels: actionPermissionLabels,
                  selected: _actionPermissions,
                  onChanged: (value) {
                    setState(() {
                      _actionPermissions = value;
                    });
                  },
                ),
                const Gap(12),
                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: client?.auth.currentUser?.id == widget.user.id
                        ? 'Yeni Şifre'
                        : 'Yeni Şifre',
                    hintText: client?.auth.currentUser?.id == widget.user.id
                        ? 'Boş bırakırsan değişmez'
                        : 'Boş bırakırsan değişmez',
                  ),
                  validator: (value) {
                    if ((value ?? '').isNotEmpty && value!.length < 6) {
                      return 'Şifre en az 6 karakter.';
                    }
                    return null;
                  },
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(),
                        child: const Text('Vazgeç'),
                      ),
                    ),
                    const Gap(12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Text('Kaydet'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class PersonnelUser {
  const PersonnelUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.email,
    required this.pagePermissions,
    required this.actionPermissions,
    required this.createdAt,
  });

  final String id;
  final String? fullName;
  final String role;
  final String? email;
  final List<String> pagePermissions;
  final List<String> actionPermissions;
  final DateTime? createdAt;

  factory PersonnelUser.fromJson(Map<String, dynamic> json) {
    return PersonnelUser(
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
      createdAt: parseAppDateTime(json['created_at']?.toString()),
    );
  }
}

class _PermissionsEditor extends StatelessWidget {
  const _PermissionsEditor({
    required this.selected,
    required this.onChanged,
    this.label = 'Sayfa Yetkileri',
    this.labels = pagePermissionLabels,
  });

  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String label;
  final Map<String, String> labels;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: labels.entries
            .map((entry) {
              final active = selected.contains(entry.key);
              return FilterChip(
                selected: active,
                label: Text(entry.value),
                onSelected: (value) {
                  final next = {...selected};
                  if (value) {
                    next.add(entry.key);
                  } else {
                    next.remove(entry.key);
                  }
                  onChanged(next);
                },
              );
            })
            .toList(growable: false),
      ),
    );
  }
}
