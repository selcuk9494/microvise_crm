'use strict';

/**
 * KKTC İnternet Vergi Dairesi (online.vergi.gov.ct.tr) Belge Doğrulama
 * mükellef sorgusu — resmi SPA XHR’larının sunucu tarafı vekili.
 *
 * Oturum: assoscmd=cfsession (şifresiz / captcha’sız misafir token).
 * Kimlik / mükellef no → gvdos_ivd_mukellef_numarasindan_mukellef_sorgula
 *   (rakam veya harfle başlayan örn. MŞ19660)
 * VKN                → gvdos_ivd_vergi_numarasindanthk_mukellef_sorgula
 * Adres              → gvdos_ivd_vergi_numarasindan_sonGecerliAdresi_sorgula (isteğe bağlı)
 *
 * Kısıtlar: Portal API’si veya cfsession değişirse kırılabilir; captcha’lı
 * tam giriş gerekirse bu proxy çalışmaz. Canlı portala CI’da istek atılmaz.
 */

const PORTAL_ORIGIN = 'https://online.vergi.gov.ct.tr';
const ASSOS_LOGIN_URL = `${PORTAL_ORIGIN}/gvdos_online-vergi_server/assos-login/`;
const DISPATCH_URL = `${PORTAL_ORIGIN}/gvdos_online-vergi_server/dispatch`;
const PAGE_NAME = 'P_INTVRG_TAHSILAT_DOGRULAMA_GORUNTULEME';
const CMD_BY_KIMLIK = 'gvdos_ivd_mukellef_numarasindan_mukellef_sorgula';
const CMD_BY_VKN = 'gvdos_ivd_vergi_numarasindanthk_mukellef_sorgula';
const CMD_ADDRESS = 'gvdos_ivd_vergi_numarasindan_sonGecerliAdresi_sorgula';

/** Sadece rakam çıkarır (adres/VKN yardımcıları için). */
function digits(value) {
  return String(value || '').replace(/\D/g, '');
}

/**
 * Portal sorgusu için kimlik/VKN normalizasyonu:
 * boşluk/ayraç temizlenir, harf+rakam tutulur, tr-TR büyük harfe çevrilir.
 */
function normalizeLookupQuery(query) {
  const raw = String(query || '')
    .trim()
    .replace(/[\s\-_.]/g, '');
  if (!raw) return '';
  const cleaned = raw.replace(/[^0-9A-Za-zÇĞİÖŞÜçğıöşü]/g, '');
  return cleaned.toLocaleUpperCase('tr-TR');
}

function hasLetters(value) {
  return /[A-ZÇĞİÖŞÜ]/i.test(String(value || ''));
}

function stripHtml(text) {
  return String(text || '')
    .replace(/<br\s*\/?>/gi, '\n')
    .replace(/<[^>]+>/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function portalMessages(payload) {
  const messages = payload?.messages;
  if (!Array.isArray(messages) || !messages.length) return '';
  return messages
    .map((item) => stripHtml(typeof item === 'string' ? item : item?.text || ''))
    .filter(Boolean)
    .join(' ');
}

/**
 * KKTC vergi no genelde 9 hane (bazen 8–11). MŞ rakam kırıntısı (örn. 19715)
 * VKN sayılmaz.
 */
function isValidVknDigits(value) {
  const d = digits(value);
  return d.length >= 8 && d.length <= 11;
}

function mapKimlik(kimlik = {}, { source } = {}) {
  // VKN yalnızca rakam; MŞ/kimlik harf+rakam kalabilir.
  const vknDigits = digits(kimlik.vergiNo || kimlik.vergiNumarasi || kimlik.vkn);
  const vkn = isValidVknDigits(vknDigits) ? vknDigits.slice(0, 11) : '';
  const kimlikNo = normalizeLookupQuery(kimlik.mukellefNo || kimlik.kimlikNo);
  const name = String(kimlik.unvan || kimlik.unvanAdi || '').trim();
  if (!name && !vkn && !kimlikNo) return null;
  return {
    name,
    vkn,
    kimlikNo,
    source: source || '',
    mukellefDurum: kimlik.mukellefDurum,
    sirketTuru: kimlik.sirketTuru,
  };
}

async function createGuestSession(fetchImpl = fetch) {
  const body = new URLSearchParams({
    assoscmd: 'cfsession',
    rtype: 'json',
    fskey: 'intvrg.fix.session',
    fuserid: 'INTVRG_FIX',
  });
  let response;
  try {
    response = await fetchImpl(ASSOS_LOGIN_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' },
      body: body.toString(),
    });
  } catch (error) {
    throw new Error(`Vergi dairesi oturumu açılamadı (ağ hatası): ${error.message || error}`);
  }
  const text = await response.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new Error('Vergi dairesi oturum yanıtı okunamadı. Portal geçici olarak kullanılamıyor olabilir.');
  }
  if (!response.ok || payload.error || !payload.token) {
    throw new Error(portalMessages(payload) || 'Vergi dairesi şifresiz oturumu alınamadı (captcha / erişim değişmiş olabilir).');
  }
  return String(payload.token);
}

