const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const PAGE = { width: 595.28, height: 841.89 };
const LEFT = 34;
const RIGHT = 561;
const WIDTH = RIGHT - LEFT;
const FOOTER_RULE_Y = 762;

const COLORS = {
  text: '#1f242c',
  label: '#6b7075',
  footer: '#9aa0a8',
  border: '#eaebef',
  grid: '#ebebeb',
  headerFill: '#fafbfd',
  red: '#d32f3c',
};

function text(value, fallback = '-') {
  const normalized = String(value ?? '').trim();
  return normalized || fallback;
}

function parseAmount(value) {
  if (value == null || value === '') return null;
  if (typeof value === 'number') {
    return Number.isFinite(value) ? value : null;
  }
  const raw = String(value).trim();
  if (!raw || raw === '-') return null;
  // "1.234,56" veya "1234,56" / "1234.56"
  let normalized = raw.replace(/[^\d,.-]/g, '');
  if (!normalized) return null;
  if (normalized.includes(',') && normalized.includes('.')) {
    normalized = normalized.replace(/\./g, '').replace(',', '.');
  } else if (normalized.includes(',')) {
    normalized = normalized.replace(',', '.');
  }
  const numeric = Number(normalized);
  return Number.isFinite(numeric) ? numeric : null;
}

function firstPositiveAmount(...candidates) {
  for (const candidate of candidates) {
    const numeric = parseAmount(candidate);
    if (numeric != null && numeric !== 0) return numeric;
  }
  for (const candidate of candidates) {
    const numeric = parseAmount(candidate);
    if (numeric != null) return numeric;
  }
  return 0;
}

function pickUnit(...candidates) {
  for (const candidate of candidates) {
    const value = String(candidate ?? '').trim();
    if (value && value !== '0' && value.toLowerCase() !== 'null') return value;
  }
  return null;
}

function mergeLineItems({ officialItems, payloadItems, localItems }) {
  const length = Math.max(
    officialItems.length,
    payloadItems.length,
    localItems.length,
  );
  const rows = [];
  for (let index = 0; index < length; index += 1) {
    const official = officialItems[index] || {};
    const payload = payloadItems[index] || {};
    const local = localItems[index] || {};
    const qty = firstPositiveAmount(
      official.birimMiktari,
      official.quantity,
      payload.birimMiktari,
      payload.quantity,
      local.quantity,
    );
    const netFromLocal =
      local.unit_price != null && local.quantity != null
        ? Number(local.unit_price) * Number(local.quantity)
        : null;
    const net = firstPositiveAmount(
      official.malHizmetTutari,
      official.netTutar,
      official.araToplam,
      payload.malHizmetTutari,
      payload.netTutar,
      netFromLocal,
    );
    const price = firstPositiveAmount(
      official.fiyat,
      official.birimFiyat,
      official.birimFiyati,
      official.unit_price,
      payload.fiyat,
      payload.birimFiyat,
      payload.birimFiyati,
      payload.unit_price,
      local.unit_price,
      qty > 0 ? net / qty : null,
    );
    const discount = firstPositiveAmount(
      official.iskontoVeEkUcretler?.find((entry) => entry?.indirimMi !== false)
        ?.tutar,
      payload.iskontoVeEkUcretler?.find((entry) => entry?.indirimMi !== false)
        ?.tutar,
      official.discount_amount,
      payload.discount_amount,
      local.discount_amount,
      0,
    );
    const tax = firstPositiveAmount(
      official.vergiler?.[0]?.vergiTutari,
      payload.vergiler?.[0]?.vergiTutari,
      official.tax_amount,
      payload.tax_amount,
      local.tax_amount,
      0,
    );
    const taxRate = firstPositiveAmount(
      official.vergiler?.[0]?.vergiOrani,
      payload.vergiler?.[0]?.vergiOrani,
      official.tax_rate,
      payload.tax_rate,
      local.tax_rate,
      0,
    );
    const computedTotal = qty * price - discount + tax;
    let total = firstPositiveAmount(
      official.toplam,
      official.tutar,
      official.vergiDahilToplam,
      payload.toplam,
      payload.tutar,
      payload.vergiDahilToplam,
      local.line_total,
      computedTotal,
    );
    if (tax > 0 && Math.abs(total - tax) < 0.005 && computedTotal > tax) {
      total = computedTotal;
    }
    rows.push({
      adi: text(
        official.adi ||
          official.description ||
          payload.adi ||
          local.description,
        'Mal/Hizmet',
      ),
      aciklama: text(
        official.aciklama ||
          official.description ||
          payload.aciklama ||
          local.description,
        '',
      ),
      birimMiktari: qty,
      birimTurKod: pickUnit(
        official.birimTurKod,
        official.unit,
        payload.birimTurKod,
        payload.unit,
        local.unit,
      ),
      fiyat: price,
      discount,
      tax,
      taxRate,
      total: total || computedTotal,
    });
  }
  return rows;
}

