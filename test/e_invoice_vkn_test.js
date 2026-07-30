const assert = require('node:assert/strict');
const test = require('node:test');

const {
  normalizeApiVkn,
  normalizeStoredVkn,
  requireStoredVkn,
  requireApiVkn,
  invoiceNumber,
  createUuidV7,
  validateInvoiceForEInvoice,
  canSendInvoiceToEnvironment,
  buildPayload,
  assertSuccessfulMaliyeResponse,
  validateRegisteredBranch,
  urlsForEnvironment,
  archiveAfterSuccessfulSend,
  officialNumberFromResponse,
  localInvoiceNumber,
  isNumberAlreadyUsedError,
  serialFromNumber,
  invoiceNumberPrefix,
} = require('../api/e-invoice').testUtils;
const { buildEInvoiceArchivePdf } = require('../api/_lib/e_invoice_pdf');

test('10 haneli VKN değerinden yalnızca ilk sıfırı kaldırır', () => {
  assert.equal(normalizeApiVkn('0007033259'), '007033259');
});

test('9 haneli VKN değerini değiştirmez', () => {
  assert.equal(normalizeApiVkn('620009058'), '620009058');
});

test('baştaki gerekli sıfırları korur', () => {
  assert.equal(requireApiVkn('0007033259'), '007033259');
});

test('CRM içinde VKN 10 hane saklanır', () => {
  assert.equal(normalizeStoredVkn('620009058'), '0620009058');
  assert.equal(requireStoredVkn('0007033259'), '0007033259');
  assert.throws(() => requireStoredVkn('7033259'), /10 haneli/);
});

test('test ve canlı ortam URL adreslerini dokümana göre seçer', () => {
  assert.deepEqual(urlsForEnvironment('test'), {
    apiBaseUrl: 'https://test-efatura.maliye.gov.ct.tr/api',
    tokenUrl:
      'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
  });
  assert.deepEqual(urlsForEnvironment('production'), {
    apiBaseUrl: 'https://efatura.maliye.gov.ct.tr/api',
    tokenUrl:
      'https://keycloak.maliye.gov.ct.tr/realms/production/protocol/openid-connect/token',
  });
});

test('ayraçları temizledikten sonra VKN değerini normalize eder', () => {
  assert.equal(normalizeApiVkn('000-703-3259'), '007033259');
});

test('9 haneye dönüşmeyen VKN değerlerini reddeder', () => {
  assert.throws(() => requireApiVkn('7033259'), /10 haneli/);
  assert.throws(() => requireApiVkn('1234567890'), /9 haneli/);
  assert.throws(() => requireApiVkn(''), /10 haneli/);
});

test('fatura numarasında normalize edilmiş 9 haneli VKN kullanır', () => {
  const number = invoiceNumber(
    { seller_vkn: '0007033259', seller_branch_code: 'MERKEZ' },
    { invoice_date: '2026-07-28', invoice_type: 'sales' },
    42,
  );
  assert.equal(number, '007033259-2026-MERKEZ-00000000042');
});

test('önceden hazırlanmış 10 haneli VKN içeren fatura numarasını düzeltir', () => {
  const number = invoiceNumber(
    { seller_vkn: '620009058', seller_branch_code: '1' },
    {
      e_invoice_number: '0007033259-2026-1-00000000001',
      invoice_type: 'sales',
    },
    1,
  );
  assert.equal(number, '007033259-2026-1-00000000001');
});

test('Maliye yanıtından resmi fatura numarasını alır', () => {
  assert.equal(
    officialNumberFromResponse(
      {
        sonuclar: [
          {
            basarili: true,
            faturaNo: '620009058-2026-1-000000000017',
          },
        ],
      },
      'fallback',
    ),
    '620009058-2026-1-000000000017',
  );
  assert.equal(
    officialNumberFromResponse({ sonuclar: [{ basarili: false }] }, 'fallback'),
    'fallback',
  );
});

test('yerel kullanımda resmi fatura numarasından VKN önekini kaldırır', () => {
  assert.equal(
    localInvoiceNumber('620009058-2026-1-00000000010'),
    '2026-1-00000000010',
  );
  assert.equal(localInvoiceNumber('SF03395'), 'SF03395');
});