async function dispatchService(token, cmd, jp, fetchImpl = fetch) {
  const body = new URLSearchParams({
    cmd,
    callid: `H${Date.now().toString(36)}`,
    pageName: PAGE_NAME,
    module: 'ivd',
    token: String(token),
    jp: JSON.stringify(jp || {}),
  });
  let response;
  try {
    response = await fetchImpl(DISPATCH_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded;charset=utf-8' },
      body: body.toString(),
    });
  } catch (error) {
    throw new Error(`Vergi dairesi sorgusu başarısız (ağ hatası): ${error.message || error}`);
  }
  const text = await response.text();
  let payload;
  try {
    payload = JSON.parse(text);
  } catch {
    throw new Error('Vergi dairesi yanıtı okunamadı.');
  }
  if (!response.ok) {
    throw new Error(portalMessages(payload) || `Vergi dairesi HTTP ${response.status} döndü.`);
  }
  if (payload.error && String(payload.error) !== '0') {
    const msg = portalMessages(payload) || 'Mükellef bulunamadı.';
    const err = new Error(msg);
    err.code = 'PORTAL_LOOKUP';
    err.portalPayload = payload;
    throw err;
  }
  return payload.data && typeof payload.data === 'object' ? payload.data : payload;
}

async function lookupByKimlik(token, kimlikNo, fetchImpl) {
  const data = await dispatchService(token, CMD_BY_KIMLIK, {
    mukellefNo: kimlikNo,
    MUKERREROLSADASORGULA: 0,
  }, fetchImpl);
  return mapKimlik(data.kimlik, { source: 'kimlik' });
}

async function lookupByVkn(token, vkn, fetchImpl) {
  const data = await dispatchService(token, CMD_BY_VKN, {
    vergiNo: vkn,
    MUKERREROLSADASORGULA: 0,
  }, fetchImpl);
  return mapKimlik(data.kimlik, { source: 'vkn' });
}

/** "LEFKOŞA BEL." / "Gazimağusa Bel" → sade il adı. */
function cleanLocationLabel(value) {
  return String(value || '')
    .replace(/\s+BEL\.?\s*$/i, '')
    .replace(/\s+/g, ' ')
    .trim();
}

/**
 * Adres payload’ından şehir adını çıkarır.
 * Örn. acikAdres "… / LEFKOŞA" veya bucakKasaba "LEFKOŞA BEL.".
 */
function extractCityFromAddressPayload(adres = {}) {
  const acik = String(adres.acikAdres || '').trim();
  if (acik.includes('/')) {
    const fromSlash = cleanLocationLabel(acik.split('/').pop());
    if (fromSlash) return fromSlash;
  }
  const bucak = cleanLocationLabel(adres.bucakKasaba);
  if (bucak) return bucak;
  const ilce = cleanLocationLabel(adres.ilceAdi || adres.ilAdi || adres.sehir);
  return ilce || '';
}

/**
 * Vergi dairesi adı/kodu — yoksa KKTC’de şehir ile aynı listelenir.
 */
