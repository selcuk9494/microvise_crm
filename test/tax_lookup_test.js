'use strict';

const test = require('node:test');
const assert = require('node:assert/strict');
const {
  lookupTaxpayer,
  normalizeLookupQuery,
  hasLetters,
  cleanLocationLabel,
  extractCityFromAddressPayload,
  ASSOS_LOGIN_URL,
  DISPATCH_URL,
  CMD_BY_KIMLIK,
  CMD_BY_VKN,
  CMD_ADDRESS,
} = require('../api/_lib/tax-lookup');

function mockFetch(handlers) {
  return async (url, options = {}) => {
    const href = String(url);
    const method = (options.method || 'GET').toUpperCase();
    const body = options.body || '';
    const match = handlers.find((item) => item.match(href, method, body));
    if (!match) {
      throw new Error(`Beklenmeyen istek: ${method} ${href} ${body}`);
    }
    const payload = typeof match.response === 'function' ? match.response(href, method, body) : match.response;
    return {
      ok: payload.ok !== false,
      status: payload.status || (payload.ok === false ? 500 : 200),
      async text() {
        return typeof payload.body === 'string' ? payload.body : JSON.stringify(payload.body);
      },
      async json() {
        return typeof payload.body === 'string' ? JSON.parse(payload.body) : payload.body;
      },
    };
  };
}

test('kimlik no ile mükellef adını ve VKN’yi doldurur (mock upstream)', async () => {
  const calls = [];
  const fetchImpl = mockFetch([
    {
      match: (url) => url === ASSOS_LOGIN_URL,
      response: { body: { token: 'guest-token-abc', redirectUrl: 'index.jsp' } },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL || method !== 'POST') return false;
        const params = new URLSearchParams(body);
        if (params.get('cmd') !== CMD_BY_VKN) return false;
        calls.push(params.get('cmd'));
        return true;
      },
      response: {
        body: {
          error: '1',
          messages: ['Girdiğiniz 987654321 Vergi Numarasi geçerli değildir.'],
        },
      },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL || method !== 'POST') return false;
        const params = new URLSearchParams(body);
        calls.push(params.get('cmd'));
        return params.get('cmd') === CMD_BY_KIMLIK && params.get('token') === 'guest-token-abc';
      },
      response: {
        body: {
          data: {
            kimlik: {
              vergiNo: '123456789',
              mukellefNo: '987654321',
              unvan: 'ÖRNEK TİCARET LTD',
              mukellefDurum: 1,
              sirketTuru: 2,
            },
          },
          metadata: { optime: '20260805000000+0300' },
        },
      },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL || method !== 'POST') return false;
        const params = new URLSearchParams(body);
        calls.push(params.get('cmd'));
        return params.get('cmd') === CMD_ADDRESS;
      },
      response: {
        body: {
          data: {
            sonuc: {
              adres: {
                acikAdres: 'Örnek Mah. Test Sk. No:1 Lefkoşa BEL. / LEFKOŞA',
                bucakKasaba: 'LEFKOŞA BEL.',
              },
            },
          },
        },
      },
    },
  ]);

  const result = await lookupTaxpayer('987654321', { fetch: fetchImpl });
  assert.equal(result.name, 'ÖRNEK TİCARET LTD');
  assert.equal(result.vkn, '123456789');
  assert.equal(result.kimlikNo, '987654321');
  assert.equal(result.source, 'kimlik');
  assert.equal(result.address, 'Örnek Mah. Test Sk. No:1 Lefkoşa BEL. / LEFKOŞA');
  assert.equal(result.city, 'LEFKOŞA');
  assert.equal(result.taxOffice, 'LEFKOŞA');
  assert.ok(calls.includes(CMD_BY_VKN));
  assert.ok(calls.includes(CMD_BY_KIMLIK));
  assert.ok(calls.includes(CMD_ADDRESS));
});

test('VKN ile sorguda unvan ve kimlik no döner (mock upstream)', async () => {
  const fetchImpl = mockFetch([
    {
      match: (url) => url === ASSOS_LOGIN_URL,
      response: { body: { token: 'guest-token-vkn' } },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL) return false;
        const params = new URLSearchParams(body);
        return params.get('cmd') === CMD_BY_VKN;
      },
      response: {
        body: {
          data: {
            kimlik: {
              vergiNo: '112233445',
              mukellefNo: '556677889',
              unvan: 'DENEME A.Ş.',
            },
          },
        },
      },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL) return false;
        return new URLSearchParams(body).get('cmd') === CMD_ADDRESS;
      },
      response: {
        body: { error: '1', messages: ['Adres bulunamadı'] },
      },
    },
  ]);

  const result = await lookupTaxpayer('112233445', { fetch: fetchImpl });
  assert.equal(result.name, 'DENEME A.Ş.');
  assert.equal(result.vkn, '112233445');
  assert.equal(result.kimlikNo, '556677889');
  assert.equal(result.source, 'vkn');
  assert.equal(result.address, undefined);
});