test('Maliye "zaten kullanılmakta" yanıtını numara çakışması olarak tanır', () => {
  assert.equal(
    isNumberAlreadyUsedError({
      message:
        "Fatura numarası '620009058-2026-1-00000000010' zaten kullanılmakta.",
    }),
    true,
  );
  assert.equal(
    isNumberAlreadyUsedError({
      message: 'Gönderim başarısız.',
      response: {
        sonuclar: [
          {
            basarili: false,
            hataMesaji:
              "Fatura numarası '620009058-2026-1-00000000017' zaten kullanılmakta.",
          },
        ],
      },
    }),
    true,
  );
  assert.equal(
    isNumberAlreadyUsedError({ message: 'Şube kodu geçersiz.' }),
    false,
  );
});

test('fatura numarasından sıra numarasını çözer', () => {
  const settings = { seller_vkn: '620009058', seller_branch_code: '1' };
  const invoice = { invoice_date: '2026-07-28', invoice_type: 'sales' };
  const prefix = invoiceNumberPrefix(settings, invoice);

  assert.equal(prefix, '620009058-2026-1-');
  assert.equal(serialFromNumber('620009058-2026-1-00000000010', prefix), 10);
  assert.equal(serialFromNumber('620009058-2025-1-00000000010', prefix), null);
  assert.equal(serialFromNumber(null, prefix), null);
});

test('doğrulama kodu UUIDv7 üretir', () => {
  const uuid = createUuidV7();
  assert.match(
    uuid,
    /^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/,
  );
});

function validSettings() {
  return {
    seller_vkn: '0620009058',
    seller_title: 'MICROVISE INNOVATION LTD',
    seller_branch_code: 'MERKEZ',
    seller_city: 'LEFKOŞA',
    seller_country_code: 'XCT',
    seller_country: 'Kuzey Kıbrıs Türk Cumhuriyeti',
    seller_address_line1: 'Test adresi',
    next_sales_number: 1,
  };
}

function validInvoice() {
  return {
    invoice_type: 'sales',
    invoice_date: '2026-07-28',
    currency: 'TRY',
    exchange_rate: 1,
    subtotal: 100,
    discount_total: 0,
    tax_total: 20,
    grand_total: 120,
    customer: {
      name: 'Test Müşteri',
      address: 'Müşteri adresi',
      city: 'LEFKOŞA',
      vkn: '0007033259',
    },
    items: [
      {
        description: 'Hizmet',
        quantity: 1,
        unit: 'Adet',
        unit_price: 100,
        tax_rate: 20,
        tax_amount: 20,
        discount_amount: 0,
      },
    ],
  };
}

test('geçerli faturanın zorunlu alan ve toplam kontrolleri geçer', () => {
  assert.deepEqual(
    validateInvoiceForEInvoice(
      validSettings(),
      validInvoice(),
      new Date('2026-07-28T12:00:00+03:00'),
    ),
    [],
  );
});

test('14 günlük faturaya izin verir, 15 günlük faturayı gönderimden önce reddeder', () => {
  const now = new Date('2026-07-28T12:00:00+03:00');
  const fourteenDaysOld = { ...validInvoice(), invoice_date: '2026-07-14' };
  const fifteenDaysOld = { ...validInvoice(), invoice_date: '2026-07-13' };

  assert.deepEqual(
    validateInvoiceForEInvoice(validSettings(), fourteenDaysOld, now),
    [],
  );
  assert.match(
    validateInvoiceForEInvoice(validSettings(), fifteenDaysOld, now).join(' '),
    /15 gün önce.*en fazla 14 günlük/,
  );
});

test('veritabanından Date nesnesi gelen bugünün faturasını kabul eder', () => {
  const invoice = {
    ...validInvoice(),
    invoice_date: new Date('2026-07-28T00:00:00.000Z'),
  };

  assert.deepEqual(
    validateInvoiceForEInvoice(
      validSettings(),
      invoice,
      new Date('2026-07-28T12:00:00+03:00'),
    ),
    [],
  );
});

test('testte gönderilen faturayı yalnızca canlıya göndermeye izin verir', () => {
  const testSent = {
    e_invoice_status: 'sent',
    e_invoice_environment: 'test',
  };
  const productionSent = {
    e_invoice_status: 'sent',
    e_invoice_environment: 'production',
  };

  assert.equal(canSendInvoiceToEnvironment(testSent, 'test'), false);
  assert.equal(canSendInvoiceToEnvironment(testSent, 'production'), true);
  assert.equal(canSendInvoiceToEnvironment(productionSent, 'production'), false);
  assert.equal(
    canSendInvoiceToEnvironment({ e_invoice_status: 'not_sent' }, 'test'),
    true,
  );
});

