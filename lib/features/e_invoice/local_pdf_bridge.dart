import 'package:flutter/foundation.dart';

/// `/api/_local/open-pdf` yalnızca Electron veya localhost API’de vardır.
/// crm.microvise.net gibi bulut host’ta bu URL Vercel 404 sayfası açar.
bool canUseLocalOpenPdfBridge({Uri? base, bool? isWeb}) {
  final web = isWeb ?? kIsWeb;
  if (!web) return false;
  final uri = base ?? Uri.base;
  if (uri.scheme == 'file' || uri.scheme == 'app') return true;
  final host = uri.host.toLowerCase();
  return host == 'localhost' || host == '127.0.0.1' || host == '::1';
}
