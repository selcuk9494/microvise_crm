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
    final password = _passwordController.text.replaceAll('\uFEFF', '').trim();
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
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(raw.startsWith('Giriş') ? raw : 'Giriş başarısız: $raw'),
        ),
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
    final base = Theme.of(context);

    return SelectionContainer.disabled(
      child: Theme(
        data: base.copyWith(
          colorScheme: base.colorScheme.copyWith(
            surface: AppTheme.surface,
            onSurface: AppTheme.text,
            primary: AppTheme.primary,
            outline: AppTheme.border,
          ),
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppTheme.surface,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 13,
            ),
            hintStyle: base.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textMuted,
            ),
            labelStyle: base.textTheme.bodyMedium?.copyWith(
              color: AppTheme.textSoft,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: BorderSide(color: AppTheme.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppTheme.radiusSm),
              borderSide: BorderSide(color: AppTheme.primary, width: 1.5),
            ),
          ),
          checkboxTheme: CheckboxThemeData(
            fillColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppTheme.primary;
              }
              return Colors.transparent;
            }),
            side: BorderSide(color: AppTheme.borderStrong),
            checkColor: WidgetStateProperty.all(Colors.white),
          ),
          listTileTheme: ListTileThemeData(
            textColor: AppTheme.text,
            iconColor: AppTheme.textMuted,
          ),
        ),
        child: Scaffold(
          backgroundColor: const Color(0xFF5E7389),
          body: DecoratedBox(
            decoration: AppTheme.loginCanvas,
            child: SafeArea(
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: AppCard(
                      color: AppTheme.surface,
                      borderColor: AppTheme.border,
                      padding: const EdgeInsets.all(24),
                      child: AutofillGroup(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final compact = constraints.maxWidth < 380;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Image.asset(
                                      'assets/images/logo_v2.png',
                                      height: compact ? 36 : 44,
                                      fit: BoxFit.contain,
                                      alignment: Alignment.centerLeft,
                                      filterQuality: FilterQuality.high,
                                    ),
                                    const Gap(10),
                                    Text(
                                      'Güvenli çalışma alanı',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(color: AppTheme.textMuted),
                                    ),
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
                                      setState(
                                        () => _rememberMe = value ?? true,
                                      );
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
                                  ?.copyWith(color: AppTheme.textMuted),
                            ),
                            if (Uri.base.host == '127.0.0.1' ||
                                Uri.base.host == 'localhost') ...[
                              const Gap(10),
                              Text(
                                'Yerel Electron: şifre, .env.local içindeki MASTER_ADMIN_PASSWORD değeridir.',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppTheme.primaryDark,
                                      fontWeight: FontWeight.w600,
                                    ),
                              ),
                            ],
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
      ),
    );
  }
}
