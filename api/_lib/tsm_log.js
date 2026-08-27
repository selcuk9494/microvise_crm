'use strict';

const XLSX = require('xlsx');

const TERM_SERI_NO_PATTERN =
  /&lt;(?:[\w]+:)?TermSeriNo&gt;\s*([^&<]+)\s*&lt;\/(?:[\w]+:)?TermSeriNo&gt;|<(?:[\w]+:)?TermSeriNo>\s*([^<]+)\s*<\/(?:[\w]+:)?TermSeriNo>/gi;

const ALLOWED_OPERATIONS = {
  TERMINALSORGU: 'TERMINAL_SORGU',
  ISEMRIACMA: 'ISEMRI_ACMA',
};

function parseTsmLogBuffer(buffer, fileName = 'tsm.xls') {
  const rows = readSpreadsheetRows(buffer);
  return parseTsmLogRows(rows, fileName);
}

function readSpreadsheetRows(buffer) {
  const workbook = XLSX.read(buffer, {
    type: 'buffer',
    cellDates: true,
  });
  if (!workbook.SheetNames.length) {
    throw new Error('Excel içinde sayfa bulunamadı.');
  }
  const sheet = workbook.Sheets[workbook.SheetNames[0]];
  const ref = sheet['!ref'];
  if (!ref) return [];
  const range = XLSX.utils.decode_range(ref);
  const rows = [];
  for (let r = range.s.r; r <= range.e.r; r += 1) {
    const row = [];
    for (let c = range.s.c; c <= range.e.c; c += 1) {
      const addr = XLSX.utils.encode_cell({ r, c });
      row.push(formatXlsxCell(sheet[addr]));
    }
    rows.push(row);
  }
  return rows;
}