test('eksik adres, uzun şube ve tutarsız toplamı gönderimden önce yakalar', () => {
  const settings = { ...validSettings(), seller_branch_code: 'ONKARAKTER' };
  const invoice = validInvoice();
  invoice.customer = { ...invoice.customer, address: '' };
  invoice.grand_total = 999;
  const errors = validateInvoiceForEInvoice(
    settings,
    invoice,
    new Date('2026-07-28T12:00:00+03:00'),
  ).join(' ');
  assert.match(errors, /en fazla 9 karakter/);
  assert.match(errors, /Müşteri adresi zorunludur/);
  assert.match(errors, /grand_total tutarsız/);
});

test('özel matrah ve irsaliye alanlarını Maliye payloadına ekler', () => {
  const invoice = validInvoice();
  invoice.irsaliye_no = 'IRS-1';
  invoice.irsaliye_tarihi = '2026-07-28';
  invoice.tax_total = 0;
  invoice.grand_total = 100;
  invoice.items[0] = {
    ...invoice.items[0],
    tax_rate: 0,
    tax_amount: 0,
    special_matrah: true,
  };
  const built = buildPayload({ settings: validSettings(), invoice });
  const sentInvoice = built.payload.faturalar[0];
  assert.equal(sentInvoice.tedarikci.vkn, '620009058');
  assert.equal(sentInvoice.tedarikci.belgeNo, '620009058');
  assert.equal(sentInvoice.tedarikci.belgeTipi, 'VERGI_SICILNO');
  assert.equal(sentInvoice.musteri.vkn, '007033259');
  assert.equal(sentInvoice.irsaliyeNo, 'IRS-1');
  assert.match(sentInvoice.irsaliyeTarihi, /^2026-07-28T/);
  assert.deepEqual(sentInvoice.malHizmetler[0].vergiler[0], {
    vergiKodu: '0002',
    vergiOrani: 0,
    vergiTutari: 0,
    vergiMuafiyetKodu: '101',
    vergiMuafiyetAciklamasi: 'Özel Matrah',
  });
});

test('satır KDV yuvarlaması ile özet toplamını tutarlı üretir', () => {
  // Unrounded per-line KDV sum is 22.452 → stored tax_total 22.45 / grand 448.99,
  // but rounded line taxes are 16.67+4.29+1.50 = 22.46 → grand 449.00.
  const invoice = {
    ...validInvoice(),
    currency: 'USD',
    exchange_rate: 42.5,
    subtotal: 426.54,
    discount_total: 0,
    tax_total: 22.45,
    grand_total: 448.99,
    items: [
      {
        description: 'WORLDLINE A910SF ÖKC',
        quantity: 1,
        unit: 'Adet',
        unit_price: 333.33,
        tax_rate: 5,
        tax_amount: 16.6665,
        discount_amount: 0,
      },
      {
        description: 'B910 SF İLETİŞİM ŞARJ ÜNİTESİ',
        quantity: 1,
        unit: 'Adet',
        unit_price: 85.71,
        tax_rate: 5,
        tax_amount: 4.2855,
        discount_amount: 0,
      },
      {
        description: 'GPRS DATA 2026 YILI (6 AY)',
        quantity: 1,
        unit: 'Adet',
        unit_price: 7.5,
        tax_rate: 20,
        tax_amount: 1.5,
        discount_amount: 0,
      },
    ],
  };

  const built = buildPayload({ settings: validSettings(), invoice });
  const sent = built.payload.faturalar[0];
  const lineTaxes = sent.malHizmetler.map((item) => item.vergiler[0].vergiTutari);

  assert.deepEqual(lineTaxes, [16.67, 4.29, 1.5]);
  assert.equal(sent.faturaToplami, 426.54);
  assert.equal(sent.kdvToplami, 22.46);
  assert.equal(sent.vergiDahilToplam, 449);
  assert.equal(sent.odenecekToplam, 449);
  // USD faturalarda gerçek kur 0,01 TL sapması yarattığı için payload kur=1 gider.
  assert.equal(sent.kur, 1);
  assert.equal(sent.paraBirimi, 'USD');
  assert.equal(
    sent.kdvToplami,
    Math.round(lineTaxes.reduce((sum, value) => sum + value, 0) * 100) / 100,
  );
});

