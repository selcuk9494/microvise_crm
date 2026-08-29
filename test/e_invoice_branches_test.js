const assert = require('node:assert/strict');
const test = require('node:test');

const {
  configuredBranches,
  hydrateBranchSettings,
  resolveSelectedBranch,
  applyBranchToSettings,
  syncActiveBranchFromEnvironment,
} = require('../api/_lib/e_invoice_branches');

test('eski tek şube kodunu test ve canlıya kopyalar', () => {
  const row = hydrateBranchSettings({ seller_branch_code: 'MERKEZ' });
  assert.equal(row.test_branch_code, 'MERKEZ');
  assert.equal(row.prod_branch_code, 'MERKEZ');
  assert.equal(row.test_branch_name, 'Merkez');
});

test('ortama göre iki şube listeler', () => {
  const settings = {
    environment: 'test',
    test_branch_code: '1',
    test_branch_name: 'Lefkoşa',
    test_branch_code_2: '2',
    test_branch_name_2: 'Girne',
    prod_branch_code: 'A',
    prod_branch_name: 'Canlı Merkez',
  };
  assert.deepEqual(configuredBranches(settings, 'test'), [
    { code: '1', name: 'Lefkoşa' },
    { code: '2', name: 'Girne' },
  ]);
  assert.deepEqual(configuredBranches(settings, 'production'), [
    { code: 'A', name: 'Canlı Merkez' },
  ]);
});

test('gönderimde seçilen şubeyi ayarlara yazar', () => {
  const settings = applyBranchToSettings(
    { seller_branch_code: '1', test_branch_code: '1' },
    { code: '2', name: 'Girne' },
  );
  assert.equal(settings.seller_branch_code, '2');
  assert.equal(settings.seller_branch_name, 'Girne');
});

test('zorunlu seçimde şube yoksa hata verir', () => {
  assert.throws(
    () =>
      resolveSelectedBranch(
        { environment: 'test', test_branch_code: '1', test_branch_name: 'Merkez' },
        '',
        { required: true },
      ),
    /Hangi şubeden/,
  );
});

test('tanımsız şube kodunu reddeder', () => {
  assert.throws(
    () =>
      resolveSelectedBranch(
        {
          environment: 'production',
          prod_branch_code: '1',
          prod_branch_name: 'Merkez',
        },
        'X',
        { required: true },
      ),
    /tanımlı değil: X/,
  );
});

test('aktif ortamın birinci şubesini seller_branch_code ile eşitler', () => {
  const synced = syncActiveBranchFromEnvironment({
    environment: 'production',
    prod_branch_code: 'KASA1',
    prod_branch_name: 'Kasa',
    seller_branch_code: '1',
  });
  assert.equal(synced.seller_branch_code, 'KASA1');
  assert.equal(synced.seller_branch_name, 'Kasa');
});
