const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const { query } = require('./db');
const { escapeHtml, isValidEmail, sendEmail } = require('./mail');
const {
  createInvoicePaymentLink,
  ensureInvoicePaymentLinksTable,
} = require('./invoice_payment');

const MODULE_ROOT = path.resolve(__dirname, '../..');

function safeCwd() {
  try {
    const cwd = process.cwd();
    if (cwd && fs.existsSync(cwd)) return cwd;
  } catch (_) {
    // ignored
  }
  return null;
}

function resolveFont(relative) {
  const candidates = [
    process.env.MICROVISE_APP_ROOT,
    MODULE_ROOT,
    safeCwd(),
  ]
    .filter(Boolean)
    .map((root) => path.resolve(String(root), relative));
  return candidates.find((candidate) => {
    try {
      return fs.existsSync(candidate);
    } catch (_) {
      return false;
    }
  });
}

function registerPdfFonts(doc) {
  const sets = [
    {
      regular: 'assets/fonts/noto_sans/NotoSans-Regular.ttf',
      bold: 'assets/fonts/noto_sans/NotoSans-Bold.ttf',
    },
    {
      regular: 'assets/fonts/inter/Inter-Regular.ttf',
      bold: 'assets/fonts/inter/Inter-Bold.ttf',
    },
  ];
  for (const set of sets) {
    const regular = resolveFont(set.regular);
    const bold = resolveFont(set.bold);
    if (regular && bold) {
      doc.registerFont('MailSans', regular);
      doc.registerFont('MailSansBold', bold);
      return { regular: 'MailSans', bold: 'MailSansBold' };
    }
  }
  return { regular: 'Helvetica', bold: 'Helvetica-Bold' };
}

function formatMoney(amount, currency) {
  const value = Number(amount);
  const safe = Number.isFinite(value) ? value : 0;
  const code = String(currency || 'TRY').toUpperCase();
  const formatted = safe.toLocaleString('tr-TR', {
    minimumFractionDigits: 2,
    maximumFractionDigits: 2,
  });
  if (code === 'TRY' || code === 'TL') return `${formatted} ₺`;
  if (code === 'USD') return `$${formatted}`;
  if (code === 'EUR') return `€${formatted}`;
  if (code === 'GBP') return `£${formatted}`;
  return `${formatted} ${code}`;
}

function localInvoiceNumber(value) {
  return String(value || '')
    .trim()
    .replace(/^\d{9}-/, '');
}

function formatDateTr(value) {
  if (!value) return '—';
  const date = new Date(value);
  if (Number.isNaN(date.getTime())) return '—';
  return new Intl.DateTimeFormat('tr-TR', {
    timeZone: 'Asia/Famagusta',
    day: '2-digit',
    month: '2-digit',
    year: 'numeric',
  }).format(date);
}

function remainingAmount(invoice) {
  return Math.max(
    0,
    Number(invoice.grand_total || 0) - Number(invoice.paid_amount || 0),
  );
}

const DEFAULT_SELLER = {
  title: 'Microvise Innovation Ltd',
  address: 'Atatürk Cad. Yenişehir Emek 2 Apt. Dış Kapı No: 1, Lefkoşa',
  website: 'www.microvise.net',
  email: 'info@microvise.net',
  phone: '',
};

