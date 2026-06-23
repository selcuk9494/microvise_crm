import 'dart:js_interop';

@JS('microviseStorePasswordCredential')
external JSPromise<JSBoolean?> _storePasswordCredential(
  JSString email,
  JSString password,
);

@JS('microviseRequestPasswordCredential')
external JSPromise<_BrowserCredentialResult?> _requestPasswordCredential();

extension type _BrowserCredentialResult(JSObject _) implements JSObject {
  external JSString? get id;
  external JSString? get password;
}

class BrowserCredential {
  const BrowserCredential({required this.email, required this.password});

  final String email;
  final String password;
}

Future<bool> storeBrowserCredential({
  required String email,
  required String password,
}) async {
  final cleanEmail = email.trim();
  if (cleanEmail.isEmpty || password.isEmpty) return false;

  try {
    final result = await _storePasswordCredential(
      cleanEmail.toJS,
      password.toJS,
    ).toDart;
    return result?.toDart ?? false;
  } catch (_) {
    return false;
  }
}

Future<BrowserCredential?> requestBrowserCredential() async {
  try {
    final result = await _requestPasswordCredential().toDart;
    final email = result?.id?.toDart.trim() ?? '';
    final password = result?.password?.toDart ?? '';
    if (email.isEmpty || password.isEmpty) return null;
    return BrowserCredential(email: email, password: password);
  } catch (_) {
    return null;
  }
}
