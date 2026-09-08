import 'package:flutter_test/flutter_test.dart';
import 'package:microvise_crm/core/format/safe_filename.dart';

void main() {
  group('safeDownloadFilename Turkish fold', () {
    test('GÜZBEL keeps U instead of underscore', () {
      expect(
        safeDownloadFilename(
          'GÜZBEL YATIRIM LTD._2026-1-00000000085.pdf',
        ),
        'GUZBEL_YATIRIM_LTD._2026-1-00000000085.pdf',
      );
    });

    test('folds mixed Turkish letters and preserves case', () {
      expect(
        foldTurkishAsciiPreserveCase('Çiğköfte ŞÖLEN'),
        'Cigkofte SOLEN',
      );
    });
  });
}
