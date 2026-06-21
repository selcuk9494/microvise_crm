import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
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
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _loading = false;
  bool _rememberMe = AppCache.readBool('auth:remember_me', defaultValue: true);

  @override
  void dispose() {
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('API yapılandırması yok.')));
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
      ref
          .read(apiAccessTokenProvider.notifier)
          .set(token, persist: _rememberMe);
      TextInput.finishAutofillContext(shouldSave: _rememberMe);
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
      body: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.backgroundAlt.withValues(alpha: 0.72),
              AppTheme.background,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
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
                              width: 152,
                              height: 44,
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(
                                  AppTheme.radiusMd,
                                ),
                                border: Border.all(color: AppTheme.border),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: OverflowBox(
                                maxWidth: 152,
                                maxHeight: 152,
                                child: Image.asset(
                                  'assets/images/logo.png',
                                  width: 152,
                                  height: 152,
                                  fit: BoxFit.cover,
                                ),
                              ),
                            ),
                            const Gap(12),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Microvise CRM',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                ),
                                Text(
                                  'Güvenli çalışma alanı',
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: const Color(0xFF64748B),
                                      ),
                                ),
                              ],
                            ),
                          ],
                        ),
                        const Gap(24),
                        TextField(
                          controller: _emailController,
                          focusNode: _emailFocusNode,
                          keyboardType: TextInputType.emailAddress,
                          textInputAction: TextInputAction.next,
                          autofillHints: const [
                            AutofillHints.username,
                            AutofillHints.email,
                          ],
                          autocorrect: false,
                          enableSuggestions: true,
                          textCapitalization: TextCapitalization.none,
                          keyboardAppearance: Brightness.light,
                          style: const TextStyle(color: Color(0xFF0F172A)),
                          cursorColor: AppTheme.primary,
                          decoration: const InputDecoration(
                            labelText: 'E-posta',
                            hintText: 'ornek@firma.com',
                          ),
                          onSubmitted: (_) => _passwordFocusNode.requestFocus(),
                        ),
                        const Gap(12),
                        TextField(
                          controller: _passwordController,
                          focusNode: _passwordFocusNode,
                          obscureText: true,
                          keyboardType: TextInputType.visiblePassword,
                          textInputAction: TextInputAction.done,
                          autofillHints: const [AutofillHints.password],
                          autocorrect: false,
                          enableSuggestions: false,
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
                        const Gap(12),
                        Text(
                          'Admin ve personel rolleri sistem üzerinden yönetilir.',
                          style: Theme.of(context).textTheme.bodySmall
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
      ),
    );
  }
}
