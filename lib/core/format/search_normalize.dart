String normalizeSearchText(String input) {
  var s = input.trim().toLowerCase();
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

Set<String> buildSearchVariants(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return const {};
  final variants = <String>{
    raw,
    raw.toLowerCase(),
    raw.toUpperCase(),
    turkishToLower(raw),
    turkishToUpper(raw),
  };
  variants.removeWhere((e) => e.trim().isEmpty);
  return variants;
}

