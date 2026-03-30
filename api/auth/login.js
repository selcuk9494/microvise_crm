const crypto = require('crypto');
const { query } = require('../_lib/db');
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

function signJwt(payload, secret) {
  const header = { alg: 'HS256', typ: 'JWT' };
  const encodedHeader = base64UrlEncode(JSON.stringify(header));
  const encodedPayload = base64UrlEncode(JSON.stringify(payload));
  const data = `${encodedHeader}.${encodedPayload}`;
  const signature = crypto.createHmac('sha256', secret).update(data).digest();
  return `${data}.${base64UrlEncode(signature)}`;
}

function normalizeEmail(email) {
  return String(email || '').trim().toLowerCase();
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

    const jwtSecret = process.env.JWT_SECRET;
    if (!jwtSecret) {
      return serverError(res, new Error('JWT_SECRET is not configured.'));
    }

    const masterEmail = normalizeEmail(process.env.MASTER_ADMIN_EMAIL);
    const masterPassword = String(process.env.MASTER_ADMIN_PASSWORD || '');
    const isMaster = masterEmail && email === masterEmail && password === masterPassword;

    const userResult = await query(
      `
        select
          id,
          email,
          full_name,
          role,
          coalesce(page_permissions, '{}'::text[]) as page_permissions,
          coalesce(action_permissions, '{}'::text[]) as action_permissions
        from public.users
        where lower(email) = $1
        limit 1
      `,
      [email],
    );

    let user = userResult.rows[0] || null;

    if (!user) {
      if (!isMaster) {
        return unauthorized(res, 'Kullanıcı bulunamadı.');
      }

      const id = crypto.randomUUID();
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

      await query(
        `
          insert into public.users (
            id,
            email,
            full_name,
            role,
            page_permissions,
            action_permissions
          )
          values ($1, $2, $3, $4, $5::text[], $6::text[])
        `,
        [id, email, 'Admin', 'admin', pagePermissions, actionPermissions],
      );

      user = {
        id,
        email,
        full_name: 'Admin',
        role: 'admin',
        page_permissions: pagePermissions,
        action_permissions: actionPermissions,
      };
    } else if (!isMaster) {
      return unauthorized(res, 'Giriş başarısız.');
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
        page_permissions: user.page_permissions || [],
        action_permissions: user.action_permissions || [],
      },
    });
  } catch (error) {
    return serverError(res, error);
  }
};

