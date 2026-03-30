const { getAuthenticatedUser } = require('./_lib/auth');
const { ok, unauthorized, methodNotAllowed, serverError } = require('./_lib/http');

module.exports = async (req, res) => {
  if (req.method !== 'GET') {
    return methodNotAllowed(res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(res);
    return ok(res, user);
  } catch (error) {
    return serverError(res, error);
  }
};

