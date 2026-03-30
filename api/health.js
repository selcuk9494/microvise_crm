const { ok, methodNotAllowed, serverError } = require('./_lib/http');
const { query } = require('./_lib/db');

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const result = await query('select now() as now');
    return ok(res, {
      ok: true,
      databaseTime: result.rows[0]?.now ?? null,
    });
  } catch (error) {
    return serverError(res, error);
  }
};