function money(value, currency) {
  const numeric = parseAmount(value) ?? 0;
  const amount = Math.abs(numeric).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const sign = numeric < 0 ? '-' : '';
  const symbol = { TRY: '₺', USD: '$', EUR: '€', GBP: '£' }[
    String(currency || '').toUpperCase()
  ];
  return symbol
    ? `${sign}${symbol}${amount}`
    : `${sign}${amount} ${text(currency, '')}`.trim();
}

function formatDate(value, includeTime = true) {
  if (!value) return '-';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return text(value);
  const parts = new Intl.DateTimeFormat('tr-TR', {
    timeZone: 'Asia/Famagusta',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
    ...(includeTime ? { hour: '2-digit', minute: '2-digit', hourCycle: 'h23' } : {}),
  }).formatToParts(date);
  const values = Object.fromEntries(
    parts.filter((part) => part.type !== 'literal').map((part) => [part.type, part.value]),
  );
  return `${values.day}.${values.month}.${values.year}${
    includeTime ? ` ${values.hour}:${values.minute}` : ''
  }`;
}

function unitName(value) {
  const code = String(value || '').toUpperCase();
  return (
    {
      C62: 'ADET(UNIT)',
      KGM: 'KG(KILOGRAM)',
      LTR: 'LT(LITRE)',
      MTR: 'MT(METRE)',
      HUR: 'SAAT(HOUR)',
    }[code] || text(value)
  );
}

const ONES = ['', 'BİR', 'İKİ', 'ÜÇ', 'DÖRT', 'BEŞ', 'ALTI', 'YEDİ', 'SEKİZ', 'DOKUZ'];
const TENS = ['', 'ON', 'YİRMİ', 'OTUZ', 'KIRK', 'ELLİ', 'ALTMIŞ', 'YETMİŞ', 'SEKSEN', 'DOKSAN'];
const GROUPS = ['', 'BİN', 'MİLYON', 'MİLYAR', 'TRİLYON'];

function threeDigitWords(value) {
  const hundreds = Math.floor(value / 100);
  const rest = value % 100;
  return `${hundreds ? `${hundreds === 1 ? '' : ONES[hundreds]}YÜZ` : ''}${
    TENS[Math.floor(rest / 10)]
  }${ONES[rest % 10]}`;
}

function integerWords(value) {
  let number = Math.max(0, Math.floor(Number(value) || 0));
  if (!number) return 'SIFIR';
  let result = '';
  let group = 0;
  while (number > 0 && group < GROUPS.length) {
    const chunk = number % 1000;
    if (chunk) {
      const words = group === 1 && chunk === 1 ? '' : threeDigitWords(chunk);
      result = `${words}${GROUPS[group]}${result}`;
    }
    number = Math.floor(number / 1000);
    group += 1;
  }
  return result;
}

