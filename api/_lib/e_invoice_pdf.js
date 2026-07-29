const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const COLORS = {
  text: '#111827',
  muted: '#4b5563',
  subtle: '#6b7280',
  border: '#d9e1e8',
  band: '#f7f9fb',
  red: '#d92d20',
};

function text(value, fallback = '-') {
  const normalized = String(value ?? '').trim();
  return normalized || fallback;
}

function money(value, currency) {
  const numericValue = Number(value || 0);
  const amount = Math.abs(numericValue).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  const sign = numericValue < 0 ? '-' : '';
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
  return lines.filter(Boolean);
}

function drawParty(doc, title, party, x, y, width, height) {
  doc.lineWidth(0.7).roundedRect(x, y, width, height, 5).stroke(COLORS.border);
  doc.font('NotoSans').fontSize(9.3).fillColor(COLORS.text).text(title, x + 10, y + 10);
  doc
    .moveTo(x + 10, y + 31)
    .lineTo(x + width - 10, y + 31)
    .strokeColor('#e8edf2')
    .stroke();
  doc
    .font('NotoSans')
    .fontSize(7.2)
    .fillColor(COLORS.text)
    .text(partyLines(party).join('\n'), x + 10, y + 42, {
      width: width - 20,
      height: height - 50,
      lineGap: 1.8,
      ellipsis: true,
    });
}

