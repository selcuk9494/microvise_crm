function setCorsHeaders(req, res, allowedMethods = 'GET,POST,PATCH,DELETE,OPTIONS') {
  const origin = req?.headers?.origin || '*';
  res.setHeader('Access-Control-Allow-Origin', origin);
  res.setHeader('Vary', 'Origin');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Requested-With',
  );
  res.setHeader('Access-Control-Allow-Methods', allowedMethods);
}

function handleCors(req, res, allowedMethods = 'GET,POST,PATCH,DELETE,OPTIONS') {
  setCorsHeaders(req, res, allowedMethods);
  if (req.method === 'OPTIONS') {
    res.statusCode = 204;
    res.end();
    return true;
  }
  return false;
}

function json(req, res, statusCode, payload) {
  setCorsHeaders(req, res);
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function ok(req, res, payload) {
  return json(req, res, 200, payload);
}

function badRequest(req, res, message) {
  return json(req, res, 400, { error: message });
}

function unauthorized(req, res, message = 'Unauthorized') {
  return json(req, res, 401, { error: message });
}

function forbidden(req, res, message = 'Forbidden') {
  return json(req, res, 403, { error: message });
}

function methodNotAllowed(req, res, method = 'GET') {
  setCorsHeaders(req, res, `${method},OPTIONS`);
  res.setHeader('Allow', method);
  return json(req, res, 405, { error: `Method not allowed. Use ${method}.` });
}

function serverError(req, res, error) {
  console.error(error);
  return json(req, res, 500, {
    error: error instanceof Error ? error.message : 'Internal server error',
  });
}

function parseBoolean(value, fallback = false) {
  if (typeof value === 'boolean') return value;
  if (typeof value !== 'string') return fallback;
  return value === 'true' || value === '1';
}

function parseInteger(value, fallback, { min, max } = {}) {
  const parsed = Number.parseInt(String(value ?? ''), 10);
  if (Number.isNaN(parsed)) return fallback;
  if (typeof min === 'number' && parsed < min) return min;
  if (typeof max === 'number' && parsed > max) return max;
  return parsed;
}

module.exports = {
  handleCors,
  ok,
  json,
  badRequest,
  unauthorized,
  forbidden,
  methodNotAllowed,
  serverError,
  parseBoolean,
  parseInteger,
};
