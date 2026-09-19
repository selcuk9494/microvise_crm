const { handleCors } = require('../_lib/http');

function htmlPage(script) {
  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Apple ile giriş</title>
</head>
<body>
  <script>${script}</script>
</body>
</html>`;
}

async function readRawBody(req) {
  if (typeof req.body === 'string') return req.body;
  if (req.body && typeof req.body === 'object' && !Buffer.isBuffer(req.body)) {
    return new URLSearchParams(req.body).toString();
  }
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  return Buffer.concat(chunks).toString('utf8');
}

function callbackScript(href) {
  const safeHref = JSON.stringify(href);
  return `
    (function () {
      var href = ${safeHref};
      try {
        if (window.opener) {
          window.opener.postMessage(href, '*');
          window.close();
          return;
        }
      } catch (_) {}
      try {
        window.parent.postMessage(href, '*');
      } catch (_) {}
      document.body.innerText = 'Apple girişi tamamlandı. Bu pencereyi kapatabilirsiniz.';
    })();
  `;
}

module.exports = async (req, res) => {
  if (req.method === 'OPTIONS') {
    handleCors(req, res, 'GET,POST,OPTIONS');
    return;
  }

  try {
    const url = new URL(req.url || '/', 'https://crm.microvise.net');
    let params = url.searchParams;

    if (req.method === 'POST') {
      const raw = await readRawBody(req);
      const posted = new URLSearchParams(raw);
      if (![...posted.keys()].length) {
        res.statusCode = 400;
        res.setHeader('Content-Type', 'text/plain; charset=utf-8');
        res.end('Apple yanıtı boş.');
        return;
      }
      const next = new URL(url.toString());
      next.search = '';
      for (const [key, value] of posted.entries()) {
        next.searchParams.set(key, value);
      }
      res.statusCode = 200;
      res.setHeader('Content-Type', 'text/html; charset=utf-8');
      res.end(htmlPage(callbackScript(next.toString())));
      return;
    }

    if (req.method !== 'GET') {
      res.statusCode = 405;
      res.end('Method not allowed');
      return;
    }

    const href = params.toString() ? url.toString() : `${url.origin}${url.pathname}`;
    res.statusCode = 200;
    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.end(htmlPage(callbackScript(href)));
  } catch (error) {
    res.statusCode = 500;
    res.setHeader('Content-Type', 'text/plain; charset=utf-8');
    res.end(error instanceof Error ? error.message : 'Apple geri dönüşü başarısız.');
  }
};
