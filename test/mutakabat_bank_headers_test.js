const assert = require('node:assert/strict');
const fs = require('node:fs');
const test = require('node:test');
const {
  findBankCountIndex,
  loadBankRows,
} = require('../api/_lib/mutakabat_processor');

test('eski banka başlığı Uzerindeki Banka Uygulama Sayısı', () => {
  const headers = [
    'Cihaz Durumu',
    'Uygulama Adi',
    'Cihaz Modeli',
    'Uzerindeki Banka Uygulama Sayısı',
    'Banka Adet',
  ];
  assert.equal(findBankCountIndex(headers), 3);
});

test('yeni banka başlığı Banka Uyg. Sayısı', () => {
  const headers = [
    'Cihaz Durumu',
    'Satis Kanali',
    'Uygulama Adi',
    'Mukellef Grubu',
    'Cihaz Modeli',
    'Banka Uyg. Sayısı',
    'VAS Uyg Sayisi',
  ];
  assert.equal(findBankCountIndex(headers), 5);
});

test('yeni Ağustos banka dosyası okunur', () => {
  const path = '/Users/selcuk/Downloads/bankaagust.xlsx';
  if (!fs.existsSync(path)) {
    test.skip('bankaagust.xlsx yok');
    return;
  }
  const loaded = loadBankRows(fs.readFileSync(path));
  assert.ok(loaded.rows.length > 1000, `satır ${loaded.rows.length}`);
  const groups = {};
  for (const row of loaded.rows) {
    groups[row.group] = (groups[row.group] || 0) + 1;
  }
  assert.ok((groups.PAX || 0) > 0, 'PAX ayrışmalı');
  assert.ok((groups.YKB || 0) > 0, 'YKB ayrışmalı');
  assert.ok((groups.INGENICO || 0) > 0, 'INGENICO ayrışmalı');
  assert.ok(loaded.rows.some((row) => row.bankCount >= 2));
});
