const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

function text(value, fallback = '-') {
  const normalized = String(value ?? '').trim();
  return normalized || fallback;
}

function money(value, currency) {
  const amount = Number(value || 0).toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  return `${amount} ${currency === 'TRY' ? 'TL' : text(currency, '')}`.trim();
}

function drawParty(doc, title, party, x, y, width) {
  doc.roundedRect(x, y, width, 104, 4).stroke('#d9e1e8');
  doc.font('NotoSans').fontSize(9).fillColor('#111827').text(title, x + 9, y + 8);
  doc
    .fontSize(7.4)
    .fillColor('#374151')
    .text(text(party?.unvan || party?.name), x + 9, y + 25, {
      width: width - 18,
      height: 24,
    })
    .text(text(party?.adres || party?.address), x + 9, y + 50, {
      width: width - 18,
      height: 27,
    })
    .text(
      `VKN/Belge No: ${text(party?.vkn || party?.belgeNo || party?.tax_number)}`,
      x + 9,
      y + 82,
      { width: width - 18 },
    );
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
      Subject: 'Maliye e-Fatura arşiv kopyası',
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
    doc.font('NotoSans');
  } else {
    doc.font('Helvetica');
  }

  const officialInvoice =
    officialData?.fatura || officialData?.invoice || officialData || {};
  const payloadInvoice = invoice.e_invoice_payload?.faturalar?.[0] || {};
  const source = { ...payloadInvoice, ...officialInvoice };
  const supplier = source.tedarikci || {
    unvan: settings.seller_title,
    adres: settings.seller_address_line1,
    vkn: settings.seller_vkn,
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
          vergiler: [{ vergiOrani: item.tax_rate }],
        }))
      : []);
  const officialUrl = `https://${
    environment === 'production'
      ? 'efatura.maliye.gov.ct.tr'
      : 'test-efatura.maliye.gov.ct.tr'
  }/dogrula/?code=${encodeURIComponent(verificationCode)}`;
  const qr = await QRCode.toDataURL(officialUrl, { margin: 0, width: 180 });

  doc.image(qr, 34, 31, { width: 64 });
  doc.fontSize(13).fillColor('#111827').text('K.K.T.C. Maliye Bakanlığı', 110, 34);
  doc.fontSize(18).fillColor('#dc2626').text('e-FATURA', 110, 53);
  doc
    .fontSize(8)
    .fillColor('#4b5563')
    .text(
      `Fatura No: ${text(source.faturaNo || invoice.e_invoice_number || invoice.invoice_number)}`,
      110,
      80,
    )
    .text(`Doğrulama Kodu: ${verificationCode}`, 110, 93);

  drawParty(doc, 'Tedarikçi Bilgileri', supplier, 34, 122, 252);
  drawParty(doc, 'Müşteri Bilgileri', customer, 309, 122, 252);

  doc
    .fontSize(8)
    .fillColor('#111827')
    .text(`Fatura Tarihi: ${text(source.faturaTarihi || invoice.invoice_date)}`, 34, 241)
    .text(`Para Birimi: ${text(source.paraBirimi || invoice.currency)}`, 309, 241);

  const columns = [34, 235, 295, 355, 427, 487, 561];
  let y = 270;
  doc.rect(34, y, 527, 22).fill('#eef2f7');
  const headers = ['Mal/Hizmet', 'Miktar', 'Birim', 'Fiyat', 'KDV', 'Toplam'];
  headers.forEach((header, index) => {
    doc
      .fontSize(7)
      .fillColor('#111827')
      .text(header, columns[index] + 4, y + 7, {
        width: columns[index + 1] - columns[index] - 8,
        align: index === 0 ? 'left' : 'right',
      });
  });
  y += 22;

  const maxRows = 12;
  items.slice(0, maxRows).forEach((item) => {
    const qty = Number(item.birimMiktari ?? item.quantity ?? 0);
    const price = Number(item.fiyat ?? item.unit_price ?? 0);
    const total = qty * price;
    const values = [
      text(item.adi || item.description),
      qty.toLocaleString('tr-TR'),
      text(item.birimTurKod || item.unit),
      money(price, source.paraBirimi || invoice.currency),
      `%${Number(item.vergiler?.[0]?.vergiOrani ?? item.tax_rate ?? 0)}`,
      money(total, source.paraBirimi || invoice.currency),
    ];
    doc.rect(34, y, 527, 25).stroke('#e5e7eb');
    values.forEach((value, index) => {
      doc
        .fontSize(6.7)
        .fillColor('#374151')
        .text(value, columns[index] + 4, y + 7, {
          width: columns[index + 1] - columns[index] - 8,
          height: 14,
          ellipsis: true,
          align: index === 0 ? 'left' : 'right',
        });
    });
    y += 25;
  });
  if (items.length > maxRows) {
    doc
      .fontSize(7)
      .fillColor('#6b7280')
      .text(`+ ${items.length - maxRows} kalem UBL/XML arşivinde kayıtlıdır.`, 34, y + 5);
    y += 20;
  }

  const currency = source.paraBirimi || invoice.currency;
  const totals = [
    ['Ara Toplam', source.faturaToplami ?? invoice.subtotal],
    ['İndirim', source.iskontoToplami ?? invoice.discount_total],
    ['KDV', source.kdvToplami ?? invoice.tax_total],
    ['Genel Toplam', source.odenecekToplam ?? invoice.grand_total],
  ];
  y = Math.max(y + 12, 620);
  totals.forEach(([label, value], index) => {
    doc
      .fontSize(index === totals.length - 1 ? 9 : 7.5)
      .fillColor('#111827')
      .text(label, 360, y, { width: 90, align: 'right' })
      .text(money(value, currency), 465, y, { width: 96, align: 'right' });
    y += 19;
  });

  const description = text(source.aciklama, '');
  if (description) {
    doc
      .fontSize(6.8)
      .fillColor('#4b5563')
      .text(`Açıklama: ${description.replace(/\s*[\r\n]+\s*/g, ' · ')}`, 34, 712, {
        width: 527,
        height: 28,
        ellipsis: true,
      });
  }
  doc
    .fontSize(6.3)
    .fillColor('#6b7280')
    .text(
      'Bu PDF, Maliye API’sinden arşivlenen resmî fatura verisi ve UBL/XML kaydı esas alınarak oluşturulmuştur. Doğrulama için QR kodu kullanınız.',
      34,
      766,
      { width: 527, align: 'center' },
    );

  doc.end();
  return completed;
}

module.exports = { buildEInvoiceArchivePdf };
