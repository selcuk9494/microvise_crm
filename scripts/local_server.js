const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { URL } = require('url');

const rootDir = path.resolve(__dirname, '..');
const webDir = path.join(rootDir, 'build', 'web');
const akinsoftJobs = new Map();

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

async function readJson(req) {
  const chunks = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  if (!chunks.length) return {};
  const text = Buffer.concat(chunks).toString('utf8').trim();
  if (!text) return {};
  try {
    return JSON.parse(text);
  } catch (_) {
    return {};
  }
}

async function handleAkinsoftTestConnection(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const year = String(
    body.akinsoft_database_year || process.env.AKINSOFT_DATABASE_YEAR || '2026',
  ).trim();
  const pattern = String(
    body.akinsoft_database_pattern ||
      process.env.AKINSOFT_DATABASE_PATTERN ||
      'WOLVOX8_MICO_{year}_WOLVOX',
  ).trim();
  const database = String(
    body.akinsoft_mssql_database ||
      process.env.AKINSOFT_MSSQL_DATABASE ||
      pattern.replace('{year}', year),
  ).trim();
  const password = String(
    body.akinsoft_mssql_password || process.env.AKINSOFT_MSSQL_PASSWORD || '',
  ).trim();
  if (!password) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'SQL şifresi zorunludur.' }),
    );
  }

  const pool = await connectAkinsoftPool({
    server: String(
      body.akinsoft_mssql_host ||
        process.env.AKINSOFT_MSSQL_HOST ||
        '10.147.17.38',
    ).trim(),
    port: Number(body.akinsoft_mssql_port || process.env.AKINSOFT_MSSQL_PORT || 1433),
    database,
    user: String(
      body.akinsoft_mssql_username || process.env.AKINSOFT_MSSQL_USERNAME || 'sa',
    ).trim(),
    password,
    options: {
      encrypt: false,
      trustServerCertificate: true,
      enableArithAbort: true,
    },
    connectionTimeout: 8000,
    requestTimeout: 15000,
  });

  try {
    const version = await pool.request().query('select @@version as version');
    const tables = await pool.request().query(`
      select top 160
        s.name as schema_name,
        t.name as table_name
      from sys.tables t
      join sys.schemas s on s.schema_id = t.schema_id
      where
        upper(t.name) like '%FAT%'
        or upper(t.name) like '%CARI%'
        or upper(t.name) like '%STOK%'
        or upper(t.name) like '%EFAT%'
      order by t.name
    `);
    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({
        ok: true,
        database,
        version: String(version.recordset[0]?.version || '').split('\n')[0],
        candidateTables: tables.recordset,
      }),
    );
  } finally {
    await pool.close();
  }
}

function buildAkinsoftSqlConfig(body) {
  const year = String(
    body.akinsoft_database_year || process.env.AKINSOFT_DATABASE_YEAR || '2026',
  ).trim();
  const pattern = String(
    body.akinsoft_database_pattern ||
      process.env.AKINSOFT_DATABASE_PATTERN ||
      'WOLVOX8_MICO_{year}_WOLVOX',
  ).trim();
  const database = String(
    body.akinsoft_mssql_database ||
      process.env.AKINSOFT_MSSQL_DATABASE ||
      pattern.replace('{year}', year),
  ).trim();
  const password = String(
    body.akinsoft_mssql_password || process.env.AKINSOFT_MSSQL_PASSWORD || '',
  ).trim();
  if (!password) {
    const error = new Error('SQL şifresi zorunludur.');
    error.statusCode = 400;
    throw error;
  }
  return {
    database,
    config: {
      server: String(
        body.akinsoft_mssql_host ||
          process.env.AKINSOFT_MSSQL_HOST ||
          '10.147.17.38',
      ).trim(),
      port: Number(body.akinsoft_mssql_port || process.env.AKINSOFT_MSSQL_PORT || 1433),
      database,
      user: String(
        body.akinsoft_mssql_username ||
          process.env.AKINSOFT_MSSQL_USERNAME ||
          'sa',
      ).trim(),
      password,
      options: {
        encrypt: false,
        trustServerCertificate: true,
        enableArithAbort: true,
      },
      connectionTimeout: 8000,
      requestTimeout: 90000,
    },
  };
}

async function connectAkinsoftPool(config) {
  const sql = require('mssql');
  const pool = new sql.ConnectionPool(config);
  return pool.connect();
}

function withTimeout(promise, ms, message) {
  let timer;
  const timeout = new Promise((_, reject) => {
    timer = setTimeout(() => reject(new Error(message)), ms);
  });
  return Promise.race([promise, timeout]).finally(() => clearTimeout(timer));
}

function upsertEnvFileValues(filePath, values) {
  const lines = fs.existsSync(filePath)
    ? fs.readFileSync(filePath, 'utf8').split(/\r?\n/)
    : [];
  const keys = new Set(Object.keys(values));
  const seen = new Set();
  const nextLines = lines.map((line) => {
    const match = line.match(/^([A-Z0-9_]+)=/);
    if (!match || !keys.has(match[1])) return line;
    seen.add(match[1]);
    return `${match[1]}=${values[match[1]]}`;
  });
  for (const key of Object.keys(values)) {
    if (!seen.has(key)) nextLines.push(`${key}=${values[key]}`);
  }
  while (nextLines.length && nextLines[nextLines.length - 1] === '') {
    nextLines.pop();
  }
  fs.writeFileSync(filePath, `${nextLines.join('\n')}\n`, 'utf8');
}

async function handleAkinsoftSaveLocalSettings(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const map = {
    AKINSOFT_MSSQL_HOST: 'akinsoft_mssql_host',
    AKINSOFT_MSSQL_PORT: 'akinsoft_mssql_port',
    AKINSOFT_MSSQL_DATABASE: 'akinsoft_mssql_database',
    AKINSOFT_MSSQL_USERNAME: 'akinsoft_mssql_username',
    AKINSOFT_MSSQL_PASSWORD: 'akinsoft_mssql_password',
    AKINSOFT_DATABASE_YEAR: 'akinsoft_database_year',
    AKINSOFT_DATABASE_PATTERN: 'akinsoft_database_pattern',
  };
  const values = {};
  for (const [envKey, settingKey] of Object.entries(map)) {
    const value = String(body[settingKey] ?? '').trim();
    if (value) values[envKey] = value;
  }
  if (!Object.keys(values).length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'Kaydedilecek Akınsoft ayarı yok.' }),
    );
  }
  upsertEnvFileValues(path.join(rootDir, '.env.local'), values);
  for (const [key, value] of Object.entries(values)) {
    process.env[key] = value;
  }
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, savedKeys: Object.keys(values) }),
  );
}

function escapeSqlName(name) {
  return String(name).replace(/]/g, ']]');
}

function sanitizeSampleValue(value) {
  if (value == null) return null;
  if (value instanceof Date) return value.toISOString();
  if (Buffer.isBuffer(value)) return `<binary:${value.length}>`;
  const text = String(value);
  return text.length > 160 ? `${text.slice(0, 157)}...` : text;
}

async function describeAkinsoftTable(pool, schemaName, tableName) {
  const columns = await pool
    .request()
    .input('schema', schemaName)
    .input('table', tableName)
    .query(`
      select
        c.COLUMN_NAME as name,
        c.DATA_TYPE as type,
        c.IS_NULLABLE as nullable,
        c.CHARACTER_MAXIMUM_LENGTH as maxLength
      from INFORMATION_SCHEMA.COLUMNS c
      where c.TABLE_SCHEMA = @schema and c.TABLE_NAME = @table
      order by c.ORDINAL_POSITION
    `);

  const countResult = await pool
    .request()
    .query(
      `select count_big(1) as total from [${escapeSqlName(schemaName)}].[${escapeSqlName(tableName)}]`,
    );

  const sampleResult = await pool
    .request()
    .query(
      `select top 3 * from [${escapeSqlName(schemaName)}].[${escapeSqlName(tableName)}]`,
    );

  const columnNames = columns.recordset.map((row) => row.name);
  const samples = sampleResult.recordset.map((row) => {
    const cleaned = {};
    for (const key of Object.keys(row).slice(0, 18)) {
      cleaned[key] = sanitizeSampleValue(row[key]);
    }
    return cleaned;
  });

  return {
    schemaName,
    tableName,
    rowCount: Number(countResult.recordset[0]?.total || 0),
    columns: columns.recordset,
    sampleColumns: columnNames.slice(0, 18),
    samples,
  };
}

async function handleAkinsoftAnalyze(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }

  const body = await readJson(req);
  const { database, config } = buildAkinsoftSqlConfig(body);
  const pool = await connectAkinsoftPool(config);

  try {
    const version = await pool.request().query('select @@version as version');
    const tableSearch = await pool.request().query(`
      select top 80
        s.name as schema_name,
        t.name as table_name,
        p.rows as approx_rows
      from sys.tables t
      join sys.schemas s on s.schema_id = t.schema_id
      left join sys.partitions p on p.object_id = t.object_id and p.index_id in (0, 1)
      where
        upper(t.name) like '%FATURA%'
        or upper(t.name) like '%FAT%'
        or upper(t.name) like '%CARI%'
        or upper(t.name) like '%STOK%'
        or upper(t.name) like '%EFAT%'
      group by s.name, t.name, p.rows
      order by
        case
          when upper(t.name) in ('FATURA', 'CARI', 'STOK') then 0
          when upper(t.name) like 'FATURA%' then 1
          when upper(t.name) like 'STOK%' then 2
          when upper(t.name) like 'CARI%' then 3
          else 4
        end,
        t.name
    `);

    const targetNames = [
      'FATURA',
      'FATURA_KALEM',
      'FATURAHR',
      'FATURA_HR',
      'FATURA_DETAY',
      'FATURA_KDV',
      'CARI',
      'CARI_ADRES',
      'CARIHR',
      'STOK',
      'STOKHR',
      'STOK_HAREKET',
      'STOK_FIYAT',
    ];
    const found = [];
    const seen = new Set();
    for (const target of targetNames) {
      const row = tableSearch.recordset.find(
        (item) => String(item.table_name).toUpperCase() === target,
      );
      if (!row) continue;
      const key = `${row.schema_name}.${row.table_name}`;
      if (seen.has(key)) continue;
      seen.add(key);
      found.push(row);
    }
    for (const row of tableSearch.recordset) {
      if (found.length >= 12) break;
      const key = `${row.schema_name}.${row.table_name}`;
      if (seen.has(key)) continue;
      seen.add(key);
      found.push(row);
    }

    const tables = [];
    for (const row of found) {
      try {
        tables.push(
          await describeAkinsoftTable(pool, row.schema_name, row.table_name),
        );
      } catch (error) {
        tables.push({
          schemaName: row.schema_name,
          tableName: row.table_name,
          error: error instanceof Error ? error.message : String(error),
        });
      }
    }

    const columnSearch = await pool.request().query(`
      select top 180
        c.TABLE_SCHEMA as schema_name,
        c.TABLE_NAME as table_name,
        c.COLUMN_NAME as column_name,
        c.DATA_TYPE as data_type
      from INFORMATION_SCHEMA.COLUMNS c
      where
        upper(c.COLUMN_NAME) like '%FAT%'
        or upper(c.COLUMN_NAME) like '%CARI%'
        or upper(c.COLUMN_NAME) like '%STOK%'
        or upper(c.COLUMN_NAME) like '%EVRAK%'
        or upper(c.COLUMN_NAME) like '%BELGE%'
        or upper(c.COLUMN_NAME) like '%TARIH%'
        or upper(c.COLUMN_NAME) like '%TUTAR%'
        or upper(c.COLUMN_NAME) like '%MIKTAR%'
        or upper(c.COLUMN_NAME) like '%FIYAT%'
      order by c.TABLE_NAME, c.ORDINAL_POSITION
    `);

    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({
        ok: true,
        database,
        version: String(version.recordset[0]?.version || '').split('\n')[0],
        candidateTables: tableSearch.recordset,
        analyzedTables: tables,
        candidateColumns: columnSearch.recordset,
      }),
    );
  } finally {
    await pool.close();
  }
}

function numberOrZero(value) {
  if (value == null) return 0;
  if (typeof value === 'number') return Number.isFinite(value) ? value : 0;
  const parsed = Number.parseFloat(String(value).replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : 0;
}

const PAYMENT_CLOSE_TOLERANCE = 0.02;

function normalizeCurrency(value) {
  const text = textOrNull(value);
  if (!text) return 'TRY';
  const upper = text.toLocaleUpperCase('tr-TR').trim();
  if (upper === 'KPB' || upper.includes('KPB')) {
    return 'TRY';
  }
  if (
    upper === '$' ||
    upper.includes('USD') ||
    upper.includes('DOLAR') ||
    upper.includes('DOVIZ') ||
    upper.includes('DÖVİZ')
  ) {
    return 'USD';
  }
  if (upper === '€' || upper.includes('EUR') || upper.includes('EURO')) {
    return 'EUR';
  }
  if (upper === '£' || upper.includes('GBP') || upper.includes('STERLIN')) {
    return 'GBP';
  }
  if (upper === 'TL' || upper.includes('TRY') || upper.includes('TURK')) {
    return 'TRY';
  }
  return ['TRY', 'USD', 'EUR', 'GBP'].includes(upper) ? upper : 'TRY';
}

function akinsoftAccountText(row) {
  const kpbDvz = numberOrZero(pick(row, ['KPBDVZ']));
  if (kpbDvz === 1) return 'KPB';
  if (kpbDvz === 0 && pick(row, ['KPBDVZ']) != null) return 'DÖVİZ';

  const direct = textOrNull(
    pick(
      row,
      [
        'HESAP',
        'HESAP_TURU',
        'HESAP_BIRIMI',
        'HESAP_ADI',
        'HESAP_SEKLI',
        'PARA_HESABI',
        'PARA_TURU',
        'PARA_BIRIMI',
        'PB',
      ],
      '',
    ),
  );
  if (direct) return direct.toLocaleUpperCase('tr-TR').trim();

  for (const [key, value] of Object.entries(row || {})) {
    const keyUpper = String(key).toLocaleUpperCase('tr-TR');
    const valueUpper = String(value ?? '').toLocaleUpperCase('tr-TR').trim();
    if (!valueUpper) continue;
    if (
      keyUpper.includes('HESAP') ||
      keyUpper.includes('PARA') ||
      keyUpper === 'PB'
    ) {
      return valueUpper;
    }
  }
  return '';
}

function isAkinsoftLocalAccount(row) {
  const kpbDvz = pick(row, ['KPBDVZ']);
  if (kpbDvz != null) return numberOrZero(kpbDvz) === 1;

  const account = akinsoftAccountText(row);
  if (account === 'KPB' || account.includes('KPB')) return true;

  const foreignFlag = parseAkinsoftBool(
    pick(row, ['DOVIZ_KULLAN', 'DOVIZLI', 'DVZ_KULLAN', 'DOVIZ_HESABI']),
  );
  return foreignFlag === false;
}

function isAkinsoftForeignAccount(row) {
  const kpbDvz = pick(row, ['KPBDVZ']);
  if (kpbDvz != null) return numberOrZero(kpbDvz) === 0;

  const account = akinsoftAccountText(row);
  if (
    account.includes('DOVIZ') ||
    account.includes('DÖVİZ') ||
    account.includes('USD') ||
    account.includes('DOLAR')
  ) {
    return true;
  }
  const foreignFlag = parseAkinsoftBool(
    pick(row, ['DOVIZ_KULLAN', 'DOVIZLI', 'DVZ_KULLAN', 'DOVIZ_HESABI']),
  );
  return foreignFlag === true;
}

function resolveAkinsoftItemCurrency(row) {
  if (isAkinsoftLocalAccount(row)) return 'TRY';
  if (isAkinsoftForeignAccount(row)) {
    const symbolCurrency = normalizeCurrency(
      pick(row, ['SIMGE', 'DOVIZ_BIRIMI', 'DOVIZ_ADI', 'DVZ_BIRIMI']),
    );
    return symbolCurrency === 'TRY' ? 'USD' : symbolCurrency;
  }
  return normalizeCurrency(
    pick(row, [
      'SIMGE',
      'DOVIZ_BIRIMI',
      'DOVIZ_KULLAN',
      'DOVIZ_ADI',
      'DVZ_BIRIMI',
      'PARA_BIRIMI',
    ]),
  );
}

function textOrNull(value) {
  const text = String(value ?? '').trim();
  return text.length ? text : null;
}

function localEInvoiceNumber(value) {
  return String(value ?? '').trim().replace(/^\d{9}-/, '');
}

function taxNumberOrNull(value) {
  const digits = String(value ?? '').replace(/[^0-9]/g, '');
  return digits.length ? digits : null;
}

function dateOrIso(value) {
  if (!value) return null;
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) return null;
  return date.toISOString();
}

