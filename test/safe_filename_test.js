const { test } = require('node:test');
const assert = require('node:assert/strict');

const {
  foldTurkishAsciiPreserveCase,
  safeDownloadFilename,
  safeFilenamePart,
} = require('../api/_lib/safe_filename');

test('GÜZBEL PDF adı Ü harfini U yapar, alt çizgiye çevirmez', () => {
  assert.equal(
    safeDownloadFilename('GÜZBEL YATIRIM LTD._2026-1-00000000085.pdf'),
    'GUZBEL_YATIRIM_LTD._2026-1-00000000085.pdf',
  );
  assert.equal(safeFilenamePart('GÜZBEL'), 'GUZBEL');
  assert.equal(foldTurkishAsciiPreserveCase('GÜZBEL'), 'GUZBEL');
});