function formatXlsxCell(cell) {
  if (!cell) return '';
  if (typeof cell.w === 'string' && cell.w.trim()) return cell.w.trim();
  if (cell.v instanceof Date && !Number.isNaN(cell.v.getTime())) {
    const d = cell.v;
    const pad = (n) => String(n).padStart(2, '0');
    return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`;
  }
  if (cell.v == null) return '';
  return String(cell.v).trim();
}

function parseTsmLogRows(rows, fileName = 'tsm.xls') {
  const header = findHeader(rows);
  if (!header) {
    return {
      fileName,
      totalRows: 0,
      matchedRows: 0,
      skippedRows: 0,
      uniqueSerials: [],
      error: 'Excel içinde "İşlem" ve "Sonuç Mesajı" kolonları bulunamadı.',
    };
  }

  const entries = [];
  const messageOptions = new Set();
  let skipped = 0;
  for (let i = header.rowIndex + 1; i < rows.length; i += 1) {
    const row = rows[i] || [];
    const operationRaw = cellAt(row, header.operationIndex);
    const messageRaw = cellAt(row, header.messageIndex);
    if (!operationRaw && !messageRaw) continue;

    const operation = parseTsmLogOperation(operationRaw);
    if (!operation) continue;
    const resultKind = parseTsmLogResultKind(messageRaw) || 'other';
    const resultMessage = normalizeTsmResultMessage(messageRaw);
    messageOptions.add(resultMessage || '(Boş)');
    const params = cellAt(row, header.paramIndex);
    const serials = extractTermSeriNos(
      [messageRaw, params, row.join('\n')].join('\n'),
    );
    if (!serials.length) {
      skipped += 1;
      continue;
    }
    const workOrder =
      operation === 'ISEMRI_ACMA' && resultKind === 'approved'
        ? parseTsmWorkOrderDetails(params || messageRaw)
        : null;
    const occurredAt = parseTsmLogDateTime(
      cellAt(row, header.dateIndex),
      cellAt(row, header.timeIndex),
    );
    for (const serialNumber of serials) {
      entries.push({
        serialNumber,
        operation,
        resultKind,
        resultMessage,
        excelRow: i + 1,
        workOrder,
        occurredAt,
      });
    }
  }

  return {
    fileName,
    totalRows: Math.max(rows.length - header.rowIndex - 1, 0),
    matchedRows: entries.length,
    skippedRows: skipped,
    uniqueSerials: groupTsmLogSerials(entries),
    resultMessageOptions: [...messageOptions].sort((a, b) =>
      a.localeCompare(b, 'tr'),
    ),
    error: null,
  };
}

function groupTsmLogSerials(entries) {
  const grouped = new Map();
  for (const entry of entries) {
    const resultMessage = entry.resultMessage || '(Boş)';
    const outcomeKey = `${entry.operation}|${resultMessage}`;
    const existing = grouped.get(entry.serialNumber);
    if (!existing) {
      grouped.set(entry.serialNumber, {
        serialNumber: entry.serialNumber,
        operations: [entry.operation],
        resultKinds: [entry.resultKind],
        resultMessages: [resultMessage],
        outcomes: [
          { operation: entry.operation, resultMessage },
        ],
        count: 1,
        workOrder: entry.workOrder || null,
        occurredAt: entry.occurredAt || null,
        _outcomeKeys: new Set([outcomeKey]),
      });
      continue;
    }
    if (!existing.operations.includes(entry.operation)) {
      existing.operations.push(entry.operation);
    }
    if (!existing.resultKinds.includes(entry.resultKind)) {
      existing.resultKinds.push(entry.resultKind);
    }
    if (!existing._outcomeKeys.has(outcomeKey)) {
      existing._outcomeKeys.add(outcomeKey);
      existing.outcomes.push({
        operation: entry.operation,
        resultMessage,
      });
      if (!existing.resultMessages.includes(resultMessage)) {
        existing.resultMessages.push(resultMessage);
      }
    }
    existing.count += 1;
    existing.workOrder = preferWorkOrder(existing.workOrder, entry.workOrder);
    existing.occurredAt = laterDate(existing.occurredAt, entry.occurredAt);
  }
  return [...grouped.values()].map((item) => {
    const { _outcomeKeys, ...rest } = item;
    return rest;
  }).sort(compareSerialsNewestFirst);
}

function laterDate(current, next) {
  if (!next) return current || null;
  if (!current) return next;
  return Date.parse(next) >= Date.parse(current) ? next : current;
}

function compareSerialsNewestFirst(a, b) {
  const da = a.occurredAt ? Date.parse(a.occurredAt) : NaN;
  const db = b.occurredAt ? Date.parse(b.occurredAt) : NaN;
  if (!Number.isNaN(da) && !Number.isNaN(db) && db !== da) return db - da;
  if (!Number.isNaN(da) && Number.isNaN(db)) return -1;
  if (Number.isNaN(da) && !Number.isNaN(db)) return 1;
  return a.serialNumber.localeCompare(b.serialNumber, 'tr');
}

function parseTsmLogOperation(raw) {
  return ALLOWED_OPERATIONS[compactKey(raw)] || null;
}

function parseTsmLogResultKind(raw) {
  const normalized = foldTurkish(raw).toUpperCase();
  if (normalized.includes('ISLEM ONAYLANDI')) return 'approved';
  if (compactKey(raw).includes('SERINOYAAITVERGINOTCNOESLESMEDI')) {
    return 'serialMismatch';
  }
  return null;
}

function normalizeTsmResultMessage(raw) {
  let text = unescapeHtml(String(raw || '')).replace(/\u0000/g, ' ').trim();
  const xmlStart = text.indexOf('<');
  if (xmlStart >= 0) text = text.slice(0, xmlStart);
  return text.replace(/\s+/g, ' ').trim();
}

function extractTermSeriNos(raw) {
  const found = new Set();
  const text = String(raw || '');
  TERM_SERI_NO_PATTERN.lastIndex = 0;
  let match = TERM_SERI_NO_PATTERN.exec(text);
  while (match) {
    const value = String(match[1] || match[2] || '').trim();
    if (value.startsWith('2')) found.add(value);
    match = TERM_SERI_NO_PATTERN.exec(text);
  }
  return [...found];
}

function parseTsmWorkOrderDetails(raw) {
  const xml = unescapeHtml(String(raw || ''));
  if (!xml) return null;
  const compact = compactKey(xml);
  const looksLikeWorkOrder =
    compact.includes('ISEMRIGIRIS') ||
    compact.includes('OPENTASK') ||
    compact.includes('ISEMRIKODU') ||
    compact.includes('ACQUIREREKRANADI') ||
    compact.includes('ACQUIRERID');
  if (!looksLikeWorkOrder) return null;

  const orderCode = xmlTag(xml, 'IsEmriKodu');
  const description = xmlTag(xml, 'Aciklama');
  const details = {
    bankName: xmlTag(xml, 'AcquirerEkranAdi'),
    acquirerId: normalizeBkmAcquirerId(xmlTag(xml, 'AcquirerId')),
    terminalId: xmlTag(xml, 'TermId'),
    merchantName: xmlTag(xml, 'IsyeriAdi'),
    merchantNo: xmlTag(xml, 'IsyeriNo'),
    bkmMerchantId: xmlTag(xml, 'BkmMerchantId'),
    address: ['IsyeriAdres1', 'IsyeriAdres2', 'IsyeriAdres3', 'IsyeriAdres4']
      .map((tag) => xmlTag(xml, tag))
      .filter(Boolean)
      .join(' '),
    city: xmlTag(xml, 'IsyeriSehir'),
    district: xmlTag(xml, 'IsyeriIlce'),
    phone: xmlTag(xml, 'IsyeriTel'),
    orderCode,
    description,
    orderKind: classifyTsmOrderKind(orderCode, description),
  };
  return workOrderRichness(details) === 0 ? null : details;
}

function classifyTsmOrderKind(orderCode, description) {
  const compact = foldTurkish(description).toUpperCase();
  if (
    compact.includes('GERI ALIM') ||
    compact.includes('GERIALIM') ||
    compact.includes('SILME')
  ) {
    return 'geriAlim';
  }
  if (compact.includes('KURULUM')) return 'kurulum';
  if (compact.includes('EKLEME')) return 'ekleme';
  switch (String(orderCode || '').trim().toUpperCase()) {
    case 'K':
      return 'kurulum';
    case 'TE':
      return 'ekleme';
    case 'TS':
      return 'geriAlim';
    default:
      return 'unknown';
  }
}

function preferWorkOrder(current, next) {
  if (!next) return current || null;
  if (!current) return next;
  return workOrderRichness(next) >= workOrderRichness(current) ? next : current;
}

function workOrderRichness(details) {
  if (!details) return 0;
  let score = 0;
  for (const key of [
    'bankName',
    'acquirerId',
    'terminalId',
    'merchantName',
    'merchantNo',
    'bkmMerchantId',
    'address',
    'city',
    'district',
    'phone',
    'orderCode',
    'description',
  ]) {
    if (String(details[key] || '').trim()) score += 1;
  }
  if (details.orderKind && details.orderKind !== 'unknown') score += 2;
  return score;
}

function xmlTag(xml, tag) {
  const pattern = new RegExp(
    `<(?:[\\w]+:)?${tag}>([^<]*)</(?:[\\w]+:)?${tag}>`,
    'i',
  );
  const match = String(xml || '').match(pattern);
  return String(match?.[1] || '').trim();
}

function normalizeBkmAcquirerId(raw) {
  const value = String(raw || '').trim();
  if (!value) return '';
  const parsed = Number.parseInt(value, 10);
  return Number.isFinite(parsed) ? String(parsed) : value;
}

function unescapeHtml(value) {
  return String(value || '')
    .replaceAll('&nbsp;', ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replace(/&#(\d+);/g, (_, code) => String.fromCharCode(Number(code)));
}

function findHeader(rows) {
  const limit = Math.min(rows.length, 15);
  for (let i = 0; i < limit; i += 1) {
    const normalized = (rows[i] || []).map((cell) => normalizeHeader(cell));
    const operationIndex = findOperationColumn(normalized);
    const messageIndex = findMessageColumn(normalized);
    if (
      operationIndex >= 0 &&
      messageIndex >= 0 &&
      operationIndex !== messageIndex
    ) {
      return {
        rowIndex: i,
        operationIndex,
        messageIndex,
        paramIndex: findParamColumn(normalized),
        dateIndex: findDateColumn(normalized),
        timeIndex: findTimeColumn(normalized),
      };
    }
  }
  return null;
}

function findOperationColumn(headers) {
  const preferred = ['islem', 'islem_tipi', 'islem_turu', 'operation'];
  for (const key of preferred) {
    const idx = headers.indexOf(key);
    if (idx >= 0) return idx;
  }
  return headers.findIndex(
    (header) =>
      header.includes('islem') &&
      !header.includes('sonuc') &&
      !header.includes('mesaj') &&
      !header.includes('kanal') &&
      !header.includes('adi'),
  );
}

function findMessageColumn(headers) {
  const preferred = [
    'sonuc_mesaji',
    'sonuc_mesaj',
    'result_message',
    'sonuc',
    'mesaj',
  ];
  for (const key of preferred) {
    const idx = headers.indexOf(key);
    if (idx >= 0) return idx;
  }
  return headers.findIndex(
    (header) =>
      (header.includes('sonuc') || header.includes('mesaj')) &&
      !header.includes('kod'),
  );
}

function findParamColumn(headers) {
  const preferred = [
    'giris_parametreleri',
    'parametreler',
    'request',
    'xml',
    'giris',
  ];
  for (const key of preferred) {
    const idx = headers.indexOf(key);
    if (idx >= 0) return idx;
  }
  return headers.findIndex((header) => header.includes('parametre'));
}

function findDateColumn(headers) {
  const preferred = [
    'eklenme_tarihi',
    'ekleme_tarihi',
    'kayit_tarihi',
    'tarih',
    'date',
  ];
  for (const key of preferred) {
    const idx = headers.indexOf(key);
    if (idx >= 0) return idx;
  }
  return headers.findIndex(
    (header) => header.includes('tarih') && !header.includes('saat'),
  );
}

function findTimeColumn(headers) {
  const preferred = ['ekleme_saati', 'eklenme_saati', 'saat', 'time'];
  for (const key of preferred) {
    const idx = headers.indexOf(key);
    if (idx >= 0) return idx;
  }
  return headers.findIndex((header) => header.includes('saat'));
}

function parseTsmLogDateTime(dateRaw, timeRaw = '') {
  const dateText = String(dateRaw || '').trim();
  const timeText = String(timeRaw || '').trim();
  if (!dateText && !timeText) return null;

  const fromSerial = excelSerialDate(dateText);
  const date = fromSerial || parseDatePart(dateText) || parseDatePart(timeText);
  if (!date) return null;

  const time = parseTimePart(timeText || dateText);
  if (!time) return date.toISOString();
  date.setHours(time.hour, time.minute, time.second, 0);
  return date.toISOString();
}

function excelSerialDate(raw) {
  const value = Number(String(raw).replace(',', '.'));
  if (!Number.isFinite(value) || value < 20000 || value > 80000) return null;
  if (/^\d{4}/.test(raw)) return null;
  const millis = Math.round(value * 86400000);
  return new Date(Date.UTC(1899, 11, 30) + millis);
}

function parseDatePart(raw) {
  const text = String(raw || '').trim();
  if (!text) return null;
  const ymd = text.match(/^(\d{4})[./-](\d{1,2})[./-](\d{1,2})/);
  if (ymd) {
    const year = Number(ymd[1]);
    const month = Number(ymd[2]);
    const day = Number(ymd[3]);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return new Date(year, month - 1, day);
    }
  }
  const dotted = text.match(/^(\d{1,2})[./](\d{1,2})[./](\d{4})/);
  if (dotted) {
    const day = Number(dotted[1]);
    const month = Number(dotted[2]);
    const year = Number(dotted[3]);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return new Date(year, month - 1, day);
    }
  }
  const iso = Date.parse(text.replace(' ', 'T'));
  if (Number.isFinite(iso)) return new Date(iso);
  return null;
}

function parseTimePart(raw) {
  const match = String(raw || '').match(/(\d{1,2}):(\d{2})(?::(\d{2}))?/);
  if (!match) return null;
  const hour = Number(match[1]);
  const minute = Number(match[2]);
  const second = Number(match[3] || 0);
  if (hour > 23 || minute > 59 || second > 59) return null;
  return { hour, minute, second };
}

function cellAt(row, index) {
  if (index < 0 || index >= row.length) return '';
  return String(row[index] || '').trim();
}

function normalizeHeader(value) {
  let text = foldTurkish(String(value || '')).toLowerCase();
  text = text.replace(/[^a-z0-9]+/g, '_');
  text = text.replace(/_+/g, '_');
  return text.replace(/^_+|_+$/g, '');
}

function compactKey(value) {
  return foldTurkish(String(value || ''))
    .toUpperCase()
    .replace(/[^A-Z0-9]/g, '');
}

function foldTurkish(value) {
  return String(value || '')
    .replaceAll('ı', 'i')
    .replaceAll('İ', 'I')
    .replaceAll('ğ', 'g')
    .replaceAll('Ğ', 'G')
    .replaceAll('ş', 's')
    .replaceAll('Ş', 'S')
    .replaceAll('ç', 'c')
    .replaceAll('Ç', 'C')
    .replaceAll('ö', 'o')
    .replaceAll('Ö', 'O')
    .replaceAll('ü', 'u')
    .replaceAll('Ü', 'U');
}

module.exports = {
  parseTsmLogBuffer,
  parseTsmLogRows,
  extractTermSeriNos,
  parseTsmLogOperation,
  parseTsmLogResultKind,
  parseTsmWorkOrderDetails,
  classifyTsmOrderKind,
  parseTsmLogDateTime,
  normalizeTsmResultMessage,
};
