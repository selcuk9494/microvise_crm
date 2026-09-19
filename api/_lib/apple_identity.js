const crypto = require('crypto');

const APPLE_ISS = 'https://appleid.apple.com';
const APPLE_JWKS_URL = 'https://appleid.apple.com/auth/keys';
const DEFAULT_BUNDLE_ID = 'com.microvise.microviseCrm';

let cachedJwks = { fetchedAt: 0, keys: [] };

function base64UrlToBuffer(input) {
  const normalized = String(input || '')
    .replace(/-/g, '+')
    .replace(/_/g, '/');
  const padded = normalized + '='.repeat((4 - (normalized.length % 4)) % 4);
  return Buffer.from(padded, 'base64');
}

function sha256Hex(value) {
  return crypto.createHash('sha256').update(String(value || ''), 'utf8').digest('hex');
}

function appleAudiences() {
  const extras = String(process.env.APPLE_CLIENT_IDS || '')
    .split(',')
    .map((item) => item.trim())
    .filter(Boolean);
  const listed = [
    DEFAULT_BUNDLE_ID,
    String(process.env.APPLE_BUNDLE_ID || '').trim(),
    String(process.env.APPLE_SERVICE_ID || '').trim(),
    ...extras,
  ].filter(Boolean);
  return [...new Set(listed)];
}

function appleRedirectUri(req) {
  const fromEnv = String(process.env.APPLE_REDIRECT_URI || '').trim();
  if (fromEnv) return fromEnv;
  const host = String(
    req?.headers?.['x-forwarded-host'] || req?.headers?.host || 'crm.microvise.net',
  )
    .split(',')[0]
    .trim();
  const proto = String(
    req?.headers?.['x-forwarded-proto'] ||
      (host.includes('localhost') || host.startsWith('127.') ? 'http' : 'https'),
  )
    .split(',')[0]
    .trim();
  return `${proto}://${host}/api/auth/apple-callback`;
}

function appleWebClientId() {
  return String(process.env.APPLE_SERVICE_ID || '').trim();
}

async function fetchAppleJwks() {
  const now = Date.now();
  if (cachedJwks.keys.length && now - cachedJwks.fetchedAt < 60 * 60 * 1000) {
    return cachedJwks.keys;
  }
  const response = await fetch(APPLE_JWKS_URL, {
    headers: { Accept: 'application/json' },
  });
  if (!response.ok) {
    throw new Error('Apple kimlik anahtarları alınamadı.');
  }
  const body = await response.json();
  const keys = Array.isArray(body?.keys) ? body.keys : [];
  if (!keys.length) throw new Error('Apple kimlik anahtarları boş.');
  cachedJwks = { fetchedAt: now, keys };
  return keys;
}

function decodeJwtPart(part) {
  try {
    return JSON.parse(base64UrlToBuffer(part).toString('utf8'));
  } catch (_) {
    return null;
  }
}

function nonceMatches(expected, actual) {
  if (!expected) return true;
  const want = String(expected);
  const got = String(actual || '');
  if (!got) return true;
  return got === want || got === sha256Hex(want);
}

async function verifyAppleIdentityToken(identityToken, { nonce } = {}) {
  const token = String(identityToken || '').trim();
  const parts = token.split('.');
  if (parts.length !== 3) return null;

  const header = decodeJwtPart(parts[0]);
  const payload = decodeJwtPart(parts[1]);
  if (!header || !payload) return null;
  if (header.alg !== 'RS256' || !header.kid) return null;

  const keys = await fetchAppleJwks();
  const jwk = keys.find((key) => key && key.kid === header.kid);
  if (!jwk) return null;

  let keyObject;
  try {
    keyObject = crypto.createPublicKey({ key: jwk, format: 'jwk' });
  } catch (_) {
    return null;
  }

  const ok = crypto.verify(
    'sha256',
    Buffer.from(`${parts[0]}.${parts[1]}`),
    keyObject,
    base64UrlToBuffer(parts[2]),
  );
  if (!ok) return null;

  const now = Math.floor(Date.now() / 1000);
  if (payload.iss !== APPLE_ISS) return null;
  if (typeof payload.exp === 'number' && payload.exp < now) return null;
  if (typeof payload.nbf === 'number' && payload.nbf > now + 60) return null;

  const audiences = appleAudiences();
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.some((value) => audiences.includes(String(value || '')))) return null;
  if (!nonceMatches(nonce, payload.nonce)) return null;

  const sub = String(payload.sub || '').trim();
  if (!sub) return null;

  const email = String(payload.email || '').trim().toLowerCase();
  return {
    sub,
    email,
    emailVerified:
      payload.email_verified === true || payload.email_verified === 'true',
    isPrivateEmail:
      payload.is_private_email === true || payload.is_private_email === 'true',
    aud: aud.map((value) => String(value || '')),
  };
}

module.exports = {
  appleAudiences,
  appleRedirectUri,
  appleWebClientId,
  verifyAppleIdentityToken,
};
