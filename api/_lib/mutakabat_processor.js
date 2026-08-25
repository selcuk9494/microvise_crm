const xlsx = require('xlsx');
const XLSXStyle = require('xlsx-js-style');

const YKB_APP = 'ykb (koop bank)';
const PAX_MODEL = 'a910sf';

function normalizeHeader(input) {
  return String(input || '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/ı/g, 'i')
    .replace(/ğ/g, 'g')
    .replace(/ü/g, 'u')
    .replace(/ş/g, 's')
    .replace(/ö/g, 'o')
    .replace(/ç/g, 'c')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim()
    .replace(/\s+/g, ' ');
}

function findHeaderIndex(headers, candidates) {
  const normalized = headers.map(normalizeHeader);
  for (const cand of candidates) {
    const n = normalizeHeader(cand);
    const idx = normalized.indexOf(n);
    if (idx >= 0) return idx;
  }
  for (const cand of candidates) {
    const n = normalizeHeader(cand);
    const idx = normalized.findIndex((h) => h.includes(n) || n.includes(h));
    if (idx >= 0) return idx;
  }
  return -1;
}

function toNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  const s = String(value ?? '')
    .trim()
    .replace(',', '.');
  const n = Number(s);
  return Number.isFinite(n) ? n : 0;
}

function readMatrix(buffer) {
  const wb = xlsx.read(buffer, { type: 'buffer', cellDates: true, raw: false });
  const sheet = wb.Sheets[wb.SheetNames[0]];
  return xlsx.utils.sheet_to_json(sheet, {
    header: 1,
    defval: '',
    raw: false,
  });
}

function classifyRow(row) {
  const app = normalizeHeader(row.appName);
  const model = normalizeHeader(row.model);
  if (app === YKB_APP || app.includes('koop')) return 'YKB';
  if (model === PAX_MODEL || model.includes('a910sf') || model.includes('paxa910')) {
    return 'PAX';
  }
  return 'INGENICO';
}

/** GMP3 / TSM satırları: PAX A910SF → PAX, diğerleri → INGENICO */
function classifyDeviceBrand(model) {
  const m = normalizeHeader(model);
  if (m.includes('a910sf') || m.includes('paxa910') || m === PAX_MODEL) {
    return 'PAX';
  }
  return 'INGENICO';
}

function countByBankTier(rows) {
  const counter = {};
  for (const row of rows) {
    const n = Math.max(0, Math.round(row.bankCount));
    counter[n] = (counter[n] || 0) + 1;
  }
  return counter;
}

function counterToObject(mapOrObj) {
  if (mapOrObj instanceof Map) {
    const out = {};
    for (const [k, v] of mapOrObj.entries()) out[String(k)] = v;
    return out;
  }
  return { ...mapOrObj };
}

function loadBankRows(buffer) {
  const matrix = readMatrix(buffer);
  if (!matrix.length) throw new Error('Banka Excel dosyası boş.');

  const headers = matrix[0].map((h) => String(h ?? ''));
  const idx = {
    appName: findHeaderIndex(headers, ['Uygulama Adi', 'Uygulama Adı']),
    model: findHeaderIndex(headers, ['Cihaz Modeli']),
    bankCount: findHeaderIndex(headers, [
      'Uzerindeki Banka Uygulama Sayısı',
      'Üzerindeki Banka Uygulama Sayısı',
    ]),
    bankCountAlt: findHeaderIndex(headers, ['Banka Adet']),
  };
  if (idx.appName < 0 || idx.model < 0) {
    throw new Error('Banka dosyasında Uygulama Adı veya Cihaz Modeli sütunu bulunamadı.');
  }
  if (idx.bankCount < 0 && idx.bankCountAlt < 0) {
    throw new Error('Banka dosyasında banka sayısı sütunu bulunamadı.');
  }

  const rows = [];
  for (let r = 1; r < matrix.length; r++) {
    const line = matrix[r];
    if (!line || line.every((c) => String(c ?? '').trim() === '')) continue;
    const record = {};
    for (let c = 0; c < headers.length; c++) {
      record[headers[c] || `col_${c}`] = line[c] ?? '';
    }
    rows.push({
      raw: record,
      appName: String(line[idx.appName] ?? ''),
      model: String(line[idx.model] ?? ''),
      bankCount: toNumber(
        line[idx.bankCount >= 0 ? idx.bankCount : idx.bankCountAlt],
      ),
      group: null,
    });
  }
  for (const row of rows) row.group = classifyRow(row);
  return { headers, rows };
}

function isYes(value) {
  const s = String(value ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
  return s === 'yes' || s === 'evet' || s === 'true' || s === '1';
}

function isVar(value) {
  const s = String(value ?? '')
    .trim()
    .toLowerCase()
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '');
  return s === 'var' || s === 'yes' || s === 'evet' || s === 'true' || s === '1';
}

function loadGmp3Rows(buffer) {
  const matrix = readMatrix(buffer);
  if (!matrix.length) throw new Error('GMP3 Excel dosyası boş.');

  const headers = matrix[0].map((h) => String(h ?? ''));
  const idx = {
    sicil: findHeaderIndex(headers, ['Sicil', 'Sicil No', 'Seri No']),
    model: findHeaderIndex(headers, ['Cihaz Modeli']),
    yetki: findHeaderIndex(headers, [
      'Harici Cihaz Yetkisi Açık',
      'Harici Cihaz Yetkisi Acik',
      'Harici Cihaz Yetkisi',
    ]),
  };
  if (idx.sicil < 0) throw new Error('GMP3 dosyasında Sicil sütunu bulunamadı.');
  if (idx.yetki < 0) {
    throw new Error('GMP3 dosyasında Harici Cihaz Yetkisi sütunu bulunamadı.');
  }

  const seen = new Set();
  const rows = [];
  let rawYesCount = 0;
  for (let r = 1; r < matrix.length; r++) {
    const line = matrix[r];
    if (!line || line.every((c) => String(c ?? '').trim() === '')) continue;
    if (!isYes(line[idx.yetki])) continue;
    rawYesCount += 1;
    const sicil = String(line[idx.sicil] ?? '').trim();
    if (!sicil || seen.has(sicil)) continue;
    seen.add(sicil);
    const record = {};
    for (let c = 0; c < headers.length; c++) {
      record[headers[c] || `col_${c}`] = line[c] ?? '';
    }
    const model = idx.model >= 0 ? String(line[idx.model] ?? '') : '';
    rows.push({
      raw: record,
      model,
      brand: classifyDeviceBrand(model),
    });
  }
  return {
    headers,
    rows,
    rawYesCount,
    duplicateSkipped: rawYesCount - rows.length,
  };
}

