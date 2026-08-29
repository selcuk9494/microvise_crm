// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Printable HTML'i tek sekmede açar.
void openFormPrintHtml(String htmlContent, {Duration? revokeAfter}) {
  final blob = html.Blob([htmlContent], 'text/html');
  final url = html.Url.createObjectUrlFromBlob(blob);
  try {
    html.window.open(url, '_blank');
  } catch (_) {
    try {
      html.window.location.assign(url);
    } catch (_) {
      html.window.location.href = url;
    }
  }
  Future<void>.delayed(
    revokeAfter ?? const Duration(seconds: 10),
    () => html.Url.revokeObjectUrl(url),
  );
}