function drawMeta(doc, label, value, x, y, width) {
  doc
    .font('NotoSans')
    .fontSize(6.4)
    .fillColor(COLORS.subtle)
    .text(label, x, y, { width });
  doc
    .fontSize(7.5)
    .fillColor(COLORS.text)
    .text(text(value), x, y + 15, { width, ellipsis: true });
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
  const whole = Math.floor(amount);
  let fraction = Math.round((amount - whole) * 100);
  let normalizedWhole = whole;
  if (fraction === 100) {
    normalizedWhole += 1;
    fraction = 0;
  }
  const labels =
    {
      TRY: ['TÜRK LİRASI', 'KURUŞ'],
      USD: ['AMERİKAN DOLARI', 'SENT'],
      EUR: ['EURO', 'CENT'],
      GBP: ['İNGİLİZ STERLİNİ', 'PENİ'],
    }[String(currency || '').toUpperCase()] || [text(currency, 'PARA'), ''];
  return `#${integerWords(normalizedWhole)} ${labels[0]}${
    fraction ? ` ${integerWords(fraction)} ${labels[1]}` : ''
  }#`;
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
  const normalizedOfficial = Array.isArray(official) ? official[0] || {} : official;
  return { ...payloadInvoice, ...normalizedOfficial };
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

  const fontPath = path.resolve(
    process.cwd(),
    'assets/fonts/noto_sans/NotoSans-Regular.ttf',
  );
  if (fs.existsSync(fontPath)) {
    doc.registerFont('NotoSans', fontPath);
    const italicPath = path.resolve(
      process.cwd(),
      'assets/fonts/noto_sans/NotoSans-Italic.ttf',
    );
    doc.registerFont(
      'NotoSansItalic',
      fs.existsSync(italicPath) ? italicPath : fontPath,
    );
    doc.font('NotoSans');
  } else {
    doc.registerFont('NotoSans', 'Helvetica');
    doc.registerFont('NotoSansItalic', 'Helvetica-Oblique');
    doc.font('Helvetica');
  }
  doc.rect(0, 0, 595.28, 841.89).fill('#ffffff');

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
  const items =
    source.malHizmetler ||
    (Array.isArray(invoice.items)
      ? invoice.items.map((item) => ({
          adi: item.description,
          birimMiktari: item.quantity,
          birimTurKod: item.unit,
          fiyat: item.unit_price,
          aciklama: item.description,
          iskontoVeEkUcretler: [
            { indirimMi: true, tutar: item.discount_amount || 0 },
          ],
          vergiler: [
            { vergiOrani: item.tax_rate, vergiTutari: item.tax_amount || 0 },
          ],
        }))
      : []);
  const currency = source.paraBirimi || invoice.currency;
  const officialUrl = `https://${
    environment === 'production'
      ? 'efatura.maliye.gov.ct.tr'
      : 'test-efatura.maliye.gov.ct.tr'
  }/dogrula/?code=${encodeURIComponent(verificationCode)}`;
  const qr = await QRCode.toBuffer(officialUrl, { margin: 0, width: 220 });

  const logoPath = path.resolve(process.cwd(), 'assets/images/kktc_maliye_logo.png');
  if (fs.existsSync(logoPath)) doc.image(logoPath, 34, 28, { width: 45, height: 62 });
  doc.font('NotoSans').fontSize(11.5).fillColor(COLORS.text).text(
    'K.K.T.C. Maliye Bakanlığı',
    86,
    29,
  );
  doc.fontSize(16).fillColor(COLORS.red).text('e-FATURA', 86, 49);
  doc
    .fontSize(7.5)
    .fillColor(COLORS.muted)
    .text(
      `Fatura No: ${text(source.faturaNo || invoice.e_invoice_number || invoice.invoice_number)}`,
      86,
      74,
      { width: 390 },
    )
  doc.image(qr, 501, 25, { width: 60 });

  drawParty(doc, 'Tedarikçi Bilgileri', supplier, 34, 112, 252, 178);
  drawParty(doc, 'Müşteri Bilgileri', customer, 309, 112, 252, 178);

  doc.roundedRect(34, 309, 527, 45, 5).fillAndStroke(COLORS.band, COLORS.border);
  drawMeta(doc, 'FATURA TARİHİ', formatDate(source.faturaTarihi || invoice.invoice_date), 45, 319, 112);
  drawMeta(doc, 'İRSALİYE NO', source.irsaliyeNo || invoice.irsaliye_no, 165, 319, 102);
  drawMeta(
    doc,
    'İRSALİYE TARİHİ',
    source.irsaliyeTarihi || invoice.irsaliye_tarihi
      ? formatDate(source.irsaliyeTarihi || invoice.irsaliye_tarihi, false)
      : '-',
    284,
    319,
    105,
  );
  drawMeta(doc, 'PARA BİRİMİ', currency, 431, 319, 105);
  doc
    .moveTo(34, 374)
    .lineTo(561, 374)
    .strokeColor('#e8edf2')
    .stroke();
  doc.font('NotoSans').fontSize(10).fillColor(COLORS.text).text('Mal/Hizmet Listesi', 34, 391);

  const columns = [34, 115, 194, 263, 330, 382, 430, 487, 561];
  let y = 414;
  doc.rect(34, y, 527, 31).fill('#fafbfd');
  const headers = [
    'Mal/Hizmet',
    'Açıklama',
    'Miktar',
    'Birim Fiyat',
    'İndirim',
    'KDV (%)',
    'KDV Tutarı',
    'Toplam',
  ];
  headers.forEach((header, index) => {
    doc
      .font('NotoSans')
      .fontSize(5.8)
      .fillColor(COLORS.text)
      .text(header, columns[index] + 3, y + 10, {
        width: columns[index + 1] - columns[index] - 6,
        align: index === 0 ? 'left' : 'right',
      });
  });
  y += 31;

  const maxRows = 5;
  items.slice(0, maxRows).forEach((item) => {
    const qty = Number(item.birimMiktari ?? item.quantity ?? 0);
    const price = Number(item.fiyat ?? item.unit_price ?? 0);
    const discount = Number(
      item.iskontoVeEkUcretler?.find((entry) => entry?.indirimMi !== false)?.tutar ??
        item.discount_amount ??
        0,
    );
    const tax = Number(item.vergiler?.[0]?.vergiTutari ?? item.tax_amount ?? 0);
    const total = Number(item.toplam ?? item.tutar ?? qty * price - discount + tax);
    const values = [
      text(item.adi || item.description),
      text(item.aciklama || item.description),
      `${qty.toLocaleString('tr-TR')}\n${unitName(item.birimTurKod || item.unit)}`,
      money(price, currency),
      discount ? `-${money(discount, currency)}` : '-',
      `%${Number(item.vergiler?.[0]?.vergiOrani ?? item.tax_rate ?? 0)}`,
      money(tax, currency),
      money(total, currency),
    ];
    const rowHeight = 38;
    doc.rect(34, y, 527, rowHeight).stroke('#e5e7eb');
    values.forEach((value, index) => {
      doc
        .font('NotoSans')
        .fontSize(5.6)
        .fillColor(COLORS.text)
        .text(value, columns[index] + 3, y + 9, {
          width: columns[index + 1] - columns[index] - 6,
          height: rowHeight - 12,
          ellipsis: true,
          align: index < 2 ? 'left' : 'right',
        });
    });
    y += rowHeight;
  });
  if (items.length > maxRows) {
    doc
      .font('NotoSansItalic')
      .fontSize(6)
      .fillColor(COLORS.subtle)
      .text(`+ ${items.length - maxRows} kalem UBL/XML kaydında yer almaktadır.`, 37, y + 4);
    y += 16;
  }

  const totals = [
    ['Ara Toplam', source.faturaToplami ?? invoice.subtotal],
    ['İndirim Toplamı', -(Number(source.iskontoToplami ?? invoice.discount_total) || 0)],
    ['KDV Toplamı', source.kdvToplami ?? invoice.tax_total],
    ['Ödenecek Toplam', source.odenecekToplam ?? invoice.grand_total],
  ];
  y += 18;
  const totalsStartY = y;
  totals.forEach(([label, value], index) => {
    doc
      .font('NotoSans')
      .fontSize(index === totals.length - 1 ? 8.8 : 7)
      .fillColor(COLORS.text)
      .text(label, 320, y, { width: 120, align: 'left' })
      .text(money(value, currency), 455, y, { width: 106, align: 'right' });
    if (index === totals.length - 2) {
      doc.moveTo(320, y + 14).lineTo(561, y + 14).strokeColor(COLORS.border).stroke();
    }
    y += index === totals.length - 1 ? 22 : 17;
  });
  const payable = source.odenecekToplam ?? invoice.grand_total;
  doc
    .font('NotoSansItalic')
    .fontSize(5.8)
    .fillColor(COLORS.subtle)
    .text(`Yalnız: ${amountInWords(payable, currency)}`, 250, y - 2, {
      width: 311,
      align: 'right',
    });

  const description = text(source.aciklama, '');
  if (description) {
    const compactDescription = y + 30 > 675;
    const descriptionY = compactDescription ? totalsStartY : Math.max(y + 30, 650);
    const descriptionWidth = compactDescription ? 255 : 527;
    doc
      .font('NotoSans')
      .fontSize(9)
      .fillColor(COLORS.text)
      .text('Açıklama', 34, descriptionY);
    doc
      .fontSize(6.5)
      .fillColor(COLORS.text)
      .text(description, 34, descriptionY + 22, {
        width: descriptionWidth,
        height: compactDescription ? 75 : 60,
        lineGap: 1.5,
        ellipsis: true,
      });
  }
  const createdAt = formatDate(new Date().toISOString());
  doc.moveTo(34, 760).lineTo(561, 760).strokeColor('#e8edf2').stroke();
  doc
    .font('NotoSans')
    .fontSize(5.8)
    .fillColor(COLORS.subtle)
    .text(
      'Bu fatura elektronik ortamda oluşturulmuş olup, yasal geçerliliği bulunmaktadır.',
      34,
      770,
      { width: 527, align: 'center' },
    )
    .text(`Doğrulama Kodu: ${verificationCode}`, 34, 783, {
      width: 527,
      align: 'center',
    })
    .text(`Oluşturma Tarihi: ${createdAt}`, 34, 796, {
      width: 527,
      align: 'center',
    });

  doc.end();
  return completed;
}

module.exports = { buildEInvoiceArchivePdf };
