const { query } = require('./db');
const crypto = require('crypto');

function base64UrlDecode(input) {
  const normalized = String(input || '')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, 'base64').toString('utf8');
}

function verifyJwt(token, secret) {
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
    const payload = JSON.parse(base64UrlDecode(encodedPayload));
    if (!payload || typeof payload !== 'object') return null;
    const now = Math.floor(Date.now() / 1000);
    if (typeof payload.exp === 'number' && payload.exp < now) return null;
    return payload;
  } catch (_) {
    return null;
  }
}

async function getAccessToken(req) {
  const header = req.headers.authorization || req.headers.Authorization;
  if (!header || typeof header !== 'string') return null;
  if (!header.startsWith('Bearer ')) return null;
  const token = header.slice(7).trim();
  return token || null;
}

async function getAuthenticatedUser(req) {
  const accessToken = await getAccessToken(req);
  if (!accessToken) {
    return null;
  }

  const jwtSecret = process.env.JWT_SECRET;
  if (!jwtSecret) {
    return null;
  }

  const payload = verifyJwt(accessToken, jwtSecret);
  if (!payload || !payload.sub) {
    return null;
  }

  const userId = String(payload.sub);
  const profileResult = await query(
    `
      select
        id,
        email,
        full_name,
        role,
        coalesce(page_permissions, '{}'::text[]) as page_permissions,
        coalesce(action_permissions, '{}'::text[]) as action_permissions
      from public.users
      where id = $1
      limit 1
    `,
    [userId],
  );

  const profile = profileResult.rows[0];
  return profile || null;
}

const defaultPersonnelPagePermissions = new Set([
  'panel',
  'musteriler',
  'formlar',
  'is_emirleri',
  'servis',
  'raporlar',
  'urunler',
  'faturalama',
]);

function hasPageAccess(user, pageKey) {
  if (!user) return false;
  if (user.role === 'admin') return true;
  const permissions = Array.isArray(user.page_permissions)
    ? user.page_permissions
    : [];
  if (permissions.length === 0) {
    return defaultPersonnelPagePermissions.has(pageKey);
  }
  return permissions.includes(pageKey);
}

module.exports = {
  getAuthenticatedUser,
  hasPageAccess,
};
