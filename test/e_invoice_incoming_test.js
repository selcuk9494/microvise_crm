const test = require('node:test');
const assert = require('node:assert/strict');
const { testUtils } = require('../api/e-invoice');

test('mapIncomingLines Maliye kalemlerini CRM satırına çevirir', () => {
  const items = testUtils.mapIncomingLines({
    malHizmetler: [
      {
        adi: 'Danışmanlık',
        birimMiktari: 1,
        birimFiyat: 100,
        birimTur: 'Adet',
        malHizmetTutari: 100,
        toplamVergi: 20,
        vergiyeEsasTutar: 100,
        vergiler: [{ oran: 20 }],
      },
    ],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].description, 'Danışmanlık');
  assert.equal(items[0].unit_price, 100);
  assert.equal(items[0].tax_rate, 20);
  assert.equal(items[0].tax_amount, 20);
});

test('mapIncomingLines ODTÜ tarzı iki kalemi ve vergiOrani alanını okur', () => {
  const items = testUtils.mapIncomingLines({
    aciklama: 'Türkiye İş Bankası\nODTÜ-KKTC Şubesi\nTR84 0006 4000 0016 8220 0634 32',
    kdvToplami: 160.84,
    faturaToplami: 6820.51,
    odenecekToplam: 6981.35,
    malHizmetler: [
      {
        adi: 'Kira',
        birimMiktari: 1,
        birimFiyat: 5815.26,
        birimTur: 'ADET(UNIT)',
        malHizmetTutari: 5815.26,
        toplamVergi: 0,
        vergiyeEsasTutar: 5815.26,
        vergiler: [{ vergiKodu: '0002', vergiOrani: 0, vergiTutari: 0 }],
      },
      {
        adi: 'İşletme Gideri Bedeli',
        birimMiktari: 1,
        birimFiyat: 1005.25,
        birimTur: 'ADET(UNIT)',
        malHizmetTutari: 1005.25,
        toplamVergi: 160.84,
        vergiyeEsasTutar: 1005.25,
        vergiler: [{ vergiKodu: '0002', vergiOrani: 16, vergiTutari: 160.84 }],
      },
    ],
  });
  assert.equal(items.length, 2);
  assert.equal(items[0].description, 'Kira');
  assert.equal(items[0].unit_price, 5815.26);
  assert.equal(items[0].tax_rate, 0);
  assert.equal(items[0].tax_amount, 0);
  assert.equal(items[0].unit, 'Adet');
  assert.equal(items[1].description, 'İşletme Gideri Bedeli');
  assert.equal(items[1].unit_price, 1005.25);
  assert.equal(items[1].tax_rate, 16);
  assert.equal(items[1].tax_amount, 160.84);
  assert.equal(items[1].line_total, 1166.09);
  // Açıklama / IBAN ürün satırı olmamalı
  assert.ok(!items.some((item) => /Bankası|IBAN|TR84/i.test(item.description)));
});

test('mapIncomingLines kalemsizken aciklama/IBAN ürün satırına yazılmaz', () => {
  const items = testUtils.mapIncomingLines({
    aciklama: 'Türkiye İş Bankası\nTR84 0006 4000 0016 8220 0634 32',
    faturaNo: '647002673-2026-WEB-00000000006',
    faturaToplami: 6820.51,
    kdvToplami: 160.84,
    odenecekToplam: 6981.35,
    malHizmetler: [],
  });
  assert.equal(items.length, 1);
  assert.equal(items[0].description, 'Gelen e-fatura');
  assert.equal(items[0].unit_price, 6820.51);
  // Karışık oran yuvarlanır (2.36 → 0), resmi oranlar kalemlerden gelmeli
  assert.ok(testUtils.looksLikePaymentOrBankNote('Türkiye İş Bankası TR84 0006'));
  assert.ok([0, 5, 10, 16, 20].includes(items[0].tax_rate));
});

test('asIncomingArray sayfalı yanıtı çözer', () => {
  assert.deepEqual(testUtils.asIncomingArray({ data: [{ a: 1 }], toplamSayfa: 2 }), [{ a: 1 }]);
});
