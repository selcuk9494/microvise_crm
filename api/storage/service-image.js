const crypto = require('crypto');
const { getAuthenticatedUser, hasPageAccess } = require('../_lib/auth');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('../_lib/http');

const bucket = 'service-images';
const maxBytes = 5 * 1024 * 1024;
const allowedContentTypes = new Set(['image/jpeg', 'image/png', 'image/webp']);

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

function safeSegment(value, fallback) {
  const cleaned = String(value || '')
    .trim()
    .replace(/[^a-zA-Z0-9._-]/g, '-')
    .replace(/-+/g, '-')
    .replace(/^-|-$/g, '');
  return cleaned || fallback;
}

function extensionFor(contentType, filename) {
  const ext = String(filename || '').toLowerCase().match(/\.([a-z0-9]+)$/)?.[1];
  if (['jpg', 'jpeg', 'png', 'webp'].includes(ext)) return ext === 'jpeg' ? 'jpg' : ext;
  if (contentType === 'image/png') return 'png';
  if (contentType === 'image/webp') return 'webp';
  return 'jpg';
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'POST,OPTIONS')) return;
  if (req.method !== 'POST') {
    return methodNotAllowed(req, res, 'POST');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    if (!hasPageAccess(user, 'servis')) return forbidden(req, res);

    const supabaseUrl = String(process.env.SUPABASE_URL || '').replace(/\/+$/, '');
    const serviceRoleKey = String(
      process.env.SUPABASE_SERVICE_ROLE_KEY || process.env.SUPABASE_SERVICE_KEY || '',
    ).trim();
    if (!supabaseUrl || !serviceRoleKey) {
      throw new Error('SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required.');
    }

    const body = await readJson(req);
    const serviceId = safeSegment(body.serviceId, 'service');
    const filename = safeSegment(body.filename, 'image');
    const contentType = String(body.contentType || '').trim().toLowerCase();
    if (!allowedContentTypes.has(contentType)) {
      return badRequest(req, res, 'Sadece JPG, PNG veya WEBP görsel yüklenebilir.');
    }

    const base64 = String(body.data || '').replace(/^data:[^;]+;base64,/i, '').trim();
    if (!base64) return badRequest(req, res, 'Görsel verisi eksik.');

    const bytes = Buffer.from(base64, 'base64');
    if (!bytes.length) return badRequest(req, res, 'Görsel verisi okunamadı.');
    if (bytes.length > maxBytes) return badRequest(req, res, 'Görsel 5 MB sınırını aşıyor.');

    const ext = extensionFor(contentType, filename);
    const random = typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : crypto.randomBytes(16).toString('hex');
    const objectPath = `${serviceId}/${Date.now()}-${random}.${ext}`;
    const uploadUrl = `${supabaseUrl}/storage/v1/object/${bucket}/${encodeURIComponent(objectPath).replace(/%2F/g, '/')}`;

    const response = await fetch(uploadUrl, {
      method: 'POST',
      headers: {
        apikey: serviceRoleKey,
        authorization: `Bearer ${serviceRoleKey}`,
        'cache-control': '3600',
        'content-type': contentType,
        'x-upsert': 'false',
      },
      body: bytes,
    });

    if (!response.ok) {
      const text = await response.text().catch(() => '');
      throw new Error(`Supabase Storage upload failed: ${response.status} ${text}`);
    }

    return ok(req, res, {
      bucket,
      path: objectPath,
      url: `${supabaseUrl}/storage/v1/object/public/${bucket}/${objectPath}`,
      contentType,
      size: bytes.length,
    });
  } catch (error) {
    return serverError(req, res, error);
  }
};