function amountInWords(value, currency) {
  const amount = Math.abs(Number(value) || 0);
  let whole = Math.floor(amount);
  let fraction = Math.round((amount - whole) * 100);
  if (fraction === 100) {
    whole += 1;
    fraction = 0;
  }
  const labels =
    {
      TRY: ['TÜRK LİRASI', 'KURUŞ'],
      USD: ['AMERİKAN DOLARI', 'SENT'],
      EUR: ['EURO', 'CENT'],
      GBP: ['İNGİLİZ STERLİNİ', 'PENİ'],
    }[String(currency || '').toUpperCase()] || [text(currency, 'PARA'), ''];
  return `#${integerWords(whole)} ${labels[0]}${
    fraction ? ` ${integerWords(fraction)} ${labels[1]}` : ''
  }#`;
}

function partyLines(party) {
  const cityCountry = [party?.sehir || party?.city, party?.ulke || party?.country]
    .map((value) => text(value, ''))
    .filter(Boolean)
    .join(', ');
  const documentNumber = party?.belgeNo || party?.documentNumber;
  const documentType = party?.belgeTipi || party?.documentType;
  const lines = [
    text(party?.unvan || party?.name),
    text(party?.adresSatir1 || party?.adres || party?.address),
    text(party?.adresSatir2 || party?.addressLine2, ''),
    cityCountry,
    `Tel: ${text(party?.telefon || party?.phone)}`,
    `E-posta: ${text(party?.email)}`,
    `Web: ${text(party?.webSitesi || party?.website)}`,
  ];
  if (party?.vkn || party?.tax_number) {
    lines.push(`VKN: ${text(party?.vkn || party?.tax_number)}`);
  }
  if (documentType || documentNumber) {
    lines.push(`${text(documentType, 'Belge No')}: ${text(documentNumber)}`);
  }
  return lines.filter(Boolean).join('\n');
}

function sourceInvoice(officialData, payloadInvoice) {
  const official =
    officialData?.fatura ||
    officialData?.invoice ||
    officialData?.data?.fatura ||
    officialData?.data?.invoice ||
    officialData?.data ||
    officialData ||
    {};
  const normalized = Array.isArray(official) ? official[0] || {} : official;
  return { ...payloadInvoice, ...normalized };
}

const COMPANY_LOGO_MAX = { width: 150, height: 52 };

// Açıklama bloğu (banka bilgileri) ölçüleri; hem yer hesabında hem çizimde
// kullanılır ki tek sayfaya sığma sınırı doğru kalsın.
const DESCRIPTION = {
  titleFontSize: 8.5,
  fontSize: 6.6,
  lineGap: 1.6,
  top: 14,
  width: 340,
};

