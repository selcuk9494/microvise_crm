const crypto = require('crypto');

const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (!chunks.length) return {};
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return {};
  try {
    const parsed = JSON.parse(text);
    return parsed && typeof parsed === 'object' ? parsed : {};
  } catch (_) {
    return {};
  }
}

async function ensureEInvoiceSchema() {
  await query(`
    create table if not exists public.e_invoice_settings (
      id uuid primary key default gen_random_uuid(),
      environment text not null default 'test',
      api_base_url text not null default 'https://test-efatura.maliye.gov.ct.tr/api',
      token_url text not null default 'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
      client_id text not null default 'efatura-frontend',
      username text,
      password text,
      seller_vkn text not null default '0620009058',
      seller_title text not null default 'MICROVISE INNOVATION LTD',
      seller_branch_code text not null default '1',
      seller_tax_office text default 'Lefkoşa',
      seller_city text default 'LEFKOŞA',
      seller_country_code text not null default 'XCT',
      seller_country text default 'Kuzey Kıbrıs Türk Cumhuriyeti',
      seller_address_line1 text,
      seller_address_line2 text,
      seller_phone text,
      seller_email text,
      seller_website text,
      seller_bank_details text,
      akinsoft_sync_enabled text default 'false',
      akinsoft_vpn_name text,
      akinsoft_vpn_host text,
      akinsoft_vpn_username text,
      akinsoft_vpn_password text,
      akinsoft_mssql_host text,
      akinsoft_mssql_port text default '1433',
      akinsoft_mssql_database text,
      akinsoft_database_year text,
      akinsoft_database_pattern text,
      akinsoft_mssql_username text,
      akinsoft_mssql_password text,
      akinsoft_sync_notes text,
      next_sales_number bigint not null default 1,
      next_purchase_number bigint not null default 1,
      last_token_at timestamptz,
      last_sync_at timestamptz,
      is_active boolean not null default true,
      created_by uuid,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now()
    )
  `);
  await query(`
    alter table public.e_invoice_settings
      add column if not exists akinsoft_sync_enabled text default 'false',
      add column if not exists seller_bank_details text,
      add column if not exists akinsoft_vpn_name text,
      add column if not exists akinsoft_vpn_host text,
      add column if not exists akinsoft_vpn_username text,
      add column if not exists akinsoft_vpn_password text,
      add column if not exists akinsoft_mssql_host text,
      add column if not exists akinsoft_mssql_port text default '1433',
      add column if not exists akinsoft_mssql_database text,
      add column if not exists akinsoft_database_year text,
      add column if not exists akinsoft_database_pattern text,
      add column if not exists akinsoft_mssql_username text,
      add column if not exists akinsoft_mssql_password text,
      add column if not exists akinsoft_sync_notes text
  `);
  await query(`
    insert into public.e_invoice_settings (
      environment, api_base_url, token_url, client_id, seller_vkn, seller_title,
      seller_branch_code, seller_tax_office, seller_city, seller_country_code,
      seller_country, seller_address_line1
    )
    select
      'test',
      'https://test-efatura.maliye.gov.ct.tr/api',
      'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
      'efatura-frontend',
      '0620009058',
      'MICROVISE INNOVATION LTD',
      '1',
      'Lefkoşa',
      'LEFKOŞA',
      'XCT',
      'Kuzey Kıbrıs Türk Cumhuriyeti',
      'ATATÜRK CAD YENİŞEHİR EMEK 2 APT. DIŞ KAPI NO:1'
    where not exists (select 1 from public.e_invoice_settings)
  `);
  await query(`
    alter table public.invoices
      add column if not exists e_invoice_number text,
      add column if not exists e_invoice_uuid uuid,
      add column if not exists e_invoice_status text not null default 'not_sent',
      add column if not exists e_invoice_environment text,
      add column if not exists e_invoice_payload jsonb,
      add column if not exists e_invoice_response jsonb,
      add column if not exists e_invoice_official_data jsonb,
      add column if not exists e_invoice_official_ubl text,
      add column if not exists e_invoice_archived_at timestamptz,
      add column if not exists e_invoice_archive_error text,
      add column if not exists e_invoice_error text,
      add column if not exists e_invoice_sent_at timestamptz,
      add column if not exists e_invoice_sending_at timestamptz,
      add column if not exists irsaliye_no text,
      add column if not exists irsaliye_tarihi date
  `);
  await query(`
    alter table public.invoice_items
      add column if not exists special_matrah boolean not null default false,
      add column if not exists tax_exemption_code text,
      add column if not exists tax_exemption_description text
  `);
  await query(`
    update public.e_invoice_settings
    set seller_vkn = '0' || seller_vkn, updated_at = now()
    where seller_vkn ~ '^[0-9]{9}$'
  `);
  await query(`
    update public.e_invoice_settings
    set seller_bank_details = concat_ws(
      E'\\n',
      'Banka Hesap Bilgileri',
      'Türkiye İş Bankası',
      'Microvise Innovation Ltd',
      'TL IBAN: TR57 0006 4000 0016 8010 3409 94',
      'USD IBAN: TR41 0006 4000 0026 8010 4107 29'
    ),
    updated_at = now()
    where nullif(trim(seller_bank_details), '') is null
  `);
}

