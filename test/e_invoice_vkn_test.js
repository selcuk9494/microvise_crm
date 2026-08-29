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
  invoiceHasLocalPdfSource,
  resolveLocalOfficialSource,
  shouldRefreshOfficialForArchive,
  canArchiveOfficialPdf,
  isIncomingOfficialInvoice,
  buildOfficialMaliyePortalUrl,
  maliyeErrorMessage,
  nextSerialForBranch,
  isPrimaryBranch,
  applyBranchToSettings,
  resolveSelectedBranch,
  applySelectedBranchAddressToPayload,
} = require('../api/e-invoice').testUtils;
const { buildEInvoiceArchivePdf, resolveArchiveSupplier } = require('../api/_lib/e_invoice_pdf');

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

test('aynı şubedeki hazırlanmış fatura numarasını korur', () => {
  const number = invoiceNumber(
    { seller_vkn: '620009058', seller_branch_code: '1' },
    {
      e_invoice_number: '620009058-2026-1-00000000067',
      invoice_date: '2026-08-29',
      invoice_type: 'sales',
    },
    1,
  );
  assert.equal(number, '620009058-2026-1-00000000067');
});

test('farklı şubede merkez sırasını taşımaz, yeni sıra kullanır', () => {
  const number = invoiceNumber(
    { seller_vkn: '620009058', seller_branch_code: 'ODT' },
    {
      e_invoice_number: '620009058-2026-1-00000000067',
      invoice_date: '2026-08-29',
      invoice_type: 'sales',
    },
    1,
  );
  assert.equal(number, '620009058-2026-ODT-00000000001');
});