/** mssql DateTime için güvenli tarih; Invalid Date üretmez. */
function toSqlDate(value, fallback = null) {
  if (value == null || value === '') return fallback;
  if (value instanceof Date && !Number.isNaN(value.getTime())) {
    return new Date(
      Date.UTC(
        value.getUTCFullYear(),
        value.getUTCMonth(),
        value.getUTCDate(),
        12,
        0,
        0,
      ),
    );
  }
  const raw = String(value).trim();
  const isoDay = raw.match(/^(\d{4}-\d{2}-\d{2})/);
  if (isoDay) {
    const parsed = new Date(`${isoDay[1]}T12:00:00`);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  const dmy = raw.match(/^(\d{1,2})[./](\d{1,2})[./](\d{4})/);
  if (dmy) {
    const day = dmy[1].padStart(2, '0');
    const month = dmy[2].padStart(2, '0');
    const parsed = new Date(`${dmy[3]}-${month}-${day}T12:00:00`);
    if (!Number.isNaN(parsed.getTime())) return parsed;
  }
  const parsed = new Date(raw);
  if (!Number.isNaN(parsed.getTime())) {
    return new Date(
      Date.UTC(
        parsed.getUTCFullYear(),
        parsed.getUTCMonth(),
        parsed.getUTCDate(),
        12,
        0,
        0,
      ),
    );
  }
  return fallback;
}

function bindSqlValue(request, sql, param, value) {
  if (value === null || value === undefined) {
    request.input(param, sql.NVarChar, null);
    return;
  }
  if (value instanceof Date) {
    if (Number.isNaN(value.getTime())) {
      throw new Error(`Geçersiz tarih parametresi: ${param}`);
    }
    request.input(param, sql.DateTime, value);
    return;
  }
  if (typeof value === 'number') {
    request.input(
      param,
      Number.isInteger(value) ? sql.BigInt : sql.Float,
      value,
    );
    return;
  }
  if (typeof value === 'boolean') {
    request.input(param, sql.Bit, value);
    return;
  }
  request.input(param, sql.NVarChar, String(value));
}

function pick(row, names, fallback = null) {
  if (!row) return fallback;
  for (const name of names) {
    if (row[name] != null && String(row[name]).trim() !== '') return row[name];
  }
  const byUpperName = new Map(
    Object.keys(row).map((key) => [
      String(key).toLocaleUpperCase('tr-TR'),
      key,
    ]),
  );
  for (const name of names) {
    const actual = byUpperName.get(String(name).toLocaleUpperCase('tr-TR'));
    if (actual && row[actual] != null && String(row[actual]).trim() !== '') {
      return row[actual];
    }
  }
  return fallback;
}

function parseAkinsoftBool(value) {
  const text = String(value ?? '').trim().toLocaleLowerCase('tr-TR');
  if (!text) return null;
  if (['1', 'true', 'evet', 'e', 'kapali', 'kapalı', 'odendi', 'ödendi'].includes(text)) {
    return true;
  }
  if (['0', 'false', 'hayir', 'hayır', 'h', 'acik', 'açık', 'odenmedi', 'ödenmedi'].includes(text)) {
    return false;
  }
  return null;
}

function resolveAkinsoftInvoicePayment(row, currency, grandTotal) {
  const remainingRaw = pick(
    row,
    currency === 'TRY'
      ? [
          'KPB_BAKIYE',
          'KPB_KALAN',
          'KPB_ACIK_TUTAR',
          'BAKIYE',
          'KALAN',
          'ACIK_TUTAR',
          'DVZ_BAKIYE',
        ]
      : [
          'DVZ_BAKIYE',
          'DVZ_KALAN',
          'DVZ_ACIK_TUTAR',
          'DOVIZ_BAKIYE',
          'KPB_BAKIYE',
          'BAKIYE',
        ],
  );
  const remainingAmount = numberOrZero(remainingRaw);
  const paidRaw = pick(
    row,
    currency === 'TRY'
      ? [
          'KPB_TAHSILAT_TOPLAMI',
          'TAHSILAT_TOPLAMI',
          'TAHSIL_EDILEN',
          'ODEME_TOPLAMI',
          'DVZ_TAHSILAT_TOPLAMI',
        ]
      : [
          'DVZ_TAHSILAT_TOPLAMI',
          'DOVIZ_TAHSILAT_TOPLAMI',
          'KPB_TAHSILAT_TOPLAMI',
          'TAHSILAT_TOPLAMI',
        ],
  );
  const paidAmount = numberOrZero(paidRaw);
  const closedFlag = parseAkinsoftBool(
    pick(row, [
      'KAPALI',
      'KAPALI_FATURA',
      'KAPANDI',
      'ODENDI',
      'ODEME_DURUMU',
      'DURUMU',
      'STATU',
      'STATUS',
    ]),
  );
  if (closedFlag === true) {
    return { paidAmount: grandTotal, status: 'paid', reliable: true, source: 'invoice' };
  }
  if (remainingRaw != null) {
    if (remainingAmount <= PAYMENT_CLOSE_TOLERANCE && grandTotal > 0) {
      return { paidAmount: grandTotal, status: 'paid', reliable: true, source: 'invoice' };
    }
    if (remainingAmount > 0 && grandTotal > 0) {
      const paid = Math.max(0, grandTotal - remainingAmount);
      return { paidAmount: paid, status: paid > 0 ? 'partial' : 'open', reliable: true, source: 'invoice' };
    }
  }
  if (paidRaw != null && paidAmount > 0 && paidAmount < grandTotal) {
    return { paidAmount, status: 'partial', reliable: true, source: 'invoice' };
  }
  if (paidRaw != null && paidAmount >= grandTotal - PAYMENT_CLOSE_TOLERANCE && grandTotal > 0) {
    return { paidAmount: grandTotal, status: 'paid', reliable: true, source: 'invoice' };
  }
  return { paidAmount: 0, status: 'open', reliable: false, source: 'invoice' };
}

function resolveAkinsoftCariPayment(movements, currency, grandTotal) {
  if (!Array.isArray(movements) || movements.length === 0 || grandTotal <= 0) {
    return null;
  }
  const debitKey = currency === 'TRY' ? 'KPB_BTUT' : 'DVZ_BTUT';
  const creditKey = currency === 'TRY' ? 'KPB_ATUT' : 'DVZ_ATUT';
  let debit = movements.reduce((sum, row) => sum + numberOrZero(row[debitKey]), 0);
  let credit = movements.reduce((sum, row) => sum + numberOrZero(row[creditKey]), 0);
  if (currency !== 'TRY' && debit <= 0 && credit <= 0) {
    debit = movements.reduce((sum, row) => sum + numberOrZero(row.KPB_BTUT), 0);
    credit = movements.reduce((sum, row) => sum + numberOrZero(row.KPB_ATUT), 0);
  }
  if (debit <= 0 && credit <= 0) return null;
  const paidAmount = Math.min(Math.max(0, credit), grandTotal);
  const remaining = Math.max(0, debit - credit);
  if (remaining <= PAYMENT_CLOSE_TOLERANCE && credit > 0) {
    return { paidAmount: grandTotal, status: 'paid', reliable: true, source: 'movement' };
  }
  if (paidAmount > 0) {
    return { paidAmount, status: 'partial', reliable: true, source: 'movement' };
  }
  return { paidAmount: 0, status: 'open', reliable: true, source: 'movement' };
}

function resolveAkinsoftDiscount(row, currency, lineNet) {
  const raw = numberOrZero(
    pick(
      row,
      currency === 'TRY'
        ? [
            'KPB_ISKONTO_TUTAR',
            'KPB_ISK_TUTAR',
            'ISKONTO_TUTAR',
            'DVZ_ISKONTO_TUTAR',
          ]
        : [
            'DVZ_ISKONTO_TUTAR',
            'DOVIZ_ISKONTO',
            'KPB_ISKONTO_TUTAR',
          ],
    ),
  );
  if (raw <= 0) return 0;
  if (lineNet > 0 && raw >= lineNet - 0.01) return 0;
  return raw;
}

function resolveAkinsoftItemAmounts(row, currency) {
  const normalizedCurrency = normalizeCurrency(currency);
  const isTry = normalizedCurrency === 'TRY';
  const quantity = numberOrZero(row.MIKTARI) || 1;
  const unitPrice = numberOrZero(
    pick(
      row,
      isTry
        ? [
            'KPB_KDV_HARICFY',
            'KPB_FIYATI',
            'KPB_BIRIM_FIYAT',
            'KPB_BF',
            'FIYATI',
            'BIRIM_FIYAT',
          ]
        : [
            'DVZ_KDV_HARICFY',
            'DVZ_FIYATI',
            'DVZ_BIRIM_FIYAT',
            'DVZ_BF',
            'DOVIZ_FIYATI',
          ],
    ),
  );
  const netTotal =
    numberOrZero(
      pick(
        row,
        isTry
          ? [
              'KPB_ARA_TUTAR',
              'KPB_TOPLAM_TUTAR',
              'KPB_TUTAR',
              'KPB_KDV_HARIC_TUTAR',
              'KPB_KDV_HARIC_TPL',
              'ARA_TUTAR',
              'TUTAR',
              'TOPLAM_TUTAR',
            ]
          : [
              'DVZ_ARA_TUTAR',
              'DVZ_TOPLAM_TUTAR',
              'DVZ_TUTAR',
              'DOVIZ_TUTARI',
              'DOVIZ_TOPLAM',
            ],
      ),
    ) || quantity * unitPrice;
  const taxRate = numberOrZero(row.KDV_ORANI);
  const explicitTaxRaw = pick(
    row,
    isTry
      ? ['KPB_KDV_TUTARI', 'KPB_KDV', 'KDV_TUTARI', 'KDV']
      : ['DVZ_KDV_TUTARI', 'DVZ_KDV', 'DOVIZ_KDV_TUTARI'],
  );
  const explicitTaxAmount =
    explicitTaxRaw == null ? null : numberOrZero(explicitTaxRaw);
  const taxIncludedTotal = numberOrZero(
    pick(
      row,
      isTry
        ? ['KPB_KDVLI_TUTAR', 'KPB_KDV_DAHIL_TUTAR']
        : ['DVZ_KDVLI_TUTAR', 'DVZ_KDV_DAHIL_TUTAR'],
    ),
  );
  const taxAmount =
    explicitTaxAmount != null
      ? explicitTaxAmount
      : taxRate > 0 && taxIncludedTotal > netTotal
        ? taxIncludedTotal - netTotal
        : 0;
  return {
    unitPrice,
    discountAmount: resolveAkinsoftDiscount(row, normalizedCurrency, netTotal),
    netTotal,
    taxRate,
    taxAmount,
  };
}

function selectAkinsoftPayment(row, movements, currency, grandTotal) {
  const invoicePayment = resolveAkinsoftInvoicePayment(row, currency, grandTotal);
  const movementPayment = resolveAkinsoftCariPayment(
    movements,
    currency,
    grandTotal,
  );
  if (invoicePayment?.status === 'paid') return invoicePayment;
  if (movementPayment?.status === 'paid') return movementPayment;
  return movementPayment || invoicePayment || { paidAmount: 0, status: 'open', reliable: false, source: null };
}

async function ensureAkinsoftSyncMap(query) {
  await query(`
    alter table public.products
      add column if not exists akinsoft_group text,
      add column if not exists akinsoft_sub_group text,
      add column if not exists akinsoft_source_id text
  `);
  await query(`
    alter table public.invoices
      add column if not exists erp_invoice_number text,
      add column if not exists erp_invoice_number_synced_at timestamptz
  `);
  await query(`
    create table if not exists public.akinsoft_sync_map (
      id uuid primary key default gen_random_uuid(),
      source_system text not null default 'akinsoft',
      source_type text not null,
      source_id text not null,
      source_code text,
      source_name text,
      local_table text not null,
      local_id uuid not null,
      matched_manually boolean not null default false,
      created_at timestamptz not null default now(),
      updated_at timestamptz not null default now(),
      unique (source_system, source_type, source_id)
    )
  `);
  await query(`
    create index if not exists idx_akinsoft_sync_map_code
    on public.akinsoft_sync_map (source_system, source_type, source_code)
  `);
}

async function findAkinsoftMappedLocalId(query, sourceType, sourceId) {
  const id = textOrNull(sourceId);
  if (!id) return { rows: [] };
  return query(
    `
      select m.local_id as id, m.matched_manually, c.vkn
      from public.akinsoft_sync_map m
      left join public.customers c on c.id = m.local_id
      where m.source_system = 'akinsoft'
        and m.source_type = $1
        and m.source_id = $2
      limit 1
    `,
    [sourceType, id],
  );
}

async function findAkinsoftMappedLocalIdByCode(query, sourceType, sourceCode) {
  const code = textOrNull(sourceCode);
  if (!code) return { rows: [] };
  return query(
    `
      select m.local_id as id, m.matched_manually, c.vkn
      from public.akinsoft_sync_map m
      left join public.customers c on c.id = m.local_id
      where m.source_system = 'akinsoft'
        and m.source_type = $1
        and m.source_code = $2
        and (m.matched_manually = true or nullif(trim(coalesce(c.vkn, '')), '') is not null)
      order by m.updated_at desc
      limit 1
    `,
    [sourceType, code],
  );
}

function isTrustedCustomerMap(row, { allowAutomaticVkn = true } = {}) {
  if (!row) return false;
  if (row.matched_manually === true) return true;
  return allowAutomaticVkn && Boolean(textOrNull(row.vkn));
}

async function upsertAkinsoftSyncMap(
  query,
  {
    sourceType,
    sourceId,
    sourceCode,
    sourceName,
    localTable,
    localId,
    matchedManually = false,
  },
) {
  const id = textOrNull(sourceId);
  if (!id || !localId) return;
  await query(
    `
      insert into public.akinsoft_sync_map (
        source_system, source_type, source_id, source_code, source_name,
        local_table, local_id, matched_manually
      )
      values ('akinsoft', $1, $2, $3, $4, $5, $6, $7)
      on conflict (source_system, source_type, source_id) do update set
        source_code = excluded.source_code,
        source_name = excluded.source_name,
        local_table = excluded.local_table,
        local_id = excluded.local_id,
        matched_manually = public.akinsoft_sync_map.matched_manually or excluded.matched_manually,
        updated_at = now()
    `,
    [
      sourceType,
      id,
      textOrNull(sourceCode),
      textOrNull(sourceName),
      localTable,
      localId,
      Boolean(matchedManually),
    ],
  );
}

async function akinsoftTableExists(pool, tableName) {
  const result = await pool
    .request()
    .input('table', tableName)
    .query(`
      select top 1 1 as ok
      from INFORMATION_SCHEMA.TABLES
      where TABLE_SCHEMA = 'dbo' and TABLE_NAME = @table
    `);
  return result.recordset.length > 0;
}

async function akinsoftTableColumnSet(pool, tableName) {
  const result = await pool
    .request()
    .input('table', tableName)
    .query(`
      select COLUMN_NAME as name
      from INFORMATION_SCHEMA.COLUMNS
      where TABLE_SCHEMA = 'dbo' and TABLE_NAME = @table
    `);
  return new Set(result.recordset.map((row) => String(row.name).toUpperCase()));
}

function normalizeProductSnapshot(product) {
  return {
    code: textOrNull(product.code) || '',
    name: textOrNull(product.name) || '',
    description: textOrNull(product.description) || '',
    category: textOrNull(product.category) || '',
    unit: textOrNull(product.unit) || 'Adet',
    taxRate: Number(numberOrZero(product.taxRate ?? product.tax_rate) || 20),
    group:
      textOrNull(product.group ?? product.akinsoft_group) ||
      textOrNull(product.category) ||
      '',
    subGroup: textOrNull(product.subGroup ?? product.akinsoft_sub_group) || '',
  };
}

function productSnapshotEqual(left, right) {
  const a = normalizeProductSnapshot(left || {});
  const b = normalizeProductSnapshot(right || {});
  return (
    a.code === b.code &&
    a.name === b.name &&
    a.description === b.description &&
    a.category === b.category &&
    a.unit === b.unit &&
    a.taxRate === b.taxRate &&
    a.group === b.group &&
    a.subGroup === b.subGroup
  );
}

async function loadCrmProductSnapshotsBySource(query) {
  await ensureAkinsoftSyncMap(query);
  const mapped = await query(`
    select
      m.source_id,
      m.local_id,
      p.code,
      p.name,
      p.description,
      p.category,
      p.unit,
      p.tax_rate,
      p.akinsoft_group,
      p.akinsoft_sub_group,
      p.akinsoft_source_id
    from public.akinsoft_sync_map m
    join public.products p on p.id = m.local_id
    where m.source_system = 'akinsoft'
      and m.source_type = 'product'
  `);
  const bySourceId = new Map();
  const byCode = new Map();
  for (const row of mapped.rows) {
    const snapshot = {
      id: row.local_id,
      code: row.code,
      name: row.name,
      description: row.description,
      category: row.category,
      unit: row.unit,
      taxRate: row.tax_rate,
      group: row.akinsoft_group,
      subGroup: row.akinsoft_sub_group,
      akinsoft_source_id: row.akinsoft_source_id,
      mapped: true,
    };
    if (row.source_id != null) bySourceId.set(String(row.source_id), snapshot);
    if (textOrNull(row.code)) byCode.set(textOrNull(row.code), snapshot);
  }
  return { bySourceId, byCode };
}

function bracketSqlName(name) {
  return `[${escapeSqlName(name)}]`;
}

function buildAkinsoftInvoiceWhere(columns, hasFaturaHr) {
  const hasColumn = (name) => columns.has(String(name).toUpperCase());
  const conditions = [
    `coalesce(FATURA_NO, '') <> ''`,
    `coalesce(FATURA_NO, '') not like N'MSF%'`,
  ];
  if (hasFaturaHr) {
    conditions.push(
      `exists (select 1 from dbo.FATURAHR h where h.BLFTKODU = dbo.FATURA.BLKODU)`,
    );
  }
  for (const column of ['SILINDI', 'SILINDI_MI', 'DELETED']) {
    if (hasColumn(column)) {
      conditions.push(`coalesce(try_convert(int, ${bracketSqlName(column)}), 0) = 0`);
    }
  }
  for (const column of ['IPTAL', 'FATURA_IPTAL', 'IPTAL_MI']) {
    if (hasColumn(column)) {
      conditions.push(`coalesce(try_convert(int, ${bracketSqlName(column)}), 0) = 0`);
    }
  }
  if (hasColumn('FATURA_DURUMU')) {
    conditions.push(`
      (
        FATURA_DURUMU is null
        or (
          upper(cast(FATURA_DURUMU as nvarchar(80))) not like N'%IPTAL%'
          and upper(cast(FATURA_DURUMU as nvarchar(80))) not like N'%İPTAL%'
        )
      )
    `);
  }
  return conditions.join('\n          and ');
}

function isAkinsoftInvoiceStatusIncluded(row) {
  const raw = pick(row, ['FATURA_DURUMU']);
  if (raw == null || String(raw).trim() === '') return true;
  const text = String(raw).trim();
  const numeric = Number.parseInt(text, 10);
  if (Number.isFinite(numeric) && String(numeric) === text) return numeric === 1;
  const upper = text.toLocaleUpperCase('tr-TR');
  return !upper.includes('IPTAL') && !upper.includes('İPTAL');
}

async function ensureAkinsoftCustomerMatchTable(pool) {
  await pool.request().query(`
    if object_id(N'dbo.MICROVISE_CARI_ESLESME', N'U') is null
    begin
      create table dbo.MICROVISE_CARI_ESLESME (
        ID int identity(1,1) not null primary key,
        AKINSOFT_BLKODU nvarchar(64) not null,
        AKINSOFT_CARIKODU nvarchar(64) null,
        AKINSOFT_CARI_ADI nvarchar(255) null,
        CRM_CUSTOMER_ID nvarchar(64) not null,
        CRM_CUSTOMER_NAME nvarchar(255) null,
        KAYIT_TARIHI datetime2 not null default sysdatetime(),
        GUNCELLEME_TARIHI datetime2 not null default sysdatetime()
      )
    end
    if not exists (
      select 1
      from sys.indexes
      where name = N'UX_MICROVISE_CARI_ESLESME_BLKODU'
        and object_id = object_id(N'dbo.MICROVISE_CARI_ESLESME')
    )
    begin
      create unique index UX_MICROVISE_CARI_ESLESME_BLKODU
      on dbo.MICROVISE_CARI_ESLESME (AKINSOFT_BLKODU)
    end
  `);
}

async function readAkinsoftCustomerMatchRows(pool) {
  try {
    const exists = await akinsoftTableExists(pool, 'MICROVISE_CARI_ESLESME');
    if (!exists) return [];
    return (
      await pool.request().query(`
        select AKINSOFT_BLKODU, AKINSOFT_CARIKODU, AKINSOFT_CARI_ADI,
          CRM_CUSTOMER_ID, CRM_CUSTOMER_NAME
        from dbo.MICROVISE_CARI_ESLESME
      `)
    ).recordset;
  } catch (_) {
    return [];
  }
}

async function writeAkinsoftCustomerMatch(body, match) {
  const sql = require('mssql');
  const { config } = buildAkinsoftSqlConfig(body || {});
  const pool = await connectAkinsoftPool(config);
  const localTaxNumber = taxNumberOrNull(match.localCustomerTaxNumber);
  try {
    await ensureAkinsoftCustomerMatchTable(pool);
    await pool
      .request()
      .input('sourceId', sql.NVarChar(64), String(match.sourceId))
      .input('sourceCode', sql.NVarChar(64), textOrNull(match.sourceCode))
      .input('sourceName', sql.NVarChar(255), textOrNull(match.sourceName))
      .input('localId', sql.NVarChar(64), String(match.localCustomerId))
      .input('localName', sql.NVarChar(255), textOrNull(match.localCustomerName))
      .query(`
        merge dbo.MICROVISE_CARI_ESLESME as target
        using (select @sourceId as AKINSOFT_BLKODU) as source
          on target.AKINSOFT_BLKODU = source.AKINSOFT_BLKODU
        when matched then update set
          AKINSOFT_CARIKODU = @sourceCode,
          AKINSOFT_CARI_ADI = @sourceName,
          CRM_CUSTOMER_ID = @localId,
          CRM_CUSTOMER_NAME = @localName,
          GUNCELLEME_TARIHI = sysdatetime()
        when not matched then insert (
          AKINSOFT_BLKODU, AKINSOFT_CARIKODU, AKINSOFT_CARI_ADI,
          CRM_CUSTOMER_ID, CRM_CUSTOMER_NAME
        ) values (
          @sourceId, @sourceCode, @sourceName, @localId, @localName
        );
      `);
    if (localTaxNumber) {
      await pool
        .request()
        .input('sourceId', sql.NVarChar(64), String(match.sourceId))
        .input('sourceCode', sql.NVarChar(64), textOrNull(match.sourceCode))
        .input('localTaxNumber', sql.NVarChar(32), localTaxNumber)
        .query(`
          update dbo.CARI
          set VERGI_NO = @localTaxNumber
          where
            cast(BLKODU as nvarchar(64)) = @sourceId
            or (@sourceCode is not null and CARIKODU = @sourceCode)
        `);
    }
  } finally {
    await pool.close();
  }
}

async function resolveAkinsoftCustomerMatches(invoices, externalRows = []) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  const externalBySource = new Map();
  for (const row of externalRows) {
    const sourceId = textOrNull(row.AKINSOFT_BLKODU);
    const localId = textOrNull(row.CRM_CUSTOMER_ID);
    if (!sourceId || !localId) continue;
    externalBySource.set(sourceId, {
      matched: true,
      method: 'akinsoft_map',
      localId,
      localName: textOrNull(row.CRM_CUSTOMER_NAME),
    });
  }

  const result = new Map();
  const sourceIds = [
    ...new Set(
      invoices
        .map((invoice) => textOrNull(invoice.customerSourceId))
        .filter(Boolean),
    ),
  ];
  const sourceCodes = [
    ...new Set(
      invoices
        .map((invoice) => textOrNull(invoice.customerCode))
        .filter(Boolean),
    ),
  ];
  const taxNumbers = [
    ...new Set(
      invoices
        .map((invoice) => taxNumberOrNull(invoice.taxNumber))
        .filter(Boolean),
    ),
  ];
  const sourceMatches = new Map();
  const codeMatches = new Map();
  const taxMatches = new Map();

  if (sourceIds.length) {
    const mapped = await query(
      `
        select m.source_id, m.local_id as id, m.matched_manually, c.name, c.vkn
        from public.akinsoft_sync_map m
        left join public.customers c on c.id = m.local_id
        where m.source_system = 'akinsoft'
          and m.source_type = 'customer'
          and m.source_id = any($1::text[])
      `,
      [sourceIds],
    );
    for (const row of mapped.rows) {
      if (!isTrustedCustomerMap(row, { allowAutomaticVkn: false })) continue;
      sourceMatches.set(row.source_id, {
        matched: true,
        method: 'source',
        localId: row.id,
        localName: row.name,
      });
    }
  }

  if (taxNumbers.length) {
    const found = await query(
      `
        select id, name, vkn
        from public.customers
        where vkn = any($1::text[])
      `,
      [taxNumbers],
    );
    for (const row of found.rows) {
      taxMatches.set(row.vkn, {
        matched: true,
        method: 'tax',
        localId: row.id,
        localName: row.name,
      });
    }
  }

  if (sourceCodes.length) {
    const mapped = await query(
      `
        select distinct on (m.source_code)
          m.source_code, m.local_id as id, m.matched_manually, c.name, c.vkn
        from public.akinsoft_sync_map m
        left join public.customers c on c.id = m.local_id
        where m.source_system = 'akinsoft'
          and m.source_type = 'customer'
          and m.source_code = any($1::text[])
        order by m.source_code, m.updated_at desc
      `,
      [sourceCodes],
    );
    for (const row of mapped.rows) {
      if (!isTrustedCustomerMap(row, { allowAutomaticVkn: false })) continue;
      codeMatches.set(row.source_code, {
        matched: true,
        method: 'code',
        localId: row.id,
        localName: row.name,
      });
    }
  }

  for (const invoice of invoices) {
    const invoiceId = textOrNull(invoice.sourceId);
    const sourceId = textOrNull(invoice.customerSourceId);
    const sourceCode = textOrNull(invoice.customerCode);
    const taxNumber = taxNumberOrNull(invoice.taxNumber);
    let match = null;

    if (taxNumber) match = taxMatches.get(taxNumber) || null;
    if (!match && sourceId && externalBySource.has(sourceId)) {
      match = externalBySource.get(sourceId);
    }
    if (!match && sourceId) match = sourceMatches.get(sourceId) || null;
    if (!match && sourceCode) match = codeMatches.get(sourceCode) || null;

    if (invoiceId) {
      result.set(invoiceId, match || { matched: false });
    }
  }
  return result;
}