function loadTsmRows(buffer) {
  const matrix = readMatrix(buffer);
  if (!matrix.length) throw new Error('TSM Excel dosyası boş.');

  const headers = matrix[0].map((h) => String(h ?? ''));
  const idx = {
    sicil: findHeaderIndex(headers, ['Sicil No', 'Sicil', 'Seri No']),
    model: findHeaderIndex(headers, ['Cihaz Modeli']),
    lisans: findHeaderIndex(headers, ['Uygulama Lisansı', 'Uygulama Lisansi']),
  };
  if (idx.lisans < 0) {
    throw new Error('TSM dosyasında Uygulama Lisansı sütunu bulunamadı.');
  }
  if (idx.sicil < 0) throw new Error('TSM dosyasında Sicil No sütunu bulunamadı.');

  const seen = new Set();
  const rows = [];
  let rawVarCount = 0;
  for (let r = 1; r < matrix.length; r++) {
    const line = matrix[r];
    if (!line || line.every((c) => String(c ?? '').trim() === '')) continue;
    if (!isVar(line[idx.lisans])) continue;
    rawVarCount += 1;
    const sicil = String(line[idx.sicil] ?? '').trim();
    if (!sicil || seen.has(sicil)) continue;
    seen.add(sicil);
    const record = {};
    for (let c = 0; c < headers.length; c++) {
      record[headers[c] || `col_${c}`] = line[c] ?? '';
    }
    const model = idx.model >= 0 ? String(line[idx.model] ?? '') : '';
    rows.push({
      raw: record,
      model,
      brand: classifyDeviceBrand(model),
    });
  }
  return {
    headers,
    rows,
    rawVarCount,
    duplicateSkipped: rawVarCount - rows.length,
  };
}

function normalizeUnitPrices(unitPrices = {}) {
  const bankTiers = unitPrices.bankTiers || unitPrices.bank_tiers || {};
  const ykbTiers = unitPrices.ykbTiers || unitPrices.ykb_tiers || bankTiers;
  const maxBankTier = Number(unitPrices.maxBankTier || unitPrices.max_bank_tier || 7);
  return {
    bankTiers: Object.fromEntries(
      Object.entries(bankTiers).map(([k, v]) => [String(k), Number(v) || 0]),
    ),
    ykbTiers: Object.fromEntries(
      Object.entries(ykbTiers).map(([k, v]) => [String(k), Number(v) || 0]),
    ),
    gmp3: Number(unitPrices.gmp3 ?? unitPrices.gmp3Price ?? 0) || 0,
    tsm: Number(unitPrices.tsm ?? unitPrices.tsmPrice ?? 0) || 0,
    maxBankTier: Number.isFinite(maxBankTier) && maxBankTier > 0 ? maxBankTier : 7,
  };
}

function priceFor(tier, map) {
  return Number(map?.[String(tier)] ?? map?.[tier] ?? 0) || 0;
}

function buildLineItems(groupName, counts, priceMap, invoiceSide) {
  const tiers = Object.keys(counts)
    .map(Number)
    .filter((n) => n > 0)
    .sort((a, b) => a - b);
  const maxTier = Math.max(
    7,
    ...(tiers.length ? tiers : [0]),
    ...Object.keys(priceMap).map(Number).filter((n) => n > 0),
  );
  const lines = [];
  let qtyTotal = 0;
  let amountTotal = 0;
  for (let n = 1; n <= maxTier; n++) {
    const qty = Number(counts[String(n)] ?? counts[n] ?? 0) || 0;
    const unit = priceFor(n, priceMap);
    const amount = qty * unit;
    qtyTotal += qty;
    amountTotal += amount;
    lines.push({
      group: groupName,
      bankTier: n,
      label: `${n} Banka`,
      quantity: qty,
      unitPrice: unit,
      microviseAmount: invoiceSide === 'microvise' ? amount : 0,
      worldlineAmount: invoiceSide === 'worldline' ? amount : 0,
    });
  }
  return {
    lines,
    qtyTotal,
    amountTotal,
    microviseTotal: invoiceSide === 'microvise' ? amountTotal : 0,
    worldlineTotal: invoiceSide === 'worldline' ? amountTotal : 0,
  };
}

/** YKB (Koop Bank): tek banka kabul — tüm cihazlar tek satırda toplanır. */
function buildYkbSingleLineItems(counts, priceMap) {
  const normalized = {};
  if (counts instanceof Map) {
    for (const [k, v] of counts.entries()) normalized[String(k)] = v;
  } else if (counts && typeof counts === 'object') {
    Object.assign(normalized, counts);
  }

  let qtyTotal = 0;
  for (const value of Object.values(normalized)) {
    qtyTotal += Number(value) || 0;
  }
  const unit =
    priceFor(1, priceMap) ||
    Object.values(priceMap || {})
      .map((v) => Number(v) || 0)
      .find((v) => v > 0) ||
    0;
  const amount = qtyTotal * unit;
  return {
    lines: [
      {
        group: 'YKB (Koop Bank)',
        bankTier: 1,
        label: '1 Banka',
        quantity: qtyTotal,
        unitPrice: unit,
        microviseAmount: 0,
        worldlineAmount: amount,
      },
    ],
    qtyTotal,
    amountTotal: amount,
    microviseTotal: 0,
    worldlineTotal: amount,
  };
}

function rowsToSheetData(headers, rows) {
  return {
    headers,
    rows: rows.map((row) => headers.map((h) => row.raw[h] ?? '')),
  };
}

function countRowsByBrand(rows) {
  const out = { INGENICO: 0, PAX: 0 };
  for (const row of rows || []) {
    const brand = row.brand === 'PAX' ? 'PAX' : 'INGENICO';
    out[brand] += 1;
  }
  return out;
}

function buildBrandIntegrations({ gmp3ByBrand, tsmByBrand, prices }) {
  const gmp3Unit = prices.gmp3;
  const tsmUnit = prices.tsm;
  const ingGmp3 = Number(gmp3ByBrand?.INGENICO || 0);
  const paxGmp3 = Number(gmp3ByBrand?.PAX || 0);
  const ingTsm = Number(tsmByBrand?.INGENICO || 0);
  const paxTsm = Number(tsmByBrand?.PAX || 0);
  return [
    {
      key: 'ingenico_gmp3',
      brand: 'INGENICO',
      kind: 'gmp3',
      label: 'INGENICO GMP3',
      quantity: ingGmp3,
      unitPrice: gmp3Unit,
      worldlineAmount: ingGmp3 * gmp3Unit,
    },
    {
      key: 'pax_gmp3',
      brand: 'PAX',
      kind: 'gmp3',
      label: 'PAX GMP3',
      quantity: paxGmp3,
      unitPrice: gmp3Unit,
      worldlineAmount: paxGmp3 * gmp3Unit,
    },
    {
      key: 'ingenico_tsm',
      brand: 'INGENICO',
      kind: 'tsm',
      label: 'INGENICO IRESTO',
      quantity: ingTsm,
      unitPrice: tsmUnit,
      worldlineAmount: ingTsm * tsmUnit,
    },
    {
      key: 'pax_tsm',
      brand: 'PAX',
      kind: 'tsm',
      label: 'PAX IRESTO',
      quantity: paxTsm,
      unitPrice: tsmUnit,
      worldlineAmount: paxTsm * tsmUnit,
    },
  ];
}

