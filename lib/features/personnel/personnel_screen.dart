import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final personnelUsersProvider = FutureProvider<List<PersonnelUser>>((ref) async {
  final apiClient = ref.watch(apiClientProvider);
  if (apiClient != null) {
    final response = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'personnel_users'},
    );
    return ((response['items'] as List?) ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(PersonnelUser.fromJson)
        .toList(growable: false);
  }

  final client = ref.watch(supabaseClientProvider);
  if (client == null) return const [];

  final rows = await client
      .from('users')
      .select('id,full_name,role,created_at')
      .order('created_at', ascending: false);

  return (rows as List)
      .map((e) => PersonnelUser.fromJson(e as Map<String, dynamic>))
      .toList(growable: false);
});

class PersonnelScreen extends ConsumerStatefulWidget {
  const PersonnelScreen({super.key});

  @override
  ConsumerState<PersonnelScreen> createState() => _PersonnelScreenState();
}

class _PersonnelScreenState extends ConsumerState<PersonnelScreen> {
  final _searchController = TextEditingController();
  String _roleFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final usersAsync = ref.watch(personnelUsersProvider);

    return AppPageLayout(
      title: 'Personel',
      subtitle: 'Kullanıcılar, roller ve erişim.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(personnelUsersProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            )
          else
            usersAsync.when(
              data: (users) {
                final query = _searchController.text.trim().toLowerCase();
                final filtered = users.where((u) {
                  if (_roleFilter != 'all' && u.role != _roleFilter) {
                    return false;
                  }
                  if (query.isEmpty) return true;
                  final haystack = [
                    u.fullName ?? '',
                    u.email ?? '',
                    u.role,
                    u.id,
                  ].join(' ').toLowerCase();
                  return haystack.contains(query);
                }).toList(growable: false);

                return Expanded(
                  child: Column(
                    children: [
                      AppCard(
                        padding: const EdgeInsets.all(12),
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 980;

                            final controls = Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                SizedBox(
                                  width: 260,
                                  child: TextField(
                                    controller: _searchController,
                                    onChanged: (_) => setState(() {}),
                                    decoration: const InputDecoration(
                                      prefixIcon: Icon(Icons.search_rounded),
                                      hintText: 'Ara',
                                    ),
                                  ),
                                ),
                                _RolePill(
                                  label: 'Rol: ${_roleLabel(_roleFilter)}',
                                  backgroundColor:
                                      AppTheme.primary.withValues(alpha: 0.12),
                                  foregroundColor: AppTheme.primaryDark,
                                  icon: Icons.badge_rounded,
                                  onTap: () async {
                                    final next =
                                        await showModalBottomSheet<String>(
                                      context: context,
                                      showDragHandle: true,
                                      builder: (context) => SafeArea(
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: const [
                                            _RoleSheetItem(
                                              value: 'all',
                                              label: 'Tümü',
                                            ),
                                            _RoleSheetItem(
                                              value: 'admin',
                                              label: 'Admin',
                                            ),
                                            _RoleSheetItem(
                                              value: 'personel',
                                              label: 'Personel',
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                    if (next == null || next.trim().isEmpty) {
                                      return;
                                    }
                                    setState(() => _roleFilter = next.trim());
                                  },
                                ),
                                FilledButton.tonalIcon(
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _roleFilter = 'all');
                                  },
                                  icon: const Icon(
                                    Icons.delete_outline_rounded,
                                    size: 18,
                                  ),
                                  label: const Text('Temizle'),
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444)
                                        .withValues(alpha: 0.12),
                                    foregroundColor: const Color(0xFF7F1D1D),
                                    minimumSize: const Size(0, 40),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                  ),
                                ),
                              ],
                            );

                            final stats = AppBadge(
                              label: 'Toplam: ${filtered.length}',
                              tone: AppBadgeTone.primary,
                            );

                            if (wide) {
                              return Row(
                                children: [
                                  Expanded(child: controls),
                                  const Gap(12),
                                  stats,
                                ],
                              );
                            }

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                controls,
                                const Gap(10),
                                stats,
                              ],
                            );
                          },
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: filtered.isEmpty
                            ? const AppCard(
                                child: Center(child: Text('Kayıt bulunamadı.')),
                              )
                            : AppCard(
                                padding: EdgeInsets.zero,
                                child: Column(
                                  children: [
                                    const _Header(),
                                    const Divider(height: 1),
                                    Expanded(
                                      child: ListView.separated(
                                        padding: EdgeInsets.zero,
                                        itemCount: filtered.length,
                                        separatorBuilder: (context, index) =>
                                            const Divider(height: 1),
                                        itemBuilder: (context, index) =>
                                            _UserRow(user: filtered[index]),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ],
                  ),
                );
              },
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (_, _) => AppCard(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'Personel listesi yüklenemedi.',
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: const Color(0xFF64748B)),
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
      color: AppTheme.surfaceMuted,
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
          SizedBox(
            width: 110,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Rol',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w800,
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

class _RolePill extends StatelessWidget {
  const _RolePill({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: foregroundColor),
            const Gap(8),
            Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: foregroundColor, fontWeight: FontWeight.w700),
            ),
            const Gap(6),
            Icon(Icons.expand_more_rounded, size: 18, color: foregroundColor),
          ],
        ),
      ),
    );
  }
}

