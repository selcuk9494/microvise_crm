'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const XLSX = require('xlsx');
const {
  parseTsmLogRows,
  parseTsmLogBuffer,
  parseTsmLogRequestBody,
  extractTermSeriNos,
  classifyTsmOrderKind,
  normalizeTsmResultMessage,
} = require('../api/_lib/tsm_log');

test('onaylanan ve eslesmeyen TermSeriNo degerlerini cikarir', () => {
  const result = parseTsmLogRows([
    ['İşlem', 'Sonuç Mesajı'],
    ['TERMINAL_SORGU', 'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>'],
    [
      'ISEMRI_ACMA',
      'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>2D10041612</TermSeriNo>',
    ],
    ['BASKA_ISLEM', 'İŞLEM ONAYLANDI <TermSeriNo>2D10041613</TermSeriNo>'],
  ]);
  assert.equal(result.error, null);
  assert.deepEqual(
    result.uniqueSerials.map((item) => item.serialNumber),
    ['2D10041611', '2D10041612'],
  );
});

test('yalnizca 2 ile baslayan terminal numaralarini alir', () => {
  assert.deepEqual(
    extractTermSeriNos('İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>'),
    ['2D10041611'],
  );
  assert.deepEqual(
    extractTermSeriNos('İŞLEM ONAYLANDI <TermSeriNo>1A10041611</TermSeriNo>'),
    [],
  );
});

test('giris parametreleri kolonundaki TermSeriNo degerini okur', () => {
  const result = parseTsmLogRows([
    ['İşlem', 'Sonuç Mesajı', 'Giriş Parametreleri'],
    [
      'TERMINAL_SORGU',
      'İŞLEM ONAYLANDI',
      '<BKM_TerminalInquiryIn><TermSeriNo>2D10041611</TermSeriNo></BKM_TerminalInquiryIn>',
    ],
    [
      'ISEMRI_ACMA',
      'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ.',
      '<BKM_OpenTaskIn><TermSeriNo>2D10049472</TermSeriNo></BKM_OpenTaskIn>',
    ],
  ]);
  assert.deepEqual(
    result.uniqueSerials.map((item) => item.serialNumber),
    ['2D10041611', '2D10049472'],
  );
});

test('isemri acma onay xmlinden banka ve kurulum tipini okur', () => {
  const xml = [
    '<BKM_OpenTaskIn>',
    '<IsEmriKodu>K</IsEmriKodu>',
    '<Aciklama>TechPos Acquirer WS Tarafından Gönderilen Kurulum Emridir</Aciklama>',
    '<AcquirerEkranAdi>HALKBANK</AcquirerEkranAdi>',
    '<AcquirerId>12</AcquirerId>',
    '<TermId>02844878</TermId>',
    '<TermSeriNo>2D10041482</TermSeriNo>',
    '<IsyeriAdi>ATLILAR ELEKTRONIK</IsyeriAdi>',
    '<KurumToken>SECRET-TOKEN</KurumToken>',
    '</BKM_OpenTaskIn>',
  ].join('');
  const result = parseTsmLogRows([
    ['İşlem', 'Sonuç Mesajı', 'Giriş Parametreleri'],
    ['ISEMRI_ACMA', 'İŞLEM ONAYLANDI', xml],
  ]);
  const order = result.uniqueSerials[0].workOrder;
  assert.equal(result.uniqueSerials[0].serialNumber, '2D10041482');
  assert.equal(order.bankName, 'HALKBANK');
  assert.equal(order.acquirerId, '12');
  assert.equal(order.terminalId, '02844878');
  assert.equal(order.merchantName, 'ATLILAR ELEKTRONIK');
  assert.equal(order.orderKind, 'kurulum');
  assert.equal(JSON.stringify(order).includes('SECRET-TOKEN'), false);
  assert.equal(Object.hasOwn(order, 'kurumToken'), false);
});

test('silme aciklamasini geri alim olarak siniflar', () => {
  assert.equal(
    classifyTsmOrderKind('TS', 'Terminal Silme Bildirimidir'),
    'geriAlim',
  );
  assert.equal(
    classifyTsmOrderKind(
      'TE',
      'TechPos Acquirer WS Tarafından Gönderilen Terminal Ekleme Bildirimidir',
    ),
    'ekleme',
  );
});

test('xlsx bufferdan sicil numarasi okur', () => {
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.aoa_to_sheet([
    ['İşlem', 'Sonuç Mesajı'],
    ['TERMINAL_SORGU', 'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>'],
  ]);
  XLSX.utils.book_append_sheet(workbook, sheet, 'Log');
  const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xlsx' });
  const result = parseTsmLogBuffer(buffer, 'tsm.xlsx');
  assert.equal(result.uniqueSerials[0].serialNumber, '2D10041611');
});

test('eklenme tarihi kolonundan occurredAt okur', () => {
  const result = parseTsmLogRows([
    ['Eklenme Tarihi', 'Ekleme Saati', 'İşlem', 'Sonuç Mesajı'],
    [
      '2026-06-05',
      '17:04:33',
      'TERMINAL_SORGU',
      'İŞLEM ONAYLANDI <TermSeriNo>2D10041611</TermSeriNo>',
    ],
  ]);
  assert.equal(result.uniqueSerials[0].serialNumber, '2D10041611');
  assert.ok(result.uniqueSerials[0].occurredAt);
  const occurred = new Date(result.uniqueSerials[0].occurredAt);
  assert.equal(occurred.getFullYear(), 2026);
  assert.equal(occurred.getMonth(), 5);
  assert.equal(occurred.getDate(), 5);
  assert.equal(occurred.getHours(), 17);
  assert.equal(occurred.getMinutes(), 4);
});

test('xls bufferdan sicil numarasi okur', () => {
  const workbook = XLSX.utils.book_new();
  const sheet = XLSX.utils.aoa_to_sheet([
    ['İşlem', 'Sonuç Mesajı'],
    [
      'ISEMRI_ACMA',
      'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ. <TermSeriNo>2D10041612</TermSeriNo>',
    ],
  ]);
  XLSX.utils.book_append_sheet(workbook, sheet, 'Log');
  const buffer = XLSX.write(workbook, { type: 'buffer', bookType: 'xls' });
  const result = parseTsmLogBuffer(buffer, 'tsm.xls');
  assert.equal(result.uniqueSerials[0].serialNumber, '2D10041612');
  assert.deepEqual(result.uniqueSerials[0].resultKinds, ['serialMismatch']);
});

test('ana islem sonuc mesaji alt seceneklerini cikarir', () => {
  const result = parseTsmLogRows([
    ['İşlem', 'Sonuç Mesajı'],
    ['TERMINAL_SORGU', 'Acquirera ait Lisans Yok <TermSeriNo>2D10041002</TermSeriNo>'],
    ['TERMINAL_SORGU', 'İŞLEM ONAYLANDI <TermSeriNo>2D10041001</TermSeriNo>'],
  ]);
  assert.equal(normalizeTsmResultMessage('İŞLEM ONAYLANDI <TermSeriNo>2D</TermSeriNo>'), 'İŞLEM ONAYLANDI');
  const messages = result.uniqueSerials.flatMap((item) => item.resultMessages);
  assert.ok(messages.includes('Acquirera ait Lisans Yok'));
  assert.ok(messages.includes('İŞLEM ONAYLANDI'));
});

test('parseTsmLogRequestBody dosya yoksa 400 doner', () => {
  assert.throws(
    () => parseTsmLogRequestBody({}),
    (error) => error.statusCode === 400 && /Excel dosyası gerekli/.test(error.message),
  );
});