test('Maliye fatura no hata mesajını düz metin olarak çıkarır', () => {
  assert.equal(
    maliyeErrorMessage(
      {
        faturaNo: '620009058-2026-1-00000000067',
        hataMesaji:
          'Fatura no formatı doğru değil. Format: VKN-YIL-SUBEKOD-SIRA şeklinde olmalıdır.',
      },
      '',
      'fallback',
    ),
    'Fatura no formatı doğru değil. Format: VKN-YIL-SUBEKOD-SIRA şeklinde olmalıdır.',
  );
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

test('her şube kendi fatura sırasını tutar', () => {
  const hqPrefix = '620009058-2026-1-';
  const odtPrefix = '620009058-2026-ODT-';
  const taken = new Set(['620009058-2026-1-00000000067']);
  assert.equal(
    nextSerialForBranch({ taken, prefix: hqPrefix, floor: 68 }),
    68,
  );
  assert.equal(nextSerialForBranch({ taken, prefix: odtPrefix, floor: 1 }), 1);
  assert.equal(
    nextSerialForBranch({
      taken: new Set(['620009058-2026-ODT-00000000003']),
      prefix: odtPrefix,
      floor: 1,
    }),
    4,
  );
  assert.equal(
    isPrimaryBranch({
      environment: 'test',
      seller_branch_code: 'ODT',
      test_branch_code: '1',
      test_branch_code_2: 'ODT',
    }),
    false,
  );
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
  assert.equal(
    canSendInvoiceToEnvironment(
      { invoice_type: 'purchase', e_invoice_status: 'not_sent' },
      'production',
    ),
    false,
  );
  assert.equal(
    canSendInvoiceToEnvironment(
      { invoice_type: 'sales', e_invoice_status: 'received' },
      'production',
    ),
    false,
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

test('ODT gönderiminde tedarikçi adresi şube 2 adresidir', () => {
  const settings = applyBranchToSettings(
    {
      ...validSettings(),
      environment: 'production',
      seller_address_line2: 'LEFKOŞA',
      prod_branch_code: '1',
      prod_branch_code_2: 'ODT',
      test_branch_address_2: 'ODTU TEKNOPARK KALKANLI',
    },
    resolveSelectedBranch(
      {
        environment: 'production',
        prod_branch_code: '1',
        prod_branch_code_2: 'ODT',
        test_branch_address_2: 'ODTU TEKNOPARK KALKANLI',
      },
      'ODT',
      { required: true },
    ),
  );
  const built = buildPayload({ settings, invoice: validInvoice() });
  built.payload.faturalar[0].tedarikci.adresSatir1 = 'ATATÜRK CAD YENİŞEHİR';
  applySelectedBranchAddressToPayload(settings, built.payload);
  assert.equal(
    built.payload.faturalar[0].tedarikci.adresSatir1,
    'ODTU TEKNOPARK KALKANLI',
  );
  assert.ok(!built.payload.faturalar[0].tedarikci.adresSatir2);
  assert.equal(built.payload.faturalar[0].subeKod, 'ODT');
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

test('KDV dahil kesirli exclusive birim fiyatında satır matrahı toplamı tutarlı', () => {
  // UI: KDV dahil 350/90/130/120/6×1.80 → exclusive 350/1.05 vb. (yuvarlanmadan DB'ye).
  // Yuvarlamadan toplanırsa faturaToplami 655.31 / vergiDahil 700.81;
  // satır satır 2 hane: 655.30 / 700.80 (Maliye beklediği).
  const invoice = {
    ...validInvoice(),
    currency: 'USD',
    exchange_rate: 42.5,
    prices_include_vat: true,
    subtotal: 655.3,
    discount_total: 0,
    tax_total: 45.5,
    grand_total: 700.8,
    items: [
      {
        description: 'PAX A910SF',
        quantity: 1,
        unit: 'Adet',
        unit_price: 350 / 1.05,
        tax_rate: 5,
        tax_amount: 16.67,
        discount_amount: 0,
      },
      {
        description: 'PAX BASE',
        quantity: 1,
        unit: 'Adet',
        unit_price: 90 / 1.05,
        tax_rate: 5,
        tax_amount: 4.29,
        discount_amount: 0,
      },
      {
        description: 'S210 PINPAD',
        quantity: 1,
        unit: 'Adet',
        unit_price: 130 / 1.05,
        tax_rate: 5,
        tax_amount: 6.19,
        discount_amount: 0,
      },
      {
        description: 'GMP3 ENTEGRASYONU 2026 YILI',
        quantity: 1,
        unit: 'Adet',
        unit_price: 120 / 1.16,
        tax_rate: 16,
        tax_amount: 16.55,
        discount_amount: 0,
      },
      {
        description: 'GPRS DATA 2026 YILI (6AY)',
        quantity: 6,
        unit: 'Adet',
        unit_price: 1.8 / 1.2,
        tax_rate: 20,
        tax_amount: 1.8,
        discount_amount: 0,
      },
    ],
  };

  const unroundedSum =
    invoice.items.reduce((sum, item) => sum + item.quantity * item.unit_price, 0);
  assert.ok(Math.abs(unroundedSum - 655.3054187) < 1e-6);
  assert.equal(Math.round(unroundedSum * 100) / 100, 655.31);

  const built = buildPayload({ settings: validSettings(), invoice });
  const sent = built.payload.faturalar[0];
  const lineTaxes = sent.malHizmetler.map((item) => item.vergiler[0].vergiTutari);
  const lineNets = sent.malHizmetler.map((item) =>
    Math.round(item.birimMiktari * item.fiyat * 100) / 100,
  );

  assert.deepEqual(lineNets, [333.33, 85.71, 123.81, 103.45, 9]);
  assert.deepEqual(lineTaxes, [16.67, 4.29, 6.19, 16.55, 1.8]);
  assert.equal(sent.faturaToplami, 655.3);
  assert.equal(sent.kdvToplami, 45.5);
  assert.equal(sent.vergiDahilToplam, 700.8);
  assert.equal(sent.odenecekToplam, 700.8);
  assert.equal(
    sent.faturaToplami,
    Math.round(lineNets.reduce((sum, value) => sum + value, 0) * 100) / 100,
  );
  assert.equal(
    sent.vergiDahilToplam,
    Math.round((sent.faturaToplami - sent.iskontoToplami + sent.kdvToplami) * 100) /
      100,
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

test('kalem açıklaması boşsa ürün adını kopyalamaz (PDF merge)', () => {
  const { mergeLineItems } = require('../api/_lib/e_invoice_pdf');
  const rows = mergeLineItems({
    officialItems: [
      {
        adi: 'PAX A910SF',
        aciklama: 'PAX A910SF',
        birimMiktari: 1,
        birimTurKod: 'C62',
        fiyat: 100,
        vergiler: [{ vergiOrani: 16, vergiTutari: 16 }],
      },
    ],
    payloadItems: [
      {
        adi: 'PAX A910SF',
        aciklama: 'PAX A910SF',
        birimMiktari: 1,
        birimTurKod: 'C62',
        fiyat: 100,
      },
    ],
    localItems: [{ description: 'PAX A910SF', quantity: 1, unit_price: 100 }],
  });
  assert.equal(rows[0].adi, 'PAX A910SF');
  assert.equal(rows[0].aciklama, '');
});

test('kalem açıklaması üründen farklıysa korunur (PDF merge)', () => {
  const { mergeLineItems } = require('../api/_lib/e_invoice_pdf');
  const rows = mergeLineItems({
    officialItems: [
      {
        adi: 'PAX A910SF',
        aciklama: '6 aylık bakım dahil',
        birimMiktari: 1,
        birimTurKod: 'C62',
        fiyat: 100,
        vergiler: [{ vergiOrani: 16, vergiTutari: 16 }],
      },
    ],
    payloadItems: [],
    localItems: [
      {
        description: 'PAX A910SF',
        product_description: '6 aylık bakım dahil',
        quantity: 1,
        unit_price: 100,
      },
    ],
  });
  assert.equal(rows[0].adi, 'PAX A910SF');
  assert.equal(rows[0].aciklama, '6 aylık bakım dahil');
});

test('Maliye payload açıklaması ürün adını tekrar etmez', () => {
  const built = buildPayload({
    settings: validSettings(),
    invoice: {
      ...validInvoice(),
      items: [
        {
          description: 'PAX A910SF',
          quantity: 1,
          unit: 'Adet',
          unit_price: 100,
          tax_rate: 16,
          tax_amount: 16,
          discount_amount: 0,
        },
        {
          description: 'B910 SF',
          product_description: 'İletişim şarj ünitesi',
          quantity: 1,
          unit: 'Adet',
          unit_price: 50,
          tax_rate: 16,
          tax_amount: 8,
          discount_amount: 0,
        },
      ],
    },
  });
  const lines = built.payload.faturalar[0].malHizmetler;
  assert.equal(lines[0].adi, 'PAX A910SF');
  assert.equal(lines[0].aciklama, '');
  assert.equal(lines[1].adi, 'B910 SF');
  assert.equal(lines[1].aciklama, 'İletişim şarj ünitesi');
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

test('PDF tedarikçi adresinde seçilen şube adresini basar', async () => {
  const invoice = validInvoice();
  invoice.e_invoice_number = '620009058-2026-ODT-00000000001';
  invoice.e_invoice_payload = {
    faturalar: [
      {
        subeKod: 'ODT',
        tedarikci: {
          unvan: 'MICROVISE INNOVATION LTD',
          adresSatir1: 'ATATÜRK CAD YENİŞEHİR',
          sehir: 'LEFKOŞA',
          ulke: 'Kuzey Kıbrıs Türk Cumhuriyeti',
          vkn: '620009058',
        },
      },
    ],
  };
  const settings = {
    ...validSettings(),
    environment: 'production',
    prod_branch_code: '1',
    prod_branch_code_2: 'ODT',
    prod_branch_address_2: 'ODTU TEKNOPARK KALKANLI',
  };
  const { supplier } = resolveArchiveSupplier({
    invoice,
    settings,
    officialData: officialDataWithItems([]),
  });
  assert.equal(supplier.adresSatir1, 'ODTU TEKNOPARK KALKANLI');
  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings,
    officialData: officialDataWithItems([]),
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
    environment: 'production',
  });
  assert.equal(pdf.subarray(0, 5).toString(), '%PDF-');
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

test('PDF açma: force/local kaynak varken Maliye yenilemesi istemez', () => {
  const withOfficial = {
    e_invoice_official_data: { faturaNo: 'X' },
    items: [{ description: 'A' }],
  };
  const withPayload = {
    e_invoice_payload: { faturalar: [{ faturaNo: 'Y' }] },
  };
  const crmOnly = { items: [{ description: 'Kalem' }] };

  assert.equal(invoiceHasLocalPdfSource(withOfficial), true);
  assert.equal(invoiceHasLocalPdfSource(withPayload), true);
  assert.equal(invoiceHasLocalPdfSource(crmOnly), true);
  assert.equal(invoiceHasLocalPdfSource({}), false);

  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: withOfficial,
      localOnly: false,
    }),
    false,
  );
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: crmOnly,
      localOnly: true,
    }),
    false,
  );
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: true,
      invoice: withOfficial,
      localOnly: true,
    }),
    true,
  );
  // Gelen alış: kalemsiz resmi özet → Maliye /open detayı yenilenmeli.
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: {
        e_invoice_status: 'received',
        e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
        e_invoice_official_data: { faturaNo: 'ALŞ-1', dogrulamaKodu: 'x' },
      },
      localOnly: true,
    }),
    true,
  );
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: {
        e_invoice_status: 'received',
        e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
        e_invoice_official_data: {
          faturaNo: 'ALŞ-1',
          malHizmetler: [{ adi: 'Hizmet', birimMiktari: 1 }],
        },
      },
      localOnly: true,
    }),
    false,
  );
  assert.equal(
    canArchiveOfficialPdf({
      e_invoice_status: 'received',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
    }),
    false,
  );
  assert.equal(
    canArchiveOfficialPdf({
      e_invoice_status: 'sent',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
    }),
    true,
  );
  assert.equal(
    canArchiveOfficialPdf({ e_invoice_status: 'received', e_invoice_uuid: '' }),
    false,
  );
  assert.equal(
    canArchiveOfficialPdf({
      e_invoice_status: 'not_sent',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
    }),
    false,
  );
  assert.equal(
    canArchiveOfficialPdf({
      invoice_type: 'purchase',
      e_invoice_status: 'prepared',
      e_invoice_uuid: '11111111-1111-1111-1111-111111111111',
    }),
    false,
  );
  assert.equal(
    isIncomingOfficialInvoice({
      invoice_type: 'purchase',
      e_invoice_status: 'received',
    }),
    true,
  );
  assert.equal(
    isIncomingOfficialInvoice({
      invoice_type: 'sales',
      e_invoice_status: 'sent',
    }),
    false,
  );
  assert.match(
    buildOfficialMaliyePortalUrl(
      '11111111-1111-1111-1111-111111111111',
      'test',
    ),
    /^https:\/\/test-efatura\.maliye\.gov\.ct\.tr\/dogrula\/\?code=/,
  );
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: {},
      localOnly: false,
    }),
    true,
  );
  assert.equal(
    shouldRefreshOfficialForArchive({
      refreshOfficial: false,
      invoice: {},
      localOnly: true,
    }),
    false,
  );

  assert.equal(resolveLocalOfficialSource(withPayload).from, 'payload');
  assert.equal(resolveLocalOfficialSource(crmOnly).from, 'crm');
});

