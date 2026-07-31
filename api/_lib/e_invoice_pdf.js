const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const MODULE_ROOT = path.resolve(__dirname, '../..');
const PAGE = { width: 595.28, height: 841.89 };
// Maliye çıktısındaki yaklaşık 16 mm yatay kenar boşlukları.
const LEFT = 48;
const RIGHT = 548;
const WIDTH = RIGHT - LEFT;
const FOOTER_RULE_Y = 778;

const COLORS = {
  text: '#1f242c',
  label: '#6b7075',
  footer: '#9aa0a8',
  border: '#dfe2e6',
  grid: '#cfd3d8',
  headerFill: '#f4f5f7',
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

function documentTypeLabel(value) {
  const code = String(value || '')
    .trim()
    .toUpperCase()
    .replace(/[\s-]+/g, '_');
  return (
    {
      VERGI_SICILNO: 'Vergi Sicil Numarası',
      VERGISICILNO: 'Vergi Sicil Numarası',
      YABANCI_KIMLIKNO: 'Yabancı Kimlik Numarası',
      YABANCIKIMLIKNO: 'Yabancı Kimlik Numarası',
      KIMLIKNO: 'Kimlik Numarası',
      TCKN: 'T.C. Kimlik Numarası',
      PASAPORTNO: 'Pasaport Numarası',
      VKN: 'VKN',
    }[code] || text(value, 'Belge No')
  );
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

function unitName(value, { short = false } = {}) {
  const code = String(value || '').toUpperCase();
  const full = {
    C62: 'ADET(UNIT)',
    KGM: 'KG(KILOGRAM)',
    LTR: 'LT(LITRE)',
    MTR: 'MT(METRE)',
    HUR: 'SAAT(HOUR)',
  }[code];
  if (short) {
    return (
      {
        C62: 'Adet',
        KGM: 'Kg',
        LTR: 'Lt',
        MTR: 'Mt',
        HUR: 'Saat',
      }[code] || text(value)
    );
  }
  return full || text(value);
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
      USD: ['ABD DOLARI', 'SENT'],
      EUR: ['EURO', 'CENT'],
      GBP: ['İNGİLİZ STERLİNİ', 'PENİ'],
    }[String(currency || '').toUpperCase()] || [text(currency, 'PARA'), ''];
  return `#${integerWords(whole)} ${labels[0]}${
    fraction ? ` ${integerWords(fraction)} ${labels[1]}` : ''
  }#`;
}

function partyLines(party) {
  const addressParts = [
    party?.adresSatir1 || party?.adres || party?.address,
    party?.adresSatir2 || party?.addressLine2,
    [party?.sehir || party?.city, party?.ulke || party?.country]
      .map((value) => text(value, ''))
      .filter(Boolean)
      .join(', '),
  ]
    .map((value) => text(value, ''))
    .filter(Boolean);
  // Maliye çıktısı adresi tek satırda birleştirir.
  const address = addressParts.join(' ');
  const documentNumber = party?.belgeNo || party?.documentNumber;
  const documentType = party?.belgeTipi || party?.documentType;
  const lines = [
    text(party?.unvan || party?.name),
    address,
    `Tel: ${text(party?.telefon || party?.phone)}`,
    `E-posta: ${text(party?.email)}`,
    `Web: ${text(party?.webSitesi || party?.website)}`,
  ];
  if (party?.vkn || party?.tax_number) {
    lines.push(`VKN: ${text(party?.vkn || party?.tax_number)}`);
  }
  if (documentType || documentNumber) {
    lines.push(
      `${documentTypeLabel(documentType)}: ${text(documentNumber)}`,
    );
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

const COMPANY_LOGO_MAX = { width: 132, height: 46 };

// Açıklama bloğu (banka bilgileri) ölçüleri; hem yer hesabında hem çizimde
// kullanılır ki tek sayfaya sığma sınırı doğru kalsın.
const DESCRIPTION = {
  titleFontSize: 8.5,
  fontSize: 6.6,
  lineGap: 1.6,
  top: 14,
  // Toplamlar sağda; açıklama sol sütunda yan yana basılır.
  width: 250,
};

function descriptionBlockHeight(doc, description, resolvedPo) {
  if (!description && !resolvedPo) return 0;
  const poBlockHeight = resolvedPo
    ? DESCRIPTION.fontSize + DESCRIPTION.lineGap + 2
    : 0;
  doc.font('Invoice').fontSize(DESCRIPTION.fontSize);
  const bodyHeight = description
    ? doc.heightOfString(description, {
        width: DESCRIPTION.width,
        lineGap: DESCRIPTION.lineGap,
      }) + (resolvedPo ? 4 + poBlockHeight : 0)
    : poBlockHeight;
  return DESCRIPTION.titleFontSize + DESCRIPTION.top + bodyHeight;
}

function resolveAssetPath(...parts) {
  const relative = path.join(...parts);
  const candidates = [
    path.resolve(MODULE_ROOT, relative),
    path.resolve(process.cwd(), relative),
    path.resolve(__dirname, relative),
  ];
  return candidates.find((candidate) => fs.existsSync(candidate)) || null;
}

function resolveCompanyLogoPath(settings) {
  const candidates = [
    text(settings?.seller_logo_path, ''),
    text(settings?.seller_logo, ''),
    resolveAssetPath('assets/images/company_logo.png'),
  ].filter(Boolean);
  for (const candidate of candidates) {
    const resolved = path.isAbsolute(candidate)
      ? candidate
      : resolveAssetPath(candidate) || path.resolve(process.cwd(), candidate);
    if (resolved && fs.existsSync(resolved)) return resolved;
  }
  return null;
}

function drawParty(doc, title, party, x, y, width, height) {
  doc.lineWidth(0.8).roundedRect(x, y, width, height, 6).stroke(COLORS.border);
  doc
    .font('InvoiceBold')
    .fontSize(10)
    .fillColor(COLORS.text)
    .text(title, x + 7, y + 8);
  doc
    .lineWidth(0.7)
    .moveTo(x + 7, y + 25)
    .lineTo(x + width - 7, y + 25)
    .strokeColor(COLORS.border)
    .stroke();
  const body = partyLines(party);
  const bodyWidth = width - 14;
  const bodyHeight = height - 36;
  let bodyFontSize = 7.1;
  while (bodyFontSize > 5.8) {
    doc.font('Invoice').fontSize(bodyFontSize);
    if (
      doc.heightOfString(body, {
        width: bodyWidth,
        lineGap: 0.7,
      }) <= bodyHeight
    ) {
      break;
    }
    bodyFontSize -= 0.2;
  }
  doc
    .font('Invoice')
    .fontSize(bodyFontSize)
    .fillColor(COLORS.text)
    .text(body, x + 7, y + 31, {
      width: bodyWidth,
      height: bodyHeight,
      lineGap: 0.7,
      ellipsis: true,
    });
}

function drawMeta(doc, label, value, x, y, width, row = 0, rowHeight = 30) {
  const rowTop = y + row * rowHeight;
  doc
    .font('Invoice')
    .fontSize(6.0)
    .fillColor(COLORS.label)
    .text(label, x, rowTop + 5, { width, ellipsis: true });
  doc
    .font('InvoiceBold')
    .fontSize(7.4)
    .fillColor(COLORS.text)
    .text(text(value), x, rowTop + 16, { width, ellipsis: true });
}

const TABLE_COLUMNS = [48, 160, 272, 336, 384, 421, 458, 504, 548];
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
  const x = TABLE_COLUMNS[index] + 3;
  return { x, width: TABLE_COLUMNS[index + 1] - TABLE_COLUMNS[index] - 6 };
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
    return Math.max(
      max,
      doc.heightOfString(value, { width: box.width, lineGap: 0.6 }),
    );
  }, 0);
  // Uzun isimler tek satırı şişirmesin; 15 kalem hedefi için tavan.
  return Math.min(tallest + 3.5, 16.5);
}

