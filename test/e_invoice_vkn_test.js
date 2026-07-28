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
  urlsForEnvironment,
} = require('../api/e-invoice').testUtils;

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