test('Türkiye firmasının 10 haneli VKN değerini yabancı belge olarak korur', () => {
  const invoice = validInvoice();
  invoice.customer = {
    ...invoice.customer,
    country_code: 'TUR',
    country: 'Türkiye',
    vkn: '1234567890',
  };

  const built = buildPayload({ settings: validSettings(), invoice });
  const customer = built.payload.faturalar[0].musteri;

  assert.equal(customer.ulkeKodu, 'TUR');
  assert.equal(customer.ulke, 'Türkiye');
  assert.equal(customer.vkn, undefined);
  assert.equal(customer.belgeNo, '1234567890');
  assert.equal(customer.belgeTipi, 'YABANCI_KIMLIKNO');
});

test('yalnızca banka hesaplarını fatura açıklamasına ekler', () => {
  const settings = {
    ...validSettings(),
    seller_bank_details:
      'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94\nUSD IBAN: TR41 0006 4000 0026 8010 4107 29',
  };
  const invoice = validInvoice();
  invoice.notes = 'WORLDLINE';

  const built = buildPayload({ settings, invoice });

  assert.equal(
    built.payload.faturalar[0].aciklama,
    'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94\nUSD IBAN: TR41 0006 4000 0026 8010 4107 29',
  );
  assert.equal('logo' in built.payload.faturalar[0], false);
  assert.equal('logoUrl' in built.payload.faturalar[0], false);
});

test('PO alanına yazılanı önek eklemeden banka bilgilerinin altına koyar', () => {
  const settings = {
    ...validSettings(),
    seller_bank_details:
      'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94',
  };
  const invoice = validInvoice();
  invoice.po_number = '4500123456';

  const built = buildPayload({ settings, invoice });

  assert.equal(
    built.payload.faturalar[0].aciklama,
    'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94\n4500123456',
  );
});

test('PO numarası boşsa açıklamaya PO satırı eklenmez', () => {
  const settings = {
    ...validSettings(),
    seller_bank_details:
      'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94',
  };
  const invoice = validInvoice();
  invoice.po_number = '   ';

  const built = buildPayload({ settings, invoice });

  assert.equal(
    built.payload.faturalar[0].aciklama,
    'Banka Hesap Bilgileri\nTürkiye İş Bankası\nTL IBAN: TR57 0006 4000 0016 8010 3409 94',
  );
});

test('Maliye kayıt bazında reddettiği faturayı başarılı saymaz', () => {
  assert.throws(
    () =>
      assertSuccessfulMaliyeResponse({
        ozet: { toplamKayit: 1, basariliKayit: 0, basarisizKayit: 1 },
        sonuclar: [
          {
            basarili: false,
            hataMesaji: 'Şube kodu kayıtlı değil.',
          },
        ],
      }),
    /Şube kodu kayıtlı değil/,
  );
  assert.doesNotThrow(() =>
    assertSuccessfulMaliyeResponse({
      ozet: { toplamKayit: 1, basariliKayit: 1, basarisizKayit: 0 },
      sonuclar: [{ basarili: true }],
    }),
  );
});

test('canlı ortamda hatalı şube kodunda kayıtlı kodları yönlendirici hatada gösterir', () => {
  assert.throws(
    () =>
      validateRegisteredBranch(
        { environment: 'production', seller_branch_code: '1' },
        new Set(['MERKEZ', 'KASA1']),
      ),
    /canlı.*1.*KASA1, MERKEZ.*E-Fatura > Ayarlar/s,
  );
});

test('Maliye sisteminde aktif şube yoksa gönderimden önce açıklayıcı hata verir', () => {
  assert.throws(
    () =>
      validateRegisteredBranch(
        { environment: 'production', seller_branch_code: '1' },
        new Set(),
      ),
    /aktif şube bulunamadı.*şube oluşturun/s,
  );
});