/** Kayıtlı detail_sheets içinden Cihaz Modeli ile marka kırılımı üretir. */
function brandCountsFromSheetData(sheetData) {
  const out = { INGENICO: 0, PAX: 0 };
  if (!sheetData || !Array.isArray(sheetData.headers) || !Array.isArray(sheetData.rows)) {
    return out;
  }
  const modelIdx = findHeaderIndex(sheetData.headers, ['Cihaz Modeli']);
  if (modelIdx < 0) {
    // Model yoksa tamamı INGENICO kabul (eski davranışa yakın)
    out.INGENICO = sheetData.rows.length;
    return out;
  }
  for (const row of sheetData.rows) {
    const model = Array.isArray(row) ? row[modelIdx] : '';
    const brand = classifyDeviceBrand(model);
    out[brand] += 1;
  }
  return out;
}

function ensureBrandIntegrations(summary, detailSheets, unitPrices) {
  const prices = normalizeUnitPrices(unitPrices);
  const integrations = Array.isArray(summary?.integrations) ? summary.integrations : [];
  const hasBrandKeys = integrations.some((i) =>
    String(i?.key || '').includes('ingenico_') || String(i?.key || '').includes('pax_'),
  );
  if (hasBrandKeys && integrations.length >= 4) {
    return summary;
  }

  let gmp3ByBrand = {
    INGENICO: Number(summary?.gmp3?.ingenico || 0),
    PAX: Number(summary?.gmp3?.pax || 0),
  };
  let tsmByBrand = {
    INGENICO: Number(summary?.tsm?.ingenico || 0),
    PAX: Number(summary?.tsm?.pax || 0),
  };

  const gmp3Total = Number(summary?.gmp3?.count || 0);
  const tsmTotal = Number(summary?.tsm?.count || 0);
  if (gmp3ByBrand.INGENICO + gmp3ByBrand.PAX === 0 && detailSheets?.gmp3) {
    gmp3ByBrand = brandCountsFromSheetData(detailSheets.gmp3);
  }
  if (tsmByBrand.INGENICO + tsmByBrand.PAX === 0 && detailSheets?.tsm) {
    tsmByBrand = brandCountsFromSheetData(detailSheets.tsm);
  }
  // Hâlâ 0 ama toplam varsa eski kayıt: tümünü INGENICO'ya yaz
  if (gmp3ByBrand.INGENICO + gmp3ByBrand.PAX === 0 && gmp3Total > 0) {
    gmp3ByBrand = { INGENICO: gmp3Total, PAX: 0 };
  }
  if (tsmByBrand.INGENICO + tsmByBrand.PAX === 0 && tsmTotal > 0) {
    tsmByBrand = { INGENICO: tsmTotal, PAX: 0 };
  }

  const brandIntegrations = buildBrandIntegrations({
    gmp3ByBrand,
    tsmByBrand,
    prices,
  });
  const worldlineIntegrations = brandIntegrations.reduce(
    (s, i) => s + (Number(i.worldlineAmount) || 0),
    0,
  );
  const worldlineBank = Number(summary?.totals?.worldlineBank || 0);
  const microviseGrand = Number(summary?.totals?.microviseGrand || 0);

  return {
    ...summary,
    gmp3: {
      ...(summary?.gmp3 || {}),
      count: gmp3ByBrand.INGENICO + gmp3ByBrand.PAX,
      ingenico: gmp3ByBrand.INGENICO,
      pax: gmp3ByBrand.PAX,
    },
    tsm: {
      ...(summary?.tsm || {}),
      count: tsmByBrand.INGENICO + tsmByBrand.PAX,
      ingenico: tsmByBrand.INGENICO,
      pax: tsmByBrand.PAX,
    },
    integrations: brandIntegrations,
    totals: {
      ...(summary?.totals || {}),
      worldlineIntegrations,
      worldlineGrand: worldlineBank + worldlineIntegrations,
      microviseGrand,
    },
  };
}

function mapCountsToLines(groupName, counts, priceMap, invoiceSide) {
  const normalized = {};
  if (counts instanceof Map) {
    for (const [k, v] of counts.entries()) normalized[String(k)] = v;
  } else if (counts && typeof counts === 'object') {
    Object.assign(normalized, counts);
  }
  return buildLineItems(groupName, normalized, priceMap, invoiceSide);
}

function recalculateSummary(summary, unitPrices) {
  const prices = normalizeUnitPrices(unitPrices);
  const ing = mapCountsToLines(
    'INGENICO',
    summary?.ingenico || {},
    prices.bankTiers,
    'microvise',
  );
  const pax = mapCountsToLines(
    'PAX (A910SF)',
    summary?.pax || {},
    prices.bankTiers,
    'microvise',
  );
  const ykb = buildYkbSingleLineItems(summary?.ykb || {}, prices.ykbTiers);

  const gmp3ByBrand = {
    INGENICO:
      Number(summary?.gmp3?.ingenico ?? 0) ||
      Number(
        (summary?.integrations || []).find((i) => i.key === 'ingenico_gmp3')
          ?.quantity || 0,
      ),
    PAX:
      Number(summary?.gmp3?.pax ?? 0) ||
      Number(
        (summary?.integrations || []).find((i) => i.key === 'pax_gmp3')
          ?.quantity || 0,
      ),
  };
  const tsmByBrand = {
    INGENICO:
      Number(summary?.tsm?.ingenico ?? 0) ||
      Number(
        (summary?.integrations || []).find((i) => i.key === 'ingenico_tsm')
          ?.quantity || 0,
      ),
    PAX:
      Number(summary?.tsm?.pax ?? 0) ||
      Number(
        (summary?.integrations || []).find((i) => i.key === 'pax_tsm')
          ?.quantity || 0,
      ),
  };
  // Eski kayıt: sadece toplam count varsa
  const gmp3CountLegacy = Number(summary?.gmp3?.count || 0) || 0;
  const tsmCountLegacy = Number(summary?.tsm?.count || 0) || 0;
  if (gmp3ByBrand.INGENICO + gmp3ByBrand.PAX === 0 && gmp3CountLegacy > 0) {
    gmp3ByBrand.INGENICO = gmp3CountLegacy;
  }
  if (tsmByBrand.INGENICO + tsmByBrand.PAX === 0 && tsmCountLegacy > 0) {
    tsmByBrand.INGENICO = tsmCountLegacy;
  }

  const integrations = buildBrandIntegrations({
    gmp3ByBrand,
    tsmByBrand,
    prices,
  });
  const worldlineIntegrations = integrations.reduce(
    (s, i) => s + (Number(i.worldlineAmount) || 0),
    0,
  );
  const gmp3Count = gmp3ByBrand.INGENICO + gmp3ByBrand.PAX;
  const tsmCount = tsmByBrand.INGENICO + tsmByBrand.PAX;

  const nextSummary = {
    ...summary,
    lineItems: [...ing.lines, ...pax.lines, ...ykb.lines],
    gmp3: {
      ...(summary?.gmp3 || {}),
      count: gmp3Count,
      ingenico: gmp3ByBrand.INGENICO,
      pax: gmp3ByBrand.PAX,
    },
    tsm: {
      ...(summary?.tsm || {}),
      count: tsmCount,
      ingenico: tsmByBrand.INGENICO,
      pax: tsmByBrand.PAX,
    },
    integrations,
    totals: {
      microviseBank: ing.microviseTotal + pax.microviseTotal,
      worldlineBank: ykb.worldlineTotal,
      worldlineIntegrations,
      microviseGrand: ing.microviseTotal + pax.microviseTotal,
      worldlineGrand: ykb.worldlineTotal + worldlineIntegrations,
    },
  };
  return { summary: nextSummary, unitPrices: prices };
}