test('gönderim payloadundan Maliye oturumu olmadan PDF üretir', async () => {
  const invoice = validInvoice();
  invoice.e_invoice_number = '620009058-2026-1-00000000099';
  invoice.e_invoice_payload = {
    faturalar: [
      {
        faturaNo: invoice.e_invoice_number,
        paraBirimi: 'TRY',
        faturaToplami: 100,
        kdvToplami: 0,
        vergiDahilToplam: 100,
        odenecekToplam: 100,
        malHizmetler: [
          {
            malHizmet: 'Test kalem',
            miktar: 1,
            birimFiyat: 100,
            malHizmetTutari: 100,
            kdvOrani: 0,
            kdvTutari: 0,
          },
        ],
        musteri: { unvan: 'TEST MUSTERI', vkn: '1234567890' },
      },
    ],
  };
  delete invoice.e_invoice_official_data;

  const source = resolveLocalOfficialSource(invoice);
  assert.equal(source.from, 'payload');

  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings: validSettings(),
    officialData: source.officialData,
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
    environment: 'production',
  });
  assert.equal(pdf.subarray(0, 5).toString(), '%PDF-');
  assert.ok(pdf.length > 3000);
});

test('yalnızca CRM kalemlerinden Maliye oturumu olmadan PDF üretir', async () => {
  const invoice = validInvoice();
  invoice.e_invoice_number = '620009058-2026-1-00000000100';
  delete invoice.e_invoice_official_data;
  delete invoice.e_invoice_payload;

  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings: validSettings(),
    officialData: null,
    verificationCode: '019faa9a-a367-74d5-a443-77eb762bca98',
    environment: 'production',
  });
  assert.equal(pdf.subarray(0, 5).toString(), '%PDF-');
  assert.ok(pdf.length > 3000);
});