function normalizeSeller(row) {
  if (!row || typeof row !== 'object') return { ...DEFAULT_SELLER };
  const website = String(row.seller_website || row.website || '')
    .trim()
    .replace(/^https?:\/\//i, '');
  return {
    title:
      String(row.seller_title || row.title || '').trim() || DEFAULT_SELLER.title,
    address:
      String(row.seller_address_line1 || row.address || '').trim() ||
      DEFAULT_SELLER.address,
    website: website || DEFAULT_SELLER.website,
    email:
      String(row.seller_email || row.email || '').trim() || DEFAULT_SELLER.email,
    phone: String(row.seller_phone || row.phone || '').trim() || DEFAULT_SELLER.phone,
  };
}

async function loadSellerForMail() {
  try {
    const result = await query(`
      select seller_title, seller_address_line1, seller_phone, seller_email, seller_website
      from public.e_invoice_settings
      where is_active = true
      order by created_at asc
      limit 1
    `);
    return normalizeSeller(result.rows[0]);
  } catch (_) {
    return { ...DEFAULT_SELLER };
  }
}

function websiteHref(website) {
  const value = String(website || '').trim();
  if (!value) return 'https://www.microvise.net';
  if (/^https?:\/\//i.test(value)) return value;
  return `https://${value}`;
}

async function loadInvoicesForMail(invoiceIds) {
  const ids = Array.from(
    new Set(
      (invoiceIds || [])
        .map((id) => String(id || '').trim())
        .filter(Boolean),
    ),
  );
  if (!ids.length) {
    const error = new Error('En az bir fatura seçilmelidir.');
    error.statusCode = 400;
    throw error;
  }
  const invoices = await query(
    `
      select
        i.id,
        i.invoice_number,
        i.invoice_type,
        i.customer_id,
        i.invoice_date,
        i.currency,
        i.grand_total,
        coalesce(i.paid_amount, 0) as paid_amount,
        i.status,
        i.e_invoice_pdf_bucket,
        i.e_invoice_pdf_path,
        c.name as customer_name,
        c.email as customer_email
      from public.invoices i
      left join public.customers c on c.id = i.customer_id
      where i.id = any($1::uuid[])
    `,
    [ids],
  );
  if (invoices.rows.length !== ids.length) {
    const error = new Error('Seçilen faturalardan bazıları bulunamadı.');
    error.statusCode = 400;
    throw error;
  }
  const items = await query(
    `
      select
        invoice_id,
        description,
        quantity,
        unit,
        unit_price,
        tax_rate,
        line_total
      from public.invoice_items
      where invoice_id = any($1::uuid[])
      order by sort_order asc, created_at asc
    `,
    [ids],
  );
  const itemsByInvoice = new Map();
  for (const item of items.rows) {
    const list = itemsByInvoice.get(item.invoice_id) || [];
    list.push(item);
    itemsByInvoice.set(item.invoice_id, list);
  }
  return invoices.rows.map((row) => ({
    ...row,
    items: itemsByInvoice.get(row.id) || [],
  }));
}

function officialPdfAttachment(invoice) {
  const objectPath = String(invoice?.e_invoice_pdf_path || '').trim();
  if (!objectPath) return null;
  try {
    if (!fs.existsSync(objectPath) || !fs.statSync(objectPath).isFile()) {
      return null;
    }
    const label = localInvoiceNumber(invoice.invoice_number) || 'efatura';
    return {
      filename: `e-fatura-${label.replace(/[^\w.-]+/g, '_').slice(0, 60)}.pdf`,
      content: fs.readFileSync(objectPath).toString('base64'),
      contentType: 'application/pdf',
    };
  } catch (_) {
    return null;
  }
}

function invoiceNumbersPhrase(invoices) {
  const numbers = (invoices || [])
    .map((row) => localInvoiceNumber(row?.invoice_number))
    .filter(Boolean);
  if (!numbers.length) return '';
  if (numbers.length === 1) return `${numbers[0]} nolu faturanız`;
  if (numbers.length === 2) {
    return `${numbers[0]} ve ${numbers[1]} nolu faturalarınız`;
  }
  const last = numbers[numbers.length - 1];
  return `${numbers.slice(0, -1).join(', ')} ve ${last} nolu faturalarınız`;
}

function invoiceMailCopy({ invoices, awaitingPayment }) {
  const list = Array.isArray(invoices) ? invoices : [];
  const named = invoiceNumbersPhrase(list);
  const many = list.length > 1;
  if (awaitingPayment) {
    return {
      preheader: named
        ? `${named} için ödeme bekleniyor.`
        : 'Faturanız hazır. Güvenli ödeme bağlantısı bu e-postadadır.',
      headerLabel: 'Ödeme bildirimi',
      amountLabel: 'Ödenecek tutar',
      body: named
        ? `${named} için ödeme beklenmektedir. Belge özeti ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz. Ödeme alındıktan sonra resmi faturanız tarafınıza iletilecektir.`
        : 'Fatura bilgileriniz aşağıdadır. Belge özeti ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz. Ödeme alındıktan sonra resmi faturanız tarafınıza iletilecektir.',
      thanks: '',
    };
  }
  return {
    preheader: named
      ? `Ödemeniz için teşekkür ederiz. ${named} ektedir.`
      : 'Ödemeniz için teşekkür ederiz. Faturanız ektedir.',
    headerLabel: 'Ödeme onayı',
    amountLabel: 'Ödenen tutar',
    body: named
      ? `Ödemeniz için teşekkür ederiz. ${named} kesilmiş olup ${
          many ? 'belgeler' : 'belgesi'
        } bu e-postanın ekinde yer almaktadır.`
      : 'Ödemeniz için teşekkür ederiz. Faturanız kesilmiş olup belgesi bu e-postanın ekinde yer almaktadır.',
    thanks: 'Ödemeniz alınmıştır. İyi çalışmalar dileriz.',
  };
}

function buildPaymentEmailHtml({
  customerName,
  invoices,
  amount,
  currency,
  paymentUrl,
  seller,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment });
  const company = normalizeSeller(seller);
  const greeting = escapeHtml(customerName || 'Yetkili');
  const total = escapeHtml(formatMoney(amount, currency));
  const safeUrl = escapeHtml(paymentUrl || '');
  const invoiceCount = invoices.length;
  const rows = invoices
    .map((invoice, index) => {
      const remaining = remainingAmount(invoice) || Number(invoice.grand_total || 0);
      const bg = index % 2 === 0 ? '#ffffff' : '#f8fafc';
      return `
        <tr>
          <td style="padding:12px 14px;border-bottom:1px solid #e8edf3;background:${bg};font-size:14px;color:#1e293b;">
            ${escapeHtml(localInvoiceNumber(invoice.invoice_number) || 'Fatura')}
          </td>
          <td style="padding:12px 14px;border-bottom:1px solid #e8edf3;background:${bg};font-size:13px;color:#64748b;white-space:nowrap;">
            ${escapeHtml(formatDateTr(invoice.invoice_date))}
          </td>
          <td style="padding:12px 14px;border-bottom:1px solid #e8edf3;background:${bg};font-size:14px;color:#0f172a;text-align:right;font-weight:600;white-space:nowrap;">
            ${escapeHtml(formatMoney(remaining, invoice.currency || currency))}
          </td>
        </tr>`;
    })
    .join('');
  const itemPreview =
    invoiceCount === 1
      ? (invoices[0].items || [])
          .slice(0, 6)
          .map((item) => {
            const desc = String(item.description || 'Kalem').trim();
            const qty = Number(item.quantity || 1);
            return `
              <tr>
                <td style="padding:8px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#334155;">
                  ${escapeHtml(desc)}
                </td>
                <td style="padding:8px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#64748b;text-align:right;white-space:nowrap;">
                  ${escapeHtml(String(qty))} ${escapeHtml(item.unit || 'Adet')}
                </td>
              </tr>`;
          })
          .join('')
      : '';
  const footerBits = [
    escapeHtml(company.title),
    company.address ? escapeHtml(company.address) : '',
    company.phone ? escapeHtml(company.phone) : '',
    company.email
      ? `<a href="mailto:${escapeHtml(company.email)}" style="color:#64748b;text-decoration:none;">${escapeHtml(company.email)}</a>`
      : '',
    company.website
      ? `<a href="${escapeHtml(websiteHref(company.website))}" style="color:#1d4ed8;text-decoration:none;">${escapeHtml(company.website)}</a>`
      : '',
  ].filter(Boolean);

  return `<!DOCTYPE html>
<html lang="tr">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <meta name="color-scheme" content="light" />
  <title>Fatura bildirimi</title>
</head>
<body style="margin:0;padding:0;background:#eef2f7;">
  <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
    ${escapeHtml(copy.preheader)}
  </div>
  <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="background:#eef2f7;">
    <tr>
      <td align="center" style="padding:28px 16px;">
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="600" style="width:600px;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #dbe4f0;">
          <tr>
            <td style="background:#1e3a5f;padding:22px 32px;">
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                <tr>
                  <td>
                    <div style="font-family:Georgia,'Times New Roman',serif;font-size:22px;letter-spacing:0.08em;color:#ffffff;font-weight:700;">
                      MICROVISE
                    </div>
                    <div style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#bfdbfe;letter-spacing:0.04em;padding-top:4px;">
                      ${escapeHtml(company.title)}
                    </div>
                  </td>
                  <td align="right" style="font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#dbeafe;line-height:1.45;">
                    ${escapeHtml(copy.headerLabel)}<br />
                    ${escapeHtml(formatDateTr(new Date()))}
                  </td>
                </tr>
              </table>
            </td>
          </tr>
          <tr>
            <td style="height:4px;background:#2563eb;font-size:0;line-height:0;">&nbsp;</td>
          </tr>
          <tr>
            <td style="padding:32px 32px 8px 32px;font-family:Arial,Helvetica,sans-serif;color:#0f172a;">
              <p style="margin:0 0 6px 0;font-size:13px;color:#64748b;letter-spacing:0.04em;text-transform:uppercase;">
                Sayın
              </p>
              <p style="margin:0 0 18px 0;font-size:20px;font-weight:700;color:#0f172a;line-height:1.3;">
                ${greeting}
              </p>
              <p style="margin:0 0 22px 0;font-size:15px;line-height:1.65;color:#334155;">
                ${escapeHtml(copy.body)}
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border:1px solid #e8edf3;border-radius:12px;overflow:hidden;">
                <tr>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;">
                    Fatura no
                  </td>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;">
                    Tarih
                  </td>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;text-align:right;">
                    Tutar
                  </td>
                </tr>
                ${rows}
              </table>
              ${
                itemPreview
                  ? `
              <p style="margin:18px 0 8px 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;">
                Kalem özeti
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border:1px solid #e8edf3;border-radius:12px;overflow:hidden;">
                ${itemPreview}
              </table>`
                  : ''
              }
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:20px 0 0 0;">
                <tr>
                  <td style="background:#f8fafc;border:1px solid #e8edf3;border-radius:12px;padding:16px 18px;">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%">
                      <tr>
                        <td style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#64748b;">
                          ${escapeHtml(copy.amountLabel)}
                        </td>
                        <td align="right" style="font-family:Arial,Helvetica,sans-serif;font-size:22px;font-weight:700;color:#1e3a5f;">
                          ${total}
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              ${
                awaitingPayment
                  ? `
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:24px 0 8px 0;">
                <tr>
                  <td align="center">
                    <table role="presentation" cellpadding="0" cellspacing="0" border="0">
                      <tr>
                        <td align="center" bgcolor="#1d4ed8" style="border-radius:10px;">
                          <a href="${safeUrl}"
                             style="display:inline-block;padding:14px 32px;font-family:Arial,Helvetica,sans-serif;font-size:15px;font-weight:700;color:#ffffff;text-decoration:none;letter-spacing:0.02em;">
                            Güvenli ödeme yap
                          </a>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
              </table>
              <p style="margin:14px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.55;color:#64748b;text-align:center;">
                Ödeme 3D Secure ile banka altyapısı üzerinden alınır.<br />
                Kart bilgileriniz Microvise sistemlerinde saklanmaz.
              </p>
              <p style="margin:16px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;line-height:1.5;color:#94a3b8;text-align:center;word-break:break-all;">
                Buton çalışmazsa bu bağlantıyı tarayıcınıza yapıştırın:<br />
                <a href="${safeUrl}" style="color:#1d4ed8;text-decoration:none;">${safeUrl}</a>
              </p>`
                  : `
              <p style="margin:18px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:14px;line-height:1.65;color:#166534;text-align:center;font-weight:600;">
                ${escapeHtml(copy.thanks)}
              </p>`
              }
            </td>
          </tr>
          <tr>
            <td style="padding:8px 32px 28px 32px;">
              <div style="height:1px;background:#e8edf3;line-height:1px;font-size:0;">&nbsp;</div>
              <p style="margin:18px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:12px;line-height:1.7;color:#64748b;text-align:center;">
                ${footerBits.join('<br />')}
              </p>
              <p style="margin:12px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;color:#94a3b8;text-align:center;line-height:1.55;">
                Bu e-posta ${escapeHtml(company.title)} tarafından resmi fatura bildirimi amacıyla gönderilmiştir.
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

function buildPaymentEmailText({
  customerName,
  invoices,
  amount,
  currency,
  paymentUrl,
  seller,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment });
  const company = normalizeSeller(seller);
  const lines = [
    `Sayın ${customerName || 'Yetkili'},`,
    '',
    copy.body,
    '',
    ...invoices.map((invoice) => {
      const remaining = remainingAmount(invoice) || Number(invoice.grand_total || 0);
      return `${localInvoiceNumber(invoice.invoice_number) || 'Fatura'}  ${formatDateTr(invoice.invoice_date)}  ${formatMoney(remaining, invoice.currency || currency)}`;
    }),
    '',
    `${copy.amountLabel}: ${formatMoney(amount, currency)}`,
    '',
    ...(awaitingPayment
      ? [
          'Güvenli ödeme:',
          paymentUrl,
          '',
          'Ödeme 3D Secure ile banka altyapısı üzerinden alınır. Kart bilgileriniz Microvise sistemlerinde saklanmaz.',
        ]
      : [copy.thanks]),
    '',
    company.title,
    company.address,
    company.phone,
    company.email,
    company.website,
  ].filter((line) => line !== undefined && line !== '');
  return lines.join('\n');
}

async function buildInvoicePaymentPdf({
  customerName,
  invoices,
  amount,
  currency,
  paymentUrl,
  seller,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment });
  const company = normalizeSeller(seller);
  let qrPng = null;
  if (awaitingPayment) {
    try {
      qrPng = await QRCode.toBuffer(paymentUrl, {
        type: 'png',
        margin: 1,
        width: 160,
        errorCorrectionLevel: 'M',
      });
    } catch (_) {
      qrPng = null;
    }
  }

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: 'A4',
      margin: 48,
      info: {
        Title: copy.headerLabel,
        Author: company.title,
      },
    });
    const chunks = [];
    doc.on('data', (chunk) => chunks.push(chunk));
    doc.on('end', () => resolve(Buffer.concat(chunks)));
    doc.on('error', reject);

    const fonts = registerPdfFonts(doc);
    const pageWidth = doc.page.width;
    const left = 48;
    const right = pageWidth - 48;
    const width = right - left;

    doc.save();
    doc.rect(0, 0, pageWidth, 78).fill('#1e3a5f');
    doc.rect(0, 78, pageWidth, 4).fill('#2563eb');
    doc
      .fillColor('#ffffff')
      .font(fonts.bold)
      .fontSize(18)
      .text('MICROVISE', left, 20);
    doc
      .fillColor('#bfdbfe')
      .font(fonts.regular)
      .fontSize(9)
      .text(company.title, left, 46, { width: width * 0.62 });
    doc
      .fillColor('#dbeafe')
      .font(fonts.regular)
      .fontSize(9)
      .text(copy.headerLabel, left + width * 0.62, 24, {
        width: width * 0.38,
        align: 'right',
      });
    doc
      .fillColor('#bfdbfe')
      .font(fonts.regular)
      .fontSize(9)
      .text(formatDateTr(new Date()), left + width * 0.62, 40, {
        width: width * 0.38,
        align: 'right',
      });
    doc.restore();

    doc.y = 104;
    doc
      .fillColor('#64748b')
      .font(fonts.regular)
      .fontSize(9)
      .text('SAYIN', left, doc.y);
    doc.moveDown(0.25);
    doc
      .fillColor('#0f172a')
      .font(fonts.bold)
      .fontSize(16)
      .text(customerName || 'Yetkili', left, doc.y, { width });
    doc.moveDown(0.55);
    doc
      .fillColor('#334155')
      .font(fonts.regular)
      .fontSize(10.5)
      .text(copy.body, left, doc.y, { width, lineGap: 2 });
    doc.moveDown(0.9);

    const colNo = left;
    const colDate = left + width * 0.42;
    const colAmt = right;
    const headerY = doc.y;
    doc.save();
    doc.rect(left, headerY, width, 22).fill('#f1f5f9');
    doc.restore();
    doc
      .fillColor('#64748b')
      .font(fonts.bold)
      .fontSize(8)
      .text('FATURA NO', colNo + 8, headerY + 7, { width: width * 0.38 });
    doc.text('TARİH', colDate, headerY + 7, { width: 90 });
    doc.text('TUTAR', colAmt - 90, headerY + 7, { width: 82, align: 'right' });
    doc.y = headerY + 26;

    for (const invoice of invoices) {
      const remaining =
        remainingAmount(invoice) || Number(invoice.grand_total || 0);
      const rowY = doc.y;
      doc
        .strokeColor('#e8edf3')
        .lineWidth(0.6)
        .moveTo(left, rowY + 18)
        .lineTo(right, rowY + 18)
        .stroke();
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(10)
        .text(localInvoiceNumber(invoice.invoice_number) || 'Fatura', colNo + 8, rowY, {
          width: width * 0.38,
        });
      doc
        .fillColor('#64748b')
        .font(fonts.regular)
        .fontSize(10)
        .text(formatDateTr(invoice.invoice_date), colDate, rowY, { width: 90 });
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(10)
        .text(
          formatMoney(remaining, invoice.currency || currency),
          colAmt - 110,
          rowY,
          { width: 102, align: 'right' },
        );
      doc.y = rowY + 24;

      for (const item of (invoice.items || []).slice(0, 10)) {
        const qty = Number(item.quantity || 1);
        const desc = String(item.description || 'Kalem').trim();
        doc
          .fillColor('#64748b')
          .font(fonts.regular)
          .fontSize(8.5)
          .text(
            `${desc}   ${qty} ${item.unit || 'Adet'}   ${formatMoney(
              item.line_total,
              invoice.currency || currency,
            )}`,
            left + 12,
            doc.y,
            { width: width - 12 },
          );
        doc.moveDown(0.15);
      }
      doc.moveDown(0.25);
    }

    doc.moveDown(0.4);
    const totalY = doc.y;
    doc.save();
    doc.roundedRect(left, totalY, width, 36, 6).fill('#f8fafc');
    doc.restore();
    doc
      .fillColor('#64748b')
      .font(fonts.regular)
      .fontSize(10)
      .text(copy.amountLabel, left + 14, totalY + 12);
    doc
      .fillColor('#1e3a5f')
      .font(fonts.bold)
      .fontSize(14)
      .text(formatMoney(amount, currency), left + width * 0.45, totalY + 10, {
        width: width * 0.55 - 14,
        align: 'right',
      });
    doc.y = totalY + 50;

    if (awaitingPayment) {
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(11)
        .text('Güvenli ödeme', left, doc.y);
      doc.moveDown(0.25);
      doc
        .fillColor('#334155')
        .font(fonts.regular)
        .fontSize(9.5)
        .text(
          'Ödeme 3D Secure ile banka altyapısı üzerinden alınır. Kart bilgileriniz Microvise sistemlerinde saklanmaz.',
          left,
          doc.y,
          { width: qrPng ? width - 130 : width, lineGap: 2 },
        );
      const linkY = doc.y + 8;
      doc
        .fillColor('#1d4ed8')
        .font(fonts.regular)
        .fontSize(9)
        .text(paymentUrl, left, linkY, {
          width: qrPng ? width - 130 : width,
          link: paymentUrl,
          underline: true,
        });
      if (qrPng) {
        doc.image(qrPng, right - 108, totalY + 50, { width: 108 });
      }
    } else {
      doc
        .fillColor('#166534')
        .font(fonts.bold)
        .fontSize(11)
        .text(copy.thanks, left, doc.y, { width });
    }

    const footerY = 790;
    doc
      .strokeColor('#e8edf3')
      .lineWidth(0.8)
      .moveTo(left, footerY)
      .lineTo(right, footerY)
      .stroke();
    doc
      .fillColor('#64748b')
      .font(fonts.regular)
      .fontSize(8)
      .text(
        [company.title, company.address, company.phone, company.email, company.website]
          .filter(Boolean)
          .join('  ·  '),
        left,
        footerY + 8,
        { width, align: 'center' },
      );

    doc.end();
  });
}

async function markPaymentLinkEmailed({ linkId, emailedTo }) {
  await ensureInvoicePaymentLinksTable();
  await query(
    `
      update public.invoice_payment_links
      set emailed_at = now(),
          emailed_to = $2,
          updated_at = now()
      where id = $1::uuid
    `,
    [linkId, emailedTo],
  );
}

async function sendInvoicePaymentLinkEmail({
  invoiceIds,
  email,
  createdBy,
  req,
}) {
  const invoices = await loadInvoicesForMail(invoiceIds);
  const customerIds = new Set(invoices.map((row) => String(row.customer_id)));
  if (customerIds.size !== 1) {
    const error = new Error('Mail aynı cariye ait faturalar için gönderilebilir.');
    error.statusCode = 400;
    throw error;
  }
  const customerName = invoices[0].customer_name || 'Cari';
  const to = String(email || invoices[0].customer_email || '').trim();
  if (!isValidEmail(to)) {
    const error = new Error(
      'Müşteri e-postası yok. Göndermeden önce e-posta yazın.',
    );
    error.statusCode = 400;
    throw error;
  }

  const totalRemaining = invoices.reduce(
    (sum, invoice) => sum + remainingAmount(invoice),
    0,
  );
  const totalGrand = invoices.reduce(
    (sum, invoice) => sum + Number(invoice.grand_total || 0),
    0,
  );
  const awaitingPayment = totalRemaining > 0.009;
  let paymentUrl = '';
  let amount = awaitingPayment ? totalRemaining : totalGrand;
  let currency = invoices[0].currency || 'TRY';
  let link = null;

  if (awaitingPayment) {
    link = await createInvoicePaymentLink({
      invoiceIds: invoices.map((row) => row.id),
      createdBy,
      req,
    });
    paymentUrl = link.paymentUrl;
    amount = link.amount;
    currency = link.currency;
  }

  const seller = await loadSellerForMail();
  const pdf = await buildInvoicePaymentPdf({
    customerName,
    invoices,
    amount,
    currency,
    paymentUrl,
    seller,
  });
  const invoiceLabel = invoices
    .map((row) => localInvoiceNumber(row.invoice_number))
    .filter(Boolean)
    .join(', ');
  const mailPayload = {
    customerName,
    invoices,
    amount,
    currency,
    paymentUrl,
    seller,
  };
  const named = invoiceNumbersPhrase(invoices);
  const crmAttachment = {
    filename: `fatura-${(invoiceLabel || 'microvise')
      .replace(/[^\w.-]+/g, '_')
      .slice(0, 60)}.pdf`,
    content: pdf.toString('base64'),
    contentType: 'application/pdf',
  };
  const officialAttachments = awaitingPayment
    ? []
    : invoices.map(officialPdfAttachment).filter(Boolean);
  const attachments = officialAttachments.length
    ? officialAttachments
    : [crmAttachment];

  await sendEmail({
    to,
    subject: awaitingPayment
      ? named
        ? `${named} için ödeme`
        : 'Fatura bildirimi · Microvise Innovation'
      : named
        ? `Ödemeniz için teşekkürler · ${invoiceLabel}`
        : 'Ödemeniz için teşekkürler',
    html: buildPaymentEmailHtml(mailPayload),
    text: buildPaymentEmailText(mailPayload),
    attachments,
  });

  if (link) {
    await markPaymentLinkEmailed({
      linkId: link.id,
      emailedTo: to,
    });
  }

  return {
    ok: true,
    paymentUrl: paymentUrl || null,
    amount,
    currency,
    invoiceCount: invoices.length,
    emailedTo: to,
    customerName,
    status: awaitingPayment ? 'pending' : 'paid',
    statusLabel: awaitingPayment
      ? 'Link gönderildi · ödeme bekliyor'
      : 'Ödeme teşekkür maili gönderildi',
    message: awaitingPayment
      ? `Fatura ve ödeme linki ${to} adresine gönderildi.`
      : `Ödemeniz için teşekkür maili ${to} adresine gönderildi.`,
  };
}

module.exports = {
  sendInvoicePaymentLinkEmail,
  loadInvoicesForMail,
  markPaymentLinkEmailed,
  formatMoney,
  localInvoiceNumber,
  formatDateTr,
  invoiceNumbersPhrase,
  invoiceMailCopy,
  buildPaymentEmailHtml,
  buildPaymentEmailText,
  normalizeSeller,
  buildInvoicePaymentPdf,
};
