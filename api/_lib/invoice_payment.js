const crypto = require('crypto');
const { query, withTransaction } = require('./db');

const HALKBANK_PROD_GATEWAY_URL = 'https://sanalpos.halkbank.com.tr/fim/est3Dgate';
const HALKBANK_TEST_GATEWAY_URL = 'https://entegrasyon.asseco-see.com.tr/fim/est3Dgate';

let tableReady = false;

function escapeHtml(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/"/g, '&quot;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

function nestpayEscape(value) {
  return String(value ?? '')
    .replace(/\\/g, '\\\\')
    .replace(/\|/g, '\\|');
}

function buildHalkbankHashVer3(params, storeKey) {
  const keys = Object.keys(params).sort((a, b) =>
    a.localeCompare(b, 'en', { sensitivity: 'base' }),
  );
  let hashValue = '';
  for (const key of keys) {
    const lowered = key.toLowerCase();
    if (lowered === 'hash' || lowered === 'encoding') continue;
    hashValue += `${nestpayEscape(params[key] ?? '')}|`;
  }
  hashValue += storeKey;
  const hex = crypto.createHash('sha512').update(hashValue, 'latin1').digest('hex');
  return Buffer.from(hex, 'hex').toString('base64');
}

function normalizeHalkbankStoreType(value) {
  const normalized = String(value || '')
    .trim()
    .toLowerCase()
    .replace(/\s+/g, '_');
  if (!normalized) return '3d';
  if (
    normalized === '3dsecure' ||
    normalized === 'secure3d' ||
    normalized === '3ds'
  ) {
    return '3d';
  }
  if (normalized === '3dpay') return '3d_pay';
  if (
    normalized === '3dhost' ||
    normalized === '3d_host' ||
    normalized === '3dhosting'
  ) {
    return '3d_pay_hosting';
  }
  return normalized;
}

function isHalkbank3DSecureFlow(storeType) {
  return normalizeHalkbankStoreType(storeType) === '3d';
}

function normalizeHalkbankExpiryMonth(value) {
  const digits = String(value || '').replace(/\D/g, '');
  return digits ? digits.slice(-2).padStart(2, '0') : '';
}

function normalizeHalkbankExpiryYear(value) {
  const digits = String(value || '').replace(/\D/g, '');
  if (!digits) return '';
  return digits.length <= 2 ? digits.padStart(2, '0') : digits.slice(-2);
}

function hasHalkbankCardDetails(cardNumber, expireMonth, expireYear, cvc) {
  return Boolean(
    String(cardNumber || '').replace(/\s/g, '') &&
      normalizeHalkbankExpiryMonth(expireMonth) &&
      normalizeHalkbankExpiryYear(expireYear) &&
      String(cvc || '').trim(),
  );
}

/** Microvise Halkbank profili kartlı classic 3d; hosting tipi desteklenmiyor. */
function resolveHalkbankStoreTypeForRequest(configStoreType, hasCardDetails) {
  const normalized = normalizeHalkbankStoreType(configStoreType);
  if (!hasCardDetails) {
    return normalized === '3d' ? '3d_pay_hosting' : normalized;
  }
  if (
    normalized === '3d' ||
    normalized === '3d_pay_hosting' ||
    normalized === '3d_host' ||
    normalized === '3d_pay'
  ) {
    return '3d';
  }
  return normalized || '3d';
}

function xmlEscape(value) {
  return String(value ?? '')
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&apos;');
}

function extractHalkbankXmlValue(xml, tagName) {
  const match = String(xml || '').match(
    new RegExp(`<${tagName}>([\\s\\S]*?)</${tagName}>`, 'i'),
  );
  return match ? match[1].trim() : '';
}

function parseHalkbankApiResponse(xml) {
  return {
    response: extractHalkbankXmlValue(xml, 'Response'),
    procReturnCode: extractHalkbankXmlValue(xml, 'ProcReturnCode'),
    errMsg: extractHalkbankXmlValue(xml, 'ErrMsg'),
    authCode: extractHalkbankXmlValue(xml, 'AuthCode'),
    hostRefNum: extractHalkbankXmlValue(xml, 'HostRefNum'),
    transId: extractHalkbankXmlValue(xml, 'TransId'),
    orderId: extractHalkbankXmlValue(xml, 'OrderId'),
  };
}

function getHalkbankCallbackField(payload, ...keys) {
  for (const key of keys) {
    const value = payload?.[key];
    if (typeof value === 'string' && value.trim() !== '') return value.trim();
    if (value != null && String(value).trim() !== '') return String(value).trim();
  }
  return '';
}

function isSuccessfulMdStatus(value) {
  return ['1', '2', '3', '4'].includes(String(value || '').trim());
}

function getHalkbankModeValue(mode) {
  return String(mode || '').trim().toUpperCase() === 'TEST' ? 'T' : 'P';
}

function getHalkbankApiUrls(config) {
  let baseUrl =
    typeof config?.apiUrl === 'string' && config.apiUrl.trim() !== ''
      ? config.apiUrl.trim()
      : typeof config?.gatewayUrl === 'string' &&
          config.gatewayUrl.includes('/fim/est3Dgate')
        ? config.gatewayUrl.replace('/fim/est3Dgate', '/fim/api')
        : config?.mode === 'TEST'
          ? 'https://entegrasyon.asseco-see.com.tr/fim/api'
          : 'https://sanalpos.halkbank.com.tr/fim/api';
  baseUrl = baseUrl.replace(/\/fim\/cc5xml\/?$/i, '/fim/api').replace(/\/+$/, '');
  return [baseUrl];
}

function resolveHalkbankApiCredentials(config) {
  return {
    apiName: String(config?.apiName || config?.provisionUser || '').trim(),
    apiPassword: String(
      config?.apiPassword || config?.provisionPassword || '',
    ).trim(),
  };
}

function buildHalkbank3DSecureApiRequestXml(payload, config, variant = 'nestpay') {
  const amount = Number(payload?.amount || 0).toFixed(2);
  const currency = getHalkbankCallbackField(payload, 'currency') || '949';
  const installment = getHalkbankCallbackField(
    payload,
    'Instalment',
    'instalment',
    'taksit',
  );
  const orderId = getHalkbankCallbackField(
    payload,
    'oid',
    'orderid',
    'Oid',
    'OrderId',
  );
  const md = getHalkbankCallbackField(payload, 'md', 'MD');
  const xid = getHalkbankCallbackField(payload, 'xid', 'XID');
  const eci = getHalkbankCallbackField(payload, 'eci', 'ECI');
  const cavv = getHalkbankCallbackField(payload, 'cavv', 'CAVV');
  const clientIp = getHalkbankCallbackField(
    payload,
    'clientIp',
    'ClientIp',
    'ip',
  );
  const { apiName, apiPassword } = resolveHalkbankApiCredentials(config);
  const mode = getHalkbankModeValue(config.mode);

  if (variant === 'legacy-md') {
    return `<?xml version="1.0" encoding="UTF-8"?>
<CC5Request>
  <Name>${xmlEscape(apiName)}</Name>
  <Password>${xmlEscape(apiPassword)}</Password>
  <ClientId>${xmlEscape(config.merchantId)}</ClientId>
  <Mode>${xmlEscape(mode)}</Mode>
  <Type>Auth</Type>
  ${clientIp ? `<IPAddress>${xmlEscape(clientIp)}</IPAddress>` : ''}
  <OrderId>${xmlEscape(orderId)}</OrderId>
  <Total>${xmlEscape(amount)}</Total>
  <Currency>${xmlEscape(currency)}</Currency>
  <Instalment>${xmlEscape(installment)}</Instalment>
  <PayerTxnId>${xmlEscape(xid)}</PayerTxnId>
  <PayerSecurityLevel>${xmlEscape(eci)}</PayerSecurityLevel>
  <PayerAuthenticationCode>${xmlEscape(cavv)}</PayerAuthenticationCode>
  <CardholderPresentCode>13</CardholderPresentCode>
  <Md>${xmlEscape(md)}</Md>
</CC5Request>`;
  }

  return `<?xml version="1.0" encoding="UTF-8"?>
<CC5Request>
  <Name>${xmlEscape(apiName)}</Name>
  <Password>${xmlEscape(apiPassword)}</Password>
  <ClientId>${xmlEscape(config.merchantId)}</ClientId>
  <Type>Auth</Type>
  <OrderId>${xmlEscape(orderId)}</OrderId>
  <Total>${xmlEscape(amount)}</Total>
  <Currency>${xmlEscape(currency)}</Currency>
  <Number>${xmlEscape(md)}</Number>
  <PayerTxnId>${xmlEscape(xid)}</PayerTxnId>
  <PayerSecurityLevel>${xmlEscape(eci)}</PayerSecurityLevel>
  <PayerAuthenticationCode>${xmlEscape(cavv)}</PayerAuthenticationCode>
</CC5Request>`;
}

async function finalizeHalkbank3DSecurePayment(payload, config) {
  const { apiName, apiPassword } = resolveHalkbankApiCredentials(config);
  if (!apiName || !apiPassword) {
    return {
      approved: false,
      message: 'Halkbank API kullanıcı bilgisi eksik (API_NAME / API_PASSWORD).',
    };
  }

  const variants = ['nestpay', 'legacy-md'];
  let lastMessage = 'Halkbank API isteği başarısız';

  for (const apiUrl of getHalkbankApiUrls(config)) {
    for (const variant of variants) {
      const xml = buildHalkbank3DSecureApiRequestXml(payload, config, variant);
      const body = new URLSearchParams({ DATA: xml }).toString();
      try {
        const response = await fetch(apiUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/x-www-form-urlencoded; charset=utf-8',
            Accept: 'application/xml, text/xml, */*',
          },
          body,
        });
        const rawXml = await response.text();
        const parsed = parseHalkbankApiResponse(rawXml);
        const approved =
          parsed.procReturnCode === '00' ||
          parsed.procReturnCode === '0000' ||
          String(parsed.response || '').toUpperCase() === 'APPROVED';
        if (approved) {
          return { approved: true, parsed, message: parsed.errMsg || 'OK' };
        }
        lastMessage =
          parsed.errMsg || `Halkbank API HTTP ${response.status}`;
      } catch (error) {
        lastMessage = error?.message || lastMessage;
      }
    }
  }

  return { approved: false, message: lastMessage };
}

