/// Turkish-aware search fold used by cari / müşteri filters.
///
/// Critical: never call [String.toLowerCase] before mapping `İ`/`I`.
/// On JS (Flutter web / Electron), `İ`.toLowerCase() becomes `i` + U+0307
/// (combining dot), which breaks substring match for ASCII queries like `mic`.
String normalizeSearchText(String input) {
  var s = turkishToLower(input);
  // Defend against precomposed/NFD leftovers (İ → i + U+0307 on some runtimes).
  s = s.replaceAll('\u0307', '');
  s = s
      .replaceAll('ç', 'c')
      .replaceAll('ğ', 'g')
      .replaceAll('ı', 'i')
      .replaceAll('ö', 'o')
      .replaceAll('ş', 's')
      .replaceAll('ü', 'u');
  s = s.replaceAll(RegExp(r'\s+'), ' ');
  return s;
}

String turkishToUpper(String input) {
  var s = input.trim();
  s = s
      .replaceAll('i', 'İ')
      .replaceAll('ı', 'I')
      .replaceAll('ş', 'Ş')
      .replaceAll('ğ', 'Ğ')
      .replaceAll('ü', 'Ü')
      .replaceAll('ö', 'Ö')
      .replaceAll('ç', 'Ç');
  return s.toUpperCase();
}

String turkishToLower(String input) {
  var s = input.trim();
  // Order matters: map dotted/dotless I before generic toLowerCase.
  s = s
      .replaceAll('I', 'ı')
      .replaceAll('İ', 'i')
      .replaceAll('Ş', 'ş')
      .replaceAll('Ğ', 'ğ')
      .replaceAll('Ü', 'ü')
      .replaceAll('Ö', 'ö')
      .replaceAll('Ç', 'ç');
  return s.toLowerCase();
}

/// True when every whitespace-separated query token is a substring of [haystack]
/// after [normalizeSearchText]. Empty query matches everything.
bool matchesSearchQuery(String haystack, String query) {
  final normalizedHay = normalizeSearchText(haystack);
  final normalizedQuery = normalizeSearchText(query);
  if (normalizedQuery.isEmpty) return true;
  final tokens = normalizedQuery
      .split(RegExp(r'\s+'))
      .where((t) => t.isNotEmpty);
  for (final token in tokens) {
    if (!normalizedHay.contains(token)) return false;
  }
  return true;
}

Set<String> buildSearchVariants(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const {};
  final variants = <String>{
    raw,
    raw.toLowerCase(),
    raw.toUpperCase(),
    turkishToLower(raw),
    turkishToUpper(raw),
    normalizeSearchText(raw),
  };
  variants.removeWhere((e) => e.trim().isEmpty);
  return variants;
}