const TABLE_HEADER_HEIGHT = 20;
// Toplamlar bloğunun (ara toplam -> "Yalnız" satırı) toplam yüksekliği.
const TOTALS_BLOCK_HEIGHT = 96;
// Devam sayfalarında içeriğin başladığı üst sınır.
const CONTINUATION_TOP = 44;

function drawTopBar(doc, createdAt) {
  doc
    .font('Invoice')
    .fontSize(6.2)
    .fillColor(COLORS.text)
    .text(formatDate(createdAt), 22, 18, { width: 100 })
    .text('KKTC E-Fatura Sistemi', 225, 18, {
      width: 145,
      align: 'center',
    });
}

function drawTableHeader(doc, y) {
  doc.rect(LEFT, y, WIDTH, TABLE_HEADER_HEIGHT).fill(COLORS.headerFill);
  drawGrid(doc, y, TABLE_HEADER_HEIGHT);
  doc.font('InvoiceBold').fontSize(6.6).fillColor(COLORS.text);
  TABLE_HEADERS.forEach((header, index) => {
    const box = columnBox(index);
    const height = doc.heightOfString(header, { width: box.width, lineGap: 0.4 });
    doc.text(header, box.x, y + (TABLE_HEADER_HEIGHT - height) / 2, {
      width: box.width,
      lineGap: 0.4,
      align: index < 2 ? 'left' : 'right',
    });
  });
  return y + TABLE_HEADER_HEIGHT;
}

