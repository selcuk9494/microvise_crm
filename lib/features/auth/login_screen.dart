import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/auth_providers.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/storage/app_cache.dart';
import '../../core/ui/app_card.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  bool _rememberMe = AppCache.readBool('auth:remember_me', defaultValue: true);

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('API yapılandırması yok.')),
      );
      return;
    }

    var email = _emailController.text.trim();
    while (email.endsWith('.')) {
      email = email.substring(0, email.length - 1).trimRight();
    }
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('E-posta ve şifre gerekli.')),
      );
      return;
    }

    setState(() => _loading = true);
    try {
      final response = await apiClient.postJson(
        '/auth/login',
        requiresAuth: false,
        body: {'email': email, 'password': password},
      );
      final token = (response['accessToken'] ?? '').toString();
      if (token.isEmpty) {
        throw Exception('Giriş başarısız.');
      }
      ref.read(apiAccessTokenProvider.notifier).set(token, persist: _rememberMe);
      ref.invalidate(currentUserProfileProvider);
      if (!mounted) return;
      context.go('/panel');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Giriş başarısız: ${e.toString()}')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: AppCard(
                padding: const EdgeInsets.all(24),
                child: AutofillGroup(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppTheme.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: AppTheme.primary.withValues(alpha: 0.18),
                              ),
                            ),
                            child: const Icon(
                              Icons.dashboard_customize_rounded,
                              color: AppTheme.primary,
                            ),
                          ),
                          const Gap(12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Microvise CRM',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                'Giriş',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: const Color(0xFF64748B)),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Gap(20),
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        textInputAction: TextInputAction.next,
                        autofillHints: const [AutofillHints.username],
                        keyboardAppearance: Brightness.light,
                        style: const TextStyle(color: Color(0xFF0F172A)),
                        cursorColor: AppTheme.primary,
                        decoration: const InputDecoration(
                          labelText: 'E-posta',
                          hintText: 'ornek@firma.com',
                        ),
                      ),
                      const Gap(12),
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        textInputAction: TextInputAction.done,
                        autofillHints: const [AutofillHints.password],
                        keyboardAppearance: Brightness.light,
                        style: const TextStyle(color: Color(0xFF0F172A)),
                        cursorColor: AppTheme.primary,
                        decoration: const InputDecoration(
                          labelText: 'Şifre',
                          hintText: '••••••••',
                        ),
                        onSubmitted: (_) => _signIn(),
                      ),
                      const Gap(16),
                      CheckboxListTile(
                        value: _rememberMe,
                        onChanged: _loading
                            ? null
                            : (value) {
                                setState(() => _rememberMe = value ?? true);
                                AppCache.writeBool(
                                  'auth:remember_me',
                                  _rememberMe,
                                );
                              },
                        title: const Text('Beni hatırla'),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                      const Gap(6),
                      Row(
                        children: [
                          Expanded(
                            child: FilledButton(
                              onPressed: _loading ? null : _signIn,
                              child: _loading
                                  ? const SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Giriş Yap'),
                            ),
                          ),
                        ],
                      ),
                      const Gap(10),
                      Text(
                        'Admin ve personel rolleri sistem üzerinden yönetilir.',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: const Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