function normalizeProvider(value) {
  const normalized =
    typeof value === 'string' && value.trim() !== ''
      ? value.trim().toLowerCase()
      : 'halkbank';
  if (normalized === 'garanti') return 'garanti';
  return 'halkbank';
}

function getPosConfigFromEnv() {
  const provider = normalizeProvider(
    process.env.INVOICE_PAYMENT_PROVIDER ||
      process.env.LICENSE_PAYMENT_PROVIDER ||
      process.env.HALKBANK_PROVIDER ||
      'halkbank',
  );
  return {
    provider,
    merchantId:
      process.env.INVOICE_PAYMENT_MERCHANT_ID ||
      process.env.LICENSE_PAYMENT_MERCHANT_ID ||
      process.env.HALKBANK_CLIENT_ID ||
      process.env.HALKBANK_MERCHANT_ID ||
      '',
    storeKey:
      process.env.INVOICE_PAYMENT_STORE_KEY ||
      process.env.LICENSE_PAYMENT_STORE_KEY ||
      process.env.HALKBANK_STORE_KEY ||
      '',
    terminalId:
      process.env.INVOICE_PAYMENT_TERMINAL_ID ||
      process.env.LICENSE_PAYMENT_TERMINAL_ID ||
      '',
    provisionUser:
      process.env.INVOICE_PAYMENT_PROVISION_USER ||
      process.env.LICENSE_PAYMENT_PROVISION_USER ||
      '',
    provisionPassword:
      process.env.INVOICE_PAYMENT_PROVISION_PASSWORD ||
      process.env.LICENSE_PAYMENT_PROVISION_PASSWORD ||
      '',
    gatewayUrl:
      process.env.INVOICE_PAYMENT_GATEWAY_URL ||
      process.env.LICENSE_PAYMENT_GATEWAY_URL ||
      '',
    storeType:
      process.env.INVOICE_PAYMENT_STORE_TYPE ||
      process.env.LICENSE_PAYMENT_STORE_TYPE ||
      '3d',
    apiUrl:
      process.env.INVOICE_PAYMENT_API_URL ||
      process.env.LICENSE_PAYMENT_API_URL ||
      '',
    apiName:
      process.env.INVOICE_PAYMENT_API_NAME ||
      process.env.LICENSE_PAYMENT_API_NAME ||
      process.env.INVOICE_PAYMENT_PROVISION_USER ||
      process.env.LICENSE_PAYMENT_PROVISION_USER ||
      '',
    apiPassword:
      process.env.INVOICE_PAYMENT_API_PASSWORD ||
      process.env.LICENSE_PAYMENT_API_PASSWORD ||
      process.env.INVOICE_PAYMENT_PROVISION_PASSWORD ||
      process.env.LICENSE_PAYMENT_PROVISION_PASSWORD ||
      '',
    mode: (
      process.env.INVOICE_PAYMENT_MODE ||
      process.env.LICENSE_PAYMENT_MODE ||
      'PROD'
    ).toUpperCase(),
  };
}