function drawRow(doc, values, y, height, font, size) {
  drawGrid(doc, y, height);
  doc.font(font).fontSize(size).fillColor(COLORS.text);
  values.forEach((value, index) => {
    const box = columnBox(index);
    const textHeight = Math.min(
      height - 2,
      doc.heightOfString(value, {
        width: box.width,
        lineGap: 0.6,
      }),
    );
    doc.text(value, box.x, y + (height - textHeight) / 2, {
      width: box.width,
      height: height - 2,
      lineGap: 0.6,
      align: index < 2 ? 'left' : 'right',
      ellipsis: true,
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
    // Tüm öğeler Maliye şablonuna göre mutlak koordinatla çiziliyor.
    // Alt doğrulama URL'sinin otomatik yeni sayfa açmaması için margin yok.
    margins: { top: 0, right: 0, bottom: 0, left: 0 },
    // Sayfa numarası (n/toplam) ancak tüm sayfalar oluşunca yazılabilir.
    bufferPages: true,
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

  // Helvetica/WinAnsi Türkçe karakterleri bozar; yalnızca gömülü TTF kullan.
  // Noto Sans (statik) öncelikli; Inter yedek. Vercel'de process.cwd() altında
  // assets olmayabilir, bu yüzden __dirname üzerinden de aranır.
  const fontSets = [
    {
      Invoice: 'assets/fonts/noto_sans/NotoSans-Regular.ttf',
      InvoiceBold: 'assets/fonts/noto_sans/NotoSans-Bold.ttf',
      InvoiceItalic: 'assets/fonts/noto_sans/NotoSans-Italic.ttf',
    },
    {
      Invoice: 'assets/fonts/inter/Inter-Regular.ttf',
      InvoiceBold: 'assets/fonts/inter/Inter-Bold.ttf',
      InvoiceItalic: 'assets/fonts/inter/Inter-Italic.ttf',
    },
  ];
  for (const name of ['Invoice', 'InvoiceBold', 'InvoiceItalic']) {
    const found = fontSets
      .map((set) => resolveAssetPath(set[name]))
      .find(Boolean);
    if (!found) {
      throw new Error(
        `PDF fontu bulunamadı (${name}). ` +
          'assets/fonts/noto_sans veya assets/fonts/inter dosyaları deploy paketinde olmalı.',
      );
    }
    doc.registerFont(name, found);
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
  const createdAt = new Date().toISOString();

  // Maliye PDF görüntüleyicisindeki resmi üst bilgi.
  drawTopBar(doc, createdAt);

  const logoPath = resolveAssetPath('assets/images/kktc_maliye_logo.png');
  if (logoPath) {
    doc.image(logoPath, LEFT, 57, { width: 42, height: 47 });
  }
  doc
    .font('InvoiceBold')
    .fontSize(11.5)
    .fillColor(COLORS.text)
    .text('K.K.T.C. Maliye Bakanlığı', 96, 57);
  doc
    .font('InvoiceBold')
    .fontSize(15.5)
    .fillColor(COLORS.red)
    .text('e-FATURA', 96, 76);

  // Firma logosu yalnızca tanımlıysa, Maliye başlığı ile QR arasında kalan
  // boşluğa ortalanır. Logo yoksa Maliye yerleşimi birebir korunur.
  const qrSize = 48;
  const qrLeft = RIGHT - qrSize;
  const companyLogoPath = resolveCompanyLogoPath(settings);
  if (companyLogoPath) {
    const companyLogo = doc.openImage(companyLogoPath);
    const titleRight =
      96 +
      doc
        .font('InvoiceBold')
        .fontSize(11.5)
        .widthOfString('K.K.T.C. Maliye Bakanlığı');
    const zoneLeft = titleRight + 12;
    const zoneRight = qrLeft - 16;
    const scale = Math.min(
      COMPANY_LOGO_MAX.width / companyLogo.width,
      COMPANY_LOGO_MAX.height / companyLogo.height,
      Math.max(0, zoneRight - zoneLeft) / companyLogo.width,
    );
    const logoWidth = companyLogo.width * scale;
    const logoHeight = companyLogo.height * scale;
    const logoLeft = (zoneLeft + zoneRight) / 2 - logoWidth / 2;
    const logoTop = 55 + Math.max(0, (49 - logoHeight) / 2);
    doc.image(companyLogoPath, logoLeft, logoTop, {
      width: logoWidth,
      height: logoHeight,
    });
  }
  doc.image(qr, qrLeft, 56, { width: qrSize, height: qrSize });

  doc
    .font('Invoice')
    .fontSize(8.2)
    .fillColor(COLORS.label)
    .text(
      `Fatura No: ${text(
        source.faturaNo || invoice.e_invoice_number || invoice.invoice_number,
      )}`,
      96,
      94,
      { width: 310, align: 'left', ellipsis: true },
    );

  const boxTop = 108;

  const boxWidth = (WIDTH - 16) / 2;
  // Maliye şablonunda taraf kutuları sabit yükseklikte; uzun metin kutu içinde
  // ellipsis ile sınırlandırılır ve takip eden blokları aşağı itmez.
  const boxHeight = 98;
  drawParty(doc, 'Tedarikçi Bilgileri', supplier, LEFT, boxTop, boxWidth, boxHeight);
  drawParty(
    doc,
    'Müşteri Bilgileri',
    customer,
    LEFT + boxWidth + 16,
    boxTop,
    boxWidth,
    boxHeight,
  );

  const metaTop = boxTop + boxHeight + 5;
  const metaHeight = 60;
  const metaMidX = LEFT + WIDTH / 2;
  const metaMidY = metaTop + metaHeight / 2;
  doc
    .lineWidth(0.8)
    .roundedRect(LEFT, metaTop, WIDTH, metaHeight, 6)
    .fillAndStroke('#ffffff', COLORS.border);
  // Maliye meta kutusu 2x2 ızgara: dikey + yatay orta çizgiler.
  doc
    .lineWidth(0.7)
    .strokeColor(COLORS.border)
    .moveTo(metaMidX, metaTop)
    .lineTo(metaMidX, metaTop + metaHeight)
    .stroke()
    .moveTo(LEFT, metaMidY)
    .lineTo(RIGHT, metaMidY)
    .stroke();
  drawMeta(
    doc,
    'FATURA TARİHİ',
    formatDate(source.faturaTarihi || invoice.invoice_date),
    LEFT + 10,
    metaTop,
    metaMidX - LEFT - 20,
  );
  drawMeta(
    doc,
    'İRSALİYE NO',
    source.irsaliyeNo || invoice.irsaliye_no,
    metaMidX + 10,
    metaTop,
    RIGHT - metaMidX - 20,
  );
  drawMeta(
    doc,
    'İRSALİYE TARİHİ',
    source.irsaliyeTarihi || invoice.irsaliye_tarihi
      ? formatDate(source.irsaliyeTarihi || invoice.irsaliye_tarihi, false)
      : '-',
    LEFT + 10,
    metaTop,
    metaMidX - LEFT - 20,
    1,
  );
  drawMeta(
    doc,
    'PARA BİRİMİ',
    currency,
    metaMidX + 10,
    metaTop,
    RIGHT - metaMidX - 20,
    1,
  );

  const listTop = metaTop + metaHeight + 5;
  doc
    .lineWidth(0.7)
    .moveTo(LEFT, listTop)
    .lineTo(RIGHT, listTop)
    .strokeColor(COLORS.border)
    .stroke();
  doc
    .font('InvoiceBold')
    .fontSize(9)
    .fillColor(COLORS.text)
    .text('Mal/Hizmet Listesi', LEFT, listTop + 5);

  let y = drawTableHeader(doc, listTop + 18);

  const rows = items.map((item) => [
    text(item.adi),
    text(item.aciklama, ''),
    `${Number(item.birimMiktari || 0).toLocaleString('tr-TR')} ${unitName(
      item.birimTurKod,
      { short: true },
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
  const descHeight = descriptionBlockHeight(doc, description, resolvedPo);
  // Kalemler hiçbir zaman kırpılmaz; sığmayanlar devam sayfasına taşar.
  const tableBottom = FOOTER_RULE_Y - 14;
  const startContinuationPage = (title) => {
    doc.addPage();
    doc.rect(0, 0, PAGE.width, PAGE.height).fill('#ffffff');
    drawTopBar(doc, createdAt);
    doc
      .font('InvoiceBold')
      .fontSize(10.5)
      .fillColor(COLORS.text)
      .text(title, LEFT, CONTINUATION_TOP);
    return CONTINUATION_TOP + 19;
  };

  let rowsOnPage = 0;
  for (const values of rows) {
    const height = rowHeight(doc, values, 'Invoice', 6.4);
    // rowsOnPage kontrolü, tek başına sayfadan uzun satırlarda sonsuz döngüyü önler.
    if (rowsOnPage > 0 && y + height > tableBottom) {
      y = drawTableHeader(doc, startContinuationPage('Mal/Hizmet Listesi (devam)'));
      rowsOnPage = 0;
    }
    drawRow(doc, values, y, height, 'Invoice', 6.4);
    y += height;
    rowsOnPage += 1;
  }

  // Toplamlar sağda, açıklama solda yan yana. Açıklama uzun diye
  // toplamları 2. sayfaya itme; gerekirse yalnız açıklama taşar.
  const blockTopGap = 6;
  if (y + blockTopGap + TOTALS_BLOCK_HEIGHT > tableBottom) {
    y = startContinuationPage('Fatura Toplamları') + 6;
  }

  const discountTotal = Number(source.iskontoToplami ?? invoice.discount_total) || 0;
  const totals = [
    ['Ara Toplam:', money(source.faturaToplami ?? invoice.subtotal, currency)],
    ['İndirim Toplamı:', `-${money(discountTotal, currency)}`],
    ['KDV Toplamı:', money(source.kdvToplami ?? invoice.tax_total, currency)],
  ];
  y += blockTopGap;
  const totalsStartY = y;
  const totalsLeft = 306;
  totals.forEach(([label, value]) => {
    doc
      .font('Invoice')
      .fontSize(7.2)
      .fillColor(COLORS.text)
      .text(label, totalsLeft, y, { width: 130 });
    doc
      .font('InvoiceBold')
      .fontSize(7.2)
      .fillColor(COLORS.text)
      .text(value, 438, y, { width: RIGHT - 438, align: 'right' });
    y += 12.5;
  });
  doc
    .lineWidth(0.8)
    .moveTo(totalsLeft, y + 2)
    .lineTo(RIGHT, y + 2)
    .strokeColor(COLORS.border)
    .stroke();
  y += 8;
  const payable = source.odenecekToplam ?? invoice.grand_total;
  doc
    .font('InvoiceBold')
    .fontSize(9.2)
    .fillColor(COLORS.text)
    .text('Ödenecek Toplam:', totalsLeft, y, { width: 150 })
    .text(money(payable, currency), 438, y, {
      width: RIGHT - 438,
      align: 'right',
    });
  y += 15;
  doc
    .font('InvoiceItalic')
    .fontSize(6.2)
    .fillColor(COLORS.label)
    .text(`Yalnız: ${amountInWords(payable, currency)}`, 350, y, {
      width: RIGHT - 350,
      align: 'right',
    });
  const totalsEndY = y + 12;

  let descriptionEndY = totalsStartY;
  if (description || resolvedPo) {
    const descriptionFitsHere = totalsStartY + descHeight <= tableBottom;
    let descY = totalsStartY;
    if (!descriptionFitsHere) {
      descY = startContinuationPage('Açıklama');
    }
    doc
      .font('InvoiceBold')
      .fontSize(DESCRIPTION.titleFontSize)
      .fillColor(COLORS.text)
      .text('Açıklama', LEFT, descY);
    let textY = descY + DESCRIPTION.top;
    if (description) {
      doc
        .font('Invoice')
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
        .font('InvoiceBold')
        .fontSize(DESCRIPTION.fontSize)
        .fillColor(COLORS.text)
        .text(resolvedPo, LEFT, textY, {
          width: DESCRIPTION.width,
        });
      textY = doc.y;
    }
    descriptionEndY = textY;
  }

  y = Math.max(totalsEndY, descriptionEndY);

  doc
    .lineWidth(0.8)
    .moveTo(LEFT, FOOTER_RULE_Y)
    .lineTo(RIGHT, FOOTER_RULE_Y)
    .strokeColor(COLORS.border)
    .stroke();
  doc
    .font('Invoice')
    .fontSize(6.5)
    .fillColor(COLORS.footer)
    .text(
      'Bu fatura elektronik ortamda oluşturulmuş olup, yasal geçerliliği bulunmaktadır.',
      LEFT,
      FOOTER_RULE_Y + 8,
      { width: WIDTH, align: 'center' },
    )
    .text(`Doğrulama Kodu: ${verificationCode}`, LEFT, FOOTER_RULE_Y + 18, {
      width: WIDTH,
      align: 'center',
    })
    .text(
      `Oluşturma Tarihi: ${formatDate(createdAt)}`,
      LEFT,
      FOOTER_RULE_Y + 28,
      { width: WIDTH, align: 'center' },
    );

  // Maliye çıktısındaki sayfa altı doğrulama adresi ve sayfa numarası.
  const pages = doc.bufferedPageRange();
  for (let index = 0; index < pages.count; index += 1) {
    doc.switchToPage(pages.start + index);
    doc
      .font('Invoice')
      .fontSize(5.8)
      .fillColor(COLORS.text)
      .text(officialUrl, 22, PAGE.height - 22, {
        width: 430,
        ellipsis: true,
      })
      .text(`${index + 1}/${pages.count}`, RIGHT - 25, PAGE.height - 22, {
        width: 25,
        align: 'right',
      });
  }

  doc.end();
  return completed;
}

module.exports = {
  buildEInvoiceArchivePdf,
  mergeLineItems,
  parseAmount,
  firstPositiveAmount,
};