test('Maliye arşivinde birim fiyat 0 ise payload/DB fiyatını kullanır', () => {
  const { mergeLineItems } = require('../api/_lib/e_invoice_pdf');
  const rows = mergeLineItems({
    officialItems: [
      {
        adi: 'EKÜ',
        birimMiktari: 2,
        birimTurKod: 'C62',
        fiyat: 0,
        vergiler: [{ vergiOrani: 16, vergiTutari: 30.35 }],
        toplam: 30.35,
      },
    ],
    payloadItems: [
      {
        adi: 'EKÜ',
        birimMiktari: 2,
        birimTurKod: 'C62',
        fiyat: 94.83,
        vergiler: [{ vergiOrani: 16, vergiTutari: 30.35 }],
      },
    ],
    localItems: [
      {
        description: 'EKÜ',
        quantity: 2,
        unit: 'C62',
        unit_price: 94.83,
        tax_rate: 16,
        tax_amount: 30.35,
        line_total: 220.01,
      },
    ],
  });

  assert.equal(rows.length, 1);
  assert.equal(rows[0].fiyat, 94.83);
  assert.equal(rows[0].birimMiktari, 2);
  assert.equal(rows[0].birimTurKod, 'C62');
  assert.ok(Math.abs(rows[0].total - 220.01) < 0.01);
});

function officialDataWithItems(items) {
  return {
    fatura: {
      faturaNo: '620009058-2026-1-00000000001',
      faturaTarihi: '2026-07-28T00:00:00Z',
      paraBirimi: 'TRY',
      tedarikci: {
        unvan: 'MICROVISE INNOVATION LİMİTED',
        adresSatir1: 'ATATÜRK CAD YENİŞEHİR',
        sehir: 'Lefkoşa',
        ulke: 'Kuzey Kıbrıs Türk Cumhuriyeti',
        vkn: '620009058',
        belgeNo: 'MŞ19660',
        belgeTipi: 'VERGI_SICILNO',
      },
      musteri: {
        unvan: 'BÜLENT MAYIN',
        adresSatir1: 'GİRNE',
        sehir: 'Girne',
        ulke: 'Kuzey Kıbrıs Türk Cumhuriyeti',
        belgeNo: '123',
        belgeTipi: 'VKN',
      },
      malHizmetler: items,
      araToplam: 0,
      iskontoToplami: 0,
      kdvToplami: 0,
      genelToplam: 0,
    },
  };
}

test('çok kalemli faturada hiçbir kalem kırpılmaz, sayfaya taşar', async () => {
  const invoice = validInvoice();
  invoice.e_invoice_number = '620009058-2026-1-00000000016';
  const items = Array.from({ length: 30 }, (_, index) => ({
    adi: `KALEM ${index + 1} İLETİŞİM ŞARJ ÜNİTESİ`,
    aciklama: `KALEM ${index + 1} AÇIKLAMA MÜŞTERİ SATIŞ`,
    birimMiktari: 1,
    birimTurKod: 'C62',
    fiyat: 85.71,
    vergiler: [{ vergiOrani: 5, vergiTutari: 4.29 }],
  }));

  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings: validSettings(),
    officialData: officialDataWithItems(items),
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
    environment: 'production',
  });

  const asLatin = pdf.toString('latin1');
  const pageCount = (asLatin.match(/\/Type\s*\/Page\b/g) || []).length;
  assert.ok(pageCount > 1, 'kalemler sığmadığında yeni sayfa açılmalı');
  assert.equal(
    /kalem UBL\/XML/.test(asLatin),
    false,
    'kalemler kırpıldığına dair not bulunmamalı',
  );
});

test('Maliye arşiv verisinden Türkçe karakterli tek sayfa A4 PDF üretir', async () => {
  const invoice = validInvoice();
  invoice.e_invoice_number = '620009058-2026-1-00000000001';
  invoice.customer.name = 'BÜLENT MAYIN';

  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings: validSettings(),
    officialData: officialDataWithItems([]),
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
    environment: 'production',
  });

  assert.equal(pdf.subarray(0, 5).toString(), '%PDF-');
  assert.ok(pdf.length > 5000);
  const asLatin = pdf.toString('latin1');
  assert.equal((asLatin.match(/\/Type\s*\/Page\b/g) || []).length, 1);
  // Helvetica/WinAnsi Türkçe'yi bozar; gömülü TTF (Noto/Inter) zorunlu.
  assert.equal(/\/BaseFont\s*\/Helvetica\b/.test(asLatin), false);
  assert.ok(
    /NotoSans|Inter/.test(asLatin),
    'PDF içinde NotoSans veya Inter fontu gömülü olmalı',
  );
});

test('test ortamında gönderim sonrası otomatik PDF arşivini atlar', async () => {
  const result = await archiveAfterSuccessfulSend({
    invoiceId: '00000000-0000-7000-8000-000000000001',
    settings: { environment: 'test' },
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
  });
  assert.equal(result.skipped, true);
  assert.equal(result.reason, 'test_environment');
  assert.equal(result.archived, false);
});