async function resolveAkinsoftCustomerRows(customers, externalRows = []) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  const result = new Map();
  const externalBySource = new Map();
  for (const row of externalRows) {
    const sourceId = textOrNull(row.AKINSOFT_BLKODU);
    const localId = textOrNull(row.CRM_CUSTOMER_ID);
    if (!sourceId || !localId) continue;
    externalBySource.set(sourceId, {
      matched: true,
      method: 'akinsoft_map',
      localId,
      localName: textOrNull(row.CRM_CUSTOMER_NAME),
    });
  }
  const sourceIds = [
    ...new Set(customers.map((customer) => textOrNull(customer.sourceId)).filter(Boolean)),
  ];
  if (sourceIds.length) {
    const mapped = await query(
      `
        select m.source_id, m.local_id as id, m.matched_manually, c.name, c.vkn
        from public.akinsoft_sync_map m
        left join public.customers c on c.id = m.local_id
        where m.source_system = 'akinsoft'
          and m.source_type = 'customer'
          and m.source_id = any($1::text[])
      `,
      [sourceIds],
    );
    for (const row of mapped.rows) {
      if (!isTrustedCustomerMap(row, { allowAutomaticVkn: false })) continue;
      result.set(row.source_id, {
        matched: true,
        method: 'source',
        localId: row.id,
        localName: row.name,
      });
    }
  }
  for (const customer of customers) {
    const sourceId = textOrNull(customer.sourceId);
    if (!sourceId) continue;
    if (externalBySource.has(sourceId)) {
      result.set(sourceId, externalBySource.get(sourceId));
    } else if (!result.has(sourceId)) {
      result.set(sourceId, { matched: false });
    }
  }
  return result;
}