function validatePosConfig(config) {
  if (config.mode === 'SIMULATION') return '';
  if (!config.merchantId || !String(config.merchantId).trim()) {
    return 'Microvise sanal POS merchantId (clientId) tanımlı değil. .env içine LICENSE_PAYMENT_MERCHANT_ID / HALKBANK_CLIENT_ID ekleyin (lokal test: INVOICE_PAYMENT_MODE=SIMULATION).';
  }
  if (!config.storeKey || !String(config.storeKey).trim()) {
    return 'Microvise sanal POS storeKey tanımlı değil. .env içine LICENSE_PAYMENT_STORE_KEY / HALKBANK_STORE_KEY ekleyin.';
  }
  if (config.provider === 'garanti' && !String(config.terminalId || '').trim()) {
    return 'Garanti sanal POS terminalId tanımlı değil.';
  }
  return '';
}

function getPublicBaseUrl(req) {
  const fromEnv =
    process.env.INVOICE_PAYMENT_BASE_URL ||
    process.env.PAYMENT_BASE_URL ||
    process.env.PUBLIC_API_BASE_URL ||
    process.env.MICROVISE_LOCAL_ORIGIN ||
    '';
  if (fromEnv && String(fromEnv).trim()) {
    return String(fromEnv).trim().replace(/\/+$/, '');
  }
  if (req) {
    const proto =
      String(req.headers['x-forwarded-proto'] || 'http').split(',')[0].trim() ||
      'http';
    const host =
      String(req.headers['x-forwarded-host'] || req.headers.host || '')
        .split(',')[0]
        .trim();
    if (host) return `${proto}://${host}`;
  }
  return 'http://127.0.0.1:4000';
}

function randomToken() {
  return crypto.randomBytes(24).toString('hex');
}

async function ensureInvoicePaymentLinksTable() {
  if (tableReady) return;
  await query(`
    create table if not exists public.invoice_payment_links (
      id uuid primary key default gen_random_uuid(),
      token text not null unique,
      customer_id uuid not null references public.customers(id) on delete cascade,
      invoice_ids uuid[] not null,
      amount numeric(14,2) not null,
      currency text not null default 'TRY',
      description text,
      status text not null default 'pending',
      provider text not null default 'halkbank',
      provider_order_id text,
      provider_payload jsonb not null default '{}'::jsonb,
      paid_at timestamptz,
      created_by uuid,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      expires_at timestamptz
    )
  `);
  await query(`
    create index if not exists idx_invoice_payment_links_token
    on public.invoice_payment_links (token)
  `);
  await query(`
    create index if not exists idx_invoice_payment_links_customer
    on public.invoice_payment_links (customer_id, created_at desc)
  `);
  tableReady = true;
}

