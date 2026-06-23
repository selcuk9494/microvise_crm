import 'dart:js_interop';
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';
import 'package:gap/gap.dart';
import 'package:web/web.dart' as web;

class LoginCredentialFields extends StatefulWidget {
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
  State<LoginCredentialFields> createState() => _LoginCredentialFieldsState();
}

class _LoginCredentialFieldsState extends State<LoginCredentialFields> {
  static int _nextViewId = 0;

  late final String _viewType = 'microvise-login-credentials-${_nextViewId++}';
  web.HTMLInputElement? _emailInput;
  web.HTMLInputElement? _passwordInput;

  @override
  void initState() {
    super.initState();
    widget.emailController.addListener(_syncEmailFromController);
    widget.passwordController.addListener(_syncPasswordFromController);
    ui_web.platformViewRegistry.registerViewFactory(_viewType, _createForm);
  }

  @override
  void dispose() {
    widget.emailController.removeListener(_syncEmailFromController);
    widget.passwordController.removeListener(_syncPasswordFromController);
    super.dispose();
  }

  web.HTMLElement _createForm(int viewId) {
    final form = web.HTMLFormElement()
      ..method = 'post'
      ..action = '/'
      ..style.cssText =
          'display:flex;flex-direction:column;gap:12px;width:100%;height:100%;'
          'margin:0;padding:0;background:transparent;box-sizing:border-box;'
      ..setAttribute('autocomplete', 'on');

    _emailInput = _buildInput(
      id: 'microvise-email-$viewId',
      label: 'E-posta',
      placeholder: 'ornek@firma.com',
      type: 'email',
      name: 'username',
      autocomplete: 'username',
      value: widget.emailController.text,
      onInput: (value) => _setControllerText(widget.emailController, value),
    );
    _passwordInput = _buildInput(
      id: 'microvise-password-$viewId',
      label: 'Şifre',
      placeholder: 'Şifre',
      type: 'password',
      name: 'password',
      autocomplete: 'current-password',
      value: widget.passwordController.text,
      onInput: (value) => _setControllerText(widget.passwordController, value),
    );

    form.append(_wrapField(_emailInput!, 'E-posta'));
    form.append(_wrapField(_passwordInput!, 'Şifre'));
    form.addEventListener(
      'submit',
      ((web.Event event) {
        event.preventDefault();
        widget.onSubmit();
      }).toJS,
    );
    return form;
  }

  web.HTMLInputElement _buildInput({
    required String id,
    required String label,
    required String placeholder,
    required String type,
    required String name,
    required String autocomplete,
    required String value,
    required void Function(String value) onInput,
  }) {
    final input = web.HTMLInputElement()
      ..id = id
      ..type = type
      ..name = name
      ..value = value
      ..placeholder = placeholder
      ..style.cssText =
          'width:100%;height:56px;border:1px solid #dce5f0;border-radius:10px;'
          'background:#fff;color:#0f172a;font:400 16px Inter,Roboto,Arial,sans-serif;'
          'outline:none;padding:18px 14px 6px;box-sizing:border-box;'
          'box-shadow:none;appearance:none;-webkit-appearance:none;';
    input
      ..setAttribute('aria-label', label)
      ..setAttribute('autocomplete', autocomplete)
      ..setAttribute('autocapitalize', 'none')
      ..setAttribute('autocorrect', 'off')
      ..setAttribute('spellcheck', 'false');
    input.addEventListener(
      'input',
      ((web.Event event) => onInput(input.value)).toJS,
    );
    input.addEventListener(
      'keydown',
      ((web.KeyboardEvent event) {
        if (event.key == 'Enter') {
          event.preventDefault();
          widget.onSubmit();
        }
      }).toJS,
    );
    return input;
  }

  web.HTMLDivElement _wrapField(web.HTMLInputElement input, String labelText) {
    final wrapper = web.HTMLDivElement()
      ..style.cssText =
          'position:relative;width:100%;height:56px;margin:0;padding:0;';
    final label = web.HTMLLabelElement()
      ..textContent = labelText
      ..style.cssText =
          'position:absolute;left:14px;top:7px;z-index:1;color:#64748b;'
          'font:500 12px Inter,Roboto,Arial,sans-serif;line-height:1;'
      ..setAttribute('for', input.id);
    wrapper.append(label);
    wrapper.append(input);
    return wrapper;
  }

  void _syncEmailFromController() {
    final input = _emailInput;
    if (input != null && input.value != widget.emailController.text) {
      input.value = widget.emailController.text;
    }
  }

  void _syncPasswordFromController() {
    final input = _passwordInput;
    if (input != null && input.value != widget.passwordController.text) {
      input.value = widget.passwordController.text;
    }
  }

  void _setControllerText(TextEditingController controller, String value) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: 124, child: HtmlElementView(viewType: _viewType)),
        const Gap(8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: widget.loading ? null : widget.onFillSavedCredential,
            icon: const Icon(Icons.password_rounded, size: 18),
            label: const Text('Kayıtlı şifreyi doldur'),
          ),
        ),
        const Gap(8),
      ],
    );
  }
}
