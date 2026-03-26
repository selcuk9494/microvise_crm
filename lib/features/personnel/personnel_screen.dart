import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../app/theme/app_theme.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';

final personnelUsersProvider = FutureProvider<List<PersonnelUser>>((ref) async {
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

class PersonnelScreen extends ConsumerWidget {
  const PersonnelScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    final usersAsync = ref.watch(personnelUsersProvider);

    return AppPageLayout(
      title: 'Personel',
      subtitle: 'Kullanıcılar, roller ve erişim.',
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
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: const Color(0xFF64748B)),
                ),
              ),
            )
          else
            usersAsync.when(
              data: (users) => AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    const _Header(),
                    const Divider(height: 1),
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: users.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) => _UserRow(user: users[index]),
                    ),
                  ],
                ),
              ),
              loading: () => const AppCard(child: SizedBox(height: 240)),
              error: (_, __) => AppCard(
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

  Future<void> _setRole(String role) async {
    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      await client.from('users').update({'role': role}).eq('id', widget.user.id);
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
                  user.id,
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

    final client = ref.read(supabaseClientProvider);
    if (client == null) return;

    setState(() => _saving = true);
    try {
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final fullName = _fullNameController.text.trim();

      final res = await client.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': fullName},
      );

      if (res.user == null) {
        throw const AuthException('Kullanıcı oluşturulamadı.');
      }

      await client.from('users').upsert({
        'id': res.user!.id,
        'full_name': fullName,
        'role': 'personel',
      });

      if (!mounted) return;
      Navigator.of(context).pop();
      ref.invalidate(personnelUsersProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Personel oluşturuldu.')),
      );
    } on AuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: ${e.message}')),
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
                    'Not: Supabase ayarlarında e-posta doğrulama açıksa, kullanıcı ilk girişte doğrulama gerektirebilir.',
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
  });

  final String id;
  final String? fullName;
  final String role;

  factory PersonnelUser.fromJson(Map<String, dynamic> json) {
    return PersonnelUser(
      id: json['id'].toString(),
      fullName: json['full_name']?.toString(),
      role: (json['role'] ?? 'personel').toString(),
    );
  }
}

