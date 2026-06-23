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
import 'browser_credentials.dart';
import 'login_credential_fields.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  static const _rememberMeKey = 'auth:remember_me';
  static const _rememberedEmailKey = 'auth:remembered_email';
  static const _legacyRememberedPasswordKey = 'auth:remembered_password';

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  bool _loading = false;
  bool _rememberMe = AppCache.readBool(_rememberMeKey, defaultValue: true);

  @override
  void initState() {
    super.initState();
    final rememberedEmail = AppCache.readString(_rememberedEmailKey);
    if (_rememberMe && rememberedEmail != null) {
      _emailController.text = rememberedEmail;
    }
    Future.microtask(() => AppCache.remove(_legacyRememberedPasswordKey));
  }

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
      if (_rememberMe) {
        await AppCache.writeString(_rememberedEmailKey, email);
        await storeBrowserCredential(email: email, password: password);
      } else {
        await AppCache.remove(_rememberedEmailKey);
      }
      TextInput.finishAutofillContext(shouldSave: true);
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

  Future<void> _fillSavedCredential() async {
    final credential = await requestBrowserCredential();
    if (!mounted) return;
    if (credential != null) {
      setState(() {
        _emailController.text = credential.email;
        _passwordController.text = credential.password;
      });
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Tarayıcıda kayıtlı giriş bulunamadı.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SelectionContainer.disabled(
      child: Scaffold(
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
                          LayoutBuilder(
                            builder: (context, constraints) {
                              final compact = constraints.maxWidth < 380;
                              final logo = Container(
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
                              );
                              final titleBlock = Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Microvise CRM',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  Text(
                                    'Güvenli çalışma alanı',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: const Color(0xFF64748B),
                                        ),
                                  ),
                                ],
                              );
                              if (compact) {
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [logo, const Gap(10), titleBlock],
                                );
                              }
                              return Row(
                                children: [
                                  logo,
                                  const Gap(12),
                                  Expanded(child: titleBlock),
                                ],
                              );
                            },
                          ),
                          const Gap(24),
                          LoginCredentialFields(
                            emailController: _emailController,
                            passwordController: _passwordController,
                            emailFocusNode: _emailFocusNode,
                            passwordFocusNode: _passwordFocusNode,
                            loading: _loading,
                            onSubmit: _signIn,
                            onFillSavedCredential: _fillSavedCredential,
                          ),
                          const Gap(8),
                          CheckboxListTile(
                            value: _rememberMe,
                            onChanged: _loading
                                ? null
                                : (value) {
                                    setState(() => _rememberMe = value ?? true);
                                    AppCache.writeBool(
                                      _rememberMeKey,
                                      _rememberMe,
                                    );
                                    if (!_rememberMe) {
                                      AppCache.remove(_rememberedEmailKey);
                                    }
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
      ),
    );
  }
}