function cleanText(value) {
  const text = String(value ?? '').trim();
  return text.length ? text : null;
}

function invoiceDescription(settings) {
  return cleanText(settings.seller_bank_details);
}

const environmentUrls = {
  test: {
    apiBaseUrl: 'https://test-efatura.maliye.gov.ct.tr/api',
    tokenUrl:
      'https://keycloak.maliye.gov.ct.tr/realms/test/protocol/openid-connect/token',
  },
  production: {
    apiBaseUrl: 'https://efatura.maliye.gov.ct.tr/api',
    tokenUrl:
      'https://keycloak.maliye.gov.ct.tr/realms/production/protocol/openid-connect/token',
  },
};

function urlsForEnvironment(environment) {
  return environmentUrls[environment === 'production' ? 'production' : 'test'];
}

function normalizeDigits(value) {
  const digits = String(value ?? '').replace(/[^0-9]/g, '');
  return digits || null;
}

function normalizeApiVkn(value) {
  const digits = normalizeDigits(value);
  if (!digits) return null;
  if (digits.length === 10 && digits.startsWith('0')) return digits.slice(1);
  return digits;
}

function normalizeStoredVkn(value) {
  const digits = normalizeDigits(value);
  if (!digits) return null;
  if (digits.length === 9) return `0${digits}`;
  return digits;
}

function requireStoredVkn(value, fieldLabel = 'VKN') {
  const vkn = normalizeStoredVkn(value);
  if (!vkn || vkn.length !== 10) {
    throw new Error(`${fieldLabel} CRM sisteminde 10 haneli olmalıdır.`);
  }
  return vkn;
}

function requireApiVkn(value, fieldLabel = 'VKN') {
  const storedVkn = requireStoredVkn(value, fieldLabel);
  const vkn = normalizeApiVkn(storedVkn);
  if (!vkn || vkn.length !== 9) {
    throw new Error(
      `${fieldLabel} API için 9 haneli olmalıdır. 10 haneli değerlerde yalnızca baştaki bir sıfır kaldırılır.`,
    );
  }
  return vkn;
}

function round2(value) {
  return Math.round((Number(value || 0) + Number.EPSILON) * 100) / 100;
}

function isoWithOffset(dateValue, offset = '+03:00') {
  const base = dateValue ? new Date(dateValue) : new Date();
  if (Number.isNaN(base.getTime())) return new Date().toISOString();
  const yyyy = base.getFullYear().toString().padStart(4, '0');
  const mm = (base.getMonth() + 1).toString().padStart(2, '0');
  const dd = base.getDate().toString().padStart(2, '0');
  const hh = base.getHours().toString().padStart(2, '0');
  const mi = base.getMinutes().toString().padStart(2, '0');
  const ss = base.getSeconds().toString().padStart(2, '0');
  return `${yyyy}-${mm}-${dd}T${hh}:${mi}:${ss}${offset}`;
}

