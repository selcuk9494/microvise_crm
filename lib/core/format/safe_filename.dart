/// Filesystem / download-safe names that keep ASCII case.
///
/// Turkish letters are folded (Ü→U, ü→u) instead of becoming `_`.
String foldTurkishAsciiPreserveCase(String input) {
  return input
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'G')
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'I')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'O')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 'S')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U');
}

/// Sanitize a download filename. Preserves `.pdf` / other extensions.
String safeDownloadFilename(
  String input, {
  String fallback = 'e_fatura.pdf',
  int maxLen = 120,
}) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return fallback;
  final dot = trimmed.lastIndexOf('.');
  final hasExt = dot > 0 && dot < trimmed.length - 1;
  final stemRaw = hasExt ? trimmed.substring(0, dot) : trimmed;
  final extRaw = hasExt ? trimmed.substring(dot) : '';
  var stem = foldTurkishAsciiPreserveCase(stemRaw)
      .replaceAll(RegExp(r'[\u0300-\u036f]'), '')
      .replaceAll(RegExp(r'[^a-zA-Z0-9._-]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  if (stem.length > maxLen) stem = stem.substring(0, maxLen);
  stem = stem.replaceAll(RegExp(r'_+$'), '');
  final ext = extRaw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9.]'), '');
  if (stem.isEmpty) {
    final fallbackDot = fallback.lastIndexOf('.');
    stem = fallbackDot > 0 ? fallback.substring(0, fallbackDot) : fallback;
  }
  if (ext.isEmpty) {
    return stem.toLowerCase().endsWith('.pdf') ? stem : '$stem.pdf';
  }
  return '$stem$ext';
}