function resolveCompanyLogoPath(settings) {
  const candidates = [
    text(settings?.seller_logo_path, ''),
    text(settings?.seller_logo, ''),
    path.resolve(process.cwd(), 'assets/images/company_logo.png'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    const resolved = path.isAbsolute(candidate)
      ? candidate
      : path.resolve(process.cwd(), candidate);
    if (fs.existsSync(resolved)) return resolved;
  }
  return null;
}

function drawParty(doc, title, party, x, y, width, height) {
  doc.lineWidth(0.8).roundedRect(x, y, width, height, 6).stroke(COLORS.border);
  doc
    .font('NotoSansBold')
    .fontSize(11)
    .fillColor(COLORS.text)
    .text(title, x + 12, y + 12);
  doc
    .font('NotoSans')
    .fontSize(8)
    .fillColor(COLORS.text)
    .text(partyLines(party), x + 12, y + 38, {
      width: width - 24,
      height: height - 46,
      lineGap: 4.6,
      ellipsis: true,
    });
}

function partyHeight(doc, party, width) {
  doc.font('NotoSans').fontSize(8);
  return (
    38 +
    doc.heightOfString(partyLines(party), { width: width - 24, lineGap: 4.6 }) +
    10
  );
}

function drawMeta(doc, label, value, x, y, width) {
  doc
    .font('NotoSans')
    .fontSize(6.8)
    .fillColor(COLORS.label)
    .text(label, x, y + 13, { width, ellipsis: true });
  doc
    .font('NotoSansBold')
    .fontSize(8.4)
    .fillColor(COLORS.text)
    .text(text(value), x, y + 27, { width, ellipsis: true });
}

const TABLE_COLUMNS = [34, 115, 196, 270, 342, 393, 434, 481, 561];
const TABLE_HEADERS = [
  'Mal/Hizmet',
  'Açıklama',
  'Miktar',
  'Birim Fiyat',
  'İndirim',
  'KDV (%)',
  'KDV Tutarı',
  'Toplam',
];

function columnBox(index) {
  const x = TABLE_COLUMNS[index] + 6;
  return { x, width: TABLE_COLUMNS[index + 1] - TABLE_COLUMNS[index] - 12 };
}

function drawGrid(doc, y, height) {
  doc.lineWidth(0.6).strokeColor(COLORS.grid);
  doc.rect(LEFT, y, WIDTH, height).stroke();
  for (let index = 1; index < TABLE_COLUMNS.length - 1; index += 1) {
    doc.moveTo(TABLE_COLUMNS[index], y).lineTo(TABLE_COLUMNS[index], y + height).stroke();
  }
}

function rowHeight(doc, values, font, size) {
  doc.font(font).fontSize(size);
  const tallest = values.reduce((max, value, index) => {
    const box = columnBox(index);
    return Math.max(max, doc.heightOfString(value, { width: box.width, lineGap: 2 }));
  }, 0);
  return tallest + 16;
}

function drawRow(doc, values, y, height, font, size) {
  drawGrid(doc, y, height);
  doc.font(font).fontSize(size).fillColor(COLORS.text);
  values.forEach((value, index) => {
    const box = columnBox(index);
    const textHeight = doc.heightOfString(value, { width: box.width, lineGap: 2 });
    doc.text(value, box.x, y + (height - textHeight) / 2, {
      width: box.width,
      lineGap: 2,
      align: index < 2 ? 'left' : 'right',
    });
  });
}

async function buildEInvoiceArchivePdf({
  invoice,
  settings,
  officialData,
  verificationCode,
  environment,
}) {
  const doc = new PDFDocument({
    size: 'A4',
    margins: { top: 30, right: 34, bottom: 30, left: 34 },
    info: {
      Title: text(invoice.e_invoice_number || invoice.invoice_number, 'E-Fatura'),
      Author: text(settings.seller_title, 'Microvise CRM'),
      Subject: 'K.K.T.C. Maliye Bakanlığı e-Fatura',
    },
  });
  const chunks = [];
  doc.on('data', (chunk) => chunks.push(chunk));
  const completed = new Promise((resolve, reject) => {
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);
  });

  const fontDir = path.resolve(process.cwd(), 'assets/fonts/noto_sans');
  const fontFiles = {
    NotoSans: ['NotoSans-Regular.ttf', 'Helvetica'],
    NotoSansBold: ['NotoSans-Bold.ttf', 'Helvetica-Bold'],
    NotoSansItalic: ['NotoSans-Italic.ttf', 'Helvetica-Oblique'],
  };
  for (const [name, [file, fallback]] of Object.entries(fontFiles)) {
    const filePath = path.join(fontDir, file);
    doc.registerFont(name, fs.existsSync(filePath) ? filePath : fallback);
  }
  doc.rect(0, 0, PAGE.width, PAGE.height).fill('#ffffff');

  const payloadInvoice = invoice.e_invoice_payload?.faturalar?.[0] || {};
  const source = sourceInvoice(officialData, payloadInvoice);
  const supplier = source.tedarikci || {
    unvan: settings.seller_title,
    adresSatir1: settings.seller_address_line1,
    adresSatir2: settings.seller_address_line2,
    sehir: settings.seller_city,
    ulke: settings.seller_country,
    telefon: settings.seller_phone,
    email: settings.seller_email,
    webSitesi: settings.seller_website,
    vkn: settings.seller_vkn,
    belgeNo: settings.seller_vkn,
    belgeTipi: 'VERGI_SICILNO',
  };
  const customer = source.musteri || invoice.customer || {};
  const payloadItems = Array.isArray(payloadInvoice.malHizmetler)
    ? payloadInvoice.malHizmetler
    : [];
  const localItems = Array.isArray(invoice.items) ? invoice.items : [];
  const officialItems = Array.isArray(source.malHizmetler)
    ? source.malHizmetler
    : [];
  const items = mergeLineItems({
    officialItems,
    payloadItems,
    localItems,
  });
  const currency = source.paraBirimi || invoice.currency;
  const officialUrl = `https://${
    environment === 'production'
      ? 'efatura.maliye.gov.ct.tr'
      : 'test-efatura.maliye.gov.ct.tr'
  }/dogrula/?code=${encodeURIComponent(verificationCode)}`;
  const qr = await QRCode.toBuffer(officialUrl, { margin: 0, width: 260 });

  const logoPath = path.resolve(process.cwd(), 'assets/images/kktc_maliye_logo.png');
  if (fs.existsSync(logoPath)) {
    doc.image(logoPath, LEFT, 30, { width: 44, height: 49 });
  }
  doc
    .font('NotoSansBold')
    .fontSize(12)
    .fillColor(COLORS.text)
    .text('K.K.T.C. Maliye Bakanlığı', 89, 33);
  doc.font('NotoSansBold').fontSize(16.5).fillColor(COLORS.red).text('e-FATURA', 89, 53);

  // Firma logosu yalnızca tanımlıysa, Maliye başlığı ile QR arasında kalan
  // boşluğa ortalanır. Logo yoksa Maliye yerleşimi birebir korunur.
  const qrLeft = RIGHT - 79;
  const companyLogoPath = resolveCompanyLogoPath(settings);
  if (companyLogoPath) {
    const companyLogo = doc.openImage(companyLogoPath);
    const titleRight =
      89 +
      doc
        .font('NotoSansBold')
        .fontSize(12)
        .widthOfString('K.K.T.C. Maliye Bakanlığı');
    const zoneLeft = titleRight + 14;
    const zoneRight = qrLeft - 14;
    const scale = Math.min(
      COMPANY_LOGO_MAX.width / companyLogo.width,
      COMPANY_LOGO_MAX.height / companyLogo.height,
      Math.max(0, zoneRight - zoneLeft) / companyLogo.width,
    );
    const logoWidth = companyLogo.width * scale;
    const logoHeight = companyLogo.height * scale;
    const logoLeft = (zoneLeft + zoneRight) / 2 - logoWidth / 2;
    const logoTop = 26 + Math.max(0, (56 - logoHeight) / 2);
    doc.image(companyLogoPath, logoLeft, logoTop, {
      width: logoWidth,
      height: logoHeight,
    });
  }
  doc.image(qr, qrLeft, 26, { width: 79, height: 79 });

  doc
    .font('NotoSans')
    .fontSize(9.4)
    .fillColor(COLORS.label)
    .text(
      `Fatura No: ${text(
        source.faturaNo || invoice.e_invoice_number || invoice.invoice_number,
      )}`,
      LEFT,
      88,
      { width: WIDTH, align: 'left', ellipsis: true },
    );

  const boxTop = 118;

  const boxWidth = (WIDTH - 12) / 2;
  const boxHeight = Math.max(
    170,
    partyHeight(doc, supplier, boxWidth),
    partyHeight(doc, customer, boxWidth),
  );
  drawParty(doc, 'Tedarikçi Bilgileri', supplier, LEFT, boxTop, boxWidth, boxHeight);
  drawParty(
    doc,
    'Müşteri Bilgileri',
    customer,
    LEFT + boxWidth + 12,
    boxTop,
    boxWidth,
    boxHeight,
  );

  const metaTop = boxTop + boxHeight + 12;
  const metaHeight = 44;
  doc
    .lineWidth(0.8)
    .roundedRect(LEFT, metaTop, WIDTH, metaHeight, 6)
    .fillAndStroke('#ffffff', COLORS.border);
  drawMeta(
    doc,
    'FATURA TARİHİ',
    formatDate(source.faturaTarihi || invoice.invoice_date),
    52,
    metaTop,
    112,
  );
  drawMeta(doc, 'İRSALİYE NO', source.irsaliyeNo || invoice.irsaliye_no, 171, metaTop, 126);
  drawMeta(
    doc,
    'İRSALİYE TARİHİ',
    source.irsaliyeTarihi || invoice.irsaliye_tarihi
      ? formatDate(source.irsaliyeTarihi || invoice.irsaliye_tarihi, false)
      : '-',
    305,
    metaTop,
    118,
  );
  drawMeta(doc, 'PARA BİRİMİ', currency, 430, metaTop, 118);

  const listTop = metaTop + metaHeight + 18;
  doc
    .font('NotoSansBold')
    .fontSize(11)
    .fillColor(COLORS.text)
    .text('Mal/Hizmet Listesi', LEFT, listTop);

  let y = listTop + 22;
  const headerHeight = 30;
  doc.rect(LEFT, y, WIDTH, headerHeight).fill(COLORS.headerFill);
  drawGrid(doc, y, headerHeight);
  doc.font('NotoSansBold').fontSize(7.2).fillColor(COLORS.text);
  TABLE_HEADERS.forEach((header, index) => {
    const box = columnBox(index);
    const height = doc.heightOfString(header, { width: box.width, lineGap: 2 });
    doc.text(header, box.x, y + (headerHeight - height) / 2, {
      width: box.width,
      lineGap: 2,
      align: index < 2 ? 'left' : 'right',
    });
  });
  y += headerHeight;

  const rows = items.map((item) => [
    text(item.adi),
    text(item.aciklama, ''),
    `${Number(item.birimMiktari || 0).toLocaleString('tr-TR')}\n${unitName(
      item.birimTurKod,
    )}`,
    money(item.fiyat, currency),
    item.discount ? `-${money(item.discount, currency)}` : '-',
    `${Number(item.taxRate || 0)}%`,
    money(item.tax, currency),
    money(item.total, currency),
  ]);

  const rawDescription = text(source.aciklama, '');
  const poNumber = text(
    invoice.po_number ||
      source.poNumber ||
      source.po_number ||
      '',
    '',
  );
  // PO satırı banka bloğundan ayrılır: banka bilgileri normal, PO koyu basılır.
  // Değer olduğu gibi yazılır, önek eklenmez; boşsa satır hiç görünmez.
  const descriptionLines = rawDescription
    .split(/\r?\n/)
    .map((line) => line.trimEnd());
  let poFromDescription = '';
  const bankLines = [];
  for (const line of descriptionLines) {
    // Eski kayıtlarda açıklama "PO: ..." önekiyle saklanmış olabilir.
    const legacy = line.match(/^\s*PO\s*:\s*(.*?)\s*$/i);
    if (legacy) {
      const value = (legacy[1] || '').trim();
      if (value) poFromDescription = value;
      continue;
    }
    if (poNumber && line.trim() === poNumber.trim()) continue;
    bankLines.push(line);
  }
  while (bankLines.length && !bankLines[bankLines.length - 1].trim()) {
    bankLines.pop();
  }
  const bankDescription = bankLines.join('\n').trim();
  const resolvedPo = (poNumber || poFromDescription).trim();
  const description = bankDescription;
  doc.font('NotoSans').fontSize(DESCRIPTION.fontSize);
  const poBlockHeight = resolvedPo
    ? DESCRIPTION.fontSize + DESCRIPTION.lineGap + 2
    : 0;
  const descriptionHeight = description
    ? DESCRIPTION.top +
      doc.heightOfString(description, {
        width: DESCRIPTION.width,
        lineGap: DESCRIPTION.lineGap,
      }) +
      (resolvedPo ? 4 + poBlockHeight : 0)
    : resolvedPo
      ? DESCRIPTION.top + poBlockHeight
      : 0;
  // Toplamlar, açıklama ve alt bilgi bloklarının tek sayfaya sığması için
  // tabloya ayrılabilecek en alt sınır.
  const tableLimit = FOOTER_RULE_Y - 14 - 121 - descriptionHeight;
  let rendered = 0;
  for (const values of rows) {
    const height = rowHeight(doc, values, 'NotoSans', 7.4);
    if (rendered > 0 && y + height > tableLimit) break;
    drawRow(doc, values, y, height, 'NotoSans', 7.4);
    y += height;
    rendered += 1;
  }
  if (rendered < rows.length) {
    doc
      .font('NotoSansItalic')
      .fontSize(6.6)
      .fillColor(COLORS.label)
      .text(`+ ${rows.length - rendered} kalem UBL/XML kaydında yer almaktadır.`, LEFT + 4, y + 5);
    y += 18;
  }

  const discountTotal = Number(source.iskontoToplami ?? invoice.discount_total) || 0;
  const totals = [
    ['Ara Toplam:', money(source.faturaToplami ?? invoice.subtotal, currency)],
    ['İndirim Toplamı:', `-${money(discountTotal, currency)}`],
    ['KDV Toplamı:', money(source.kdvToplami ?? invoice.tax_total, currency)],
  ];
  y += 16;
  const totalsLeft = 253.5;
  totals.forEach(([label, value]) => {
    doc
      .font('NotoSans')
      .fontSize(8)
      .fillColor(COLORS.text)
      .text(label, totalsLeft, y, { width: 160 })
      .text(value, 401, y, { width: RIGHT - 401, align: 'right' });
    y += 16.5;
  });
  doc
    .lineWidth(0.8)
    .moveTo(totalsLeft, y + 3)
    .lineTo(RIGHT, y + 3)
    .strokeColor(COLORS.border)
    .stroke();
  y += 13;
  const payable = source.odenecekToplam ?? invoice.grand_total;
  doc
    .font('NotoSansBold')
    .fontSize(10.5)
    .fillColor(COLORS.text)
    .text('Ödenecek Toplam:', totalsLeft, y, { width: 170 })
    .text(money(payable, currency), 401, y, { width: RIGHT - 401, align: 'right' });
  y += 20;
  doc
    .font('NotoSansItalic')
    .fontSize(6.8)
    .fillColor(COLORS.label)
    .text(`Yalnız: ${amountInWords(payable, currency)}`, 220, y, {
      width: RIGHT - 220,
      align: 'right',
    });
  y += 22;

  if (description || resolvedPo) {
    doc
      .font('NotoSansBold')
      .fontSize(DESCRIPTION.titleFontSize)
      .fillColor(COLORS.text)
      .text('Açıklama', LEFT, y);
    let textY = y + DESCRIPTION.top;
    if (description) {
      doc
        .font('NotoSans')
        .fontSize(DESCRIPTION.fontSize)
        .fillColor(COLORS.text)
        .text(description, LEFT, textY, {
          width: DESCRIPTION.width,
          lineGap: DESCRIPTION.lineGap,
        });
      textY = doc.y + 4;
    }
    if (resolvedPo) {
      doc
        .font('NotoSansBold')
        .fontSize(DESCRIPTION.fontSize)
        .fillColor(COLORS.text)
        .text(resolvedPo, LEFT, textY, {
          width: DESCRIPTION.width,
        });
    }
  }

  doc
    .lineWidth(0.8)
    .moveTo(LEFT, FOOTER_RULE_Y)
    .lineTo(RIGHT, FOOTER_RULE_Y)
    .strokeColor(COLORS.border)
    .stroke();
  doc
    .font('NotoSans')
    .fontSize(7)
    .fillColor(COLORS.footer)
    .text(
      'Bu fatura elektronik ortamda oluşturulmuş olup, yasal geçerliliği bulunmaktadır.',
      LEFT,
      FOOTER_RULE_Y + 12,
      { width: WIDTH, align: 'center' },
    )
    .text(`Doğrulama Kodu: ${verificationCode}`, LEFT, FOOTER_RULE_Y + 25, {
      width: WIDTH,
      align: 'center',
    })
    .text(
      `Oluşturma Tarihi: ${formatDate(new Date().toISOString())}`,
      LEFT,
      FOOTER_RULE_Y + 38,
      { width: WIDTH, align: 'center' },
    );

  doc.end();
  return completed;
}

module.exports = {
  buildEInvoiceArchivePdf,
  mergeLineItems,
  parseAmount,
  firstPositiveAmount,
};