async function loadOpenInvoices(invoiceIds) {
  const ids = Array.from(
    new Set(
      (invoiceIds || [])
        .map((id) => String(id || '').trim())
        .filter(Boolean),
    ),
  );
  if (!ids.length) {
    const error = new Error('En az bir fatura seçilmelidir.');
    error.statusCode = 400;
    throw error;
  }
  const result = await query(
    `
      select
        id,
        invoice_number,
        invoice_type,
        customer_id,
        currency,
        exchange_rate,
        grand_total,
        coalesce(paid_amount, 0) as paid_amount,
        status,
        is_active
      from public.invoices
      where id = any($1::uuid[])
        and coalesce(is_active, true) = true
    `,
    [ids],
  );
  if (result.rows.length !== ids.length) {
    const error = new Error('Seçilen faturalardan bazıları bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  const customerIds = new Set(result.rows.map((r) => String(r.customer_id)));
  if (customerIds.size !== 1) {
    const error = new Error('Ödeme linki tek müşteriye ait faturalar için oluşturulabilir.');
    error.statusCode = 400;
    throw error;
  }
  const open = result.rows
    .map((row) => {
      const remaining =
        Number(row.grand_total || 0) - Number(row.paid_amount || 0);
      return {
        id: String(row.id),
        invoiceNumber: String(row.invoice_number || ''),
        invoiceType: String(row.invoice_type || 'sales'),
        customerId: String(row.customer_id),
        currency: String(row.currency || 'TRY'),
        exchangeRate: Number(row.exchange_rate || 1) || 1,
        remaining,
        status: String(row.status || ''),
      };
    })
    .filter((row) => row.remaining > 0.009 && ['open', 'partial'].includes(row.status));
  if (!open.length) {
    const error = new Error('Tahsil edilecek açık fatura yok.');
    error.statusCode = 400;
    throw error;
  }
  const currencies = new Set(open.map((r) => r.currency));
  if (currencies.size !== 1) {
    const error = new Error('Seçilen faturaların para birimi aynı olmalıdır.');
    error.statusCode = 400;
    throw error;
  }
  return open;
}

function getHostedPageUrl() {
  const configured = String(
    process.env.INVOICE_PAYMENT_HOSTED_PAGE_URL ||
      process.env.PAYMENT_INVOICE_HOSTED_PAGE_URL ||
      '',
  ).trim();
  // WP /fatura-odeme henüz yokken env yanlışlıkla 404 sayfasına götürmesin.
  const crmFallback = 'https://crm.microvise.net/api/invoice-pay';
  const exactUrl =
    configured && !/fatura-odeme/i.test(configured) ? configured : crmFallback;
  try {
    const normalized = new URL(String(exactUrl).trim());
    if (normalized.protocol !== 'https:' && normalized.protocol !== 'http:') {
      throw new Error('Invalid protocol');
    }
    normalized.hash = '';
    return normalized;
  } catch {
    return new URL(crmFallback);
  }
}

function getHostedBridgeCallbackUrl() {
  // Live WP tema henüz invoice_hosted kabul etmiyor ("Gecersiz callback").
  // Varsayılan: doğrudan CRM callback. WP plugin yüklendikten sonra
  // INVOICE_PAYMENT_USE_WP_BRIDGE=1 ile bridge tekrar açılır.
  const useWpBridge = String(
    process.env.INVOICE_PAYMENT_USE_WP_BRIDGE || '',
  )
    .trim()
    .toLowerCase();
  if (
    useWpBridge !== '1' &&
    useWpBridge !== 'true' &&
    useWpBridge !== 'yes' &&
    useWpBridge !== 'on'
  ) {
    return '';
  }

  const exactUrl =
    process.env.INVOICE_PAYMENT_HOSTED_CALLBACK_URL ||
    process.env.PAYMENT_INVOICE_HOSTED_CALLBACK_URL ||
    'https://www.microvise.net/wp-admin/admin-post.php?action=microvise_halkbank_bridge&callback=invoice_hosted';
  try {
    const normalized = new URL(String(exactUrl).trim());
    if (normalized.protocol !== 'https:' && normalized.protocol !== 'http:') {
      return '';
    }
    return normalized.toString();
  } catch {
    return '';
  }
}

function useHostedPaymentPage(config) {
  if (config.mode === 'SIMULATION') return false;
  const flag = String(
    process.env.INVOICE_PAYMENT_HOSTED ||
      process.env.PAYMENT_INVOICE_HOSTED ||
      '1',
  )
    .trim()
    .toLowerCase();
  if (flag === '0' || flag === 'false' || flag === 'off' || flag === 'no') {
    return false;
  }
  return true;
}

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function signInvoiceHostedSession(payload) {
  const secret = process.env.JWT_SECRET;
  if (!secret) {
    throw Object.assign(new Error('JWT_SECRET tanımlı değil.'), {
      statusCode: 500,
    });
  }
  const header = base64UrlEncode(
    JSON.stringify({ alg: 'HS256', typ: 'JWT' }),
  );
  const body = base64UrlEncode(
    JSON.stringify({
      ...payload,
      exp: Math.floor(Date.now() / 1000) + 60 * 60 * 24 * 7,
    }),
  );
  const data = `${header}.${body}`;
  const sig = crypto
    .createHmac('sha256', secret)
    .update(data)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  return `${data}.${sig}`;
}

function verifyInvoiceHostedSession(token) {
  const secret = process.env.JWT_SECRET;
  if (!secret) return null;
  const parts = String(token || '').split('.');
  if (parts.length !== 3) return null;
  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const data = `${encodedHeader}.${encodedPayload}`;
  const expectedSig = crypto
    .createHmac('sha256', secret)
    .update(data)
    .digest('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
  if (expectedSig !== encodedSignature) return null;
  try {
    const normalized = String(encodedPayload)
      .replace(/-/g, '+')
      .replace(/_/g, '/');
    const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
    const payload = JSON.parse(Buffer.from(padded, 'base64').toString('utf8'));
    if (!payload || payload.kind !== 'invoice-hosted') return null;
    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.exp === 'number' && payload.exp < now) return null;
    return payload;
  } catch {
    return null;
  }
}

function buildHostedPaymentUrl({
  sessionToken,
  token,
  amount,
  currency,
  customerName,
  invoiceCount,
  invoiceNumbers,
}) {
  const hostedUrl = getHostedPageUrl();
  hostedUrl.searchParams.set('session', sessionToken);
  hostedUrl.searchParams.set('token', token);
  hostedUrl.searchParams.set('amount', Number(amount).toFixed(2));
  hostedUrl.searchParams.set('currency', currency || 'TRY');
  if (customerName) hostedUrl.searchParams.set('customer', String(customerName));
  if (invoiceCount) hostedUrl.searchParams.set('invoices', String(invoiceCount));
  const numbers = (invoiceNumbers || [])
    .map((n) => String(n || '').trim())
    .filter(Boolean);
  if (numbers.length) {
    hostedUrl.searchParams.set('numbers', numbers.join(', '));
  }
  return hostedUrl.toString();
}

async function createInvoicePaymentLink({
  invoiceIds,
  createdBy,
  req,
}) {
  await ensureInvoicePaymentLinksTable();
  const config = getPosConfigFromEnv();
  const configError = validatePosConfig(config);
  if (configError) {
    const error = new Error(configError);
    error.statusCode = 400;
    throw error;
  }

  const invoices = await loadOpenInvoices(invoiceIds);
  const amount = Number(
    invoices.reduce((sum, inv) => sum + inv.remaining, 0).toFixed(2),
  );
  const currency = invoices[0].currency;
  const customerId = invoices[0].customerId;
  const description = `Açık fatura ödemesi (${invoices.length} fatura)`;
  const token = randomToken();
  const expiresAt = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000);

  const customerResult = await query(
    `select name from public.customers where id = $1 limit 1`,
    [customerId],
  );
  const customerName = customerResult.rows[0]?.name || '';
  const invoiceNumbers = invoices
    .map((i) => i.invoiceNumber)
    .filter(Boolean);

  const inserted = await query(
    `
      insert into public.invoice_payment_links (
        token,
        customer_id,
        invoice_ids,
        amount,
        currency,
        description,
        status,
        provider,
        created_by,
        expires_at
      ) values (
        $1, $2, $3::uuid[], $4, $5, $6, 'pending', $7, $8, $9
      )
      returning *
    `,
    [
      token,
      customerId,
      invoices.map((i) => i.id),
      amount,
      currency,
      description,
      config.provider,
      createdBy || null,
      expiresAt.toISOString(),
    ],
  );

  const row = inserted.rows[0];
  const baseUrl = getPublicBaseUrl(req);
  const directUrl = `${baseUrl}/api/invoice-pay?token=${encodeURIComponent(token)}`;
  const sessionToken = signInvoiceHostedSession({
    kind: 'invoice-hosted',
    linkId: row.id,
    token,
    amount,
    currency,
    customerId,
    customerName,
    invoiceCount: invoices.length,
    invoiceNumbers,
  });

  const hosted = useHostedPaymentPage(config);
  const paymentUrl = hosted
    ? buildHostedPaymentUrl({
        sessionToken,
        token,
        amount,
        currency,
        customerName,
        invoiceCount: invoices.length,
        invoiceNumbers,
      })
    : directUrl;

  return {
    id: row.id,
    token,
    sessionToken,
    paymentUrl,
    directUrl,
    hosted,
    amount,
    currency,
    invoiceCount: invoices.length,
    customerName,
    invoices: invoices.map((i) => ({
      id: i.id,
      invoiceNumber: i.invoiceNumber,
      remaining: i.remaining,
    })),
    expiresAt: expiresAt.toISOString(),
    provider: config.provider,
  };
}

async function getPaymentLinkByToken(token) {
  await ensureInvoicePaymentLinksTable();
  const result = await query(
    `
      select l.*, c.name as customer_name
      from public.invoice_payment_links l
      left join public.customers c on c.id = l.customer_id
      where l.token = $1
      limit 1
    `,
    [String(token || '').trim()],
  );
  return result.rows[0] || null;
}

async function getInvoiceNumbersForLink(link) {
  const ids = Array.isArray(link?.invoice_ids) ? link.invoice_ids : [];
  if (!ids.length) return [];
  const result = await query(
    `
      select invoice_number
      from public.invoices
      where id = any($1::uuid[])
      order by invoice_number asc
    `,
    [ids],
  );
  return result.rows
    .map((row) => String(row.invoice_number || '').trim())
    .filter(Boolean);
}

function nestpayCurrencyCode(currency) {
  switch (String(currency || 'TRY').trim().toUpperCase()) {
    case 'USD':
      return '840';
    case 'EUR':
      return '978';
    case 'GBP':
      return '826';
    case 'TRY':
    case 'TL':
    default:
      return '949';
  }
}

function currencyDisplayLabel(currency) {
  switch (String(currency || 'TRY').trim().toUpperCase()) {
    case 'USD':
      return 'USD';
    case 'EUR':
      return 'EUR';
    case 'GBP':
      return 'GBP';
    case 'TRY':
    case 'TL':
      return '₺';
    default:
      return String(currency || 'TRY').trim().toUpperCase() || 'TRY';
  }
}

function buildHalkbankRedirectHtml({
  orderId,
  amount,
  currency,
  callbackUrl,
  config,
  card,
}) {
  const gatewayUrl =
    config.gatewayUrl ||
    (config.mode === 'TEST' ? HALKBANK_TEST_GATEWAY_URL : HALKBANK_PROD_GATEWAY_URL);
  const amountText = Number(amount).toFixed(2);
  const cardNumber = String(card?.cardNumber || '').replace(/\s/g, '');
  const expireMonth = normalizeHalkbankExpiryMonth(card?.expireMonth);
  const expireYear = normalizeHalkbankExpiryYear(card?.expireYear);
  const cvc = String(card?.cvc || '').trim();
  const hasCard = hasHalkbankCardDetails(cardNumber, expireMonth, expireYear, cvc);
  const storeType = resolveHalkbankStoreTypeForRequest(config.storeType, hasCard);
  const rnd = (Date.now() / 1000).toFixed(4);
  const currencyCode = nestpayCurrencyCode(currency);
  const currencyLabel = currencyDisplayLabel(currency);
  const params = {
    clientid: String(config.merchantId).trim(),
    storetype: storeType,
    hashAlgorithm: 'ver3',
    islemtipi: 'Auth',
    TranType: 'Auth',
    Instalment: '',
    amount: amountText,
    currency: currencyCode,
    oid: String(orderId),
    okUrl: callbackUrl,
    failUrl: callbackUrl,
    lang: 'tr',
    rnd,
  };
  if (hasCard) {
    params.pan = cardNumber;
    params.cv2 = cvc;
    params.Ecom_Payment_Card_ExpDate_Year = expireYear;
    params.Ecom_Payment_Card_ExpDate_Month = expireMonth;
    if (card?.cardHolderName) {
      params.cardholdername = String(card.cardHolderName).trim();
    }
  }
  const hash = buildHalkbankHashVer3(params, String(config.storeKey || '').trim());
  params.HASH = hash;
  params.hash = hash;
  const inputs = Object.entries(params)
    .sort(([a], [b]) => a.localeCompare(b, 'en', { sensitivity: 'base' }))
    .map(
      ([key, value]) =>
        `<input type="hidden" name="${escapeHtml(key)}" value="${escapeHtml(value)}">`,
    )
    .join('');
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Microvise Güvenli Ödeme</title>
  <style>
    body{font-family:system-ui,-apple-system,sans-serif;background:#f4f7fb;margin:0;padding:24px;color:#1e293b}
    .card{max-width:420px;margin:40px auto;background:#fff;border-radius:14px;padding:24px;box-shadow:0 8px 24px rgba(15,23,42,.08)}
    h1{font-size:18px;margin:0 0 8px}
    p{margin:0 0 12px;color:#64748b;font-size:14px}
    .amount{font-size:28px;font-weight:800;color:#0f172a;margin:16px 0}
    button{width:100%;border:0;border-radius:10px;background:#277777;color:#fff;font-weight:700;padding:14px;cursor:pointer}
  </style>
</head>
<body>
  <div class="card">
    <h1>Microvise Sanal POS</h1>
    <p>Ödeme sayfasına yönlendiriliyorsunuz…</p>
    <div class="amount">${escapeHtml(amountText)} ${escapeHtml(currencyLabel)}</div>
    <form id="pay" action="${escapeHtml(gatewayUrl)}" method="POST">${inputs}</form>
    <button type="submit" form="pay">Ödemeye Git</button>
  </div>
  <script>document.getElementById('pay').submit();</script>
</body>
</html>`;
}

function buildStatusHtml({ title, message, ok }) {
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>${escapeHtml(title)}</title>
  <style>
    body{font-family:system-ui,-apple-system,sans-serif;background:#f4f7fb;margin:0;padding:24px;color:#1e293b}
    .card{max-width:420px;margin:40px auto;background:#fff;border-radius:14px;padding:24px;box-shadow:0 8px 24px rgba(15,23,42,.08)}
    h1{font-size:18px;margin:0 0 8px;color:${ok ? '#16845a' : '#c8424b'}}
    p{margin:0;color:#64748b;font-size:14px;line-height:1.5}
  </style>
</head>
<body>
  <div class="card">
    <h1>${escapeHtml(title)}</h1>
    <p>${escapeHtml(message)}</p>
  </div>
</body>
</html>`;
}

function buildCrmHostedPaymentPageHtml({
  sessionToken,
  token,
  amount,
  currency,
  customerName,
  invoiceCount,
  invoiceNumbers,
  status,
  errorMessage,
}) {
  const amountText = Number(amount || 0).toFixed(2);
  const currencyLabel = String(currency || 'TRY');
  const customer = String(customerName || 'Müşteri');
  const numbers = (invoiceNumbers || [])
    .map((n) => String(n || '').trim())
    .filter(Boolean);
  const countLabel =
    numbers.length > 0
      ? numbers.join(', ')
      : invoiceCount > 0
        ? `${invoiceCount} adet`
        : '-';
  const payApi = 'https://crm.microvise.net/api/invoice-pay?action=pay';

  if (status === 'success') {
    return buildStatusHtml({
      title: 'Ödeme onaylandı',
      message:
        numbers.length > 0
          ? `Teşekkürler. Ödemeniz alındı. Faturalar: ${numbers.join(', ')}`
          : 'Teşekkürler. Ödemeniz alındı, ilgili faturalar güncellendi.',
      ok: true,
    });
  }
  if (status === 'fail') {
    return buildStatusHtml({
      title: 'Ödeme tamamlanamadı',
      message: errorMessage || 'Banka işlemi başarısız döndü.',
      ok: false,
    });
  }
  if (!sessionToken) {
    return buildStatusHtml({
      title: 'Ödeme bağlantısı geçersiz',
      message: 'Bu ekran CRM üzerinden oluşturulan geçerli ödeme oturumu ile açılmalıdır.',
      ok: false,
    });
  }

  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Fatura Ödeme · Microvise</title>
  <style>
    body{margin:0;background:linear-gradient(180deg,#eff6ff 0%,#f8fafc 100%);font-family:system-ui,-apple-system,sans-serif;color:#0f172a}
    .wrap{max-width:720px;margin:16px auto;padding:0 12px}
    .card{background:#fff;border:1px solid #dbe4f0;border-radius:20px;overflow:hidden;box-shadow:0 16px 40px rgba(15,23,42,.10)}
    .hero{padding:18px 20px;background:linear-gradient(135deg,#0d6efd 0%,#1d4ed8 55%,#0f3d91 100%);color:#fff}
    .hero h1{margin:0 0 4px;font-size:24px}
    .hero p{margin:0;opacity:.92;font-size:14px}
    .body{padding:18px}
    .summary{display:grid;grid-template-columns:repeat(3,minmax(0,1fr));gap:10px;margin-bottom:14px}
    .box{background:#f8fafc;border:1px solid #e2e8f0;border-radius:12px;padding:12px}
    .label{display:block;font-size:11px;color:#64748b;margin-bottom:4px}
    .value{font-size:16px;font-weight:800;word-break:break-word}
    .helper{margin:0 0 14px;color:#64748b;font-size:13px;line-height:1.45}
    .notice{display:none;padding:12px 14px;border-radius:12px;margin-bottom:12px;border:1px solid #fecaca;background:#fff1f2;color:#b91c1c}
    .grid{display:grid;gap:10px}
    .two{grid-template-columns:repeat(2,minmax(0,1fr))}
    label{display:block;font-size:12px;font-weight:700;margin:0 0 4px}
    input{width:100%;box-sizing:border-box;padding:10px 11px;border:1px solid #cbd5e1;border-radius:11px;font-size:14px;background:#fff}
    input:focus{outline:none;border-color:#0d6efd;box-shadow:0 0 0 4px rgba(13,110,253,.12)}
    .actions{display:flex;justify-content:space-between;align-items:center;gap:12px;flex-wrap:wrap;margin-top:12px;padding-top:12px;border-top:1px solid #e2e8f0}
    button{border:0;border-radius:999px;padding:12px 18px;font-size:14px;font-weight:700;cursor:pointer;background:#dc2626;color:#fff}
    button:disabled{opacity:.6;cursor:not-allowed}
    .muted{font-size:12px;color:#64748b}
    .loader{display:none;margin-top:10px;color:#1d4ed8;font-weight:700;font-size:13px}
    @media(max-width:640px){.summary,.two{grid-template-columns:1fr}}
  </style>
</head>
<body>
  <div class="wrap">
    <div class="card">
      <div class="hero">
        <h1>Fatura Ödeme</h1>
        <p>Ödeme Microvise sanal POS üzerinden alınır.</p>
      </div>
      <div class="body">
        <div class="summary">
          <div class="box"><span class="label">Müşteri</span><div class="value">${escapeHtml(customer)}</div></div>
          <div class="box"><span class="label">Fatura No</span><div class="value">${escapeHtml(countLabel)}</div></div>
          <div class="box"><span class="label">Tutar</span><div class="value">${escapeHtml(amountText + ' ' + currencyLabel)}</div></div>
        </div>
        <p class="helper">Kart bilgilerinizi girin. 3D Secure onayı sonrası sonuç bu ekranda gösterilir.</p>
        <div id="err" class="notice"></div>
        <form id="pay-form" class="grid" novalidate>
          <div>
            <label for="card-holder">Kart üzerindeki isim</label>
            <input id="card-holder" type="text" autocomplete="cc-name" placeholder="Ad Soyad" required>
          </div>
          <div>
            <label for="card-number">Kart numarası</label>
            <input id="card-number" type="text" inputmode="numeric" autocomplete="cc-number" maxlength="23" placeholder="1234 5678 9012 3456" required>
          </div>
          <div class="grid two">
            <div>
              <label for="card-expiry">Son kullanma</label>
              <input id="card-expiry" type="text" inputmode="numeric" autocomplete="cc-exp" maxlength="5" placeholder="03/29" required>
            </div>
            <div>
              <label for="card-cvc">CVC</label>
              <input id="card-cvc" type="password" inputmode="numeric" autocomplete="cc-csc" maxlength="4" placeholder="CVC" required>
            </div>
          </div>
          <div class="actions">
            <div class="muted">3D Secure · Microvise Sanal POS</div>
            <button id="pay" type="submit">Ödeme Yap</button>
          </div>
        </form>
        <div id="loader" class="loader">Banka ekranı hazırlanıyor…</div>
      </div>
    </div>
  </div>
  <script>
  (function(){
    var sessionToken=${JSON.stringify(sessionToken)};
    var token=${JSON.stringify(token || '')};
    var apiUrl=${JSON.stringify(payApi)};
    var form=document.getElementById('pay-form');
    var err=document.getElementById('err');
    var loader=document.getElementById('loader');
    var btn=document.getElementById('pay');
    var cardHolder=document.getElementById('card-holder');
    var cardNumber=document.getElementById('card-number');
    var cardExpiry=document.getElementById('card-expiry');
    var cardCvc=document.getElementById('card-cvc');
    function digits(v){return (v||'').replace(/\\D/g,'');}
    function showError(message){err.textContent=message;err.style.display='block';}
    cardNumber.addEventListener('input',function(){
      var d=digits(cardNumber.value).slice(0,19);
      var p=[];for(var i=0;i<d.length;i+=4){p.push(d.slice(i,i+4));}
      cardNumber.value=p.join(' ');
    });
    cardExpiry.addEventListener('input',function(){
      var d=digits(cardExpiry.value).slice(0,4);
      if(d.length>=3){d=d.slice(0,2)+'/'+d.slice(2);}
      cardExpiry.value=d;
    });
    cardCvc.addEventListener('input',function(){cardCvc.value=digits(cardCvc.value).slice(0,4);});
    form.addEventListener('submit',function(event){
      event.preventDefault();
      err.style.display='none';
      var holder=cardHolder.value.trim();
      var number=digits(cardNumber.value);
      var expiry=cardExpiry.value.trim().split('/');
      var expMonth=expiry[0]||'';
      var expYearShort=expiry[1]||'';
      var expYear=expYearShort?'20'+expYearShort:'';
      var cvc=digits(cardCvc.value);
      if(!holder||number.length<12||expMonth.length!==2||expYearShort.length!==2||cvc.length<3){
        showError('Lütfen kart bilgilerini eksiksiz ve doğru girin.');
        return;
      }
      loader.style.display='block';
      btn.disabled=true;
      fetch(apiUrl,{
        method:'POST',
        headers:{'Content-Type':'application/json'},
        body:JSON.stringify({
          sessionToken:sessionToken,
          token:token,
          cardHolderName:holder,
          cardNumber:number,
          expireMonth:expMonth,
          expireYear:expYear,
          cvc:cvc
        })
      }).then(function(r){return r.json().then(function(d){return {ok:r.ok,d:d};});})
      .then(function(res){
        if(res.d&&res.d.success&&res.d.html){
          document.open();document.write(res.d.html);document.close();return;
        }
        throw new Error((res.d&&res.d.message)||'Ödeme başlatılamadı.');
      }).catch(function(e){
        loader.style.display='none';
        btn.disabled=false;
        showError(e&&e.message?e.message:'Ödeme başlatılamadı.');
      });
    });
  })();
  </script>
</body>
</html>`;
}

async function startPaymentRedirect(token, req, card = null) {
  const link = await getPaymentLinkByToken(token);
  if (!link) {
    return {
      statusCode: 404,
      html: buildStatusHtml({
        title: 'Link bulunamadı',
        message: 'Ödeme linki geçersiz veya silinmiş.',
        ok: false,
      }),
    };
  }
  if (link.status === 'paid') {
    return {
      statusCode: 200,
      html: buildStatusHtml({
        title: 'Ödeme tamamlandı',
        message: 'Bu fatura ödemesi daha önce alınmış.',
        ok: true,
      }),
    };
  }
  if (link.expires_at && new Date(link.expires_at).getTime() < Date.now()) {
    return {
      statusCode: 410,
      html: buildStatusHtml({
        title: 'Link süresi doldu',
        message: 'Lütfen CRM üzerinden yeni bir ödeme linki oluşturun.',
        ok: false,
      }),
    };
  }

  const config = getPosConfigFromEnv();
  const configError = validatePosConfig(config);
  if (configError) {
    return {
      statusCode: 500,
      html: buildStatusHtml({
        title: 'POS yapılandırması eksik',
        message: configError,
        ok: false,
      }),
    };
  }

  if (config.mode === 'SIMULATION') {
    // Gerçek tahsilat yazma — sadece linkin geçerli olduğunu göster.
    return {
      statusCode: 200,
      html: buildStatusHtml({
        title: 'Simülasyon (tahsilat yok)',
        message:
          'SIMULATION modunda fatura kapatılmaz ve tahsilat kaydı oluşmaz. ' +
          'Canlı tahsilat için Microvise POS (PROD) + kartlı 3d akışı gerekir.',
        ok: true,
      }),
    };
  }

  const hasCard = hasHalkbankCardDetails(
    card?.cardNumber,
    card?.expireMonth,
    card?.expireYear,
    card?.cvc,
  );
  const resolvedStoreType = resolveHalkbankStoreTypeForRequest(
    config.storeType,
    hasCard,
  );
  if (isHalkbank3DSecureFlow(resolvedStoreType) && !hasCard) {
    return {
      statusCode: 400,
      html: buildStatusHtml({
        title: 'Kart bilgisi gerekli',
        message:
          'Bu üye işyeri classic 3d kullanır. Ödeme linkindeki kart formunu doldurup tekrar deneyin.',
        ok: false,
      }),
      json: {
        success: false,
        message:
          'Kart bilgisi gerekli. Microvise POS classic 3d ile çalışır (lisans ödemesi gibi).',
      },
    };
  }

  const baseUrl = getPublicBaseUrl(req);
  const directCallbackUrl = `${baseUrl}/api/invoice-pay?action=callback&token=${encodeURIComponent(token)}`;
  const bridgeCallbackUrl = getHostedBridgeCallbackUrl();
  const callbackUrl =
    useHostedPaymentPage(config) && bridgeCallbackUrl
      ? `${bridgeCallbackUrl}${
          bridgeCallbackUrl.includes('?') ? '&' : '?'
        }token=${encodeURIComponent(token)}`
      : directCallbackUrl;
  const orderId = String(link.id).replace(/-/g, '').slice(0, 20);
  await query(
    `
      update public.invoice_payment_links
      set provider_order_id = $2, updated_at = now()
      where id = $1
    `,
    [link.id, orderId],
  );

  if (config.provider === 'garanti') {
    return {
      statusCode: 501,
      html: buildStatusHtml({
        title: 'Garanti henüz bağlanmadı',
        message:
          'Fatura ödeme linki şu an Halkbank NestPay (Microvise sanal POS) ile çalışır. Provider=halkbank kullanın.',
        ok: false,
      }),
    };
  }

  return {
    statusCode: 200,
    html: buildHalkbankRedirectHtml({
      orderId,
      amount: Number(link.amount),
      currency: link.currency || 'TRY',
      callbackUrl,
      config,
      card,
    }),
  };
}

function isSuccessfulCallback(body, config) {
  const code = getHalkbankCallbackField(
    body,
    'ProcReturnCode',
    'procreturncode',
    'PROCRETURNCODE',
  );
  const response = getHalkbankCallbackField(body, 'Response', 'response');
  if (
    code === '00' ||
    code === '0000' ||
    String(response || '').toUpperCase() === 'APPROVED'
  ) {
    return true;
  }
  const callbackStoreType = normalizeHalkbankStoreType(
    getHalkbankCallbackField(body, 'storetype', 'storeType', 'StoreType') ||
      config?.storeType,
  );
  const mdStatus = getHalkbankCallbackField(
    body,
    'mdStatus',
    'mdstatus',
    'MDStatus',
  );
  // 3d_pay gateway'de tamamlanır; classic 3d için mdStatus tek başına yeterli değil.
  if (callbackStoreType === '3d_pay' && isSuccessfulMdStatus(mdStatus)) {
    return true;
  }
  return false;
}

async function completeInvoicePayment(link, { success, providerPayload, providerOrderId }) {
  if (!success) {
    await query(
      `
        update public.invoice_payment_links
        set status = 'failed',
            provider_payload = coalesce(provider_payload, '{}'::jsonb) || $2::jsonb,
            updated_at = now()
        where id = $1 and status = 'pending'
      `,
      [link.id, JSON.stringify(providerPayload || {})],
    );
    return { ok: false };
  }

  if (link.status === 'paid') return { ok: true, alreadyPaid: true };

  await withTransaction(async (txQuery) => {
    const locked = await txQuery(
      `
        select * from public.invoice_payment_links
        where id = $1
        for update
      `,
      [link.id],
    );
    const current = locked.rows[0];
    if (!current) return;
    if (current.status === 'paid') return;

    const invoiceIds = current.invoice_ids || [];
    const invoices = await txQuery(
      `
        select
          id,
          invoice_number,
          invoice_type,
          customer_id,
          currency,
          exchange_rate,
          grand_total,
          coalesce(paid_amount, 0) as paid_amount,
          status
        from public.invoices
        where id = any($1::uuid[])
      `,
      [invoiceIds],
    );

    for (const invoice of invoices.rows) {
      const remaining =
        Number(invoice.grand_total || 0) - Number(invoice.paid_amount || 0);
      if (remaining <= 0.009) continue;
      await txQuery(
        `
          insert into public.transactions (
            customer_id,
            invoice_id,
            transaction_type,
            amount,
            currency,
            exchange_rate,
            payment_method,
            transaction_date,
            description,
            is_active
          ) values (
            $1, $2, $3, $4, $5, $6, 'pos', current_date, $7, true
          )
        `,
        [
          invoice.customer_id,
          invoice.id,
          invoice.invoice_type === 'purchase' ? 'payment' : 'collection',
          remaining,
          invoice.currency || current.currency || 'TRY',
          Number(invoice.exchange_rate || 1) || 1,
          `Sanal POS ödeme linki: ${invoice.invoice_number}`,
        ],
      );
    }

    await txQuery(
      `
        update public.invoice_payment_links
        set status = 'paid',
            paid_at = now(),
            provider_order_id = coalesce($2, provider_order_id),
            provider_payload = coalesce(provider_payload, '{}'::jsonb) || $3::jsonb,
            updated_at = now()
        where id = $1
      `,
      [
        current.id,
        providerOrderId || null,
        JSON.stringify(providerPayload || {}),
      ],
    );
  });

  return { ok: true };
}

async function handlePaymentCallback(token, body) {
  const link = await getPaymentLinkByToken(token);
  if (!link) {
    return {
      statusCode: 404,
      html: buildStatusHtml({
        title: 'Link bulunamadı',
        message: 'Ödeme sonucu işlenemedi.',
        ok: false,
      }),
    };
  }

  const config = getPosConfigFromEnv();
  let success = isSuccessfulCallback(body || {}, config);
  let failMessage = String(
    body?.errmsg || body?.ErrMsg || body?.mdErrorMsg || 'İşlem tamamlanamadı.',
  );
  const providerPayload = { ...(body || {}) };

  // Classic 3d: 3D Secure sonrası API Auth gerekir (lisans ödemesiyle aynı).
  if (!success) {
    const mdStatus = getHalkbankCallbackField(
      body,
      'mdStatus',
      'mdstatus',
      'MDStatus',
    );
    const callbackStoreType = normalizeHalkbankStoreType(
      getHalkbankCallbackField(body, 'storetype', 'storeType', 'StoreType') ||
        config.storeType,
    );
    const needsFinalize =
      isHalkbank3DSecureFlow(callbackStoreType) ||
      isHalkbank3DSecureFlow(config.storeType) ||
      Boolean(getHalkbankCallbackField(body, 'md', 'MD'));
    if (needsFinalize && isSuccessfulMdStatus(mdStatus)) {
      const finalResult = await finalizeHalkbank3DSecurePayment(
        body || {},
        config,
      );
      success = Boolean(finalResult.approved);
      failMessage = finalResult.message || failMessage;
      providerPayload.apiFinalize = {
        approved: success,
        message: finalResult.message || null,
        parsed: finalResult.parsed || null,
      };
    } else if (needsFinalize) {
      failMessage = failMessage || `MDStatus ${mdStatus || '0'}`;
    }
  }

  await completeInvoicePayment(link, {
    success,
    providerPayload,
    providerOrderId:
      body?.oid || body?.OrderId || body?.orderid || link.provider_order_id,
  });

  if (useHostedPaymentPage(config)) {
    const resultUrl = getHostedPageUrl();
    resultUrl.searchParams.set('invoice', success ? 'success' : 'fail');
    resultUrl.searchParams.set('token', String(token || ''));
    resultUrl.searchParams.set('amount', Number(link.amount).toFixed(2));
    resultUrl.searchParams.set('currency', link.currency || 'TRY');
    if (link.customer_name) {
      resultUrl.searchParams.set('customer', String(link.customer_name));
    }
    const invoiceCount = Array.isArray(link.invoice_ids)
      ? link.invoice_ids.length
      : 0;
    if (invoiceCount) {
      resultUrl.searchParams.set('invoices', String(invoiceCount));
    }
    const invoiceNumbers = await getInvoiceNumbersForLink(link);
    if (invoiceNumbers.length) {
      resultUrl.searchParams.set('numbers', invoiceNumbers.join(', '));
    }
    if (!success) {
      resultUrl.searchParams.set('errmsg', failMessage.slice(0, 240));
    }
    return {
      statusCode: 302,
      redirect: resultUrl.toString(),
      html: buildStatusHtml({
        title: success ? 'Ödeme başarılı' : 'Ödeme başarısız',
        message: success
          ? 'Teşekkürler. Ödemeniz alındı, faturalar güncellendi.'
          : failMessage,
        ok: success,
      }),
    };
  }

  return {
    statusCode: 200,
    html: buildStatusHtml({
      title: success ? 'Ödeme başarılı' : 'Ödeme başarısız',
      message: success
        ? 'Teşekkürler. Ödemeniz alındı, faturalar güncellendi.'
        : failMessage,
      ok: success,
    }),
  };
}

async function getHostedSessionInfo({ sessionToken, token }) {
  await ensureInvoicePaymentLinksTable();
  let session = sessionToken ? verifyInvoiceHostedSession(sessionToken) : null;
  const lookupToken = String(token || session?.token || '').trim();
  if (!lookupToken) {
    const error = new Error('Ödeme oturumu geçersiz.');
    error.statusCode = 400;
    throw error;
  }
  const link = await getPaymentLinkByToken(lookupToken);
  if (!link) {
    const error = new Error('Ödeme linki bulunamadı.');
    error.statusCode = 404;
    throw error;
  }
  if (session && session.linkId && String(session.linkId) !== String(link.id)) {
    const error = new Error('Ödeme oturumu eşleşmiyor.');
    error.statusCode = 400;
    throw error;
  }
  const invoiceNumbers =
    Array.isArray(session?.invoiceNumbers) && session.invoiceNumbers.length
      ? session.invoiceNumbers
      : await getInvoiceNumbersForLink(link);
  return {
    ok: true,
    token: link.token,
    status: link.status,
    amount: Number(link.amount),
    currency: link.currency || 'TRY',
    customerName: link.customer_name || session?.customerName || '',
    invoiceCount: Array.isArray(link.invoice_ids) ? link.invoice_ids.length : null,
    invoiceNumbers,
    description: link.description || '',
    expiresAt: link.expires_at,
    paid: link.status === 'paid',
  };
}

async function startHostedPayment({ sessionToken, token, req, card }) {
  const session = sessionToken ? verifyInvoiceHostedSession(sessionToken) : null;
  const lookupToken = String(token || session?.token || '').trim();
  if (!lookupToken) {
    return {
      statusCode: 400,
      json: { success: false, message: 'Geçersiz veya süresi dolmuş ödeme oturumu' },
    };
  }
  if (session && session.token && session.token !== lookupToken) {
    return {
      statusCode: 400,
      json: { success: false, message: 'Oturum token eşleşmiyor' },
    };
  }
  const result = await startPaymentRedirect(lookupToken, req, card || null);
  if (result.json && !result.html) {
    return {
      statusCode: result.statusCode || 400,
      json: result.json,
    };
  }
  if (result.html) {
    return {
      statusCode: result.statusCode || 200,
      json: {
        success: result.statusCode < 400,
        html: result.html,
        token: lookupToken,
        message:
          result.statusCode >= 400
            ? result.json?.message || 'Ödeme başlatılamadı'
            : undefined,
      },
    };
  }
  return {
    statusCode: result.statusCode || 500,
    json: {
      success: false,
      message: 'Ödeme başlatılamadı',
    },
  };
}

module.exports = {
  ensureInvoicePaymentLinksTable,
  createInvoicePaymentLink,
  getPaymentLinkByToken,
  getHostedSessionInfo,
  startHostedPayment,
  startPaymentRedirect,
  handlePaymentCallback,
  getPosConfigFromEnv,
  validatePosConfig,
  getHostedPageUrl,
  useHostedPaymentPage,
  buildCrmHostedPaymentPageHtml,
  getInvoiceNumbersForLink,
  verifyInvoiceHostedSession,
};
