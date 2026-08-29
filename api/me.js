const { getAuthenticatedUser } = require('./_lib/auth');
const {
  handleCors,
  ok,
  unauthorized,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');
const { query } = require('./_lib/db');
const { ensureInvoicePaymentLinksTable } = require('./_lib/invoice_payment');
const { sendPosPaymentReminders } = require('./_lib/invoice_mail');

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

function wantsPosReminderCron(req) {
  if (req.headers['x-vercel-cron']) return true;
  try {
    const url = new URL(req.url || '/', 'http://localhost');
    return url.searchParams.get('cron') === 'pos-reminders';
  } catch {
    return false;
  }
}

function isCronAuthorized(req) {
  const secret = String(process.env.CRON_SECRET || '').trim();
  const auth = String(req.headers.authorization || '');
  let querySecret = '';
  try {
    querySecret =
      new URL(req.url || '/', 'http://localhost').searchParams.get('secret') ||
      '';
  } catch (_) {}
  if (secret) {
    return auth === `Bearer ${secret}` || querySecret === secret;
  }
  if (req.headers['x-vercel-cron']) return true;
  return process.env.VERCEL !== '1';
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,OPTIONS')) return;
  if (req.method !== 'GET') {
    return methodNotAllowed(req, res, 'GET');
  }

  try {
    if (wantsPosReminderCron(req)) {
      if (!isCronAuthorized(req)) {
        return unauthorized(req, res, 'Cron yetkisi yok.');
      }
      await ensureInvoicePaymentLinksTable();
      const result = await sendPosPaymentReminders({
        req,
        onlyOverdue: true,
        skipAlreadyReminded: true,
      });
      return ok(req, res, result);
    }

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
