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
  loadDraftInvoicesForPayPage,
  verifyInvoiceHostedSession,
  verifyPosRefundTicket,
  signInvoiceHostedSession,
  getPublicBaseUrl,
} = require('./_lib/invoice_payment');
const { buildPaymentOgImage } = require('./_lib/payment_og_image');

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

function formatOgAmount(amount, currency) {
  const value = Number(amount);
  const safe = Number.isFinite(value) ? value : 0;
  const formatted = safe.toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const code = String(currency || 'TRY').toUpperCase();
  if (code === 'TRY' || code === 'TL') return `${formatted} TL`;
  if (code === 'USD') return `$${formatted}`;
  if (code === 'EUR') return `EUR ${formatted}`;
  return `${formatted} ${code}`;
}

function paymentPageUrls(req, token) {
  const base = getPublicBaseUrl(req).replace(/\/$/, '');
  const short = String(token || '').trim();
  if (!short) return { pageUrl: '', ogImageUrl: '' };
  const pageUrl = `${base}/p/${encodeURIComponent(short)}`;
  return { pageUrl, ogImageUrl: `${pageUrl}/og.png` };
}

function getQuery(req) {
  try {
    const url = new URL(req.url || '/', 'http://localhost');
    return Object.fromEntries(url.searchParams.entries());
  } catch {
    return {};
  }
}

async function buildHostedPageFromToken({
  token,
  session,
  query = {},
  status = '',
  req = null,
}) {
  const lookupToken =
    String(token || '').trim() ||
    String(verifyInvoiceHostedSession(session)?.token || '').trim();
  if (!lookupToken && !status) {
    return {
      statusCode: 400,
      html: '<h1>Eksik token</h1><p>Ödeme linki geçersiz.</p>',
    };
  }

  let invoiceNumbers = String(query.numbers || '')
    .split(',')
    .map((n) => n.trim())
    .filter(Boolean);
  let amount = query.amount;
  let currency = query.currency;
  let customerName = query.customer;
  let invoiceCount = Number(query.invoices || 0) || 0;
  let sessionToken = String(session || '').trim();
  let draftInvoices = [];

  if (lookupToken) {
    const link = await getPaymentLinkByToken(lookupToken);
    if (!link) {
      return {
        statusCode: 404,
        html: '<h1>Link bulunamadı</h1><p>Ödeme linki geçersiz veya süresi dolmuş.</p>',
      };
    }
    amount = Number(link.amount).toFixed(2);
    currency = link.currency || 'TRY';
    customerName = link.customer_name || '';
    invoiceCount = Array.isArray(link.invoice_ids) ? link.invoice_ids.length : 0;
    if (!invoiceNumbers.length) {
      invoiceNumbers = await getInvoiceNumbersForLink(link);
    }
    try {
      draftInvoices = await loadDraftInvoicesForPayPage(link);
    } catch (_) {
      draftInvoices = [];
    }
    if (!sessionToken) {
      sessionToken = signInvoiceHostedSession({
        kind: 'invoice-hosted',
        linkId: link.id,
        token: lookupToken,
        amount: Number(link.amount),
        currency: link.currency || 'TRY',
        customerId: link.customer_id,
        customerName,
        invoiceCount,
        invoiceNumbers,
      });
    }
  }

  return {
    statusCode: 200,
    html: buildCrmHostedPaymentPageHtml({
      sessionToken,
      token: lookupToken,
      amount,
      currency,
      customerName,
      invoiceCount,
      invoiceNumbers,
      invoices: draftInvoices,
      status,
      errorMessage: query.errmsg || '',
      ...paymentPageUrls(req, lookupToken),
    }),
  };
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
    const token = String(query.token || query.t || '').trim();
    const session = String(query.session || '').trim();
    const invoiceStatus = String(query.invoice || '').trim().toLowerCase();

    const wantsOg =
      query.og === '1' ||
      query.preview === '1' ||
      String(query.format || '').toLowerCase() === 'png';

    if (req.method === 'GET' && wantsOg && token) {
      const link = await getPaymentLinkByToken(token);
      if (!link) {
        res.statusCode = 404;
        res.setHeader('Content-Type', 'text/plain; charset=utf-8');
        res.end('Og image not found');
        return;
      }
      const numbers = await getInvoiceNumbersForLink(link);
      const { pageUrl } = paymentPageUrls(req, token);
      const png = await buildPaymentOgImage({
        amountLabel: formatOgAmount(link.amount, link.currency),
        pageUrl,
        invoiceLabel: (numbers || []).join(', '),
      });
      res.statusCode = 200;
      res.setHeader('Content-Type', 'image/png');
      res.setHeader('Cache-Control', 'public, max-age=3600');
      res.end(png);
      return;
    }

    // Kısa link (/p/TOKEN) veya eski uzun link → hosted ödeme ekranı
    if (
      req.method === 'GET' &&
      !action &&
      (token ||
        session ||
        invoiceStatus === 'success' ||
        invoiceStatus === 'fail')
    ) {
      const page = await buildHostedPageFromToken({
        token,
        session,
        query,
        status: invoiceStatus,
        req,
      });
      return sendHtml(res, page.statusCode, page.html);
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

    if (
      (req.method === 'GET' || req.method === 'POST') &&
      (action === 'verify-refund' || action === 'verify_refund')
    ) {
      const body = req.method === 'POST' ? await readBody(req) : {};
      const ticket = String(
        body.ticket || body.refund_ticket || query.ticket || '',
      ).trim();
      const verified = await verifyPosRefundTicket(ticket);
      return sendJson(res, verified.ok ? 200 : 400, verified);
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
          cardNumber: body.cardNumber || body.pan || body.pn,
          expireMonth:
            body.expireMonth || body.Ecom_Payment_Card_ExpDate_Month || body.em,
          expireYear:
            body.expireYear || body.Ecom_Payment_Card_ExpDate_Year || body.ey,
          cvc: body.sc || body.cvc || body.cv2 || body.cardSecurityCode,
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