class _RoleSheetItem extends StatelessWidget {
  const _RoleSheetItem({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      onTap: () => Navigator.of(context).pop(value),
    );
  }
}

String _roleLabel(String value) {
  switch (value) {
    case 'admin':
      return 'Admin';
    case 'personel':
      return 'Personel';
    default:
      return 'Tümü';
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

  Future<void> _editUser() async {
    final nameController =
        TextEditingController(text: widget.user.fullName ?? '');
    final emailController = TextEditingController(text: widget.user.email ?? '');
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Personel Düzenle',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed:
                            saving ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(12),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Ad Soyad',
                    ),
                  ),
                  const Gap(12),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                    ),
                  ),
                  const Gap(18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final fullName = nameController.text.trim();
                                  final email = emailController.text.trim();
                                  if (fullName.length < 2) return;
                                  if (!email.contains('@')) return;
                                  final apiClient = ref.read(apiClientProvider);
                                  final client =
                                      ref.read(supabaseClientProvider);
                                  if (apiClient == null && client == null) {
                                    return;
                                  }
                                  setState(() => saving = true);
                                  try {
                                    if (apiClient != null) {
                                      await apiClient.patchJson(
                                        '/personnel/users',
                                        body: {
                                          'id': widget.user.id,
                                          'email': email,
                                          'full_name': fullName,
                                          'role': widget.user.role,
                                        },
                                      );
                                    } else {
                                      await client!
                                          .from('users')
                                          .update({
                                            'email': email,
                                            'full_name': fullName,
                                          })
                                          .eq('id', widget.user.id);
                                    }
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(true);
                                  } catch (_) {
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(false);
                                  } finally {
                                    setState(() => saving = false);
                                  }
                                },
                          child: saving
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
      ),
    );

    nameController.dispose();
    emailController.dispose();

    if (saved == true) {
      ref.invalidate(personnelUsersProvider);
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel güncellendi.')),
      );
    }
  }

  Future<void> _setPassword() async {
    final controller = TextEditingController();
    bool saving = false;

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: const EdgeInsets.all(24),
        backgroundColor: Colors.transparent,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: AppCard(
            padding: const EdgeInsets.all(20),
            child: StatefulBuilder(
              builder: (context, setState) => Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Şifre Değiştir',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed:
                            saving ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const Gap(12),
                  Text(
                    widget.user.email?.trim().isNotEmpty ?? false
                        ? widget.user.email!
                        : widget.user.id,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xFF64748B)),
                  ),
                  const Gap(12),
                  TextField(
                    controller: controller,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Yeni Şifre',
                      hintText: 'Minimum 6 karakter',
                    ),
                  ),
                  const Gap(18),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: saving
                              ? null
                              : () => Navigator.of(context).pop(false),
                          child: const Text('Vazgeç'),
                        ),
                      ),
                      const Gap(12),
                      Expanded(
                        child: FilledButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  final password = controller.text;
                                  if (password.length < 6) return;
                                  final apiClient = ref.read(apiClientProvider);
                                  if (apiClient == null) return;
                                  setState(() => saving = true);
                                  try {
                                    await apiClient.postJson(
                                      '/personnel/users',
                                      body: {
                                        'op': 'set_password',
                                        'id': widget.user.id,
                                        'password': password,
                                      },
                                    );
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(true);
                                  } catch (_) {
                                    if (!context.mounted) return;
                                    Navigator.of(context).pop(false);
                                  } finally {
                                    setState(() => saving = false);
                                  }
                                },
                          child: saving
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
      ),
    );

    controller.dispose();
    if (saved == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şifre güncellendi.')),
      );
    }
  }

  Future<void> _deleteUser() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Personeli Sil'),
        content: const Text('Bu kullanıcıyı silmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/personnel/users',
          body: {'op': 'delete', 'id': widget.user.id},
        );
      } else {
        await client!.from('users').delete().eq('id', widget.user.id);
      }
      ref.invalidate(personnelUsersProvider);
      ref.invalidate(currentUserProfileProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel silinemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setRole(String role) async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      if (apiClient != null) {
        await apiClient.postJson(
          '/mutate',
          body: {
            'op': 'updateWhere',
            'table': 'users',
            'filters': [
              {'col': 'id', 'op': 'eq', 'value': widget.user.id},
            ],
            'values': {'role': role},
          },
        );
      } else {
        await client!.from('users').update({'role': role}).eq('id', widget.user.id);
      }
      ref.invalidate(personnelUsersProvider);
      ref.invalidate(currentUserProfileProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rol güncellenemedi.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final tone =
        user.role == 'admin' ? AppBadgeTone.primary : AppBadgeTone.neutral;
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const Gap(2),
                Text(
                  user.email?.trim().isNotEmpty ?? false
                      ? user.email!
                      : user.id,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ],
            ),
          ),
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
          IconButton(
            tooltip: 'Düzenle',
            onPressed: _saving ? null : _editUser,
            icon: const Icon(Icons.edit_outlined),
          ),
          const Gap(2),
          IconButton(
            tooltip: 'Şifre',
            onPressed: _saving ? null : _setPassword,
            icon: const Icon(Icons.key_rounded),
          ),
          const Gap(2),
          IconButton(
            tooltip: 'Sil',
            onPressed: _saving ? null : _deleteUser,
            icon: const Icon(Icons.delete_outline_rounded),
          ),
          const Gap(6),
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

