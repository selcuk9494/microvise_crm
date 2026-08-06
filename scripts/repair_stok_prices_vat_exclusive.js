/**
 * One-shot: WOLVOX STOK_FIYAT (KDV hariç) → CRM products.sale_price / currency.
 * Additionally unwrap CRM prices that look like WOL*(1+KDV) and fix orphan PAX rows.
 *
 * Usage: node scripts/repair_stok_prices_vat_exclusive.js
 */
const sql = require('mssql');
const { Client } = require('pg');
const fs = require('fs');
const path = require('path');

function loadDotEnvLocal() {
  const file = path.join(process.cwd(), '.env.local');
  if (!fs.existsSync(file)) return;
  for (const line of fs.readFileSync(file, 'utf8').split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith('#')) continue;
    const i = t.indexOf('=');
    if (i <= 0) continue;
    const k = t.slice(0, i).trim();
    const v = t.slice(i + 1).trim().replace(/^["']|["']$/g, '');
    if (!process.env[k]) process.env[k] = v;
  }
}

function normalizeCurrency(value) {
  const text = value == null ? '' : String(value).trim();
  if (!text) return 'TRY';
  const upper = text.toLocaleUpperCase('tr-TR');
  if (upper === '$' || upper.includes('USD') || upper.includes('DOLAR') || upper.includes('DOVIZ') || upper.includes('DÖVİZ')) {
    return 'USD';
  }
  if (upper === '€' || upper.includes('EUR') || upper.includes('EURO')) return 'EUR';
  if (upper === '£' || upper.includes('GBP') || upper.includes('STERLIN')) return 'GBP';
  if (upper === 'TL' || upper.includes('TRY') || upper.includes('TURK') || upper.includes('KPB')) {
    return 'TRY';
  }
  return ['TRY', 'USD', 'EUR', 'GBP'].includes(upper) ? upper : 'TRY';
}

function round2(n) {
  return Math.round(Number(n) * 100) / 100;
}

function looksVatInclusive(salePrice, taxRate) {
  const tax = Number(taxRate) || 0;
  const price = Number(salePrice) || 0;
  if (!(price > 0) || !(tax > 0)) return null;
  const exclusive = round2(price / (1 + tax / 100));
  if (!(exclusive > 0) || exclusive >= price) return null;
  const reincl = round2(exclusive * (1 + tax / 100));
  if (Math.abs(reincl - price) > 0.02) return null;
  return exclusive;
}

async function main() {
  loadDotEnvLocal();
  const mssqlPool = await sql.connect({
    server: process.env.AKINSOFT_MSSQL_HOST,
    port: Number(process.env.AKINSOFT_MSSQL_PORT || 1433),
    database: process.env.AKINSOFT_MSSQL_DATABASE,
    user: process.env.AKINSOFT_MSSQL_USERNAME,
    password: process.env.AKINSOFT_MSSQL_PASSWORD,
    options: { encrypt: false, trustServerCertificate: true, enableArithAbort: true },
    connectionTimeout: 15000,
    requestTimeout: 60000,
  });

  const wolRows = (
    await mssqlPool.request().query(`
      ;with ranked as (
        select
          s.BLKODU,
          s.STOKKODU,
          s.STOK_ADI,
          s.DOVIZ_BIRIMI,
          s.DOVIZ_KULLAN,
          s.KDV_ORANI,
          f.FIYATI,
          f.HESAP,
          f.KPB_MI,
          row_number() over (
            partition by s.BLKODU
            order by
              case when f.FIYAT_NO = 1 then 0 else 1 end,
              case
                when f.KPB_MI = 2 then 0
                when upper(ltrim(rtrim(isnull(f.HESAP, '')))) not in ('', 'TL', 'TRY', 'KPB') then 0
                else 1
              end,
              f.FIYATI desc
          ) as rn
        from dbo.STOK s
        join dbo.STOK_FIYAT f on f.BLSTKODU = s.BLKODU
        where f.ALIS_SATIS = 2 and f.FIYATI > 0
      )
      select * from ranked where rn = 1
    `)
  ).recordset;

  const byCode = new Map();
  const byBlkodu = new Map();
  for (const row of wolRows) {
    const salePrice = Number(row.FIYATI) || 0;
    let currency = 'TRY';
    if (row.HESAP) currency = normalizeCurrency(row.HESAP);
    else if (Number(row.KPB_MI) === 2) currency = normalizeCurrency(row.DOVIZ_BIRIMI) || 'USD';
    else if (Number(row.DOVIZ_KULLAN) === 1) currency = normalizeCurrency(row.DOVIZ_BIRIMI) || 'USD';
    const mapped = {
      blkodu: String(row.BLKODU),
      code: String(row.STOKKODU || '').trim(),
      name: row.STOK_ADI,
      salePrice,
      currency,
      taxRate: Number(row.KDV_ORANI) || 0,
    };
    byBlkodu.set(mapped.blkodu, mapped);
    if (mapped.code) byCode.set(mapped.code, mapped);
  }

  const pg = new Client({
    connectionString: process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false },
  });
  await pg.connect();

  const crm = await pg.query(`
    select id, code, name, sale_price::float as sale_price, currency,
           tax_rate::float as tax_rate, akinsoft_source_id, product_type
    from public.products
    where coalesce(is_active, true) = true
  `);

  const changes = [];
  for (const p of crm.rows) {
    const wol =
      (p.code && byCode.get(p.code)) ||
      (p.akinsoft_source_id && byBlkodu.get(String(p.akinsoft_source_id))) ||
      null;

    let nextPrice = Number(p.sale_price) || 0;
    let nextCurrency = normalizeCurrency(p.currency || 'TRY');
    let reason = null;

    if (wol && wol.salePrice > 0) {
      const incl = round2(wol.salePrice * (1 + (wol.taxRate || p.tax_rate || 0) / 100));
      const crmPrice = Number(p.sale_price) || 0;
      const matchIncl =
        crmPrice > 0 && Math.abs(crmPrice - incl) <= 0.05;
      const matchExcl =
        crmPrice > 0 && Math.abs(crmPrice - wol.salePrice) <= 0.02;
      if (!matchExcl || nextCurrency !== wol.currency || crmPrice === 0) {
        nextPrice = round2(wol.salePrice);
        nextCurrency = wol.currency;
        reason = matchIncl
          ? 'wol-exclusive (was ~VAT-inclusive)'
          : crmPrice === 0
            ? 'wol-fill-zero'
            : 'wol-overwrite';
      }
    } else if (p.product_type === 'product' && nextPrice > 0) {
      const exclusive = looksVatInclusive(nextPrice, p.tax_rate);
      const name = String(p.name || '');
      const code = String(p.code || '');
      const orphanFx =
        /PAX|WORLDLINE|ÖKC|OKC|PINPAD|A910|B910/i.test(`${name} ${code}`) ||
        code === 'MVa4bebff43e5b' ||
        code === 'MVc711a48d6e86';
      if (exclusive != null && orphanFx) {
        nextPrice = exclusive;
        nextCurrency = 'USD';
        reason = 'orphan-unwrap-vat-inclusive';
      }
    }

    if (
      reason &&
      (round2(nextPrice) !== round2(p.sale_price) ||
        nextCurrency !== normalizeCurrency(p.currency || 'TRY'))
    ) {
      changes.push({
        id: p.id,
        code: p.code,
        name: p.name,
        before: { price: Number(p.sale_price), currency: p.currency },
        after: { price: nextPrice, currency: nextCurrency },
        reason,
      });
    }
  }

  for (const c of changes) {
    await pg.query(
      `update public.products set sale_price = $2, currency = $3 where id = $1`,
      [c.id, c.after.price, c.after.currency],
    );
  }

  console.log(JSON.stringify({ fixed: changes.length, samples: changes.slice(0, 40) }, null, 2));
  if (changes.length > 40) {
    console.log(`... and ${changes.length - 40} more`);
  }

  await pg.end();
  await mssqlPool.close();
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
