const {
  appleWebClientId,
  appleRedirectUri,
  appleAudiences,
} = require('../_lib/apple_identity');
const {
  handleCors,
  ok,
  methodNotAllowed,
  serverError,
} = require('../_lib/http');

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    const clientId = appleWebClientId();
    const redirectUri = appleRedirectUri(req);
    return ok(req, res, {
      enabled: Boolean(clientId),
      clientId,
      redirectUri,
      audiences: appleAudiences(),
    });
  } catch (error) {
    return serverError(req, res, error);
  }
};
