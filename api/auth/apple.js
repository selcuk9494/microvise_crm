const crypto = require('crypto');
const { query } = require('../_lib/db');
const { ensureUsersAuthColumns } = require('../_lib/schema');
const {
  verifyAppleIdentityToken,
} = require('../_lib/apple_identity');
const {
  handleCors,
  ok,
  badRequest,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('../_lib/http');

function readJsonOrEmpty(value) {
  if (!value || typeof value !== 'object') return {};
  return value;
}

async function readJson(req) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return readJsonOrEmpty(req.body);
  }
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

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function signJwt(payload, secret) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.createHmac('sha256', secret).update(data).digest();
  return `${data}.${base64UrlEncode(signature)}`;
}

function normalizeEmail(email) {
  let value = String(email || '').trim().toLowerCase();
  while (value.endsWith('.')) {
    value = value.slice(0, -1).trimEnd();
  }
  return value;
}

function normalizeTextArray(value) {
  if (Array.isArray(value)) {
    return value.map((e) => String(e || '').trim()).filter((e) => e.length > 0);
  }
  return [];
}

const adminPagePermissions = [
  'panel',
  'musteriler',
  'formlar',
  'tsm_log',
  'is_emirleri',
  'servis',
  'raporlar',
  'urunler',
  'faturalama',
  'e_fatura',
  'finans',
  'tanimlamalar',
  'personel',
];

const userSelectSql = `
  select
    id,
    email,
    full_name,
    role,
    coalesce(page_permissions, '{}'::text[]) as page_permissions,
    coalesce(action_permissions, '{}'::text[]) as action_permissions,
    apple_user_id,
    coalesce(is_active, true) as is_active
  from public.users
`;

function sessionPayload(user, jwtSecret) {
  const now = Math.floor(Date.now() / 1000);
  const pagePermissions = normalizeTextArray(user.page_permissions);
  return {
    accessToken: signJwt(
      {
        sub: user.id,
        email: user.email,
        role: user.role,
        exp: now + 60 * 60 * 24 * 7,
        iat: now,
      },
      jwtSecret,
    ),
    user: {
      id: user.id,
      email: user.email,
      full_name: user.full_name || null,
      role: user.role || 'personel',
      page_permissions:
        user.role === 'admin'
          ? [...new Set([...adminPagePermissions, ...pagePermissions])]
          : pagePermissions,
      action_permissions: normalizeTextArray(user.action_permissions),
    },
  };
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'POST,OPTIONS')) return;
  if (req.method !== 'POST') {
    return methodNotAllowed(req, res, 'POST');
  }

  try {
    const body = await readJson(req);
    const identityToken = String(body.identityToken || body.id_token || '').trim();
    const nonce = String(body.nonce || '').trim();
    const givenName = String(body.givenName || body.fullName?.givenName || '').trim();
    const familyName = String(
      body.familyName || body.fullName?.familyName || '',
    ).trim();
    const clientEmail = normalizeEmail(body.email);

    if (!identityToken) {
      return badRequest(req, res, 'Apple kimliği alınamadı.');
    }

    await ensureUsersAuthColumns();

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      return serverError(req, res, new Error('JWT_SECRET is not configured.'));
    }

    let appleUser;
    try {
      appleUser = await verifyAppleIdentityToken(identityToken, { nonce });
    } catch (error) {
      return serverError(req, res, error);
    }
    if (!appleUser) {
      return unauthorized(req, res, 'Apple kimliği doğrulanamadı.');
    }

    const appleUserId = appleUser.sub;
    const email = appleUser.email || clientEmail;

    const found = await query(
      `
        ${userSelectSql}
        where apple_user_id = $1
           or ($2 <> '' and lower(email) = $2)
        order by
          case
            when apple_user_id = $1 then 0
            else 1
          end
        limit 1
      `,
      [appleUserId, email],
    );

    let user = found.rows[0] || null;
    if (user && user.is_active === false) {
      return unauthorized(req, res, 'Kullanıcı pasif.');
    }

    if (user && user.apple_user_id && user.apple_user_id !== appleUserId) {
      return unauthorized(
        req,
        res,
        'Bu e-posta başka bir Apple hesabına bağlı.',
      );
    }

    if (user && !user.apple_user_id) {
      try {
        await query(
          `
            update public.users
            set apple_user_id = $2,
                updated_at = now()
            where id = $1
              and (apple_user_id is null or btrim(apple_user_id) = '')
          `,
          [user.id, appleUserId],
        );
        user.apple_user_id = appleUserId;
      } catch (_) {}
    }

    if (!user) {
      return unauthorized(
        req,
        res,
        'Bu Apple hesabı CRM’de kayıtlı değil. Personel e-postanızla yöneticiden hesap açılmasını isteyin.',
      );
    }

    const displayName = [givenName, familyName].filter(Boolean).join(' ').trim();
    if (displayName && !String(user.full_name || '').trim()) {
      try {
        await query(
          `
            update public.users
            set full_name = $2,
                updated_at = now()
            where id = $1
              and (full_name is null or btrim(full_name) = '')
          `,
          [user.id, displayName],
        );
        user.full_name = displayName;
      } catch (_) {}
    }

    return ok(req, res, sessionPayload(user, jwtSecret));
  } catch (error) {
    return serverError(req, res, error);
  }
};
