const { handleCors, ok, methodNotAllowed, serverError } = require('./_lib/http');
const { query } = require('./_lib/db');

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    const result = await query('select now() as now');
    return ok(req, res, {
      ok: true,
      databaseTime: result.rows[0]?.now ?? null,
    });
  } catch (error) {
    return serverError(req, res, error);
  }
};
