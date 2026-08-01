#!/usr/bin/env node
/**
 * Canlı gönderilmiş CRM faturalarını Akınsoft’a yazar / Maliye no ile günceller.
 *
 * Kullanım:
 *   AKINSOFT_MSSQL_PASSWORD='...' node scripts/akinsoft_sync_sent_invoices.js
 * veya .env.local içinde AKINSOFT_MSSQL_* alanları (Ayarlar → Yerel kaydet).
 */
const fs = require('fs');
const path = require('path');
const http = require('http');

const rootDir = path.join(__dirname, '..');

function loadEnvFile(filePath) {
  if (!fs.existsSync(filePath)) return;
  for (const line of fs.readFileSync(filePath, 'utf8').split(/\n/)) {
    const text = line.trim();
    if (!text || text.startsWith('#')) continue;
    const i = text.indexOf('=');
    if (i <= 0) continue;
    const key = text.slice(0, i).trim();
    let value = text.slice(i + 1).trim();
    if (
      (value.startsWith('"') && value.endsWith('"')) ||
      (value.startsWith("'") && value.endsWith("'"))
    ) {
      value = value.slice(1, -1);
    }
    if (process.env[key] == null || process.env[key] === '') {
      process.env[key] = value;
    }
  }
}

loadEnvFile(path.join(rootDir, '.env.local'));
loadEnvFile(path.join(rootDir, '.env'));

function postJson(urlPath, body) {
  const payload = Buffer.from(JSON.stringify(body), 'utf8');
  return new Promise((resolve, reject) => {
    const req = http.request(
      {
        hostname: '127.0.0.1',
        port: Number(process.env.PORT || 4000),
        path: urlPath,
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          'Content-Length': payload.length,
        },
        timeout: 15 * 60 * 1000,
      },
      (res) => {
        const chunks = [];
        res.on('data', (c) => chunks.push(c));
        res.on('end', () => {
          const text = Buffer.concat(chunks).toString('utf8');
          let json = null;
          try {
            json = JSON.parse(text);
          } catch (_) {
            json = { ok: false, error: text.slice(0, 500) };
          }
          resolve({ status: res.statusCode || 0, json });
        });
      },
    );
    req.on('error', reject);
    req.on('timeout', () => {
      req.destroy();
      reject(new Error('İstek zaman aşımı'));
    });
    req.write(payload);
    req.end();
  });
}

async function main() {
  if (!String(process.env.AKINSOFT_MSSQL_PASSWORD || '').trim()) {
    console.error(
      'AKINSOFT_MSSQL_PASSWORD yok.\n' +
        '1) http://127.0.0.1:4000 aç\n' +
        '2) E-Fatura ayarlarında SQL şifresini gir → Yerel kaydet\n' +
        '3) Bu scripti tekrar çalıştır',
    );
    process.exit(1);
  }

  const { query } = require(path.join(rootDir, 'api', '_lib', 'db.js'));
  const result = await query(`
    select i.id, i.invoice_number, i.erp_invoice_number, i.e_invoice_number,
           c.name as customer_name, m.source_id
    from public.invoices i
    left join public.customers c on c.id = i.customer_id
    left join public.akinsoft_sync_map m
      on m.source_system = 'akinsoft'
     and m.source_type = 'invoice'
     and m.local_id = i.id
    where i.is_active is distinct from false
      and i.e_invoice_status = 'sent'
      and (i.e_invoice_environment is null or i.e_invoice_environment = 'production')
      and nullif(trim(i.e_invoice_number), '') is not null
    order by i.invoice_date desc nulls last, i.created_at desc
  `);
  const ids = result.rows.map((row) => String(row.id));
  if (!ids.length) {
    console.log('Aktarılacak canlı e-fatura yok.');
    return;
  }

  console.log(`Bulunan: ${ids.length} canlı e-fatura`);
  for (const row of result.rows.slice(0, 20)) {
    console.log(
      `- ${(row.customer_name || '').slice(0, 32)} | ${row.invoice_number} | erp=${row.erp_invoice_number || '-'} | map=${row.source_id || '-'}`,
    );
  }
  if (result.rows.length > 20) console.log(`  ... +${result.rows.length - 20} daha`);

  const settings = {
    akinsoft_mssql_host: process.env.AKINSOFT_MSSQL_HOST || '10.147.17.38',
    akinsoft_mssql_port: process.env.AKINSOFT_MSSQL_PORT || '1433',
    akinsoft_mssql_database: process.env.AKINSOFT_MSSQL_DATABASE || '',
    akinsoft_mssql_username: process.env.AKINSOFT_MSSQL_USERNAME || 'sa',
    akinsoft_mssql_password: process.env.AKINSOFT_MSSQL_PASSWORD,
    akinsoft_database_year: process.env.AKINSOFT_DATABASE_YEAR || '2026',
    akinsoft_database_pattern:
      process.env.AKINSOFT_DATABASE_PATTERN || 'WOLVOX8_MICO_{year}_WOLVOX',
  };

  // Önce numara güncelle (yoksa oluşturur), ardından eşleşmemiş CRM faturalarını yaz.
  console.log('\n→ push-invoice-numbers');
  const numbers = await postJson('/api/akinsoft/push-invoice-numbers', {
    ...settings,
    invoiceIds: ids,
  });
  console.log(
    `status=${numbers.status} ok=${numbers.json?.ok} success=${numbers.json?.success} failed=${numbers.json?.failed}`,
  );
  for (const item of numbers.json?.items || []) {
    const mark = item.ok ? (item.skipped ? 'SKIP' : 'OK') : 'FAIL';
    console.log(
      `  [${mark}] ${item.invoiceNumber || item.invoiceId}: ${item.reason || ''}`,
    );
  }

  const createTargets = result.rows
    .filter((row) => !row.source_id)
    .map((row) => String(row.id));
  if (createTargets.length) {
    console.log(`\n→ push-invoices (${createTargets.length} eşleşmemiş)`);
    const created = await postJson('/api/akinsoft/push-invoices', {
      ...settings,
      invoiceIds: createTargets,
    });
    console.log(
      `status=${created.status} ok=${created.json?.ok} success=${created.json?.success} failed=${created.json?.failed}`,
    );
    for (const item of created.json?.items || []) {
      const mark = item.ok ? (item.skipped ? 'SKIP' : 'OK') : 'FAIL';
      console.log(
        `  [${mark}] ${item.invoiceNumber || item.invoiceId}: ${item.reason || ''}`,
      );
    }
  }

  console.log('\nBitti.');
}

main().catch((error) => {
  console.error(error?.message || error);
  process.exit(1);
});