function extractTaxOfficeFromPayload(data = {}, city = '') {
  const adres = data?.sonuc?.adres || data?.adres || {};
  const kimlik = data?.sonuc?.kimlik || data?.kimlik || {};
  const mukellefiyet = data?.mukellefiyetBilgi || {};
  const candidates = [
    adres.vergiDairesiAdi,
    adres.vdAdi,
    adres.vergiDairesi,
    kimlik.vergiDairesiAdi,
    kimlik.vdAdi,
    mukellefiyet.vergiDairesiAdi,
    mukellefiyet.vdAdi,
    data.vergiDairesiAdi,
    data.vdAdi,
  ];
  for (const raw of candidates) {
    const label = cleanLocationLabel(raw);
    if (label) return label;
  }
  const vdKod = adres.vdKod || kimlik.vdKod || mukellefiyet.vdKod || data.vdKod;
  if (vdKod != null && String(vdKod).trim() && String(vdKod).trim() !== '0') {
    return String(vdKod).trim();
  }
  // KKTC’de vergi daireleri şehir adlarıyla eşleşir (e-fatura listesi).
  return city || '';
}

async function lookupAddress(token, vkn, fetchImpl) {
  try {
    const data = await dispatchService(token, CMD_ADDRESS, {
      vergiNo: vkn,
      DS_AKOSADRESGETIR: 1,
    }, fetchImpl);
    const adres = data?.sonuc?.adres || data?.adres || {};
    const raw = adres.acikAdres || '';
    const address = String(raw).replace(/^Adres:\s*/i, '').trim();
    const city = extractCityFromAddressPayload(adres);
    const taxOffice = extractTaxOfficeFromPayload(data, city);
    return {
      address: address || '',
      city: city || '',
      taxOffice: taxOffice || '',
    };
  } catch {
    return { address: '', city: '', taxOffice: '' };
  }
}

/**
 * @param {string} query Kimlik no, mükellef no (örn. MŞ19660) veya VKN
 * @param {{ fetch?: typeof fetch, includeAddress?: boolean }} [options]
 */
async function lookupTaxpayer(query, options = {}) {
  const fetchImpl = options.fetch || fetch;
  const includeAddress = options.includeAddress !== false;
  const q = normalizeLookupQuery(query);
  if (q.length < 5 || q.length > 11) {
    throw new Error('Geçerli bir kimlik no veya VKN girin (5–11 karakter; harf+rakam olabilir).');
  }

  const token = await createGuestSession(fetchImpl);
  let result = null;
  let lastError = null;

  // Harfli (MŞ19660 vb.) → önce mükellefNo; saf rakam 9–11 → önce VKN.
  const letterId = hasLetters(q);
  const tryVknFirst = !letterId && q.length >= 9 && q.length <= 11;

  if (tryVknFirst) {
    try {
      result = await lookupByVkn(token, q, fetchImpl);
    } catch (error) {
      lastError = error;
    }
  }
  if (!result?.name && !result?.vkn) {
    try {
      result = await lookupByKimlik(token, q, fetchImpl);
    } catch (error) {
      lastError = error;
    }
  }
  // Harfli kimlikte mükellefNo tutmazsa vergiNo yolunu da dene.
  if (!result?.name && !result?.vkn && letterId) {
    try {
      result = await lookupByVkn(token, q, fetchImpl);
    } catch (error) {
      lastError = error;
    }
  }

  if (!result?.name && !result?.vkn) {
    const msg = lastError?.message || 'Mükellef bulunamadı.';
    if (/birden fazla|mükellef bulundu/i.test(msg)) {
      throw new Error('Birden fazla mükellef bulundu. Tam kimlik numarası veya VKN ile tekrar arayın.');
    }
    throw new Error(msg);
  }

  if (includeAddress && result.vkn) {
    const location = await lookupAddress(token, result.vkn, fetchImpl);
    if (location.address) result.address = location.address;
    if (location.city) result.city = location.city;
    if (location.taxOffice) result.taxOffice = location.taxOffice;
  }

  return result;
}

module.exports = {
  PORTAL_ORIGIN,
  ASSOS_LOGIN_URL,
  DISPATCH_URL,
  CMD_BY_KIMLIK,
  CMD_BY_VKN,
  CMD_ADDRESS,
  digits,
  isValidVknDigits,
  normalizeLookupQuery,
  hasLetters,
  cleanLocationLabel,
  extractCityFromAddressPayload,
  extractTaxOfficeFromPayload,
  mapKimlik,
  createGuestSession,
  dispatchService,
  lookupTaxpayer,
};
