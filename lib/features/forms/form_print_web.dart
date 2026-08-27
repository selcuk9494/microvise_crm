// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

/// Printable HTML'i yeni pencerede açar.
///
/// Blob URL kullanmaz; böylece yazdırma üst/alt bilgisinde CRM linki çıkmaz.
void openFormPrintHtml(String htmlContent, {Duration? revokeAfter}) {
  try {
    final win = html.window.open('', '_blank');
    if (win != null) {
      final doc = win.document;
      doc.open();
      doc.write(htmlContent);
      doc.close();
      return;
    }
  } catch (_) {}

  // Popup engellenirse eski yol (üst/altta blob/CRM URL görünebilir).
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
