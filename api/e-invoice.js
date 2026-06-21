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
      token_url text not null default 'https://keycloak.maliye.gov.ct.tr/realms/vergi-stage/protocol/openid-connect/token',
      client_id text not null default 'efatura-frontend',
      username text,
      password text,
      seller_vkn text not null default '620009058',
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
      'https://keycloak.maliye.gov.ct.tr/realms/vergi-stage/protocol/openid-connect/token',
      'efatura-frontend',
      '620009058',
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
      add column if not exists e_invoice_error text,
      add column if not exists e_invoice_sent_at timestamptz
  `);
}

function cleanText(value) {
  const text = String(value ?? '').trim();
  return text.length ? text : null;
}

function normalizeDigits(value) {
  const digits = String(value ?? '').replace(/[^0-9]/g, '');
  return digits || null;
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

function partyFromSettings(settings) {
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
    vkn: normalizeDigits(settings.seller_vkn),
  };
}

function partyFromCustomer(customer) {
  const address = cleanText(customer.address) || cleanText(customer.full_address);
  return {
    ulkeKodu: cleanText(customer.country_code) || 'XCT',
    ulke: cleanText(customer.country) || 'Kuzey Kıbrıs Türk Cumhuriyeti',
    sehir: cleanText(customer.city) || null,
    adresSatir1: address,
    adresSatir2: cleanText(customer.address_line2),
    telefon: cleanText(customer.phone1) || cleanText(customer.phone),
    email: cleanText(customer.email),
    webSitesi: cleanText(customer.website),
    unvan: cleanText(customer.name),
    vkn:
      normalizeDigits(customer.tax_number) ||
      normalizeDigits(customer.vkn) ||
      normalizeDigits(customer.tckn_ms),
  };
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
  if (invoice.e_invoice_number) return invoice.e_invoice_number;
  const year = new Date(invoice.invoice_date || Date.now()).getFullYear();
  const vkn = normalizeDigits(settings.seller_vkn) || '000000000';
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
    const taxAmount =
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
          vergiOrani: taxRate,
          vergiTutari: taxAmount,
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
        aciklama: cleanText(invoice.notes),
        kur: Number(invoice.exchange_rate || 1),
        faturaToplami: round2(invoice.subtotal),
        iskontoToplami: round2(invoice.discount_total),
        kdvToplami: round2(invoice.tax_total),
        vergiDahilToplam: round2(invoice.grand_total),
        odenecekToplam: round2(invoice.grand_total),
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

  const response = await fetch(settings.token_url, {
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

async function sendToMaliye({ settings, payload }) {
  const token = await tokenFor(settings);
  const vkn = encodeURIComponent(normalizeDigits(settings.seller_vkn) || '');
  const base = String(settings.api_base_url || '').replace(/\/+$/, '');
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
  return json;
}

module.exports = async (req, res) => {
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

    if (action === 'prepare' || action === 'send') {
      const invoiceId = String(body.invoiceId || '').trim();
      if (!invoiceId) return badRequest(req, res, 'invoiceId zorunludur.');
      const settings = await getSettings();
      const invoice = await fetchInvoice(invoiceId);
      if (!invoice) return badRequest(req, res, 'Fatura bulunamadı.');
      if (!Array.isArray(invoice.items) || invoice.items.length === 0) {
        return badRequest(req, res, 'E-fatura için en az bir kalem olmalıdır.');
      }
      const built = buildPayload({ settings, invoice });

      await query(
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
        `,
        [
          invoiceId,
          built.number,
          built.uuid,
          settings.environment,
          JSON.stringify(built.payload),
        ],
      );

      if (action === 'prepare') {
        return ok(req, res, {
          ok: true,
          mode: 'prepare',
          invoiceNumber: built.number,
          uuid: built.uuid,
          payload: built.payload,
        });
      }

      try {
        const response = await sendToMaliye({ settings, payload: built.payload });
        await query(
          `
            update public.invoices
            set e_invoice_status = 'sent',
                e_invoice_response = $2::jsonb,
                e_invoice_error = null,
                e_invoice_sent_at = now(),
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
        return ok(req, res, {
          ok: true,
          mode: 'send',
          invoiceNumber: built.number,
          uuid: built.uuid,
          response,
        });
      } catch (error) {
        await query(
          `
            update public.invoices
            set e_invoice_status = 'failed',
                e_invoice_response = $2::jsonb,
                e_invoice_error = $3,
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
};
