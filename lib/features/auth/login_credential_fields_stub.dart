import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';

class LoginCredentialFields extends StatelessWidget {
  const LoginCredentialFields({
    super.key,
    required this.emailController,
    required this.passwordController,
    required this.emailFocusNode,
    required this.passwordFocusNode,
    required this.loading,
    required this.onSubmit,
    required this.onFillSavedCredential,
  });

  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocusNode;
  final FocusNode passwordFocusNode;
  final bool loading;
  final VoidCallback onSubmit;
  final VoidCallback onFillSavedCredential;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: emailController,
          focusNode: emailFocusNode,
          keyboardType: TextInputType.emailAddress,
          textInputAction: TextInputAction.next,
          autofillHints: const [AutofillHints.username, AutofillHints.email],
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
          onSubmitted: (_) => passwordFocusNode.requestFocus(),
        ),
        const Gap(12),
        TextField(
          controller: passwordController,
          focusNode: passwordFocusNode,
          obscureText: true,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autofillHints: const ['current-password', AutofillHints.password],
          autocorrect: false,
          enableSuggestions: true,
          keyboardAppearance: Brightness.light,
          style: const TextStyle(color: Color(0xFF0F172A)),
          cursorColor: AppTheme.primary,
          decoration: const InputDecoration(
            labelText: 'Şifre',
            hintText: '••••••••',
          ),
          onSubmitted: (_) => onSubmit(),
        ),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: loading ? null : onFillSavedCredential,
            icon: const Icon(Icons.password_rounded, size: 18),
            label: const Text('Kayıtlı şifreyi doldur'),
          ),
        ),
        const Gap(8),
      ],
    );
  }
}
