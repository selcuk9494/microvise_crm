'use strict';

const { getAuthenticatedUser, hasPageAccess } = require('./_lib/auth');
const {
  handleCors,
  ok,
  badRequest,
  forbidden,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');
const { parseTsmLogBuffer } = require('./_lib/tsm_log');

const maxFileBytes = 20 * 1024 * 1024;

async function readJson(req) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return req.body;
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

function decodeBase64File(raw) {
  const text = String(raw || '').trim();
  if (!text) return null;
  const comma = text.indexOf(',');
  const payload = text.startsWith('data:') && comma >= 0 ? text.slice(comma + 1) : text;
  try {
    const buffer = Buffer.from(payload, 'base64');
    return buffer.length ? buffer : null;
  } catch (_) {
    return null;
  }
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'POST,OPTIONS')) return;
  if (req.method !== 'POST') {
    return methodNotAllowed(req, res, 'POST');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    if (!hasPageAccess(user, 'tsm_log') && !hasPageAccess(user, 'formlar')) {
      return forbidden(req, res, 'TSM Log için yetkiniz yok.');
    }

    const body = await readJson(req);
    const fileName = String(body.fileName || 'tsm.xls').trim() || 'tsm.xls';
    const buffer = decodeBase64File(body.fileBase64);
    if (!buffer) {
      return badRequest(req, res, 'Excel dosyası gerekli.');
    }
    if (buffer.length > maxFileBytes) {
      return badRequest(req, res, 'Excel dosyası 20 MB sınırını aşıyor.');
    }

    const parsed = parseTsmLogBuffer(buffer, fileName);
    return ok(req, res, parsed);
  } catch (error) {
    const message = error instanceof Error ? error.message : 'Excel okunamadı.';
    if (/Excel|sayfa|format|Unsupported/i.test(message)) {
      return badRequest(req, res, `Excel okunamadı: ${message}`);
    }
    return serverError(req, res, error);
  }
};