function processMutakabat({ bankBuffer, gmp3Buffer, tsmBuffer, unitPrices }) {
  if (!bankBuffer) throw new Error('Banka Excel dosyası zorunludur.');
  const prices = normalizeUnitPrices(unitPrices);

  const bank = loadBankRows(bankBuffer);
  const ingenicoRows = bank.rows.filter((r) => r.group === 'INGENICO');
  const paxRows = bank.rows.filter((r) => r.group === 'PAX');
  const ykbRows = bank.rows.filter((r) => r.group === 'YKB');

  const ingenicoCounts = countByBankTier(ingenicoRows);
  const paxCounts = countByBankTier(paxRows);
  const ykbCounts = countByBankTier(ykbRows);

  let gmp3Data = null;
  if (gmp3Buffer) gmp3Data = loadGmp3Rows(gmp3Buffer);
  let tsmData = null;
  if (tsmBuffer) tsmData = loadTsmRows(tsmBuffer);

  const gmp3ByBrand = countRowsByBrand(gmp3Data?.rows);
  const tsmByBrand = countRowsByBrand(tsmData?.rows);
  const gmp3Count = gmp3ByBrand.INGENICO + gmp3ByBrand.PAX;
  const tsmCount = tsmByBrand.INGENICO + tsmByBrand.PAX;

  const ing = buildLineItems('INGENICO', ingenicoCounts, prices.bankTiers, 'microvise');
  const pax = buildLineItems('PAX (A910SF)', paxCounts, prices.bankTiers, 'microvise');
  const ykb = buildYkbSingleLineItems(ykbCounts, prices.ykbTiers);

  const integrations = buildBrandIntegrations({
    gmp3ByBrand,
    tsmByBrand,
    prices,
  });
  const worldlineIntegrationTotal = integrations.reduce(
    (s, i) => s + (Number(i.worldlineAmount) || 0),
    0,
  );

  const microviseBankTotal = ing.microviseTotal + pax.microviseTotal;
  const worldlineBankTotal = ykb.worldlineTotal;

  const summary = {
    ingenico: counterToObject(ingenicoCounts),
    pax: counterToObject(paxCounts),
    ykb: counterToObject(ykbCounts),
    gmp3: {
      count: gmp3Count,
      ingenico: gmp3ByBrand.INGENICO,
      pax: gmp3ByBrand.PAX,
      rawYesCount: gmp3Data?.rawYesCount || 0,
      duplicateSkipped: gmp3Data?.duplicateSkipped || 0,
    },
    tsm: {
      count: tsmCount,
      ingenico: tsmByBrand.INGENICO,
      pax: tsmByBrand.PAX,
      rawVarCount: tsmData?.rawVarCount || 0,
      duplicateSkipped: tsmData?.duplicateSkipped || 0,
    },
    lineItems: [...ing.lines, ...pax.lines, ...ykb.lines],
    integrations,
    totals: {
      microviseBank: microviseBankTotal,
      worldlineBank: worldlineBankTotal,
      worldlineIntegrations: worldlineIntegrationTotal,
      microviseGrand: microviseBankTotal,
      worldlineGrand: worldlineBankTotal + worldlineIntegrationTotal,
    },
    rowCounts: {
      bankTotal: bank.rows.length,
      ingenico: ingenicoRows.length,
      pax: paxRows.length,
      ykb: ykbRows.length,
      gmp3: gmp3Count,
      tsm: tsmCount,
      gmp3Ingenico: gmp3ByBrand.INGENICO,
      gmp3Pax: gmp3ByBrand.PAX,
      tsmIngenico: tsmByBrand.INGENICO,
      tsmPax: tsmByBrand.PAX,
    },
  };

  const detailSheets = {
    original: rowsToSheetData(bank.headers, bank.rows),
    ingenico: rowsToSheetData(bank.headers, ingenicoRows),
    pax: rowsToSheetData(bank.headers, paxRows),
    ykb: rowsToSheetData(bank.headers, ykbRows),
  };
  if (gmp3Data) {
    detailSheets.gmp3 = rowsToSheetData(gmp3Data.headers, gmp3Data.rows);
    detailSheets.gmp3_ingenico = rowsToSheetData(
      gmp3Data.headers,
      gmp3Data.rows.filter((r) => r.brand === 'INGENICO'),
    );
    detailSheets.gmp3_pax = rowsToSheetData(
      gmp3Data.headers,
      gmp3Data.rows.filter((r) => r.brand === 'PAX'),
    );
  }
  if (tsmData) {
    detailSheets.tsm = rowsToSheetData(tsmData.headers, tsmData.rows);
    detailSheets.tsm_ingenico = rowsToSheetData(
      tsmData.headers,
      tsmData.rows.filter((r) => r.brand === 'INGENICO'),
    );
    detailSheets.tsm_pax = rowsToSheetData(
      tsmData.headers,
      tsmData.rows.filter((r) => r.brand === 'PAX'),
    );
  }

  return { summary, detailSheets, unitPrices: prices };
}

function sheetFromData({ headers, rows }) {
  return XLSXStyle.utils.aoa_to_sheet([headers, ...rows]);
}

function money(n) {
  const v = Number(n) || 0;
  return Math.round(v * 100) / 100;
}

function styleCell(sheet, addr, style) {
  if (!sheet[addr]) sheet[addr] = { t: 's', v: '' };
  sheet[addr].s = { ...(sheet[addr].s || {}), ...style };
}

function applyRangeStyle(sheet, startRow, endRow, startCol, endCol, style) {
  for (let r = startRow; r <= endRow; r += 1) {
    for (let c = startCol; c <= endCol; c += 1) {
      const addr = XLSXStyle.utils.encode_cell({ r, c });
      styleCell(sheet, addr, style);
    }
  }
}

function setCell(sheet, r, c, value, style) {
  const addr = XLSXStyle.utils.encode_cell({ r, c });
  const isNum = typeof value === 'number' && Number.isFinite(value);
  sheet[addr] = isNum
    ? { t: 'n', v: value, z: '#,##0.00' }
    : { t: 's', v: value == null ? '' : String(value) };
  if (style) sheet[addr].s = style;
}

