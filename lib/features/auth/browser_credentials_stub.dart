class BrowserCredential {
  const BrowserCredential({required this.email, required this.password});

  final String email;
  final String password;
}

Future<bool> storeBrowserCredential({
  required String email,
  required String password,
}) async {
  return false;
}

Future<BrowserCredential?> requestBrowserCredential() async {
  return null;
}
