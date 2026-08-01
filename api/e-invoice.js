const crypto = require('crypto');
const fs = require('fs');

const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const { query } = require('./_lib/db');
const {
  buildEInvoiceArchivePdf,
  writeLocalEInvoicePdf,
} = require('./_lib/e_invoice_pdf');
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
      add column if not exists e_invoice_pdf_bucket text,
      add column if not exists e_invoice_pdf_path text,
      add column if not exists e_invoice_pdf_sha256 text,
      add column if not exists e_invoice_pdf_created_at timestamptz,
      add column if not exists e_invoice_archived_at timestamptz,
      add column if not exists e_invoice_archive_error text,
      add column if not exists e_invoice_error text,
      add column if not exists e_invoice_sent_at timestamptz,
      add column if not exists e_invoice_sending_at timestamptz,
      add column if not exists irsaliye_no text,
      add column if not exists irsaliye_tarihi date,
      add column if not exists po_number text,
      add column if not exists erp_invoice_number text,
      add column if not exists erp_invoice_number_synced_at timestamptz,
      add column if not exists prices_include_vat boolean not null default false,
      add column if not exists akinsoft_sync_status text,
      add column if not exists akinsoft_synced_at timestamptz,
      add column if not exists akinsoft_sync_error text
  `);
  await query(`
    alter table public.invoice_items
      add column if not exists special_matrah boolean not null default false,
      add column if not exists tax_exemption_code text,
      add column if not exists tax_exemption_description text,
      add column if not exists notes text
  `);
  await query(`
    alter table public.customers
      add column if not exists country_code text not null default 'XCT',
      add column if not exists country text not null default 'Kuzey Kıbrıs Türk Cumhuriyeti'
  `);
  await query(`
    create table if not exists public.e_invoice_transmissions (
      id uuid primary key default gen_random_uuid(),
      invoice_id uuid not null references public.invoices(id) on delete cascade,
      environment text not null,
      e_invoice_number text,
      e_invoice_uuid uuid,
      payload jsonb,
      response jsonb,
      official_data jsonb,
      official_ubl text,
      sent_at timestamptz,
      archived_at timestamptz,
      created_at timestamptz not null default now(),
      unique (invoice_id, environment, e_invoice_uuid)
    )
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

/** Line açıklama: only a real distinct note — never duplicate Mal/Hizmet (adi). */
function distinctLineAciklama(adi, item) {
  const name = String(adi || '')
    .trim()
    .toLocaleLowerCase('tr-TR');
  const candidates = [
    item?.aciklama,
    item?.line_description,
    item?.notes,
  ];
  for (const candidate of candidates) {
    const value = cleanText(candidate);
    if (!value) continue;
    if (name && value.toLocaleLowerCase('tr-TR') === name) continue;
    return value;
  }
  return '';
}

function invoiceDescription(settings, invoice) {
  const bank = cleanText(settings.seller_bank_details);
  // Alana yazılan değer olduğu gibi eklenir; önek konmaz. Boşsa satır çıkmaz.
  const po = cleanText(invoice?.po_number);
  if (!bank && !po) return null;
  if (!po) return bank;
  if (!bank) return po;
  return `${bank}\n${po}`;
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

function calendarDateUtc(value) {
  const text = String(value || '');
  const match = text.match(/^(\d{4})-(\d{2})-(\d{2})/);
  if (match) {
    return validCalendarDateUtc(
      Number(match[1]),
      Number(match[2]),
      Number(match[3]),
    );
  }

  const parsed = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(parsed.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Famagusta',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(parsed);
  const values = Object.fromEntries(
    parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]),
  );
  return validCalendarDateUtc(
    Number(values.year),
    Number(values.month),
    Number(values.day),
  );
}

function validCalendarDateUtc(year, month, day) {
  const timestamp = Date.UTC(year, month - 1, day);
  const parsed = new Date(timestamp);
  if (
    parsed.getUTCFullYear() !== year ||
    parsed.getUTCMonth() !== month - 1 ||
    parsed.getUTCDate() !== day
  ) {
    return null;
  }
  return timestamp;
}

function currentCalendarDateUtc(now = new Date()) {
  const parts = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Asia/Famagusta',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
  }).formatToParts(now);
  const values = Object.fromEntries(
    parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]),
  );
  return Date.UTC(Number(values.year), Number(values.month) - 1, Number(values.day));
}

