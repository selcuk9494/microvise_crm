const fs = require('fs');
const path = require('path');
const http = require('http');
const crypto = require('crypto');
const { URL } = require('url');

const rootDir = path.resolve(__dirname, '..');
const webDir = path.join(rootDir, 'build', 'web');
const akinsoftJobs = new Map();

function loadEnvFile(filePath, { override = false } = {}) {
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
    const current = process.env[key];
    // Boş string dosyadaki değeri engellemesin (Electron/IDE env kirliliği).
    if (override || current == null || current === '') {
      process.env[key] = value;
    }
  }
}

// Electron: önce userData/.env.local (override), sonra proje kökü.
if (process.env.MICROVISE_ENV_DIR) {
  loadEnvFile(path.join(process.env.MICROVISE_ENV_DIR, '.env.local'), {
    override: true,
  });
  loadEnvFile(path.join(process.env.MICROVISE_ENV_DIR, '.env'), {
    override: true,
  });
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
        or upper(t.name) like '%HIZMET%'
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

// CRM MSSQL bağlantılarının program_name değeri (dm_exec_sessions).
// Havuzdaki DATABASE S kilitlerini WOLVOX engeli sanmamak için kullanılır.
const AKINSOFT_CRM_APP_NAME = 'microvise-crm';

function buildAkinsoftSqlConfig(body) {
  // UI her istekte şifreyi gönderir; yerelde kalıcı olsun ki CLI/senkron da çalışsın.
  try {
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
      const value = String(body?.[settingKey] ?? '').trim();
      if (value) {
        values[envKey] = value;
        process.env[envKey] = value;
      }
    }
    if (Object.keys(values).length) {
      upsertEnvFileValues(path.join(rootDir, '.env.local'), values);
    }
  } catch (_) {
    // env yazımı opsiyonel
  }
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
        // CRM havuzunu WOLVOX/SSMS'ten ayırt etmek için (dm_exec_sessions.program_name).
        appName: AKINSOFT_CRM_APP_NAME,
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

// Akınsoft/WOLVOX MSSQL yazımında kilit bekleme süresi (ms). WOLVOX açıkken
// ilgili tablolar kilitli olabilir; 180 sn beklemek yerine bu sürede net hata
// döndürürüz. Ortam değişkeni ile ayarlanabilir.
const AKINSOFT_LOCK_TIMEOUT_MS = Math.max(
  Number(process.env.AKINSOFT_LOCK_TIMEOUT_MS || 0) || 15000,
  1000,
);

// Yanıttaki build etiketi — istemci/log'da hangi sunucu kodunun yanıt verdiğini gösterir.
const AKINSOFT_SERVER_BUILD = 'cari-vkn-currency-kpb-v17';

// Geçici 1222 için kısa üstel retry (yalnızca gerçek kilit hatasında ödenir).
// Happy path: ilk deneme başarılıysa backoff / retry maliyeti yok.
const AKINSOFT_LOCK_RETRY_MAX = Math.max(
  Number(process.env.AKINSOFT_LOCK_RETRY_MAX || 0) || 3,
  1,
);
const AKINSOFT_LOCK_RETRY_BASE_MS = Math.max(
  Number(process.env.AKINSOFT_LOCK_RETRY_BASE_MS || 0) || 200,
  50,
);
const AKINSOFT_LOCK_RETRY_CAP_MS = Math.max(
  Number(process.env.AKINSOFT_LOCK_RETRY_CAP_MS || 0) || 800,
  AKINSOFT_LOCK_RETRY_BASE_MS,
);
// TX-order (BLKODU rezervasyonu TX dışı) ile self-lock giderildi; batch arası bekleme gerekmez.
const AKINSOFT_INTER_INVOICE_DELAY_MS = Math.max(
  Number(
    process.env.AKINSOFT_INTER_INVOICE_DELAY_MS === undefined
      ? 0
      : process.env.AKINSOFT_INTER_INVOICE_DELAY_MS,
  ) || 0,
  0,
);
// Lock DMV monitor: hızlı başarıda hiç sorgu atılmaz (lazy start).
const AKINSOFT_LOCK_MONITOR_DELAY_MS = Math.max(
  Number(process.env.AKINSOFT_LOCK_MONITOR_DELAY_MS || 0) || 2000,
  0,
);

function sleepMs(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/** Lazy lock monitor: delayMs dolmadan işlem biterse DMV sorgusu yok. */
function startAkinsoftLockMonitor(pool, sql, spid, { delayMs, intervalMs, maxTicks } = {}) {
  const startDelay =
    delayMs == null ? AKINSOFT_LOCK_MONITOR_DELAY_MS : Math.max(Number(delayMs) || 0, 0);
  const tickMs = Math.max(Number(intervalMs) || 1000, 200);
  const ticks = Math.max(Number(maxTicks) || 14, 1);
  let stop = false;
  let selfWait = null;
  let wakeSleep = null;
  const interruptibleSleep = (ms) =>
    new Promise((resolve) => {
      const timer = setTimeout(() => {
        wakeSleep = null;
        resolve();
      }, ms);
      wakeSleep = () => {
        clearTimeout(timer);
        wakeSleep = null;
        resolve();
      };
    });
  const promise = (async () => {
    if (!spid) return;
    if (startDelay > 0) {
      await interruptibleSleep(startDelay);
      if (stop) return;
    }
    for (let k = 0; k < ticks && !stop; k += 1) {
      try {
        const w = await pool.request().input('spid', sql.Int, spid).query(`
          select top 1
            r.status as reqStatus, r.command as command,
            r.wait_type as waitType, r.wait_resource as waitResource,
            r.blocking_session_id as blockingSessionId,
            bs.program_name as blockerProgram, bs.host_name as blockerHost,
            bs.login_name as blockerLogin, bs.status as blockerStatus,
            datediff(second, bs.last_request_start_time, getdate()) as blockerIdleSec
          from sys.dm_exec_requests r
          left join sys.dm_exec_sessions bs on bs.session_id = r.blocking_session_id
          where r.session_id = @spid
            and (r.wait_type is not null or r.blocking_session_id <> 0)
        `);
        const row = w.recordset?.[0];
        if (row && (row.waitType || row.blockingSessionId)) {
          selfWait = {
            command: textOrNull(row.command),
            waitType: textOrNull(row.waitType),
            waitResource: textOrNull(row.waitResource),
            blockingSessionId: row.blockingSessionId || 0,
            blockerProgram: textOrNull(row.blockerProgram),
            blockerHost: textOrNull(row.blockerHost),
            blockerLogin: textOrNull(row.blockerLogin),
            blockerStatus: textOrNull(row.blockerStatus),
            blockerIdleSec: row.blockerIdleSec ?? null,
          };
          if (row.blockingSessionId) break;
        }
      } catch (_) {
        // monitor opsiyonel
      }
      if (stop) break;
      await interruptibleSleep(tickMs);
    }
  })();
  return {
    get selfWait() {
      return selfWait;
    },
    stop() {
      stop = true;
      if (wakeSleep) wakeSleep();
    },
    async done() {
      stop = true;
      if (wakeSleep) wakeSleep();
      try {
        await promise;
      } catch (_) {}
    },
  };
}

function extractAkinsoftSqlError(error) {
  if (!error) return null;
  const info = error?.originalError?.info || {};
  const number = Number(error.number ?? info.number ?? 0) || null;
  const message = String(error.message || error || '').slice(0, 500);
  if (!number && !message) return null;
  return {
    number,
    code: textOrNull(error.code) || null,
    message,
    state: error.state ?? info.state ?? null,
    class: error.class ?? info.class ?? null,
    procName: textOrNull(error.procName ?? info.procName),
    lineNumber: error.lineNumber ?? info.lineNumber ?? null,
  };
}

// fn(attempt) sonuç döndürmeli. __lock true ise backoff ile tekrar dener.
async function withAkinsoftLockRetry(fn, { label } = {}) {
  const attempts = [];
  let last = null;
  for (let attempt = 0; attempt < AKINSOFT_LOCK_RETRY_MAX; attempt += 1) {
    last = await fn(attempt);
    if (!last || last.ok || !last.__lock) {
      if (last && attempts.length) last.lockRetries = attempts;
      if (last) delete last.__lock;
      return last;
    }
    attempts.push({
      attempt: attempt + 1,
      label: label || null,
      phase: last.phase || null,
      reason: last.reason || null,
      sqlError: last.sqlError || null,
      selfWait: last.selfWait || null,
    });
    if (attempt + 1 >= AKINSOFT_LOCK_RETRY_MAX) break;
    const delay = Math.min(
      AKINSOFT_LOCK_RETRY_CAP_MS,
      AKINSOFT_LOCK_RETRY_BASE_MS * 2 ** attempt,
    );
    await sleepMs(delay);
  }
  if (last) {
    last.lockRetries = attempts;
    delete last.__lock;
  }
  return last;
}

// node-mssql / tedious / kendi appName — bunlar "WOLVOX açık" sayılmaz.
function isOwnAkinsoftProgram(programName) {
  const p = String(programName || '').trim().toLowerCase();
  if (!p) return false;
  return (
    p === 'node-mssql' ||
    p === String(AKINSOFT_CRM_APP_NAME).toLowerCase() ||
    p.includes('microvise') ||
    p.includes('tedious') ||
    p.includes('node-mssql')
  );
}

function isWolvoxLikeProgram(programName) {
  const p = String(programName || '').toLowerCase();
  return (
    p.includes('wolvox') ||
    p.includes('werp') ||
    p.includes('akinsoft') ||
    p.includes('akınsoft')
  );
}

// DATABASE düzeyinde S (shared) her bağlantıda vardır; yazmayı engellemez.
// Gerçek engel: KEY/PAGE/RID/OBJECT/HOBT vb. üzerinde X/U/IX/IU/SIX/...
function isHarmlessDatabaseSharedLock(lock) {
  const type = String(lock?.resourceType || '').toUpperCase();
  const mode = String(lock?.requestMode || '').toUpperCase();
  return type === 'DATABASE' && (mode === 'S' || mode === 'IS');
}

function isMeaningfulAkinsoftLock(lock) {
  if (!lock || isHarmlessDatabaseSharedLock(lock)) return false;
  const type = String(lock.resourceType || '').toUpperCase();
  const mode = String(lock.requestMode || '').toUpperCase();
  // DB-level shared/intent-shared gürültü; diğer her şey potansiyel engel.
  if (type === 'DATABASE') return !(mode === 'S' || mode === 'IS');
  // Sch-S çoğu zaman zararsız; Sch-M bloklar.
  if (mode === 'SCH-S') return false;
  return true;
}

function isExternalOrMeaningfulSession(session, meaningfulLocks) {
  if (!session) return false;
  if (Number(session.blockingSessionId || 0) > 0) return true;
  if (isWolvoxLikeProgram(session.programName)) return true;
  if (!isOwnAkinsoftProgram(session.programName)) return true;
  // Kendi havuz oturumu: yalnız anlamlı (satır/nesne) kilit tutuyorsa ilgili.
  const sid = Number(session.sessionId);
  return (meaningfulLocks || []).some((l) => Number(l.sessionId) === sid);
}

// MSSQL/tedious ham hatalarını kullanıcıya anlamlı Türkçe nedene çevirir.
// Not: WOLVOX varsayımı kesin değil; blockers geldikten sonra
// refineAkinsoftLockItemReasons ile netleştirilir.
function describeAkinsoftSqlError(error) {
  if (!error) return 'Bilinmeyen Akınsoft hatası.';
  const number = Number(
    error.number ?? error?.originalError?.info?.number ?? 0,
  );
  const code = String(error.code || '');
  const message = String(error.message || error);
  if (number === 1222 || /lock request time out/i.test(message)) {
    return (
      'Akınsoft kaydı kilitli — WOLVOX’ta ilgili cari/fatura/stok ekranı açık ' +
      'olabilir. WOLVOX’u kapatıp (veya kaydı bırakıp) tekrar deneyin.'
    );
  }
  if (
    code === 'ETIMEOUT' ||
    /Timeout: Request failed to complete/i.test(message)
  ) {
    return (
      'Akınsoft SQL isteği zaman aşımına uğradı — kayıt kilitli ya da bağlantı ' +
      'yavaş olabilir. WOLVOX açıksa kapatıp tekrar deneyin.'
    );
  }
  return message;
}

function describeAkinsoftLockReasonFromEvidence({ blockers, selfWait } = {}) {
  const blockerProg = textOrNull(selfWait?.blockerProgram);
  if (blockerProg && isWolvoxLikeProgram(blockerProg)) {
    return (
      'Akınsoft kaydı kilitli — WOLVOX’ta ilgili cari/fatura/stok ekranı açık ' +
      'olabilir. WOLVOX’u kapatıp (veya kaydı bırakıp) tekrar deneyin.'
    );
  }
  if (blockerProg && isOwnAkinsoftProgram(blockerProg)) {
    return (
      'Akınsoft kaydı kısa süreliğe kilitlendi — engelleyen WOLVOX değil, ' +
      'CRM’in başka bir SQL bağlantısı (eşzamanlı SAP senkronu olabilir). ' +
      'Birkaç saniye sonra tekrar deneyin.'
    );
  }
  const locks = Array.isArray(blockers?.locks) ? blockers.locks : [];
  const sessions = Array.isArray(blockers?.sessions) ? blockers.sessions : [];
  const hasWolvox =
    locks.some((l) => isWolvoxLikeProgram(l.programName)) ||
    sessions.some((s) => isWolvoxLikeProgram(s.programName));
  if (hasWolvox) {
    return (
      'Akınsoft kaydı kilitli — WOLVOX’ta ilgili cari/fatura/stok ekranı açık ' +
      'olabilir. WOLVOX’u kapatıp (veya kaydı bırakıp) tekrar deneyin.'
    );
  }
  const onlyOwnNoise =
    locks.length === 0 &&
    sessions.every((s) => isOwnAkinsoftProgram(s.programName));
  if (onlyOwnNoise || (locks.length === 0 && sessions.length === 0)) {
    return (
      'Akınsoft kaydı kısa süreliğe kilitlendi; şu an görünen engelleyici ' +
      'WOLVOX değil (yalnızca CRM SQL havuz bağlantıları veya kilit kalkmış). ' +
      'Birkaç saniye sonra tekrar deneyin.'
    );
  }
  const sample = locks[0] || sessions[0];
  const who = [
    textOrNull(sample?.programName),
    textOrNull(sample?.hostName),
  ]
    .filter(Boolean)
    .join(' @ ');
  return (
    'Akınsoft kaydı kilitli' +
    (who ? ` (${who})` : '') +
    '. Engelleyen oturumu kapatıp tekrar deneyin.'
  );
}

// Kilit hatası olan item.reason metinlerini blockers/selfWait kanıtına göre düzelt.
function refineAkinsoftLockItemReasons(items, blockers) {
  if (!Array.isArray(items) || !items.length) return items;
  for (const it of items) {
    if (!it || it.ok) continue;
    if (!/kilitli|zaman aşımına uğrad/i.test(String(it.reason || ''))) continue;
    it.reason = describeAkinsoftLockReasonFromEvidence({
      blockers,
      selfWait: it.selfWait || null,
    });
  }
  return items;
}

// LOCK_TIMEOUT oturum ayarını verilen bağlantıya uygular. Yazma akışında ilk
// MSSQL isteği olarak çağrılırsa, aynı akıştaki sonraki ardışık pool.request()
// çağrıları (cari arama/oluşturma, mükerrer FATURA kontrolü, FATURA_NO güncelleme)
// aynı bağlantıyı yeniden kullandığından hepsi kilit sınırından yararlanır.
async function applyAkinsoftLockTimeout(pool) {
  try {
    await pool.request().query(`set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS}`);
    return true;
  } catch (_) {
    return false;
  }
}

// Bir hatanın SQL kilit zaman aşımı (error 1222) olup olmadığını söyler.
function isAkinsoftLockError(error) {
  const number = Number(
    error?.number ?? error?.originalError?.info?.number ?? 0,
  );
  return (
    number === 1222 || /lock request time out/i.test(String(error?.message || ''))
  );
}

// Kilit oluştuğunda anlamlı engelleyicileri döndürür. CRM havuzunun
// DATABASE S kilitleri / idle node-mssql oturumları raporlanmaz (false positive).
// VIEW SERVER STATE gerekir; yetki yoksa boş döner.
async function getAkinsoftLockHolders(pool) {
  const out = {
    locks: [],
    sessions: [],
    ignoredOwnLocks: 0,
    ignoredOwnSessions: 0,
  };
  // (1) Başka oturumların kilitleri — zararsız DATABASE S ve yalnız kendi
  // havuzunun anlamsız kilitleri elenir; @@spid zaten dışarıda.
  try {
    const locks = await pool.request().query(`
      set lock_timeout 4000;
      select top 100
        es.session_id as sessionId,
        es.login_name as loginName,
        es.host_name as hostName,
        es.program_name as programName,
        db_name(tl.resource_database_id) as dbName,
        tl.resource_type as resourceType,
        tl.request_mode as requestMode,
        tl.request_status as requestStatus,
        case when tl.resource_type = 'OBJECT'
             then object_name(tl.resource_associated_entity_id, tl.resource_database_id)
             else null end as objectName
      from sys.dm_tran_locks tl
      join sys.dm_exec_sessions es
        on es.session_id = tl.request_session_id
      where tl.request_session_id <> @@spid
        and es.is_user_process = 1
    `);
    const raw = (locks.recordset || []).map((r) => ({
      sessionId: r.sessionId,
      loginName: textOrNull(r.loginName),
      hostName: textOrNull(r.hostName),
      programName: textOrNull(r.programName),
      dbName: textOrNull(r.dbName),
      resourceType: textOrNull(r.resourceType),
      requestMode: textOrNull(r.requestMode),
      requestStatus: textOrNull(r.requestStatus),
      objectName: textOrNull(r.objectName),
    }));
    const meaningful = [];
    for (const lock of raw) {
      if (!isMeaningfulAkinsoftLock(lock)) {
        out.ignoredOwnLocks += 1;
        continue;
      }
      // Kendi havuzunun DATABASE dışı kilitleri (paralel senkron) anlamlıdır.
      meaningful.push(lock);
    }
    out.locks = meaningful;
  } catch (error) {
    out.locksError = `Kilit sorgulanamadı: ${error?.message || error}`;
  }
  // (2) Bu DB'ye bağlı kullanıcı oturumları — idle CRM havuzu gizlenir;
  // WOLVOX / yabancı / aktif bloklayan oturumlar kalır.
  try {
    const sessions = await pool.request().query(`
      set lock_timeout 4000;
      select top 100
        es.session_id as sessionId,
        es.login_name as loginName,
        es.host_name as hostName,
        es.program_name as programName,
        es.status as status,
        es.last_request_start_time as lastRequestStart,
        er.blocking_session_id as blockingSessionId,
        er.command as command,
        er.wait_type as waitType,
        er.wait_resource as waitResource
      from sys.dm_exec_sessions es
      left join sys.dm_exec_requests er on er.session_id = es.session_id
      where es.session_id <> @@spid
        and es.is_user_process = 1
        and (es.database_id = db_id() or er.database_id = db_id())
    `);
    const rawSessions = (sessions.recordset || []).map((r) => ({
      sessionId: r.sessionId,
      loginName: textOrNull(r.loginName),
      hostName: textOrNull(r.hostName),
      programName: textOrNull(r.programName),
      status: textOrNull(r.status),
      lastRequestStart: r.lastRequestStart || null,
      blockingSessionId: r.blockingSessionId || 0,
      command: textOrNull(r.command),
      waitType: textOrNull(r.waitType),
      waitResource: textOrNull(r.waitResource),
    }));
    const kept = [];
    for (const session of rawSessions) {
      if (isExternalOrMeaningfulSession(session, out.locks)) {
        kept.push(session);
      } else {
        out.ignoredOwnSessions += 1;
      }
    }
    out.sessions = kept;
    out.hasRealExternalBlocker =
      out.locks.some((l) => !isOwnAkinsoftProgram(l.programName)) ||
      out.sessions.some(
        (s) =>
          isWolvoxLikeProgram(s.programName) ||
          (!isOwnAkinsoftProgram(s.programName) &&
            (Number(s.blockingSessionId || 0) > 0 ||
              String(s.status || '').toLowerCase() === 'running')),
      );
  } catch (error) {
    out.sessionsError = `Oturumlar sorgulanamadı: ${error?.message || error}`;
  }
  return out;
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
        or upper(t.name) like '%HIZMET%'
        or upper(t.name) like '%EFAT%'
      group by s.name, t.name, p.rows
      order by
        case
          when upper(t.name) in ('FATURA', 'CARI', 'STOK', 'HIZMET') then 0
          when upper(t.name) like 'FATURA%' then 1
          when upper(t.name) like 'STOK%' then 2
          when upper(t.name) like 'HIZMET%' then 2
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
      'HIZMET',
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
        or upper(c.COLUMN_NAME) like '%HIZMET%'
        or upper(c.COLUMN_NAME) like '%HZM%'
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

/** null/boş dışında finite sayı; 0 geçerli KDV yüzdeidir (|| 20 ile karıştırma). */
function optionalNumber(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? value : null;
  const parsed = Number.parseFloat(String(value).replace(',', '.'));
  return Number.isFinite(parsed) ? parsed : null;
}

/**
 * WOLVOX STOK/HIZMET/fatura KDV yüzdesi.
 * KDV_ORANI doğrudan yüzde tutar (1/2/3 index değil). Satış > TPT > alış.
 * `|| 20` kullanılmaz: %0 ve %1 korunur; yalnızca tüm adaylar null ise fallback.
 */
function resolveAkinsoftVatPercent(row, fallback = 20) {
  const rate =
    optionalNumber(row?.KDV_ORANI) ??
    optionalNumber(row?.KDV_ORANI_SATIS_TPT) ??
    optionalNumber(row?.taxRate ?? row?.tax_rate) ??
    optionalNumber(row?.KDV_ORANI_ALIS);
  return rate == null ? fallback : rate;
}

const PAYMENT_CLOSE_TOLERANCE = 0.02;
// WOLVOX: FATURA.FATURA_NO = varchar(30), CARIHR.EVRAK_NO = varchar(20).
// E-fatura no 20 karakteri aşınca tahsilat EVRAK_NO kırpılır; birebir eşleşme kaçırılır.
const AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN = 20;

function akinsoftCariHrEvrakVariants(invoiceNumber) {
  const no = textOrNull(invoiceNumber);
  if (!no) return [];
  const variants = [no];
  if (no.length > AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN) {
    variants.push(no.slice(0, AKINSOFT_CARIHR_EVRAK_NO_MAX_LEN));
  }
  return variants;
}

/** CARIHR.EVRAK_NO → pull edilen FATURA_NO (kırpık eşleşme dahil). */
function resolveAkinsoftCariHrInvoiceNumber(evrakNo, invoiceNumbers) {
  const key = textOrNull(evrakNo);
  if (!key) return null;
  const list = Array.isArray(invoiceNumbers) ? invoiceNumbers : [];
  if (list.includes(key)) return key;
  const prefixMatches = list.filter(
    (no) =>
      typeof no === 'string' &&
      no.length > key.length &&
      no.startsWith(key),
  );
  if (prefixMatches.length === 1) return prefixMatches[0];
  // Tek aday yoksa güvenli taraf: kırpık anahtarı kullanma.
  return prefixMatches.length === 0 ? key : null;
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
  // KPBDVZ=1 → KPB/TL hesabı. DOVIZ_BIRIMI='$'' olsa bile bu yalnızca zeytin/FX
  // sütunudur; tutar KPB alanlarındadır (ör. DA0000001741: 4500 TL / 103.44 $).
  // KPBDVZ=0 → döviz hesabı; sembol (DOVIZ_BIRIMI) geçerli para birimidir.
  if (isAkinsoftLocalAccount(row)) return 'TRY';

  const symbolRaw = pick(row, ['SIMGE', 'DOVIZ_BIRIMI', 'DOVIZ_ADI', 'DVZ_BIRIMI']);
  if (textOrNull(symbolRaw)) {
    const symbolCurrency = normalizeCurrency(symbolRaw);
    // Açık TL/TRY sembolü asla USD'ye zorlanmaz.
    if (symbolCurrency === 'TRY') return 'TRY';
    return symbolCurrency;
  }

  if (isAkinsoftForeignAccount(row)) {
    // Sembol yok + KPBDVZ=0: DVZ tutarı boşsa KPB/TRY kullan (boş DVZ→USD 0 yazmayı engelle).
    const tryAmounts = resolveAkinsoftItemAmounts(row, 'TRY');
    const usdAmounts = resolveAkinsoftItemAmounts(row, 'USD');
    const hasForeign =
      numberOrZero(usdAmounts.netTotal) > 0 || numberOrZero(usdAmounts.unitPrice) > 0;
    const hasTry =
      numberOrZero(tryAmounts.netTotal) > 0 || numberOrZero(tryAmounts.unitPrice) > 0;
    if (!hasForeign && hasTry) return 'TRY';
    return 'USD';
  }

  return normalizeCurrency(
    pick(row, [
      'SIMGE',
      'DOVIZ_BIRIMI',
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
  // VKN öneki 9–11 hane olabilir (0620009058 / 620009058).
  return String(value ?? '')
    .trim()
    .replace(/^\d{9,11}-/, '');
}

/** Benzersiz, boş olmayan fatura no listesi (STŞ / Maliye / ERP). */
function uniqueInvoiceNumbers(...values) {
  const out = [];
  const seen = new Set();
  for (const value of values) {
    const text = textOrNull(value);
    if (!text) continue;
    const key = text.toLocaleUpperCase('tr-TR');
    if (seen.has(key)) continue;
    seen.add(key);
    out.push(text);
    const local = localEInvoiceNumber(text);
    if (local && local !== text) {
      const localKey = local.toLocaleUpperCase('tr-TR');
      if (!seen.has(localKey)) {
        seen.add(localKey);
        out.push(local);
      }
    }
  }
  return out;
}

/** CRM eşleşmesi için normalize anahtar (trim + TR upper). */
function normalizeInvoiceMatchKey(value) {
  const text = textOrNull(value);
  return text ? text.toLocaleUpperCase('tr-TR') : null;
}

/**
 * Faturaları CRM’de bulmak için aday anahtarlar:
 * resmi e-fatura, ERP/FATURA_NO, STŞ, VKN-önekli/önek-siz, CARIHR 20-char kırpık.
 */
function expandInvoiceMatchKeys(...values) {
  const out = [];
  const seen = new Set();
  const push = (raw) => {
    const key = normalizeInvoiceMatchKey(raw);
    if (!key || seen.has(key)) return;
    seen.add(key);
    out.push(key);
  };
  for (const value of uniqueInvoiceNumbers(...values)) {
    push(value);
    for (const variant of akinsoftCariHrEvrakVariants(value)) {
      push(variant);
    }
  }
  return out;
}

/**
 * Mevcut CRM faturasını Akınsoft source_id ve/veya numara varyantlarıyla bul.
 * Silinmiş sync_map hedefi stale kabul edilir (orphan map temizlenir).
 */
async function findExistingCrmInvoiceForAkinsoft(
  query,
  { sourceId = null, numbers = [] } = {},
) {
  const sid = textOrNull(sourceId);
  if (sid) {
    const mapped = await query(
      `
        select i.id, i.invoice_number, i.erp_invoice_number, i.e_invoice_number,
               i.is_active, i.status, i.currency,
               round(coalesce(i.grand_total, 0)::numeric, 2)::text as grand_total,
               m.local_id as mapped_local_id
        from public.akinsoft_sync_map m
        left join public.invoices i on i.id = m.local_id
        where m.source_system = 'akinsoft'
          and m.source_type = 'invoice'
          and m.source_id = $1
        limit 1
      `,
      [sid],
    );
    const row = mapped.rows[0];
    if (row?.mapped_local_id && !row?.id) {
      // Kullanıcı faturayı sildi; stale map → FK’ye yol açmasın.
      await query(
        `
          delete from public.akinsoft_sync_map
          where source_system = 'akinsoft'
            and source_type = 'invoice'
            and source_id = $1
        `,
        [sid],
      );
    } else if (row?.id) {
      return { ...row, matchMethod: 'source_id' };
    }
  }

  const keys = expandInvoiceMatchKeys(
    ...(Array.isArray(numbers) ? numbers : [numbers]),
  );
  if (!keys.length) return null;

  const found = await query(
    `
      select
        id, invoice_number, erp_invoice_number, e_invoice_number,
        is_active, status, currency,
        round(coalesce(grand_total, 0)::numeric, 2)::text as grand_total
      from public.invoices
      where
        upper(trim(coalesce(invoice_number, ''))) = any($1::text[])
        or upper(trim(coalesce(erp_invoice_number, ''))) = any($1::text[])
        or upper(trim(coalesce(e_invoice_number, ''))) = any($1::text[])
        or upper(trim(regexp_replace(
          coalesce(e_invoice_number, ''),
          '^\\d{9,11}-',
          ''
        ))) = any($1::text[])
        or left(upper(trim(coalesce(invoice_number, ''))), 20) = any($1::text[])
        or left(upper(trim(coalesce(erp_invoice_number, ''))), 20) = any($1::text[])
        or left(upper(trim(coalesce(e_invoice_number, ''))), 20) = any($1::text[])
      order by
        case when is_active is distinct from false then 0 else 1 end,
        updated_at desc nulls last,
        created_at desc nulls last
      limit 1
    `,
    [keys],
  );
  const row = found.rows[0];
  return row?.id ? { ...row, matchMethod: 'number' } : null;
}

/**
 * Pull önizlemesi için toplu CRM fatura eşlemesi (source_id + numara varyantları).
 * Dönen Map: invoiceSourceId → crm row (veya numara anahtarı → row).
 */
async function loadCrmInvoicesForAkinsoftMatch(query, invoices) {
  const list = Array.isArray(invoices) ? invoices : [];
  const bySourceId = new Map();
  const byNumberKey = new Map();

  const sourceIds = [
    ...new Set(list.map((inv) => textOrNull(inv.sourceId)).filter(Boolean)),
  ];
  if (sourceIds.length) {
    const mapped = await query(
      `
        select
          m.source_id,
          i.id, i.invoice_number, i.erp_invoice_number, i.e_invoice_number,
          i.is_active, i.status, i.currency,
          round(coalesce(i.grand_total, 0)::numeric, 2)::text as grand_total
        from public.akinsoft_sync_map m
        join public.invoices i on i.id = m.local_id
        where m.source_system = 'akinsoft'
          and m.source_type = 'invoice'
          and m.source_id = any($1::text[])
      `,
      [sourceIds],
    );
    for (const row of mapped.rows) {
      const sid = textOrNull(row.source_id);
      if (sid && row.id) bySourceId.set(sid, row);
    }
  }

  const allKeys = [];
  const keySeen = new Set();
  for (const inv of list) {
    for (const key of expandInvoiceMatchKeys(
      inv.invoiceNumber,
      inv.erpInvoiceNumber,
      inv.eInvoiceNumber,
      inv.officialEInvoiceNumber,
    )) {
      if (keySeen.has(key)) continue;
      keySeen.add(key);
      allKeys.push(key);
    }
  }
  if (allKeys.length) {
    const found = await query(
      `
        select
          id, invoice_number, erp_invoice_number, e_invoice_number,
          is_active, status, currency,
          round(coalesce(grand_total, 0)::numeric, 2)::text as grand_total
        from public.invoices
        where
          upper(trim(coalesce(invoice_number, ''))) = any($1::text[])
          or upper(trim(coalesce(erp_invoice_number, ''))) = any($1::text[])
          or upper(trim(coalesce(e_invoice_number, ''))) = any($1::text[])
          or upper(trim(regexp_replace(
            coalesce(e_invoice_number, ''),
            '^\\d{9,11}-',
            ''
          ))) = any($1::text[])
          or left(upper(trim(coalesce(invoice_number, ''))), 20) = any($1::text[])
          or left(upper(trim(coalesce(erp_invoice_number, ''))), 20) = any($1::text[])
          or left(upper(trim(coalesce(e_invoice_number, ''))), 20) = any($1::text[])
      `,
      [allKeys],
    );
    const indexRow = (row, raw) => {
      const key = normalizeInvoiceMatchKey(raw);
      if (key && !byNumberKey.has(key)) byNumberKey.set(key, row);
    };
    for (const row of found.rows) {
      indexRow(row, row.invoice_number);
      indexRow(row, row.erp_invoice_number);
      indexRow(row, row.e_invoice_number);
      indexRow(row, localEInvoiceNumber(row.e_invoice_number));
      for (const variant of akinsoftCariHrEvrakVariants(row.invoice_number)) {
        indexRow(row, variant);
      }
      for (const variant of akinsoftCariHrEvrakVariants(row.erp_invoice_number)) {
        indexRow(row, variant);
      }
      for (const variant of akinsoftCariHrEvrakVariants(row.e_invoice_number)) {
        indexRow(row, variant);
      }
    }
  }

  function resolveForInvoice(invoice) {
    const sid = textOrNull(invoice.sourceId);
    if (sid && bySourceId.has(sid)) return bySourceId.get(sid);
    for (const key of expandInvoiceMatchKeys(
      invoice.invoiceNumber,
      invoice.erpInvoiceNumber,
      invoice.eInvoiceNumber,
      invoice.officialEInvoiceNumber,
    )) {
      if (byNumberKey.has(key)) return byNumberKey.get(key);
    }
    return null;
  }

  return { bySourceId, byNumberKey, resolveForInvoice };
}

/**
 * Aynı resmi / ERP numarasıyla mevcut FATURA veya orphan CARIHR (FTO_*) bul.
 * WOLVOX’ta FATURA_NO unique DEĞİL; mükerrer create’i engellemek için zorunlu.
 */
async function findExistingAkinsoftFaturaByNumbers(pool, sql, numbers) {
  const list = uniqueInvoiceNumbers(...(Array.isArray(numbers) ? numbers : [numbers]));
  if (!list.length) return null;

  const faturaReq = pool.request();
  const faturaParams = list.map((no, index) => {
    const name = `fn${index}`;
    faturaReq.input(name, sql.NVarChar(64), no);
    return `@${name}`;
  });
  const fatura = await faturaReq.query(`
    set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS};
    select top 20
      cast(BLKODU as nvarchar(64)) as sourceId,
      FATURA_NO as invoiceNumber,
      TARIHI as invoiceDate
    from dbo.FATURA with (nolock)
    where FATURA_NO in (${faturaParams.join(', ')})
    order by
      case when FATURA_NO = ${faturaParams[0]} then 0 else 1 end,
      TARIHI desc,
      BLKODU desc
  `);
  if (fatura.recordset?.length) {
    const row = fatura.recordset[0];
    return {
      sourceId: String(row.sourceId),
      invoiceNumber: textOrNull(row.invoiceNumber),
      via: 'fatura',
      matchCount: fatura.recordset.length,
      allSourceIds: fatura.recordset.map((r) => String(r.sourceId)),
    };
  }

  const cariReq = pool.request();
  const cariParams = list.map((no, index) => {
    const name = `en${index}`;
    cariReq.input(name, sql.NVarChar(64), no);
    return `@${name}`;
  });
  const cari = await cariReq.query(`
    set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS};
    select top 20
      cast(BLKODU as nvarchar(64)) as cariHrId,
      EVRAK_NO as invoiceNumber,
      cast(ENTEGRASYON as nvarchar(40)) as entegrasyon,
      ISLEM_TURU as islemTuru
    from dbo.CARIHR with (nolock)
    where EVRAK_NO in (${cariParams.join(', ')})
      and (
        ENTEGRASYON like N'FTO[_]%'
        or ENTEGRASYON like N'FTK[_]%'
        or ISLEM_TURU in (4, 9)
      )
    order by TARIHI desc, BLKODU desc
  `);
  if (!cari.recordset?.length) return null;

  let recoveredSourceId = null;
  for (const row of cari.recordset) {
    const ent = String(row.entegrasyon || '');
    const m = ent.match(/^FT[OK]_(\d+)$/i);
    if (m) {
      recoveredSourceId = m[1];
      break;
    }
  }
  return {
    sourceId: recoveredSourceId,
    invoiceNumber: textOrNull(cari.recordset[0].invoiceNumber),
    via: 'carihr',
    matchCount: cari.recordset.length,
    orphanCariHr: true,
    allSourceIds: recoveredSourceId ? [recoveredSourceId] : [],
  };
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
/** Wolvox dönem kontrolü için gün başı (TARIHI2 / VADESI). */
function toSqlDateOnly(value, fallback = null) {
  const d = toSqlDate(value, fallback);
  if (!(d instanceof Date) || Number.isNaN(d.getTime())) return fallback;
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate(), 0, 0, 0));
}

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
            'KPB_FIYATI',
            'KPB_KDV_HARICFY',
            'KPB_IND_FIYAT',
            'KPB_BIRIM_FIYAT',
            'KPB_BF',
            'FIYATI',
            'BIRIM_FIYAT',
          ]
        : [
            'DVZ_FIYATI',
            'DVZ_KDV_HARICFY',
            'DVZ_IND_FIYAT',
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
  // KPB_FIYATI bazen KDV dahil (KPB_KDVLI ile aynı); birim fiyatı net satırdan düzelt.
  let resolvedUnitPrice = unitPrice;
  if (
    quantity > 0 &&
    netTotal > 0 &&
    unitPrice > 0 &&
    Math.abs(unitPrice * quantity - netTotal) > 0.05
  ) {
    const fromNet = netTotal / quantity;
    if (fromNet > 0 && fromNet < unitPrice) {
      resolvedUnitPrice = fromNet;
    }
  }
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
    unitPrice: resolvedUnitPrice,
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
      add column if not exists erp_invoice_number_synced_at timestamptz,
      add column if not exists prices_include_vat boolean not null default false,
      add column if not exists akinsoft_sync_status text,
      add column if not exists akinsoft_synced_at timestamptz,
      add column if not exists akinsoft_sync_error text
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
  await query(`
    update public.invoices i
    set
      akinsoft_sync_status = 'synced',
      akinsoft_synced_at = coalesce(i.akinsoft_synced_at, m.updated_at, m.created_at, now())
    from public.akinsoft_sync_map m
    where m.source_system = 'akinsoft'
      and m.source_type = 'invoice'
      and m.local_id = i.id
      and (
        i.akinsoft_sync_status is null
        or i.akinsoft_sync_status = ''
        or i.akinsoft_sync_status = 'pending'
      )
  `);
}

async function setInvoiceAkinsoftSyncStatus(query, invoiceId, status, errorMessage) {
  const id = textOrNull(invoiceId);
  if (!id) return;
  const syncStatus = String(status || '').trim().toLowerCase();
  if (!['synced', 'error', 'pending'].includes(syncStatus)) return;
  const err =
    syncStatus === 'error'
      ? textOrNull(errorMessage)?.slice(0, 2000) || 'Akınsoft gönderimi başarısız.'
      : null;
  await query(
    `
      update public.invoices
      set akinsoft_sync_status = $2,
          akinsoft_synced_at = case
            when $2 = 'synced' then now()
            else akinsoft_synced_at
          end,
          akinsoft_sync_error = $3,
          updated_at = now()
      where id = $1::uuid
    `,
    [id, syncStatus, err],
  );
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

/** Cari unvanını kabaca karşılaştır (aynı VKN / farklı şirket ayrımı). */
function normalizeAkinsoftCustomerNameKey(value) {
  return String(value || '')
    .toLocaleUpperCase('tr-TR')
    .replace(/&/g, ' AND ')
    .replace(/[^0-9A-ZÇĞİÖŞÜ]+/gi, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

const AKINSOFT_CUSTOMER_NAME_NOISE = new Set([
  'LTD',
  'LIMITED',
  'LLC',
  'INC',
  'CO',
  'COMPANY',
  'FOOD',
  'BEVERAGE',
  'BEVERAGES',
  'TRADING',
  'TRADE',
  'ENTERPRISE',
  'ENTERPRISES',
  'SANAYI',
  'TICARET',
  'TURIZM',
  'TOURISM',
  'VE',
  'AND',
  'THE',
  'STI',
  'SIRKETI',
  'SIRKET',
  'A',
  'S',
  'AS',
]);

function akinsoftCustomerDistinctiveTokens(value) {
  return normalizeAkinsoftCustomerNameKey(value)
    .split(' ')
    .filter((token) => token.length > 1 && !AKINSOFT_CUSTOMER_NAME_NOISE.has(token));
}

function akinsoftCustomerNamesCompatible(pulledName, localName) {
  const a = normalizeAkinsoftCustomerNameKey(pulledName);
  const b = normalizeAkinsoftCustomerNameKey(localName);
  if (!a || !b) return false;
  if (a === b) return true;
  // Tam içerme yalnızca gürültü kelimeleri çıkarıldıktan sonra anlamlıysa.
  const tokensA = akinsoftCustomerDistinctiveTokens(pulledName);
  const tokensB = akinsoftCustomerDistinctiveTokens(localName);
  if (!tokensA.length || !tokensB.length) return false;
  const setB = new Set(tokensB);
  let overlap = 0;
  for (const token of tokensA) {
    if (setB.has(token)) overlap += 1;
  }
  // En az 1 ayırt edici ortak token ve %50+ örtüşme.
  // "M & L FOOD" vs "AYDIN FOOD" → ayırt edici token yok ortak → reddet.
  const ratio = overlap / Math.min(tokensA.length, tokensB.length);
  return overlap >= 1 && ratio >= 0.5;
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
        source_code = coalesce(excluded.source_code, public.akinsoft_sync_map.source_code),
        source_name = coalesce(excluded.source_name, public.akinsoft_sync_map.source_name),
        local_table = excluded.local_table,
        -- Manuel eşleşmeyi otomatik (VKN/isim) yazımla bozma.
        local_id = case
          when public.akinsoft_sync_map.matched_manually = true
            and excluded.matched_manually = false
            and public.akinsoft_sync_map.local_id is distinct from excluded.local_id
          then public.akinsoft_sync_map.local_id
          else excluded.local_id
        end,
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

const _akinsoftSchemaCache = {
  exists: new Map(),
  columns: new Map(),
  identity: new Map(),
};

async function akinsoftTableExists(pool, tableName) {
  const key = String(tableName || '').toUpperCase();
  if (_akinsoftSchemaCache.exists.has(key)) {
    return _akinsoftSchemaCache.exists.get(key);
  }
  const result = await pool
    .request()
    .input('table', tableName)
    .query(`
      select top 1 1 as ok
      from INFORMATION_SCHEMA.TABLES
      where TABLE_SCHEMA = 'dbo' and TABLE_NAME = @table
    `);
  const ok = result.recordset.length > 0;
  _akinsoftSchemaCache.exists.set(key, ok);
  return ok;
}

async function akinsoftTableColumnSet(pool, tableName) {
  const key = String(tableName || '').toUpperCase();
  if (_akinsoftSchemaCache.columns.has(key)) {
    return _akinsoftSchemaCache.columns.get(key);
  }
  const result = await pool
    .request()
    .input('table', tableName)
    .query(`
      select COLUMN_NAME as name
      from INFORMATION_SCHEMA.COLUMNS
      where TABLE_SCHEMA = 'dbo' and TABLE_NAME = @table
    `);
  const cols = new Set(result.recordset.map((row) => String(row.name).toUpperCase()));
  _akinsoftSchemaCache.columns.set(key, cols);
  return cols;
}

function normalizeProductSnapshot(product) {
  const productType =
    textOrNull(product.productType ?? product.product_type) === 'service'
      ? 'service'
      : 'product';
  return {
    code: textOrNull(product.code) || '',
    name: textOrNull(product.name) || '',
    description: textOrNull(product.description) || '',
    category: textOrNull(product.category) || '',
    unit: textOrNull(product.unit) || 'Adet',
    taxRate: Number(resolveAkinsoftVatPercent(product)),
    group:
      textOrNull(product.group ?? product.akinsoft_group) ||
      textOrNull(product.category) ||
      '',
    subGroup: textOrNull(product.subGroup ?? product.akinsoft_sub_group) || '',
    productType,
    salePrice: Number(numberOrZero(product.salePrice ?? product.sale_price)),
    currency: normalizeCurrency(product.currency) || 'TRY',
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
    a.subGroup === b.subGroup &&
    a.productType === b.productType &&
    a.salePrice === b.salePrice &&
    a.currency === b.currency
  );
}

function akinsoftHizmetSourceId(blkodu) {
  const id = Number(blkodu);
  if (!Number.isFinite(id) || id <= 0) return null;
  return `hizmet:${id}`;
}

function mapAkinsoftHizmetRow(row) {
  const blkodu = String(row.BLKODU);
  const dovizPrice = numberOrZero(row.DOVIZ_FIYATI);
  const kpbPrice = numberOrZero(row.KPB_FIYATI);
  const hasDoviz = dovizPrice > 0;
  const currency = hasDoviz
    ? normalizeCurrency(row.DOVIZ_BIRIMI) || 'USD'
    : 'TRY';
  const name = textOrNull(row.ADI) || `Hizmet ${blkodu}`;
  return {
    sourceId: akinsoftHizmetSourceId(blkodu),
    code: textOrNull(row.OZEL_KODU) || `HZM-${blkodu}`,
    name,
    unit: textOrNull(row.BIRIMI) || 'Adet',
    taxRate: resolveAkinsoftVatPercent(row),
    group:
      textOrNull(row.GRUBU) ||
      textOrNull(row.ARA_GRUBU) ||
      textOrNull(row.OZEL_KODU) ||
      'Hizmet',
    subGroup: textOrNull(row.ALT_GRUBU) || textOrNull(row.ARA_GRUBU),
    category:
      textOrNull(row.GRUBU) ||
      textOrNull(row.ARA_GRUBU) ||
      'Hizmet',
    description: textOrNull(row.ACIKLAMA),
    currency,
    purchasePrice: 0,
    // WOLVOX HIZMET Fiyatlar sekmesi KDV hariç tutulur.
    salePrice: hasDoviz ? dovizPrice : kpbPrice,
    productType: 'service',
    trackStock: false,
    isActive: row.AKTIF == null ? true : Number(row.AKTIF) !== 0,
    createdAt: null,
  };
}

/** STOK_FIYAT HESAP / KPB_MI → CRM currency (WOLVOX $ → USD, TL → TRY). */
function resolveAkinsoftStokCurrency(row, salePrice) {
  const hesap = textOrNull(row.SATIS_HESAP ?? row.HESAP);
  const dovizBirimi = textOrNull(row.DOVIZ_BIRIMI);
  const kpbMi = Number(row.SATIS_KPB_MI);
  if (salePrice > 0) {
    if (hesap) return normalizeCurrency(hesap);
    if (kpbMi === 2) return normalizeCurrency(dovizBirimi) || 'USD';
    if (kpbMi === 1) return 'TRY';
  }
  if (Number(row.DOVIZ_KULLAN) === 1 && dovizBirimi) {
    return normalizeCurrency(dovizBirimi) || 'USD';
  }
  if (dovizBirimi) {
    const cur = normalizeCurrency(dovizBirimi);
    if (cur !== 'TRY') return cur;
  }
  return 'TRY';
}

/**
 * WOLVOX STOK kartı → CRM product.
 * Satış fiyatı dbo.STOK_FIYAT (ALIS_SATIS=2) üzerinden gelir; FIYATI KDV hariçtir.
 * Döviz satırı (KPB_MI=2 / HESAP=$) varsa TL satırına tercih edilir.
 */
function mapAkinsoftStokRow(row) {
  const salePrice = numberOrZero(row.SATIS_FIYATI ?? row.FIYATI);
  return {
    sourceId: String(row.BLKODU),
    code: textOrNull(row.STOKKODU),
    name: textOrNull(row.STOK_ADI) || `Stok ${row.BLKODU}`,
    unit: textOrNull(row.BIRIMI) || textOrNull(row.BIRIMI_2) || 'Adet',
    taxRate: resolveAkinsoftVatPercent(row),
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
    currency: resolveAkinsoftStokCurrency(row, salePrice),
    purchasePrice: 0,
    salePrice,
    productType: 'product',
    trackStock: true,
    createdAt: dateOrIso(row.KAYIT_TARIHI),
  };
}

/** STOK select + OUTER APPLY preferred SATIŞ FİYATI -1 (döviz öncelikli). */
function buildAkinsoftStokSelectSql({ hasStokFiyat, whereClause, topParam }) {
  const top = topParam ? `top (${topParam})` : '';
  const priceSelect = hasStokFiyat
    ? `
            pf.FIYATI as SATIS_FIYATI,
            pf.HESAP as SATIS_HESAP,
            pf.KPB_MI as SATIS_KPB_MI`
    : `
            cast(null as float) as SATIS_FIYATI,
            cast(null as varchar(16)) as SATIS_HESAP,
            cast(null as smallint) as SATIS_KPB_MI`;
  const fromJoin = hasStokFiyat
    ? `
          from dbo.STOK s
          outer apply (
            select top 1
              f.FIYATI,
              f.HESAP,
              f.KPB_MI
            from dbo.STOK_FIYAT f
            where f.BLSTKODU = s.BLKODU
              and f.ALIS_SATIS = 2
              and f.FIYATI > 0
            order by
              case when f.FIYAT_NO = 1 then 0 else 1 end,
              case
                when f.KPB_MI = 2 then 0
                when upper(ltrim(rtrim(isnull(f.HESAP, '')))) not in ('', 'TL', 'TRY', 'KPB')
                  then 0
                else 1
              end,
              f.FIYATI desc
          ) pf`
    : `
          from dbo.STOK s`;
  return `
          select ${top}
            s.BLKODU, s.STOKKODU, s.STOK_ADI, s.BIRIMI, s.KDV_ORANI, s.KDV_ORANI_ALIS,
            s.KDV_ORANI_SATIS_TPT, s.OZEL_KODU1,
            s.OZEL_KODU2, s.OZEL_KODU3, s.ARA_GRUBU, s.ALT_GRUBU, s.KAYIT_TARIHI,
            s.ACIKLAMA1, s.ACIKLAMA2, s.DOVIZ_BIRIMI, s.DOVIZ_KULLAN,
            ${priceSelect.trim()}
          ${fromJoin}
          where ${whereClause}
          order by s.BLKODU desc
        `;
}

function resolveAkinsoftLineProductSourceId(row) {
  const stokId = Number(row.BLSTKODU);
  if (Number.isFinite(stokId) && stokId > 0) return String(stokId);
  return akinsoftHizmetSourceId(row.BLHZMKODU);
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
      p.sale_price,
      p.currency,
      p.product_type,
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
      salePrice: row.sale_price,
      currency: row.currency,
      productType: row.product_type,
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

    // BLKODU / harici map önce: aynı VKN'li farklı cariler (Aydın vs M&L) birleşmesin.
    if (sourceId && externalBySource.has(sourceId)) {
      match = externalBySource.get(sourceId);
    }
    if (!match && sourceId) match = sourceMatches.get(sourceId) || null;
    if (!match && sourceCode) match = codeMatches.get(sourceCode) || null;
    if (!match && taxNumber) {
      const taxMatch = taxMatches.get(taxNumber) || null;
      // Aynı VKN birden fazla WOLVOX carisine ait olabilir; unvan uyuşmuyorsa VKN ile eşleme.
      if (
        taxMatch &&
        akinsoftCustomerNamesCompatible(invoice.customerName, taxMatch.localName)
      ) {
        match = taxMatch;
      }
    }

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

async function pullAkinsoftDataset(body) {
  const sql = require('mssql');
  const { database, config } = buildAkinsoftSqlConfig(body);
  const limit = Math.max(1, Math.min(Number(body.limit || 2000), 5000));
  // pull-and-update: tam stok/hizmet kataloğu yerine yalnızca fatura
  // kalemlerinde geçen ürünleri çeker (büyük STOK/HIZMET taraması atlanır).
  const liteCatalog =
    body?.syncMode === 'pull-and-update' || body?.liteCatalog === true;
  const pool = await connectAkinsoftPool(config);

  try {
    const warnings = [];
    const [hasFatura, hasFaturaHr, hasFaturaKdv, hasCari, hasStok, hasHizmet, hasCariHr, hasStokFiyat] =
      await Promise.all([
        akinsoftTableExists(pool, 'FATURA'),
        akinsoftTableExists(pool, 'FATURAHR'),
        akinsoftTableExists(pool, 'FATURA_KDV'),
        akinsoftTableExists(pool, 'CARI'),
        akinsoftTableExists(pool, 'STOK'),
        akinsoftTableExists(pool, 'HIZMET'),
        akinsoftTableExists(pool, 'CARIHR'),
        akinsoftTableExists(pool, 'STOK_FIYAT'),
      ]);

    let customers = [];
    let products = [];
    let customerCount = 0;
    let productCount = 0;
    let hizmetCount = 0;
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
    if (hasCari && !liteCatalog) {
      const countResult = await pool
        .request()
        .query(`select count_big(1) as total from dbo.CARI`);
      customerCount = Number(countResult.recordset[0]?.total || 0);
    }
    // Stok/hizmet kartları (fiyat dahil) her zaman çekilir; lite yalnızca CARI'yı atlar.
    const mapProductRow = mapAkinsoftStokRow;
    if (hasStok) {
      const countResult = await pool
        .request()
        .query(`select count_big(1) as total from dbo.STOK`);
      productCount = Number(countResult.recordset[0]?.total || 0);
      // Fatura kalemlerinden bağımsız: yeni açılan stoklar da gelsin.
      // Fiyat: STOK_FIYAT satış (KDV hariç) + döviz hesabı ($/TL).
      products = (
        await pool.request().input('limit', sql.Int, limit).query(
          buildAkinsoftStokSelectSql({
            hasStokFiyat,
            whereClause: `coalesce(s.STOK_ADI, '') <> ''
             or coalesce(s.STOKKODU, '') <> ''`,
            topParam: '@limit',
          }),
        )
      ).recordset.map(mapProductRow);
    }
    if (hasHizmet) {
      const countResult = await pool
        .request()
        .query(`select count_big(1) as total from dbo.HIZMET`);
      hizmetCount = Number(countResult.recordset[0]?.total || 0);
      const hizmetRows = (
        await pool.request().input('limit', sql.Int, limit).query(`
          select top (@limit)
            BLKODU, ADI, OZEL_KODU, KPB_FIYATI, DOVIZ_FIYATI, DOVIZ_BIRIMI,
            ACIKLAMA, KDV_ORANI, BIRIMI, GRUBU, ARA_GRUBU, ALT_GRUBU, AKTIF
          from dbo.HIZMET
          where coalesce(ADI, '') <> ''
          order by BLKODU desc
        `)
      ).recordset.map(mapAkinsoftHizmetRow);
      products = [...products, ...hizmetRows];
      productCount += hizmetCount;
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
      const invoiceNumbers = headers
        .map((row) => textOrNull(row.FATURA_NO))
        .filter(Boolean);

      const fetchInvoiceCustomers = async () => {
        if (!(customerIds.length && hasCari)) return [];
        const request = pool.request();
        customerIds.forEach((id, index) => request.input(`cid${index}`, sql.Int, id));
        const paramList = customerIds.map((_, index) => `@cid${index}`).join(',');
        return (
          await request.query(`
            select
              BLKODU, CARIKODU, TICARI_UNVANI, ADI, SOYADI, VERGI_DAIRESI,
              VERGI_NO, TEL1, TEL2, CEP_TEL, FAKS, E_MAIL, WEB, KAYIT_TARIHI
            from dbo.CARI
            where BLKODU in (${paramList})
          `)
        ).recordset.map(mapCustomerRow);
      };

      const fetchInvoiceItems = async () => {
        if (!(ids.length && hasFaturaHr)) return [];
        const request = pool.request();
        ids.forEach((id, index) => request.input(`id${index}`, sql.Int, id));
        const paramList = ids.map((_, index) => `@id${index}`).join(',');
        return (
          await request.query(`
            select *
            from dbo.FATURAHR
            where BLFTKODU in (${paramList})
            order by BLFTKODU, BLKODU
          `)
        ).recordset;
      };

      const fetchCariHr = async () => {
        if (!(invoiceNumbers.length && hasCariHr)) {
          return { rows: [], reliable: Boolean(hasCariHr) };
        }
        try {
          // Uzun e-fatura no'ları CARIHR.EVRAK_NO (varchar 20) içinde kırpık
          // tutulur; tam FATURA_NO ile IN eşleşmesi kaçırır → durum open kalır.
          const lookupNumbers = [
            ...new Set(invoiceNumbers.flatMap(akinsoftCariHrEvrakVariants)),
          ];
          const request = pool.request();
          request.timeout = 25000;
          lookupNumbers.forEach((no, index) =>
            request.input(`no${index}`, sql.NVarChar, no),
          );
          const paramList = lookupNumbers.map((_, index) => `@no${index}`).join(',');
          const rows = (
            await request.query(`
              select EVRAK_NO, KPB_BTUT, KPB_ATUT, DVZ_BTUT, DVZ_ATUT
              from dbo.CARIHR
              where EVRAK_NO in (${paramList})
                and coalesce(SILINDI, 0) = 0
            `)
          ).recordset;
          return { rows, reliable: true };
        } catch (error) {
          warnings.push(
            `Cari hareketleri okunamadı; ödeme/durum bilgisi eksik olabilir: ${
              error instanceof Error ? error.message : String(error)
            }`,
          );
          return { rows: [], reliable: false };
        }
      };

      const fetchKdv = async () => {
        if (!(ids.length && hasFaturaKdv)) return [];
        const request = pool.request();
        ids.forEach((id, index) => request.input(`id${index}`, sql.Int, id));
        const paramList = ids.map((_, index) => `@id${index}`).join(',');
        return (
          await request.query(`
            select BLFTKODU, KDV_ORANI, KDV_MATRAHI, KDV_TUTARI
            from dbo.FATURA_KDV
            where BLFTKODU in (${paramList})
          `)
        ).recordset;
      };

      const [usedCustomers, itemRows, cariHrPack, kdvRows] = await Promise.all([
        fetchInvoiceCustomers(),
        fetchInvoiceItems(),
        fetchCariHr(),
        fetchKdv(),
      ]);
      if (usedCustomers.length) {
        const bySource = new Map(customers.map((row) => [String(row.sourceId), row]));
        for (const customer of usedCustomers) {
          bySource.set(String(customer.sourceId), customer);
        }
        customers = [...bySource.values()];
      }
      const cariHrRows = cariHrPack.rows;
      let cariHrPaymentReliable = cariHrPack.reliable;
      const productIds = [
        ...new Set(
          itemRows
            .map((row) => Number(row.BLSTKODU))
            .filter((id) => Number.isFinite(id) && id > 0),
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
            await request.query(
              buildAkinsoftStokSelectSql({
                hasStokFiyat,
                whereClause: `s.BLKODU in (${paramList})`,
                topParam: null,
              }),
            )
          ).recordset.map(mapProductRow);
          products = [...products, ...extra];
        }
      }
      const hizmetIds = [
        ...new Set(
          itemRows
            .map((row) => Number(row.BLHZMKODU))
            .filter((id) => Number.isFinite(id) && id > 0),
        ),
      ];
      if (hizmetIds.length && hasHizmet) {
        const known = new Set(products.map((row) => String(row.sourceId)));
        const missingIds = hizmetIds.filter(
          (id) => !known.has(akinsoftHizmetSourceId(id)),
        );
        if (missingIds.length) {
          const request = pool.request();
          missingIds.forEach((id, index) =>
            request.input(`hid${index}`, sql.Int, id),
          );
          const paramList = missingIds
            .map((_, index) => `@hid${index}`)
            .join(',');
          const extra = (
            await request.query(`
              select
                BLKODU, ADI, OZEL_KODU, KPB_FIYATI, DOVIZ_FIYATI, DOVIZ_BIRIMI,
                ACIKLAMA, KDV_ORANI, BIRIMI, GRUBU, ARA_GRUBU, ALT_GRUBU, AKTIF
              from dbo.HIZMET
              where BLKODU in (${paramList})
            `)
          ).recordset.map(mapAkinsoftHizmetRow);
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
          productSourceId: resolveAkinsoftLineProductSourceId(row),
          code: textOrNull(row.STOKKODU),
          description: textOrNull(row.STOK_ADI) || 'Fatura kalemi',
          quantity: numberOrZero(row.MIKTARI) || 1,
          unit:
            textOrNull(row.BIRIMI) ||
            textOrNull(row.BIRIMI_2) ||
            'Adet',
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
        const mappedNo = resolveAkinsoftCariHrInvoiceNumber(
          row.EVRAK_NO,
          invoiceNumbers,
        );
        if (!mappedNo) continue;
        const list = cariHrByInvoiceNo.get(mappedNo) || [];
        list.push(row);
        cariHrByInvoiceNo.set(mappedNo, list);
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
              'DOVIZ_ADI',
              'DVZ_BIRIMI',
              'PARA_BIRIMI',
              'DOVIZ',
            ]);
        const headerDovizKullan = parseAkinsoftBool(pick(row, ['DOVIZ_KULLAN']));
        const itemCurrencies = rawItems
          .map((item) => textOrNull(item.currency))
          .filter(Boolean);
        const tryItemCount = itemCurrencies.filter((item) => item === 'TRY').length;
        const foreignItemCurrency = itemCurrencies.find((item) => item !== 'TRY');
        let currency = foreignItemCurrency || (
          itemCurrencies.length ? 'TRY' : normalizeCurrency(headerCurrencyValue)
        );
        // Satırların tamamı KPB/TL (KPBDVZ=1) ise başlık DOVIZ_KULLAN=1 / DOVIZ_BIRIMI=$
        // olsa bile TRY kal — zeytin sütunu ikincil FX'tir.
        if (itemCurrencies.length && tryItemCount === itemCurrencies.length) {
          currency = 'TRY';
        }
        // Başlık TL ise (DOVIZ_KULLAN=0 veya DOVIZ_BIRIMI=TL) satır yanlış sınıflansa bile TRY kal.
        const headerIsTry =
          headerDovizKullan === false ||
          (textOrNull(headerCurrencyValue) != null &&
            normalizeCurrency(headerCurrencyValue) === 'TRY');
        if (headerIsTry && currency !== 'TRY') {
          const tryAmountSum = rawItems.reduce(
            (sum, item) => sum + numberOrZero(item.amountsByCurrency?.TRY?.netTotal),
            0,
          );
          const foreignAmountSum = rawItems.reduce(
            (sum, item) =>
              sum + numberOrZero(item.amountsByCurrency?.FOREIGN?.netTotal),
            0,
          );
          // İkincil FX tutarı dolu olsa bile başlık TL ise KPB tutarını kullan.
          if (tryAmountSum > 0) {
            currency = 'TRY';
          } else if (foreignAmountSum <= 0) {
            currency = 'TRY';
          }
        }
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
      if (invoices.length) {
        const { resolveForInvoice } = await loadCrmInvoicesForAkinsoftMatch(
          query,
          invoices,
        );
        invoices = invoices
          .map((invoice) => {
            const row = resolveForInvoice(invoice);
            if (!row) return { ...invoice, importAction: 'new' };
            const active = row.is_active !== false;
            if (!active) {
              return {
                ...invoice,
                importAction: 'restore',
                existingInvoiceId: row.id,
              };
            }
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
            // Sağlıklı TL faturayı boş/döviz pull ile full rewrite etme.
            const crmIsHealthyTry =
              normalizeCurrency(row.currency) === 'TRY' &&
              numberOrZero(row.grand_total) > PAYMENT_CLOSE_TOLERANCE;
            const pulledIsEmptyForeign =
              normalizeCurrency(invoice.currency) !== 'TRY' &&
              numberOrZero(invoice.grandTotal) <= PAYMENT_CLOSE_TOLERANCE;
            if (crmIsHealthyTry && pulledIsEmptyForeign) {
              if (sameStatus) return null;
              return {
                ...invoice,
                importAction: 'update',
                updateKind: 'status',
                existingInvoiceId: row.id,
              };
            }
            // Sağlıklı TL'yi, zeytin FX tutarıyla USD gibi görünen pull ile ezme.
            // (KPBDVZ=1 satır + DOVIZ_BIRIMI=$ → yanlış USD 103.44 vs doğru TRY 4500)
            const pulledIsForeign =
              normalizeCurrency(invoice.currency) !== 'TRY' &&
              numberOrZero(invoice.grandTotal) > PAYMENT_CLOSE_TOLERANCE;
            if (crmIsHealthyTry && pulledIsForeign && !sameCurrency) {
              if (sameStatus) return null;
              return {
                ...invoice,
                importAction: 'update',
                updateKind: 'status',
                existingInvoiceId: row.id,
              };
            }
            // Yalnız ödeme/durum farkıysa tam yeniden yazım gereksiz.
            const updateKind = sameCurrency && sameTotal ? 'status' : 'full';
            return {
              ...invoice,
              importAction: 'update',
              updateKind,
              existingInvoiceId: row.id,
            };
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

    return {
      ok: true,
      database,
      tables: {
        FATURA: hasFatura,
        FATURAHR: hasFaturaHr,
        FATURA_KDV: hasFaturaKdv,
        CARI: hasCari,
        STOK: hasStok,
        HIZMET: hasHizmet,
        CARIHR: hasCariHr,
      },
      counts: {
        customers: customerCount || customers.length,
        products: productCount || products.length,
        stok: hasStok ? productCount - hizmetCount : 0,
        hizmet: hizmetCount,
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
    };
  } finally {
    await pool.close();
  }
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
  const data = await pullAkinsoftDataset(body);
  return send(
    res,
    200,
    { 'Content-Type': 'application/json; charset=utf-8' },
    JSON.stringify(data),
  );
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

  const actionable = [];
  for (const invoice of invoices) {
    const invoiceNumber = textOrNull(invoice.invoiceNumber);
    if (!invoiceNumber) continue;
    if (invoice.paymentReliable === false) {
      unreliable += 1;
      continue;
    }
    actionable.push(invoice);
  }

  const { resolveForInvoice } = await loadCrmInvoicesForAkinsoftMatch(
    query,
    actionable,
  );

  const updatesById = new Map();
  for (let index = 0; index < actionable.length; index += 1) {
    const invoice = actionable[index];
    const invoiceNumber = textOrNull(invoice.invoiceNumber);
    const existing =
      (invoice.existingInvoiceId
        ? { id: invoice.existingInvoiceId }
        : null) || resolveForInvoice(invoice);
    const invoiceId = textOrNull(existing?.id);
    if (!invoiceId) {
      notFound += 1;
      if (missing.length < 50 && invoiceNumber) missing.push(invoiceNumber);
      continue;
    }
    updatesById.set(invoiceId, {
      id: invoiceId,
      paidAmount: numberOrZero(invoice.paidAmount),
      status: textOrNull(invoice.status) || 'open',
      invoiceNumber,
    });
    if (
      index === 0 ||
      index + 1 === actionable.length ||
      (index + 1) % 50 === 0
    ) {
      reportProgress(index + 1, {
        stage: 'status',
        stageLabel: 'Fatura durumları güncelleniyor',
        total: invoices.length,
        invoiceNumber,
      });
    }
  }
  const updates = [...updatesById.values()];

  if (updates.length) {
    const result = await query(
      `
        update public.invoices i
        set paid_amount = v.paid_amount,
            status = v.status,
            updated_at = now()
        from (
          select *
          from unnest($1::uuid[], $2::numeric[], $3::text[])
            as t(id, paid_amount, status)
        ) v
        where i.id = v.id
          and (
            coalesce(i.paid_amount, 0) is distinct from v.paid_amount
            or coalesce(i.status, '') is distinct from v.status
          )
        returning i.id, i.status
      `,
      [
        updates.map((row) => row.id),
        updates.map((row) => row.paidAmount),
        updates.map((row) => row.status),
      ],
    );
    updated = result.rows.length;
    for (const row of result.rows) {
      const status = textOrNull(row.status) || 'open';
      if (statusCounts[status] != null) statusCounts[status] += 1;
    }
    unchanged = Math.max(0, updates.length - updated);
  }

  reportProgress(invoices.length, {
    stage: 'status',
    stageLabel: 'Fatura durumları güncellendi',
    total: invoices.length,
  });

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
  const { query, withTransaction } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
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
  let invoicesCreated = 0;
  let invoicesUpdated = 0;
  let invoiceItemsImported = 0;
  let customersMatchedBySource = 0;
  let customersMatchedByTax = 0;
  let customersMatchedByCode = 0;
  let customersCreated = 0;
  let invoicesSkippedMissingCustomerMatch = 0;
  let invoicesSkippedErrors = 0;
  const skippedInvoices = [];
  const invoiceWriteLog = [];

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
    stageLabel: 'Stok/hizmet kartları hazırlanıyor',
    total: products.length,
  });
  for (let productIndex = 0; productIndex < products.length; productIndex += 1) {
    const product = products[productIndex];
    const reportProductProgress = () => {
      const current = productIndex + 1;
      if (current === 1 || current === products.length || current % 10 === 0) {
        reportProgress(current, {
          stage: 'products',
          stageLabel: 'Stok/hizmet kartları hazırlanıyor',
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
    const productType =
      textOrNull(product.productType) === 'service' ? 'service' : 'product';
    const trackStock =
      product.trackStock === false || productType === 'service' ? false : true;
    const salePrice = numberOrZero(product.salePrice);
    const currency = normalizeCurrency(product.currency) || 'TRY';
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
            product_type = $11,
            track_stock = $12,
            sale_price = case when $13::numeric > 0 then $13 else sale_price end,
            currency = case
              when $13::numeric > 0 then coalesce($14, currency)
              when $14 is not null and $14 <> '' and coalesce(sale_price, 0) = 0
                then $14
              else currency
            end,
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
          resolveAkinsoftVatPercent(product),
          textOrNull(product.group),
          textOrNull(product.subGroup),
          sourceId,
          productType,
          trackStock,
          salePrice,
          currency,
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
          values ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, 0, true, $12, $13, $14)
          on conflict (code) do update set
            name = excluded.name,
            description = coalesce(excluded.description, public.products.description),
            category = coalesce(excluded.category, public.products.category),
            unit = excluded.unit,
            tax_rate = excluded.tax_rate,
            product_type = excluded.product_type,
            track_stock = excluded.track_stock,
            sale_price = case
              when excluded.sale_price > 0 then excluded.sale_price
              else public.products.sale_price
            end,
            currency = case
              when excluded.sale_price > 0 then coalesce(excluded.currency, public.products.currency)
              when coalesce(public.products.sale_price, 0) = 0
                then coalesce(excluded.currency, public.products.currency)
              else public.products.currency
            end,
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
          productType,
          textOrNull(product.unit) || 'Adet',
          numberOrZero(product.purchasePrice),
          salePrice,
          resolveAkinsoftVatPercent(product),
          currency,
          trackStock,
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
            sale_price, currency, track_stock, min_stock, is_active,
            akinsoft_group, akinsoft_sub_group, akinsoft_source_id
          )
          values ($1, $2, $3, $4, $5, $6, $7, $8, $9, 0, true, $10, $11, $12)
          returning id
        `,
        [
          name,
          textOrNull(product.description),
          textOrNull(product.category),
          productType,
          textOrNull(product.unit) || 'Adet',
          resolveAkinsoftVatPercent(product),
          salePrice,
          currency,
          trackStock,
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
      taxRate: resolveAkinsoftVatPercent(product),
      salePrice,
      currency,
      productType,
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
    // Kaynak BLKODU map / bellek önce — aynı VKN'li farklı carileri birleştirme.
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
    if (!customerId && invoiceTaxNumber) {
      const found = await query(
        `select id, name from public.customers where vkn = $1 order by created_at desc nulls last limit 5`,
        [invoiceTaxNumber],
      );
      const compatible = (found.rows || []).find((row) =>
        akinsoftCustomerNamesCompatible(invoice.customerName, row.name),
      );
      customerId = compatible?.id || null;
      if (customerId) customersMatchedByTax += 1;
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

    let writeAction = null;
    let invoiceId = null;
    let itemsWritten = 0;
    try {
      const result = await withTransaction(async (tx) => {
        const existing =
          (textOrNull(invoice.existingInvoiceId)
            ? await tx(
                `
                  select id, invoice_number, erp_invoice_number, e_invoice_number
                  from public.invoices
                  where id = $1::uuid
                  limit 1
                `,
                [invoice.existingInvoiceId],
              ).then((r) => (r.rows[0] ? { ...r.rows[0], matchMethod: 'preface' } : null))
            : null) ||
          (await findExistingCrmInvoiceForAkinsoft(tx, {
            sourceId: invoice.sourceId,
            numbers: [
              invoiceNumber,
              invoice.erpInvoiceNumber,
              invoice.eInvoiceNumber,
              invoice.officialEInvoiceNumber,
            ],
          }));

        let id = textOrNull(existing?.id);
        let action = id ? 'updated' : 'created';

        if (id) {
          const updated = await tx(
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
                erp_invoice_number = coalesce(nullif(trim(erp_invoice_number), ''), $14),
                e_invoice_status = case
                  when e_invoice_status = 'sent' then e_invoice_status
                  else 'manual'
                end,
                is_active = true,
                updated_at = now()
              where id = $1
              returning id
            `,
            [
              id,
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
          id = textOrNull(updated.rows[0]?.id);
          if (!id) {
            throw new Error(
              `CRM fatura satırı kayboldu (id eşleşmedi); kalem yazılmadı: ${invoiceNumber}`,
            );
          }
        } else {
          const inserted = await tx(
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
                erp_invoice_number = coalesce(
                  nullif(trim(public.invoices.erp_invoice_number), ''),
                  excluded.erp_invoice_number
                ),
                e_invoice_status = case
                  when public.invoices.e_invoice_status = 'sent' then public.invoices.e_invoice_status
                  else 'manual'
                end,
                is_active = true,
                updated_at = now()
              returning id, (xmax = 0) as inserted_new
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
          id = textOrNull(inserted.rows[0]?.id);
          if (!id) {
            throw new Error(`Fatura oluşturulamadı: ${invoiceNumber}`);
          }
          // on conflict path → update say.
          if (inserted.rows[0]?.inserted_new === false) action = 'updated';
        }

        await upsertAkinsoftSyncMap(tx, {
          sourceType: 'invoice',
          sourceId: invoice.sourceId,
          sourceCode: invoiceNumber,
          sourceName: invoice.customerName,
          localTable: 'invoices',
          localId: id,
        });
        await tx(
          `
            update public.invoices
            set erp_invoice_number = coalesce(nullif(trim(erp_invoice_number), ''), $2),
                updated_at = now()
            where id = $1
              and (
                erp_invoice_number is null
                or erp_invoice_number = ''
              )
          `,
          [id, invoiceNumber],
        );

        // Parent doğrulandıktan sonra kalemleri değiştir (tek transaction).
        await tx(`delete from public.invoice_items where invoice_id = $1`, [id]);
        let index = 0;
        let itemCount = 0;
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
          await tx(
            `
              insert into public.invoice_items (
                invoice_id, product_id, description, quantity, unit, unit_price,
                tax_rate, tax_amount, discount_rate, discount_amount, line_total,
                sort_order
              )
              values ($1, $2, $3, $4, $5, $6, $7, $8, 0, $9, $10, $11)
            `,
            [
              id,
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
          itemCount += 1;
        }
        await tx(
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
          [id, paymentReliable],
        );
        return { id, action, itemCount, matchMethod: existing?.matchMethod || null };
      });
      invoiceId = result.id;
      writeAction = result.action;
      itemsWritten = result.itemCount;
    } catch (error) {
      invoicesSkippedErrors += 1;
      skippedInvoices.push({
        invoiceNumber,
        customerSourceId: invoice.customerSourceId,
        customerCode: invoice.customerCode,
        customerName: invoice.customerName,
        reason: error instanceof Error ? error.message : String(error),
      });
      reportProgress(invoiceIndex + 1, {
        invoiceNumber,
        skipped: true,
        error: true,
      });
      continue;
    }

    if (writeAction === 'created') invoicesCreated += 1;
    else invoicesUpdated += 1;
    invoicesImported += 1;
    invoiceItemsImported += itemsWritten;
    if (invoiceWriteLog.length < 100) {
      invoiceWriteLog.push({
        invoiceNumber,
        invoiceId,
        action: writeAction,
      });
    }
    reportProgress(invoiceIndex + 1, {
      invoiceNumber,
      action: writeAction,
    });
  }

  console.log(
    `[akinsoft-import] invoices created=${invoicesCreated} updated=${invoicesUpdated} skipped_customer=${invoicesSkippedMissingCustomerMatch} skipped_error=${invoicesSkippedErrors} items=${invoiceItemsImported}`,
  );

  return {
    customers: customersImported,
    products: productsImported,
    productsCreated,
    productsUpdated,
    productsSkipped,
    invoices: invoicesImported,
    invoicesCreated,
    invoicesUpdated,
    invoiceItems: invoiceItemsImported,
    customerMatches: {
      source: customersMatchedBySource,
      tax: customersMatchedByTax,
      code: customersMatchedByCode,
      created: customersCreated,
    },
    skipped: {
      missingCustomerMatch: invoicesSkippedMissingCustomerMatch,
      errors: invoicesSkippedErrors,
      invoices: skippedInvoices,
      productsUnchanged: productsSkipped,
    },
    invoiceWriteLog,
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

// Tek aksiyon: SAP'tan yeni/değişen faturaları çek, ödeme-durum
// güncellemesini uygula, eşleşmiş yenileri içe aktar.
async function runAkinsoftPullAndUpdate(body, reportProgress) {
  const report = (current, extra = {}) => {
    if (!reportProgress) return;
    reportProgress({
      stage: extra.stage || 'pull',
      stageLabel: extra.stageLabel || 'SAP faturaları çekiliyor',
      current: Number.isFinite(current) ? current : 0,
      total: Number.isFinite(extra.total) ? extra.total : 1,
      invoiceNumber: extra.invoiceNumber ?? null,
      ...extra,
    });
  };

  report(0, {
    stage: 'pull',
    stageLabel: 'SAP faturaları çekiliyor',
    total: 1,
  });
  const pull = await pullAkinsoftDataset({
    ...body,
    syncMode: 'pull-and-update',
  });
  const invoices = Array.isArray(pull.invoices) ? pull.invoices : [];
  report(1, {
    stage: 'pull',
    stageLabel: 'SAP faturaları çekildi',
    total: 1,
  });

  const matched = (invoice) => invoice?.customerMatch?.matched === true;
  // status: yalnızca ödeme/durum farkı → hızlı sync
  // full / unmatched update: tam yeniden yazım veya sadece status (eşleşmeyen)
  const isStatusOnlyUpdate = (invoice) =>
    invoice.importAction === 'update' &&
    (invoice.updateKind === 'status' || !matched(invoice));
  const toStatusOnly = invoices.filter(isStatusOnlyUpdate);
  const toImport = invoices.filter(
    (invoice) =>
      matched(invoice) &&
      (invoice.importAction === 'new' ||
        invoice.importAction === 'restore' ||
        (invoice.importAction === 'update' && invoice.updateKind !== 'status')),
  );
  const needReview = invoices.filter(
    (invoice) =>
      !matched(invoice) &&
      (invoice.importAction === 'new' || invoice.importAction === 'restore'),
  );

  let statusSync = {
    checked: 0,
    updated: 0,
    unchanged: 0,
    notFound: 0,
    unreliable: 0,
    statusCounts: { paid: 0, partial: 0, open: 0 },
    missingInvoiceNumbers: [],
  };
  let importSummary = {
    customers: 0,
    products: 0,
    invoices: 0,
    invoiceItems: 0,
    productsCreated: 0,
    productsUpdated: 0,
    productsSkipped: 0,
  };

  if (toStatusOnly.length) {
    const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
    const statusResult = await syncAkinsoftInvoiceStatuses(
      query,
      toStatusOnly,
      (current, extra = {}) =>
        report(current, {
          stage: 'status',
          stageLabel: 'Ödeme/durum güncelleniyor',
          total: toStatusOnly.length,
          ...extra,
        }),
    );
    statusSync = statusResult.statusSync || statusSync;
  }

  if (toImport.length) {
    const selectedCustomerSources = new Set(
      toImport
        .map((invoice) => textOrNull(invoice.customerSourceId))
        .filter(Boolean),
    );
    const relatedCustomers = (Array.isArray(pull.customers) ? pull.customers : []).filter(
      (customer) => selectedCustomerSources.has(textOrNull(customer.sourceId)),
    );
    importSummary = await importAkinsoftDataset(
      {
        ...pull,
        settings: body,
        invoices: toImport,
        customers: relatedCustomers,
        products: Array.isArray(pull.products) ? pull.products : [],
        statusOnly: false,
      },
      ({ stage, stageLabel, current, total, invoiceNumber }) =>
        report(current, {
          stage: stage || 'invoices',
          stageLabel: stageLabel || 'Yeni faturalar yazılıyor',
          total,
          invoiceNumber,
        }),
    );

    const needsProductPush = toImport.some(
      (invoice) =>
        invoice.importAction === 'new' || invoice.importAction === 'restore',
    );
    if (needsProductPush) {
      try {
        report(0, {
          stage: 'products_push',
          stageLabel: 'CRM stokları Akınsoft’a yazılıyor',
          total: 1,
        });
        const sql = require('mssql');
        const { config } = buildAkinsoftSqlConfig(body);
        config.requestTimeout = Math.max(Number(config.requestTimeout || 0), 180000);
        const pool = await connectAkinsoftPool(config);
        try {
          const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
          importSummary.productsPush = await pushUnmappedCrmProductsToAkinsoft(
            pool,
            sql,
            query,
          );
        } finally {
          await pool.close();
        }
        report(1, {
          stage: 'products_push',
          stageLabel: 'CRM stokları yazıldı',
          total: 1,
        });
      } catch (error) {
        importSummary.productsPush = {
          created: 0,
          matched: 0,
          failed: 0,
          error: error?.message || String(error),
        };
      }
    } else {
      importSummary.productsPush = {
        created: 0,
        matched: 0,
        failed: 0,
        skipped: true,
      };
    }
  }

  const importedTotal = Number(importSummary.invoices || 0);
  const created = Number(
    importSummary.invoicesCreated != null
      ? importSummary.invoicesCreated
      : Math.min(
          toImport.filter((invoice) => invoice.importAction !== 'update').length,
          importedTotal,
        ),
  );
  const importedUpdates = Number(
    importSummary.invoicesUpdated != null
      ? importSummary.invoicesUpdated
      : Math.max(0, importedTotal - created),
  );
  const updated = Number(statusSync.updated || 0) + importedUpdates;
  const failed =
    Number(statusSync.notFound || 0) +
    Number(statusSync.unreliable || 0) +
    Number(importSummary.skipped?.missingCustomerMatch || 0) +
    Number(importSummary.skipped?.errors || 0) +
    Number(importSummary.productsPush?.failed || 0);

  console.log(
    `[akinsoft-pull-and-update] pulled=${invoices.length} created=${created} updated=${updated} failed=${failed} needReview=${needReview.length} statusUpdated=${statusSync.updated || 0} statusUnchanged=${statusSync.unchanged || 0}`,
  );

  return {
    ok: true,
    database: pull.database,
    tables: pull.tables,
    counts: pull.counts,
    warnings: pull.warnings,
    customers: pull.customers,
    products: pull.products,
    invoices: pull.invoices,
    needReviewInvoices: needReview,
    summary: {
      pulled: invoices.length,
      created,
      updated,
      failed,
      unchanged: Number(statusSync.unchanged || 0),
      needReview: needReview.length,
      statusSync,
      import: importSummary,
    },
    // Güvenli inceleme: uygulamak silmez; yalnızca mükerrer aday sorgusu.
    duplicateCheckHint:
      "select erp_invoice_number, e_invoice_number, invoice_number, count(*) from public.invoices where is_active is distinct from false group by 1,2,3 having count(*) > 1 order by count(*) desc limit 50;",
  };
}

async function handleAkinsoftPullAndUpdate(req, res) {
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
  const id =
    typeof crypto.randomUUID === 'function'
      ? crypto.randomUUID()
      : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
  const job = {
    id,
    type: 'pull-and-update',
    status: 'running',
    stage: 'pull',
    stageLabel: 'SAP faturaları çekiliyor',
    total: 1,
    current: 0,
    percent: 0,
    currentInvoiceNumber: null,
    summary: null,
    result: null,
    error: null,
    startedAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
  };
  akinsoftJobs.set(id, job);
  runAkinsoftPullAndUpdate(body, ({ stage, stageLabel, current, total, invoiceNumber }) => {
    job.stage = stage || job.stage;
    job.stageLabel = stageLabel || job.stageLabel;
    job.current = Number.isFinite(current) ? current : job.current;
    job.total = Number.isFinite(total) ? total : job.total;
    job.currentInvoiceNumber = invoiceNumber || null;
    job.percent = job.total ? Math.floor((job.current / job.total) * 100) : 0;
    job.updatedAt = new Date().toISOString();
  })
    .then((result) => {
      job.status = 'done';
      job.current = job.total;
      job.percent = 100;
      job.summary = result.summary;
      job.result = result;
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

// FATURA UPDATE'ini kendi transaction bağlantısında çalıştırır.
// Kilit beklerken (lazy) engelleyiciyi yakalar; hızlı başarıda DMV maliyeti yok.
async function monitoredFaturaUpdate(pool, sql, whereSql, binder) {
  const tx = new sql.Transaction(pool);
  await tx.begin();
  let mon = null;
  try {
    const sp = await new sql.Request(tx).query('select @@spid as spid');
    const spid = Number(sp.recordset?.[0]?.spid);
    const req = new sql.Request(tx);
    binder(req);
    const updateP = req.query(`
      set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS};
      update dbo.FATURA set FATURA_NO = @newNumber where ${whereSql};
      select @@rowcount as affected;
    `);
    mon = startAkinsoftLockMonitor(pool, sql, spid);
    try {
      const res = await updateP;
      await mon.done();
      const affected = Number(res.recordset?.[0]?.affected || 0);
      await tx.commit();
      return { affected, errNo: 0, selfWait: mon.selfWait };
    } catch (e) {
      await mon.done();
      try { await tx.rollback(); } catch (_) {}
      const errNo = Number(e?.number ?? e?.originalError?.info?.number ?? 0);
      return { affected: 0, errNo, selfWait: mon.selfWait };
    }
  } catch (e) {
    if (mon) await mon.done();
    try { await tx.rollback(); } catch (_) {}
    return {
      affected: 0,
      errNo: Number(e?.number ?? e?.originalError?.info?.number ?? 0),
      selfWait: mon?.selfWait || null,
    };
  }
}

async function attemptWriteAkinsoftInvoiceNumber(pool, sql, item) {
  const newNumber = textOrNull(item.newNumber);
  const sourceId = textOrNull(item.sourceId);
  let oldNumber = textOrNull(item.oldNumber);
  if (!newNumber) {
    return { ok: false, reason: 'Yeni fatura numarası yok.' };
  }
  let blkodu = Number(sourceId);
  if (!Number.isFinite(blkodu)) blkodu = null;

  // Okumalar NOLOCK + autocommit (kilit beklemez).
  try {
    if (blkodu != null) {
      const cur = await pool.request().input('b', sql.BigInt, blkodu).query(
        `set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS}; select top 1 FATURA_NO as n from dbo.FATURA with (nolock) where BLKODU = @b`,
      );
      const c = textOrNull(cur.recordset?.[0]?.n);
      if (c) oldNumber = c;
    }
    if (oldNumber && oldNumber === newNumber) {
      return { ok: true, skipped: true, reason: 'Numara zaten aynı.', oldNumber };
    }
    const existing = await pool.request()
      .input('newNumber', sql.NVarChar(64), newNumber)
      .input('b', sql.BigInt, blkodu)
      .query(`set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS}; select top 1 cast(BLKODU as nvarchar(64)) as sourceId from dbo.FATURA with (nolock) where FATURA_NO = @newNumber and (@b is null or BLKODU <> @b)`);
    if (existing.recordset?.length) {
      return {
        ok: false,
        reason: `Akınsoft’ta ${newNumber} numarası başka bir faturada kullanılıyor.`,
        oldNumber,
        conflictSourceId: String(existing.recordset[0].sourceId),
      };
    }
    if (blkodu == null && oldNumber) {
      const r = await pool.request().input('o', sql.NVarChar(64), oldNumber).query(
        `set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS}; select top 1 BLKODU as b from dbo.FATURA with (nolock) where FATURA_NO = @o`,
      );
      const b = Number(r.recordset?.[0]?.b);
      if (Number.isFinite(b)) blkodu = b;
    }
  } catch (error) {
    return {
      ok: false,
      reason: describeAkinsoftSqlError(error),
      oldNumber,
      __lock: isAkinsoftLockError(error),
      sqlError: extractAkinsoftSqlError(error),
      phase: 'read',
    };
  }

  // Ana güncelleme — canlı bekleme yakalama ile.
  // Yalnızca BLKODU ile güncelle: FATURA_NO unique değil; no ile update
  // aynı STŞ’li birden fazla satırı tek seferde Maliye no’ya çevirir.
  let upd;
  if (blkodu != null) {
    upd = await monitoredFaturaUpdate(pool, sql, 'BLKODU = @b', (r) => {
      r.input('newNumber', sql.NVarChar(64), newNumber);
      r.input('b', sql.BigInt, blkodu);
    });
  } else {
    return {
      ok: false,
      reason: 'Akınsoft fatura eşlemesi (BLKODU) bulunamadı.',
      oldNumber,
    };
  }

  if (upd.errNo) {
    const lockFail = upd.errNo === 1222;
    return {
      ok: false,
      reason: lockFail
        ? describeAkinsoftLockReasonFromEvidence({ selfWait: upd.selfWait })
        : describeAkinsoftSqlError({ number: upd.errNo }),
      oldNumber,
      __lock: lockFail,
      sqlError: {
        number: upd.errNo,
        message: lockFail
          ? 'Lock request time out period exceeded.'
          : `SQL error ${upd.errNo}`,
      },
      selfWait: upd.selfWait || null,
      phase: 'update',
    };
  }
  if (!upd.affected) {
    return {
      ok: false,
      reason: oldNumber
        ? `Akınsoft’ta ${oldNumber} numaralı fatura bulunamadı.`
        : 'Akınsoft fatura eşlemesi (BLKODU) bulunamadı.',
      oldNumber,
      selfWait: upd.selfWait || null,
    };
  }

  let cariHrUpdated = null;
  if (oldNumber && oldNumber !== newNumber && blkodu != null) {
    try {
      // SADECE bu faturaya bağlı hareketler — aynı STŞ no ile
      // birden fazla CARIHR varsa hepsini tek Maliye no’ya çekmeyi engeller.
      await pool.request()
        .input('o', sql.NVarChar(64), oldNumber)
        .input('newNumber', sql.NVarChar(64), newNumber)
        .input('fto', sql.NVarChar(40), `FTO_${blkodu}`)
        .input('ftk', sql.NVarChar(40), `FTK_${blkodu}`)
        .query(`
          set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS};
          update dbo.CARIHR
          set EVRAK_NO = @newNumber
          where EVRAK_NO = @o
            and (
              ENTEGRASYON = @fto
              or ENTEGRASYON = @ftk
            )
        `);
      cariHrUpdated = true;
    } catch (_) {
      cariHrUpdated = false;
    }
  } else if (oldNumber && oldNumber !== newNumber) {
    // BLKODU yoksa eski geniş güncelleme yerine güvenli red.
    cariHrUpdated = false;
  }
  return { ok: true, updated: upd.affected, oldNumber, sourceId: blkodu != null ? String(blkodu) : null, cariHrUpdated, selfWait: upd.selfWait || null };
}

// Kilit garantisi: FATURA'da OBJECT kilidi tutan ve belirli süredir işlem
// yapmayan (bayat/asılı) WOLVOX oturumlarını bulur ve KILL eder. Aktif kullanıcıyı
// vurmamak için yalnızca last_request_start_time eşiği geçmiş oturumları hedefler.
// 'sa' sysadmin olduğundan KILL yetkisi vardır. Öldürülen oturumları döndürür.
async function killStaleAkinsoftFaturaLockers(pool, sql, maxAgeSeconds) {
  const maxAge = Math.max(
    Number(
      maxAgeSeconds ?? process.env.AKINSOFT_KILL_STALE_AFTER_SEC ?? 20,
    ) || 20,
    5,
  );
  const killed = [];
  try {
    const found = await pool.request().input('maxAge', sql.Int, maxAge).query(`
      set lock_timeout 4000;
      select distinct
        es.session_id as sessionId,
        es.program_name as programName,
        es.host_name as hostName,
        datediff(second, es.last_request_start_time, getdate()) as ageSeconds,
        es.status as status
      from sys.dm_exec_sessions es
      join sys.dm_tran_locks tl
        on tl.request_session_id = es.session_id
      where es.session_id <> @@spid
        and es.is_user_process = 1
        and (
          es.program_name like '%WERP%'
          or es.program_name like '%Wolvox%'
          or es.program_name like '%WOLVOX%'
          or es.program_name like '%AKINSOFT%'
        )
        and tl.resource_database_id = db_id()
        and es.open_transaction_count > 0
        and es.status = 'sleeping'
        and es.last_request_start_time < dateadd(second, -@maxAge, getdate())
    `);
    for (const row of found.recordset || []) {
      const sid = Number(row.sessionId);
      if (!Number.isFinite(sid)) continue;
      try {
        await pool.request().query(`kill ${sid}`);
        killed.push({
          sessionId: sid,
          programName: textOrNull(row.programName),
          hostName: textOrNull(row.hostName),
          ageSeconds: Number(row.ageSeconds) || null,
        });
      } catch (e) {
        killed.push({
          sessionId: sid,
          programName: textOrNull(row.programName),
          hostName: textOrNull(row.hostName),
          killError: String(e?.message || e),
        });
      }
    }
  } catch (_) {
    // tespit/temizlik opsiyonel
  }
  return killed;
}

// Numara güncelleme sarmalayıcısı: 1222'de bayat WOLVOX temizliği + backoff retry.
async function writeAkinsoftInvoiceNumber(pool, sql, item) {
  return withAkinsoftLockRetry(
    async (attempt) => {
      let result = await attemptWriteAkinsoftInvoiceNumber(pool, sql, item);
      if (result.ok || !result.__lock) {
        return result;
      }
      // İlk kilit denemesinde bayat WOLVOX oturumlarını bir kez temizle.
      if (attempt === 0) {
        const killed = await killStaleAkinsoftFaturaLockers(pool, sql).catch(
          () => [],
        );
        result.killedSessions = killed;
        if (killed.length) {
          await sleepMs(250);
          const retry = await attemptWriteAkinsoftInvoiceNumber(pool, sql, item);
          retry.killedSessions = killed;
          return retry;
        }
      }
      return result;
    },
    { label: 'push-invoice-number' },
  );
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
  const key = `${String(tableName || '').toUpperCase()}.${String(columnName || '').toUpperCase()}`;
  if (_akinsoftSchemaCache.identity.has(key)) {
    return _akinsoftSchemaCache.identity.get(key);
  }
  const result = await pool.request().query(`
    select COLUMNPROPERTY(
      OBJECT_ID(N'dbo.${String(tableName).replace(/'/g, "''")}'),
      N'${String(columnName).replace(/'/g, "''")}',
      'IsIdentity'
    ) as is_identity
  `);
  const ok = Number(result.recordset?.[0]?.is_identity) === 1;
  _akinsoftSchemaCache.identity.set(key, ok);
  return ok;
}

/**
 * Wolvox BLKODU allocator: SQL Server sequence dbo.{TABLE}_GEN via
 * SP_GEN_ID + NEXT VALUE FOR (see e.g. STOK_FIYAT_SFD_TRG).
 * Never use bare max(BLKODU)+1 — it steals IDs the sequence will reissue.
 *
 * requestFactory (opsiyonel): () => sql.Request — açık transaction bağlantısı.
 * TX açıkken pool.request() ile max(BLKODU) almak, diğer havuz oturumunun
 * kendi X kilitlerine çarpıp 1222 self-lock üretir.
 */
async function akinsoftNextBlkoduSafe(pool, tableName, requestFactory) {
  const sql = require('mssql');
  const safe = String(tableName || '').replace(/[^A-Za-z0-9_]/g, '');
  if (!safe) throw new Error('Geçersiz tablo adı.');
  const genName = `${safe}_GEN`;
  const newRequest = () =>
    typeof requestFactory === 'function' ? requestFactory() : pool.request();

  const maxResult = await newRequest().query(`
    set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS};
    select isnull(max(try_convert(bigint, BLKODU)), 0) as max_id
    from dbo.${safe} with (nolock)
  `);
  const maxId = Number(maxResult.recordset?.[0]?.max_id || 0);

  let seqCurrent = null;
  try {
    const seqResult = await newRequest().query(`
      select convert(bigint, current_value) as cv
      from sys.sequences
      where schema_id = schema_id(N'dbo') and name = N'${genName}'
    `);
    if (seqResult.recordset?.[0]?.cv != null) {
      seqCurrent = Number(seqResult.recordset[0].cv);
    }
  } catch (_) {
    seqCurrent = null;
  }

  if (seqCurrent == null) {
    // Ensure sequence exists (encrypted SP_GEN_ID creates {name} sequence when missing).
    try {
      const genReq = newRequest();
      genReq.input('GEN_NAME', sql.VarChar(32), genName);
      genReq.input('INCREMENT', sql.Int, 1);
      genReq.output('GEN_VALUE', sql.BigInt);
      await genReq.execute('dbo.SP_GEN_ID');
    } catch (_) {
      // Fall through to max+1 if sequence cannot be created.
    }
    try {
      const seqResult = await newRequest().query(`
        select convert(bigint, current_value) as cv
        from sys.sequences
        where schema_id = schema_id(N'dbo') and name = N'${genName}'
      `);
      if (seqResult.recordset?.[0]?.cv != null) {
        seqCurrent = Number(seqResult.recordset[0].cv);
      }
    } catch (_) {
      seqCurrent = null;
    }
  }

  if (seqCurrent != null) {
    // Sequence current_value is last issued. If behind table max, restart so
    // NEXT VALUE returns maxId+1 (same IDs Wolvox would otherwise collide on).
    if (seqCurrent < maxId) {
      await newRequest().query(`
        alter sequence dbo.${genName} restart with ${maxId + 1}
      `);
    }
    const nextResult = await newRequest().query(`
      select next value for dbo.${genName} as next_id
    `);
    const nextId = Number(nextResult.recordset?.[0]?.next_id);
    if (Number.isFinite(nextId) && nextId > 0) return nextId;
  }

  return maxId + 1;
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

/** Aynı değeri listedeki tüm mevcut kolonlara yazar (Akınsoft UI farklı alan okuyabilir). */
function setAllColumns(target, columns, names, value) {
  if (value === undefined) return 0;
  let count = 0;
  for (const name of names) {
    const key = String(name).toUpperCase();
    if (columns.has(key)) {
      target[key] = value;
      count += 1;
    }
  }
  return count;
}

function akinsoftCurrencySymbol(currency) {
  const code = normalizeCurrency(currency);
  if (code === 'USD') return '$';
  if (code === 'EUR') return '€';
  if (code === 'GBP') return '£';
  return code === 'TRY' ? 'TL' : code;
}

async function resolveAkinsoftFxRates(pool, currency, exchangeRate) {
  const symbol = akinsoftCurrencySymbol(currency);
  // Faturadaki CRM kuru SAP/Akınsoft'a gitmeli (oluşturulurken güncel satış kuru).
  const crmRate = Math.max(Number(exchangeRate) || 0, 0);
  let alis = crmRate > 0 ? crmRate : 0.000001;
  let satis = crmRate > 0 ? crmRate : 0.000001;
  try {
    const result = await pool
      .request()
      .input('sym', sql.NVarChar(16), symbol)
      .input('code', sql.NVarChar(16), normalizeCurrency(currency))
      .query(`
        select top 1
          cast(ALIS_FIYATI as float) as alis,
          cast(SATIS_FIYATI as float) as satis
        from dbo.DOVIZ
        where convert(nvarchar(16), DOVIZ_BIRIMI) in (@sym, @code)
           or convert(nvarchar(16), DOVIZ_SIMGESI) = @sym
        order by TARIHI desc
      `);
    const row = result.recordset?.[0];
    if (crmRate > 0) {
      // Satış = CRM fatura kuru. Alış: DOVIZ yakınsa onu kullan, değilse CRM.
      satis = crmRate;
      const dovizAlis = Number(row?.alis) || 0;
      if (dovizAlis > 0 && Math.abs(dovizAlis - crmRate) / crmRate <= 0.25) {
        alis = dovizAlis;
      } else {
        alis = crmRate;
      }
    } else {
      if (row?.alis > 0) alis = Number(row.alis);
      if (row?.satis > 0) satis = Number(row.satis);
    }
  } catch (_) {
    // DOVIZ tablosu yoksa CRM kuru ile devam.
  }
  return { symbol, alis, satis };
}

async function resolveAkinsoftDefaultDepo(pool, sql) {
  try {
    const ayar = await pool.request().query(`
      select top 1
        convert(nvarchar(64), DEPO_ADI) as depoAdi,
        cast(DEPO_KULLAN as int) as depoKullan
      from dbo.AYAR
    `);
    const fromAyar = textOrNull(ayar.recordset?.[0]?.depoAdi);
    if (fromAyar) return fromAyar;
  } catch (_) {
    // AYAR.depo yoksa DEPO tablosuna bak.
  }
  try {
    const depo = await pool.request().query(`
      select top 1 convert(nvarchar(64), DEPO_ADI) as depoAdi
      from dbo.DEPO
      where coalesce(AKTIF, 1) = 1
      order by case when upper(convert(nvarchar(64), DEPO_ADI)) = N'ANA DEPO' then 0 else 1 end,
               BLKODU
    `);
    const fromDepo = textOrNull(depo.recordset?.[0]?.depoAdi);
    if (fromDepo) return fromDepo;
  } catch (_) {
    // ignore
  }
  return 'ANA DEPO';
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
  // Trigger'lı tablolarda (CARIHR vb.) OUTPUT without INTO hata verir.
  const result = await request.query(`
    declare @out table (BLKODU nvarchar(64));
    insert into dbo.${safeTable} (${colSql.join(', ')})
    output inserted.BLKODU into @out
    values (${valSql.join(', ')});
    select BLKODU from @out;
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

/** Döviz faturada cari kartında DOVIZ_KULLAN yoksa form TL açılır / cari değişimi hata verir. */
async function ensureAkinsoftCariFxEnabled(pool, sql, customerSourceId, currency) {
  const sourceId = Number(customerSourceId);
  if (!Number.isFinite(sourceId)) return false;
  const symbol = akinsoftCurrencySymbol(currency);
  if (!symbol || symbol === 'TL' || normalizeCurrency(currency) === 'TRY') {
    return false;
  }
  const columns = await akinsoftTableColumnSet(pool, 'CARI');
  if (!columns.has('DOVIZ_KULLAN') && !columns.has('DOVIZ_BIRIMI')) {
    return false;
  }
  const result = await pool
    .request()
    .input('id', sql.BigInt, sourceId)
    .input('symbol', sql.VarChar(4), symbol)
    .query(`
      update dbo.CARI
      set
        DOVIZ_KULLAN = coalesce(DOVIZ_KULLAN, 1),
        DOVIZ_BIRIMI = coalesce(nullif(ltrim(rtrim(DOVIZ_BIRIMI)), ''), @symbol)
      where BLKODU = @id
        and (
          DOVIZ_KULLAN is null
          or DOVIZ_KULLAN = 0
          or nullif(ltrim(rtrim(convert(varchar(8), DOVIZ_BIRIMI))), '') is null
        );
      select @@rowcount as updated;
    `);
  return Number(result.recordset?.[0]?.updated || 0) > 0;
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
  const customerCurrency = normalizeCurrency(
    customer.currency || customer.default_currency,
  );
  if (customerCurrency && customerCurrency !== 'TRY') {
    setFirstColumn(values, columns, ['DOVIZ_KULLAN'], 1);
    setFirstColumn(
      values,
      columns,
      ['DOVIZ_BIRIMI'],
      akinsoftCurrencySymbol(customerCurrency),
    );
  }

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
  const vatPercent = resolveAkinsoftVatPercent(product);
  setFirstColumn(values, columns, ['KDV_ORANI'], vatPercent);
  setFirstColumn(values, columns, ['KDV_ORANI_ALIS'], vatPercent);
  setFirstColumn(values, columns, ['KDV_ORANI_SATIS_TPT'], vatPercent);
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
        and coalesce(p.product_type, 'product') <> 'service'
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
          reason: describeAkinsoftSqlError(error),
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
    currency: invoice.currency,
  });
}

async function attemptWriteAkinsoftInvoiceCreate(pool, sql, query, invoice) {
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

  // Cari arama/oluşturma, mükerrer FATURA kontrolü ve stok/döviz sorguları da
  // transaction dışında çalışır; bu bağlantıya da kilit sınırı uygula.
  await applyAkinsoftLockTimeout(pool);

  const existingMap = await findAkinsoftSourceByLocalId(query, 'invoice', invoiceId);
  if (existingMap?.source_id) {
    await setInvoiceAkinsoftSyncStatus(query, invoiceId, 'synced');
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

  const duplicate = await findExistingAkinsoftFaturaByNumbers(pool, sql, [
    invoiceNumber,
    maliyeNumber,
    invoice.erp_invoice_number,
    invoice.invoice_number,
  ]);
  if (duplicate?.sourceId || duplicate?.orphanCariHr) {
    if (duplicate.sourceId) {
      await upsertAkinsoftSyncMap(query, {
        sourceType: 'invoice',
        sourceId: String(duplicate.sourceId),
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
              akinsoft_sync_status = 'synced',
              akinsoft_synced_at = now(),
              akinsoft_sync_error = null,
              updated_at = now()
          where id = $1::uuid
        `,
        [invoiceId, invoiceNumber],
      );
      return {
        ok: true,
        skipped: true,
        reason: duplicate.orphanCariHr
          ? 'Akınsoft’ta aynı numaralı cari hareket vardı; FATURA satırı yok/eksik — yeni fatura oluşturulmadı, eşleme güncellendi.'
          : duplicate.matchCount > 1
            ? `Akınsoft’ta aynı numaralı ${duplicate.matchCount} fatura vardı; ilkine eşlendi, yeni kayıt yazılmadı.`
            : 'Akınsoft’ta aynı numaralı fatura vardı; eşleme güncellendi.',
        sourceId: String(duplicate.sourceId),
        invoiceNumber,
      };
    }
    return {
      ok: false,
      reason:
        `Akınsoft’ta ${invoiceNumber} için fatura başlığı olmadan cari hareket var (muhtemel mükerrer/orphan). ` +
        'Yeni FATURA yazılmadı — WOLVOX’ta manuel kontrol edin.',
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
  const fxRates = isTry
    ? { symbol: 'TL', alis: 1, satis: 1 }
    : await resolveAkinsoftFxRates(pool, currency, exchangeRate);
  const kpbRate = isTry ? 1 : Math.max(Number(fxRates.satis) || exchangeRate, 0.000001);
  // Cari kartında döviz kapalıysa Wolvox fatura formunu TL açar.
  if (!isTry) {
    await ensureAkinsoftCariFxEnabled(pool, sql, customerSourceId, currency);
  }
  const defaultDepo = await resolveAkinsoftDefaultDepo(pool, sql);
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
    const lineNotes = (() => {
      const name = String(description || '')
        .trim()
        .toLocaleLowerCase('tr-TR');
      for (const candidate of [item.notes, item.aciklama, item.line_description]) {
        const value = textOrNull(candidate);
        if (!value) continue;
        if (name && value.toLocaleLowerCase('tr-TR') === name) continue;
        return value;
      }
      return null;
    })();
    linePayloads.push({
      productSourceId: Number.isFinite(productSourceId) ? productSourceId : null,
      productCode: Number.isFinite(productSourceId) ? productCode : null,
      description,
      notes: lineNotes,
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
  const kpbFactor = isTry ? 1 : kpbRate;
  const kpbSubtotal = isTry ? subtotal : subtotal * kpbFactor;
  const kpbDiscount = isTry ? discountTotal : discountTotal * kpbFactor;
  const kpbTax = isTry ? taxTotal : taxTotal * kpbFactor;
  const kpbGrand = isTry ? grandTotal : grandTotal * kpbFactor;

  const faturaIdentity = await akinsoftColumnIsIdentity(pool, 'FATURA', 'BLKODU');
  const lineIdentity = await akinsoftColumnIsIdentity(pool, 'FATURAHR', 'BLKODU');

  // TX açılmadan metadata + BLKODU rezervasyonu. TX sırasında pool.request()
  // (ayrı bağlantı) ile max(BLKODU)/metadata almak self-lock 1222 üretir.
  const hasFaturaKur =
    !isTry && (await akinsoftTableExists(pool, 'FATURA_KUR'));
  const kurColumns = hasFaturaKur
    ? await akinsoftTableColumnSet(pool, 'FATURA_KUR')
    : null;
  const kurIdentity = hasFaturaKur
    ? await akinsoftColumnIsIdentity(pool, 'FATURA_KUR', 'BLKODU')
    : true;
  const hasFaturaKdv = await akinsoftTableExists(pool, 'FATURA_KDV');
  const kdvColumns = hasFaturaKdv
    ? await akinsoftTableColumnSet(pool, 'FATURA_KDV')
    : null;
  const kdvIdentity = hasFaturaKdv
    ? await akinsoftColumnIsIdentity(pool, 'FATURA_KDV', 'BLKODU')
    : true;
  const cariHrIdentity =
    hasCariHr && cariHrColumns.size
      ? await akinsoftColumnIsIdentity(pool, 'CARIHR', 'BLKODU')
      : true;

  const kdvRates = (() => {
    const byRate = new Map();
    for (const line of linePayloads) {
      const rate = Number(line.taxRate) || 0;
      const cur = byRate.get(rate) || { matrah: 0, tax: 0 };
      cur.matrah += isTry ? line.net : line.net * kpbFactor;
      cur.tax += isTry ? line.tax : line.tax * kpbFactor;
      byRate.set(rate, cur);
    }
    return byRate;
  })();

  let reservedFaturaBlkodu = null;
  const reservedLineBlkodus = [];
  let reservedKurBlkodu = null;
  let reservedCariHrBlkodu = null;
  const reservedKdvBlkodus = [];
  try {
    if (!faturaIdentity) {
      reservedFaturaBlkodu = await akinsoftNextBlkoduSafe(pool, 'FATURA');
    }
    // Her satır için sequence'den ayrı ID al. Tek ID + lineBlkodu++ sequence'i
    // geride bırakır; Wolvox sonraki SP_GEN_ID ile PK çakışması üretir.
    if (!lineIdentity) {
      for (let i = 0; i < linePayloads.length; i += 1) {
        reservedLineBlkodus.push(await akinsoftNextBlkoduSafe(pool, 'FATURAHR'));
      }
    }
    if (hasFaturaKur && !kurIdentity) {
      reservedKurBlkodu = await akinsoftNextBlkoduSafe(pool, 'FATURA_KUR');
    }
    if (hasFaturaKdv && !kdvIdentity) {
      for (let i = 0; i < kdvRates.size; i += 1) {
        reservedKdvBlkodus.push(await akinsoftNextBlkoduSafe(pool, 'FATURA_KDV'));
      }
    }
    if (hasCariHr && cariHrColumns.size && !cariHrIdentity) {
      reservedCariHrBlkodu = await akinsoftNextBlkoduSafe(pool, 'CARIHR');
    }
  } catch (error) {
    return {
      ok: false,
      reason: isAkinsoftLockError(error)
        ? describeAkinsoftLockReasonFromEvidence({})
        : describeAkinsoftSqlError(error),
      __lock: isAkinsoftLockError(error),
      sqlError: extractAkinsoftSqlError(error),
      phase: 'reserve',
    };
  }

  const transaction = new sql.Transaction(pool);
  await transaction.begin();
  let createSelfWait = null;
  let mon = null;
  try {
    const sp = await new sql.Request(transaction).query('select @@spid as spid');
    mon = startAkinsoftLockMonitor(pool, sql, Number(sp.recordset?.[0]?.spid));
  } catch (_) {}
  try {
    const txRequest = () => new sql.Request(transaction);
    // Bu transaction'ın bağlantısında kilit beklemesini sınırla; WOLVOX kaydı
    // kilitliyse INSERT 180 sn asılı kalmak yerine ~15 sn'de 1222 hatası verir.
    await txRequest().query(`set lock_timeout ${AKINSOFT_LOCK_TIMEOUT_MS}`);
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
      // Trigger'lı tablolarda OUTPUT ... without INTO hata verir; tablo değişkenine al.
      const result = await request.query(`
        declare @out table (BLKODU nvarchar(64));
        insert into dbo.${safeTable} (${colSql.join(', ')})
        output inserted.BLKODU into @out
        values (${valSql.join(', ')});
        select BLKODU from @out;
      `);
      return result.recordset?.[0]?.BLKODU == null
        ? null
        : String(result.recordset[0].BLKODU);
    };

    const header = {};
    if (!faturaIdentity) {
      header.BLKODU = reservedFaturaBlkodu;
    }
    setFirstColumn(header, faturaColumns, ['FATURA_NO'], invoiceNumber);
    setFirstColumn(header, faturaColumns, ['TARIHI'], invoiceDate);
    // Dönem kilidi: KAYIT_TARIHI native faturalarda dolu; boşsa "önceki dönem" hatası.
    // TARIHI2 computed (TARIHI'den türetilir) — yazılmaz.
    setFirstColumn(header, faturaColumns, ['KAYIT_TARIHI'], invoiceDate);
    setFirstColumn(header, faturaColumns, ['KAYDEDEN'], 'CRM');
    if (dueDate) {
      setFirstColumn(header, faturaColumns, ['VADESI'], toSqlDateOnly(dueDate, dueDate));
    }
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
    setFirstColumn(header, faturaColumns, ['KUR', 'DOVIZ_KURU'], kpbRate);
    setFirstColumn(
      header,
      faturaColumns,
      ['DOVIZ_KULLAN', 'DOVIZLI', 'DVZ_KULLAN'],
      isTry ? 0 : 1,
    );
    // Native/referans FX faturalarda KPBDVZ_CARI=1 (form "Kullanılan Cari Hesabı" ile birlikte).
    setFirstColumn(header, faturaColumns, ['KPBDVZ_CARI'], 1);
    setFirstColumn(
      header,
      faturaColumns,
      ['DOVIZ_BIRIMI', 'DOVIZ_ADI', 'DVZ_BIRIMI', 'PARA_BIRIMI', 'DOVIZ'],
      fxRates.symbol,
    );
    // Referans döviz faturası (…021) ile aynı zorunlu bayraklar.
    setFirstColumn(header, faturaColumns, ['FATURA_TIPI'], 1);
    setFirstColumn(header, faturaColumns, ['KDV_DURUMU'], 0);
    setFirstColumn(
      header,
      faturaColumns,
      ['KDV_ORANI'],
      linePayloads[0] ? linePayloads[0].taxRate : 0,
    );
    setFirstColumn(header, faturaColumns, ['CARIHRK_ISLE'], 1);
    setFirstColumn(header, faturaColumns, ['STOKHRK_ISLE'], 1);
    setFirstColumn(header, faturaColumns, ['DVZ_HSISLE_STOK'], isTry ? 0 : 1);
    setFirstColumn(header, faturaColumns, ['DVZ_HSISLE_CARI'], 0);
    setFirstColumn(header, faturaColumns, ['YUVARLAMA_KULLAN'], 1);
    setFirstColumn(header, faturaColumns, ['KUL_STOK_FIYATI'], 1);
    setFirstColumn(header, faturaColumns, ['EFATURA_KULLAN'], 0);
    setFirstColumn(header, faturaColumns, ['EFATURA_DURUM'], 1);
    setFirstColumn(header, faturaColumns, ['EFATURA_TURU'], 1);
    setFirstColumn(header, faturaColumns, ['SILINDI'], 0);
    setFirstColumn(header, faturaColumns, ['IPTAL'], 0);
    setFirstColumn(header, faturaColumns, ['FATURA_KESILDI'], 0);
    setFirstColumn(header, faturaColumns, ['VADE_DURUMU'], 0);
    setFirstColumn(header, faturaColumns, ['OTV_KULLAN'], 0);
    setFirstColumn(header, faturaColumns, ['OIV_KULLAN'], 0);
    setAllColumns(
      header,
      faturaColumns,
      ['MIKTAR1_TOPLAM', 'MIKTAR2_TOPLAM'],
      linePayloads.reduce((sum, line) => sum + (Number(line.quantity) || 0), 0),
    );
    // Wolvox formu NULL ile 0'ı farklı okuyor; referans faturadaki gibi sıfırla.
    for (const zeroCol of [
      'ISK_KUL_CARI',
      'ISK_ORAN_CARI',
      'ISK_TUTAR_CARI',
      'ISK_KUL_1',
      'ISK_ORAN_1',
      'ISK_TUTAR_1',
      'ISK_KUL_2',
      'ISK_ORAN_2',
      'ISK_TUTAR_2',
      'ISK_KUL_3',
      'ISK_ORAN_3',
      'ISK_TUTAR_3',
      'ISK_KUL_STOK',
      'ISK_TUTAR_STOK',
      'ISK_KUL_OZEL',
      'ISK_TUTAR_OZEL',
      'ISK_KUL_ALT',
      'ISK_ORAN_ALT',
      'ISK_TUTAR_ALT1',
      'ISK_TUTAR_ALT2',
      'TOPLAM_ISK_STOK',
      'TOPLAM_ISK_FAT',
      'TOPLAM_ISK_YUZDESI',
      'TOPLAM_OTV_KPB',
      'TOPLAM_OTV_DVZ',
      'YUVARLAMA_KPB',
      'YUVARLAMA_DVZ',
      'PAZ_DURUMU',
      'GM_ENTEGRASYON',
      'IHRAC_KAYDI',
      'BONUS_ISLE',
      'TEVKIFAT_LIMIT_KULLAN',
      'TEVKIFAT_TUTARI_KPB',
      'TEVKIFAT_TUTARI_DVZ',
      'ORTALAMA_VADE',
      'TOPLAM_OIV_KPB',
      'TOPLAM_OIV_DVZ',
      'YDF_DVZ_EKUC_SIGORTA',
      'YDF_DVZ_EKUC_NAVLUN',
      'YDF_DVZ_EKUC_GUMRUK',
      'ISK_TUTAR_CARI_DVZ',
      'ISK_TUTAR_1_DVZ',
      'ISK_TUTAR_2_DVZ',
      'ISK_TUTAR_3_DVZ',
      'ISK_TUTAR_STOK_DVZ',
      'ISK_TUTAR_OZEL_DVZ',
      'ISK_TUTAR_ALT1_DVZ',
      'ISK_TUTAR_ALT2_DVZ',
      'TOPLAM_ISK_STOK_DVZ',
      'TOPLAM_ISK_FAT_DVZ',
      'PAZ_URUN_TUTARI_DVZ',
      'PAZ_ISC_TUTARI_DVZ',
      'EK_MALIYET_KPB',
      'EK_MALIYET_DVZ',
      'KPB_EKKESINTILER',
      'DVZ_EKKESINTILER',
      'SEVK_BLKODU',
      'ISK_TUTAR_PRM',
      'ISK_TUTAR_PRM_DVZ',
      'TOPLAM_OTEL_KNKVR_DVZ',
      'TOPLAM_OTEL_KNKVR_KPB',
    ]) {
      setFirstColumn(header, faturaColumns, [zeroCol], 0);
    }
    setAllColumns(
      header,
      faturaColumns,
      ['TOPLAM_ALT_KPB', 'TOPLAM_ARA_KPB', 'KPB_ARA_TOPLAM', 'TOPLAM_ARA', 'KPB_ARA_TUTAR', 'ARA_TOPLAM'],
      kpbSubtotal,
    );
    setAllColumns(
      header,
      faturaColumns,
      [
        'TOPLAM_ISK_KPB',
        'KPB_IND_TOPLAM',
        'KPB_ISKONTO_TOPLAM',
        'IND_TOPLAM',
        'ISKONTO_TOPLAM',
      ],
      kpbDiscount,
    );
    setAllColumns(
      header,
      faturaColumns,
      [
        'TOPLAM_KDV_KPB',
        'KPB_KDV_TOPLAM',
        'TOPLAM_KDV',
        'KDV_TOPLAM',
        'HESAPLANAN_KDV_KPB',
      ],
      kpbTax,
    );
    setAllColumns(
      header,
      faturaColumns,
      [
        'TOPLAM_GENEL_KPB',
        'KPB_GENEL_TOPLAM',
        'TOPLAM_GENEL',
        'GENEL_TOPLAM',
        'FATURA_TOPLAMI',
        'KPB_KDV_DAHIL_TOPLAM',
      ],
      kpbGrand,
    );
    if (!isTry) {
      setAllColumns(
        header,
        faturaColumns,
        ['TOPLAM_ALT_DVZ', 'TOPLAM_ARA_DVZ', 'DVZ_ARA_TOPLAM', 'DOVIZ_ARA_TOPLAM'],
        subtotal,
      );
      setAllColumns(
        header,
        faturaColumns,
        ['TOPLAM_ISK_DVZ', 'DVZ_IND_TOPLAM', 'DVZ_ISKONTO_TOPLAM', 'DOVIZ_ISKONTO_TOPLAM'],
        discountTotal,
      );
      setAllColumns(
        header,
        faturaColumns,
        ['TOPLAM_KDV_DVZ', 'DVZ_KDV_TOPLAM', 'DOVIZ_KDV_TOPLAM', 'HESAPLANAN_KDV_DVZ'],
        taxTotal,
      );
      setAllColumns(
        header,
        faturaColumns,
        ['TOPLAM_GENEL_DVZ', 'DVZ_GENEL_TOPLAM', 'DOVIZ_GENEL_TOPLAM'],
        grandTotal,
      );
    }

    const faturaSourceId = await insertWithTx('FATURA', faturaColumns, header);
    if (!faturaSourceId) {
      throw new Error('FATURA kaydı oluşturulamadı (BLKODU alınamadı).');
    }
    const faturaBlkodu = Number(faturaSourceId);

    let lineIdx = 0;
    for (const line of linePayloads) {
      const row = {};
      if (!lineIdentity) {
        row.BLKODU = reservedLineBlkodus[lineIdx++];
      }
      setFirstColumn(row, lineColumns, ['BLFTKODU'], faturaBlkodu);
      if (line.productSourceId != null) {
        setFirstColumn(row, lineColumns, ['BLSTKODU'], line.productSourceId);
        setFirstColumn(row, lineColumns, ['STOKKODU'], line.productCode);
      } else {
        // Referans form: stok yoksa BLSTKODU=0 (NULL değil).
        setFirstColumn(row, lineColumns, ['BLSTKODU'], 0);
      }
      // Ürün adı STOK_ADI'ya; kalem açıklaması ayrı ACIKLAMA alanına.
      if (lineColumns.has('STOK_ADI')) {
        setFirstColumn(row, lineColumns, ['STOK_ADI'], line.description);
        if (line.notes) {
          setFirstColumn(row, lineColumns, ['ACIKLAMA', 'ACIKLAMA1'], line.notes);
        }
      } else {
        setFirstColumn(row, lineColumns, ['ACIKLAMA', 'ACIKLAMA1'], line.description);
        if (line.notes) {
          setFirstColumn(row, lineColumns, ['ACIKLAMA1', 'ACIKLAMA2'], line.notes);
        }
      }
      const unitLabel = textOrNull(line.unit) || 'ADET';
      setAllColumns(row, lineColumns, ['MIKTARI', 'MIKTARI_2'], line.quantity);
      setAllColumns(row, lineColumns, ['BIRIMI', 'BIRIMI_2'], unitLabel);
      setFirstColumn(row, lineColumns, ['BIRIM_CARPANI'], 1);
      // DEPO_KULLAN=1 iken satırda Depo Adı zorunlu (aksi halde Kaydet hata verir).
      setFirstColumn(row, lineColumns, ['DEPO_ADI'], defaultDepo);
      setFirstColumn(row, lineColumns, ['DEPOZITO_BLSTKODU'], 0);
      // Wolvox satır: KPBDVZ=1 KPB/TL, KPBDVZ=0 döviz hesabı (ters yazılırsa UI TL gösterir).
      setFirstColumn(row, lineColumns, ['KPBDVZ'], isTry ? 1 : 0);
      setFirstColumn(
        row,
        lineColumns,
        ['DOVIZ_BIRIMI', 'DVZ_BIRIMI'],
        fxRates.symbol,
      );
      if (!isTry) {
        setFirstColumn(row, lineColumns, ['DOVIZ_ALIS'], fxRates.alis);
        setFirstColumn(row, lineColumns, ['DOVIZ_SATIS'], fxRates.satis);
      }
      setFirstColumn(row, lineColumns, ['KDV_ORANI'], line.taxRate);
      setFirstColumn(row, lineColumns, ['KDV_DURUMU'], 0);
      setFirstColumn(row, lineColumns, ['SIRA_NO'], linePayloads.indexOf(line) + 1);
      const lineKpbNet = isTry ? line.net : line.net * kpbFactor;
      const lineKpbTax = isTry ? line.tax : line.tax * kpbFactor;
      const lineKpbGross = isTry ? line.gross : line.gross * kpbFactor;
      const lineKpbPrice = isTry ? line.unitPrice : line.unitPrice * kpbFactor;
      setAllColumns(
        row,
        lineColumns,
        [
          'KPB_FIYATI',
          'KPB_KDV_HARICFY',
          'KPB_IND_FIYAT',
          'KPB_FIYATI_2',
          'KPB_BIRIM_FIYAT',
          'KPB_BF',
          'FIYATI',
        ],
        lineKpbPrice,
      );
      setAllColumns(
        row,
        lineColumns,
        [
          'KPB_ARA_TUTAR',
          'KPB_TOPLAM_TUTAR',
          'KPB_IND_TUTAR',
          'KPB_TUTAR',
          'KPB_KDV_HARIC_TUTAR',
        ],
        lineKpbNet,
      );
      setAllColumns(
        row,
        lineColumns,
        ['KPB_KDV_TUTARI', 'KPB_KDV', 'KDV_TUTARI'],
        lineKpbTax,
      );
      setAllColumns(
        row,
        lineColumns,
        ['KPB_KDVLI_TUTAR', 'KPB_KDV_DAHIL_TUTAR'],
        lineKpbGross,
      );
      if (!isTry) {
        setAllColumns(
          row,
          lineColumns,
          [
            'DVZ_FIYATI',
            'DVZ_KDV_HARICFY',
            'DVZ_IND_FIYAT',
            'DVZ_FIYATI_2',
            'DVZ_BIRIM_FIYAT',
            'DVZ_BF',
          ],
          line.unitPrice,
        );
        setAllColumns(
          row,
          lineColumns,
          ['DVZ_ARA_TUTAR', 'DVZ_TOPLAM_TUTAR', 'DVZ_IND_TUTAR', 'DVZ_TUTAR'],
          line.net,
        );
        setAllColumns(row, lineColumns, ['DVZ_KDV_TUTARI', 'DVZ_KDV'], line.tax);
        setAllColumns(
          row,
          lineColumns,
          ['DVZ_KDVLI_TUTAR', 'DVZ_KDV_DAHIL_TUTAR'],
          line.gross,
        );
      }
      await insertWithTx('FATURAHR', lineColumns, row);
    }

    // Wolvox döviz faturası için FATURA_KUR şart (yoksa liste DVZ görür, form TL açılır).
    if (hasFaturaKur && kurColumns) {
      const kurRow = {};
      if (!kurIdentity) {
        kurRow.BLKODU = reservedKurBlkodu;
      }
      setFirstColumn(kurRow, kurColumns, ['BLFTKODU'], faturaBlkodu);
      setFirstColumn(kurRow, kurColumns, ['DOVIZ_BIRIMI'], fxRates.symbol);
      setFirstColumn(kurRow, kurColumns, ['DOVIZ_ALIS'], fxRates.alis);
      setFirstColumn(kurRow, kurColumns, ['DOVIZ_SATIS'], fxRates.satis);
      await insertWithTx('FATURA_KUR', kurColumns, kurRow);
    }

    // Referans faturadaki gibi KDV özeti (FATURA_KDV) yazılmazsa form bozulabiliyor.
    if (hasFaturaKdv && kdvColumns) {
      let kdvIdx = 0;
      for (const [rate, amounts] of kdvRates.entries()) {
        const kdvRow = {};
        if (!kdvIdentity) {
          kdvRow.BLKODU = reservedKdvBlkodus[kdvIdx++];
        }
        setFirstColumn(kdvRow, kdvColumns, ['BLFTKODU'], faturaBlkodu);
        setFirstColumn(kdvRow, kdvColumns, ['KDV_ORANI'], rate);
        setFirstColumn(kdvRow, kdvColumns, ['KDV_MATRAHI'], amounts.matrah);
        setFirstColumn(kdvRow, kdvColumns, ['KDV_TUTARI'], amounts.tax);
        setFirstColumn(kdvRow, kdvColumns, ['SON_KDV'], amounts.tax);
        await insertWithTx('FATURA_KDV', kdvColumns, kdvRow);
      }
    }

    let cariHrWritten = false;
    if (hasCariHr && cariHrColumns.size) {
      const cariRow = {};
      if (!cariHrIdentity) {
        cariRow.BLKODU = reservedCariHrBlkodu;
      }
      setFirstColumn(cariRow, cariHrColumns, ['BLCRKODU'], customerSourceId);
      setFirstColumn(cariRow, cariHrColumns, ['EVRAK_NO'], invoiceNumber);
      setFirstColumn(cariRow, cariHrColumns, ['TARIHI'], invoiceDate);
      setFirstColumn(cariRow, cariHrColumns, ['KAYIT_TARIHI'], invoiceDate);
      setFirstColumn(cariRow, cariHrColumns, ['KAYDEDEN'], 'CRM');
      if (dueDate) {
        setFirstColumn(
          cariRow,
          cariHrColumns,
          ['VADESI'],
          toSqlDateOnly(dueDate, dueDate),
        );
      }
      setFirstColumn(
        cariRow,
        cariHrColumns,
        ['ACIKLAMA'],
        textOrNull(invoice.notes) || `CRM fatura ${invoiceNumber}`,
      );
      // Satışta cari borç (BTUT), alışta alacak (ATUT).
      if (isSales) {
        setFirstColumn(cariRow, cariHrColumns, ['KPB_BTUT', 'BTUT'], kpbGrand);
        if (!isTry) {
          setAllColumns(cariRow, cariHrColumns, ['DVZ_BTUT', 'DVZ_BTUT2'], grandTotal);
        }
      } else {
        setFirstColumn(cariRow, cariHrColumns, ['KPB_ATUT', 'ATUT'], kpbGrand);
        if (!isTry) {
          setAllColumns(cariRow, cariHrColumns, ['DVZ_ATUT', 'DVZ_ATUT2'], grandTotal);
        }
      }
      setFirstColumn(cariRow, cariHrColumns, ['KUR', 'DOVIZ_KURU'], kpbRate);
      setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_KULLAN'], isTry ? 0 : 1);
      // Referans FX CARIHR: KPBDVZ=1 (KPB tutar + DVZ tutar birlikte).
      setFirstColumn(cariRow, cariHrColumns, ['KPBDVZ'], 1);
      setFirstColumn(
        cariRow,
        cariHrColumns,
        ['DOVIZ_BIRIMI', 'DOVIZ_BIRIMI2'],
        fxRates.symbol,
      );
      if (!isTry) {
        setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_ALIS'], fxRates.alis);
        setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_ALIS2'], fxRates.alis);
        setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_SATIS'], fxRates.satis);
        setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_SATIS2'], fxRates.satis);
        setFirstColumn(cariRow, cariHrColumns, ['DOVIZ_HES_ISLE'], 0);
      }
      setFirstColumn(cariRow, cariHrColumns, ['ISLEM_TURU'], 9);
      setFirstColumn(cariRow, cariHrColumns, ['FATURA_DURUMU'], 1);
      setFirstColumn(cariRow, cariHrColumns, ['SILINDI'], 0);
      setFirstColumn(
        cariRow,
        cariHrColumns,
        ['ENTEGRASYON'],
        `FTO_${faturaBlkodu}`,
      );
      await insertWithTx('CARIHR', cariHrColumns, cariRow);
      cariHrWritten = true;
    }

    await transaction.commit();
    if (mon) {
      createSelfWait = mon.selfWait;
      await mon.done();
    }

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
            akinsoft_sync_status = 'synced',
            akinsoft_synced_at = now(),
            akinsoft_sync_error = null,
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
      selfWait: createSelfWait,
    };
  } catch (error) {
    if (mon) {
      createSelfWait = mon.selfWait;
      await mon.done();
    }
    try {
      await transaction.rollback();
    } catch (_) {
      // ignore rollback errors
    }
    return {
      ok: false,
      reason: isAkinsoftLockError(error)
        ? describeAkinsoftLockReasonFromEvidence({ selfWait: createSelfWait })
        : describeAkinsoftSqlError(error),
      selfWait: createSelfWait,
      __lock: isAkinsoftLockError(error),
      sqlError: extractAkinsoftSqlError(error),
      phase: 'create',
    };
  }
}

async function writeAkinsoftInvoiceCreate(pool, sql, query, invoice) {
  return withAkinsoftLockRetry(
    async () => attemptWriteAkinsoftInvoiceCreate(pool, sql, query, invoice),
    { label: 'push-invoice-create' },
  );
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
        ii.notes,
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
  // Yazımda TX + opsiyonel monitor; fazla havuz bağlantısı self-lock riskini artırır.
  config.pool = { max: 3, min: 0, idleTimeoutMillis: 10000 };
  const pool = await connectAkinsoftPool(config);
  const items = [];
  let blockers = null;
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
        await setInvoiceAkinsoftSyncStatus(
          query,
          invoiceId,
          'error',
          'Pasif fatura Akınsoft’a gönderilemez.',
        );
        continue;
      }
      if (String(row.status || '') === 'cancelled') {
        items.push({
          invoiceId,
          invoiceNumber: row.invoice_number,
          ok: false,
          reason: 'İptal fatura Akınsoft’a gönderilemez.',
        });
        await setInvoiceAkinsoftSyncStatus(
          query,
          invoiceId,
          'error',
          'İptal fatura Akınsoft’a gönderilemez.',
        );
        continue;
      }
      try {
        const write = await writeAkinsoftInvoiceCreate(pool, sql, query, {
          ...row,
          items: itemsByInvoice.get(String(invoiceId)) || [],
        });
        const ok = write.ok === true;
        if (ok) {
          await setInvoiceAkinsoftSyncStatus(query, row.id, 'synced');
        } else {
          await setInvoiceAkinsoftSyncStatus(
            query,
            row.id,
            'error',
            write.reason || 'Akınsoft gönderimi başarısız.',
          );
        }
        items.push({
          invoiceId: row.id,
          invoiceNumber: row.invoice_number,
          ok,
          skipped: write.skipped === true,
          sourceId: write.sourceId || row.akinsoft_source_id || null,
          lineCount: write.lineCount || 0,
          descriptionOnlyLines: write.descriptionOnlyLines || 0,
          customerCreated: write.customerCreated === true,
          customerMatchedBy: write.customerMatchedBy || null,
          cariHrWritten: write.cariHrWritten === true,
          reason: write.reason || null,
          selfWait: write.selfWait || null,
          phase: write.phase || null,
          sqlError: write.sqlError || null,
          lockRetries: write.lockRetries || null,
        });
      } catch (error) {
        const reason = describeAkinsoftSqlError(error);
        await setInvoiceAkinsoftSyncStatus(query, row.id, 'error', reason);
        items.push({
          invoiceId: row.id,
          invoiceNumber: row.invoice_number,
          ok: false,
          reason,
          sqlError: extractAkinsoftSqlError(error),
        });
      }
      // Sonraki faturaya geçmeden kısa ara — varsayılan 0 (TX-order fix sonrası gereksiz).
      if (AKINSOFT_INTER_INVOICE_DELAY_MS > 0) {
        await sleepMs(AKINSOFT_INTER_INVOICE_DELAY_MS);
      }
    }
    // Kilit görülürse: anlamlı engelleyicileri tespit et; CRM DATABASE S gürültüsünü ele.
    if (
      items.some(
        (it) =>
          it &&
          !it.ok &&
          /kilitli|zaman aşımına uğrad/i.test(String(it.reason || '')),
      )
    ) {
      blockers = await getAkinsoftLockHolders(pool);
      refineAkinsoftLockItemReasons(items, blockers);
      for (const it of items) {
        if (!it || it.ok || !it.invoiceId) continue;
        if (!/kilitli|zaman aşımına|CRM’in başka|engelleyici WOLVOX değil/i.test(
          String(it.reason || ''),
        )) {
          continue;
        }
        await setInvoiceAkinsoftSyncStatus(
          query,
          it.invoiceId,
          'error',
          it.reason,
        ).catch(() => {});
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
      blockers,
      serverBuild: AKINSOFT_SERVER_BUILD,
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
  config.pool = { max: 3, min: 0, idleTimeoutMillis: 10000 };
  const pool = await connectAkinsoftPool(config);
  const items = [];
  let blockers = null;
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

        // Akınsoft’ta yoksa: önce resmi/ERP no ile var mı bak; yoksa oluştur.
        // Eski davranış "bulunamadı → hemen create" idi; STŞ ile bir kez,
        // Maliye no ile bir kez yazıp sonra rename ile aynı EVRAK_NO’ya
        // çekince mükerrer borç/tahsilat üretiyordu.
        if (
          !write.ok &&
          !row.akinsoft_source_id &&
          /bulunamadı|eşlemesi/i.test(String(write.reason || ''))
        ) {
          const existing = await findExistingAkinsoftFaturaByNumbers(pool, sql, [
            eInvoiceNumber,
            officialEInvoiceNumber,
            erpNumber,
            invoiceNumber,
          ]);
          if (existing?.sourceId) {
            write = {
              ok: true,
              skipped: true,
              reason: existing.orphanCariHr
                ? 'Akınsoft’ta aynı numaralı cari hareket vardı; yeni fatura yazılmadı, eşleme güncellendi.'
                : 'Akınsoft’ta aynı numaralı fatura vardı; yeni kayıt yerine eşleme güncellendi.',
              oldNumber: erpNumber || invoiceNumber,
              sourceId: String(existing.sourceId),
            };
            row.akinsoft_source_id = String(existing.sourceId);
          } else if (existing?.orphanCariHr) {
            write = {
              ok: false,
              reason:
                `Akınsoft’ta ${eInvoiceNumber} evrak no’lu orphan cari hareket var; ` +
                'mükerrer FATURA oluşturmadı. WOLVOX’ta hareketleri kontrol edin.',
            };
          } else {
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
                  i.erp_invoice_number,
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
                    ii.notes,
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
                erp_invoice_number: erpNumber || header.erp_invoice_number,
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
                  lockRetries: created.lockRetries || null,
                };
                row.akinsoft_source_id = created.sourceId;
              } else {
                write = {
                  ok: false,
                  reason:
                    created.reason ||
                    'Akınsoft’ta fatura bulunamadı ve oluşturma başarısız.',
                  selfWait: created.selfWait || null,
                  phase: created.phase || 'create',
                  sqlError: created.sqlError || null,
                  lockRetries: created.lockRetries || null,
                };
              }
            }
          }
        } else if (
          !write.ok &&
          write.conflictSourceId &&
          /başka bir faturada kullanılıyor/i.test(String(write.reason || ''))
        ) {
          // Hedef Maliye no zaten başka BLKODU’da: oluşturma; o kayda eşle.
          write = {
            ok: true,
            skipped: true,
            reason:
              'Maliye numarası Akınsoft’ta zaten vardı; mevcut faturaya eşlendi (yeni kayıt yok).',
            oldNumber: erpNumber || invoiceNumber,
            sourceId: String(write.conflictSourceId),
          };
          row.akinsoft_source_id = String(write.conflictSourceId);
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
          await setInvoiceAkinsoftSyncStatus(query, row.id, 'synced');
        } else {
          await setInvoiceAkinsoftSyncStatus(
            query,
            row.id,
            'error',
            write.reason || 'Akınsoft no güncellemesi başarısız.',
          );
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
          lockHolders: write.lockHolders || null,
          killedSessions: write.killedSessions || null,
          cariHrUpdated: write.cariHrUpdated ?? null,
          selfWait: write.selfWait || null,
          phase: write.phase || null,
          sqlError: write.sqlError || null,
          lockRetries: write.lockRetries || null,
          akinsoftSourceIdInput: row.akinsoft_source_id || null,
        });
      } catch (error) {
        // Bir faturadaki hata tüm toplu işlemi düşürmesin.
        const reason = describeAkinsoftSqlError(error);
        await setInvoiceAkinsoftSyncStatus(query, row.id, 'error', reason);
        items.push({
          ...base,
          ok: false,
          reason,
          sqlError: extractAkinsoftSqlError(error),
        });
      }
      if (AKINSOFT_INTER_INVOICE_DELAY_MS > 0) {
        await sleepMs(AKINSOFT_INTER_INVOICE_DELAY_MS);
      }
    }
    // Kilit görülürse: anlamlı engelleyicileri tespit et; CRM DATABASE S gürültüsünü ele.
    if (
      items.some(
        (it) =>
          it &&
          !it.ok &&
          /kilitli|zaman aşımına uğrad/i.test(String(it.reason || '')),
      )
    ) {
      blockers = await getAkinsoftLockHolders(pool);
      refineAkinsoftLockItemReasons(items, blockers);
      for (const it of items) {
        if (!it || it.ok || !it.invoiceId) continue;
        if (!/kilitli|zaman aşımına|CRM’in başka|engelleyici WOLVOX değil/i.test(
          String(it.reason || ''),
        )) {
          continue;
        }
        await setInvoiceAkinsoftSyncStatus(
          query,
          it.invoiceId,
          'error',
          it.reason,
        ).catch(() => {});
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
      blockers,
      serverBuild: AKINSOFT_SERVER_BUILD,
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
  const { createAkinsoftFinanceHandlers } = require('./akinsoft_finance_sync');
  const mssql = require('mssql');
  const financeRoutes = createAkinsoftFinanceHandlers({
    sql: mssql,
    buildAkinsoftSqlConfig,
    connectAkinsoftPool,
    akinsoftTableExists,
    akinsoftTableColumnSet,
    akinsoftNextBlkoduSafe,
    insertAkinsoftRowWithRequest,
    setFirstColumn,
    setAllColumns,
    readJson,
    send,
    textOrNull,
    numberOrZero,
    toSqlDate,
  });
  const routes = {
    '/api/akinsoft/test-connection': handleAkinsoftTestConnection,
    '/api/akinsoft/save-local-settings': handleAkinsoftSaveLocalSettings,
    '/api/akinsoft/analyze': handleAkinsoftAnalyze,
    '/api/akinsoft/pull': handleAkinsoftPull,
    '/api/akinsoft/pull-and-update': handleAkinsoftPullAndUpdate,
    '/api/akinsoft/import': handleAkinsoftImport,
    '/api/akinsoft/import-job': handleAkinsoftImportJob,
    '/api/akinsoft/local-customers': handleAkinsoftLocalCustomers,
    '/api/akinsoft/map-customer': handleAkinsoftMapCustomer,
    '/api/akinsoft/bulk-map-customers-job': handleAkinsoftBulkMapCustomersJob,
    '/api/akinsoft/bulk-map-customers': handleAkinsoftBulkMapCustomers,
    '/api/akinsoft/duplicate-customers': handleAkinsoftDuplicateCustomers,
    '/api/akinsoft/push-invoice-numbers': handleAkinsoftPushInvoiceNumbers,
    '/api/akinsoft/push-invoices': handleAkinsoftPushInvoices,
    ...financeRoutes,
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

function safeJoin(root, requestPath) {
  const decoded = decodeURIComponent(requestPath);
  const normalized = decoded.replace(/^\/+/, '');
  const resolved = path.resolve(root, normalized);
  if (!resolved.startsWith(root)) return null;
  return resolved;
}

/**
 * Yerel web + API + Akınsoft köprüsünü başlatır (CLI ve Electron ortak).
 * @returns {Promise<{ port: number, url: string, server: import('http').Server }>}
 */
function startLocalServer(options = {}) {
  const host = String(options.host || '127.0.0.1');
  const requestedPortRaw =
    options.port != null ? String(options.port) : process.env.PORT;
  const requestedPort = Number(requestedPortRaw || 3000);
  const exitOnBusy = options.exitOnBusy !== false && require.main === module;

  const server = http.createServer(async (req, res) => {
    try {
      const url = new URL(
        req.url || '/',
        `http://${req.headers.host || 'localhost'}`,
      );
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

        if (pathname === '/api/_local/open-pdf') {
          const filePath = String(req.query.path || '').trim();
          let resolved;
          try {
            resolved = path.resolve(filePath);
          } catch (_) {
            return send(res, 400, { 'Content-Type': 'text/plain' }, 'Geçersiz yol');
          }
          const pdfDir = String(process.env.MICROVISE_PDF_DIR || '').trim();
          const allowedRoots = [
            pdfDir,
            path.join(require('os').tmpdir(), 'microvise-crm', 'pdfs'),
          ]
            .filter(Boolean)
            .map((dir) => path.resolve(dir));
          const allowed = allowedRoots.some(
            (root) =>
              resolved === root || resolved.startsWith(`${root}${path.sep}`),
          );
          const lower = resolved.toLowerCase();
          const isPdf = lower.endsWith('.pdf');
          const isZip = lower.endsWith('.zip');
          if (
            !allowed ||
            (!isPdf && !isZip) ||
            !fs.existsSync(resolved) ||
            !fs.statSync(resolved).isFile()
          ) {
            return send(
              res,
              404,
              { 'Content-Type': 'text/plain' },
              isZip ? 'ZIP bulunamadı' : 'PDF bulunamadı',
            );
          }
          const body = fs.readFileSync(resolved);
          const downloadName = path.basename(resolved);
          const asAttachment =
            isZip ||
            String(req.query.download || '').trim() === '1' ||
            String(req.query.download || '').trim().toLowerCase() === 'true';
          return send(
            res,
            200,
            {
              'Content-Type': isZip ? 'application/zip' : 'application/pdf',
              'Content-Disposition': `${asAttachment ? 'attachment' : 'inline'}; filename="${downloadName}"`,
              'Cache-Control': 'no-store',
            },
            body,
          );
        }

        // Toplu e-fatura: yerel PDF yollarından tek ZIP üret.
        if (pathname === '/api/_local/zip-pdfs' && req.method === 'POST') {
          try {
            const body = await readJson(req);
            const files = Array.isArray(body.files) ? body.files : [];
            const zipFileName = String(body.zipFileName || 'e_faturalar.zip').trim();
            const pdfDir = String(process.env.MICROVISE_PDF_DIR || '').trim();
            const allowedRoots = [
              pdfDir,
              path.join(require('os').tmpdir(), 'microvise-crm', 'pdfs'),
            ]
              .filter(Boolean)
              .map((dir) => path.resolve(dir));
            const { createStoreZip } = require(path.join(
              rootDir,
              'api',
              '_lib',
              'zip_store.js',
            ));
            const {
              writeLocalExportZip,
            } = require(path.join(rootDir, 'api', '_lib', 'e_invoice_pdf.js'));

            const usedNames = new Set();
            const zipEntries = [];
            for (const item of files) {
              const rawPath = String(item?.path || '').trim();
              if (!rawPath) continue;
              let resolved;
              try {
                resolved = path.resolve(rawPath);
              } catch (_) {
                continue;
              }
              const allowed = allowedRoots.some(
                (root) =>
                  resolved === root ||
                  resolved.startsWith(`${root}${path.sep}`),
              );
              if (
                !allowed ||
                !resolved.toLowerCase().endsWith('.pdf') ||
                !fs.existsSync(resolved) ||
                !fs.statSync(resolved).isFile()
              ) {
                continue;
              }
              let name = String(item?.name || path.basename(resolved))
                .trim()
                .replace(/[^a-zA-Z0-9._-]+/g, '_');
              if (!name.toLowerCase().endsWith('.pdf')) name = `${name || 'e_fatura'}.pdf`;
              let candidate = name;
              let i = 2;
              while (usedNames.has(candidate.toLowerCase())) {
                const dot = name.lastIndexOf('.');
                const stem = dot > 0 ? name.slice(0, dot) : name;
                const ext = dot > 0 ? name.slice(dot) : '';
                candidate = `${stem}_${i}${ext}`;
                i += 1;
              }
              usedNames.add(candidate.toLowerCase());
              zipEntries.push({
                name: candidate,
                data: fs.readFileSync(resolved),
              });
            }
            if (!zipEntries.length) {
              return send(
                res,
                400,
                { 'Content-Type': 'application/json; charset=utf-8' },
                JSON.stringify({ ok: false, error: 'ZIP için geçerli PDF yok.' }),
              );
            }
            const zipBytes = createStoreZip(zipEntries);
            const zipPath = writeLocalExportZip(zipBytes, zipFileName);
            const zipUrl = `/api/_local/open-pdf?path=${encodeURIComponent(zipPath)}&download=1`;
            return send(
              res,
              200,
              { 'Content-Type': 'application/json; charset=utf-8' },
              JSON.stringify({
                ok: true,
                zipPath,
                zipUrl,
                zipFileName: path.basename(zipPath),
                count: zipEntries.length,
              }),
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

        // İstemci tarafında üretilen ZIP baytlarını yerel diske yazar.
        if (pathname === '/api/_local/save-export' && req.method === 'POST') {
          try {
            const body = await readJson(req);
            const fileName = String(body.fileName || 'export.bin').trim();
            const base64 = String(body.base64 || '').trim();
            if (!base64) {
              return send(
                res,
                400,
                { 'Content-Type': 'application/json; charset=utf-8' },
                JSON.stringify({ ok: false, error: 'base64 zorunlu.' }),
              );
            }
            const lower = fileName.toLowerCase();
            if (!lower.endsWith('.zip') && !lower.endsWith('.pdf')) {
              return send(
                res,
                400,
                { 'Content-Type': 'application/json; charset=utf-8' },
                JSON.stringify({ ok: false, error: 'Yalnızca .zip / .pdf.' }),
              );
            }
            const bytes = Buffer.from(base64, 'base64');
            if (!bytes.length) {
              return send(
                res,
                400,
                { 'Content-Type': 'application/json; charset=utf-8' },
                JSON.stringify({ ok: false, error: 'Boş dosya.' }),
              );
            }
            const {
              writeLocalExportZip,
              writeLocalEInvoicePdf,
            } = require(path.join(rootDir, 'api', '_lib', 'e_invoice_pdf.js'));
            const savedPath = lower.endsWith('.zip')
              ? writeLocalExportZip(bytes, fileName)
              : writeLocalEInvoicePdf(bytes, fileName);
            const fileUrl = `/api/_local/open-pdf?path=${encodeURIComponent(savedPath)}&download=1`;
            return send(
              res,
              200,
              { 'Content-Type': 'application/json; charset=utf-8' },
              JSON.stringify({
                ok: true,
                path: savedPath,
                url: fileUrl,
                fileName: path.basename(savedPath),
              }),
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

        // Electron setWindowOpenHandler bunu yakalar; tarayıcıda no-op JSON.
        if (pathname === '/api/_local/reveal-file') {
          const filePath = String(req.query.path || '').trim();
          let resolved;
          try {
            resolved = path.resolve(filePath);
          } catch (_) {
            return send(res, 400, { 'Content-Type': 'application/json' }, JSON.stringify({ ok: false, error: 'Geçersiz yol' }));
          }
          const pdfDir = String(process.env.MICROVISE_PDF_DIR || '').trim();
          const allowedRoots = [
            pdfDir,
            path.join(require('os').tmpdir(), 'microvise-crm', 'pdfs'),
          ]
            .filter(Boolean)
            .map((dir) => path.resolve(dir));
          const allowed = allowedRoots.some(
            (root) =>
              resolved === root || resolved.startsWith(`${root}${path.sep}`),
          );
          const lower = resolved.toLowerCase();
          const okExt = lower.endsWith('.pdf') || lower.endsWith('.zip');
          if (
            !allowed ||
            !okExt ||
            !fs.existsSync(resolved) ||
            !fs.statSync(resolved).isFile()
          ) {
            return send(
              res,
              404,
              { 'Content-Type': 'application/json' },
              JSON.stringify({ ok: false, error: 'Dosya bulunamadı' }),
            );
          }
          return send(
            res,
            200,
            { 'Content-Type': 'application/json' },
            JSON.stringify({ ok: true, path: resolved }),
          );
        }

        if (pathname.startsWith('/api/akinsoft/')) {
          try {
            return await handleAkinsoftRequest(req, res);
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
        if (!handler) {
          return send(
            res,
            404,
            { 'Content-Type': 'application/json' },
            JSON.stringify({ error: 'Not found' }),
          );
        }
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

  return new Promise((resolve, reject) => {
    server.once('error', (err) => {
      if (err && err.code === 'EADDRINUSE') {
        const msg = requestedPortRaw
          ? `PORT ${requestedPort} kullanımda. Farklı PORT verin.`
          : 'PORT 3000 kullanımda. PORT=0 npm run local-web ile otomatik port seçebilirsiniz.';
        if (exitOnBusy) {
          console.error(msg);
          process.exit(1);
        }
        reject(new Error(msg));
        return;
      }
      if (exitOnBusy) {
        console.error(err);
        process.exit(1);
      }
      reject(err);
    });

    const portToBind = requestedPortRaw ? requestedPort : 0;
    server.listen(portToBind, host, () => {
      const address = server.address();
      const port =
        address && typeof address === 'object' && address.port
          ? address.port
          : portToBind;
      const url = `http://${host}:${port}`;
      process.env.MICROVISE_LOCAL_ORIGIN = url;
      console.log(`Local web: ${url}`);
      resolve({ port, url, server, host });
    });
  });
}

module.exports = {
  handleAkinsoftRequest,
  startLocalServer,
};

if (require.main === module) {
  startLocalServer().catch((err) => {
    console.error(err);
    process.exit(1);
  });
}
