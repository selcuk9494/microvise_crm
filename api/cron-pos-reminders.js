const { handleCors, methodNotAllowed, ok, unauthorized, serverError } = require('./_lib/http');
const { ensureInvoicePaymentLinksTable } = require('./_lib/invoice_payment');
const { sendPosPaymentReminders } = require('./_lib/invoice_mail');

function isCronAuthorized(req) {
  const secret = String(process.env.CRON_SECRET || '').trim();
  const auth = String(req.headers.authorization || '');
  const querySecret = String(req.query?.secret || '').trim();
  if (secret) {
    return auth === `Bearer ${secret}` || querySecret === secret;
  }
  if (req.headers['x-vercel-cron']) return true;
  return process.env.VERCEL !== '1';
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,POST,OPTIONS')) return;
  if (req.method !== 'GET' && req.method !== 'POST') {
    return methodNotAllowed(req, res, 'GET');
  }
  if (!isCronAuthorized(req)) {
    return unauthorized(req, res, 'Cron yetkisi yok.');
  }
  try {
    await ensureInvoicePaymentLinksTable();
    const result = await sendPosPaymentReminders({
      req,
      onlyOverdue: true,
      skipAlreadyReminded: true,
    });
    return ok(req, res, result);
  } catch (error) {
    return serverError(req, res, error);
  }
};
