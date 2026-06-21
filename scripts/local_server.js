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
      requestTimeout: 20000,
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
      'KAPANDI',
      'ODENDI',
      'ODEME_DURUMU',
      'DURUMU',
      'STATU',
      'STATUS',
    ]),
  );
  if (closedFlag === true) {
    return { paidAmount: grandTotal, status: 'paid' };
  }
  if (remainingRaw != null) {
    if (remainingAmount <= 0 && grandTotal > 0) {
      return { paidAmount: grandTotal, status: 'paid' };
    }
    if (remainingAmount > 0 && grandTotal > 0) {
      const paid = Math.max(0, grandTotal - remainingAmount);
      return { paidAmount: paid, status: paid > 0 ? 'partial' : 'open' };
    }
  }
  if (paidRaw != null && paidAmount > 0 && paidAmount < grandTotal) {
    return { paidAmount, status: 'partial' };
  }
  return { paidAmount: 0, status: 'open' };
}

function resolveAkinsoftCariPayment(movements, currency, grandTotal) {
  if (!Array.isArray(movements) || movements.length === 0 || grandTotal <= 0) {
    return null;
  }
  const debitKey = currency === 'TRY' ? 'KPB_BTUT' : 'DVZ_BTUT';
  const creditKey = currency === 'TRY' ? 'KPB_ATUT' : 'DVZ_ATUT';
  const debit = movements.reduce((sum, row) => sum + numberOrZero(row[debitKey]), 0);
  const credit = movements.reduce((sum, row) => sum + numberOrZero(row[creditKey]), 0);
  if (debit <= 0 && credit <= 0) return null;
  const paidAmount = Math.min(Math.max(0, credit), grandTotal);
  const remaining = Math.max(0, debit - credit);
  if (remaining <= 0.01 && credit > 0) {
    return { paidAmount: grandTotal, status: 'paid' };
  }
  if (paidAmount > 0) {
    return { paidAmount, status: 'partial' };
  }
  return { paidAmount: 0, status: 'open' };
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

async function ensureAkinsoftSyncMap(query) {
  await query(`
    alter table public.products
      add column if not exists akinsoft_group text,
      add column if not exists akinsoft_sub_group text,
      add column if not exists akinsoft_source_id text
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
    }

    let invoices = [];
    let rawInvoiceCount = 0;
    if (hasFatura) {
      const faturaColumns = await akinsoftTableColumnSet(pool, 'FATURA');
      const invoiceWhere = buildAkinsoftInvoiceWhere(faturaColumns, hasFaturaHr);
      const rawInvoiceCountResult = await pool.request().query(`
        select count_big(1) as total
        from dbo.FATURA
        where coalesce(FATURA_NO, '') not like N'MSF%'
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
      const headers = rawHeaders.filter((row) => {
        const invoiceNumber = textOrNull(row.FATURA_NO) || '';
        return !invoiceNumber.toUpperCase().startsWith('MSF');
      });

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
        const request = pool.request();
        invoiceNumbers.forEach((no, index) => request.input(`no${index}`, sql.NVarChar, no));
        const paramList = invoiceNumbers.map((_, index) => `@no${index}`).join(',');
        cariHrRows.push(
          ...(
            await request.query(`
              select *
              from dbo.CARIHR
              where EVRAK_NO in (${paramList})
                and coalesce(SILINDI, 0) = 0
            `)
          ).recordset,
        );
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
        const request = pool.request();
        productIds.forEach((id, index) => request.input(`pid${index}`, sql.Int, id));
        const paramList = productIds.map((_, index) => `@pid${index}`).join(',');
        products = (
          await request.query(`
            select
              BLKODU, STOKKODU, STOK_ADI, BIRIMI, KDV_ORANI, OZEL_KODU1,
              OZEL_KODU2, OZEL_KODU3, ARA_GRUBU, ALT_GRUBU, KAYIT_TARIHI,
              ACIKLAMA1, ACIKLAMA2
            from dbo.STOK
            where BLKODU in (${paramList})
          `)
        ).recordset.map(mapProductRow);
      }

      const itemsByInvoice = new Map();
      for (const row of itemRows) {
        const key = String(row.BLFTKODU);
        const list = itemsByInvoice.get(key) || [];
        const account = akinsoftAccountText(row);
        const currency = resolveAkinsoftItemCurrency(row);
        const priceFields =
          currency === 'TRY'
            ? [
                'KPB_KDV_HARICFY',
                'KPB_FIYATI',
                'KPB_BIRIM_FIYAT',
                'KPB_BF',
                'FIYATI',
                'BIRIM_FIYAT',
                'DVZ_KDV_HARICFY',
                'DVZ_FIYATI',
                'DVZ_BIRIM_FIYAT',
              ]
            : [
                'DVZ_KDV_HARICFY',
                'DVZ_FIYATI',
                'DVZ_BIRIM_FIYAT',
                'DVZ_BF',
                'DOVIZ_FIYATI',
                'KPB_KDV_HARICFY',
                'KPB_FIYATI',
                'KPB_BIRIM_FIYAT',
              ];
        const amountFields =
          currency === 'TRY'
            ? [
                'KPB_ARA_TUTAR',
                'KPB_TOPLAM_TUTAR',
                'KPB_TUTAR',
                'KPB_KDV_HARIC_TUTAR',
                'KPB_KDV_HARIC_TPL',
                'ARA_TUTAR',
                'TUTAR',
                'TOPLAM_TUTAR',
                'DVZ_ARA_TUTAR',
                'DVZ_TOPLAM_TUTAR',
                'DVZ_TUTAR',
              ]
            : [
                'DVZ_ARA_TUTAR',
                'DVZ_TOPLAM_TUTAR',
                'DVZ_TUTAR',
                'DOVIZ_TUTARI',
                'DOVIZ_TOPLAM',
                'KPB_ARA_TUTAR',
                'KPB_TOPLAM_TUTAR',
                'KPB_TUTAR',
              ];
        const unitPrice = numberOrZero(pick(row, priceFields));
        const lineNet =
          numberOrZero(pick(row, amountFields)) ||
          numberOrZero(row.MIKTARI) * unitPrice;
        const discount = resolveAkinsoftDiscount(row, currency, lineNet);
        const taxRate = numberOrZero(row.KDV_ORANI);
        const explicitTaxAmount = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_KDV_TUTARI',
                  'KPB_KDV',
                  'KDV_TUTARI',
                  'KDV',
                  'DVZ_KDV_TUTARI',
                ]
              : [
                  'DVZ_KDV_TUTARI',
                  'DVZ_KDV',
                  'DOVIZ_KDV_TUTARI',
                  'KPB_KDV_TUTARI',
                  'KDV_TUTARI',
                ],
          ),
        );
        const taxIncludedTotal = numberOrZero(
          pick(
            row,
            currency === 'TRY'
              ? [
                  'KPB_KDVLI_TUTAR',
                  'KPB_KDV_DAHIL_TUTAR',
                  'KPB_TOPLAM_TUTAR',
                ]
              : [
                  'DVZ_KDVLI_TUTAR',
                  'DVZ_KDV_DAHIL_TUTAR',
                  'DVZ_TOPLAM_TUTAR',
                ],
          ),
        );
        const taxAmount =
          explicitTaxAmount ||
          (taxRate > 0 && taxIncludedTotal > lineNet
            ? taxIncludedTotal - lineNet
            : 0);
        list.push({
          sourceId: String(row.BLKODU),
          productSourceId: row.BLSTKODU == null ? null : String(row.BLSTKODU),
          code: textOrNull(row.STOKKODU),
          description: textOrNull(row.STOK_ADI) || 'Fatura kalemi',
          quantity: numberOrZero(row.MIKTARI) || 1,
          unit: textOrNull(row.BIRIMI) || 'Adet',
          unitPrice,
          discountAmount: discount,
          netTotal: lineNet,
          taxRate,
          taxAmount,
          currency,
          account,
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
          numberOrZero(taxes[0]?.taxRate) || numberOrZero(row.KDV_ORANI) || 20;
        const items = (itemsByInvoice.get(key) || []).map((item) => ({
          ...item,
          taxRate: numberOrZero(item.taxRate) || primaryTaxRate,
          taxAmount: numberOrZero(item.taxAmount),
        }));
        const itemAccounts = [
          ...new Set(items.map((item) => textOrNull(item.account)).filter(Boolean)),
        ];
        const subtotal = items.reduce((sum, item) => sum + item.netTotal, 0);
        const discountTotal = items.reduce((sum, item) => sum + item.discountAmount, 0);
        const headerCurrencyValue = pick(row, [
              'DOVIZ_BIRIMI',
              'DOVIZ_KULLAN',
              'DOVIZ_ADI',
              'DVZ_BIRIMI',
              'PARA_BIRIMI',
              'DOVIZ',
            ]);
        const itemCurrencies = items
          .map((item) => textOrNull(item.currency))
          .filter(Boolean);
        const foreignItemCurrency = itemCurrencies.find((item) => item !== 'TRY');
        const currency = foreignItemCurrency || (
          itemCurrencies.length ? 'TRY' : normalizeCurrency(headerCurrencyValue)
        );
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
        const payment =
          resolveAkinsoftCariPayment(
            cariHrByInvoiceNo.get(invoiceNumber) || [],
            currency,
            finalGrandTotal,
          ) || resolveAkinsoftInvoicePayment(row, currency, finalGrandTotal);
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
            const sameStatus = textOrNull(row.status) === textOrNull(invoice.status);
            const sameCurrency =
              normalizeCurrency(row.currency) === normalizeCurrency(invoice.currency);
            const sameTotal =
              Math.abs(numberOrZero(row.grand_total) - numberOrZero(invoice.grandTotal)) <
              0.01;
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
          invoices: invoices.length,
          rawInvoices: rawInvoiceCount || invoices.length,
          filteredInvoices: Math.max(0, (rawInvoiceCount || invoices.length) - invoices.length),
          invoiceItems: invoices.reduce((sum, item) => sum + item.items.length, 0),
          unmatchedCustomers: invoices.filter(
            (item) => item.customerMatch?.matched !== true,
          ).length,
        },
        customers,
        products,
        invoices,
      }),
    );
  } finally {
    await pool.close();
  }
}

