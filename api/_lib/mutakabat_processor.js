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
  if (model === PAX_MODEL || model.includes('a910sf')) return 'PAX';
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
    rows.push({ raw: record });
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
    rows.push({ raw: record });
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
  const gmp3Count = Number(summary?.gmp3?.count || 0) || 0;
  const tsmCount = Number(summary?.tsm?.count || 0) || 0;
  const gmp3Amount = gmp3Count * prices.gmp3;
  const tsmAmount = tsmCount * prices.tsm;
  const nextSummary = {
    ...summary,
    lineItems: [...ing.lines, ...pax.lines, ...ykb.lines],
    integrations: [
      {
        key: 'tsm',
        label: 'TSM Kablosuz Entegrasyon / Iresto',
        quantity: tsmCount,
        unitPrice: prices.tsm,
        worldlineAmount: tsmAmount,
      },
      {
        key: 'gmp3',
        label: 'GMP3 Kablolu Entegrasyon',
        quantity: gmp3Count,
        unitPrice: prices.gmp3,
        worldlineAmount: gmp3Amount,
      },
    ],
    totals: {
      microviseBank: ing.microviseTotal + pax.microviseTotal,
      worldlineBank: ykb.worldlineTotal,
      worldlineIntegrations: gmp3Amount + tsmAmount,
      microviseGrand: ing.microviseTotal + pax.microviseTotal,
      worldlineGrand: ykb.worldlineTotal + gmp3Amount + tsmAmount,
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

  const gmp3Count = gmp3Data?.rows.length || 0;
  const tsmCount = tsmData?.rows.length || 0;
  const gmp3Amount = gmp3Count * prices.gmp3;
  const tsmAmount = tsmCount * prices.tsm;

  const ing = buildLineItems('INGENICO', ingenicoCounts, prices.bankTiers, 'microvise');
  const pax = buildLineItems('PAX (A910SF)', paxCounts, prices.bankTiers, 'microvise');
  const ykb = buildYkbSingleLineItems(ykbCounts, prices.ykbTiers);

  const microviseBankTotal = ing.microviseTotal + pax.microviseTotal;
  const worldlineBankTotal = ykb.worldlineTotal;
  const worldlineIntegrationTotal = gmp3Amount + tsmAmount;

  const summary = {
    ingenico: counterToObject(ingenicoCounts),
    pax: counterToObject(paxCounts),
    ykb: counterToObject(ykbCounts),
    gmp3: {
      count: gmp3Count,
      rawYesCount: gmp3Data?.rawYesCount || 0,
      duplicateSkipped: gmp3Data?.duplicateSkipped || 0,
    },
    tsm: {
      count: tsmCount,
      rawVarCount: tsmData?.rawVarCount || 0,
      duplicateSkipped: tsmData?.duplicateSkipped || 0,
    },
    lineItems: [...ing.lines, ...pax.lines, ...ykb.lines],
    integrations: [
      {
        key: 'tsm',
        label: 'TSM Kablosuz Entegrasyon / Iresto',
        quantity: tsmCount,
        unitPrice: prices.tsm,
        worldlineAmount: tsmAmount,
      },
      {
        key: 'gmp3',
        label: 'GMP3 Kablolu Entegrasyon',
        quantity: gmp3Count,
        unitPrice: prices.gmp3,
        worldlineAmount: gmp3Amount,
      },
    ],
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
    },
  };

  const detailSheets = {
    original: rowsToSheetData(bank.headers, bank.rows),
    ingenico: rowsToSheetData(bank.headers, ingenicoRows),
    pax: rowsToSheetData(bank.headers, paxRows),
    ykb: rowsToSheetData(bank.headers, ykbRows),
  };
  if (gmp3Data) {
    detailSheets.gmp3 = rowsToSheetData(
      gmp3Data.headers,
      gmp3Data.rows,
    );
  }
  if (tsmData) {
    detailSheets.tsm = rowsToSheetData(
      tsmData.headers,
      tsmData.rows,
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
  grandMicro: 'E2E8F0',
  grandWorld: 'C5E0DC',
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
  const integQty = integrations.reduce((s, i) => s + (i.quantity || 0), 0);
  const integAmount = Number(summary.totals.worldlineIntegrations) || 0;

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

  writeTitleRow('Microvise Keseceği Fatura', COLORS.microHeader);
  setCell(sheet, r, 0, 'INGENICO', bodyStyle);
  setCell(sheet, r, 1, ingenico.totals.qty, {
    ...bodyStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', bodyStyle);
  setCell(sheet, r, 3, money(ingenico.totals.micro), moneyStyle);
  setCell(sheet, r, 4, '', bodyStyle);
  r += 1;
  setCell(sheet, r, 0, 'PAX', bodyStyle);
  setCell(sheet, r, 1, pax.totals.qty, {
    ...bodyStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', bodyStyle);
  setCell(sheet, r, 3, money(pax.totals.micro), moneyStyle);
  setCell(sheet, r, 4, '', bodyStyle);
  r += 1;
  setCell(sheet, r, 0, 'Microvise Keseceği Fatura', totalStyle);
  setCell(sheet, r, 1, ingenico.totals.qty + pax.totals.qty, {
    ...totalStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', totalStyle);
  setCell(sheet, r, 3, money(summary.totals.microviseGrand), {
    ...totalMoneyStyle,
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandMicro } },
  });
  setCell(sheet, r, 4, '', {
    ...totalStyle,
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandMicro } },
  });
  r += 2;

  // =========================================================
  // B) Worldline Keseceği Fatura (YKB + GMP3 + TSM)
  // =========================================================
  writeTitleRow(
    'B) Worldline Keseceği Fatura (YKB + GMP3 + TSM)',
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

  writeTitleRow('GMP3 DATA / TSM IRESTO DATA', COLORS.integHeader);
  writeSimpleTable(
    ['Açıklama', 'Adet', 'Birim Fiyat', 'Tutar (Worldline)', ''],
    integrations.map((item) => [
      item.label,
      item.quantity,
      money(item.unitPrice),
      money(item.worldlineAmount),
      '',
    ]),
    'ENTEGRASYON TOPLAM',
    integQty,
    integAmount,
  );

  writeTitleRow('Worldline Keseceği Fatura', COLORS.worldHeader);
  setCell(sheet, r, 0, 'YKB_KOOP BANKA', bodyStyle);
  setCell(sheet, r, 1, ykb.totals.qty, {
    ...bodyStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', bodyStyle);
  setCell(sheet, r, 3, money(ykb.totals.world), moneyStyle);
  setCell(sheet, r, 4, '', bodyStyle);
  r += 1;
  setCell(sheet, r, 0, 'GMP3 / TSM', bodyStyle);
  setCell(sheet, r, 1, integQty, {
    ...bodyStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', bodyStyle);
  setCell(sheet, r, 3, money(integAmount), moneyStyle);
  setCell(sheet, r, 4, '', bodyStyle);
  r += 1;
  setCell(sheet, r, 0, 'Worldline Keseceği Fatura', totalStyle);
  setCell(sheet, r, 1, ykb.totals.qty + integQty, {
    ...totalStyle,
    alignment: { horizontal: 'center' },
  });
  setCell(sheet, r, 2, '', totalStyle);
  setCell(sheet, r, 3, money(summary.totals.worldlineGrand), {
    ...totalMoneyStyle,
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandWorld } },
  });
  setCell(sheet, r, 4, '', {
    ...totalStyle,
    fill: { patternType: 'solid', fgColor: { rgb: COLORS.grandWorld } },
  });

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

function buildMutakabatWorkbook({ summary, detailSheets, unitPrices, periodLabel }) {
  const sheets = detailSheets && typeof detailSheets === 'object' ? detailSheets : {};
  const wb = XLSXStyle.utils.book_new();
  XLSXStyle.utils.book_append_sheet(
    wb,
    buildDashboardSheet(summary, unitPrices, periodLabel),
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
  if (sheets.gmp3) {
    XLSXStyle.utils.book_append_sheet(wb, sheetFromData(sheets.gmp3), 'GMP3 DATA');
  }
  if (sheets.tsm) {
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
  exportMutakabatExcel,
  decodeBase64File,
  normalizeUnitPrices,
};
