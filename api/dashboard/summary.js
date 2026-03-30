const { getAuthenticatedUser, hasPageAccess } = require('../_lib/auth');
const { query } = require('../_lib/db');
const { ok, forbidden, unauthorized, methodNotAllowed, serverError } = require('../_lib/http');

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    if (!hasPageAccess(user, 'panel')) {
      return forbidden(res, 'Panele erişim yetkiniz yok.');
    }

    const result = await query('select * from public.dashboard_snapshot()');
    return ok(res, result.rows[0] || {});
  } catch (error) {
    return serverError(res, error);
  }
};
