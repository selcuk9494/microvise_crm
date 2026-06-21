const sql = require('mssql');
const fs = require('fs');
const path = require('path');

function loadDotEnvLocal() {
  const file = path.join(process.cwd(), '.env.local');
  if (!fs.existsSync(file)) return;
  const lines = fs.readFileSync(file, 'utf8').split(/\r?\n/);
  for (const line of lines) {
    const trimmed = line.trim();
    if (!trimmed || trimmed.startsWith('#')) continue;
    const idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    const key = trimmed.slice(0, idx).trim();
    const value = trimmed.slice(idx + 1).trim().replace(/^["']|["']$/g, '');
    if (!process.env[key]) process.env[key] = value;
  }
}

loadDotEnvLocal();

function arg(name, fallback = '') {
  const prefix = `--${name}=`;
  const found = process.argv.find((item) => item.startsWith(prefix));
  return found ? found.slice(prefix.length) : process.env[name.toUpperCase()] || fallback;
}

async function main() {
  const year = arg('year', '2026');
  const pattern = arg('database-pattern', 'WOLVOX8_MICO_{year}_WOLVOX');
  const host = arg('host', process.env.AKINSOFT_MSSQL_HOST || '10.147.17.38');
  const port = Number(arg('port', process.env.AKINSOFT_MSSQL_PORT || '1433'));
  const database = arg(
    'database',
    process.env.AKINSOFT_MSSQL_DATABASE || pattern.replace('{year}', year),
  );
  const user = arg('user', process.env.AKINSOFT_MSSQL_USERNAME || 'sa');
  const password = arg('password', process.env.AKINSOFT_MSSQL_PASSWORD || '');

  if (!password) {
    throw new Error('SQL şifresi yok. .env.local içine AKINSOFT_MSSQL_PASSWORD ekleyin veya --password=... verin.');
  }

  const pool = await sql.connect({
    server: host,
    port,
    database,
    user,
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
    console.log('MSSQL bağlantısı başarılı.');
    console.log(String(version.recordset[0].version).split('\n')[0]);

    const tables = await pool.request().query(`
      select top 200
        s.name as schema_name,
        t.name as table_name
      from sys.tables t
      join sys.schemas s on s.schema_id = t.schema_id
      order by t.name
    `);
    console.log('\nİlk tablolar:');
    for (const row of tables.recordset.slice(0, 40)) {
      console.log(`- ${row.schema_name}.${row.table_name}`);
    }

    const candidates = await pool.request().query(`
      select
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
    console.log('\nFatura/Cari/Stok aday tablolar:');
    for (const row of candidates.recordset.slice(0, 120)) {
      console.log(`- ${row.schema_name}.${row.table_name}`);
    }
  } finally {
    await pool.close();
  }
}

main().catch((error) => {
  console.error(`Hata: ${error.message}`);
  process.exitCode = 1;
});
