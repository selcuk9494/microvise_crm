const crypto = require('crypto');
const { query } = require('../_lib/db');
const { ensureUsersAuthColumns } = require('../_lib/schema');
const { ok, badRequest, unauthorized, methodNotAllowed, serverError } = require('../_lib/http');

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

function base64UrlEncode(input) {
  return Buffer.from(input)
    .toString('base64')
    .replace(/=/g, '')
    .replace(/\+/g, '-')
    .replace(/\//g, '_');
}

function uuidV4() {
  if (typeof crypto.randomUUID === 'function') return crypto.randomUUID();
  const b = crypto.randomBytes(16);
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  const hex = b.toString('hex');
  return `${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}`;
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

module.exports = async (req, res) => {
  if (req.method !== 'POST') {
    return methodNotAllowed(res, 'POST');
  }

  try {
    const body = await readJson(req);
    const email = normalizeEmail(body.email);
    const password = String(body.password || '');

    if (!email || !email.includes('@') || password.length < 1) {
      return badRequest(res, 'E-posta ve şifre gerekli.');
    }

    await ensureUsersAuthColumns();

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      return serverError(res, new Error('JWT_SECRET is not configured.'));
    }

    const masterEmail = normalizeEmail(process.env.MASTER_ADMIN_EMAIL);
    const masterPassword = String(process.env.MASTER_ADMIN_PASSWORD || '');
    const isMasterEmail = masterEmail && email === masterEmail;
    const isMasterPassword = masterPassword && password === masterPassword;
    const isMaster = isMasterEmail && isMasterPassword;

    const userResult = await query(
      `
        select
          id,
          email,
          full_name,
          role,
          coalesce(page_permissions, '{}'::text[]) as page_permissions,
          coalesce(action_permissions, '{}'::text[]) as action_permissions,
          password_hash,
          coalesce(is_active, true) as is_active
        from public.users
        where lower(email) = $1
        limit 1
      `,
      [email],
    );

    let user = userResult.rows[0] || null;

    if (user && user.is_active === false) {
      return unauthorized(res, 'Kullanıcı pasif.');
    }

    if (!user) {
      if (!isMaster) return unauthorized(res, 'Giriş başarısız.');
      const id = uuidV4();
      const pagePermissions = [
        'panel',
        'musteriler',
        'formlar',
        'is_emirleri',
        'servis',
        'raporlar',
        'urunler',
        'faturalama',
        'tanimlamalar',
        'personel',
      ];
      const actionPermissions = ['duzenleme', 'pasife_alma', 'kalici_silme'];
      try {
        await query(
          `
            insert into public.users (
              id,
              email,
              full_name,
              role,
              page_permissions,
              action_permissions,
              password_hash,
              is_active
            )
            values ($1, $2, $3, $4, $5::text[], $6::text[], crypt($7, gen_salt('bf')), true)
          `,
          [id, email, 'Admin', 'admin', pagePermissions, actionPermissions, password],
        );
      } catch (_) {}
      const created = await query(
        `
          select
            id,
            email,
            full_name,
            role,
            coalesce(page_permissions, '{}'::text[]) as page_permissions,
            coalesce(action_permissions, '{}'::text[]) as action_permissions,
            password_hash,
            coalesce(is_active, true) as is_active
          from public.users
          where lower(email) = $1
          limit 1
        `,
        [email],
      );
      user = created.rows[0] || null;
    }

    if (!user) return unauthorized(res, 'Giriş başarısız.');

    if (!isMaster) {
      const pwHash = user.password_hash ? String(user.password_hash) : '';
      if (!pwHash) return unauthorized(res, 'Şifre tanımlı değil.');
      const okPw = await query(
        `
          select 1 as ok
          from public.users
          where id = $1
            and password_hash = crypt($2, password_hash)
          limit 1
        `,
        [user.id, password],
      );
      if (!okPw.rows[0]?.ok) return unauthorized(res, 'Giriş başarısız.');
    }

    const now = Math.floor(Date.now() / 1000);
    const payload = {
      sub: user.id,
      email: user.email,
      role: user.role,
      exp: now + 60 * 60 * 24 * 7,
      iat: now,
    };
    const accessToken = signJwt(payload, jwtSecret);

    return ok(res, {
      accessToken,
      user: {
        id: user.id,
        email: user.email,
        full_name: user.full_name || null,
        role: user.role || 'personel',
        page_permissions: normalizeTextArray(user.page_permissions),
        action_permissions: normalizeTextArray(user.action_permissions),
      },
    });
  } catch (error) {
    return serverError(res, error);
  }
};