const COLORS = {
  // Microvise: lacivert | Worldline: worldline.com/tr-tr yeşili (#277777 / #E3F5F2)
  titleBg: '0F172A',
  titleFg: 'FFFFFF',
  microBg: 'F1F5F9',
  microHeader: '1E293B',
  worldBg: 'E3F5F2',
  worldHeader: '277777',
  ingenicoHeader: '1E3A5F',
  paxHeader: '243B55',
  ykbHeader: '277777',
  integHeader: '1F5C5C',
  headerFg: 'FFFFFF',
  tableHeader: 'E2E8F0',
  totalRow: 'F1F5F9',
  grandMicro: '1E293B',
  grandWorld: '1A5C5C',
  highlightMicroRow: 'E8EEF5',
  highlightWorldRow: 'D8EFEA',
  borderStrong: '0F172A',
  borderWorldStrong: '1A5C5C',
  groupIngenico: 'F8FAFC',
  groupPax: 'F1F5F9',
  groupYkb: 'E3F5F2',
  border: '94A3B8',
  label: '0F172A',
  muted: '64748B',
};

function borderThin() {
  const edge = { style: 'thin', color: { rgb: COLORS.border } };
  return { top: edge, bottom: edge, left: edge, right: edge };
}

function borderMedium(rgb) {
  const edge = { style: 'medium', color: { rgb: rgb || COLORS.borderStrong } };
  return { top: edge, bottom: edge, left: edge, right: edge };
}

function baseFont(overrides = {}) {
  return {
    name: 'Calibri',
    sz: 11,
    color: { rgb: COLORS.label },
    ...overrides,
  };
}

function buildGroupTableRows(groupName, items) {
  let filtered = (items || []).filter((i) => i.group === groupName && i.quantity > 0);

  // YKB her zaman tek satır: 1 Banka + toplam adet/tutar
  if (groupName === 'YKB (Koop Bank)' && filtered.length > 0) {
    const qty = filtered.reduce((s, i) => s + (i.quantity || 0), 0);
    const unit =
      filtered.find((i) => Number(i.unitPrice) > 0)?.unitPrice ||
      filtered[0].unitPrice ||
      0;
    const world =
      filtered.reduce((s, i) => s + (Number(i.worldlineAmount) || 0), 0) ||
      qty * Number(unit);
    filtered = [
      {
        label: '1 Banka',
        quantity: qty,
        unitPrice: unit,
        microviseAmount: 0,
        worldlineAmount: world,
      },
    ];
  }

  const rows = [];
  for (const item of filtered) {
    rows.push({
      label: item.label,
      qty: item.quantity,
      unit: money(item.unitPrice),
      micro: money(item.microviseAmount),
      world: money(item.worldlineAmount),
    });
  }
  const totals = filtered.reduce(
    (acc, item) => {
      acc.qty += item.quantity || 0;
      acc.micro += item.microviseAmount || 0;
      acc.world += item.worldlineAmount || 0;
      return acc;
    },
    { qty: 0, micro: 0, world: 0 },
  );
  return { rows, totals };
}

