const { Pool, types } = require('pg');

// Keep Postgres `date` as YYYY-MM-DD strings. Default JS Date (UTC midnight)
// JSON-serializes to ...T00:00:00.000Z and shifts calendar day in UTC+3 UIs.
function keepDateAsString(typesApi) {
  try {
    typesApi.setTypeParser(typesApi.builtins.DATE, (value) => value);
  } catch (_) {
    // ignore missing builtins in alternate drivers
  }
}
keepDateAsString(types);

let pool;
let neonPool;
let neonLoadError;

function normalizeConnectionString(raw) {
  let value = String(raw || '').trim();
  if (!value) return '';
  value = value.replace(/^DATABASE_URL\s*=\s*/i, '');
  value = value.replace(/^POSTGRES_URL\s*=\s*/i, '');
  return value.trim();
}

function connectionStringFromEnv() {
  return normalizeConnectionString(
    process.env.DATABASE_URL || process.env.POSTGRES_URL || process.env.NEON_DATABASE_URL,
  );
}

function isNeonHost(connectionString) {
  try {
    const host = new URL(connectionString).hostname.toLowerCase();
    return host === 'neon.tech' || host.endsWith('.neon.tech');
  } catch (_) {
    return /neon\.tech/i.test(connectionString || '');
  }
}

/**
 * Neon TCP :5432 SSL is blocked/broken on some local networks (SSLRequest → "N").
 * Neon serverless WebSocket uses :443 and supports multi-statement SQL + transactions.
 */
function getNeonPool() {
  if (neonPool) return neonPool;
  if (neonLoadError) throw neonLoadError;
  const connectionString = connectionStringFromEnv();
  if (!connectionString) {
    throw new Error(
      'DATABASE_URL is not configured. Set DATABASE_URL/POSTGRES_URL/NEON_DATABASE_URL or PGHOST/PGDATABASE/PGUSER/PGPASSWORD.',
    );
  }
  try {
    const neonDriver = require('@neondatabase/serverless');
    if (neonDriver.types) keepDateAsString(neonDriver.types);
    neonDriver.neonConfig.webSocketConstructor = require('ws');
    neonPool = new neonDriver.Pool({
      connectionString,
      max: 4,
      connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 8000),
      idleTimeoutMillis: 10000,
    });
    neonPool.on('error', (err) => {
      console.error(err);
    });
    return neonPool;
  } catch (err) {
    neonLoadError = err;
    throw err;
  }
}

function resolveDbConfig() {
  let connectionString = connectionStringFromEnv();
  if (connectionString) {
    let sslMode = process.env.PGSSLMODE || '';
    let parsedConnectionUrl = null;
    try {
      const parsed = new URL(connectionString);
      parsedConnectionUrl = parsed;
      if (!sslMode) {
        sslMode = parsed.searchParams.get('sslmode') || '';
      }
    } catch (_) {
      // ignore URL parse errors and fall back to PGSSLMODE
    }

    const normalized = String(sslMode || '').toLowerCase();
    const ssl =
      normalized === 'disable' || normalized === 'false' ? false : { rejectUnauthorized: false };
    if (ssl === false && parsedConnectionUrl) {
      parsedConnectionUrl.searchParams.delete('sslmode');
      parsedConnectionUrl.searchParams.delete('ssl');
      connectionString = parsedConnectionUrl.toString();
    }

    return {
      connectionString,
      ssl,
    };
  }

  const host = process.env.PGHOST;
  const database = process.env.PGDATABASE;
  const user = process.env.PGUSER;
  const password = process.env.PGPASSWORD;
  const port = process.env.PGPORT ? Number.parseInt(process.env.PGPORT, 10) : undefined;

  if (!host || !database || !user) {
    throw new Error(
      'DATABASE_URL is not configured. Set DATABASE_URL/POSTGRES_URL/NEON_DATABASE_URL or PGHOST/PGDATABASE/PGUSER/PGPASSWORD.',
    );
  }

  const normalized = String(process.env.PGSSLMODE || '').toLowerCase();
  const ssl =
    normalized === 'disable' || normalized === 'false' ? false : { rejectUnauthorized: false };

  return {
    host,
    database,
    user,
    password,
    port,
    ssl,
  };
}

function getPool() {
  if (!pool) {
    pool = new Pool({
      ...resolveDbConfig(),
      max: 4,
      connectionTimeoutMillis: Number(process.env.PG_CONNECTION_TIMEOUT_MS || 5000),
      idleTimeoutMillis: 10000,
      query_timeout: Number(process.env.PG_QUERY_TIMEOUT_MS || 15000),
      statement_timeout: Number(process.env.PG_STATEMENT_TIMEOUT_MS || 15000),
    });
    pool.on('error', (err) => {
      console.error(err);
    });
  }
  return pool;
}

function shouldUseNeonWs() {
  if (String(process.env.MICROVISE_DB_DRIVER || '').trim().toLowerCase() === 'pg') {
    return false;
  }
  if (String(process.env.MICROVISE_DB_DRIVER || '').trim().toLowerCase() === 'neon') {
    return true;
  }
  const connectionString = connectionStringFromEnv();
  return !!(connectionString && isNeonHost(connectionString));
}

async function query(text, params = []) {
  if (shouldUseNeonWs()) {
    return getNeonPool().query(text, params);
  }
  const result = await getPool().query(text, params);
  return result;
}

function activePool() {
  return shouldUseNeonWs() ? getNeonPool() : getPool();
}

/**
 * Run work inside a single DB transaction (BEGIN/COMMIT/ROLLBACK).
 * `fn` receives a query(text, params) bound to that client.
 */
async function withTransaction(fn) {
  const client = await activePool().connect();
  try {
    await client.query('BEGIN');
    const txQuery = (text, params = []) => client.query(text, params);
    const result = await fn(txQuery);
    await client.query('COMMIT');
    return result;
  } catch (error) {
    try {
      await client.query('ROLLBACK');
    } catch (_) {
      // ignore rollback errors
    }
    throw error;
  } finally {
    client.release();
  }
}

module.exports = { query, withTransaction };
