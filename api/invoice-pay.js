const {
  handleCors,
  methodNotAllowed,
  serverError,
} = require('./_lib/http');
const {
  ensureInvoicePaymentLinksTable,
  startPaymentRedirect,
  handlePaymentCallback,
  getPaymentLinkByToken,
  getHostedSessionInfo,
  startHostedPayment,
  buildCrmHostedPaymentPageHtml,
  getInvoiceNumbersForLink,
  verifyInvoiceHostedSession,
} = require('./_lib/invoice_payment');

function sendHtml(res, statusCode, html) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'text/html; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(html);
}

function sendJson(res, statusCode, payload) {
  res.statusCode = statusCode;
  res.setHeader('Content-Type', 'application/json; charset=utf-8');
  res.setHeader('Cache-Control', 'no-store');
  res.end(JSON.stringify(payload));
}

function getQuery(req) {
  try {
    const url = new URL(req.url || '/', 'http://localhost');
    return Object.fromEntries(url.searchParams.entries());
  } catch {
    return {};
  }
}

async function readBody(req) {
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return req.body;
  }
  const chunks = [];
  for await (const chunk of req) chunks.push(chunk);
  const raw = Buffer.concat(chunks).toString('utf8');
  if (!raw.trim()) return {};
  const contentType = String(req.headers['content-type'] || '').toLowerCase();
  if (contentType.includes('application/json')) {
    try {
      return JSON.parse(raw);
    } catch {
      return {};
    }
  }
  if (
    contentType.includes('application/x-www-form-urlencoded') ||
    raw.includes('=')
  ) {
    const params = new URLSearchParams(raw);
    return Object.fromEntries(params.entries());
  }
  try {
    return JSON.parse(raw);
  } catch {
    return {};
  }
}

module.exports = async (req, res) => {
  if (handleCors(req, res, 'GET,POST,OPTIONS')) return;

  try {
    await ensureInvoicePaymentLinksTable();
    const query = getQuery(req);
    const action = String(query.action || '').trim().toLowerCase();
    const token = String(query.token || '').trim();
    const session = String(query.session || '').trim();
    const invoiceStatus = String(query.invoice || '').trim().toLowerCase();

    // Hosted ödeme ekranı (CRM fallback; WP /fatura-odeme hazır olunca env ile oraya alınır)
    if (
      req.method === 'GET' &&
      !action &&
      (session || invoiceStatus === 'success' || invoiceStatus === 'fail')
    ) {
      let invoiceNumbers = String(query.numbers || '')
        .split(',')
        .map((n) => n.trim())
        .filter(Boolean);
      let amount = query.amount;
      let currency = query.currency;
      let customerName = query.customer;
      let invoiceCount = Number(query.invoices || 0) || 0;

      const lookupToken =
        token ||
        (session ? verifyInvoiceHostedSession(session)?.token : '') ||
        '';
      if (lookupToken) {
        try {
          const link = await getPaymentLinkByToken(lookupToken);
          if (link) {
            if (!amount) amount = Number(link.amount).toFixed(2);
            if (!currency) currency = link.currency || 'TRY';
            if (!customerName) customerName = link.customer_name || '';
            if (!invoiceCount && Array.isArray(link.invoice_ids)) {
              invoiceCount = link.invoice_ids.length;
            }
            if (!invoiceNumbers.length) {
              invoiceNumbers = await getInvoiceNumbersForLink(link);
            }
          }
        } catch {
          // query params ile devam
        }
      }

      return sendHtml(
        res,
        200,
        buildCrmHostedPaymentPageHtml({
          sessionToken: session,
          token: lookupToken || token,
          amount,
          currency,
          customerName,
          invoiceCount,
          invoiceNumbers,
          status: invoiceStatus,
          errorMessage: query.errmsg || '',
        }),
      );
    }

    if (req.method === 'POST' && action === 'callback') {
      const payload = await readBody(req);
      const result = await handlePaymentCallback(token, payload);
      if (result.redirect) {
        res.statusCode = result.statusCode || 302;
        res.setHeader('Location', result.redirect);
        res.setHeader('Cache-Control', 'no-store');
        res.end();
        return;
      }
      return sendHtml(res, result.statusCode, result.html);
    }

    if (
      (req.method === 'GET' || req.method === 'POST') &&
      (action === 'session' || action === 'hosted-session')
    ) {
      const body = req.method === 'POST' ? await readBody(req) : {};
      const sessionToken = String(
        body.session || body.sessionToken || query.session || '',
      ).trim();
      try {
        const info = await getHostedSessionInfo({
          sessionToken,
          token: token || body.token,
        });
        return sendJson(res, 200, info);
      } catch (error) {
        return sendJson(res, error.statusCode || 400, {
          ok: false,
          message: error.message || 'Oturum okunamadı',
        });
      }
    }

    if (req.method === 'POST' && (action === 'pay' || action === 'hosted-pay')) {
      const body = await readBody(req);
      const sessionToken = String(body.session || body.sessionToken || '').trim();
      const result = await startHostedPayment({
        sessionToken,
        token: token || body.token,
        req,
        card: {
          cardHolderName: body.cardHolderName || body.cardholdername,
          cardNumber: body.cardNumber || body.pan,
          expireMonth: body.expireMonth || body.Ecom_Payment_Card_ExpDate_Month,
          expireYear: body.expireYear || body.Ecom_Payment_Card_ExpDate_Year,
          cvc: body.cvc || body.cv2,
        },
      });
      return sendJson(res, result.statusCode, result.json);
    }

    if (req.method === 'GET' && action === 'status' && token) {
      const link = await getPaymentLinkByToken(token);
      res.statusCode = link ? 200 : 404;
      res.setHeader('Content-Type', 'application/json; charset=utf-8');
      res.end(
        JSON.stringify({
          ok: Boolean(link),
          status: link?.status || null,
          amount: link ? Number(link.amount) : null,
          currency: link?.currency || null,
        }),
      );
      return;
    }

    if (req.method === 'GET' || req.method === 'POST') {
      if (!token) {
        return sendHtml(
          res,
          400,
          '<h1>Eksik token</h1><p>Ödeme linki geçersiz.</p>',
        );
      }
      if (action === 'callback') {
        const result = await handlePaymentCallback(token, query);
        if (result.redirect) {
          res.statusCode = result.statusCode || 302;
          res.setHeader('Location', result.redirect);
          res.setHeader('Cache-Control', 'no-store');
          res.end();
          return;
        }
        return sendHtml(res, result.statusCode, result.html);
      }
      const result = await startPaymentRedirect(token, req);
      return sendHtml(res, result.statusCode, result.html);
    }

    return methodNotAllowed(req, res, 'GET,POST');
  } catch (error) {
    return serverError(req, res, error);
  }
};