test('portal hata mesajını kullanıcıya iletir (mock upstream)', async () => {
  const fetchImpl = mockFetch([
    {
      match: (url) => url === ASSOS_LOGIN_URL,
      response: { body: { token: 'guest-token-err' } },
    },
    {
      match: (url) => url === DISPATCH_URL,
      response: {
        body: {
          error: '1',
          messages: ['Girdiğiniz 999999991 mükellef numarasina ait mükellef bulunamadı.'],
        },
      },
    },
  ]);

  await assert.rejects(
    () => lookupTaxpayer('999999991', { fetch: fetchImpl, includeAddress: false }),
    /mükellef bulunamadı/i,
  );
});

test('normalizeLookupQuery harfli mükellef noyu korur ve büyük harfe çevirir', () => {
  assert.equal(normalizeLookupQuery('mş19660'), 'MŞ19660');
  assert.equal(normalizeLookupQuery('  MŞ19660  '), 'MŞ19660');
  assert.equal(normalizeLookupQuery('987654321'), '987654321');
  assert.equal(hasLetters('MŞ19660'), true);
  assert.equal(hasLetters('987654321'), false);
});

test('harfle başlayan mükellef no (MŞ19660) kimlik komutuna gider (mock upstream)', async () => {
  const calls = [];
  let jpSent = null;
  const fetchImpl = mockFetch([
    {
      match: (url) => url === ASSOS_LOGIN_URL,
      response: { body: { token: 'guest-token-letter' } },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL || method !== 'POST') return false;
        const params = new URLSearchParams(body);
        const cmd = params.get('cmd');
        calls.push(cmd);
        if (cmd !== CMD_BY_KIMLIK) return false;
        jpSent = JSON.parse(params.get('jp') || '{}');
        return params.get('token') === 'guest-token-letter';
      },
      response: {
        body: {
          data: {
            kimlik: {
              vergiNo: '700123456',
              mukellefNo: 'MŞ19660',
              unvan: 'HARFLİ MÜKELLEF LTD',
            },
          },
        },
      },
    },
    {
      match: (url, method, body) => {
        if (url !== DISPATCH_URL) return false;
        return new URLSearchParams(body).get('cmd') === CMD_ADDRESS;
      },
      response: {
        body: { data: { sonuc: { adres: { acikAdres: 'Girne Cad. No:5' } } } },
      },
    },
  ]);

  const result = await lookupTaxpayer('mş19660', { fetch: fetchImpl });
  assert.equal(result.name, 'HARFLİ MÜKELLEF LTD');
  assert.equal(result.vkn, '700123456');
  assert.equal(result.kimlikNo, 'MŞ19660');
  assert.equal(result.source, 'kimlik');
  assert.equal(result.address, 'Girne Cad. No:5');
  assert.equal(result.city, undefined);
  assert.equal(result.taxOffice, undefined);
  assert.deepEqual(jpSent, { mukellefNo: 'MŞ19660', MUKERREROLSADASORGULA: 0 });
  assert.equal(calls[0], CMD_BY_KIMLIK);
  assert.ok(!calls.includes(CMD_BY_VKN));
});

test('harfli sorguda kimlik tutmazsa vergiNo yolunu dener (mock upstream)', async () => {
  const calls = [];
  const fetchImpl = mockFetch([
    {
      match: (url) => url === ASSOS_LOGIN_URL,
      response: { body: { token: 'guest-token-letter-fb' } },
    },
    {
      match: (url) => url === DISPATCH_URL,
      response: (url, method, body) => {
        const params = new URLSearchParams(body);
        const cmd = params.get('cmd');
        calls.push(cmd);
        if (cmd === CMD_BY_KIMLIK) {
          return {
            body: {
              error: '1',
              messages: ['Girdiğiniz MŞ19660 mükellef numarasina ait mükellef bulunamadı.'],
            },
          };
        }
        if (cmd === CMD_BY_VKN) {
          return {
            body: {
              data: {
                kimlik: {
                  vergiNo: 'MŞ19660',
                  mukellefNo: '112233445',
                  unvan: 'VKN FALLBACK A.Ş.',
                },
              },
            },
          };
        }
        return { ok: false, status: 500, body: { error: 'unexpected' } };
      },
    },
  ]);

  const result = await lookupTaxpayer('MŞ19660', { fetch: fetchImpl, includeAddress: false });
  assert.equal(result.name, 'VKN FALLBACK A.Ş.');
  assert.equal(result.vkn, 'MŞ19660');
  assert.equal(result.source, 'vkn');
  assert.deepEqual(calls, [CMD_BY_KIMLIK, CMD_BY_VKN]);
});

test('geçersiz kısa sorguyu reddeder', async () => {
  await assert.rejects(
    () => lookupTaxpayer('MS12', { fetch: async () => { throw new Error('network'); } }),
    /5–11 karakter/i,
  );
});

test('adres payloadundan şehir ve vergi dairesi çıkarılır', () => {
  assert.equal(cleanLocationLabel('LEFKOŞA BEL.'), 'LEFKOŞA');
  assert.equal(
    extractCityFromAddressPayload({
      acikAdres: 'ATATÜRK CAD … LEFKOŞA BEL. / LEFKOŞA',
      bucakKasaba: 'LEFKOŞA BEL.',
    }),
    'LEFKOŞA',
  );
  assert.equal(
    extractCityFromAddressPayload({ bucakKasaba: 'GİRNE BEL.' }),
    'GİRNE',
  );
});
