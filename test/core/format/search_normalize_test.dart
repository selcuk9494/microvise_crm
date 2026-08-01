import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/core/format/search_normalize.dart';

void main() {
  group('normalizeSearchText Turkish İ/I', () {
    test('MİCROVISE matches mic and mıc', () {
      final hay = normalizeSearchText('MİCROVISE');
      expect(hay, 'microvise');
      expect(hay.contains(normalizeSearchText('mic')), isTrue);
      expect(hay.contains(normalizeSearchText('mıc')), isTrue);
      expect(hay.contains(normalizeSearchText('MIC')), isTrue);
      expect(hay.contains(normalizeSearchText('MİC')), isTrue);
    });

    test('MICROVISE / Microvise match mic and mıc', () {
      for (final name in ['MICROVISE', 'Microvise', 'Mıcrovise']) {
        expect(
          matchesSearchQuery(name, 'mic'),
          isTrue,
          reason: name,
        );
        expect(
          matchesSearchQuery(name, 'mıc'),
          isTrue,
          reason: name,
        );
      }
    });

    test('combining-dot İ form still folds', () {
      // Simulate JS toLowerCase residue: i + U+0307
      const dotted = 'MİCROVISE';
      expect(normalizeSearchText(dotted), 'microvise');
      expect(matchesSearchQuery('mi\u0307crovise', 'mic'), isTrue);
    });

    test('multi-token substring', () {
      expect(
        matchesSearchQuery('MİCROVISE INNOVATION LIMITED', 'mic lim'),
        isTrue,
      );
      expect(
        matchesSearchQuery('MİCROVISE INNOVATION LIMITED', 'mic xyz'),
        isFalse,
      );
    });
  });
}