class _CreatePersonnelDialogState extends ConsumerState<_CreatePersonnelDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();
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

    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    setState(() => _saving = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final fullName = _fullNameController.text.trim();

      if (apiClient != null) {
        await apiClient.postJson(
          '/personnel/users',
          body: {
            'email': email,
            'password': password,
            'full_name': fullName,
            'role': 'personel',
            'page_permissions': const [
              'panel',
              'musteriler',
              'formlar',
              'is_emirleri',
              'servis',
              'raporlar',
              'urunler',
              'faturalama',
            ],
            'action_permissions': const [
              'duzenleme',
              'pasife_alma',
            ],
          },
        );
      } else {
        await client!.from('users').insert({
          'email': email,
          'full_name': fullName,
          'role': 'personel',
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(personnelUsersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel oluşturuldu.')),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel oluşturulamadı.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
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
                  validator: (v) =>
                      v == null || v.trim().length < 2 ? 'Ad soyad gerekli.' : null,
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
                  validator: (v) =>
                      v == null || v.length < 6 ? 'Şifre en az 6 karakter.' : null,
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
                    'Not: Personel bu bilgiler ile sisteme giriş yapar.',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: const Color(0xFF64748B)),
                  ),
                ),
                const Gap(18),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed:
                            _saving ? null : () => Navigator.of(context).pop(),
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

class PersonnelUser {
  const PersonnelUser({
    required this.id,
    required this.fullName,
    required this.role,
    required this.email,
  });

  final String id;
  final String? fullName;
  final String role;
  final String? email;

  factory PersonnelUser.fromJson(Map<String, dynamic> json) {
    return PersonnelUser(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: (json['role'] ?? 'personel').toString(),
      email: json['email']?.toString(),
    );
  }
}
