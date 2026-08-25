const { getAuthenticatedUser } = require('./_lib/auth');
const {
  handleCors,
  ok,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');
const { query } = require('./_lib/db');

function wantsHealth(req) {
  try {
    const url = new URL(req.url || '/', 'http://localhost');
    if (url.searchParams.get('health') === '1') return true;
    // Rewrite from /api/health may leave the original path in some runtimes.
    return /\/api\/health(?:\?|$)/.test(url.pathname + url.search);
  } catch {
    return false;
  }
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    if (wantsHealth(req)) {
      const result = await query('select now() as now');
      return ok(req, res, {
        ok: true,
        databaseTime: result.rows[0]?.now ?? null,
      });
    }

    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    return ok(req, res, user);
  } catch (error) {
    return serverError(req, res, error);
  }
};