async function handleAkinsoftPull(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }

  const body = await readJson(req);
  const sql = require('mssql');
  const { database, config } = buildAkinsoftSqlConfig(body);
  const limit = Math.max(1, Math.min(Number(body.limit || 2000), 5000));
  const pool = await connectAkinsoftPool(config);

  try {
    const warnings = [];
    const [hasFatura, hasFaturaHr, hasFaturaKdv, hasCari, hasStok, hasCariHr] =
      await Promise.all([
        akinsoftTableExists(pool, 'FATURA'),
        akinsoftTableExists(pool, 'FATURAHR'),
        akinsoftTableExists(pool, 'FATURA_KDV'),
        akinsoftTableExists(pool, 'CARI'),
        akinsoftTableExists(pool, 'STOK'),
        akinsoftTableExists(pool, 'CARIHR'),
      ]);

    let customers = [];
    let products = [];
    let customerCount = 0;
    let productCount = 0;
    const mapCustomerRow = (row) => ({
      sourceId: String(row.BLKODU),
      code: textOrNull(row.CARIKODU),
      name:
        textOrNull(row.TICARI_UNVANI) ||
        [row.ADI, row.SOYADI].map(textOrNull).filter(Boolean).join(' ') ||
        `Cari ${row.BLKODU}`,
      taxNumber: taxNumberOrNull(row.VERGI_NO),
      taxOffice: textOrNull(row.VERGI_DAIRESI),
      phone: textOrNull(row.CEP_TEL) || textOrNull(row.TEL1),
      email: textOrNull(row.E_MAIL),
      website: textOrNull(row.WEB),
      createdAt: dateOrIso(row.KAYIT_TARIHI),
    });
    if (hasCari) {
      const countResult = await pool
        .request()
        .query(`select count_big(1) as total from dbo.CARI`);
      customerCount = Number(countResult.recordset[0]?.total || 0);
    }
    const mapProductRow = (row) => ({
          sourceId: String(row.BLKODU),
          code: textOrNull(row.STOKKODU),
          name: textOrNull(row.STOK_ADI) || `Stok ${row.BLKODU}`,
          unit: textOrNull(row.BIRIMI) || 'Adet',
          taxRate: numberOrZero(row.KDV_ORANI) || 20,
          group:
            textOrNull(row.ARA_GRUBU) ||
            textOrNull(row.OZEL_KODU1) ||
            textOrNull(row.OZEL_KODU2),
          subGroup:
            textOrNull(row.ALT_GRUBU) ||
            textOrNull(row.OZEL_KODU2) ||
            textOrNull(row.OZEL_KODU3),
          category:
            textOrNull(row.ARA_GRUBU) ||
            textOrNull(row.OZEL_KODU1) ||
            textOrNull(row.OZEL_KODU2),
          description:
            [row.ACIKLAMA1, row.ACIKLAMA2].map(textOrNull).filter(Boolean).join(' ') ||
            null,
          currency: 'TRY',
          purchasePrice: 0,
          salePrice: 0,
          createdAt: dateOrIso(row.KAYIT_TARIHI),
        });
    if (hasStok) {
      const countResult = await pool
        .request()
        .query(`select count_big(1) as total from dbo.STOK`);
      productCount = Number(countResult.recordset[0]?.total || 0);
      // Fatura kalemlerinden bağımsız: yeni açılan stoklar da gelsin.
      products = (
        await pool.request().input('limit', sql.Int, limit).query(`
          select top (@limit)
            BLKODU, STOKKODU, STOK_ADI, BIRIMI, KDV_ORANI, OZEL_KODU1,
            OZEL_KODU2, OZEL_KODU3, ARA_GRUBU, ALT_GRUBU, KAYIT_TARIHI,
            ACIKLAMA1, ACIKLAMA2
          from dbo.STOK
          where coalesce(STOK_ADI, '') <> ''
             or coalesce(STOKKODU, '') <> ''
          order by BLKODU desc
        `)
      ).recordset.map(mapProductRow);
    }

    let invoices = [];
    let rawInvoiceCount = 0;
    if (hasFatura) {
      const faturaColumns = await akinsoftTableColumnSet(pool, 'FATURA');
      const invoiceWhere = buildAkinsoftInvoiceWhere(faturaColumns, hasFaturaHr);
      const rawInvoiceCountResult = await pool.request().query(`
        select count_big(1) as total
        from dbo.FATURA
        where ${invoiceWhere}
      `);
      rawInvoiceCount = Number(rawInvoiceCountResult.recordset[0]?.total || 0);
      const rawHeaders = (
        await pool.request().input('limit', sql.Int, limit).query(`
          select top (@limit) *
          from dbo.FATURA
          where ${invoiceWhere}
          order by TARIHI desc, BLKODU desc
        `)
      ).recordset;
      const filteredHeaders = rawHeaders.filter((row) => {
        const invoiceNumber = textOrNull(row.FATURA_NO) || '';
        return (
          !invoiceNumber.toUpperCase().startsWith('MSF') &&
          isAkinsoftInvoiceStatusIncluded(row)
        );
      });
      const seenInvoiceNumbers = new Set();
      const headers = [];
      for (const row of filteredHeaders) {
        const invoiceNumber = (textOrNull(row.FATURA_NO) || `AKN-${row.BLKODU}`)
          .toLocaleUpperCase('tr-TR')
          .trim();
        if (seenInvoiceNumbers.has(invoiceNumber)) continue;
        seenInvoiceNumbers.add(invoiceNumber);
        headers.push(row);
      }

      const ids = headers.map((row) => Number(row.BLKODU)).filter(Number.isFinite);
      const customerIds = [
        ...new Set(
          headers.map((row) => Number(row.BLCRKODU)).filter(Number.isFinite),
        ),
      ];
      if (customerIds.length && hasCari) {
        const request = pool.request();
        customerIds.forEach((id, index) => request.input(`cid${index}`, sql.Int, id));
        const paramList = customerIds.map((_, index) => `@cid${index}`).join(',');
        const usedCustomers = (
          await request.query(`
            select
              BLKODU, CARIKODU, TICARI_UNVANI, ADI, SOYADI, VERGI_DAIRESI,
              VERGI_NO, TEL1, TEL2, CEP_TEL, FAKS, E_MAIL, WEB, KAYIT_TARIHI
            from dbo.CARI
            where BLKODU in (${paramList})
          `)
        ).recordset.map(mapCustomerRow);
        const bySource = new Map(customers.map((row) => [String(row.sourceId), row]));
        for (const customer of usedCustomers) {
          bySource.set(String(customer.sourceId), customer);
        }
        customers = [...bySource.values()];
      }
      const itemRows = [];
      const kdvRows = [];
      const cariHrRows = [];
      let cariHrPaymentReliable = Boolean(hasCariHr);
      if (ids.length && hasFaturaHr) {
        const request = pool.request();
        ids.forEach((id, index) => request.input(`id${index}`, sql.Int, id));
        const paramList = ids.map((_, index) => `@id${index}`).join(',');
        itemRows.push(
          ...(
            await request.query(`
              select *
              from dbo.FATURAHR
              where BLFTKODU in (${paramList})
              order by BLFTKODU, BLKODU
            `)
          ).recordset,
        );
      }
      const invoiceNumbers = headers
        .map((row) => textOrNull(row.FATURA_NO))
        .filter(Boolean);
      if (invoiceNumbers.length && hasCariHr) {
        try {
          const request = pool.request();
          request.timeout = 25000;
          invoiceNumbers.forEach((no, index) =>
            request.input(`no${index}`, sql.NVarChar, no),
          );
          const paramList = invoiceNumbers.map((_, index) => `@no${index}`).join(',');
          cariHrRows.push(
            ...(
              await request.query(`
                select EVRAK_NO, KPB_BTUT, KPB_ATUT, DVZ_BTUT, DVZ_ATUT
                from dbo.CARIHR
                where EVRAK_NO in (${paramList})
                  and coalesce(SILINDI, 0) = 0
              `)
            ).recordset,
          );
        } catch (error) {
          cariHrPaymentReliable = false;
          warnings.push(
            `Cari hareketleri okunamadı; ödeme/durum bilgisi eksik olabilir: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
        }
      }
      if (ids.length && hasFaturaKdv) {
        const request = pool.request();
        ids.forEach((id, index) => request.input(`id${index}`, sql.Int, id));
        const paramList = ids.map((_, index) => `@id${index}`).join(',');
        kdvRows.push(
          ...(
            await request.query(`
              select BLFTKODU, KDV_ORANI, KDV_MATRAHI, KDV_TUTARI
              from dbo.FATURA_KDV
              where BLFTKODU in (${paramList})
            `)
          ).recordset,
        );
      }
      const productIds = [
        ...new Set(
          itemRows.map((row) => Number(row.BLSTKODU)).filter(Number.isFinite),
        ),
      ];
      if (productIds.length && hasStok) {
        const known = new Set(products.map((row) => String(row.sourceId)));
        const missingIds = productIds.filter((id) => !known.has(String(id)));
        if (missingIds.length) {
          const request = pool.request();
          missingIds.forEach((id, index) =>
            request.input(`pid${index}`, sql.Int, id),
          );
          const paramList = missingIds
            .map((_, index) => `@pid${index}`)
            .join(',');
          const extra = (
            await request.query(`
              select
                BLKODU, STOKKODU, STOK_ADI, BIRIMI, KDV_ORANI, OZEL_KODU1,
                OZEL_KODU2, OZEL_KODU3, ARA_GRUBU, ALT_GRUBU, KAYIT_TARIHI,
                ACIKLAMA1, ACIKLAMA2
              from dbo.STOK
              where BLKODU in (${paramList})
            `)
          ).recordset.map(mapProductRow);
          products = [...products, ...extra];
        }
      }

      const itemsByInvoice = new Map();
      for (const row of itemRows) {
        const key = String(row.BLFTKODU);
        const list = itemsByInvoice.get(key) || [];
        const account = akinsoftAccountText(row);
        const currency = resolveAkinsoftItemCurrency(row);
        const amountsByCurrency = {
          TRY: resolveAkinsoftItemAmounts(row, 'TRY'),
          FOREIGN: resolveAkinsoftItemAmounts(row, currency === 'TRY' ? 'USD' : currency),
        };
        const selectedAmounts =
          currency === 'TRY' ? amountsByCurrency.TRY : amountsByCurrency.FOREIGN;
        list.push({
          sourceId: String(row.BLKODU),
          productSourceId: row.BLSTKODU == null ? null : String(row.BLSTKODU),
          code: textOrNull(row.STOKKODU),
          description: textOrNull(row.STOK_ADI) || 'Fatura kalemi',
          quantity: numberOrZero(row.MIKTARI) || 1,
          unit: textOrNull(row.BIRIMI) || 'Adet',
          unitPrice: selectedAmounts.unitPrice,
          discountAmount: selectedAmounts.discountAmount,
          netTotal: selectedAmounts.netTotal,
          taxRate: selectedAmounts.taxRate,
          taxAmount: selectedAmounts.taxAmount,
          currency,
          account,
          amountsByCurrency,
        });
        itemsByInvoice.set(key, list);
      }

      const kdvByInvoice = new Map();
      for (const row of kdvRows) {
        const key = String(row.BLFTKODU);
        const list = kdvByInvoice.get(key) || [];
        list.push({
          taxRate: numberOrZero(row.KDV_ORANI),
          taxableAmount: numberOrZero(row.KDV_MATRAHI),
          taxAmount: numberOrZero(row.KDV_TUTARI),
        });
        kdvByInvoice.set(key, list);
      }

      const cariHrByInvoiceNo = new Map();
      for (const row of cariHrRows) {
        const key = textOrNull(row.EVRAK_NO);
        if (!key) continue;
        const list = cariHrByInvoiceNo.get(key) || [];
        list.push(row);
        cariHrByInvoiceNo.set(key, list);
      }

      invoices = headers.map((row) => {
        const key = String(row.BLKODU);
        const invoiceNumber = textOrNull(row.FATURA_NO) || `AKN-${key}`;
        const taxes = kdvByInvoice.get(key) || [];
        const primaryTaxRate =
          numberOrZero(taxes[0]?.taxRate) || numberOrZero(row.KDV_ORANI) || 0;
        const rawItems = itemsByInvoice.get(key) || [];
        const itemAccounts = [
          ...new Set(rawItems.map((item) => textOrNull(item.account)).filter(Boolean)),
        ];
        const headerCurrencyValue = pick(row, [
              'DOVIZ_BIRIMI',
              'DOVIZ_KULLAN',
              'DOVIZ_ADI',
              'DVZ_BIRIMI',
              'PARA_BIRIMI',
              'DOVIZ',
            ]);
        const itemCurrencies = rawItems
          .map((item) => textOrNull(item.currency))
          .filter(Boolean);
        const foreignItemCurrency = itemCurrencies.find((item) => item !== 'TRY');
        const currency = foreignItemCurrency || (
          itemCurrencies.length ? 'TRY' : normalizeCurrency(headerCurrencyValue)
        );
        const items = rawItems.map((item) => {
          const amounts =
            (currency === 'TRY'
              ? item.amountsByCurrency?.TRY
              : item.amountsByCurrency?.FOREIGN) ||
            item;
          const taxAmount = numberOrZero(amounts.taxAmount);
          const taxRate =
            taxAmount <= 0
              ? 0
              : numberOrZero(amounts.taxRate) || primaryTaxRate;
          const { amountsByCurrency, ...rest } = item;
          return {
            ...rest,
            unitPrice: numberOrZero(amounts.unitPrice),
            discountAmount: numberOrZero(amounts.discountAmount),
            netTotal: numberOrZero(amounts.netTotal),
            taxRate,
            taxAmount,
            currency,
          };
        });
        const subtotal = items.reduce((sum, item) => sum + item.netTotal, 0);
        const discountTotal = items.reduce((sum, item) => sum + item.discountAmount, 0);
        const headerSubtotal = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_ARA_TOPLAM',
                  'TOPLAM_ARA',
                  'TOPLAM_ARA_KPB',
                  'KPB_ARA_TUTAR',
                  'KPB_TOPLAM',
                  'KPB_TOPLAM_TUTAR',
                  'KPB_MATRAH',
                  'ARA_TOPLAM',
                  'ARA_TUTAR',
                  'TOPLAM',
                  'TOPLAM_TUTAR',
                ]
              : [
                  'DVZ_ARA_TOPLAM',
                  'TOPLAM_ARA_DVZ',
                  'DVZ_ARA_TUTAR',
                  'DVZ_TOPLAM',
                  'DVZ_TOPLAM_TUTAR',
                  'DOVIZ_ARA_TOPLAM',
                  'DOVIZ_TOPLAM',
                  'KPB_ARA_TOPLAM',
                  'KPB_TOPLAM',
                ],
          ),
        );
        const headerDiscountTotal = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_IND_TOPLAM',
                  'KPB_IND_TUTAR',
                  'KPB_ISKONTO_TOPLAM',
                  'KPB_ISKONTO_TUTAR',
                  'IND_TOPLAM',
                  'ISKONTO_TOPLAM',
                ]
              : [
                  'DVZ_IND_TOPLAM',
                  'DVZ_IND_TUTAR',
                  'DVZ_ISKONTO_TOPLAM',
                  'DOVIZ_ISKONTO_TOPLAM',
                  'KPB_IND_TOPLAM',
                ],
          ),
        );
        const headerTaxTotal = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_KDV_TOPLAM',
                  'TOPLAM_KDV',
                  'TOPLAM_KDV_KPB',
                  'KPB_KDV_TUTARI',
                  'KDV_TOPLAM',
                  'KDV_TUTARI',
                ]
              : [
                  'TOPLAM_KDV_DVZ',
                  'DVZ_KDV_TOPLAM',
                  'DVZ_KDV_TUTARI',
                  'DOVIZ_KDV_TOPLAM',
                  'KPB_KDV_TOPLAM',
                ],
          ),
        );
        const headerGrandTotal = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_GENEL_TOPLAM',
                  'TOPLAM_GENEL',
                  'TOPLAM_GENEL_KPB',
                  'KPB_GENELTOPLAM',
                  'KPB_KDV_DAHIL_TOPLAM',
                  'KPB_KDV_DAHIL_TUTAR',
                  'KPB_KDVLI_TOPLAM',
                  'KPB_KDVLI_TUTAR',
                  'KPB_TOPLAM_TUTAR',
                  'GENEL_TOPLAM',
                  'GENELTOPLAM',
                  'KDV_DAHIL_TOPLAM',
                  'KDV_DAHIL_TUTAR',
                  'KDVLI_TOPLAM',
                  'KDVLI_TUTAR',
                  'TOPLAM_TUTAR',
                  'FATURA_TOPLAMI',
                ]
              : [
                  'DVZ_GENEL_TOPLAM',
                  'TOPLAM_GENEL_DVZ',
                  'DVZ_GENELTOPLAM',
                  'DVZ_KDV_DAHIL_TOPLAM',
                  'DVZ_KDV_DAHIL_TUTAR',
                  'DVZ_KDVLI_TOPLAM',
                  'DVZ_KDVLI_TUTAR',
                  'DVZ_TOPLAM_TUTAR',
                  'DOVIZ_GENEL_TOPLAM',
                  'DOVIZ_GENELTOPLAM',
                  'DOVIZ_KDV_DAHIL_TOPLAM',
                  'DOVIZ_KDVLI_TOPLAM',
                  'DOVIZ_TOPLAM',
                  'KPB_GENEL_TOPLAM',
                  'KPB_GENELTOPLAM',
                  'KPB_KDV_DAHIL_TOPLAM',
                  'KPB_KDVLI_TOPLAM',
                ],
          ),
        );
        const tableTaxTotal = taxes.reduce((sum, item) => sum + item.taxAmount, 0);
        const itemTaxTotal = items.reduce((sum, item) => sum + item.taxAmount, 0);
        const finalSubtotal = subtotal || headerSubtotal || Math.max(0, headerGrandTotal - headerTaxTotal);
        const finalDiscountTotal = discountTotal || headerDiscountTotal;
        const taxTotal = headerTaxTotal || tableTaxTotal || itemTaxTotal;
        const finalGrandTotal =
          headerGrandTotal || finalSubtotal - finalDiscountTotal + taxTotal;
        const payment = selectAkinsoftPayment(
          row,
          cariHrByInvoiceNo.get(invoiceNumber) || [],
          currency,
          finalGrandTotal,
        );
        return {
          sourceId: key,
          invoiceNumber,
          sourceStatus: row.FATURA_DURUMU,
          invoiceType: 'sales',
          customerSourceId: row.BLCRKODU == null ? null : String(row.BLCRKODU),
          customerCode: textOrNull(row.CARIKODU),
          customerName:
            textOrNull(row.TICARI_UNVANI) ||
            textOrNull(row.ADI_SOYADI) ||
            `Cari ${row.BLCRKODU || ''}`.trim(),
          taxNumber: taxNumberOrNull(row.VERGI_NO),
          taxOffice: textOrNull(row.VERGI_DAIRESI),
          invoiceDate: dateOrIso(row.TARIHI),
          dueDate: dateOrIso(row.VADESI),
          group: textOrNull(row.GRUBU),
          notes: textOrNull(row.ACIKLAMA),
          currency,
          subtotal: finalSubtotal,
          discountTotal: finalDiscountTotal,
          taxTotal,
          grandTotal: finalGrandTotal,
          paidAmount: payment.paidAmount,
          status: payment.status,
          paymentReliable:
            payment.reliable === true &&
            (payment.source !== 'movement' || cariHrPaymentReliable),
          accountMode: itemAccounts.join(', '),
          items,
          taxes,
        };
      });
    }

    let customerMatches = new Map();
    try {
      const externalCustomerMatches = await readAkinsoftCustomerMatchRows(pool);
      const customerRowMatches = await resolveAkinsoftCustomerRows(
        customers,
        externalCustomerMatches,
      );
      customers = customers.map((customer) => ({
        ...customer,
        customerMatch:
          customerRowMatches.get(String(customer.sourceId)) || { matched: false },
      }));
      customerMatches = await resolveAkinsoftCustomerMatches(
        invoices,
        externalCustomerMatches,
      );
      invoices = invoices.map((invoice) => ({
        ...invoice,
        customerMatch:
          customerMatches.get(String(invoice.sourceId)) || { matched: false },
      }));
    } catch (error) {
      invoices = invoices.map((invoice) => ({
        ...invoice,
        customerMatch: { matched: false, error: String(error.message || error) },
      }));
    }

    try {
      const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
      const invoiceNumbers = invoices
        .map((invoice) => textOrNull(invoice.invoiceNumber))
        .filter(Boolean);
      if (invoiceNumbers.length) {
        const existing = await query(
          `
            select
              invoice_number,
              is_active,
              status,
              currency,
              round(coalesce(grand_total, 0)::numeric, 2)::text as grand_total
            from public.invoices
            where invoice_number = any($1::text[])
          `,
          [invoiceNumbers],
        );
        const existingByNo = new Map(
          existing.rows.map((row) => [String(row.invoice_number), row]),
        );
        invoices = invoices
          .map((invoice) => {
            const row = existingByNo.get(String(invoice.invoiceNumber));
            if (!row) return { ...invoice, importAction: 'new' };
            const active = row.is_active !== false;
            if (!active) return { ...invoice, importAction: 'restore' };
            const statusComparable = invoice.paymentReliable !== false;
            const sameStatus =
              !statusComparable ||
              textOrNull(row.status) === textOrNull(invoice.status);
            const sameCurrency =
              normalizeCurrency(row.currency) === normalizeCurrency(invoice.currency);
            const sameTotal =
              Math.abs(numberOrZero(row.grand_total) - numberOrZero(invoice.grandTotal)) <=
              PAYMENT_CLOSE_TOLERANCE;
            if (sameStatus && sameCurrency && sameTotal) return null;
            return { ...invoice, importAction: 'update' };
          })
          .filter(Boolean);
      }
    } catch (error) {
      invoices = invoices.map((invoice) => ({
        ...invoice,
        importAction: 'new',
        importCheckError: String(error.message || error),
      }));
    }

    let productsUnchanged = 0;
    try {
      const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
      const { bySourceId } = await loadCrmProductSnapshotsBySource(query);
      const requiredIds = new Set();
      for (const invoice of invoices) {
        for (const item of Array.isArray(invoice.items) ? invoice.items : []) {
          const sourceId = textOrNull(item.productSourceId);
          if (sourceId) requiredIds.add(sourceId);
        }
      }
      const filtered = [];
      for (const product of products) {
        const sourceId = textOrNull(product.sourceId);
        if (sourceId && requiredIds.has(sourceId)) {
          filtered.push(product);
          continue;
        }
        const previous = sourceId ? bySourceId.get(sourceId) : null;
        if (!previous || !productSnapshotEqual(previous, product)) {
          filtered.push(product);
          continue;
        }
        productsUnchanged += 1;
      }
      products = filtered;
    } catch (error) {
      warnings.push(
        `Stok delta filtresi atlandı: ${error?.message || error}`,
      );
    }

    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({
        ok: true,
        database,
        tables: {
          FATURA: hasFatura,
          FATURAHR: hasFaturaHr,
          FATURA_KDV: hasFaturaKdv,
          CARI: hasCari,
          STOK: hasStok,
          CARIHR: hasCariHr,
        },
        counts: {
          customers: customerCount || customers.length,
          products: productCount || products.length,
          productsSelected: products.length,
          productsUnchanged,
          invoices: invoices.length,
          rawInvoices: rawInvoiceCount || invoices.length,
          filteredInvoices: Math.max(0, (rawInvoiceCount || invoices.length) - invoices.length),
          invoiceItems: invoices.reduce((sum, item) => sum + item.items.length, 0),
          unmatchedCustomers: invoices.filter(
            (item) => item.customerMatch?.matched !== true,
          ).length,
        },
        warnings,
        customers,
        products,
        invoices,
      }),
    );
  } finally {
    await pool.close();
  }
}

// Yalnızca ödeme/durum bilgisini tazeler: yeni fatura, cari, stok ve kalem
// yazmaz. ERP'de kapanan faturaları hızlıca CRM'e yansıtmak için kullanılır.
async function syncAkinsoftInvoiceStatuses(query, invoices, reportProgress) {
  let updated = 0;
  let unchanged = 0;
  let notFound = 0;
  let unreliable = 0;
  const statusCounts = { paid: 0, partial: 0, open: 0 };
  const missing = [];

  reportProgress(0, {
    stage: 'status',
    stageLabel: 'Fatura durumları güncelleniyor',
    total: invoices.length,
  });

  for (let index = 0; index < invoices.length; index += 1) {
    const invoice = invoices[index];
    const invoiceNumber = textOrNull(invoice.invoiceNumber);
    const report = () =>
      reportProgress(index + 1, {
        stage: 'status',
        stageLabel: 'Fatura durumları güncelleniyor',
        total: invoices.length,
        invoiceNumber,
      });

    if (!invoiceNumber) {
      report();
      continue;
    }
    if (invoice.paymentReliable === false) {
      unreliable += 1;
      report();
      continue;
    }

    let invoiceId = null;
    if (invoice.sourceId != null) {
      const mapped = await findAkinsoftMappedLocalId(
        query,
        'invoice',
        invoice.sourceId,
      );
      invoiceId = mapped.rows?.[0]?.id || null;
    }
    if (!invoiceId) {
      const found = await query(
        `
          select id
          from public.invoices
          where erp_invoice_number = $1
             or invoice_number = $1
          order by (erp_invoice_number = $1) desc
          limit 1
        `,
        [invoiceNumber],
      );
      invoiceId = found.rows[0]?.id || null;
    }
    if (!invoiceId) {
      notFound += 1;
      if (missing.length < 50) missing.push(invoiceNumber);
      report();
      continue;
    }

    const status = textOrNull(invoice.status) || 'open';
    const result = await query(
      `
        update public.invoices
        set paid_amount = $2,
            status = $3,
            updated_at = now()
        where id = $1
          and (
            coalesce(paid_amount, 0) is distinct from $2
            or coalesce(status, '') is distinct from $3
          )
        returning id
      `,
      [invoiceId, numberOrZero(invoice.paidAmount), status],
    );
    if (result.rows.length) {
      updated += 1;
      if (statusCounts[status] != null) statusCounts[status] += 1;
    } else {
      unchanged += 1;
    }
    report();
  }

  return {
    statusOnly: true,
    customers: 0,
    products: 0,
    invoices: updated,
    invoiceItems: 0,
    statusSync: {
      checked: invoices.length,
      updated,
      unchanged,
      notFound,
      unreliable,
      statusCounts,
      missingInvoiceNumbers: missing,
    },
  };
}

async function importAkinsoftDataset(data, onProgress) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  const invoices = Array.isArray(data.invoices) ? data.invoices : [];
  const reportProgress = (current, extra = {}) => {
    if (!onProgress) return;
    const total = Number.isFinite(extra.total) ? Math.max(0, extra.total) : invoices.length;
    const safeCurrent = Math.min(Math.max(0, current), total);
    onProgress({
      stage: extra.stage || 'invoices',
      stageLabel: extra.stageLabel || 'Faturalar yazılıyor',
      current: safeCurrent,
      total,
      invoiceNumber: extra.invoiceNumber ?? null,
      ...extra,
    });
  };
  if (data.statusOnly === true) {
    return syncAkinsoftInvoiceStatuses(query, invoices, reportProgress);
  }

  const selectedCustomerSources = new Set(
    invoices
      .map((invoice) => textOrNull(invoice.customerSourceId))
      .filter(Boolean),
  );
  const selectedCustomerCodes = new Set(
    invoices.map((invoice) => textOrNull(invoice.customerCode)).filter(Boolean),
  );
  const selectedProductSources = new Set();
  const selectedProductCodes = new Set();
  for (const invoice of invoices) {
    for (const item of Array.isArray(invoice.items) ? invoice.items : []) {
      const sourceId = textOrNull(item.productSourceId);
      const code = textOrNull(item.code);
      if (sourceId) selectedProductSources.add(sourceId);
      if (code) selectedProductCodes.add(code);
    }
  }
  const allCustomers = Array.isArray(data.customers) ? data.customers : [];
  const allProducts = Array.isArray(data.products) ? data.products : [];
  const customers = invoices.length
    ? allCustomers.filter(
        (customer) =>
          selectedCustomerSources.has(textOrNull(customer.sourceId)) ||
          selectedCustomerCodes.has(textOrNull(customer.code)),
      )
    : allCustomers;
  // Stoklar fatura seçiminden bağımsız senkronize edilir (çift yönlü).
  const products = allProducts;
  const customerIdBySource = new Map();
  const productIdBySource = new Map();
  const productIdByCode = new Map();

  let customersImported = 0;
  let productsImported = 0;
  let productsCreated = 0;
  let productsUpdated = 0;
  let productsSkipped = 0;
  let invoicesImported = 0;
  let invoiceItemsImported = 0;
  let customersMatchedBySource = 0;
  let customersMatchedByTax = 0;
  let customersMatchedByCode = 0;
  let customersCreated = 0;
  let invoicesSkippedMissingCustomerMatch = 0;
  const skippedInvoices = [];

  const productSnapshots = await loadCrmProductSnapshotsBySource(query);
  for (const [sourceId, snapshot] of productSnapshots.bySourceId) {
    if (snapshot.id) productIdBySource.set(sourceId, snapshot.id);
  }
  for (const [code, snapshot] of productSnapshots.byCode) {
    if (snapshot.id) productIdByCode.set(code, snapshot.id);
  }

  reportProgress(0, {
    stage: 'customers',
    stageLabel: 'Cari eşleşmeleri hazırlanıyor',
    total: customers.length,
  });
  for (let customerIndex = 0; customerIndex < customers.length; customerIndex += 1) {
    const customer = customers[customerIndex];
    const reportCustomerProgress = () => {
      const current = customerIndex + 1;
      if (current === 1 || current === customers.length || current % 10 === 0) {
        reportProgress(current, {
          stage: 'customers',
          stageLabel: 'Cari eşleşmeleri hazırlanıyor',
          total: customers.length,
        });
      }
    };
    const name = textOrNull(customer.name);
    if (!name) {
      reportCustomerProgress();
      continue;
    }
    const customerTaxNumber = taxNumberOrNull(customer.taxNumber);
    let existing = { rows: [] };
    let matchMethod = null;
    if (customerTaxNumber) {
      existing = await query(
        `select id from public.customers where vkn = $1 limit 1`,
        [customerTaxNumber],
      );
      if (existing.rows.length) matchMethod = 'tax';
    }
    if (!existing?.rows?.length) {
      const mapped = await findAkinsoftMappedLocalId(
        query,
        'customer',
        customer.sourceId,
      );
      if (
        isTrustedCustomerMap(mapped.rows?.[0], {
          allowAutomaticVkn: Boolean(customerTaxNumber),
        })
      ) {
        existing = mapped;
        matchMethod = 'source';
      }
    }
    if (!existing?.rows?.length && textOrNull(customer.code)) {
      existing = await findAkinsoftMappedLocalIdByCode(
        query,
        'customer',
        customer.code,
      );
      if (existing.rows.length) matchMethod = 'code_map';
    }
    if (!existing?.rows?.length && textOrNull(customer.code)) {
      existing = await query(
        `
          select c.id
          from public.customers c
          join public.akinsoft_sync_map m
            on m.local_table = 'customers'
           and m.local_id = c.id
          where m.source_type = 'customer'
            and m.source_code = $1
          limit 1
        `,
        [textOrNull(customer.code)],
      );
      if (existing.rows.length) matchMethod = 'code';
    }

    let id = existing?.rows?.[0]?.id || null;
    if (id) {
      await query(
        `
          update public.customers
          set name = $2,
              vkn = coalesce($3, vkn),
              phone_1 = coalesce($4, phone_1),
              email = coalesce($5, email),
              is_active = true
          where id = $1
        `,
        [
          id,
          name,
          customerTaxNumber,
          textOrNull(customer.phone),
          textOrNull(customer.email),
        ],
      );
    } else {
      reportCustomerProgress();
      continue;
    }
    if (!id) {
      reportCustomerProgress();
      continue;
    }
    if (!matchMethod) customersCreated += 1;
    if (matchMethod === 'source') customersMatchedBySource += 1;
    if (matchMethod === 'tax') customersMatchedByTax += 1;
    if (matchMethod === 'code' || matchMethod === 'code_map') {
      customersMatchedByCode += 1;
    }
    customersImported += 1;
    if (customer.sourceId != null) customerIdBySource.set(String(customer.sourceId), id);
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'customer',
      sourceId: customer.sourceId,
      sourceCode: customer.code,
      sourceName: name,
      localTable: 'customers',
      localId: id,
    });
    reportCustomerProgress();
  }

  reportProgress(0, {
    stage: 'products',
    stageLabel: 'Stok kartları hazırlanıyor',
    total: products.length,
  });
  for (let productIndex = 0; productIndex < products.length; productIndex += 1) {
    const product = products[productIndex];
    const reportProductProgress = () => {
      const current = productIndex + 1;
      if (current === 1 || current === products.length || current % 10 === 0) {
        reportProgress(current, {
          stage: 'products',
          stageLabel: 'Stok kartları hazırlanıyor',
          total: products.length,
        });
      }
    };
    const name = textOrNull(product.name);
    if (!name) {
      reportProductProgress();
      continue;
    }
    const code = textOrNull(product.code);
    const sourceId = textOrNull(product.sourceId);
    let id = null;
    let created = false;
    let existingSnapshot =
      (sourceId && productSnapshots.bySourceId.get(sourceId)) ||
      (code && productSnapshots.byCode.get(code)) ||
      null;
    if (existingSnapshot?.id) {
      id = existingSnapshot.id;
    }
    if (!id && sourceId) {
      const mapped = await findAkinsoftMappedLocalId(query, 'product', sourceId);
      id = mapped.rows?.[0]?.id || null;
      if (!id) {
        const bySourceCol = await query(
          `
            select id
            from public.products
            where akinsoft_source_id = $1
            limit 1
          `,
          [sourceId],
        );
        id = bySourceCol.rows?.[0]?.id || null;
      }
    }
    if (!id && code) {
      const byCode = await query(
        `select id from public.products where code = $1 limit 1`,
        [code],
      );
      id = byCode.rows?.[0]?.id || null;
    }
    if (id && existingSnapshot && productSnapshotEqual(existingSnapshot, product)) {
      productsSkipped += 1;
      if (sourceId != null) productIdBySource.set(String(sourceId), id);
      if (code) productIdByCode.set(code, id);
      reportProductProgress();
      continue;
    }
    if (id) {
      await query(
        `
          update public.products
          set
            code = coalesce($2, code),
            name = $3,
            description = coalesce($4, description),
            category = coalesce($5, category),
            unit = coalesce($6, unit),
            tax_rate = coalesce($7, tax_rate),
            akinsoft_group = coalesce($8, akinsoft_group),
            akinsoft_sub_group = coalesce($9, akinsoft_sub_group),
            akinsoft_source_id = coalesce($10, akinsoft_source_id),
            is_active = true
          where id = $1
        `,
        [
          id,
          code,
          name,
          textOrNull(product.description),
          textOrNull(product.category),
          textOrNull(product.unit) || 'Adet',
          numberOrZero(product.taxRate) || 20,
          textOrNull(product.group),
          textOrNull(product.subGroup),
          sourceId,
        ],
      );
    } else if (code) {
      const result = await query(
        `
          insert into public.products (
            code, name, description, category, product_type, unit,
            purchase_price, sale_price, tax_rate, currency, track_stock,
            min_stock, is_active, akinsoft_group, akinsoft_sub_group,
            akinsoft_source_id
          )
          values ($1, $2, $3, $4, 'product', $5, $6, $7, $8, $9, true, 0, true, $10, $11, $12)
          on conflict (code) do update set
            name = excluded.name,
            description = coalesce(excluded.description, public.products.description),
            category = coalesce(excluded.category, public.products.category),
            unit = excluded.unit,
            tax_rate = excluded.tax_rate,
            akinsoft_group = excluded.akinsoft_group,
            akinsoft_sub_group = excluded.akinsoft_sub_group,
            akinsoft_source_id = excluded.akinsoft_source_id,
            is_active = true
          returning id, (xmax = 0) as inserted
        `,
        [
          code,
          name,
          textOrNull(product.description),
          textOrNull(product.category),
          textOrNull(product.unit) || 'Adet',
          numberOrZero(product.purchasePrice),
          numberOrZero(product.salePrice),
          numberOrZero(product.taxRate) || 20,
          textOrNull(product.currency) || 'TRY',
          textOrNull(product.group),
          textOrNull(product.subGroup),
          sourceId,
        ],
      );
      id = result.rows[0]?.id;
      created = result.rows[0]?.inserted === true;
    } else {
      const result = await query(
        `
          insert into public.products (
            name, description, category, product_type, unit, tax_rate,
            currency, track_stock, min_stock, is_active, akinsoft_group,
            akinsoft_sub_group, akinsoft_source_id
          )
          values ($1, $2, $3, 'product', $4, $5, $6, true, 0, true, $7, $8, $9)
          returning id
        `,
        [
          name,
          textOrNull(product.description),
          textOrNull(product.category),
          textOrNull(product.unit) || 'Adet',
          numberOrZero(product.taxRate) || 20,
          textOrNull(product.currency) || 'TRY',
          textOrNull(product.group),
          textOrNull(product.subGroup),
          sourceId,
        ],
      );
      id = result.rows[0]?.id;
      created = true;
    }
    if (!id) {
      reportProductProgress();
      continue;
    }
    if (created) productsCreated += 1;
    else productsUpdated += 1;
    productsImported += 1;
    if (sourceId != null) productIdBySource.set(String(sourceId), id);
    if (code) productIdByCode.set(code, id);
    const nextSnapshot = {
      id,
      code,
      name,
      description: textOrNull(product.description),
      category: textOrNull(product.category),
      unit: textOrNull(product.unit) || 'Adet',
      taxRate: numberOrZero(product.taxRate) || 20,
      group: textOrNull(product.group),
      subGroup: textOrNull(product.subGroup),
      mapped: true,
    };
    if (sourceId != null) productSnapshots.bySourceId.set(String(sourceId), nextSnapshot);
    if (code) productSnapshots.byCode.set(code, nextSnapshot);
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'product',
      sourceId: sourceId || code || id,
      sourceCode: code,
      sourceName: name,
      localTable: 'products',
      localId: id,
    });
    reportProductProgress();
  }

  reportProgress(0, {
    stage: 'invoices',
    stageLabel: 'Faturalar yazılıyor',
    total: invoices.length,
  });
  for (let invoiceIndex = 0; invoiceIndex < invoices.length; invoiceIndex += 1) {
    const invoice = invoices[invoiceIndex];
    const invoiceNumber = textOrNull(invoice.invoiceNumber);
    if (!invoiceNumber) {
      reportProgress(invoiceIndex + 1, { invoiceNumber: null });
      continue;
    }
    const invoiceTaxNumber = taxNumberOrNull(invoice.taxNumber);
    let customerId = textOrNull(invoice.customerMatch?.localId);
    if (customerId && invoice.customerSourceId != null) {
      customerIdBySource.set(String(invoice.customerSourceId), customerId);
    }
    if (!customerId && invoiceTaxNumber) {
      const found = await query(
        `select id from public.customers where vkn = $1 limit 1`,
        [invoiceTaxNumber],
      );
      customerId = found.rows[0]?.id || null;
      if (customerId) customersMatchedByTax += 1;
    }
    if (!customerId && invoice.customerSourceId != null) {
      customerId = customerIdBySource.get(String(invoice.customerSourceId)) || null;
    }
    if (!customerId && invoice.customerSourceId != null) {
      const mapped = await findAkinsoftMappedLocalId(
        query,
        'customer',
        invoice.customerSourceId,
      );
      customerId = isTrustedCustomerMap(mapped.rows?.[0], {
        allowAutomaticVkn: Boolean(invoiceTaxNumber),
      })
        ? mapped.rows[0]?.id || null
        : null;
      if (customerId) customersMatchedBySource += 1;
    }
    if (!customerId && textOrNull(invoice.customerCode)) {
      const mapped = await findAkinsoftMappedLocalIdByCode(
        query,
        'customer',
        invoice.customerCode,
      );
      customerId = mapped.rows[0]?.id || null;
      if (customerId) customersMatchedByCode += 1;
    }
    if (!customerId) {
      invoicesSkippedMissingCustomerMatch += 1;
      skippedInvoices.push({
        invoiceNumber,
        customerSourceId: invoice.customerSourceId,
        customerCode: invoice.customerCode,
        customerName: invoice.customerName,
        reason: 'VKN yok veya CRM carisiyle eşleşmedi.',
      });
      reportProgress(invoiceIndex + 1, {
        invoiceNumber,
        skipped: true,
      });
      continue;
    }
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'customer',
      sourceId: invoice.customerSourceId,
      sourceCode: invoice.customerCode,
      sourceName: invoice.customerName,
      localTable: 'customers',
      localId: customerId,
    });

    const invoiceDate = dateOrIso(invoice.invoiceDate)?.slice(0, 10) || new Date().toISOString().slice(0, 10);
    const dueDate = dateOrIso(invoice.dueDate)?.slice(0, 10);
    const currency = normalizeCurrency(invoice.currency);
    const paymentReliable = invoice.paymentReliable !== false;
    let invoiceId = null;
    if (invoice.sourceId != null) {
      const mappedInvoice = await findAkinsoftMappedLocalId(
        query,
        'invoice',
        invoice.sourceId,
      );
      invoiceId = mappedInvoice.rows?.[0]?.id || null;
    }
    if (invoiceId) {
      await query(
        `
          update public.invoices
          set
            customer_id = $2,
            invoice_date = $3,
            due_date = $4,
            currency = $5,
            subtotal = $6,
            tax_total = $7,
            discount_total = $8,
            grand_total = $9,
            paid_amount = case
              when $11::boolean then $10
              else public.invoices.paid_amount
            end,
            status = case
              when $11::boolean then $12
              else public.invoices.status
            end,
            notes = $13,
            erp_invoice_number = coalesce(erp_invoice_number, $14),
            e_invoice_status = case
              when e_invoice_status = 'sent' then e_invoice_status
              else 'manual'
            end,
            is_active = true,
            updated_at = now()
          where id = $1
        `,
        [
          invoiceId,
          customerId,
          invoiceDate,
          dueDate,
          currency,
          numberOrZero(invoice.subtotal),
          numberOrZero(invoice.taxTotal),
          numberOrZero(invoice.discountTotal),
          numberOrZero(invoice.grandTotal),
          numberOrZero(invoice.paidAmount),
          paymentReliable,
          textOrNull(invoice.status) || 'open',
          textOrNull(invoice.notes),
          invoiceNumber,
        ],
      );
    } else {
      const result = await query(
        `
          insert into public.invoices (
            invoice_number, invoice_type, customer_id, invoice_date, due_date,
            currency, exchange_rate, subtotal, tax_total, discount_total,
            grand_total, paid_amount, status, notes, is_active, erp_invoice_number,
            e_invoice_status
          )
          values (
            $1, 'sales', $2, $3, $4, $5, 1, $6, $7, $8, $9, $10, $11, $12, true, $1,
            'manual'
          )
          on conflict (invoice_number) do update set
            customer_id = excluded.customer_id,
            invoice_date = excluded.invoice_date,
            due_date = excluded.due_date,
            currency = excluded.currency,
            subtotal = excluded.subtotal,
            tax_total = excluded.tax_total,
            discount_total = excluded.discount_total,
            grand_total = excluded.grand_total,
            paid_amount = case
              when $13::boolean then excluded.paid_amount
              else public.invoices.paid_amount
            end,
            status = case
              when $13::boolean then excluded.status
              else public.invoices.status
            end,
            notes = excluded.notes,
            erp_invoice_number = coalesce(public.invoices.erp_invoice_number, excluded.erp_invoice_number),
            e_invoice_status = case
              when public.invoices.e_invoice_status = 'sent' then public.invoices.e_invoice_status
              else 'manual'
            end,
            is_active = true,
            updated_at = now()
          returning id
        `,
        [
          invoiceNumber,
          customerId,
          invoiceDate,
          dueDate,
          currency,
          numberOrZero(invoice.subtotal),
          numberOrZero(invoice.taxTotal),
          numberOrZero(invoice.discountTotal),
          numberOrZero(invoice.grandTotal),
          numberOrZero(invoice.paidAmount),
          textOrNull(invoice.status) || 'open',
          textOrNull(invoice.notes),
          paymentReliable,
        ],
      );
      invoiceId = result.rows[0]?.id;
    }
    if (!invoiceId) continue;
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'invoice',
      sourceId: invoice.sourceId,
      sourceCode: invoiceNumber,
      sourceName: invoice.customerName,
      localTable: 'invoices',
      localId: invoiceId,
    });
    await query(
      `
        update public.invoices
        set erp_invoice_number = coalesce(erp_invoice_number, $2),
            updated_at = now()
        where id = $1
          and (
            erp_invoice_number is null
            or erp_invoice_number = ''
          )
      `,
      [invoiceId, invoiceNumber],
    );
    await query(`delete from public.invoice_items where invoice_id = $1`, [invoiceId]);
    let index = 0;
    const invoiceSubtotal = numberOrZero(invoice.subtotal);
    const invoiceTaxTotal = numberOrZero(invoice.taxTotal);
    for (const item of Array.isArray(invoice.items) ? invoice.items : []) {
      const productId =
        item.productSourceId == null
          ? productIdByCode.get(textOrNull(item.code))
          : productIdBySource.get(String(item.productSourceId)) ||
            productIdByCode.get(textOrNull(item.code));
      const quantity = numberOrZero(item.quantity) || 1;
      const netTotal =
        numberOrZero(item.netTotal) ||
        numberOrZero(item.unitPrice) * quantity;
      const unitPrice = numberOrZero(item.unitPrice) || netTotal / quantity;
      const discountAmount = numberOrZero(item.discountAmount);
      const tax = (invoice.taxes || [])[0] || {};
      const rawTaxRate = numberOrZero(item.taxRate) || numberOrZero(tax.taxRate) || 0;
      const explicitTaxAmount =
        item.taxAmount == null ? null : numberOrZero(item.taxAmount);
      const taxAmount = explicitTaxAmount != null
        ? explicitTaxAmount
        : invoiceSubtotal > 0 && invoiceTaxTotal > 0 && !numberOrZero(item.taxRate)
          ? invoiceTaxTotal * (netTotal / invoiceSubtotal)
          : 0;
      const taxRate = invoiceTaxTotal <= 0 && taxAmount <= 0 ? 0 : rawTaxRate;
      const lineTotal = Math.max(0, netTotal - discountAmount + taxAmount);
      await query(
        `
          insert into public.invoice_items (
            invoice_id, product_id, description, quantity, unit, unit_price,
            tax_rate, tax_amount, discount_rate, discount_amount, line_total,
            sort_order
          )
          values ($1, $2, $3, $4, $5, $6, $7, $8, 0, $9, $10, $11)
        `,
        [
          invoiceId,
          productId || null,
          textOrNull(item.description) || 'Fatura kalemi',
          quantity,
          textOrNull(item.unit) || 'Adet',
          unitPrice,
          taxRate,
          taxAmount,
          discountAmount,
          lineTotal,
          index,
        ],
      );
      index += 1;
      invoiceItemsImported += 1;
    }
    await query(
      `
        update public.invoices i
        set
          subtotal = totals.subtotal,
          tax_total = totals.tax_total,
          discount_total = totals.discount_total,
          grand_total = totals.grand_total,
          status = case
            when $2::boolean and coalesce(i.paid_amount, 0) + 0.02 >= totals.grand_total and totals.grand_total > 0 then 'paid'
            when $2::boolean and coalesce(i.paid_amount, 0) > 0 then 'partial'
            else i.status
          end,
          updated_at = now()
        from (
          select
            coalesce(sum(unit_price * quantity), 0) as subtotal,
            coalesce(sum(tax_amount), 0) as tax_total,
            coalesce(sum(discount_amount), 0) as discount_total,
            coalesce(sum(line_total), 0) as grand_total
          from public.invoice_items
          where invoice_id = $1
        ) totals
        where i.id = $1
      `,
      [invoiceId, paymentReliable],
    );
    invoicesImported += 1;
    reportProgress(invoiceIndex + 1, { invoiceNumber });
  }

  return {
    customers: customersImported,
    products: productsImported,
    productsCreated,
    productsUpdated,
    productsSkipped,
    invoices: invoicesImported,
    invoiceItems: invoiceItemsImported,
    customerMatches: {
      source: customersMatchedBySource,
      tax: customersMatchedByTax,
      code: customersMatchedByCode,
      created: customersCreated,
    },
    skipped: {
      missingCustomerMatch: invoicesSkippedMissingCustomerMatch,
      invoices: skippedInvoices,
      productsUnchanged: productsSkipped,
    },
  };
}

async function handleAkinsoftImport(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const summary = await importAkinsoftDataset(body);
  if (body.statusOnly !== true) {
    try {
      const sql = require('mssql');
      const { config } = buildAkinsoftSqlConfig(body.settings || body);
      config.requestTimeout = Math.max(Number(config.requestTimeout || 0), 180000);
      const pool = await connectAkinsoftPool(config);
      try {
        const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
        summary.productsPush = await pushUnmappedCrmProductsToAkinsoft(
          pool,
          sql,
          query,
        );
      } finally {
        await pool.close();
      }
    } catch (error) {
      summary.productsPush = {
        created: 0,
        matched: 0,
        failed: 0,
        error: error?.message || String(error),
      };
    }
  }
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, summary }),
  );
}

async function handleAkinsoftImportJob(req, res) {
  if (req.method === 'GET') {
    const id = req.query?.id;
    const job = id ? akinsoftJobs.get(id) : null;
    if (!job) {
      return send(
        res,
        404,
        { 'Content-Type': 'application/json; charset=utf-8' },
        JSON.stringify({ ok: false, error: 'İş bulunamadı.' }),
      );
    }
    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: true, job }),
    );
  }
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'GET veya POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const invoices = Array.isArray(body.invoices) ? body.invoices : [];
  if (!invoices.length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'İçe aktarılacak fatura yok.' }),
    );
  }
  const id =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const job = {
    id,
    type: 'import',
    status: 'running',
    stage: 'invoices',
    stageLabel: 'Faturalar yazılıyor',
    total: invoices.length,
    current: 0,
    percent: 0,
    currentInvoiceNumber: null,
    summary: null,
    error: null,
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  akinsoftJobs.set(id, job);
  importAkinsoftDataset(body, ({ stage, stageLabel, current, total, invoiceNumber }) => {
    job.stage = stage || job.stage;
    job.stageLabel = stageLabel || job.stageLabel;
    job.current = Number.isFinite(current) ? current : job.current;
    job.total = Number.isFinite(total) ? total : job.total;
    job.currentInvoiceNumber = invoiceNumber || null;
    job.percent = job.total ? Math.floor((job.current / job.total) * 100) : 0;
    job.updatedAt = new Date().toISOString();
  })
    .then(async (summary) => {
      if (body.statusOnly !== true) {
        try {
          job.stage = 'products_push';
          job.stageLabel = 'CRM stokları Akınsoft’a yazılıyor';
          job.updatedAt = new Date().toISOString();
          const sql = require('mssql');
          const { config } = buildAkinsoftSqlConfig(body.settings || body);
          config.requestTimeout = Math.max(
            Number(config.requestTimeout || 0),
            180000,
          );
          const pool = await connectAkinsoftPool(config);
          try {
            const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
            summary.productsPush = await pushUnmappedCrmProductsToAkinsoft(
              pool,
              sql,
              query,
            );
          } finally {
            await pool.close();
          }
        } catch (error) {
          summary.productsPush = {
            created: 0,
            matched: 0,
            failed: 0,
            error: error?.message || String(error),
          };
        }
      }
      job.status = 'done';
      job.current = job.total;
      job.percent = 100;
      job.summary = summary;
      job.updatedAt = new Date().toISOString();
    })
    .catch((error) => {
      job.status = 'error';
      job.error = error instanceof Error ? error.message : String(error);
      job.updatedAt = new Date().toISOString();
    });
  return send(
    res,
    202,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, jobId: id, job }),
  );
}

async function handleAkinsoftLocalCustomers(req, res) {
  if (req.method !== 'GET') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'GET gerekli.' }),
    );
  }
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  const search = textOrNull(req.query?.search) || '';
  const normalizedSearch = search
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'I')
    .replace(/ğ/g, 'g')
    .replace(/Ğ/g, 'G')
    .replace(/ü/g, 'u')
    .replace(/Ü/g, 'U')
    .replace(/ş/g, 's')
    .replace(/Ş/g, 'S')
    .replace(/ö/g, 'o')
    .replace(/Ö/g, 'O')
    .replace(/ç/g, 'c')
    .replace(/Ç/g, 'C');
  const like = `%${search}%`;
  const normalizedLike = `%${normalizedSearch}%`;
  const result = await query(
    `
      select id, name, vkn as tax_number, phone_1 as phone1, email
      from public.customers
      where is_active is not false
        and (
          $1 = ''
          or coalesce(name, '') ilike $2
          or coalesce(vkn, '') ilike $2
          or coalesce(phone_1, '') ilike $2
          or translate(
              coalesce(name, ''),
              'ıİğĞüÜşŞöÖçÇ',
              'iIgGuUsSoOcC'
            ) ilike $3
        )
      order by name
      limit 40
    `,
    [search, like, normalizedLike],
  );
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, customers: result.rows }),
  );
}

async function handleAkinsoftMapCustomer(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const sourceId = textOrNull(body.sourceId);
  const localCustomerId = textOrNull(body.localCustomerId);
  if (!sourceId || !localCustomerId) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'Akınsoft cari ve CRM cari seçimi gerekli.' }),
    );
  }

  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  const customer = await query(
    `select id, name, vkn from public.customers where id = $1 limit 1`,
    [localCustomerId],
  );
  if (!customer.rows.length) {
    return send(
      res,
      404,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'CRM carisi bulunamadı.' }),
    );
  }
  const localName = customer.rows[0].name;
  await upsertAkinsoftSyncMap(query, {
    sourceType: 'customer',
    sourceId,
    sourceCode: body.sourceCode,
    sourceName: body.sourceName,
    localTable: 'customers',
    localId: localCustomerId,
    matchedManually: true,
  });

  let wroteBack = false;
  let writeBackError = null;
  try {
    await writeAkinsoftCustomerMatch(body.settings || body, {
      sourceId,
      sourceCode: body.sourceCode,
      sourceName: body.sourceName,
      localCustomerId,
      localCustomerName: localName,
      localCustomerTaxNumber: customer.rows[0].vkn,
    });
    wroteBack = true;
  } catch (error) {
    writeBackError = error instanceof Error ? error.message : String(error);
  }

  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({
      ok: true,
      match: {
        matched: true,
        method: wroteBack ? 'manual_akinsoft' : 'manual_local',
        localId: localCustomerId,
        localName,
        wroteBack,
        writeBackError,
      },
    }),
  );
}

async function handleAkinsoftBulkMapCustomers(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const matches = Array.isArray(body.matches) ? body.matches : [];
  if (!matches.length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'Kaydedilecek cari eşleşmesi yok.' }),
    );
  }

  const summary = await processAkinsoftBulkMapCustomers(body, matches);
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, summary }),
  );
}

async function processAkinsoftBulkMapCustomers(body, matches, onProgress) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  let saved = 0;
  let wroteBack = 0;
  const skipped = [];
  const errors = [];

  for (let index = 0; index < matches.length; index += 1) {
    const raw = matches[index];
    const item = raw && typeof raw === 'object' ? raw : {};
    const sourceId = textOrNull(item.sourceId);
    const localCustomerId = textOrNull(item.localCustomerId);
    if (!sourceId || !localCustomerId) {
      skipped.push({ sourceId, reason: 'Akınsoft cari veya CRM cari eksik.' });
      if (onProgress) onProgress({ current: index + 1, sourceId });
      continue;
    }
    const customer = await query(
      `select id, name, vkn from public.customers where id = $1 limit 1`,
      [localCustomerId],
    );
    if (!customer.rows.length) {
      skipped.push({ sourceId, reason: 'CRM carisi bulunamadı.' });
      if (onProgress) onProgress({ current: index + 1, sourceId });
      continue;
    }
    const localName = customer.rows[0].name;
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'customer',
      sourceId,
      sourceCode: item.sourceCode,
      sourceName: item.sourceName,
      localTable: 'customers',
      localId: localCustomerId,
      matchedManually: true,
    });
    saved += 1;
    try {
      await withTimeout(
        writeAkinsoftCustomerMatch(body.settings || body, {
          sourceId,
          sourceCode: item.sourceCode,
          sourceName: item.sourceName,
          localCustomerId,
          localCustomerName: localName,
          localCustomerTaxNumber: customer.rows[0].vkn,
        }),
        12000,
        'Akınsoft yazma zaman aşımına uğradı.',
      );
      wroteBack += 1;
    } catch (error) {
      errors.push({
        sourceId,
        error: error instanceof Error ? error.message : String(error),
      });
    }
    if (onProgress) onProgress({ current: index + 1, sourceId });
  }

  const savedSourceIds = matches
    .map((item) => textOrNull(item && typeof item === 'object' ? item.sourceId : null))
    .filter(Boolean);
  let verified = 0;
  if (savedSourceIds.length) {
    const verifiedResult = await query(
      `
        select count(*)::int as count
        from public.akinsoft_sync_map
        where source_system = 'akinsoft'
          and source_type = 'customer'
          and source_id = any($1::text[])
      `,
      [savedSourceIds],
    );
    verified = verifiedResult.rows[0]?.count ?? 0;
  }

  return { requested: matches.length, saved, verified, wroteBack, skipped, errors };
}

async function handleAkinsoftBulkMapCustomersJob(req, res) {
  if (req.method === 'GET') {
    const id = req.query?.id;
    const job = id ? akinsoftJobs.get(id) : null;
    if (!job) {
      return send(
        res,
        404,
        { 'Content-Type': 'application/json; charset=utf-8' },
        JSON.stringify({ ok: false, error: 'İş bulunamadı.' }),
      );
    }
    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: true, job }),
    );
  }
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'GET veya POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const matches = Array.isArray(body.matches) ? body.matches : [];
  if (!matches.length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'Kaydedilecek cari eşleşmesi yok.' }),
    );
  }
  const id =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const job = {
    id,
    status: 'running',
    total: matches.length,
    current: 0,
    percent: 0,
    currentSourceId: null,
    summary: null,
    error: null,
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  akinsoftJobs.set(id, job);
  processAkinsoftBulkMapCustomers(body, matches, ({ current, sourceId }) => {
    job.current = current;
    job.currentSourceId = sourceId || null;
    job.percent = job.total ? Math.floor((current / job.total) * 100) : 0;
    job.updatedAt = new Date().toISOString();
  })
    .then((summary) => {
      job.status = 'done';
      job.current = job.total;
      job.percent = 100;
      job.summary = summary;
      job.updatedAt = new Date().toISOString();
    })
    .catch((error) => {
      job.status = 'error';
      job.error = error instanceof Error ? error.message : String(error);
      job.updatedAt = new Date().toISOString();
    });
  return send(
    res,
    202,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, jobId: id, job }),
  );
}

async function findDuplicateAkinsoftCustomers(query) {
  const result = await query(`
    with base as (
      select
        c.id,
        c.name,
        c.vkn,
        c.created_at,
        coalesce(inv.cnt, 0) as invoice_count,
        exists (
          select 1
          from public.akinsoft_sync_map m
          where m.source_system = 'akinsoft'
            and m.source_type = 'customer'
            and m.local_id = c.id
        ) as has_akinsoft_map,
        lower(regexp_replace(trim(c.name), '\\s+', ' ', 'g')) as key_name
      from public.customers c
      left join (
        select customer_id, count(*)::int as cnt
        from public.invoices
        group by customer_id
      ) inv on inv.customer_id = c.id
      where c.is_active is not false
        and coalesce(trim(c.name), '') <> ''
    ),
    duplicate_groups as (
      select key_name
      from base
      group by key_name
      having count(*) > 1
         and bool_or(has_akinsoft_map or vkn is null)
    )
    select *
    from base
    where key_name in (select key_name from duplicate_groups)
    order by key_name, invoice_count desc, created_at asc
  `);
  const groups = new Map();
  for (const row of result.rows) {
    const list = groups.get(row.key_name) || [];
    list.push(row);
    groups.set(row.key_name, list);
  }
  return [...groups.entries()].map(([key, rows]) => ({
    key,
    keep: rows[0],
    remove: rows.slice(1),
    count: rows.length,
  }));
}

async function findVknlessAkinsoftCustomers(query) {
  const result = await query(`
    select
      c.id,
      c.name,
      c.vkn,
      c.created_at,
      coalesce(inv.cnt, 0) as invoice_count
    from public.customers c
    left join (
      select customer_id, count(*)::int as cnt
      from public.invoices
      group by customer_id
    ) inv on inv.customer_id = c.id
    where c.is_active is not false
      and nullif(trim(coalesce(c.vkn, '')), '') is null
      and exists (
        select 1
        from public.akinsoft_sync_map m
        where m.source_system = 'akinsoft'
          and m.source_type = 'customer'
          and m.local_id = c.id
      )
    order by invoice_count asc, c.created_at desc
    limit 500
  `);
  return result.rows || [];
}

async function handleAkinsoftDuplicateCustomers(req, res) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);

  if (req.method === 'GET') {
    const groups = await findDuplicateAkinsoftCustomers(query);
    const vknless = await findVknlessAkinsoftCustomers(query);
    return send(
      res,
      200,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({
        ok: true,
        groups: groups.slice(0, 50),
        vknless: vknless.slice(0, 50),
        duplicateGroups: groups.length,
        removableCustomers: groups.reduce((sum, item) => sum + item.remove.length, 0),
        vknlessCustomers: vknless.length,
      }),
    );
  }

  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'GET veya POST gerekli.' }),
    );
  }

  const groups = await findDuplicateAkinsoftCustomers(query);
  let merged = 0;
  let deactivated = 0;
  for (const group of groups) {
    const keepId = group.keep.id;
    const removeIds = group.remove.map((item) => item.id);
    if (!removeIds.length) continue;
    await query(`update public.invoices set customer_id = $1 where customer_id = any($2::uuid[])`, [keepId, removeIds]);
    await query(`update public.akinsoft_sync_map set local_id = $1 where local_id = any($2::uuid[])`, [keepId, removeIds]);
    await query(`update public.payments set customer_id = $1 where customer_id = any($2::uuid[])`, [keepId, removeIds]).catch(() => {});
    await query(`update public.transactions set customer_id = $1 where customer_id = any($2::uuid[])`, [keepId, removeIds]).catch(() => {});
    try {
      const deleted = await query(
        `delete from public.customers where id = any($1::uuid[]) returning id`,
        [removeIds],
      );
      merged += deleted.rows.length;
    } catch (_) {
      await query(`update public.customers set is_active = false where id = any($1::uuid[])`, [removeIds]);
      deactivated += removeIds.length;
    }
  }
  const vknless = await findVknlessAkinsoftCustomers(query);
  const alreadyHandled = new Set(groups.flatMap((group) => group.remove.map((item) => item.id)));
  const vknlessIds = vknless
    .map((item) => item.id)
    .filter((id) => id && !alreadyHandled.has(id));
  if (vknlessIds.length) {
    const deletable = vknless
      .filter((item) => vknlessIds.includes(item.id) && Number(item.invoice_count || 0) === 0)
      .map((item) => item.id);
    const passiveOnly = vknlessIds.filter((id) => !deletable.includes(id));
    if (deletable.length) {
      const deleted = await query(
        `delete from public.customers where id = any($1::uuid[]) returning id`,
        [deletable],
      ).catch(() => ({ rows: [] }));
      merged += deleted.rows.length;
      const notDeleted = deletable.filter(
        (id) => !deleted.rows.some((row) => row.id === id),
      );
      passiveOnly.push(...notDeleted);
    }
    if (passiveOnly.length) {
      await query(`update public.customers set is_active = false where id = any($1::uuid[])`, [passiveOnly]);
      deactivated += passiveOnly.length;
    }
  }
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({ ok: true, merged, deactivated, groups: groups.length, vknless: vknless.length }),
  );
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

async function readAkinsoftInvoiceNumberBySourceId(pool, sql, sourceId) {
  const id = textOrNull(sourceId);
  if (!id) return null;
  const result = await pool
    .request()
    .input('sourceId', sql.NVarChar(64), id)
    .query(`
      select top 1 FATURA_NO as invoiceNumber
      from dbo.FATURA
      where cast(BLKODU as nvarchar(64)) = @sourceId
    `);
  return textOrNull(result.recordset?.[0]?.invoiceNumber);
}

async function writeAkinsoftInvoiceNumber(pool, sql, item) {
  const newNumber = textOrNull(item.newNumber);
  const sourceId = textOrNull(item.sourceId);
  let oldNumber = textOrNull(item.oldNumber);
  if (!newNumber) {
    return { ok: false, reason: 'Yeni fatura numarası yok.' };
  }

  // BLKODU biliniyorsa Akınsoft’taki güncel numarayı esas al.
  if (sourceId) {
    const current = await readAkinsoftInvoiceNumberBySourceId(pool, sql, sourceId);
    if (current) oldNumber = current;
  }

  if (oldNumber && oldNumber === newNumber) {
    return { ok: true, skipped: true, reason: 'Numara zaten aynı.', oldNumber };
  }

  const existing = await pool
    .request()
    .input('newNumber', sql.NVarChar(64), newNumber)
    .input('sourceId', sql.NVarChar(64), sourceId)
    .query(`
      select top 1
        cast(BLKODU as nvarchar(64)) as sourceId,
        FATURA_NO as invoiceNumber
      from dbo.FATURA
      where FATURA_NO = @newNumber
        and (
          @sourceId is null
          or cast(BLKODU as nvarchar(64)) <> @sourceId
        )
    `);
  if (existing.recordset?.length) {
    return {
      ok: false,
      reason: `Akınsoft’ta ${newNumber} numarası başka bir faturada kullanılıyor.`,
      oldNumber,
    };
  }

  let updated = 0;
  if (sourceId) {
    const byId = await pool
      .request()
      .input('sourceId', sql.NVarChar(64), sourceId)
      .input('newNumber', sql.NVarChar(64), newNumber)
      .query(`
        update dbo.FATURA
        set FATURA_NO = @newNumber
        where cast(BLKODU as nvarchar(64)) = @sourceId
      `);
    updated = Number(byId.rowsAffected?.[0] || 0);
  }
  if (!updated && oldNumber) {
    const byNo = await pool
      .request()
      .input('oldNumber', sql.NVarChar(64), oldNumber)
      .input('newNumber', sql.NVarChar(64), newNumber)
      .query(`
        update dbo.FATURA
        set FATURA_NO = @newNumber
        where FATURA_NO = @oldNumber
      `);
    updated = Number(byNo.rowsAffected?.[0] || 0);
  }
  if (!updated) {
    return {
      ok: false,
      reason: oldNumber
        ? `Akınsoft’ta ${oldNumber} numaralı fatura bulunamadı.`
        : 'Akınsoft fatura eşlemesi (BLKODU) bulunamadı.',
      oldNumber,
    };
  }

  if (oldNumber && oldNumber !== newNumber) {
    await pool
      .request()
      .input('oldNumber', sql.NVarChar(64), oldNumber)
      .input('newNumber', sql.NVarChar(64), newNumber)
      .query(`
        update dbo.CARIHR
        set EVRAK_NO = @newNumber
        where EVRAK_NO = @oldNumber
      `);
  }

  return { ok: true, updated, oldNumber };
}

async function findAkinsoftSourceByLocalId(query, sourceType, localId) {
  const id = textOrNull(localId);
  if (!id) return null;
  const result = await query(
    `
      select source_id, source_code, source_name, matched_manually
      from public.akinsoft_sync_map
      where source_system = 'akinsoft'
        and source_type = $1
        and local_id = $2::uuid
      order by matched_manually desc, updated_at desc
      limit 1
    `,
    [sourceType, id],
  );
  return result.rows?.[0] || null;
}

async function akinsoftColumnIsIdentity(pool, tableName, columnName = 'BLKODU') {
  const result = await pool.request().query(`
    select COLUMNPROPERTY(
      OBJECT_ID(N'dbo.${String(tableName).replace(/'/g, "''")}'),
      N'${String(columnName).replace(/'/g, "''")}',
      'IsIdentity'
    ) as is_identity
  `);
  return Number(result.recordset?.[0]?.is_identity) === 1;
}

async function akinsoftNextBlkoduSafe(pool, tableName) {
  const safe = String(tableName || '').replace(/[^A-Za-z0-9_]/g, '');
  if (!safe) throw new Error('Geçersiz tablo adı.');
  const result = await pool.request().query(`
    select isnull(max(try_convert(bigint, BLKODU)), 0) + 1 as next_id
    from dbo.${safe}
  `);
  return Number(result.recordset?.[0]?.next_id || 1);
}

function setFirstColumn(target, columns, names, value) {
  if (value === undefined) return false;
  for (const name of names) {
    const key = String(name).toUpperCase();
    if (columns.has(key)) {
      target[key] = value;
      return true;
    }
  }
  return false;
}

async function insertAkinsoftRowWithRequest(
  requestFactory,
  sql,
  tableName,
  columns,
  values,
) {
  const safeTable = String(tableName || '').replace(/[^A-Za-z0-9_]/g, '');
  const entries = Object.entries(values).filter(
    ([key, value]) => value !== undefined && columns.has(String(key).toUpperCase()),
  );
  if (!entries.length) {
    throw new Error(`${safeTable} için yazılacak kolon bulunamadı.`);
  }
  const request = requestFactory();
  const colSql = [];
  const valSql = [];
  entries.forEach(([key, value], index) => {
    const col = String(key).toUpperCase();
    const param = `p${index}`;
    colSql.push(`[${col}]`);
    valSql.push(`@${param}`);
    bindSqlValue(request, sql, param, value);
  });
  const result = await request.query(`
    insert into dbo.${safeTable} (${colSql.join(', ')})
    output inserted.BLKODU as BLKODU
    values (${valSql.join(', ')})
  `);
  return result.recordset?.[0]?.BLKODU == null
    ? null
    : String(result.recordset[0].BLKODU);
}

async function findAkinsoftCariByTaxNumber(pool, sql, taxNumber) {
  const vkn = taxNumberOrNull(taxNumber);
  if (!vkn) return null;
  const result = await pool
    .request()
    .input('vkn', sql.NVarChar(32), vkn)
    .query(`
      select top 1
        cast(BLKODU as nvarchar(64)) as sourceId,
        CARIKODU as sourceCode,
        coalesce(TICARI_UNVANI, ADI_SOYADI, ADI) as sourceName
      from dbo.CARI
      where replace(replace(coalesce(VERGI_NO, ''), ' ', ''), '-', '') = @vkn
         or coalesce(VERGI_NO, '') = @vkn
    `);
  const row = result.recordset?.[0];
  if (!row?.sourceId) return null;
  return {
    sourceId: String(row.sourceId),
    sourceCode: textOrNull(row.sourceCode),
    sourceName: textOrNull(row.sourceName),
    matchedBy: 'vkn',
  };
}

async function createAkinsoftCari(pool, sql, query, customer) {
  const hasCari = await akinsoftTableExists(pool, 'CARI');
  if (!hasCari) {
    throw new Error('Akınsoft CARI tablosu bulunamadı.');
  }
  const columns = await akinsoftTableColumnSet(pool, 'CARI');
  const identity = await akinsoftColumnIsIdentity(pool, 'CARI', 'BLKODU');
  const name =
    textOrNull(customer.name) ||
    textOrNull(customer.customer_name) ||
    'CRM Cari';
  const taxNumber = taxNumberOrNull(customer.vkn || customer.tax_number);
  const code =
    textOrNull(customer.code) ||
    (taxNumber ? `MV${taxNumber}` : `MV${String(customer.id || '').replace(/-/g, '').slice(0, 10)}`);

  // Aynı cari kodu varsa üzerine yazmak yerine mevcut kaydı kullan.
  if (code) {
    const existingCode = await pool
      .request()
      .input('code', sql.NVarChar(64), code)
      .query(`
        select top 1
          cast(BLKODU as nvarchar(64)) as sourceId,
          CARIKODU as sourceCode,
          coalesce(TICARI_UNVANI, ADI_SOYADI, ADI) as sourceName
        from dbo.CARI
        where CARIKODU = @code
      `);
    if (existingCode.recordset?.[0]?.sourceId) {
      const row = existingCode.recordset[0];
      return {
        sourceId: String(row.sourceId),
        sourceCode: textOrNull(row.sourceCode) || code,
        sourceName: textOrNull(row.sourceName) || name,
        created: false,
        matchedBy: 'code',
      };
    }
  }

  const values = {};
  if (!identity) {
    values.BLKODU = await akinsoftNextBlkoduSafe(pool, 'CARI');
  }
  setFirstColumn(values, columns, ['CARIKODU'], code);
  setFirstColumn(values, columns, ['TICARI_UNVANI', 'ADI_SOYADI', 'ADI'], name);
  setFirstColumn(values, columns, ['VERGI_NO'], taxNumber);
  setFirstColumn(
    values,
    columns,
    ['VERGI_DAIRESI'],
    textOrNull(customer.tax_office),
  );
  setFirstColumn(
    values,
    columns,
    ['TEL1', 'TEL'],
    textOrNull(customer.phone_1 || customer.phone),
  );
  setFirstColumn(
    values,
    columns,
    ['CEP_TEL'],
    textOrNull(customer.mobile || customer.phone_2),
  );
  setFirstColumn(values, columns, ['E_MAIL', 'EMAIL'], textOrNull(customer.email));
  setFirstColumn(
    values,
    columns,
    ['ADRES', 'ADRES1', 'ADRESI', 'ADRES_1'],
    textOrNull(customer.address_line1 || customer.address),
  );
  setFirstColumn(
    values,
    columns,
    ['IL', 'SEHIR', 'ILI'],
    textOrNull(customer.city),
  );
  setFirstColumn(values, columns, ['ULKE'], textOrNull(customer.country));
  setFirstColumn(values, columns, ['SILINDI', 'SILINDI_MI', 'DELETED'], 0);
  setFirstColumn(values, columns, ['AKTIF', 'AKTIF_MI'], 1);
  setFirstColumn(values, columns, ['KAYIT_TARIHI'], new Date());

  const sourceId = await insertAkinsoftRowWithRequest(
    () => pool.request(),
    sql,
    'CARI',
    columns,
    values,
  );
  if (!sourceId) {
    throw new Error('Akınsoft cari kaydı oluşturulamadı.');
  }

  if (customer.id) {
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'customer',
      sourceId,
      sourceCode: code,
      sourceName: name,
      localTable: 'customers',
      localId: customer.id,
    });
    try {
      await ensureAkinsoftCustomerMatchTable(pool);
      await pool
        .request()
        .input('sourceId', sql.NVarChar(64), String(sourceId))
        .input('sourceCode', sql.NVarChar(64), code)
        .input('sourceName', sql.NVarChar(255), name)
        .input('localId', sql.NVarChar(64), String(customer.id))
        .input('localName', sql.NVarChar(255), name)
        .query(`
          merge dbo.MICROVISE_CARI_ESLESME as target
          using (select @sourceId as AKINSOFT_BLKODU) as source
            on target.AKINSOFT_BLKODU = source.AKINSOFT_BLKODU
          when matched then update set
            AKINSOFT_CARIKODU = @sourceCode,
            AKINSOFT_CARI_ADI = @sourceName,
            CRM_CUSTOMER_ID = @localId,
            CRM_CUSTOMER_NAME = @localName,
            GUNCELLEME_TARIHI = sysdatetime()
          when not matched then insert (
            AKINSOFT_BLKODU, AKINSOFT_CARIKODU, AKINSOFT_CARI_ADI,
            CRM_CUSTOMER_ID, CRM_CUSTOMER_NAME
          ) values (
            @sourceId, @sourceCode, @sourceName, @localId, @localName
          );
        `);
      if (taxNumber) {
        await pool
          .request()
          .input('sourceId', sql.NVarChar(64), String(sourceId))
          .input('localTaxNumber', sql.NVarChar(32), taxNumber)
          .query(`
            update dbo.CARI
            set VERGI_NO = @localTaxNumber
            where cast(BLKODU as nvarchar(64)) = @sourceId
              and (
                VERGI_NO is null
                or ltrim(rtrim(VERGI_NO)) = ''
              )
          `);
      }
    } catch (_) {
      // Yerel eşleşme tablosu opsiyonel.
    }
  }

  return {
    sourceId,
    sourceCode: code,
    sourceName: name,
    created: true,
    matchedBy: 'created',
  };
}

async function createAkinsoftStok(pool, sql, query, product, cached = null) {
  const hasStok = cached?.hasStok ?? (await akinsoftTableExists(pool, 'STOK'));
  if (!hasStok) {
    throw new Error('Akınsoft STOK tablosu bulunamadı.');
  }
  const columns =
    cached?.columns || (await akinsoftTableColumnSet(pool, 'STOK'));
  const identity =
    cached?.identity ?? (await akinsoftColumnIsIdentity(pool, 'STOK', 'BLKODU'));
  const name = textOrNull(product.name) || 'CRM Stok';
  const code =
    textOrNull(product.code) ||
    `MV${String(product.id || '').replace(/-/g, '').slice(0, 12)}`;

  if (code) {
    const existing = await pool
      .request()
      .input('code', sql.NVarChar(64), code)
      .query(`
        select top 1
          cast(BLKODU as nvarchar(64)) as sourceId,
          STOKKODU as sourceCode,
          STOK_ADI as sourceName
        from dbo.STOK
        where STOKKODU = @code
      `);
    if (existing.recordset?.[0]?.sourceId) {
      const row = existing.recordset[0];
      if (product.id) {
        await upsertAkinsoftSyncMap(query, {
          sourceType: 'product',
          sourceId: String(row.sourceId),
          sourceCode: textOrNull(row.sourceCode) || code,
          sourceName: textOrNull(row.sourceName) || name,
          localTable: 'products',
          localId: product.id,
        });
        await query(
          `
            update public.products
            set akinsoft_source_id = $2,
                code = coalesce(nullif(trim(code), ''), $3)
            where id = $1::uuid
          `,
          [product.id, String(row.sourceId), code],
        );
      }
      return {
        sourceId: String(row.sourceId),
        sourceCode: textOrNull(row.sourceCode) || code,
        sourceName: textOrNull(row.sourceName) || name,
        created: false,
        matchedBy: 'code',
      };
    }
  }

  const values = {};
  if (!identity) {
    values.BLKODU = await akinsoftNextBlkoduSafe(pool, 'STOK');
  }
  setFirstColumn(values, columns, ['STOKKODU'], code);
  setFirstColumn(values, columns, ['STOK_ADI'], name);
  setFirstColumn(
    values,
    columns,
    ['ACIKLAMA1', 'ACIKLAMA', 'ACIKLAMA2'],
    textOrNull(product.description),
  );
  setFirstColumn(values, columns, ['BIRIMI'], textOrNull(product.unit) || 'Adet');
  setFirstColumn(
    values,
    columns,
    ['KDV_ORANI'],
    numberOrZero(product.tax_rate) || 20,
  );
  setFirstColumn(
    values,
    columns,
    ['ARA_GRUBU', 'OZEL_KODU1'],
    textOrNull(product.akinsoft_group || product.category),
  );
  setFirstColumn(
    values,
    columns,
    ['ALT_GRUBU', 'OZEL_KODU2'],
    textOrNull(product.akinsoft_sub_group),
  );
  setFirstColumn(values, columns, ['SILINDI', 'SILINDI_MI', 'DELETED'], 0);
  setFirstColumn(values, columns, ['AKTIF', 'AKTIF_MI'], 1);
  setFirstColumn(values, columns, ['KAYIT_TARIHI'], new Date());

  const sourceId = await insertAkinsoftRowWithRequest(
    () => pool.request(),
    sql,
    'STOK',
    columns,
    values,
  );
  if (!sourceId) {
    throw new Error('Akınsoft stok kaydı oluşturulamadı.');
  }

  if (product.id) {
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'product',
      sourceId,
      sourceCode: code,
      sourceName: name,
      localTable: 'products',
      localId: product.id,
    });
    await query(
      `
        update public.products
        set akinsoft_source_id = $2,
            code = coalesce(nullif(trim(code), ''), $3)
        where id = $1::uuid
      `,
      [product.id, sourceId, code],
    );
  }

  return {
    sourceId,
    sourceCode: code,
    sourceName: name,
    created: true,
    matchedBy: 'created',
  };
}

async function pushUnmappedCrmProductsToAkinsoft(pool, sql, query) {
  await ensureAkinsoftSyncMap(query);
  const result = await query(
    `
      select
        p.id,
        p.code,
        p.name,
        p.description,
        p.unit,
        p.tax_rate,
        p.category,
        p.akinsoft_group,
        p.akinsoft_sub_group,
        p.akinsoft_source_id
      from public.products p
      left join public.akinsoft_sync_map m
        on m.source_system = 'akinsoft'
       and m.source_type = 'product'
       and m.local_id = p.id
      where p.is_active = true
        and coalesce(trim(p.name), '') <> ''
        and m.id is null
        and coalesce(nullif(trim(p.akinsoft_source_id), ''), '') = ''
      order by p.created_at desc
      limit 2000
    `,
  );

  let created = 0;
  let matched = 0;
  let failed = 0;
  const errors = [];
  if (!result.rows.length) {
    return { created, matched, failed, errors, scanned: 0 };
  }
  const hasStok = await akinsoftTableExists(pool, 'STOK');
  if (!hasStok) {
    return {
      created: 0,
      matched: 0,
      failed: result.rows.length,
      errors: [{ reason: 'Akınsoft STOK tablosu bulunamadı.' }],
      scanned: result.rows.length,
    };
  }
  const cached = {
    hasStok: true,
    columns: await akinsoftTableColumnSet(pool, 'STOK'),
    identity: await akinsoftColumnIsIdentity(pool, 'STOK', 'BLKODU'),
  };
  for (const product of result.rows) {
    try {
      const write = await createAkinsoftStok(pool, sql, query, product, cached);
      if (write.created) created += 1;
      else matched += 1;
    } catch (error) {
      failed += 1;
      if (errors.length < 20) {
        errors.push({
          productId: product.id,
          name: product.name,
          reason: error?.message || String(error),
        });
      }
    }
  }
  return { created, matched, failed, errors, scanned: result.rows.length };
}

async function resolveAkinsoftCustomerForPush(pool, sql, query, invoice) {
  const mapped = await findAkinsoftSourceByLocalId(
    query,
    'customer',
    invoice.customer_id,
  );
  if (mapped?.source_id) {
    return {
      sourceId: String(mapped.source_id),
      sourceCode: textOrNull(mapped.source_code),
      sourceName: textOrNull(mapped.source_name) || textOrNull(invoice.customer_name),
      created: false,
      matchedBy: 'map',
    };
  }

  const taxNumber = taxNumberOrNull(invoice.customer_vkn || invoice.vkn);
  if (taxNumber) {
    const byVkn = await findAkinsoftCariByTaxNumber(pool, sql, taxNumber);
    if (byVkn) {
      if (invoice.customer_id) {
        await upsertAkinsoftSyncMap(query, {
          sourceType: 'customer',
          sourceId: byVkn.sourceId,
          sourceCode: byVkn.sourceCode,
          sourceName: byVkn.sourceName,
          localTable: 'customers',
          localId: invoice.customer_id,
        });
      }
      return { ...byVkn, created: false };
    }
  }

  return createAkinsoftCari(pool, sql, query, {
    id: invoice.customer_id,
    name: invoice.customer_name,
    code: invoice.customer_code,
    vkn: taxNumber,
    tax_office: invoice.customer_tax_office,
    phone_1: invoice.customer_phone,
    email: invoice.customer_email,
    address_line1: invoice.customer_address,
    city: invoice.customer_city,
    country: invoice.customer_country,
  });
}

async function writeAkinsoftInvoiceCreate(pool, sql, query, invoice) {
  const invoiceId = textOrNull(invoice.id);
  const maliyeNumber = localEInvoiceNumber(invoice.e_invoice_number);
  const invoiceNumber =
    (String(invoice.e_invoice_status || '') === 'sent' && maliyeNumber) ||
    localEInvoiceNumber(invoice.invoice_number) ||
    textOrNull(invoice.invoice_number);
  if (!invoiceId || !invoiceNumber) {
    return { ok: false, reason: 'Fatura numarası veya id eksik.' };
  }
  if (!Array.isArray(invoice.items) || invoice.items.length === 0) {
    return { ok: false, reason: 'Faturada kalem yok.' };
  }

  const existingMap = await findAkinsoftSourceByLocalId(query, 'invoice', invoiceId);
  if (existingMap?.source_id) {
    return {
      ok: true,
      skipped: true,
      reason: 'Fatura zaten Akınsoft ile eşleşmiş.',
      sourceId: String(existingMap.source_id),
      invoiceNumber,
    };
  }

  let customerRef;
  try {
    customerRef = await resolveAkinsoftCustomerForPush(pool, sql, query, invoice);
  } catch (error) {
    return {
      ok: false,
      reason: `Cari çözümlenemedi: ${error?.message || error}`,
    };
  }
  const customerSourceId = Number(customerRef.sourceId);
  if (!Number.isFinite(customerSourceId)) {
    return { ok: false, reason: `Geçersiz cari BLKODU: ${customerRef.sourceId}` };
  }
  const customerMap = {
    source_id: customerRef.sourceId,
    source_code: customerRef.sourceCode,
    source_name: customerRef.sourceName,
  };

  const duplicate = await pool
    .request()
    .input('invoiceNumber', sql.NVarChar(64), invoiceNumber)
    .query(`
      select top 1 cast(BLKODU as nvarchar(64)) as sourceId
      from dbo.FATURA
      where FATURA_NO = @invoiceNumber
    `);
  if (duplicate.recordset?.length) {
    const sourceId = String(duplicate.recordset[0].sourceId);
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'invoice',
      sourceId,
      sourceCode: invoiceNumber,
      sourceName: textOrNull(invoice.customer_name),
      localTable: 'invoices',
      localId: invoiceId,
    });
    await query(
      `
        update public.invoices
        set erp_invoice_number = coalesce(nullif(trim(erp_invoice_number), ''), $2),
            erp_invoice_number_synced_at = now(),
            updated_at = now()
        where id = $1::uuid
      `,
      [invoiceId, invoiceNumber],
    );
    return {
      ok: true,
      skipped: true,
      reason: 'Akınsoft’ta aynı numaralı fatura vardı; eşleme güncellendi.',
      sourceId,
      invoiceNumber,
    };
  }

  const hasFatura = await akinsoftTableExists(pool, 'FATURA');
  const hasFaturaHr = await akinsoftTableExists(pool, 'FATURAHR');
  if (!hasFatura || !hasFaturaHr) {
    return { ok: false, reason: 'Akınsoft FATURA / FATURAHR tabloları bulunamadı.' };
  }

  const faturaColumns = await akinsoftTableColumnSet(pool, 'FATURA');
  const lineColumns = await akinsoftTableColumnSet(pool, 'FATURAHR');
  const hasCariHr = await akinsoftTableExists(pool, 'CARIHR');
  const cariHrColumns = hasCariHr
    ? await akinsoftTableColumnSet(pool, 'CARIHR')
    : new Set();

  const currency = normalizeCurrency(invoice.currency);
  const isTry = currency === 'TRY';
  const exchangeRate = Math.max(Number(invoice.exchange_rate) || 1, 0.000001);
  const invoiceDate =
    toSqlDate(invoice.invoice_date, toSqlDate(new Date())) || new Date();
  const dueDate = toSqlDate(invoice.due_date, invoiceDate);
  const isSales = String(invoice.invoice_type || 'sales') !== 'purchase';

  const linePayloads = [];
  for (const item of invoice.items) {
    const qty = numberOrZero(item.quantity) || 1;
    const unitPrice = numberOrZero(item.unit_price);
    const discount = numberOrZero(item.discount_amount);
    const net =
      numberOrZero(item.net_total) ||
      Math.max(0, qty * unitPrice - discount);
    const taxRate = numberOrZero(item.tax_rate);
    const tax =
      numberOrZero(item.tax_amount) ||
      (taxRate > 0 ? (net * taxRate) / 100 : 0);
    const gross = numberOrZero(item.line_total) || net + tax;
    let productSourceId = null;
    let productCode = textOrNull(item.product_code);
    if (item.product_id) {
      const productMap = await findAkinsoftSourceByLocalId(
        query,
        'product',
        item.product_id,
      );
      if (productMap?.source_id) {
        productSourceId = Number(productMap.source_id);
        productCode = productCode || textOrNull(productMap.source_code);
      } else {
        const productRow = await query(
          `
            select code, akinsoft_source_id
            from public.products
            where id = $1::uuid
            limit 1
          `,
          [item.product_id],
        );
        const prow = productRow.rows?.[0];
        productCode = productCode || textOrNull(prow?.code);
        if (prow?.akinsoft_source_id) {
          productSourceId = Number(prow.akinsoft_source_id);
        }
      }
    }
    if (!Number.isFinite(productSourceId) && productCode) {
      const byCode = await pool
        .request()
        .input('code', sql.NVarChar(64), productCode)
        .query(`
          select top 1 cast(BLKODU as nvarchar(64)) as sourceId, STOKKODU as code
          from dbo.STOK
          where STOKKODU = @code
        `);
      if (byCode.recordset?.[0]?.sourceId) {
        productSourceId = Number(byCode.recordset[0].sourceId);
      }
    }
    // Stok eşleşmezse kalem yine yazılır; ürün adı açıklama/STOK_ADI olarak gider.
    const description =
      textOrNull(item.description) || productCode || 'Fatura kalemi';
    linePayloads.push({
      productSourceId: Number.isFinite(productSourceId) ? productSourceId : null,
      productCode: Number.isFinite(productSourceId) ? productCode : null,
      description,
      asDescriptionOnly: !Number.isFinite(productSourceId),
      quantity: qty,
      unit: textOrNull(item.unit) || 'Adet',
      unitPrice,
      discount,
      net,
      taxRate,
      tax,
      gross,
    });
  }

  const subtotal =
    numberOrZero(invoice.subtotal) ||
    linePayloads.reduce((sum, row) => sum + row.net, 0);
  const discountTotal =
    numberOrZero(invoice.discount_total) ||
    linePayloads.reduce((sum, row) => sum + row.discount, 0);
  const taxTotal =
    numberOrZero(invoice.tax_total) ||
    linePayloads.reduce((sum, row) => sum + row.tax, 0);
  const grandTotal =
    numberOrZero(invoice.grand_total) || subtotal - discountTotal + taxTotal;
  const kpbFactor = isTry ? 1 : exchangeRate;
  const kpbSubtotal = isTry ? subtotal : subtotal * kpbFactor;
  const kpbDiscount = isTry ? discountTotal : discountTotal * kpbFactor;
  const kpbTax = isTry ? taxTotal : taxTotal * kpbFactor;
  const kpbGrand = isTry ? grandTotal : grandTotal * kpbFactor;

  const faturaIdentity = await akinsoftColumnIsIdentity(pool, 'FATURA', 'BLKODU');
  const lineIdentity = await akinsoftColumnIsIdentity(pool, 'FATURAHR', 'BLKODU');
  const transaction = new sql.Transaction(pool);
  await transaction.begin();
  try {
    const txRequest = () => new sql.Request(transaction);
    const insertWithTx = async (tableName, columns, values) => {
      const safeTable = String(tableName || '').replace(/[^A-Za-z0-9_]/g, '');
      const entries = Object.entries(values).filter(
        ([key, value]) => value !== undefined && columns.has(String(key).toUpperCase()),
      );
      const request = txRequest();
      const colSql = [];
      const valSql = [];
      entries.forEach(([key, value], index) => {
        const col = String(key).toUpperCase();
        const param = `p${index}`;
        colSql.push(`[${col}]`);
        valSql.push(`@${param}`);
        bindSqlValue(request, sql, param, value);
      });
      const result = await request.query(`
        insert into dbo.${safeTable} (${colSql.join(', ')})
        output inserted.BLKODU as BLKODU
        values (${valSql.join(', ')})
      `);
      return result.recordset?.[0]?.BLKODU == null
        ? null
        : String(result.recordset[0].BLKODU);
    };

    const header = {};
    if (!faturaIdentity) {
      header.BLKODU = await akinsoftNextBlkoduSafe(pool, 'FATURA');
    }
    setFirstColumn(header, faturaColumns, ['FATURA_NO'], invoiceNumber);
    setFirstColumn(header, faturaColumns, ['TARIHI'], invoiceDate);
    if (dueDate) setFirstColumn(header, faturaColumns, ['VADESI'], dueDate);
    setFirstColumn(header, faturaColumns, ['BLCRKODU'], customerSourceId);
    setFirstColumn(
      header,
      faturaColumns,
      ['CARIKODU'],
      textOrNull(customerMap.source_code),
    );
    setFirstColumn(
      header,
      faturaColumns,
      ['TICARI_UNVANI', 'ADI_SOYADI'],
      textOrNull(invoice.customer_name) || textOrNull(customerMap.source_name),
    );
    setFirstColumn(header, faturaColumns, ['ACIKLAMA'], textOrNull(invoice.notes));
    setFirstColumn(header, faturaColumns, ['SILINDI', 'SILINDI_MI', 'DELETED'], 0);
    setFirstColumn(header, faturaColumns, ['IPTAL', 'FATURA_IPTAL', 'IPTAL_MI'], 0);
    setFirstColumn(header, faturaColumns, ['KAPALI', 'KAPANDI'], 0);
    setFirstColumn(header, faturaColumns, ['FATURA_DURUMU'], 1);
    setFirstColumn(
      header,
      faturaColumns,
      ['ALIS_SATIS', 'ALIS_SATIS_M'],
      isSales ? 1 : 0,
    );
    // ALISFATURA genelde "alış faturası mı?" bayrağıdır; satışta 0 olmalı.
    setFirstColumn(header, faturaColumns, ['ALISFATURA'], isSales ? 0 : 1);
    setFirstColumn(header, faturaColumns, ['KUR', 'DOVIZ_KURU'], exchangeRate);
    setFirstColumn(
      header,
      faturaColumns,
      ['DOVIZ_KULLAN', 'DOVIZLI', 'DVZ_KULLAN'],
      isTry ? 0 : 1,
    );
    setFirstColumn(
      header,
      faturaColumns,
      ['DOVIZ_BIRIMI', 'DOVIZ_ADI', 'DVZ_BIRIMI', 'PARA_BIRIMI', 'DOVIZ'],
      currency,
    );
    setFirstColumn(
      header,
      faturaColumns,
      [
        'KPB_ARA_TOPLAM',
        'TOPLAM_ARA',
        'TOPLAM_ARA_KPB',
        'KPB_ARA_TUTAR',
        'ARA_TOPLAM',
      ],
      kpbSubtotal,
    );
    setFirstColumn(
      header,
      faturaColumns,
      ['KPB_IND_TOPLAM', 'KPB_ISKONTO_TOPLAM', 'IND_TOPLAM', 'ISKONTO_TOPLAM'],
      kpbDiscount,
    );
    setFirstColumn(
      header,
      faturaColumns,
      ['KPB_KDV_TOPLAM', 'TOPLAM_KDV', 'TOPLAM_KDV_KPB', 'KDV_TOPLAM'],
      kpbTax,
    );
    setFirstColumn(
      header,
      faturaColumns,
      [
        'KPB_GENEL_TOPLAM',
        'TOPLAM_GENEL',
        'TOPLAM_GENEL_KPB',
        'GENEL_TOPLAM',
        'FATURA_TOPLAMI',
        'KPB_KDV_DAHIL_TOPLAM',
      ],
      kpbGrand,
    );
    if (!isTry) {
      setFirstColumn(
        header,
        faturaColumns,
        ['DVZ_ARA_TOPLAM', 'TOPLAM_ARA_DVZ', 'DOVIZ_ARA_TOPLAM'],
        subtotal,
      );
      setFirstColumn(
        header,
        faturaColumns,
        ['DVZ_IND_TOPLAM', 'DVZ_ISKONTO_TOPLAM', 'DOVIZ_ISKONTO_TOPLAM'],
        discountTotal,
      );
      setFirstColumn(
        header,
        faturaColumns,
        ['DVZ_KDV_TOPLAM', 'TOPLAM_KDV_DVZ', 'DOVIZ_KDV_TOPLAM'],
        taxTotal,
      );
      setFirstColumn(
        header,
        faturaColumns,
        ['DVZ_GENEL_TOPLAM', 'TOPLAM_GENEL_DVZ', 'DOVIZ_GENEL_TOPLAM'],
        grandTotal,
      );
    }

    const faturaSourceId = await insertWithTx('FATURA', faturaColumns, header);
    if (!faturaSourceId) {
      throw new Error('FATURA kaydı oluşturulamadı (BLKODU alınamadı).');
    }
    const faturaBlkodu = Number(faturaSourceId);

    let lineBlkodu = lineIdentity
      ? null
      : await akinsoftNextBlkoduSafe(pool, 'FATURAHR');
    for (const line of linePayloads) {
      const row = {};
      if (!lineIdentity) {
        row.BLKODU = lineBlkodu;
        lineBlkodu += 1;
      }
      setFirstColumn(row, lineColumns, ['BLFTKODU'], faturaBlkodu);
      if (line.productSourceId != null) {
        setFirstColumn(row, lineColumns, ['BLSTKODU'], line.productSourceId);
        setFirstColumn(row, lineColumns, ['STOKKODU'], line.productCode);
      }
      // Stok yoksa yalnızca ad/açıklama alanına yazılır.
      setFirstColumn(row, lineColumns, ['STOK_ADI', 'ACIKLAMA', 'ACIKLAMA1'], line.description);
      setFirstColumn(row, lineColumns, ['MIKTARI'], line.quantity);
      setFirstColumn(row, lineColumns, ['BIRIMI'], line.unit);
      setFirstColumn(row, lineColumns, ['KDV_ORANI'], line.taxRate);
      const lineKpbNet = isTry ? line.net : line.net * kpbFactor;
      const lineKpbTax = isTry ? line.tax : line.tax * kpbFactor;
      const lineKpbGross = isTry ? line.gross : line.gross * kpbFactor;
      const lineKpbPrice = isTry ? line.unitPrice : line.unitPrice * kpbFactor;
      setFirstColumn(
        row,
        lineColumns,
        ['KPB_KDV_HARICFY', 'KPB_FIYATI', 'KPB_BIRIM_FIYAT', 'KPB_BF', 'FIYATI'],
        lineKpbPrice,
      );
      setFirstColumn(
        row,
        lineColumns,
        ['KPB_ARA_TUTAR', 'KPB_TOPLAM_TUTAR', 'KPB_TUTAR', 'KPB_KDV_HARIC_TUTAR'],
        lineKpbNet,
      );
      setFirstColumn(
        row,
        lineColumns,
        ['KPB_KDV_TUTARI', 'KPB_KDV', 'KDV_TUTARI'],
        lineKpbTax,
      );
      setFirstColumn(
        row,
        lineColumns,
        ['KPB_KDVLI_TUTAR', 'KPB_KDV_DAHIL_TUTAR'],
        lineKpbGross,
      );
      if (!isTry) {
        setFirstColumn(
          row,
          lineColumns,
          ['DVZ_KDV_HARICFY', 'DVZ_FIYATI', 'DVZ_BIRIM_FIYAT', 'DVZ_BF'],
          line.unitPrice,
        );
        setFirstColumn(
          row,
          lineColumns,
          ['DVZ_ARA_TUTAR', 'DVZ_TOPLAM_TUTAR', 'DVZ_TUTAR'],
          line.net,
        );
        setFirstColumn(row, lineColumns, ['DVZ_KDV_TUTARI', 'DVZ_KDV'], line.tax);
        setFirstColumn(
          row,
          lineColumns,
          ['DVZ_KDVLI_TUTAR', 'DVZ_KDV_DAHIL_TUTAR'],
          line.gross,
        );
      }
      await insertWithTx('FATURAHR', lineColumns, row);
    }

    let cariHrWritten = false;
    if (hasCariHr && cariHrColumns.size) {
      const cariHrIdentity = await akinsoftColumnIsIdentity(
        pool,
        'CARIHR',
        'BLKODU',
      );
      const cariRow = {};
      if (!cariHrIdentity) {
        cariRow.BLKODU = await akinsoftNextBlkoduSafe(pool, 'CARIHR');
      }
      setFirstColumn(cariRow, cariHrColumns, ['BLCRKODU'], customerSourceId);
      setFirstColumn(cariRow, cariHrColumns, ['EVRAK_NO'], invoiceNumber);
      setFirstColumn(cariRow, cariHrColumns, ['TARIHI'], invoiceDate);
      if (dueDate) setFirstColumn(cariRow, cariHrColumns, ['VADESI'], dueDate);
      setFirstColumn(
        cariRow,
        cariHrColumns,
        ['ACIKLAMA'],
        textOrNull(invoice.notes) || `CRM fatura ${invoiceNumber}`,
      );
      // Satışta cari borç (BTUT), alışta alacak (ATUT).
      if (isSales) {
        setFirstColumn(cariRow, cariHrColumns, ['KPB_BTUT', 'BTUT'], kpbGrand);
        setFirstColumn(cariRow, cariHrColumns, ['KPB_ATUT', 'ATUT'], 0);
        if (!isTry) {
          setFirstColumn(cariRow, cariHrColumns, ['DVZ_BTUT'], grandTotal);
          setFirstColumn(cariRow, cariHrColumns, ['DVZ_ATUT'], 0);
        }
      } else {
        setFirstColumn(cariRow, cariHrColumns, ['KPB_ATUT', 'ATUT'], kpbGrand);
        setFirstColumn(cariRow, cariHrColumns, ['KPB_BTUT', 'BTUT'], 0);
        if (!isTry) {
          setFirstColumn(cariRow, cariHrColumns, ['DVZ_ATUT'], grandTotal);
          setFirstColumn(cariRow, cariHrColumns, ['DVZ_BTUT'], 0);
        }
      }
      setFirstColumn(cariRow, cariHrColumns, ['KUR', 'DOVIZ_KURU'], exchangeRate);
      await insertWithTx('CARIHR', cariHrColumns, cariRow);
      cariHrWritten = true;
    }

    await transaction.commit();

    await upsertAkinsoftSyncMap(query, {
      sourceType: 'invoice',
      sourceId: faturaSourceId,
      sourceCode: invoiceNumber,
      sourceName: textOrNull(invoice.customer_name),
      localTable: 'invoices',
      localId: invoiceId,
    });
    await query(
      `
        update public.invoices
        set erp_invoice_number = coalesce(nullif(trim(erp_invoice_number), ''), $2),
            erp_invoice_number_synced_at = now(),
            updated_at = now()
        where id = $1::uuid
      `,
      [invoiceId, invoiceNumber],
    );

    return {
      ok: true,
      sourceId: faturaSourceId,
      invoiceNumber,
      lineCount: linePayloads.length,
      descriptionOnlyLines: linePayloads.filter((line) => line.asDescriptionOnly)
        .length,
      customerCreated: customerRef.created === true,
      customerMatchedBy: customerRef.matchedBy || null,
      cariHrWritten,
    };
  } catch (error) {
    try {
      await transaction.rollback();
    } catch (_) {
      // ignore rollback errors
    }
    return { ok: false, reason: error?.message || String(error) };
  }
}

async function handleAkinsoftPushInvoices(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const invoiceIds = Array.isArray(body.invoiceIds)
    ? body.invoiceIds.map((id) => String(id || '').trim()).filter(Boolean)
    : [];
  if (!invoiceIds.length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'invoiceIds gerekli.' }),
    );
  }

  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);

  const headerResult = await query(
    `
      select
        i.id,
        i.invoice_number,
        i.invoice_type,
        i.customer_id,
        i.invoice_date,
        i.due_date,
        i.currency,
        i.exchange_rate,
        i.subtotal,
        i.tax_total,
        i.discount_total,
        i.grand_total,
        i.status,
        i.notes,
        i.is_active,
        i.e_invoice_number,
        i.e_invoice_status,
        c.name as customer_name,
        c.vkn as customer_vkn,
        c.tax_office as customer_tax_office,
        coalesce(c.phone_1, c.phone_2) as customer_phone,
        c.email as customer_email,
        c.address as customer_address,
        c.city as customer_city,
        c.country as customer_country,
        m.source_id as akinsoft_source_id
      from public.invoices i
      left join public.customers c on c.id = i.customer_id
      left join public.akinsoft_sync_map m
        on m.source_system = 'akinsoft'
       and m.source_type = 'invoice'
       and m.local_id = i.id
      where i.id = any($1::uuid[])
    `,
    [invoiceIds],
  );
  const itemsResult = await query(
    `
      select
        ii.invoice_id,
        ii.product_id,
        ii.description,
        ii.quantity,
        ii.unit,
        ii.unit_price,
        ii.tax_rate,
        ii.tax_amount,
        ii.discount_amount,
        ii.line_total,
        p.code as product_code
      from public.invoice_items ii
      left join public.products p on p.id = ii.product_id
      where ii.invoice_id = any($1::uuid[])
      order by ii.sort_order asc
    `,
    [invoiceIds],
  );
  const itemsByInvoice = new Map();
  for (const row of itemsResult.rows) {
    const key = String(row.invoice_id);
    const list = itemsByInvoice.get(key) || [];
    list.push(row);
    itemsByInvoice.set(key, list);
  }

  const sql = require('mssql');
  const { config } = buildAkinsoftSqlConfig(body.settings || body);
  config.requestTimeout = Math.max(Number(config.requestTimeout || 0), 180000);
  const pool = await connectAkinsoftPool(config);
  const items = [];
  const byId = new Map(headerResult.rows.map((row) => [String(row.id), row]));
  try {
    for (const invoiceId of invoiceIds) {
      const row = byId.get(String(invoiceId));
      if (!row) {
        items.push({ invoiceId, ok: false, reason: 'Fatura CRM’de bulunamadı.' });
        continue;
      }
      if (row.is_active === false) {
        items.push({
          invoiceId,
          invoiceNumber: row.invoice_number,
          ok: false,
          reason: 'Pasif fatura Akınsoft’a gönderilemez.',
        });
        continue;
      }
      if (String(row.status || '') === 'cancelled') {
        items.push({
          invoiceId,
          invoiceNumber: row.invoice_number,
          ok: false,
          reason: 'İptal fatura Akınsoft’a gönderilemez.',
        });
        continue;
      }
      try {
        const write = await writeAkinsoftInvoiceCreate(pool, sql, query, {
          ...row,
          items: itemsByInvoice.get(String(invoiceId)) || [],
        });
        items.push({
          invoiceId: row.id,
          invoiceNumber: row.invoice_number,
          ok: write.ok === true,
          skipped: write.skipped === true,
          sourceId: write.sourceId || row.akinsoft_source_id || null,
          lineCount: write.lineCount || 0,
          descriptionOnlyLines: write.descriptionOnlyLines || 0,
          customerCreated: write.customerCreated === true,
          customerMatchedBy: write.customerMatchedBy || null,
          cariHrWritten: write.cariHrWritten === true,
          reason: write.reason || null,
        });
      } catch (error) {
        items.push({
          invoiceId: row.id,
          invoiceNumber: row.invoice_number,
          ok: false,
          reason: error?.message || String(error),
        });
      }
    }
  } finally {
    await pool.close();
  }

  const success = items.filter((item) => item.ok).length;
  const failed = items.length - success;
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({
      ok: failed === 0,
      success,
      failed,
      items,
    }),
  );
}

async function handleAkinsoftPushInvoiceNumbers(req, res) {
  if (req.method !== 'POST') {
    return send(
      res,
      405,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'POST gerekli.' }),
    );
  }
  const body = await readJson(req);
  const invoiceIds = Array.isArray(body.invoiceIds)
    ? body.invoiceIds.map((id) => String(id || '').trim()).filter(Boolean)
    : [];
  if (!invoiceIds.length) {
    return send(
      res,
      400,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'invoiceIds gerekli.' }),
    );
  }

  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  await query(`
    alter table public.invoices
      add column if not exists erp_invoice_number text,
      add column if not exists erp_invoice_number_synced_at timestamptz
  `);

  const result = await query(
    `
      select
        i.id,
        i.invoice_number,
        i.erp_invoice_number,
        i.e_invoice_number,
        i.e_invoice_status,
        i.e_invoice_environment,
        i.erp_invoice_number_synced_at,
        m.source_id as akinsoft_source_id,
        m.source_code as akinsoft_source_code
      from public.invoices i
      left join public.akinsoft_sync_map m
        on m.source_system = 'akinsoft'
       and m.source_type = 'invoice'
       and m.local_id = i.id
      where i.id = any($1::uuid[])
    `,
    [invoiceIds],
  );

  const sql = require('mssql');
  const { config } = buildAkinsoftSqlConfig(body.settings || body);
  // Toplu güncellemede satır başına birkaç sorgu olduğu için süreyi uzat.
  config.requestTimeout = Math.max(Number(config.requestTimeout || 0), 180000);
  const pool = await connectAkinsoftPool(config);
  const items = [];
  const byId = new Map(result.rows.map((row) => [String(row.id), row]));
  try {
    for (const invoiceId of invoiceIds) {
      const row = byId.get(String(invoiceId));
      if (!row) {
        items.push({
          invoiceId,
          ok: false,
          reason: 'Fatura CRM’de bulunamadı.',
        });
        continue;
      }

      const officialEInvoiceNumber = textOrNull(row.e_invoice_number);
      const eInvoiceNumber = localEInvoiceNumber(officialEInvoiceNumber);
      const invoiceNumber = textOrNull(row.invoice_number);
      const erpNumber =
        textOrNull(row.erp_invoice_number) ||
        textOrNull(row.akinsoft_source_code) ||
        (invoiceNumber &&
        localEInvoiceNumber(invoiceNumber) !== eInvoiceNumber
          ? invoiceNumber
          : null);
      const base = {
        invoiceId: row.id,
        invoiceNumber,
        erpInvoiceNumber: erpNumber,
        eInvoiceNumber,
        officialEInvoiceNumber,
        environment: row.e_invoice_environment,
        status: row.e_invoice_status,
      };

      try {
        if (row.e_invoice_status !== 'sent' || !officialEInvoiceNumber) {
          items.push({
            ...base,
            ok: false,
            reason: 'Yalnızca gönderilmiş e-faturalar güncellenir.',
          });
          continue;
        }
        if (
          textOrNull(row.e_invoice_environment) &&
          textOrNull(row.e_invoice_environment) !== 'production'
        ) {
          items.push({
            ...base,
            ok: false,
            reason: 'Yalnızca canlı ortamda gönderilmiş faturalar Akınsoft’a yazılır.',
          });
          continue;
        }

        // Önce Akınsoft’taki numarayı güncellemeyi dene. CRM erp alanı
        // yalnızca Akınsoft yazımı başarılı olursa set edilir; aksi halde
        // fatura “bağlı” sanılıp gönder ikonu kaybolur.
        let renamed = false;
        let write = await writeAkinsoftInvoiceNumber(pool, sql, {
          oldNumber:
            erpNumber ||
            (invoiceNumber && invoiceNumber !== eInvoiceNumber
              ? invoiceNumber
              : null),
          newNumber: eInvoiceNumber,
          sourceId: row.akinsoft_source_id,
        });

        // Akınsoft’ta yoksa (ERP’den gelmemiş CRM faturası) yeni kayıt oluştur.
        if (
          !write.ok &&
          !row.akinsoft_source_id &&
          /bulunamadı|eşlemesi/i.test(String(write.reason || ''))
        ) {
          const full = await query(
            `
              select
                i.id,
                i.invoice_number,
                i.invoice_type,
                i.customer_id,
                i.invoice_date,
                i.due_date,
                i.currency,
                i.exchange_rate,
                i.subtotal,
                i.tax_total,
                i.discount_total,
                i.grand_total,
                i.status,
                i.notes,
                i.is_active,
                i.e_invoice_number,
                i.e_invoice_status,
                c.name as customer_name,
                c.vkn as customer_vkn,
                c.tax_office as customer_tax_office,
                coalesce(c.phone_1, c.phone_2) as customer_phone,
                c.email as customer_email,
                c.address as customer_address,
                c.city as customer_city,
                c.country as customer_country
              from public.invoices i
              left join public.customers c on c.id = i.customer_id
              where i.id = $1::uuid
              limit 1
            `,
            [row.id],
          );
          const header = full.rows?.[0];
          const lineRows = (
            await query(
              `
                select
                  ii.product_id,
                  ii.description,
                  ii.quantity,
                  ii.unit,
                  ii.unit_price,
                  ii.tax_rate,
                  ii.tax_amount,
                  ii.discount_amount,
                  ii.line_total,
                  p.code as product_code
                from public.invoice_items ii
                left join public.products p on p.id = ii.product_id
                where ii.invoice_id = $1::uuid
                order by ii.sort_order asc
              `,
              [row.id],
            )
          ).rows;
          if (header && lineRows.length) {
            const created = await writeAkinsoftInvoiceCreate(pool, sql, query, {
              ...header,
              // Maliye numarasıyla yazılsın.
              invoice_number: eInvoiceNumber,
              e_invoice_number: officialEInvoiceNumber,
              e_invoice_status: 'sent',
              items: lineRows,
            });
            if (created.ok) {
              write = {
                ok: true,
                skipped: created.skipped === true,
                reason: created.skipped
                  ? created.reason
                  : 'Akınsoft’ta fatura yoktu; Maliye numarasıyla oluşturuldu.',
                oldNumber: null,
                sourceId: created.sourceId,
              };
              row.akinsoft_source_id = created.sourceId;
            } else {
              write = {
                ok: false,
                reason:
                  created.reason ||
                  'Akınsoft’ta fatura bulunamadı ve oluşturma başarısız.',
              };
            }
          }
        }

        if (write.ok) {
          if (invoiceNumber !== eInvoiceNumber) {
            const conflict = await query(
              `
                select id
                from public.invoices
                where invoice_number = $1
                  and id is distinct from $2
                limit 1
              `,
              [eInvoiceNumber, row.id],
            );
            if (!conflict.rows.length) {
              await query(
                `
                  update public.invoices
                  set invoice_number = $2,
                      updated_at = now()
                  where id = $1
                `,
                [row.id, eInvoiceNumber],
              );
              renamed = true;
            }
          }
          const preserveErp =
            write.oldNumber ||
            erpNumber ||
            (invoiceNumber !== eInvoiceNumber ? invoiceNumber : null);
          if (preserveErp) {
            await query(
              `
                update public.invoices
                set erp_invoice_number = coalesce(
                      nullif(trim(erp_invoice_number), ''),
                      $2
                    ),
                    erp_invoice_number_synced_at = now(),
                    updated_at = now()
                where id = $1
              `,
              [row.id, preserveErp],
            );
          } else {
            await query(
              `
                update public.invoices
                set erp_invoice_number_synced_at = now(),
                    updated_at = now()
                where id = $1
              `,
              [row.id],
            );
          }
          if (row.akinsoft_source_id || write.sourceId) {
            await upsertAkinsoftSyncMap(query, {
              sourceType: 'invoice',
              sourceId: row.akinsoft_source_id || write.sourceId,
              sourceCode: eInvoiceNumber,
              sourceName: null,
              localTable: 'invoices',
              localId: row.id,
            });
          }
        }

        items.push({
          ...base,
          invoiceNumber: write.ok ? eInvoiceNumber : invoiceNumber,
          erpInvoiceNumber: write.oldNumber || erpNumber,
          renamed,
          ok: write.ok === true,
          skipped: write.skipped === true,
          created: /oluşturuldu/i.test(String(write.reason || '')),
          reason: write.reason || null,
          sourceId: row.akinsoft_source_id || write.sourceId || null,
        });
      } catch (error) {
        // Bir faturadaki hata tüm toplu işlemi düşürmesin.
        items.push({
          ...base,
          ok: false,
          reason: error?.message || String(error),
        });
      }
    }
  } finally {
    await pool.close();
  }

  const success = items.filter((item) => item.ok).length;
  const failed = items.length - success;
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify({
      ok: failed === 0,
      success,
      failed,
      items,
    }),
  );
}

async function handleAkinsoftRequest(req, res) {
  setCors(res);
  if (req.method === 'OPTIONS') return send(res, 204, {}, null);
  const url = new URL(req.url || '/', `http://${req.headers.host || 'localhost'}`);
  let pathname = url.pathname || '/';
  if (!pathname.startsWith('/api/akinsoft/')) {
    pathname = `/api/akinsoft/${pathname.replace(/^\/+/, '')}`;
  }
  const routes = {
    '/api/akinsoft/test-connection': handleAkinsoftTestConnection,
    '/api/akinsoft/save-local-settings': handleAkinsoftSaveLocalSettings,
    '/api/akinsoft/analyze': handleAkinsoftAnalyze,
    '/api/akinsoft/pull': handleAkinsoftPull,
    '/api/akinsoft/import': handleAkinsoftImport,
    '/api/akinsoft/import-job': handleAkinsoftImportJob,
    '/api/akinsoft/local-customers': handleAkinsoftLocalCustomers,
    '/api/akinsoft/map-customer': handleAkinsoftMapCustomer,
    '/api/akinsoft/bulk-map-customers-job': handleAkinsoftBulkMapCustomersJob,
    '/api/akinsoft/bulk-map-customers': handleAkinsoftBulkMapCustomers,
    '/api/akinsoft/duplicate-customers': handleAkinsoftDuplicateCustomers,
    '/api/akinsoft/push-invoice-numbers': handleAkinsoftPushInvoiceNumbers,
    '/api/akinsoft/push-invoices': handleAkinsoftPushInvoices,
  };
  const handler = routes[pathname];
  if (!handler) {
    return send(
      res,
      404,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({ ok: false, error: 'Akınsoft endpoint bulunamadı.' }),
    );
  }
  try {
    return await handler(req, res);
  } catch (e) {
    return send(
      res,
      e.statusCode || 500,
      { 'Content-Type': 'application/json; charset=utf-8' },
      JSON.stringify({
        ok: false,
        error: e instanceof Error ? e.message : String(e),
      }),
    );
  }
}

module.exports = {
  handleAkinsoftRequest,
};

function safeJoin(root, requestPath) {
  const decoded = decodeURIComponent(requestPath);
  const normalized = decoded.replace(/^\/+/, '');
  const resolved = path.resolve(root, normalized);
  if (!resolved.startsWith(root)) return null;
  return resolved;
}

if (require.main === module) {
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

      if (pathname === '/api/akinsoft/test-connection') {
        try {
          return await handleAkinsoftTestConnection(req, res);
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

      if (pathname === '/api/akinsoft/save-local-settings') {
        try {
          return await handleAkinsoftSaveLocalSettings(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/analyze') {
        try {
          return await handleAkinsoftAnalyze(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/pull') {
        try {
          return await handleAkinsoftPull(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/import') {
        try {
          return await handleAkinsoftImport(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/import-job') {
        try {
          return await handleAkinsoftImportJob(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/local-customers') {
        try {
          return await handleAkinsoftLocalCustomers(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/map-customer') {
        try {
          return await handleAkinsoftMapCustomer(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/bulk-map-customers-job') {
        try {
          return await handleAkinsoftBulkMapCustomersJob(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/bulk-map-customers') {
        try {
          return await handleAkinsoftBulkMapCustomers(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
            { 'Content-Type': 'application/json; charset=utf-8' },
            JSON.stringify({
              ok: false,
              error: e instanceof Error ? e.message : String(e),
            }),
          );
        }
      }

      if (pathname === '/api/akinsoft/duplicate-customers') {
        try {
          return await handleAkinsoftDuplicateCustomers(req, res);
        } catch (e) {
          return send(
            res,
            e.statusCode || 500,
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
}