function buildDashboardSheet(summary, unitPrices, periodLabel) {
  const sheet = {};
  const merges = [];
  let r = 0;
  const maxCol = 4;

  const sectionHeaderStyle = (bg) => ({
    font: baseFont({ bold: true, color: { rgb: COLORS.headerFg } }),
    fill: { patternType: 'solid', fgColor: { rgb: bg } },
    alignment: { horizontal: 'left', vertical: 'center' },
    border: borderThin(),
  });
  const colHeaderStyle = {
    font: baseFont({ bold: true, sz: 10 }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.tableHeader } },
    alignment: { horizontal: 'center', vertical: 'center' },
    border: borderThin(),
  };
  const bodyStyle = {
    font: baseFont(),
    border: borderThin(),
    alignment: { vertical: 'center' },
  };
  const moneyStyle = {
    ...bodyStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };
  const totalStyle = {
    font: baseFont({ bold: true }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.totalRow } },
    border: borderThin(),
  };
  const totalMoneyStyle = {
    ...totalStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };

  function fillRow(style) {
    for (let c = 0; c <= maxCol; c += 1) {
      if (!sheet[XLSXStyle.utils.encode_cell({ r, c })]) {
        setCell(sheet, r, c, '', style);
      } else if (style) {
        styleCell(sheet, XLSXStyle.utils.encode_cell({ r, c }), style);
      }
    }
  }

  function writeTitleRow(text, bg) {
    setCell(sheet, r, 0, text, sectionHeaderStyle(bg));
    for (let c = 1; c <= maxCol; c += 1) setCell(sheet, r, c, '', sectionHeaderStyle(bg));
    merges.push({ s: { r, c: 0 }, e: { r, c: maxCol } });
    r += 1;
  }

  function writeSimpleTable(headers, dataRows, totalLabel, totalQty, totalAmount) {
    headers.forEach((h, c) => setCell(sheet, r, c, h, colHeaderStyle));
    r += 1;
    if (!dataRows.length) {
      setCell(sheet, r, 0, 'Kayıt yok', bodyStyle);
      for (let c = 1; c <= maxCol; c += 1) setCell(sheet, r, c, '', bodyStyle);
      merges.push({ s: { r, c: 0 }, e: { r, c: maxCol } });
      r += 1;
    } else {
      for (const row of dataRows) {
        setCell(sheet, r, 0, row[0], bodyStyle);
        setCell(sheet, r, 1, row[1], {
          ...bodyStyle,
          alignment: { horizontal: 'center', vertical: 'center' },
        });
        setCell(sheet, r, 2, row[2], moneyStyle);
        setCell(sheet, r, 3, row[3], moneyStyle);
        setCell(sheet, r, 4, '', bodyStyle);
        r += 1;
      }
      setCell(sheet, r, 0, totalLabel, totalStyle);
      setCell(sheet, r, 1, totalQty, {
        ...totalStyle,
        alignment: { horizontal: 'center' },
      });
      setCell(sheet, r, 2, '', totalStyle);
      setCell(sheet, r, 3, money(totalAmount), totalMoneyStyle);
      setCell(sheet, r, 4, '', totalStyle);
      r += 1;
    }
    r += 1;
  }

  // --- Başlık ---
  writeTitleRow('Worldline / Microvise Mutakabat', COLORS.titleBg);
  writeTitleRow(periodLabel ? `Dönem: ${periodLabel}` : 'Dönem: —', COLORS.titleBg);
  r += 1;

  const ingenico = buildGroupTableRows('INGENICO', summary.lineItems);
  const pax = buildGroupTableRows('PAX (A910SF)', summary.lineItems);
  const ykb = buildGroupTableRows('YKB (Koop Bank)', summary.lineItems);
  const integrations = summary.integrations || [];
  const integOf = (key) => integrations.find((i) => i.key === key) || null;
  const ingenicoGmp3 = integOf('ingenico_gmp3');
  const paxGmp3 = integOf('pax_gmp3');
  const ingenicoTsm = integOf('ingenico_tsm');
  const paxTsm = integOf('pax_tsm');
  const legacyGmp3 = integOf('gmp3');
  const legacyTsm = integOf('tsm');
  const hasBrandGmp3 = Boolean(ingenicoGmp3 || paxGmp3);
  const hasBrandTsm = Boolean(ingenicoTsm || paxTsm);
  const ingGmp3Qty = hasBrandGmp3
    ? Number(ingenicoGmp3?.quantity) || 0
    : Number(legacyGmp3?.quantity) || 0;
  const ingGmp3Amount = hasBrandGmp3
    ? Number(ingenicoGmp3?.worldlineAmount) || 0
    : Number(legacyGmp3?.worldlineAmount) || 0;
  const paxGmp3Qty = Number(paxGmp3?.quantity) || 0;
  const paxGmp3Amount = Number(paxGmp3?.worldlineAmount) || 0;
  const ingTsmQty = hasBrandTsm
    ? Number(ingenicoTsm?.quantity) || 0
    : Number(legacyTsm?.quantity) || 0;
  const ingTsmAmount = hasBrandTsm
    ? Number(ingenicoTsm?.worldlineAmount) || 0
    : Number(legacyTsm?.worldlineAmount) || 0;
  const paxTsmQty = Number(paxTsm?.quantity) || 0;
  const paxTsmAmount = Number(paxTsm?.worldlineAmount) || 0;
  const gmp3Qty = ingGmp3Qty + paxGmp3Qty;
  const gmp3Amount = ingGmp3Amount + paxGmp3Amount;
  const tsmQty = ingTsmQty + paxTsmQty;
  const tsmAmount = ingTsmAmount + paxTsmAmount;
  const gmp3Unit =
    Number(
      ingenicoGmp3?.unitPrice ??
        paxGmp3?.unitPrice ??
        legacyGmp3?.unitPrice,
    ) || 0;
  const tsmUnit =
    Number(
      ingenicoTsm?.unitPrice ?? paxTsm?.unitPrice ?? legacyTsm?.unitPrice,
    ) || 0;

  // --- Üst özet: iki taraf yan yana ---
  setCell(sheet, r, 0, 'FATURA ÖZETİ — Taraflar Ayrı', {
    font: baseFont({ bold: true, sz: 12 }),
  });
  merges.push({ s: { r, c: 0 }, e: { r, c: maxCol } });
  r += 1;

  setCell(sheet, r, 0, 'Microvise Keseceği Fatura', sectionHeaderStyle(COLORS.microHeader));
  setCell(sheet, r, 1, '', sectionHeaderStyle(COLORS.microHeader));
  merges.push({ s: { r, c: 0 }, e: { r, c: 1 } });
  setCell(sheet, r, 2, '', { border: borderThin() });
  setCell(sheet, r, 3, 'Worldline Keseceği Fatura', sectionHeaderStyle(COLORS.worldHeader));
  setCell(sheet, r, 4, '', sectionHeaderStyle(COLORS.worldHeader));
  merges.push({ s: { r, c: 3 }, e: { r, c: 4 } });
  r += 1;

  setCell(sheet, r, 0, money(summary.totals.microviseGrand), {
    font: baseFont({ bold: true, sz: 14 }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.microBg } },
    alignment: { horizontal: 'center', vertical: 'center' },
    border: borderThin(),
    numFmt: '₺#,##0.00',
  });
  setCell(sheet, r, 1, '', {
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.microBg } },
    border: borderThin(),
  });
  merges.push({ s: { r, c: 0 }, e: { r, c: 1 } });
  setCell(sheet, r, 2, '', { border: borderThin() });
  setCell(sheet, r, 3, money(summary.totals.worldlineGrand), {
    font: baseFont({ bold: true, sz: 14 }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.worldBg } },
    alignment: { horizontal: 'center', vertical: 'center' },
    border: borderThin(),
    numFmt: '₺#,##0.00',
  });
  setCell(sheet, r, 4, '', {
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.worldBg } },
    border: borderThin(),
  });
  merges.push({ s: { r, c: 3 }, e: { r, c: 4 } });
  r += 2;

  // --- Ürün satırları (ayrı) ---
  writeTitleRow('ÜRÜN SATIRLARI — Ayrı Özet', COLORS.titleBg);
  setCell(sheet, r, 0, 'Ürün', colHeaderStyle);
  setCell(sheet, r, 1, 'Adet', colHeaderStyle);
  setCell(sheet, r, 2, 'Taraf', colHeaderStyle);
  setCell(sheet, r, 3, 'Tutar', colHeaderStyle);
  setCell(sheet, r, 4, '', colHeaderStyle);
  r += 1;
  const productRows = [
    ['INGENICO', ingenico.totals.qty, 'Microvise', ingenico.totals.micro],
    ['PAX', pax.totals.qty, 'Microvise', pax.totals.micro],
    ['INGENICO GMP3', ingGmp3Qty, 'Worldline', ingGmp3Amount],
    ['PAX GMP3', paxGmp3Qty, 'Worldline', paxGmp3Amount],
    ['INGENICO IRESTO', ingTsmQty, 'Worldline', ingTsmAmount],
    ['PAX IRESTO', paxTsmQty, 'Worldline', paxTsmAmount],
  ];
  for (const row of productRows) {
    setCell(sheet, r, 0, row[0], bodyStyle);
    setCell(sheet, r, 1, row[1], {
      ...bodyStyle,
      alignment: { horizontal: 'center', vertical: 'center' },
    });
    setCell(sheet, r, 2, row[2], bodyStyle);
    setCell(sheet, r, 3, money(row[3]), moneyStyle);
    setCell(sheet, r, 4, '', bodyStyle);
    r += 1;
  }
  r += 1;

  // =========================================================
  // A) Microvise Keseceği Fatura (INGENICO + PAX)
  // =========================================================
  writeTitleRow(
    'A) Microvise Keseceği Fatura (INGENICO + PAX)',
    COLORS.microHeader,
  );

  writeTitleRow('INGENICO BANKA', COLORS.ingenicoHeader);
  writeSimpleTable(
    ['Banka Sayısı', 'Adet', 'Birim Fiyat', 'Tutar (Microvise)', ''],
    ingenico.rows.map((row) => [row.label, row.qty, row.unit, row.micro, '']),
    'INGENICO TOPLAM',
    ingenico.totals.qty,
    ingenico.totals.micro,
  );

  writeTitleRow('PAX BANKA', COLORS.paxHeader);
  writeSimpleTable(
    ['Banka Sayısı', 'Adet', 'Birim Fiyat', 'Tutar (Microvise)', ''],
    pax.rows.map((row) => [row.label, row.qty, row.unit, row.micro, '']),
    'PAX TOPLAM',
    pax.totals.qty,
    pax.totals.micro,
  );
  r += 1;

  // =========================================================
  // B) Worldline detayları
  // =========================================================
  writeTitleRow(
    'B) Worldline Detay (YKB + GMP3 + IRESTO)',
    COLORS.worldHeader,
  );

  writeTitleRow('YKB_KOOP BANKA', COLORS.ykbHeader);
  writeSimpleTable(
    ['Banka Sayısı', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    ykb.rows.map((row) => [row.label, row.qty, row.unit, row.world, '']),
    'YKB TOPLAM',
    ykb.totals.qty,
    ykb.totals.world,
  );

  writeTitleRow('INGENICO GMP3', COLORS.integHeader);
  writeSimpleTable(
    ['Açıklama', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    ingGmp3Qty || ingenicoGmp3 || legacyGmp3
      ? [['INGENICO GMP3', ingGmp3Qty, money(gmp3Unit), money(ingGmp3Amount), '']]
      : [],
    'INGENICO GMP3 TOPLAM',
    ingGmp3Qty,
    ingGmp3Amount,
  );

  writeTitleRow('PAX GMP3', COLORS.integHeader);
  writeSimpleTable(
    ['Açıklama', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    paxGmp3Qty || paxGmp3
      ? [['PAX GMP3', paxGmp3Qty, money(gmp3Unit), money(paxGmp3Amount), '']]
      : [],
    'PAX GMP3 TOPLAM',
    paxGmp3Qty,
    paxGmp3Amount,
  );

  writeTitleRow('INGENICO IRESTO', COLORS.integHeader);
  writeSimpleTable(
    ['Açıklama', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    ingTsmQty || ingenicoTsm || legacyTsm
      ? [['INGENICO IRESTO', ingTsmQty, money(tsmUnit), money(ingTsmAmount), '']]
      : [],
    'INGENICO IRESTO TOPLAM',
    ingTsmQty,
    ingTsmAmount,
  );

  writeTitleRow('PAX IRESTO', COLORS.integHeader);
  writeSimpleTable(
    ['Açıklama', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    paxTsmQty || paxTsm
      ? [['PAX IRESTO', paxTsmQty, money(tsmUnit), money(paxTsmAmount), '']]
      : [],
    'PAX IRESTO TOPLAM',
    paxTsmQty,
    paxTsmAmount,
  );

  const ykbUnitFromItems = (summary.lineItems || [])
    .filter((i) => i.group === 'YKB (Koop Bank)' && Number(i.unitPrice) > 0)
    .map((i) => Number(i.unitPrice));
  const ykbUnitNum =
    ykbUnitFromItems.length > 0
      ? ykbUnitFromItems[0]
      : ykb.totals.qty > 0
        ? ykb.totals.world / ykb.totals.qty
        : null;

  // 1) Marka detay (kendi toplamı) + YKB
  writeTitleRow('Worldline Detay — Marka', COLORS.integHeader);
  writeSimpleTable(
    ['Kalem', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    [
      ['INGENICO GMP3', ingGmp3Qty, money(gmp3Unit), money(ingGmp3Amount), ''],
      ['PAX GMP3', paxGmp3Qty, money(gmp3Unit), money(paxGmp3Amount), ''],
      ['INGENICO IRESTO', ingTsmQty, money(tsmUnit), money(ingTsmAmount), ''],
      ['PAX IRESTO', paxTsmQty, money(tsmUnit), money(paxTsmAmount), ''],
      [
        'YKB_KOOP BANKA',
        ykb.totals.qty,
        ykbUnitNum == null ? '—' : money(ykbUnitNum),
        money(ykb.totals.world),
        '',
      ],
    ],
    'DETAY TOPLAM',
    gmp3Qty + tsmQty + ykb.totals.qty,
    gmp3Amount + tsmAmount + ykb.totals.world,
  );

  // =========================================================
  // EN ALT: 2 özel fatura özeti (yan yana değil, alt alta vurgulu)
  // =========================================================
  writeTitleRow('FATURA ÖZETLERİ — ÖZEL', COLORS.titleBg);

  const microRowStyle = {
    font: baseFont({ bold: true, sz: 11 }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.highlightMicroRow } },
    border: borderMedium(COLORS.borderStrong),
    alignment: { vertical: 'center' },
  };
  const microRowMoney = {
    ...microRowStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };
  const microGrandStyle = {
    font: baseFont({ bold: true, sz: 13, color: { rgb: COLORS.headerFg } }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandMicro } },
    border: borderMedium(COLORS.borderStrong),
    alignment: { vertical: 'center' },
  };
  const microGrandMoney = {
    ...microGrandStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };

  writeTitleRow('Microvise Keseceği Fatura', COLORS.microHeader);
  setCell(sheet, r, 0, 'INGENICO', microRowStyle);
  setCell(sheet, r, 1, ingenico.totals.qty, {
    ...microRowStyle,
    alignment: { horizontal: 'center', vertical: 'center' },
  });
  setCell(sheet, r, 2, '', microRowStyle);
  setCell(sheet, r, 3, money(ingenico.totals.micro), microRowMoney);
  setCell(sheet, r, 4, '', microRowStyle);
  r += 1;
  setCell(sheet, r, 0, 'PAX', microRowStyle);
  setCell(sheet, r, 1, pax.totals.qty, {
    ...microRowStyle,
    alignment: { horizontal: 'center', vertical: 'center' },
  });
  setCell(sheet, r, 2, '', microRowStyle);
  setCell(sheet, r, 3, money(pax.totals.micro), microRowMoney);
  setCell(sheet, r, 4, '', microRowStyle);
  r += 1;
  setCell(sheet, r, 0, 'Microvise Keseceği Fatura', microGrandStyle);
  setCell(sheet, r, 1, ingenico.totals.qty + pax.totals.qty, {
    ...microGrandStyle,
    alignment: { horizontal: 'center', vertical: 'center' },
  });
  setCell(sheet, r, 2, '', microGrandStyle);
  setCell(sheet, r, 3, money(summary.totals.microviseGrand), microGrandMoney);
  setCell(sheet, r, 4, '', microGrandStyle);
  r += 2;

  const worldColHeader = {
    font: baseFont({ bold: true, sz: 11, color: { rgb: COLORS.headerFg } }),
    fill: { patternType: 'solid', fgColor: { rgb: '1F6B6B' } },
    alignment: { horizontal: 'center', vertical: 'center' },
    border: borderMedium(COLORS.borderWorldStrong),
  };
  const worldRowStyle = {
    font: baseFont({ bold: true, sz: 11 }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.highlightWorldRow } },
    border: borderMedium(COLORS.borderWorldStrong),
    alignment: { vertical: 'center' },
  };
  const worldRowMoney = {
    ...worldRowStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };
  const worldGrandStyle = {
    font: baseFont({ bold: true, sz: 13, color: { rgb: COLORS.headerFg } }),
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandWorld } },
    border: borderMedium(COLORS.borderWorldStrong),
    alignment: { vertical: 'center' },
  };
  const worldGrandMoney = {
    ...worldGrandStyle,
    alignment: { horizontal: 'right', vertical: 'center' },
    numFmt: '₺#,##0.00',
  };

  writeTitleRow('Worldline Keseceği Fatura', COLORS.worldHeader);
  setCell(sheet, r, 0, 'Kalem', worldColHeader);
  setCell(sheet, r, 1, 'Adet', worldColHeader);
  setCell(sheet, r, 2, 'Birim Fiyat', worldColHeader);
  setCell(sheet, r, 3, 'Tutar (Worldline)', worldColHeader);
  setCell(sheet, r, 4, '', worldColHeader);
  r += 1;

  const worldlineOzetRows = [
    {
      label: 'GMP3 / IRESTO (INGENICO + PAX)',
      qty: gmp3Qty + tsmQty,
      unit: gmp3Unit === tsmUnit ? gmp3Unit : null,
      amount: gmp3Amount + tsmAmount,
    },
    {
      label: 'YKB_KOOP BANKA',
      qty: ykb.totals.qty,
      unit: ykbUnitNum,
      amount: ykb.totals.world,
    },
  ];
  for (const row of worldlineOzetRows) {
    setCell(sheet, r, 0, row.label, worldRowStyle);
    setCell(sheet, r, 1, row.qty, {
      ...worldRowStyle,
      alignment: { horizontal: 'center', vertical: 'center' },
    });
    if (row.unit == null || Number.isNaN(Number(row.unit))) {
      setCell(sheet, r, 2, '—', {
        ...worldRowStyle,
        alignment: { horizontal: 'center', vertical: 'center' },
      });
    } else {
      setCell(sheet, r, 2, money(Number(row.unit)), worldRowMoney);
    }
    setCell(sheet, r, 3, money(row.amount), worldRowMoney);
    setCell(sheet, r, 4, '', worldRowStyle);
    r += 1;
  }
  setCell(sheet, r, 0, 'Worldline Keseceği Fatura', worldGrandStyle);
  setCell(sheet, r, 1, ykb.totals.qty + gmp3Qty + tsmQty, {
    ...worldGrandStyle,
    alignment: { horizontal: 'center', vertical: 'center' },
  });
  setCell(sheet, r, 2, '', worldGrandStyle);
  setCell(sheet, r, 3, money(summary.totals.worldlineGrand), worldGrandMoney);
  setCell(sheet, r, 4, '', worldGrandStyle);
  r += 1;

  sheet['!merges'] = merges;
  sheet['!cols'] = [
    { wch: 42 },
    { wch: 10 },
    { wch: 14 },
    { wch: 20 },
    { wch: 8 },
  ];
  sheet['!rows'] = [{ hpt: 26 }, { hpt: 20 }];
  sheet['!ref'] = XLSXStyle.utils.encode_range({
    s: { r: 0, c: 0 },
    e: { r, c: maxCol },
  });

  void unitPrices;
  void fillRow;
  return sheet;
}

