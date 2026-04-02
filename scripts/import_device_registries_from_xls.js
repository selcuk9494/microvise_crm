const fs = require('fs');
const path = require('path');
const xlsx = require('xlsx');

const rootDir = path.resolve(__dirname, '..');

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

function normalizeHeader(input) {
  return String(input || '')
    .trim()
    .toLowerCase()
    .replaceAll(' ', '')
    .replaceAll('ç', 'c')
    .replaceAll('ğ', 'g')
    .replaceAll('ı', 'i')
    .replaceAll('ö', 'o')
    .replaceAll('ş', 's')
    .replaceAll('ü', 'u');
}

function normalizeRegistryNumber(input) {
  return String(input || '').trim();
}

function normalizeVkn(input) {
  return String(input || '').trim();
}

async function main() {
  const fileArg = process.argv[2] || './dokuman/sicil.xls';
  const xlsPath = path.isAbsolute(fileArg) ? fileArg : path.resolve(rootDir, fileArg);
  if (!fs.existsSync(xlsPath)) {
    throw new Error(`Dosya bulunamadı: ${xlsPath}`);
  }

  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  const { ensureDeviceRegistriesTable } = require(path.join(rootDir, 'api', '_lib', 'schema.js'));

  await ensureDeviceRegistriesTable();

  const customers = await query(
    `
      select id, vkn
      from public.customers
      where vkn is not null
        and btrim(vkn) <> ''
    `,
  );
  const vknToCustomerId = new Map();
  for (const row of customers.rows) {
    const vkn = normalizeVkn(row.vkn);
    const id = String(row.id || '').trim();
    if (!vkn || !id) continue;
    vknToCustomerId.set(vkn, id);
  }

  const workbook = xlsx.readFile(xlsPath, { cellDates: true });
  const sheetName = workbook.SheetNames[0];
  const sheet = workbook.Sheets[sheetName];
  if (!sheet) throw new Error('Excel sheet okunamadı.');

  const rows = xlsx.utils.sheet_to_json(sheet, { header: 1, raw: false });
  if (!Array.isArray(rows) || rows.length < 2) {
    throw new Error('Excel boş veya header yok.');
  }

  const header = rows[0] || [];
  let sicilIndex = -1;
  let vknIndex = -1;
  let modelIndex = -1;
  for (let i = 0; i < header.length; i++) {
    const h = normalizeHeader(header[i]);
    if (sicilIndex === -1 && h.includes('sicil')) sicilIndex = i;
    if (vknIndex === -1 && (h === 'vkn' || h.includes('vkn'))) vknIndex = i;
    if (modelIndex === -1 && h.includes('model')) modelIndex = i;
  }
  if (sicilIndex === -1 || vknIndex === -1) {
    throw new Error('Kolonlar bulunamadı. (Sicil, VKN, Model)');
  }

  let imported = 0;
  let updatedOrExisting = 0;
  let missingCustomer = 0;
  let skipped = 0;

  const now = new Date().toISOString();

  for (let r = 1; r < rows.length; r++) {
    const row = rows[r] || [];
    const registryNumber = normalizeRegistryNumber(row[sicilIndex]);
    const vkn = normalizeVkn(row[vknIndex]);
    const model = modelIndex === -1 ? '' : String(row[modelIndex] || '').trim();

    if (!registryNumber || !vkn) {
      skipped++;
      continue;
    }

    const customerId = vknToCustomerId.get(vkn);
    if (!customerId) {
      missingCustomer++;
      continue;
    }

    const registryNorm = registryNumber.trim().toUpperCase();
    const result = await query(
      `
        insert into public.device_registries (
          registry_number,
          registry_number_norm,
          model,
          customer_id,
          application_form_id,
          is_active,
          assigned_at,
          released_at
        )
        values ($1,$2,$3,$4,null,true,$5,null)
        on conflict (registry_number_norm)
        do update set
          registry_number = excluded.registry_number,
          model = excluded.model,
          customer_id = excluded.customer_id,
          application_form_id = null,
          is_active = true,
          assigned_at = excluded.assigned_at,
          released_at = null
        returning (xmax = 0) as inserted
      `,
      [registryNumber, registryNorm, model || null, customerId, now],
    );

    if (result.rows[0]?.inserted) imported++;
    else updatedOrExisting++;
  }

  const summary = {
    file: xlsPath,
    imported,
    updatedOrExisting,
    missingCustomer,
    skipped,
  };
  process.stdout.write(`${JSON.stringify(summary, null, 2)}\n`);
}

main().catch((err) => {
  process.stderr.write(`${err instanceof Error ? err.stack : String(err)}\n`);
  process.exit(1);
});

