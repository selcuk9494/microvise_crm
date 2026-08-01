const { Pool, types } = require('pg');

// Keep Postgres `date` as YYYY-MM-DD strings. Default JS Date (UTC midnight)
// JSON-serializes to ...T00:00:00.000Z and shifts calendar day in UTC+3 UIs.
types.setTypeParser(types.builtins.DATE, (value) => value);

let pool;

function normalizeConnectionString(raw) {
  let value = String(raw || '').trim();
  if (!value) return '';
  value = value.replace(/^DATABASE_URL\s*=\s*/i, '');
  value = value.replace(/^POSTGRES_URL\s*=\s*/i, '');
  return value.trim();
}

function resolveDbConfig() {
  let connectionString = normalizeConnectionString(
    process.env.DATABASE_URL || process.env.POSTGRES_URL || process.env.NEON_DATABASE_URL,
  );
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

async function query(text, params = []) {
  const result = await getPool().query(text, params);
  return result;
}

module.exports = { query };
