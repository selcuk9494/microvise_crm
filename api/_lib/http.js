function json(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.end(JSON.stringify(payload));
}

function ok(res, payload) {
  return json(res, 200, payload);
}

function badRequest(res, message) {
  return json(res, 400, { error: message });
}

function unauthorized(res, message = 'Unauthorized') {
  return json(res, 401, { error: message });
}

function forbidden(res, message = 'Forbidden') {
  return json(res, 403, { error: message });
}

function methodNotAllowed(res, method = 'GET') {
  res.setHeader('Allow', method);
  return json(res, 405, { error: `Method not allowed. Use ${method}.` });
}

function serverError(res, error) {
  console.error(error);
  return json(res, 500, {
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