function splitSheetDataByBrand(sheetData) {
  if (!sheetData || !Array.isArray(sheetData.headers) || !Array.isArray(sheetData.rows)) {
    return { ingenico: null, pax: null };
  }
  const modelIdx = findHeaderIndex(sheetData.headers, ['Cihaz Modeli']);
  const ingenicoRows = [];
  const paxRows = [];
  for (const row of sheetData.rows) {
    const model = modelIdx >= 0 && Array.isArray(row) ? row[modelIdx] : '';
    if (classifyDeviceBrand(model) === 'PAX') paxRows.push(row);
    else ingenicoRows.push(row);
  }
  return {
    ingenico: { headers: sheetData.headers, rows: ingenicoRows },
    pax: { headers: sheetData.headers, rows: paxRows },
  };
}

function ensureBrandDetailSheets(detailSheets) {
  const sheets = detailSheets && typeof detailSheets === 'object' ? { ...detailSheets } : {};
  if (sheets.gmp3 && (!sheets.gmp3_ingenico || !sheets.gmp3_pax)) {
    const split = splitSheetDataByBrand(sheets.gmp3);
    if (!sheets.gmp3_ingenico) sheets.gmp3_ingenico = split.ingenico;
    if (!sheets.gmp3_pax) sheets.gmp3_pax = split.pax;
  }
  if (sheets.tsm && (!sheets.tsm_ingenico || !sheets.tsm_pax)) {
    const split = splitSheetDataByBrand(sheets.tsm);
    if (!sheets.tsm_ingenico) sheets.tsm_ingenico = split.ingenico;
    if (!sheets.tsm_pax) sheets.tsm_pax = split.pax;
  }
  return sheets;
}