function validateInvoiceForEInvoice(settings, invoice, now = new Date()) {
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
  const invoiceDate = calendarDateUtc(invoice.invoice_date);
  if (invoiceDate == null) {
    errors.push('Fatura tarihi geçersizdir.');
  } else {
    const ageInDays = Math.floor(
      (currentCalendarDateUtc(now) - invoiceDate) / (24 * 60 * 60 * 1000),
    );
    if (ageInDays > 14) {
      errors.push(
        `Fatura tarihi ${ageInDays} gün önce. Maliye en fazla 14 günlük faturayı kabul eder.`,
      );
    } else if (ageInDays < 0) {
      errors.push('Fatura tarihi gelecekte olamaz.');
    }
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
    discountTotal += Number.isFinite(discount) ? round2(discount) : 0;
    taxTotal += lineTaxAmount(item);
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
  const countryCode = String(customer.country_code || 'XCT').trim().toUpperCase();
  const party = {
    ulkeKodu: countryCode,
    ulke:
      cleanText(customer.country) ||
      (countryCode === 'TUR'
        ? 'Türkiye'
        : 'Kuzey Kıbrıs Türk Cumhuriyeti'),
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
    if (countryCode === 'XCT') {
      party.vkn = requireApiVkn(storedVkn, 'Müşteri VKN');
    } else {
      const foreignTaxNumber = normalizeDigits(storedVkn);
      if (!foreignTaxNumber) {
        throw new Error('Yabancı müşteri vergi/kimlik numarası zorunludur.');
      }
      party.belgeNo = foreignTaxNumber;
      party.belgeTipi = 'YABANCI_KIMLIKNO';
    }
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

function invoiceNumberPrefix(settings, invoice) {
  const year = new Date(invoice.invoice_date || Date.now()).getFullYear();
  const vkn = requireApiVkn(settings.seller_vkn, 'Satıcı VKN');
  const branch = cleanText(settings.seller_branch_code) || '1';
  return `${vkn}-${year}-${branch}-`;
}

function isNumberAlreadyUsedError(error) {
  const haystack = [
    error?.message,
    JSON.stringify(error?.response || ''),
  ]
    .filter(Boolean)
    .join(' ')
    .toLocaleLowerCase('tr-TR');
  return (
    haystack.includes('zaten kullanılmakta') ||
    haystack.includes('zaten kullanilmakta') ||
    haystack.includes('zaten kullanılmış') ||
    haystack.includes('daha önce kullanılmış')
  );
}

function officialNumberFromResponse(response, fallback) {
  const items = Array.isArray(response?.sonuclar) ? response.sonuclar : [];
  for (const item of items) {
    if (item?.basarili === false) continue;
    const number = cleanText(item?.faturaNo);
    if (number) return number;
  }
  return cleanText(fallback);
}

function localInvoiceNumber(number) {
  return cleanText(number).replace(/^\d{9}-/, '');
}

// Canlı gönderim başarılı olunca CRM fatura numarasını Maliye numarasına çeker.
// ERP'deki eski numara erp_invoice_number alanında saklanır (Akınsoft yazımı için).
async function applyOfficialInvoiceNumber({
  invoiceId,
  officialNumber,
  currentInvoiceNumber,
  erpInvoiceNumber,
  environment,
}) {
  if (String(environment || '') !== 'production') {
    return { renamed: false, reason: 'not_production' };
  }
  const official = cleanText(officialNumber);
  if (!official) return { renamed: false, reason: 'missing_number' };
  const localOfficial = localInvoiceNumber(official);

  const current = cleanText(currentInvoiceNumber);
  const preservedErp =
    cleanText(erpInvoiceNumber) ||
    (current && current !== official && current !== localOfficial ? current : null);

  if (current === localOfficial) {
    if (preservedErp && !cleanText(erpInvoiceNumber)) {
      await query(
        `
          update public.invoices
          set erp_invoice_number = coalesce(erp_invoice_number, $2),
              updated_at = now()
          where id = $1
        `,
        [invoiceId, preservedErp],
      );
    }
    return {
      renamed: false,
      reason: 'already_official',
      invoiceNumber: localOfficial,
      erpInvoiceNumber: preservedErp,
    };
  }

  const conflict = await query(
    `
      select id
      from public.invoices
      where invoice_number = $1
        and id is distinct from $2
      limit 1
    `,
    [localOfficial, invoiceId],
  );
  if (conflict.rows.length) {
    if (preservedErp) {
      await query(
        `
          update public.invoices
          set erp_invoice_number = coalesce(erp_invoice_number, $2),
              updated_at = now()
          where id = $1
        `,
        [invoiceId, preservedErp],
      );
    }
    return {
      renamed: false,
      reason: 'conflict',
      invoiceNumber: current,
      erpInvoiceNumber: preservedErp,
      officialNumber: localOfficial,
    };
  }

  await query(
    `
      update public.invoices
      set invoice_number = $2,
          erp_invoice_number = coalesce(nullif(trim(erp_invoice_number), ''), $3),
          updated_at = now()
      where id = $1
    `,
    [invoiceId, localOfficial, preservedErp],
  );
  return {
    renamed: true,
    from: current,
    to: localOfficial,
    erpInvoiceNumber: preservedErp,
    invoiceNumber: localOfficial,
  };
}

// Sayaç yalnızca başarılı gönderimden sonra ilerlediği için hazırlanmış ya da
// hatalı kalan faturalar aynı numarayı tutabiliyor. Numarayı gönderim anında
// yerelde kullanılmış olanları atlayarak seçiyoruz.
async function reservedInvoiceNumbers(prefix, excludeInvoiceId) {
  const result = await query(
    `
      select e_invoice_number
      from public.invoices
      where e_invoice_number like $1
        and id is distinct from $2
        and e_invoice_status in ('sent', 'prepared')
    `,
    [`${prefix}%`, excludeInvoiceId || null],
  );
  return new Set(
    result.rows
      .map((row) => cleanText(row.e_invoice_number))
      .filter(Boolean),
  );
}

function serialFromNumber(number, prefix) {
  if (!number || !String(number).startsWith(prefix)) return null;
  const parsed = Number.parseInt(String(number).slice(prefix.length), 10);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
}

async function resolveInvoiceNumber({ settings, invoice, invoiceId, skip }) {
  const prefix = invoiceNumberPrefix(settings, invoice);
  const taken = await reservedInvoiceNumbers(prefix, invoiceId);
  for (const value of skip || []) {
    const cleaned = cleanText(value);
    if (cleaned) taken.add(cleaned);
  }

  const stored = cleanText(invoice.e_invoice_number);
  if (stored) {
    const normalized = invoiceNumber(settings, invoice, 0);
    if (!taken.has(normalized)) {
      return { number: normalized, serial: serialFromNumber(normalized, prefix) };
    }
  }

  let serial = nextNumber(settings, invoice.invoice_type);
  let candidate = `${prefix}${String(serial).padStart(11, '0')}`;
  while (taken.has(candidate)) {
    serial += 1;
    candidate = `${prefix}${String(serial).padStart(11, '0')}`;
  }
  return { number: candidate, serial };
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
            select json_agg(row_to_json(line) order by line.sort_order asc)
            from (
              select
                ii.*,
                nullif(btrim(coalesce(p.description, '')), '') as product_description
              from public.invoice_items ii
              left join public.products p on p.id = ii.product_id
              where ii.invoice_id = i.id
            ) line
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

function lineTaxAmount(item) {
  const qty = Number(item.quantity || 0);
  const price = Number(item.unit_price || 0);
  const base = qty * price;
  const discount = round2(Number(item.discount_amount || 0));
  const taxRate = Number(item.tax_rate || 0);
  if (item.special_matrah === true) return 0;
  if (item.tax_amount == null) {
    return round2((base - discount) * (taxRate / 100));
  }
  return round2(item.tax_amount);
}

// Maliye bazı kurlarda satır bazlı TL çevirisi ile başlık toplamını
// karşılaştırıyor; 0,01 sapma "Fatura toplamı tutarsız" üretiyor.
// Bağımsız e-fatura uygulaması gibi payload'da kur=1 gönderilir;
// CRM'deki exchange_rate yerel muhasebe için saklanmaya devam eder.
function payloadExchangeRate(_invoice) {
  return 1;
}

function buildPayload({ settings, invoice, number: numberOverride }) {
  const serial = nextNumber(settings, invoice.invoice_type);
  const number =
    cleanText(numberOverride) || invoiceNumber(settings, invoice, serial);
  const uuid = invoice.e_invoice_uuid || createUuidV7();
  const seller = partyFromSettings(settings);
  const customer = partyFromCustomer(invoice.customer || {});
  const isPurchase = invoice.invoice_type === 'purchase';
  const items = Array.isArray(invoice.items) ? invoice.items : [];

  let faturaToplami = 0;
  let iskontoToplami = 0;
  let kdvToplami = 0;

  const malHizmetler = items.map((item) => {
    const qty = Number(item.quantity || 0);
    const price = Number(item.unit_price || 0);
    const base = qty * price;
    const discount = round2(Number(item.discount_amount || 0));
    const taxRate = Number(item.tax_rate || 0);
    const specialMatrah = item.special_matrah === true;
    const taxAmount = lineTaxAmount(item);
    faturaToplami += base;
    iskontoToplami += discount;
    kdvToplami += taxAmount;
    const adi = cleanText(item.description) || 'Mal/Hizmet';
    return {
      adi,
      birimMiktari: qty,
      fiyat: price,
      birimTurKod: unitCode(item.unit),
      aciklama: distinctLineAciklama(adi, item),
      saticiUrunKodu: cleanText(item.product_id),
      iskontoVeEkUcretler:
        discount > 0
          ? [
              {
                indirimMi: true,
                tutar: discount,
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

  faturaToplami = round2(faturaToplami);
  iskontoToplami = round2(iskontoToplami);
  kdvToplami = round2(kdvToplami);
  const vergiDahilToplam = round2(faturaToplami - iskontoToplami + kdvToplami);

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
        aciklama: invoiceDescription(settings, invoice),
        kur: payloadExchangeRate(invoice),
        // Header totals must match sum of rounded line taxes; stored invoice
        // totals can drift by 0.01 when the UI summed unrounded KDV first.
        faturaToplami,
        iskontoToplami,
        kdvToplami,
        vergiDahilToplam,
        odenecekToplam: vergiDahilToplam,
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

function canSendInvoiceToEnvironment(invoice, environment) {
  if (
    invoice.e_invoice_status === 'manual' ||
    invoice.e_invoice_status === 'manual_sent'
  ) {
    return false;
  }
  if (invoice.e_invoice_status !== 'sent') return true;
  return (
    invoice.e_invoice_environment === 'test' &&
    environment === 'production'
  );
}

async function preserveTransmission(invoice) {
  if (!invoice.e_invoice_uuid || !invoice.e_invoice_environment) return;
  await query(
    `
      insert into public.e_invoice_transmissions (
        invoice_id, environment, e_invoice_number, e_invoice_uuid,
        payload, response, official_data, official_ubl, sent_at, archived_at
      )
      values ($1, $2, $3, $4, $5::jsonb, $6::jsonb, $7::jsonb, $8, $9, $10)
      on conflict (invoice_id, environment, e_invoice_uuid) do nothing
    `,
    [
      invoice.id,
      invoice.e_invoice_environment,
      invoice.e_invoice_number,
      invoice.e_invoice_uuid,
      JSON.stringify(invoice.e_invoice_payload || null),
      JSON.stringify(invoice.e_invoice_response || null),
      JSON.stringify(invoice.e_invoice_official_data || null),
      invoice.e_invoice_official_ubl,
      invoice.e_invoice_sent_at,
      invoice.e_invoice_archived_at,
    ],
  );
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

function validateRegisteredBranch(settings, branches) {
  const configured = cleanText(settings.seller_branch_code).toUpperCase();
  const environmentLabel =
    settings.environment === 'production' ? 'canlı' : 'test';
  const registered = [...branches].sort();

  if (!registered.length) {
    throw new Error(
      `Maliye ${environmentLabel} sisteminde bu VKN için aktif şube bulunamadı. ` +
        'Önce Maliye e-Fatura sisteminde bir şube oluşturun, ardından E-Fatura > Ayarlar bölümündeki Şube Kod alanını güncelleyin.',
    );
  }
  if (!registered.includes(configured)) {
    throw new Error(
      `Şube kodu Maliye ${environmentLabel} sisteminde kayıtlı değil: ${cleanText(settings.seller_branch_code)}. ` +
        `Kayıtlı şube kodları: ${registered.join(', ')}. ` +
        'E-Fatura > Ayarlar bölümündeki Şube Kod alanını kayıtlı kodlardan biriyle güncelleyin.',
    );
  }
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

const eInvoicePdfBucket = 'service-images';
const localPdfBucket = 'local';

/** Electron / yerel API: bulut depolama olmadan PDF üret. */
function preferLocalPdfMode() {
  if (String(process.env.DISABLE_SUPABASE || '').trim().toLowerCase() === 'true') {
    return true;
  }
  if (String(process.env.MICROVISE_LOCAL_ORIGIN || '').trim()) {
    return true;
  }
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = String(
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  ).trim();
  return !url || !key;
}

function hasSupabaseStorageConfig() {
  if (String(process.env.DISABLE_SUPABASE || '').trim().toLowerCase() === 'true') {
    return false;
  }
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = String(
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  ).trim();
  return Boolean(url && key);
}

function supabaseStorageConfig() {
  const url = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
  const key = String(
    process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
  ).trim();
  if (!url || !key) {
    throw new Error('SUPABASE_URL ve SUPABASE_SERVICE_ROLE_KEY zorunludur.');
  }
  return { url, key };
}

function buildLocalOpenPdfUrl(absolutePath) {
  const filePath = String(absolutePath || '').trim();
  if (!filePath) return null;
  const pathQuery = `/api/_local/open-pdf?path=${encodeURIComponent(filePath)}`;
  const localOrigin = String(process.env.MICROVISE_LOCAL_ORIGIN || '').trim();
  if (localOrigin) {
    return `${localOrigin.replace(/\/$/, '')}${pathQuery}`;
  }
  return pathQuery;
}

function storageHeaders(key) {
  return {
    apikey: key,
    authorization: key.startsWith('sb_') ? key : `Bearer ${key}`,
  };
}

function safePdfFilenamePart(value, fallback = 'fatura') {
  const cleaned = String(value || '')
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'I')
    .replace(/ğ/g, 'g')
    .replace(/Ğ/g, 'G')
    .replace(/ü/g, 'u')
    .replace(/Ü/g, 'U')
    .replace(/ş/g, 's')
    .replace(/Ş/g, 'S')
    .replace(/ö/g, 'o')
    .replace(/Ö/g, 'O')
    .replace(/ç/g, 'c')
    .replace(/Ç/g, 'C')
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
    .slice(0, 80);
  return cleaned || fallback;
}

function buildEInvoicePdfFileName(invoice) {
  const invoiceNumber = safePdfFilenamePart(
    localInvoiceNumber(invoice?.e_invoice_number || invoice?.invoice_number),
    'fatura',
  );
  const customerName = safePdfFilenamePart(
    invoice?.customer_name ||
      invoice?.customer?.name ||
      invoice?.customers?.name,
    'cari',
  );
  return `${invoiceNumber}_${customerName}.pdf`;
}

async function uploadEInvoicePdf({ invoiceId, invoice, verificationCode, pdf }) {
  const { url, key } = supabaseStorageConfig();
  const fileName = buildEInvoicePdfFileName(invoice);
  const safeCode = String(verificationCode || '')
    .replace(/[^a-zA-Z0-9-]/g, '')
    .slice(0, 36);
  const objectPath = `e-invoices/${invoiceId}/${fileName}`;
  const uploadUrl = `${url}/storage/v1/object/${eInvoicePdfBucket}/${objectPath}`;
  const response = await fetch(uploadUrl, {
    method: 'POST',
    headers: {
      ...storageHeaders(key),
      'content-type': 'application/pdf',
      'cache-control': '31536000',
      'x-upsert': 'true',
      'x-content-disposition': `attachment; filename="${fileName}"`,
    },
    body: pdf,
  });
  if (!response.ok) {
    // Eski UUID yollarıyla çakışmayı önlemek için kodlu yola düş.
    const fallbackPath = `e-invoices/${invoiceId}/${safeCode || 'e-fatura'}_${fileName}`;
    const fallbackUrl = `${url}/storage/v1/object/${eInvoicePdfBucket}/${fallbackPath}`;
    const fallback = await fetch(fallbackUrl, {
      method: 'POST',
      headers: {
        ...storageHeaders(key),
        'content-type': 'application/pdf',
        'cache-control': '31536000',
        'x-upsert': 'true',
        'x-content-disposition': `attachment; filename="${fileName}"`,
      },
      body: pdf,
    });
    if (!fallback.ok) {
      throw new Error(
        `E-fatura PDF yüklenemedi: ${response.status} ${await response.text()}`,
      );
    }
    return {
      bucket: eInvoicePdfBucket,
      path: fallbackPath,
      fileName,
      sha256: crypto.createHash('sha256').update(pdf).digest('hex'),
    };
  }
  return {
    bucket: eInvoicePdfBucket,
    path: objectPath,
    fileName,
    sha256: crypto.createHash('sha256').update(pdf).digest('hex'),
  };
}

async function createEInvoicePdfSignedUrl(bucket, objectPath, downloadName) {
  const { url, key } = supabaseStorageConfig();
  const response = await fetch(
    `${url}/storage/v1/object/sign/${bucket}/${objectPath}`,
    {
      method: 'POST',
      headers: {
        ...storageHeaders(key),
        'content-type': 'application/json',
      },
      body: JSON.stringify({
        expiresIn: 900,
        ...(downloadName ? { download: downloadName } : {}),
      }),
    },
  );
  const result = await response.json().catch(() => ({}));
  if (!response.ok || !result.signedURL) {
    const detail =
      result?.message ||
      result?.error ||
      result?.msg ||
      (typeof result === 'string' ? result : '');
    throw new Error(
      `E-fatura PDF bağlantısı oluşturulamadı: ${response.status}${
        detail ? ` ${detail}` : ''
      }`,
    );
  }
  let signed = `${url}/storage/v1${result.signedURL}`;
  if (downloadName && !/[?&]download=/.test(signed)) {
    signed += `${signed.includes('?') ? '&' : '?'}download=${encodeURIComponent(downloadName)}`;
  }
  return signed;
}

function humanizeArchiveError(message) {
  const raw = String(message || '').trim();
  if (!raw) return 'PDF oluşturulamadı.';
  const lower = raw.toLowerCase();
  if (
    lower.includes('invalid user credentials') ||
    lower.includes('invalid login credentials') ||
    lower.includes('invalid_grant')
  ) {
    return (
      'E-fatura API oturumu açılamadı (kullanıcı/şifre). ' +
      'Ayarları kontrol edin; arşivlenmiş faturalarda PDF yerel veriden üretilebilir.'
    );
  }
  if (
    lower.includes('supabase') ||
    lower.includes('service_role') ||
    lower.includes('pdf yüklenemedi') ||
    lower.includes('pdf bağlantısı')
  ) {
    return (
      'PDF depolama yapılandırması hatalı veya eksik. ' +
      'SUPABASE_SERVICE_ROLE_KEY kontrol edin; mobil için PDF baytları doğrudan döndürülür.'
    );
  }
  return raw;
}

function invoiceHasOfficialArchive(invoice) {
  return Boolean(invoice?.e_invoice_official_data);
}

/** Resmi arşiv, gönderim payload'ı veya CRM kalemleri — Maliye olmadan PDF için yeterli. */
function invoiceHasLocalPdfSource(invoice) {
  if (!invoice) return false;
  if (invoice.e_invoice_official_data) return true;
  if (invoice.e_invoice_payload) return true;
  return Array.isArray(invoice.items) && invoice.items.length > 0;
}

function resolveLocalOfficialSource(invoice) {
  if (invoice?.e_invoice_official_data) {
    return {
      officialData: invoice.e_invoice_official_data,
      officialUbl: invoice.e_invoice_official_ubl || '',
      from: 'official',
    };
  }
  if (invoice?.e_invoice_payload) {
    return {
      officialData:
        invoice.e_invoice_payload?.faturalar?.[0] || invoice.e_invoice_payload,
      officialUbl: cleanText(invoice.e_invoice_official_ubl) || '',
      from: 'payload',
    };
  }
  return {
    officialData: null,
    officialUbl: cleanText(invoice?.e_invoice_official_ubl) || '',
    from: 'crm',
  };
}

/**
 * force = PDF yeniden üret (Maliye değil).
 * refreshOfficial yalnızca açıkça true ise veya yerel kaynak yoksa (bulut) true.
 * Electron/local: asla Keycloak çağırmaz (refreshOfficial açıkça true değilse).
 */
function shouldRefreshOfficialForArchive({
  refreshOfficial,
  invoice,
  localOnly,
}) {
  if (refreshOfficial === true) return true;
  if (localOnly) return false;
  return !invoiceHasLocalPdfSource(invoice);
}

async function deliverBuiltArchivePdf({
  invoiceId,
  invoice,
  settings,
  officialData,
  officialUbl,
  verificationCode,
  includePdf = false,
}) {
  const pdf = await buildEInvoiceArchivePdf({
    invoice,
    settings,
    officialData,
    verificationCode,
    environment: settings.environment,
  });
  const fileName = buildEInvoicePdfFileName(invoice);
  const sha256 = crypto.createHash('sha256').update(pdf).digest('hex');
  const localOnly = preferLocalPdfMode();

  let storedPdf = null;
  let localPdfPath = null;
  let storageError = null;

  if (localOnly) {
    localPdfPath = writeLocalEInvoicePdf(pdf, fileName);
    storedPdf = {
      bucket: localPdfBucket,
      path: localPdfPath,
      fileName,
      sha256,
    };
  } else if (hasSupabaseStorageConfig()) {
    try {
      storedPdf = await uploadEInvoicePdf({
        invoiceId,
        invoice,
        verificationCode,
        pdf,
      });
      try {
        localPdfPath = writeLocalEInvoicePdf(pdf, storedPdf.fileName);
      } catch (_) {
        // Yerel kopya isteğe bağlı; depolama asıl kaynaktır.
      }
    } catch (error) {
      storageError = error;
    }
  } else {
    // Bulut depolama yok: yine de temp PDF + base64 ile açılabilir olsun.
    try {
      localPdfPath = writeLocalEInvoicePdf(pdf, fileName);
      storedPdf = {
        bucket: localPdfBucket,
        path: localPdfPath,
        fileName,
        sha256,
      };
    } catch (error) {
      storageError = error;
    }
  }

  await query(
    `
      update public.invoices
      set e_invoice_official_data = coalesce($2::jsonb, e_invoice_official_data),
          e_invoice_official_ubl = coalesce($3, e_invoice_official_ubl),
          e_invoice_pdf_bucket = coalesce($4, e_invoice_pdf_bucket),
          e_invoice_pdf_path = coalesce($5, e_invoice_pdf_path),
          e_invoice_pdf_sha256 = coalesce($6, e_invoice_pdf_sha256),
          e_invoice_pdf_created_at = case
            when $4 is null then e_invoice_pdf_created_at
            else now()
          end,
          e_invoice_archived_at = coalesce(e_invoice_archived_at, now()),
          e_invoice_archive_error = $7,
          updated_at = now()
      where id = $1
    `,
    [
      invoiceId,
      officialData == null ? null : JSON.stringify(officialData),
      officialUbl || null,
      storedPdf?.bucket || null,
      storedPdf?.path || null,
      storedPdf?.sha256 || null,
      storageError ? humanizeArchiveError(storageError.message) : null,
    ],
  );

  let pdfUrl = buildLocalOpenPdfUrl(localPdfPath);
  if (!pdfUrl && storedPdf && !localOnly && hasSupabaseStorageConfig()) {
    try {
      pdfUrl = await createEInvoicePdfSignedUrl(
        storedPdf.bucket,
        storedPdf.path,
        storedPdf.fileName,
      );
    } catch (_) {
      // İmzalı URL isteğe bağlı; pdfBase64 yedek olarak döner.
    }
  }

  // Electron ve mobil: bayt yedeği her zaman tercih edilir.
  const shouldIncludePdf =
    includePdf === true ||
    localOnly ||
    !pdfUrl ||
    Boolean(storageError);
  if (!pdfUrl && !shouldIncludePdf) {
    throw new Error(
      localOnly
        ? 'Yerel PDF oluşturuldu ancak açılamadı (MICROVISE_LOCAL_ORIGIN / temp yolu).'
        : 'PDF bağlantısı oluşturulamadı.',
    );
  }

  return {
    archived: true,
    archivedAt: new Date().toISOString(),
    pdfUrl: pdfUrl || null,
    pdfFileName: fileName,
    localPdfPath,
    bucket: storedPdf?.bucket || null,
    path: storedPdf?.path || null,
    ...(shouldIncludePdf ? { pdfBase64: pdf.toString('base64') } : {}),
    ...(storageError
      ? { storageWarning: humanizeArchiveError(storageError.message) }
      : {}),
  };
}

async function archiveOfficialInvoice({
  invoiceId,
  settings,
  verificationCode,
  token,
  refreshOfficial = false,
  includePdf = false,
  invoice: invoiceHint = null,
}) {
  try {
    const invoice = invoiceHint || (await fetchInvoice(invoiceId));
    if (!invoice) {
      throw new Error('Fatura bulunamadı.');
    }

    const code = cleanText(verificationCode || invoice.e_invoice_uuid);
    const localOnly = preferLocalPdfMode();
    const localSource = resolveLocalOfficialSource(invoice);
    let officialData = localSource.officialData;
    let officialUbl = localSource.officialUbl;
    let maliyeWarning = null;

    const mustHitMaliye = shouldRefreshOfficialForArchive({
      refreshOfficial,
      invoice,
      localOnly,
    });

    if (mustHitMaliye) {
      try {
        const archive = await fetchOfficialInvoiceArchive({
          settings,
          verificationCode: code,
          token: token || (await tokenFor(settings)),
        });
        officialData = archive.data;
        officialUbl = archive.ubl;
      } catch (maliyeError) {
        // PDF açma: CRM/payload/resmi cache varken Keycloak hatası engel olmamalı.
        if (!invoiceHasLocalPdfSource(invoice)) {
          throw maliyeError;
        }
        const fallback = resolveLocalOfficialSource(invoice);
        officialData = fallback.officialData;
        officialUbl = fallback.officialUbl;
        maliyeWarning = humanizeArchiveError(maliyeError.message);
      }
    } else if (!invoiceHasLocalPdfSource(invoice)) {
      throw new Error(
        'PDF için kayıtlı e-fatura verisi yok. Önce gönderim/arşiv gerekir.',
      );
    }

    const delivered = await deliverBuiltArchivePdf({
      invoiceId,
      invoice,
      settings,
      officialData,
      officialUbl,
      verificationCode: code,
      includePdf: includePdf || localOnly,
    });
    return maliyeWarning
      ? { ...delivered, storageWarning: delivered.storageWarning || maliyeWarning }
      : delivered;
  } catch (error) {
    const friendly = humanizeArchiveError(error.message);
    await query(
      `
        update public.invoices
        set e_invoice_archive_error = $2,
            updated_at = now()
        where id = $1
      `,
      [invoiceId, friendly],
    );
    return { archived: false, error: friendly };
  }
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

async function archiveOfficialInvoiceWithRetry(
  args,
  { attempts = 4, delayMs = 1200 } = {},
) {
  let last = { archived: false, error: 'Arşivleme denemesi yapılmadı.' };
  for (let attempt = 1; attempt <= attempts; attempt += 1) {
    if (attempt > 1) await sleep(delayMs * (attempt - 1));
    last = await archiveOfficialInvoice(args);
    if (last.archived) {
      return { ...last, attempts: attempt };
    }
  }
  return { ...last, attempts };
}

async function archiveAfterSuccessfulSend({
  invoiceId,
  settings,
  verificationCode,
  token,
}) {
  if (settings.environment !== 'production') {
    return {
      archived: false,
      skipped: true,
      reason: 'test_environment',
    };
  }
  // Gönderim sonrası: Maliye'den resmi arşivi çek (token elde var).
  return archiveOfficialInvoiceWithRetry({
    invoiceId,
    settings,
    verificationCode,
    token,
    refreshOfficial: true,
  });
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
  validateRegisteredBranch(settings, branches);
  const errors = [];
  for (const invoice of payload.faturalar || []) {
    if (invoiceTypes.size && !invoiceTypes.has(String(invoice.faturaTuru).toUpperCase())) {
      errors.push(`Fatura türü Maliye kod listesinde yok: ${invoice.faturaTuru}.`);
    }
    if (currencies.size && !currencies.has(String(invoice.paraBirimi).toUpperCase())) {
      errors.push(`Para birimi Maliye kod listesinde yok: ${invoice.paraBirimi}.`);
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

      const includePdf = body.includePdf === true;
      const localOnly = preferLocalPdfMode();
      // force / includePdf: PDF yeniden üret. Maliye yalnızca refreshOfficial:true.
      const refreshOfficial = shouldRefreshOfficialForArchive({
        refreshOfficial: body.refreshOfficial === true,
        invoice,
        localOnly,
      });
      const rebuildPdf =
        body.force === true ||
        includePdf === true ||
        !cleanText(invoice.e_invoice_pdf_bucket) ||
        !cleanText(invoice.e_invoice_pdf_path);

      if (
        !rebuildPdf &&
        !refreshOfficial &&
        invoiceHasLocalPdfSource(invoice) &&
        cleanText(invoice.e_invoice_pdf_bucket) &&
        cleanText(invoice.e_invoice_pdf_path)
      ) {
        const pdfFileName = buildEInvoicePdfFileName(invoice);
        const bucket = cleanText(invoice.e_invoice_pdf_bucket);
        const objectPath = cleanText(invoice.e_invoice_pdf_path);

        // Yerel arşiv: temp dosya varsa doğrudan aç; yoksa CRM verisinden üret.
        if (localOnly || bucket === localPdfBucket) {
          let localPdfPath = null;
          let pdfBuffer = null;
          if (
            bucket === localPdfBucket &&
            objectPath &&
            fs.existsSync(objectPath) &&
            fs.statSync(objectPath).isFile()
          ) {
            localPdfPath = objectPath;
            if (includePdf || localOnly) {
              pdfBuffer = fs.readFileSync(objectPath);
            }
          } else {
            const settingsForPdf = await getSettings();
            const localSource = resolveLocalOfficialSource(invoice);
            pdfBuffer = await buildEInvoiceArchivePdf({
              invoice,
              settings: settingsForPdf,
              officialData: localSource.officialData,
              verificationCode: invoice.e_invoice_uuid,
              environment:
                invoice.e_invoice_environment === 'production'
                  ? 'production'
                  : 'test',
            });
            localPdfPath = writeLocalEInvoicePdf(pdfBuffer, pdfFileName);
            await query(
              `
                update public.invoices
                set e_invoice_pdf_bucket = $2,
                    e_invoice_pdf_path = $3,
                    e_invoice_pdf_sha256 = $4,
                    e_invoice_pdf_created_at = now(),
                    updated_at = now()
                where id = $1
              `,
              [
                invoiceId,
                localPdfBucket,
                localPdfPath,
                crypto.createHash('sha256').update(pdfBuffer).digest('hex'),
              ],
            );
          }
          const pdfUrl = buildLocalOpenPdfUrl(localPdfPath);
          if (!pdfUrl && !(pdfBuffer && (includePdf || localOnly))) {
            return badRequest(
              req,
              res,
              'Yerel PDF açılamadı (MICROVISE_LOCAL_ORIGIN / temp yolu).',
            );
          }
          return ok(req, res, {
            ok: true,
            archived: true,
            alreadyArchived: true,
            archivedAt: invoice.e_invoice_archived_at,
            pdfUrl: pdfUrl || null,
            pdfFileName,
            localPdfPath,
            ...((includePdf || localOnly) && pdfBuffer
              ? { pdfBase64: pdfBuffer.toString('base64') }
              : {}),
          });
        }

        if (hasSupabaseStorageConfig()) {
          try {
            const pdfUrl = await createEInvoicePdfSignedUrl(
              bucket,
              objectPath,
              pdfFileName,
            );
            return ok(req, res, {
              ok: true,
              archived: true,
              alreadyArchived: true,
              archivedAt: invoice.e_invoice_archived_at,
              pdfUrl,
              pdfFileName,
            });
          } catch (_) {
            // İmzalı URL başarısız → kayıtlı CRM verisinden PDF üret.
          }
        }
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
        refreshOfficial,
        includePdf: includePdf || localOnly,
        invoice,
      });
      return ok(req, res, { ok: archive.archived, ...archive });
    }

    if (action === 'prepare' || action === 'send') {
      const invoiceId = String(body.invoiceId || '').trim();
      if (!invoiceId) return badRequest(req, res, 'invoiceId zorunludur.');
      const settings = await getSettings();
      const invoice = await fetchInvoice(invoiceId);
      if (!invoice) return badRequest(req, res, 'Fatura bulunamadı.');
      const testToProduction =
        invoice.e_invoice_status === 'sent' &&
        invoice.e_invoice_environment === 'test' &&
        settings.environment === 'production';
      if (!canSendInvoiceToEnvironment(invoice, settings.environment)) {
        if (
          invoice.e_invoice_status === 'manual' ||
          invoice.e_invoice_status === 'manual_sent'
        ) {
          return badRequest(
            req,
            res,
            invoice.e_invoice_status === 'manual_sent'
              ? 'Bu fatura manuel gönderildi olarak işaretli. API’ye gönderilmez.'
              : 'Bu fatura manuel kesildi olarak işaretli. API’ye gönderilmez.',
          );
        }
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
      const payloadInvoice = testToProduction
        ? { ...invoice, e_invoice_number: null, e_invoice_uuid: null }
        : invoice;
      const reserved = await resolveInvoiceNumber({
        settings,
        invoice: payloadInvoice,
        invoiceId,
      });
      let built = buildPayload({
        settings,
        invoice: payloadInvoice,
        number: reserved.number,
      });

      if (action === 'prepare') {
        if (testToProduction) {
          return ok(req, res, {
            ok: true,
            mode: 'prepare',
            promotion: 'test_to_production',
            invoiceNumber: built.number,
            uuid: built.uuid,
            payload: built.payload,
          });
        }
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

      if (testToProduction) await preserveTransmission(invoice);
      const claimed = await query(
        `
          update public.invoices
          set e_invoice_number = $2,
              e_invoice_uuid = $3,
              e_invoice_status = 'prepared',
              e_invoice_environment = $4,
              e_invoice_payload = $5::jsonb,
              e_invoice_official_data = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_official_data
              end,
              e_invoice_official_ubl = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_official_ubl
              end,
              e_invoice_pdf_bucket = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_pdf_bucket
              end,
              e_invoice_pdf_path = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_pdf_path
              end,
              e_invoice_pdf_sha256 = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_pdf_sha256
              end,
              e_invoice_pdf_created_at = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_pdf_created_at
              end,
              e_invoice_archived_at = case
                when e_invoice_environment = 'test' and $4 = 'production' then null
                else e_invoice_archived_at
              end,
              e_invoice_archive_error = null,
              e_invoice_error = null,
              e_invoice_sending_at = now(),
              updated_at = now()
          where id = $1
            and (
              e_invoice_status is distinct from 'sent'
              or (
                e_invoice_status = 'sent'
                and e_invoice_environment = 'test'
                and $4 = 'production'
              )
            )
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
        // Maliye numarayı kullanılmış sayarsa bir sonraki boş numarayla yeniden dener.
        const collided = [];
        let sent = null;
        for (let attempt = 0; ; attempt += 1) {
          try {
            sent = await sendToMaliye({ settings, payload: built.payload });
            break;
          } catch (sendError) {
            if (attempt >= 4 || !isNumberAlreadyUsedError(sendError)) throw sendError;
            collided.push(built.number);
            const retry = await resolveInvoiceNumber({
              settings,
              invoice: payloadInvoice,
              invoiceId,
              skip: collided,
            });
            if (retry.number === built.number) throw sendError;
            built = buildPayload({
              settings,
              invoice: { ...payloadInvoice, e_invoice_number: null },
              number: retry.number,
            });
            built.uuid = payloadInvoice.e_invoice_uuid || built.uuid;
            await query(
              `
                update public.invoices
                set e_invoice_number = $2,
                    e_invoice_payload = $3::jsonb,
                    updated_at = now()
                where id = $1
              `,
              [invoiceId, built.number, JSON.stringify(built.payload)],
            );
          }
        }
        const response = sent.response;
        const officialNumber = officialNumberFromResponse(response, built.number);
        await query(
          `
            update public.invoices
            set e_invoice_status = 'sent',
                e_invoice_number = $2,
                e_invoice_response = $3::jsonb,
                e_invoice_error = null,
                e_invoice_sent_at = now(),
                e_invoice_sending_at = null,
                updated_at = now()
            where id = $1
          `,
          [invoiceId, officialNumber, JSON.stringify(response)],
        );
        const renamed = await applyOfficialInvoiceNumber({
          invoiceId,
          officialNumber,
          currentInvoiceNumber: invoice.invoice_number,
          erpInvoiceNumber: invoice.erp_invoice_number,
          environment: settings.environment,
        });
        const nextColumn =
          invoice.invoice_type === 'purchase'
            ? 'next_purchase_number'
            : 'next_sales_number';
        const usedSerial = serialFromNumber(
          officialNumber,
          invoiceNumberPrefix(settings, payloadInvoice),
        );
        await query(
          `update public.e_invoice_settings set ${nextColumn} = greatest(${nextColumn} + 1, $2::bigint), last_sync_at = now(), updated_at = now() where id = $1`,
          [settings.id, usedSerial ? usedSerial + 1 : 1],
        );
        const archive = await archiveAfterSuccessfulSend({
          invoiceId,
          settings,
          verificationCode: built.uuid,
          token: sent.token,
        });
        return ok(req, res, {
          ok: true,
          mode: 'send',
          invoiceNumber: officialNumber,
          localInvoiceNumber: renamed.invoiceNumber || invoice.invoice_number,
          erpInvoiceNumber: renamed.erpInvoiceNumber || invoice.erp_invoice_number,
          renamed,
          uuid: built.uuid,
          response,
          archive,
        });
      } catch (error) {
        if (testToProduction) {
          await query(
            `
              update public.invoices
              set e_invoice_number = $2,
                  e_invoice_uuid = $3,
                  e_invoice_status = 'sent',
                  e_invoice_environment = 'test',
                  e_invoice_payload = $4::jsonb,
                  e_invoice_response = $5::jsonb,
                  e_invoice_official_data = $6::jsonb,
                  e_invoice_official_ubl = $7,
                  e_invoice_archived_at = $8,
                  e_invoice_sent_at = $9,
                  e_invoice_error = $10,
                  e_invoice_sending_at = null,
                  updated_at = now()
              where id = $1
            `,
            [
              invoiceId,
              invoice.e_invoice_number,
              invoice.e_invoice_uuid,
              JSON.stringify(invoice.e_invoice_payload || null),
              JSON.stringify(invoice.e_invoice_response || null),
              JSON.stringify(invoice.e_invoice_official_data || null),
              invoice.e_invoice_official_ubl,
              invoice.e_invoice_archived_at,
              invoice.e_invoice_sent_at,
              `Canlı gönderim başarısız: ${error.message}`,
            ],
          );
        } else {
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
        }
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
  canSendInvoiceToEnvironment,
  buildPayload,
  assertSuccessfulMaliyeResponse,
  validatePayloadAgainstApi,
  validateRegisteredBranch,
  urlsForEnvironment,
  applyRegisteredSupplierIdentity,
  archiveAfterSuccessfulSend,
  isNumberAlreadyUsedError,
  serialFromNumber,
  invoiceNumberPrefix,
  officialNumberFromResponse,
  localInvoiceNumber,
  applyOfficialInvoiceNumber,
  invoiceHasLocalPdfSource,
  resolveLocalOfficialSource,
  shouldRefreshOfficialForArchive,
  preferLocalPdfMode,
};