function createUuidV7() {
  const now = BigInt(Date.now());
  const bytes = crypto.randomBytes(16);
  bytes[0] = Number((now >> 40n) & 0xffn);
  bytes[1] = Number((now >> 32n) & 0xffn);
  bytes[2] = Number((now >> 24n) & 0xffn);
  bytes[3] = Number((now >> 16n) & 0xffn);
  bytes[4] = Number((now >> 8n) & 0xffn);
  bytes[5] = Number(now & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

function unitCode(unit) {
  const key = String(unit || '').toLocaleLowerCase('tr-TR');
  if (key.includes('kg')) return 'KGM';
  if (key.includes('lt') || key.includes('litre')) return 'LTR';
  if (key.includes('mt') || key.includes('metre')) return 'MTR';
  if (key.includes('saat')) return 'HUR';
  return 'C62';
}

function validateParty(party, label) {
  const errors = [];
  if (!cleanText(party.unvan)) errors.push(`${label} ünvanı zorunludur.`);
  if (!cleanText(party.adresSatir1)) errors.push(`${label} adresi zorunludur.`);
  if (!cleanText(party.sehir)) errors.push(`${label} şehri zorunludur.`);
  if (!/^[A-Z]{3}$/.test(String(party.ulkeKodu || ''))) {
    errors.push(`${label} ülke kodu ISO3 formatında olmalıdır.`);
  }
  if (!party.vkn && !(party.belgeNo && party.belgeTipi)) {
    errors.push(`${label} VKN veya kimlik belge bilgisi zorunludur.`);
  }
  return errors;
}

function validateInvoiceForEInvoice(settings, invoice) {
  const errors = [];
  try {
    requireStoredVkn(settings.seller_vkn, 'Satıcı VKN');
    requireApiVkn(settings.seller_vkn, 'Satıcı VKN');
  } catch (error) {
    errors.push(error.message);
  }

  const branch = cleanText(settings.seller_branch_code);
  if (!branch) {
    errors.push('Şube kodu zorunludur.');
  } else if (branch.length > 9) {
    errors.push('Şube kodu en fazla 9 karakter olmalıdır.');
  } else if (!/^[A-Za-z0-9_]+$/.test(branch)) {
    errors.push('Şube kodu yalnızca harf, rakam ve alt çizgi içermelidir.');
  }

  const currency = String(invoice.currency || '').trim().toUpperCase();
  if (!['TRY', 'USD', 'EUR', 'GBP'].includes(currency)) {
    errors.push(`Desteklenmeyen para birimi: ${currency || '(boş)'}.`);
  }
  if (Number(invoice.exchange_rate || 0) <= 0) {
    errors.push('Kur sıfırdan büyük olmalıdır.');
  }
  if (Number.isNaN(new Date(invoice.invoice_date).getTime())) {
    errors.push('Fatura tarihi geçersizdir.');
  }
  if (invoice.irsaliye_no && !invoice.irsaliye_tarihi) {
    errors.push('İrsaliye numarası girildiğinde irsaliye tarihi zorunludur.');
  }
  if (invoice.irsaliye_tarihi && !invoice.irsaliye_no) {
    errors.push('İrsaliye tarihi girildiğinde irsaliye numarası zorunludur.');
  }

  let seller;
  let customer;
  try {
    seller = partyFromSettings(settings);
  } catch (error) {
    errors.push(error.message);
  }
  try {
    customer = partyFromCustomer(invoice.customer || {});
  } catch (error) {
    errors.push(error.message);
  }
  if (seller) errors.push(...validateParty(seller, 'Satıcı'));
  if (customer) errors.push(...validateParty(customer, 'Müşteri'));

  const items = Array.isArray(invoice.items) ? invoice.items : [];
  if (!items.length) errors.push('En az bir fatura kalemi zorunludur.');
  let subtotal = 0;
  let discountTotal = 0;
  let taxTotal = 0;
  for (const [index, item] of items.entries()) {
    const prefix = `${index + 1}. kalem`;
    const qty = Number(item.quantity);
    const price = Number(item.unit_price);
    const discount = Number(item.discount_amount || 0);
    const taxRate = Number(item.tax_rate || 0);
    const base = qty * price;
    const specialMatrah = item.special_matrah === true;
    if (!cleanText(item.description)) errors.push(`${prefix} açıklaması zorunludur.`);
    if (!Number.isFinite(qty) || qty <= 0) errors.push(`${prefix} miktarı sıfırdan büyük olmalıdır.`);
    if (!Number.isFinite(price) || price < 0) errors.push(`${prefix} fiyatı negatif olamaz.`);
    if (!Number.isFinite(discount) || discount < 0 || discount > base) {
      errors.push(`${prefix} iskontosu kalem tutarı aralığında olmalıdır.`);
    }
    if (!Number.isFinite(taxRate) || taxRate < 0 || taxRate > 100) {
      errors.push(`${prefix} vergi oranı 0-100 aralığında olmalıdır.`);
    }
    if (specialMatrah && (taxRate !== 0 || Number(item.tax_amount || 0) !== 0)) {
      errors.push(`${prefix} özel matrahta vergi oranı ve tutarı 0 olmalıdır.`);
    }
    subtotal += Number.isFinite(base) ? base : 0;
    discountTotal += Number.isFinite(discount) ? discount : 0;
    taxTotal += specialMatrah
      ? 0
      : item.tax_amount == null
        ? round2((base - discount) * (taxRate / 100))
        : Number(item.tax_amount);
  }
  const expected = {
    subtotal: round2(subtotal),
    discount_total: round2(discountTotal),
    tax_total: round2(taxTotal),
    grand_total: round2(subtotal - discountTotal + taxTotal),
  };
  for (const [field, calculated] of Object.entries(expected)) {
    const stored = round2(invoice[field]);
    if (Math.abs(stored - calculated) > 0.02) {
      errors.push(
        `${field} tutarsız: kayıtlı ${stored.toFixed(2)}, hesaplanan ${calculated.toFixed(2)}.`,
      );
    }
  }
  return errors;
}

function partyFromSettings(settings) {
  const apiVkn = requireApiVkn(settings.seller_vkn, 'Satıcı VKN');
  return {
    ulkeKodu: cleanText(settings.seller_country_code) || 'XCT',
    ulke: cleanText(settings.seller_country) || 'Kuzey Kıbrıs Türk Cumhuriyeti',
    sehir: cleanText(settings.seller_city) || 'LEFKOŞA',
    adresSatir1: cleanText(settings.seller_address_line1),
    adresSatir2: cleanText(settings.seller_address_line2),
    telefon: cleanText(settings.seller_phone),
    email: cleanText(settings.seller_email),
    webSitesi: cleanText(settings.seller_website),
    unvan: cleanText(settings.seller_title),
    vkn: apiVkn,
    belgeNo: apiVkn,
    belgeTipi: 'VERGI_SICILNO',
  };
}

function partyFromCustomer(customer) {
  const address = cleanText(customer.address) || cleanText(customer.full_address);
  const party = {
    ulkeKodu: cleanText(customer.country_code) || 'XCT',
    ulke: cleanText(customer.country) || 'Kuzey Kıbrıs Türk Cumhuriyeti',
    sehir: cleanText(customer.city) || null,
    adresSatir1: address,
    adresSatir2: cleanText(customer.address_line2),
    telefon: cleanText(customer.phone1) || cleanText(customer.phone),
    email: cleanText(customer.email),
    webSitesi: cleanText(customer.website),
    unvan: cleanText(customer.name),
  };
  const storedVkn = customer.tax_number || customer.vkn;
  if (storedVkn) {
    party.vkn = requireApiVkn(storedVkn, 'Müşteri VKN');
  } else {
    const identityNumber = normalizeDigits(customer.tckn_ms);
    if (identityNumber) {
      party.belgeNo = identityNumber;
      party.belgeTipi = 'KIMLIKNO';
    }
  }
  return party;
}

function nextNumber(settings, invoiceType) {
  const raw =
    invoiceType === 'purchase'
      ? settings.next_purchase_number
      : settings.next_sales_number;
  const parsed = Number.parseInt(String(raw || '1'), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : 1;
}

function invoiceNumber(settings, invoice, serial) {
  if (invoice.e_invoice_number) {
    const parts = String(invoice.e_invoice_number).split('-');
    if (parts.length === 4) {
      parts[0] = requireApiVkn(parts[0], 'Fatura numarasındaki VKN');
      return parts.join('-');
    }
    return invoice.e_invoice_number;
  }
  const year = new Date(invoice.invoice_date || Date.now()).getFullYear();
  const vkn = requireApiVkn(settings.seller_vkn, 'Satıcı VKN');
  const branch = cleanText(settings.seller_branch_code) || '1';
  return `${vkn}-${year}-${branch}-${String(serial).padStart(11, '0')}`;
}

async function getSettings() {
  await ensureEInvoiceSchema();
  const result = await query(
    `select * from public.e_invoice_settings where is_active = true order by created_at asc limit 1`,
  );
  return result.rows[0] || null;
}

async function fetchInvoice(invoiceId) {
  const result = await query(
    `
      select
        i.*,
        row_to_json(c.*) as customer,
        coalesce(
          (
            select json_agg(ii order by ii.sort_order asc)
            from public.invoice_items ii
            where ii.invoice_id = i.id
          ),
          '[]'::json
        ) as items
      from public.invoices i
      left join public.customers c on c.id = i.customer_id
      where i.id = $1
      limit 1
    `,
    [invoiceId],
  );
  return result.rows[0] || null;
}

function buildPayload({ settings, invoice }) {
  const serial = nextNumber(settings, invoice.invoice_type);
  const number = invoiceNumber(settings, invoice, serial);
  const uuid = invoice.e_invoice_uuid || createUuidV7();
  const seller = partyFromSettings(settings);
  const customer = partyFromCustomer(invoice.customer || {});
  const isPurchase = invoice.invoice_type === 'purchase';
  const items = Array.isArray(invoice.items) ? invoice.items : [];

  const malHizmetler = items.map((item) => {
    const qty = Number(item.quantity || 0);
    const price = Number(item.unit_price || 0);
    const base = qty * price;
    const discount = Number(item.discount_amount || 0);
    const taxRate = Number(item.tax_rate || 0);
    const specialMatrah = item.special_matrah === true;
    const taxAmount = specialMatrah
      ? 0
      :
      item.tax_amount == null
        ? round2((base - discount) * (taxRate / 100))
        : round2(item.tax_amount);
    return {
      adi: cleanText(item.description) || 'Mal/Hizmet',
      birimMiktari: qty,
      fiyat: price,
      birimTurKod: unitCode(item.unit),
      aciklama: cleanText(item.description),
      saticiUrunKodu: cleanText(item.product_id),
      iskontoVeEkUcretler:
        discount > 0
          ? [
              {
                indirimMi: true,
                tutar: round2(discount),
                neden: 'Satır indirimi',
                oran: Number(item.discount_rate || 0),
              },
            ]
          : [],
      vergiler: [
        {
          vergiKodu: '0002',
          vergiOrani: specialMatrah ? 0 : taxRate,
          vergiTutari: taxAmount,
          ...(specialMatrah
            ? {
                vergiMuafiyetKodu: cleanText(item.tax_exemption_code) || '101',
                vergiMuafiyetAciklamasi:
                  cleanText(item.tax_exemption_description) || 'Özel Matrah',
              }
            : {}),
        },
      ],
    };
  });

  const payload = {
    faturalar: [
      {
        faturaNo: number,
        dogrulamaKodu: uuid,
        subeKod: cleanText(settings.seller_branch_code) || '1',
        malHizmetler,
        faturaTarihi: isoWithOffset(invoice.invoice_date),
        paraBirimi: invoice.currency || 'TRY',
        faturaTuru: isPurchase ? 'ALIS' : 'SATIS',
        aciklama: invoiceDescription(settings),
        kur: Number(invoice.exchange_rate || 1),
        faturaToplami: round2(invoice.subtotal),
        iskontoToplami: round2(invoice.discount_total),
        kdvToplami: round2(invoice.tax_total),
        vergiDahilToplam: round2(invoice.grand_total),
        odenecekToplam: round2(invoice.grand_total),
        irsaliyeNo: cleanText(invoice.irsaliye_no),
        irsaliyeTarihi: invoice.irsaliye_tarihi
          ? isoWithOffset(invoice.irsaliye_tarihi)
          : null,
        musteri: isPurchase ? seller : customer,
        tedarikci: isPurchase ? customer : seller,
      },
    ],
  };

  return { payload, number, uuid };
}

async function tokenFor(settings) {
  if (!settings.username || !settings.password) {
    throw new Error('E-fatura test kullanıcısı ve şifresi girilmemiş.');
  }

  const params = new URLSearchParams();
  params.set('grant_type', 'password');
  params.set('client_id', settings.client_id || 'efatura-frontend');
  params.set('username', settings.username);
  params.set('password', settings.password);

  const urls = urlsForEnvironment(settings.environment);
  const response = await fetch(urls.tokenUrl, {
    method: 'POST',
    headers: { 'content-type': 'application/x-www-form-urlencoded' },
    body: params.toString(),
  });
  const json = await response.json().catch(() => ({}));
  if (!response.ok || !json.access_token) {
    throw new Error(json.error_description || json.error || 'Token alınamadı.');
  }
  await query(
    `update public.e_invoice_settings set last_token_at = now(), updated_at = now() where id = $1`,
    [settings.id],
  );
  return json.access_token;
}

function responseItems(value) {
  if (Array.isArray(value)) return value;
  if (!value || typeof value !== 'object') return [];
  for (const key of ['data', 'items', 'content', 'sonuclar', 'subeler']) {
    if (Array.isArray(value[key])) return value[key];
  }
  return [];
}

function valuesFromRows(rows, keys) {
  return new Set(
    rows
      .map((row) => {
        if (typeof row === 'string') return row;
        for (const key of keys) {
          const value = cleanText(row?.[key]);
          if (value) return value;
        }
        return null;
      })
      .filter(Boolean)
      .map((value) => String(value).toUpperCase()),
  );
}

async function apiGet({ base, path, token }) {
  const response = await fetch(`${base}${path}`, {
    headers: {
      authorization: `Bearer ${token}`,
      accept: 'application/json',
    },
  });
  const text = await response.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = { raw: text };
  }
  if (!response.ok) {
    const error = new Error(
      json?.message || json?.error || text || `${path} doğrulaması başarısız.`,
    );
    error.response = json;
    throw error;
  }
  return json;
}

async function apiGetText({ base, path, token, accept }) {
  const response = await fetch(`${base}${path}`, {
    headers: {
      authorization: `Bearer ${token}`,
      accept,
    },
  });
  const text = await response.text();
  if (!response.ok) {
    const error = new Error(text || `${path} arşivlemesi başarısız.`);
    error.response = { raw: text };
    throw error;
  }
  return text;
}

async function fetchOfficialInvoiceArchive({ settings, verificationCode, token }) {
  const base = urlsForEnvironment(settings.environment).apiBaseUrl;
  const vkn = encodeURIComponent(requireApiVkn(settings.seller_vkn, 'Satıcı VKN'));
  const code = encodeURIComponent(cleanText(verificationCode));
  if (!code) throw new Error('Maliye doğrulama kodu bulunamadı.');
  const detailPath = `/mukellefler/${vkn}/faturalar/${code}`;
  const [data, ubl] = await Promise.all([
    apiGet({ base, path: detailPath, token }),
    apiGetText({
      base,
      path: `${detailPath}/ubl`,
      token,
      accept: 'application/xml',
    }),
  ]);
  return { data, ubl };
}

async function archiveOfficialInvoice({ invoiceId, settings, verificationCode, token }) {
  try {
    const archive = await fetchOfficialInvoiceArchive({
      settings,
      verificationCode,
      token: token || (await tokenFor(settings)),
    });
    await query(
      `
        update public.invoices
        set e_invoice_official_data = $2::jsonb,
            e_invoice_official_ubl = $3,
            e_invoice_archived_at = now(),
            e_invoice_archive_error = null,
            updated_at = now()
        where id = $1
      `,
      [invoiceId, JSON.stringify(archive.data), archive.ubl],
    );
    return { archived: true, archivedAt: new Date().toISOString() };
  } catch (error) {
    await query(
      `
        update public.invoices
        set e_invoice_archive_error = $2,
            updated_at = now()
        where id = $1
      `,
      [invoiceId, error.message],
    );
    return { archived: false, error: error.message };
  }
}

async function validatePayloadAgainstApi({ settings, payload, token }) {
  const base = urlsForEnvironment(settings.environment).apiBaseUrl;
  const vkn = encodeURIComponent(requireApiVkn(settings.seller_vkn, 'Satıcı VKN'));
  const [invoiceTypesRaw, currenciesRaw, taxesRaw, unitsRaw, branchesRaw] =
    await Promise.all([
      apiGet({ base, path: '/fatura-turleri', token }),
      apiGet({ base, path: '/para-birimleri', token }),
      apiGet({ base, path: '/vergiler', token }),
      apiGet({ base, path: '/birim-turleri', token }),
      apiGet({ base, path: `/mukellefler/${vkn}/subeler`, token }),
    ]);

  const invoiceTypes = valuesFromRows(responseItems(invoiceTypesRaw), [
    'kod',
    'code',
    'faturaTuru',
  ]);
  const currencies = valuesFromRows(responseItems(currenciesRaw), [
    'kod',
    'code',
    'paraBirimi',
  ]);
  const taxes = valuesFromRows(responseItems(taxesRaw), [
    'vergiKodu',
    'kod',
    'code',
  ]);
  const units = valuesFromRows(responseItems(unitsRaw), [
    'kod',
    'code',
    'birimTurKod',
  ]);
  const branches = valuesFromRows(responseItems(branchesRaw), [
    'subeKod',
    'kod',
    'code',
  ]);
  const errors = [];
  for (const invoice of payload.faturalar || []) {
    if (invoiceTypes.size && !invoiceTypes.has(String(invoice.faturaTuru).toUpperCase())) {
      errors.push(`Fatura türü Maliye kod listesinde yok: ${invoice.faturaTuru}.`);
    }
    if (currencies.size && !currencies.has(String(invoice.paraBirimi).toUpperCase())) {
      errors.push(`Para birimi Maliye kod listesinde yok: ${invoice.paraBirimi}.`);
    }
    if (branches.size && !branches.has(String(invoice.subeKod).toUpperCase())) {
      errors.push(`Şube kodu Maliye sisteminde kayıtlı değil: ${invoice.subeKod}.`);
    }
    for (const item of invoice.malHizmetler || []) {
      if (units.size && !units.has(String(item.birimTurKod).toUpperCase())) {
        errors.push(`Birim kodu Maliye kod listesinde yok: ${item.birimTurKod}.`);
      }
      for (const tax of item.vergiler || []) {
        if (taxes.size && !taxes.has(String(tax.vergiKodu).toUpperCase())) {
          errors.push(`Vergi kodu Maliye kod listesinde yok: ${tax.vergiKodu}.`);
        }
      }
    }
  }
  if (errors.length) throw new Error(errors.join(' '));
}

async function applyRegisteredSupplierIdentity({ settings, payload, token }) {
  const base = urlsForEnvironment(settings.environment).apiBaseUrl;
  const sellerVkn = requireApiVkn(settings.seller_vkn, 'Satıcı VKN');
  const registeredRaw = await apiGet({
    base,
    path: `/mukellefler/${encodeURIComponent(sellerVkn)}`,
    token,
  });
  const registered =
    registeredRaw?.data && typeof registeredRaw.data === 'object'
      ? registeredRaw.data
      : registeredRaw;
  const registeredTitle =
    cleanText(registered?.unvan) ||
    cleanText(registered?.ticariUnvan) ||
    cleanText(settings.seller_title);
  const registeredDocumentNumber =
    cleanText(registered?.belgeNo) || sellerVkn;
  const registeredDocumentType =
    cleanText(registered?.belgeTipi) || 'VERGI_SICILNO';

  for (const invoice of payload.faturalar || []) {
    const supplier = invoice?.tedarikci;
    if (!supplier || normalizeApiVkn(supplier.vkn) !== sellerVkn) continue;
    supplier.unvan = registeredTitle;
    supplier.belgeNo = registeredDocumentNumber;
    supplier.belgeTipi = registeredDocumentType;
  }
}

function assertSuccessfulMaliyeResponse(response) {
  const failedCount = Number(response?.ozet?.basarisizKayit || 0);
  const failedItems = Array.isArray(response?.sonuclar)
    ? response.sonuclar.filter((item) => item?.basarili === false)
    : [];
  if (failedCount > 0 || failedItems.length > 0) {
    const messages = failedItems
      .map((item) => cleanText(item?.hataMesaji))
      .filter(Boolean);
    const error = new Error(
      messages.join(' ') ||
        `${Math.max(failedCount, failedItems.length)} fatura reddedildi.`,
    );
    error.response = response;
    throw error;
  }
  return response;
}

async function sendToMaliye({ settings, payload }) {
  const token = await tokenFor(settings);
  const vkn = encodeURIComponent(requireApiVkn(settings.seller_vkn, 'Satıcı VKN'));
  const base = urlsForEnvironment(settings.environment).apiBaseUrl;
  await applyRegisteredSupplierIdentity({ settings, payload, token });
  await validatePayloadAgainstApi({ settings, payload, token });
  const response = await fetch(`${base}/mukellefler/${vkn}/faturalar`, {
    method: 'POST',
    headers: {
      authorization: `Bearer ${token}`,
      'content-type': 'application/json',
      accept: 'application/json',
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : {};
  } catch (_) {
    json = { raw: text };
  }
  if (!response.ok) {
    const message = json?.error || json?.message || text || 'E-fatura gönderimi başarısız.';
    const error = new Error(message);
    error.response = json;
    throw error;
  }
  return { response: assertSuccessfulMaliyeResponse(json), token };
}

async function handler(req, res) {
  if (handleCors(req, res, 'GET,POST,OPTIONS')) return;

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    if (!hasPageAccess(user, 'e_fatura') && !hasPageAccess(user, 'faturalama')) {
      return forbidden(req, res, 'E-fatura yetkiniz yok.');
    }

    await ensureEInvoiceSchema();

    if (req.method === 'GET') {
      const settings = await getSettings();
      return ok(req, res, { settings });
    }

    if (req.method !== 'POST') return methodNotAllowed(req, res, 'GET,POST');

    const body = await readJson(req);
    const action = String(body.action || '').trim();

    if (action === 'save_settings') {
      const values = body.settings && typeof body.settings === 'object' ? body.settings : {};
      const allowed = [
        'environment',
        'api_base_url',
        'token_url',
        'client_id',
        'username',
        'password',
        'seller_vkn',
        'seller_title',
        'seller_branch_code',
        'seller_tax_office',
        'seller_city',
        'seller_country_code',
        'seller_country',
        'seller_address_line1',
        'seller_address_line2',
        'seller_phone',
        'seller_email',
        'seller_website',
        'seller_bank_details',
        'akinsoft_sync_enabled',
        'akinsoft_vpn_name',
        'akinsoft_vpn_host',
        'akinsoft_vpn_username',
        'akinsoft_vpn_password',
        'akinsoft_mssql_host',
        'akinsoft_mssql_port',
        'akinsoft_mssql_database',
        'akinsoft_database_year',
        'akinsoft_database_pattern',
        'akinsoft_mssql_username',
        'akinsoft_mssql_password',
        'akinsoft_sync_notes',
        'next_sales_number',
        'next_purchase_number',
      ];
      const current = await getSettings();
      const picked = {};
      for (const key of allowed) {
        if (Object.prototype.hasOwnProperty.call(values, key)) picked[key] = values[key];
      }
      if (Object.prototype.hasOwnProperty.call(picked, 'seller_vkn')) {
        try {
          picked.seller_vkn = requireStoredVkn(picked.seller_vkn, 'Satıcı VKN');
        } catch (error) {
          return badRequest(req, res, error.message);
        }
      }
      const selectedEnvironment =
        picked.environment === 'production' ? 'production' : 'test';
      const selectedUrls = urlsForEnvironment(selectedEnvironment);
      picked.environment = selectedEnvironment;
      picked.api_base_url = selectedUrls.apiBaseUrl;
      picked.token_url = selectedUrls.tokenUrl;
      picked.updated_at = new Date().toISOString();
      if (user.auth_user_id) picked.created_by = user.auth_user_id;

      const keys = Object.keys(picked);
      if (!keys.length) return badRequest(req, res, 'Kaydedilecek ayar yok.');
      const setSql = keys.map((key, idx) => `${key} = $${idx + 2}`).join(', ');
      const result = await query(
        `update public.e_invoice_settings set ${setSql} where id = $1 returning *`,
        [current.id, ...keys.map((key) => picked[key])],
      );
      return ok(req, res, { settings: result.rows[0] });
    }

    if (action === 'archive') {
      const invoiceId = String(body.invoiceId || '').trim();
      if (!invoiceId) return badRequest(req, res, 'invoiceId zorunludur.');
      const invoice = await fetchInvoice(invoiceId);
      if (!invoice) return badRequest(req, res, 'Fatura bulunamadı.');
      if (invoice.e_invoice_status !== 'sent' || !invoice.e_invoice_uuid) {
        return badRequest(req, res, 'Yalnızca gönderilmiş e-fatura arşivlenebilir.');
      }
      if (
        invoice.e_invoice_official_data &&
        cleanText(invoice.e_invoice_official_ubl)
      ) {
        return ok(req, res, {
          ok: true,
          archived: true,
          alreadyArchived: true,
          archivedAt: invoice.e_invoice_archived_at,
        });
      }
      const currentSettings = await getSettings();
      const archiveSettings = {
        ...currentSettings,
        environment:
          invoice.e_invoice_environment === 'production' ? 'production' : 'test',
      };
      const archive = await archiveOfficialInvoice({
        invoiceId,
        settings: archiveSettings,
        verificationCode: invoice.e_invoice_uuid,
      });
      return ok(req, res, { ok: archive.archived, ...archive });
    }

    if (action === 'prepare' || action === 'send') {
      const invoiceId = String(body.invoiceId || '').trim();
      if (!invoiceId) return badRequest(req, res, 'invoiceId zorunludur.');
      const settings = await getSettings();
      const invoice = await fetchInvoice(invoiceId);
      if (!invoice) return badRequest(req, res, 'Fatura bulunamadı.');
      if (invoice.e_invoice_status === 'sent') {
        return badRequest(
          req,
          res,
          `Bu fatura daha önce başarıyla gönderildi${
            invoice.e_invoice_number ? `: ${invoice.e_invoice_number}` : '.'
          } Tekrar gönderilemez.`,
        );
      }
      if (!Array.isArray(invoice.items) || invoice.items.length === 0) {
        return badRequest(req, res, 'E-fatura için en az bir kalem olmalıdır.');
      }
      const validationErrors = validateInvoiceForEInvoice(settings, invoice);
      if (validationErrors.length) {
        return badRequest(req, res, validationErrors.join(' '));
      }
      const built = buildPayload({ settings, invoice });

      if (action === 'prepare') {
        const prepared = await query(
          `
            update public.invoices
            set e_invoice_number = $2,
                e_invoice_uuid = $3,
                e_invoice_status = 'prepared',
                e_invoice_environment = $4,
                e_invoice_payload = $5::jsonb,
                e_invoice_error = null,
                updated_at = now()
            where id = $1
              and e_invoice_status is distinct from 'sent'
            returning id
          `,
          [
            invoiceId,
            built.number,
            built.uuid,
            settings.environment,
            JSON.stringify(built.payload),
          ],
        );
        if (!prepared.rows.length) {
          return badRequest(req, res, 'Başarıyla gönderilmiş fatura değiştirilemez.');
        }
        return ok(req, res, {
          ok: true,
          mode: 'prepare',
          invoiceNumber: built.number,
          uuid: built.uuid,
          payload: built.payload,
        });
      }

      const claimed = await query(
        `
          update public.invoices
          set e_invoice_number = $2,
              e_invoice_uuid = $3,
              e_invoice_status = 'prepared',
              e_invoice_environment = $4,
              e_invoice_payload = $5::jsonb,
              e_invoice_error = null,
              e_invoice_sending_at = now(),
              updated_at = now()
          where id = $1
            and e_invoice_status is distinct from 'sent'
            and (
              e_invoice_sending_at is null
              or e_invoice_sending_at < now() - interval '10 minutes'
            )
          returning id
        `,
        [
          invoiceId,
          built.number,
          built.uuid,
          settings.environment,
          JSON.stringify(built.payload),
        ],
      );
      if (!claimed.rows.length) {
        return badRequest(
          req,
          res,
          'Bu fatura daha önce gönderildi veya gönderim işlemi halen devam ediyor.',
        );
      }

      try {
        const sent = await sendToMaliye({ settings, payload: built.payload });
        const response = sent.response;
        await query(
          `
            update public.invoices
            set e_invoice_status = 'sent',
                e_invoice_response = $2::jsonb,
                e_invoice_error = null,
                e_invoice_sent_at = now(),
                e_invoice_sending_at = null,
                updated_at = now()
            where id = $1
          `,
          [invoiceId, JSON.stringify(response)],
        );
        const nextColumn =
          invoice.invoice_type === 'purchase'
            ? 'next_purchase_number'
            : 'next_sales_number';
        await query(
          `update public.e_invoice_settings set ${nextColumn} = ${nextColumn} + 1, last_sync_at = now(), updated_at = now() where id = $1`,
          [settings.id],
        );
        const archive = await archiveOfficialInvoice({
          invoiceId,
          settings,
          verificationCode: built.uuid,
          token: sent.token,
        });
        return ok(req, res, {
          ok: true,
          mode: 'send',
          invoiceNumber: built.number,
          uuid: built.uuid,
          response,
          archive,
        });
      } catch (error) {
        await query(
          `
            update public.invoices
            set e_invoice_status = 'failed',
                e_invoice_response = $2::jsonb,
                e_invoice_error = $3,
                e_invoice_sending_at = null,
                updated_at = now()
            where id = $1
          `,
          [
            invoiceId,
            JSON.stringify(error.response || { error: error.message }),
            error.message,
          ],
        );
        throw error;
      }
    }

    return badRequest(req, res, 'Geçersiz işlem.');
  } catch (error) {
    return serverError(req, res, error);
  }
}

module.exports = handler;
module.exports.testUtils = {
  normalizeApiVkn,
  normalizeStoredVkn,
  requireStoredVkn,
  requireApiVkn,
  invoiceNumber,
  createUuidV7,
  validateInvoiceForEInvoice,
  buildPayload,
  assertSuccessfulMaliyeResponse,
  validatePayloadAgainstApi,
  urlsForEnvironment,
  applyRegisteredSupplierIdentity,
};