function buildMutakabatWorkbook({ summary, detailSheets, unitPrices, periodLabel }) {
  const prices = normalizeUnitPrices(unitPrices);
  const enrichedSummary = ensureBrandIntegrations(summary, detailSheets, prices);
  const sheets = ensureBrandDetailSheets(detailSheets);
  const wb = XLSXStyle.utils.book_new();
  XLSXStyle.utils.book_append_sheet(
    wb,
    buildDashboardSheet(enrichedSummary, prices, periodLabel),
    'Dashboard',
  );
  if (sheets.ingenico) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.ingenico), 'INGENICO BANKA');
  }
  if (sheets.pax) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.pax), 'PAX BANKA');
  }
  if (sheets.ykb) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.ykb), 'YKB_KOOP BANKA');
  }
  if (sheets.gmp3_ingenico) {
    XLSXStyle.utils.book_append_sheet(
      wb,
      sheetFromData(sheets.gmp3_ingenico),
      'INGENICO GMP3',
    );
  }
  if (sheets.gmp3_pax) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.gmp3_pax), 'PAX GMP3');
  }
  if (sheets.tsm_ingenico) {
    XLSXStyle.utils.book_append_sheet(
      wb,
      sheetFromData(sheets.tsm_ingenico),
      'INGENICO IRESTO',
    );
  }
  if (sheets.tsm_pax) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.tsm_pax), 'PAX IRESTO');
  }
  // Marka sheet yoksa eski birleşik sheet'leri yaz
  if (!sheets.gmp3_ingenico && !sheets.gmp3_pax && sheets.gmp3) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.gmp3), 'GMP3 DATA');
  }
  if (!sheets.tsm_ingenico && !sheets.tsm_pax && sheets.tsm) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.tsm), 'TSM IRESTO DATA');
  }
  return wb;
}

function exportMutakabatExcel(payload) {
  const wb = buildMutakabatWorkbook(payload);
  return XLSXStyle.write(wb, { type: 'buffer', bookType: 'xlsx' });
}

function decodeBase64File(value) {
  if (!value) return null;
  const raw = String(value).trim();
  if (!raw) return null;
  const base64 = raw.includes(',') ? raw.split(',').pop() : raw;
  return Buffer.from(base64, 'base64');
}

module.exports = {
  processMutakabat,
  recalculateSummary,
  ensureBrandIntegrations,
  exportMutakabatExcel,
  decodeBase64File,
  normalizeUnitPrices,
};
