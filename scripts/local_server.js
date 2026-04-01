const fs = require('fs');
const path = require('path');
const http = require('http');
const { URL } = require('url');

const rootDir = path.resolve(__dirname, '..');
const webDir = path.join(rootDir, 'build', 'web');

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  const content = fs.readFileSync(filePath, 'utf8');
  for (const rawLine of content.split('\n')) {
    const line = rawLine.trim();
    if (!line) continue;
    if (line.startsWith('#')) continue;
    const eq = line.indexOf('=');
    if (eq <= 0) continue;
    const key = line.slice(0, eq).trim();
    let value = line.slice(eq + 1).trim();
    if (!key) continue;
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] == null) {
      process.env[key] = value;
    }
  }
}

loadEnvFile(path.join(rootDir, '.env.local'));
loadEnvFile(path.join(rootDir, '.env'));

function contentTypeFor(filePath) {
  const ext = path.extname(filePath).toLowerCase();
  switch (ext) {
    case '.html':
      return 'text/html; charset=utf-8';
    case '.js':
      return 'application/javascript; charset=utf-8';
    case '.css':
      return 'text/css; charset=utf-8';
    case '.json':
      return 'application/json; charset=utf-8';
    case '.png':
      return 'image/png';
    case '.jpg':
    case '.jpeg':
      return 'image/jpeg';
    case '.svg':
      return 'image/svg+xml';
    case '.ico':
      return 'image/x-icon';
    case '.wasm':
      return 'application/wasm';
    case '.ttf':
      return 'font/ttf';
    case '.otf':
      return 'font/otf';
    case '.woff':
      return 'font/woff';
    case '.woff2':
      return 'font/woff2';
    default:
      return 'application/octet-stream';
  }
}

function send(res, statusCode, headers, body) {
  res.statusCode = statusCode;
  for (const [k, v] of Object.entries(headers || {})) {
    res.setHeader(k, v);
  }
  if (body == null) return res.end();
  res.end(body);
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Authorization, Content-Type, Accept',
  );
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,PATCH,DELETE,OPTIONS');
}

function getApiHandler(urlPath) {
  const relative = urlPath.replace(/^\/api\/?/, '');
  if (!relative) return null;
  const clean = relative.replace(/\/+$/, '');
  const handlerPath = path.join(rootDir, 'api', `${clean}.js`);
  if (!fs.existsSync(handlerPath)) return null;
  delete require.cache[require.resolve(handlerPath)];
  return require(handlerPath);
}

function safeJoin(root, requestPath) {
  const decoded = decodeURIComponent(requestPath);
  const normalized = decoded.replace(/^\/+/, '');
  const resolved = path.resolve(root, normalized);
  if (!resolved.startsWith(root)) return null;
  return resolved;
}

const server = http.createServer(async (req, res) => {
  try {
    const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
    const pathname = url.pathname || '/';

    if (pathname.startsWith('/api/')) {
      setCors(res);
      if (req.method === 'OPTIONS') return send(res, 204, {}, null);
      req.query = {};
      for (const [key, value] of url.searchParams.entries()) {
        req.query[key] = value;
      }

      if (pathname === '/api/_local/stats') {
        try {
          const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
          const tables = [
            'users',
            'customers',
            'work_orders',
            'service_records',
            'lines',
            'licenses',
            'invoices',
            'invoice_items',
            'payments',
            'transactions',
          ];
          const counts = {};
          for (const table of tables) {
            try {
              const result = await query(
                `select count(*)::int as c from public.${table}`,
              );
              counts[table] = result.rows[0]?.c ?? 0;
            } catch (e) {
              counts[table] = null;
            }
          }
          return send(
            res,
            200,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({ ok: true, counts }),
          );
        } catch (e) {
          return send(
            res,
            500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      const handler = getApiHandler(pathname);
      if (!handler) return send(res, 404, { 'Content-Type': 'application/json' }, JSON.stringify({ error: 'Not found' }));
      return handler(req, res);
    }

    if (!fs.existsSync(webDir)) {
      return send(
        res,
        500,
        { 'Content-Type': 'text/plain; charset=utf-8' },
        'build/web bulunamadı. Önce flutter build web çalıştırın.',
      );
    }

    const filePath = safeJoin(webDir, pathname);
    if (filePath && fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
      return send(
        res,
        200,
        { 'Content-Type': contentTypeFor(filePath) },
        fs.readFileSync(filePath),
      );
    }

    const indexPath = path.join(webDir, 'index.html');
    return send(
      res,
      200,
      { 'Content-Type': 'text/html; charset=utf-8' },
      fs.readFileSync(indexPath),
    );
  } catch (err) {
    return send(
      res,
      500,
      { 'Content-Type': 'text/plain; charset=utf-8' },
      err instanceof Error ? err.message : 'Server error',
    );
  }
});

const requestedPortRaw = process.env.PORT;
const requestedPort = Number(requestedPortRaw || 3000);

server.on('error', (err) => {
  if (err && err.code === 'EADDRINUSE') {
    if (requestedPortRaw) {
      console.error(`PORT ${requestedPort} kullanımda. Farklı PORT verin.`);
      process.exit(1);
    }
    console.error(
      'PORT 3000 kullanımda. PORT=0 npm run local-web ile otomatik port seçebilirsiniz.',
    );
    process.exit(1);
  }
  console.error(err);
  process.exit(1);
});

const portToBind = requestedPortRaw ? requestedPort : 0;
server.listen(portToBind, '127.0.0.1', () => {
  const address = server.address();
  const port =
    address && typeof address === 'object' && address.port ? address.port : portToBind;
  console.log(`Local web: http://127.0.0.1:${port}`);
});
