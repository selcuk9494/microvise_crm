const { getAuthenticatedUser } = require('./_lib/auth');
const {
  handleCors,
  ok,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    const user = await getAuthenticatedUser(req);
    if (!user) return unauthorized(req, res);
    return ok(req, res, user);
  } catch (error) {
    return serverError(req, res, error);
  }
};