async function importAkinsoftDataset(data, onProgress) {
  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  await ensureAkinsoftSyncMap(query);
  const invoices = Array.isArray(data.invoices) ? data.invoices : [];
  const reportProgress = (current, extra = {}) => {
    if (!onProgress) return;
    onProgress({
      stage: 'invoices',
      current,
      total: invoices.length,
      ...extra,
    });
  };
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
  const products = invoices.length
    ? allProducts.filter(
        (product) =>
          selectedProductSources.has(textOrNull(product.sourceId)) ||
          selectedProductCodes.has(textOrNull(product.code)),
      )
    : allProducts;
  const customerIdBySource = new Map();
  const productIdBySource = new Map();
  const productIdByCode = new Map();

  let customersImported = 0;
  let productsImported = 0;
  let invoicesImported = 0;
  let invoiceItemsImported = 0;
  let customersMatchedBySource = 0;
  let customersMatchedByTax = 0;
  let customersMatchedByCode = 0;
  let customersCreated = 0;
  let invoicesSkippedMissingCustomerMatch = 0;
  const skippedInvoices = [];

  for (const customer of customers) {
    const name = textOrNull(customer.name);
    if (!name) continue;
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
      continue;
    }
    if (!id) continue;
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
  }

  for (const product of products) {
    const name = textOrNull(product.name);
    if (!name) continue;
    const code = textOrNull(product.code);
    let id = null;
    if (code) {
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
          returning id
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
          textOrNull(product.sourceId),
        ],
      );
      id = result.rows[0]?.id;
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
          textOrNull(product.sourceId),
        ],
      );
      id = result.rows[0]?.id;
    }
    if (!id) continue;
    productsImported += 1;
    if (product.sourceId != null) productIdBySource.set(String(product.sourceId), id);
    if (code) productIdByCode.set(code, id);
    await upsertAkinsoftSyncMap(query, {
      sourceType: 'product',
      sourceId: product.sourceId,
      sourceCode: product.code,
      sourceName: name,
      localTable: 'products',
      localId: id,
    });
  }

  for (let invoiceIndex = 0; invoiceIndex < invoices.length; invoiceIndex += 1) {
    const invoice = invoices[invoiceIndex];
    const invoiceNumber = textOrNull(invoice.invoiceNumber);
    if (!invoiceNumber) {
      reportProgress(invoiceIndex + 1, { invoiceNumber: null });
      continue;
    }
    const invoiceTaxNumber = taxNumberOrNull(invoice.taxNumber);
    let customerId = null;
    if (invoiceTaxNumber) {
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
    const result = await query(
      `
        insert into public.invoices (
          invoice_number, invoice_type, customer_id, invoice_date, due_date,
          currency, exchange_rate, subtotal, tax_total, discount_total,
          grand_total, paid_amount, status, notes, is_active
        )
        values ($1, 'sales', $2, $3, $4, $5, 1, $6, $7, $8, $9, $10, $11, $12, true)
        on conflict (invoice_number) do update set
          customer_id = excluded.customer_id,
          invoice_date = excluded.invoice_date,
          due_date = excluded.due_date,
          currency = excluded.currency,
          subtotal = excluded.subtotal,
          tax_total = excluded.tax_total,
          discount_total = excluded.discount_total,
          grand_total = excluded.grand_total,
          paid_amount = excluded.paid_amount,
          status = excluded.status,
          notes = excluded.notes,
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
      ],
    );
    const invoiceId = result.rows[0]?.id;
    if (!invoiceId) continue;
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
      const rawTaxRate = numberOrZero(item.taxRate) || numberOrZero(tax.taxRate) || 20;
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
            when coalesce(i.paid_amount, 0) >= totals.grand_total and totals.grand_total > 0 then 'paid'
            when coalesce(i.paid_amount, 0) > 0 then 'partial'
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
      [invoiceId],
    );
    invoicesImported += 1;
    reportProgress(invoiceIndex + 1, { invoiceNumber });
  }

  return {
    customers: customersImported,
    products: productsImported,
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
  importAkinsoftDataset(body, ({ stage, current, total, invoiceNumber }) => {
    job.stage = stage || job.stage;
    job.current = current;
    job.total = total || job.total;
    job.currentInvoiceNumber = invoiceNumber || null;
    job.percent = job.total ? Math.floor((job.current / job.total) * 100) : 0;
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
