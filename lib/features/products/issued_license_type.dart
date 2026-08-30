class IssuedLicenseType {
  static const gmp3 = 'gmp3';
  static const iresto = 'iresto';

  static String normalize(String? raw) {
    final n = (raw ?? '')
        .trim()
        .toLowerCase()
        .replaceAll('ı', 'i')
        .replaceAll('İ', 'i')
        .replaceAll(RegExp(r'[\s_\-]+'), '');
    if (n.contains('iresto')) return iresto;
    if (n.contains('gmp3') || n == 'gmp') return gmp3;
    return n;
  }

  static String label(String? raw) {
    switch (normalize(raw)) {
      case iresto:
        return 'iResto';
      case gmp3:
        return 'GMP3';
      default:
        final t = (raw ?? '').trim();
        return t.isEmpty ? 'Lisans' : t;
    }
  }

  static String defaultName(String type) {
    return normalize(type) == iresto ? 'iResto Lisansı' : 'GMP3 Lisansı';
  }

  static bool isGmp3(String? raw) => normalize(raw) == gmp3;
  static bool isIresto(String? raw) => normalize(raw) == iresto;
}
