const fs = require('fs');
const path = require('path');

const PDFDocument = require('pdfkit');
const QRCode = require('qrcode');

const { query } = require('./db');
const { escapeHtml, isValidEmail, sendEmail } = require('./mail');
const { ensureCustomerEmailColumns } = require('./schema');
const {
  createInvoicePaymentLink,
  ensureInvoicePaymentLinksTable,
  uniqueLinkIds,
  buildHostedPaymentUrl,
} = require('./invoice_payment');
const { posPaymentOverdue } = require('./pos_status');

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

const DEFAULT_BANK_TRANSFER = {
  intro:
    'İsterseniz Türkiye İş Bankası hesabımıza havale veya EFT ile de ödeme yapabilirsiniz.',
  bank: 'Türkiye İş Bankası',
  accountName: 'Microvise Innovation Ltd',
  ibanTl: 'TR57 0006 4000 0016 8010 3409 94',
  ibanUsd: 'TR41 0006 4000 0026 8010 4107 29',
  note: 'Havale açıklamasına fatura numaranızı yazın.',
};

function numberOrZero(value) {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : 0;
}

function invoiceVatParts(invoice) {
  let subtotal = numberOrZero(invoice?.subtotal);
  let tax = numberOrZero(invoice?.tax_total);
  const total = numberOrZero(invoice?.grand_total);
  if (subtotal <= 0 && Array.isArray(invoice?.items) && invoice.items.length) {
    subtotal = invoice.items.reduce((sum, item) => {
      return sum + numberOrZero(item.unit_price) * numberOrZero(item.quantity || 1);
    }, 0);
    tax = invoice.items.reduce((sum, item) => {
      const net = numberOrZero(item.unit_price) * numberOrZero(item.quantity || 1);
      const line = numberOrZero(item.line_total);
      const fromLine = line > net + 0.009 ? line - net : 0;
      const fromRate = net * (numberOrZero(item.tax_rate) / 100);
      return sum + (fromLine || fromRate);
    }, 0);
  }
  if (subtotal <= 0 && total > 0 && tax > 0) subtotal = Math.max(0, total - tax);
  if (subtotal <= 0 && total > 0) subtotal = total;
  if (tax <= 0 && total > subtotal + 0.009) tax = total - subtotal;
  return {
    subtotal,
    tax,
    total: total || subtotal + tax,
  };
}

function combinedVatParts(invoices) {
  const list = Array.isArray(invoices) ? invoices : [];
  return list.reduce(
    (acc, invoice) => {
      const parts = invoiceVatParts(invoice);
      acc.subtotal += parts.subtotal;
      acc.tax += parts.tax;
      acc.total += parts.total;
      return acc;
    },
    { subtotal: 0, tax: 0, total: 0 },
  );
}

function bankTransferLines() {
  const bank = DEFAULT_BANK_TRANSFER;
  return [
    bank.intro,
    bank.accountName,
    bank.bank,
    `TL IBAN: ${bank.ibanTl}`,
    `USD IBAN: ${bank.ibanUsd}`,
    bank.note,
  ];
}

function bankTransferPdfLines() {
  const bank = DEFAULT_BANK_TRANSFER;
  return [
    `${bank.accountName}  ·  ${bank.bank}`,
    `TL  ${bank.ibanTl}`,
    `USD  ${bank.ibanUsd}`,
    bank.note,
  ];
}

function wrapUnbroken(text, chunk = 36) {
  return String(text || '').replace(new RegExp(`(\\S{${chunk}})`, 'g'), '$1\u200b');
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
  await ensureCustomerEmailColumns();
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
        i.subtotal,
        i.tax_total,
        i.grand_total,
        coalesce(i.paid_amount, 0) as paid_amount,
        i.status,
        i.e_invoice_pdf_bucket,
        i.e_invoice_pdf_path,
        c.name as customer_name,
        c.email as customer_email,
        c.email_2 as customer_email_2,
        c.email_3 as customer_email_3
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

function paymentPurposeTitles(invoices) {
  const seen = new Set();
  const titles = [];
  for (const invoice of invoices || []) {
    for (const item of invoice.items || []) {
      const desc = String(item.description || '').trim();
      if (!desc) continue;
      const key = desc.toLocaleLowerCase('tr-TR');
      if (seen.has(key)) continue;
      seen.add(key);
      titles.push(desc);
    }
  }
  return titles;
}

function paymentPurposeSentence(invoices) {
  const titles = paymentPurposeTitles(invoices);
  if (!titles.length) return '';
  if (titles.length === 1) return `Bu ödeme: ${titles[0]}.`;
  return `Bu ödeme:\n${titles.map((title) => `• ${title}`).join('\n')}`;
}

function invoiceMailCopy({ invoices, awaitingPayment, isReminder = false }) {
  const list = Array.isArray(invoices) ? invoices : [];
  const named = invoiceNumbersPhrase(list);
  const many = list.length > 1;
  const purpose = paymentPurposeSentence(list);
  const withPurpose = (text) => (purpose ? `${text}\n\n${purpose}` : text);
  if (isReminder && awaitingPayment) {
    return {
      preheader: named
        ? `${named} için ödeme hatırlatması.`
        : 'Faturanız için ödeme hatırlatması.',
      headerLabel: 'Ödeme hatırlatması',
      amountLabel: 'Ödenecek tutar',
      body: withPurpose(
        named
          ? `${named} için 1 haftadır ödeme beklenmektedir. Belge özeti yeniden ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz. Ödeme alındıktan sonra resmi faturanız tarafınıza iletilecektir.`
          : 'Faturanız için 1 haftadır ödeme beklenmektedir. Belge özeti yeniden ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz.',
      ),
      thanks: '',
    };
  }
  if (awaitingPayment) {
    return {
      preheader: named
        ? `${named} için ödeme bekleniyor.`
        : 'Faturanız hazır. Güvenli ödeme bağlantısı bu e-postadadır.',
      headerLabel: 'Ödeme bildirimi',
      amountLabel: 'Ödenecek tutar',
      body: withPurpose(
        named
          ? `${named} için ödeme beklenmektedir. Belge özeti ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz. Ödeme alındıktan sonra resmi faturanız tarafınıza iletilecektir.`
          : 'Fatura bilgileriniz aşağıdadır. Belge özeti ektedir. Tahsilatı aşağıdaki güvenli bağlantı üzerinden tamamlayabilirsiniz. Ödeme alındıktan sonra resmi faturanız tarafınıza iletilecektir.',
      ),
      thanks: '',
    };
  }
  return {
    preheader: named
      ? `Ödemeniz için teşekkür ederiz. ${named} ektedir.`
      : 'Ödemeniz için teşekkür ederiz. Faturanız ektedir.',
    headerLabel: 'Ödeme onayı',
    amountLabel: 'Ödenen tutar',
    body: withPurpose(
      named
        ? `Ödemeniz için teşekkür ederiz. ${named} kesilmiş olup ${
            many ? 'belgeler' : 'belgesi'
          } bu e-postanın ekinde yer almaktadır.`
        : 'Ödemeniz için teşekkür ederiz. Faturanız kesilmiş olup belgesi bu e-postanın ekinde yer almaktadır.',
    ),
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
  isReminder = false,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment, isReminder });
  const company = normalizeSeller(seller);
  const greeting = escapeHtml(customerName || 'Yetkili');
  const vat = combinedVatParts(invoices);
  const payAmount = numberOrZero(amount) || vat.total;
  const total = escapeHtml(formatMoney(payAmount, currency));
  const subtotalText = escapeHtml(formatMoney(vat.subtotal, currency));
  const taxText = escapeHtml(formatMoney(vat.tax, currency));
  const safeUrl = escapeHtml(paymentUrl || '');
  const invoiceCount = invoices.length;
  const rows = invoices
    .map((invoice, index) => {
      const remaining = remainingAmount(invoice) || Number(invoice.grand_total || 0);
      const bg = index % 2 === 0 ? '#ffffff' : '#f8fafc';
      return `
        <tr>
          <td style="padding:12px 14px;border-bottom:1px solid #e8edf3;background:${bg};font-size:14px;color:#1e293b;word-break:break-word;overflow-wrap:anywhere;">
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
  const itemPreview = invoices
    .flatMap((invoice) => invoice.items || [])
    .slice(0, 12)
    .map((item) => {
      const desc = String(item.description || 'Kalem').trim();
      const qty = Number(item.quantity || 1);
      return `
              <tr>
                <td style="padding:8px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#334155;word-break:break-word;overflow-wrap:anywhere;">
                  ${escapeHtml(desc)}
                </td>
                <td style="padding:8px 14px;border-bottom:1px solid #f1f5f9;font-size:13px;color:#64748b;text-align:right;white-space:nowrap;width:88px;">
                  ${escapeHtml(String(qty))} ${escapeHtml(item.unit || 'Adet')}
                </td>
              </tr>`;
    })
    .join('');
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
        <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="width:100%;max-width:600px;background:#ffffff;border-radius:16px;overflow:hidden;border:1px solid #dbe4f0;">
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
                ${escapeHtml(copy.body).replace(/\n/g, '<br />')}
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="border:1px solid #e8edf3;border-radius:12px;overflow:hidden;table-layout:fixed;">
                <tr>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;width:46%;">
                    Fatura no
                  </td>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;width:24%;">
                    Tarih
                  </td>
                  <td style="padding:10px 14px;background:#f1f5f9;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;text-align:right;width:30%;">
                    Tutar
                  </td>
                </tr>
                ${rows}
              </table>
              ${
                itemPreview
                  ? `
              <p style="margin:18px 0 8px 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;">
                Ödeme kalemleri
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
                        <td style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#64748b;padding:0 0 8px 0;">
                          KDV hariç tutar
                        </td>
                        <td align="right" style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#0f172a;padding:0 0 8px 0;white-space:nowrap;">
                          ${subtotalText}
                        </td>
                      </tr>
                      <tr>
                        <td style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#64748b;padding:0 0 10px 0;">
                          KDV
                        </td>
                        <td align="right" style="font-family:Arial,Helvetica,sans-serif;font-size:14px;color:#0f172a;padding:0 0 10px 0;white-space:nowrap;">
                          ${taxText}
                        </td>
                      </tr>
                      <tr>
                        <td style="font-family:Arial,Helvetica,sans-serif;font-size:13px;color:#64748b;border-top:1px solid #e2e8f0;padding-top:10px;">
                          ${escapeHtml(copy.amountLabel)}
                        </td>
                        <td align="right" style="font-family:Arial,Helvetica,sans-serif;font-size:22px;font-weight:700;color:#1e3a5f;border-top:1px solid #e2e8f0;padding-top:8px;white-space:nowrap;">
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
              </p>
              <table role="presentation" cellpadding="0" cellspacing="0" border="0" width="100%" style="margin:20px 0 0 0;">
                <tr>
                  <td style="background:#f8fafc;border:1px solid #e8edf3;border-radius:12px;padding:16px 18px;">
                    <p style="margin:0 0 8px 0;font-family:Arial,Helvetica,sans-serif;font-size:11px;font-weight:700;letter-spacing:0.06em;text-transform:uppercase;color:#64748b;">
                      Havale / EFT
                    </p>
                    <p style="margin:0 0 10px 0;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.55;color:#334155;">
                      ${escapeHtml(DEFAULT_BANK_TRANSFER.intro)}
                    </p>
                    <p style="margin:0;font-family:Arial,Helvetica,sans-serif;font-size:13px;line-height:1.7;color:#0f172a;word-break:break-word;overflow-wrap:anywhere;">
                      ${escapeHtml(DEFAULT_BANK_TRANSFER.accountName)}<br />
                      ${escapeHtml(DEFAULT_BANK_TRANSFER.bank)}<br />
                      TL IBAN: ${escapeHtml(DEFAULT_BANK_TRANSFER.ibanTl)}<br />
                      USD IBAN: ${escapeHtml(DEFAULT_BANK_TRANSFER.ibanUsd)}
                    </p>
                    <p style="margin:10px 0 0 0;font-family:Arial,Helvetica,sans-serif;font-size:12px;color:#64748b;">
                      ${escapeHtml(DEFAULT_BANK_TRANSFER.note)}
                    </p>
                  </td>
                </tr>
              </table>`
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
  isReminder = false,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment, isReminder });
  const company = normalizeSeller(seller);
  const vat = combinedVatParts(invoices);
  const payAmount = numberOrZero(amount) || vat.total;
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
    `KDV hariç tutar: ${formatMoney(vat.subtotal, currency)}`,
    `KDV: ${formatMoney(vat.tax, currency)}`,
    `${copy.amountLabel}: ${formatMoney(payAmount, currency)}`,
    '',
    ...(awaitingPayment
      ? [
          'Güvenli ödeme:',
          paymentUrl,
          '',
          'Ödeme 3D Secure ile banka altyapısı üzerinden alınır. Kart bilgileriniz Microvise sistemlerinde saklanmaz.',
          '',
          ...bankTransferLines(),
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
  isReminder = false,
}) {
  const awaitingPayment = Boolean(String(paymentUrl || '').trim());
  const copy = invoiceMailCopy({ invoices, awaitingPayment, isReminder });
  const company = normalizeSeller(seller);
  let qrPng = null;
  if (awaitingPayment) {
    try {
      qrPng = await QRCode.toBuffer(paymentUrl, {
        type: 'png',
        margin: 0,
        width: 120,
        errorCorrectionLevel: 'M',
      });
    } catch (_) {
      qrPng = null;
    }
  }

  return new Promise((resolve, reject) => {
    const doc = new PDFDocument({
      size: 'A4',
      margin: 36,
      bufferPages: true,
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
    const left = 36;
    const right = pageWidth - 36;
    const width = right - left;
    const footerY = doc.page.height - 52;
    const pageBottom = () => footerY - 10;

    doc.save();
    doc.rect(0, 0, pageWidth, 64).fill('#1e3a5f');
    doc.rect(0, 64, pageWidth, 3).fill('#2563eb');
    doc
      .fillColor('#ffffff')
      .font(fonts.bold)
      .fontSize(16)
      .text('MICROVISE', left, 16);
    doc
      .fillColor('#bfdbfe')
      .font(fonts.regular)
      .fontSize(8)
      .text(company.title, left, 38, { width: width * 0.62, lineBreak: false });
    doc
      .fillColor('#dbeafe')
      .font(fonts.regular)
      .fontSize(8)
      .text(copy.headerLabel, left + width * 0.62, 18, {
        width: width * 0.38,
        align: 'right',
      });
    doc
      .fillColor('#bfdbfe')
      .font(fonts.regular)
      .fontSize(8)
      .text(formatDateTr(new Date()), left + width * 0.62, 34, {
        width: width * 0.38,
        align: 'right',
      });
    doc.restore();

    doc.y = 82;
    doc
      .fillColor('#64748b')
      .font(fonts.regular)
      .fontSize(8)
      .text('SAYIN', left, doc.y);
    doc.moveDown(0.15);
    doc
      .fillColor('#0f172a')
      .font(fonts.bold)
      .fontSize(13)
      .text(customerName || 'Yetkili', left, doc.y, { width });
    doc.moveDown(0.3);
    doc
      .fillColor('#334155')
      .font(fonts.regular)
      .fontSize(9)
      .text(copy.body, left, doc.y, { width, lineGap: 1.2 });
    doc.moveDown(0.45);

    const vat = combinedVatParts(invoices);
    const payAmount = numberOrZero(amount) || vat.total;
    const ensureSpace = (needed) => {
      if (doc.y + needed <= pageBottom()) return;
      doc.y = Math.min(doc.y, pageBottom() - 4);
    };

    const colNo = left;
    const colDate = left + width * 0.46;
    const colAmt = right;
    const headerY = doc.y;
    doc.save();
    doc.rect(left, headerY, width, 18).fill('#f1f5f9');
    doc.restore();
    doc
      .fillColor('#64748b')
      .font(fonts.bold)
      .fontSize(7.5)
      .text('FATURA NO', colNo + 8, headerY + 5, { width: width * 0.42 });
    doc.text('TARİH', colDate, headerY + 5, { width: 78 });
    doc.text('TUTAR', colAmt - 90, headerY + 5, { width: 82, align: 'right' });
    doc.y = headerY + 22;

    for (const invoice of invoices) {
      const remaining =
        remainingAmount(invoice) || Number(invoice.grand_total || 0);
      ensureSpace(22);
      const numberText = wrapUnbroken(
        localInvoiceNumber(invoice.invoice_number) || 'Fatura',
        28,
      );
      const numberHeight = doc
        .font(fonts.bold)
        .fontSize(10)
        .heightOfString(numberText, { width: width * 0.42 });
      const rowH = Math.max(16, Math.min(numberHeight, 28));
      const rowY = doc.y;
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(10)
        .text(numberText, colNo + 8, rowY, {
          width: width * 0.42,
          height: rowH,
          ellipsis: true,
        });
      doc
        .fillColor('#64748b')
        .font(fonts.regular)
        .fontSize(9)
        .text(formatDateTr(invoice.invoice_date), colDate, rowY, { width: 78 });
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
      doc.y = rowY + rowH + 4;
      doc
        .strokeColor('#e8edf3')
        .lineWidth(0.6)
        .moveTo(left, doc.y)
        .lineTo(right, doc.y)
        .stroke();
      doc.y += 4;

      for (const item of (invoice.items || []).slice(0, 8)) {
        const qty = Number(item.quantity || 1);
        const desc = wrapUnbroken(String(item.description || 'Kalem').trim(), 42);
        const rightCol = `${qty} ${item.unit || 'Adet'}   ${formatMoney(
          item.line_total,
          invoice.currency || currency,
        )}`;
        const descWidth = width - 132;
        ensureSpace(14);
        const itemY = doc.y;
        doc
          .fillColor('#64748b')
          .font(fonts.regular)
          .fontSize(8)
          .text(desc, left + 12, itemY, {
            width: descWidth,
            height: 12,
            ellipsis: true,
          });
        doc.text(rightCol, right - 118, itemY, {
          width: 110,
          align: 'right',
        });
        doc.y = itemY + 12;
      }
    }

    const totalsHeight = 62;
    ensureSpace(totalsHeight + 6);
    const totalY = doc.y;
    doc.save();
    doc.roundedRect(left, totalY, width, totalsHeight, 5).fill('#f8fafc');
    doc.restore();
    const vatRows = [
      ['KDV hariç tutar', formatMoney(vat.subtotal, currency), false],
      ['KDV', formatMoney(vat.tax, currency), false],
      [copy.amountLabel, formatMoney(payAmount, currency), true],
    ];
    vatRows.forEach((row, index) => {
      const y = totalY + 8 + index * 18;
      doc
        .fillColor('#64748b')
        .font(fonts.regular)
        .fontSize(row[2] ? 10 : 9)
        .text(row[0], left + 14, y);
      doc
        .fillColor(row[2] ? '#1e3a5f' : '#0f172a')
        .font(row[2] ? fonts.bold : fonts.regular)
        .fontSize(row[2] ? 12 : 9)
        .text(row[1], left + width * 0.45, y, {
          width: width * 0.55 - 14,
          align: 'right',
        });
    });
    doc.y = totalY + totalsHeight + 8;

    if (awaitingPayment) {
      const qrSize = 72;
      const textWidth = qrPng ? width - qrSize - 16 : width;
      const payBlockY = doc.y;
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(10)
        .text('Güvenli ödeme', left, payBlockY);
      doc
        .fillColor('#334155')
        .font(fonts.regular)
        .fontSize(8)
        .text(
          'Ödeme 3D Secure ile alınır. Kart bilgileriniz saklanmaz.',
          left,
          payBlockY + 14,
          { width: textWidth, lineGap: 1 },
        );
      doc
        .fillColor('#1d4ed8')
        .font(fonts.regular)
        .fontSize(7.5)
        .text(wrapUnbroken(paymentUrl, 34), left, payBlockY + 32, {
          width: textWidth,
          height: 28,
          link: paymentUrl,
          underline: true,
        });
      if (qrPng) {
        doc.image(qrPng, right - qrSize, payBlockY, { width: qrSize });
        doc.y = Math.max(payBlockY + 62, payBlockY + qrSize);
      } else {
        doc.y = payBlockY + 62;
      }

      const bankH = 70;
      if (doc.y + bankH > pageBottom()) {
        doc.y = pageBottom() - bankH;
      }
      const bankY = doc.y + 6;
      doc.save();
      doc.roundedRect(left, bankY, width, bankH, 5).stroke('#e8edf3');
      doc.restore();
      doc
        .fillColor('#0f172a')
        .font(fonts.bold)
        .fontSize(9)
        .text('Havale / EFT', left + 10, bankY + 8);
      doc
        .fillColor('#334155')
        .font(fonts.regular)
        .fontSize(8)
        .text(bankTransferPdfLines().join('\n'), left + 10, bankY + 22, {
          width: width - 20,
          height: bankH - 28,
          lineGap: 1.2,
        });
      doc.y = bankY + bankH;
    } else {
      doc
        .fillColor('#166534')
        .font(fonts.bold)
        .fontSize(10)
        .text(copy.thanks, left, doc.y, { width });
    }

    doc.switchToPage(0);
    doc.page.margins.bottom = 0;
    doc
      .strokeColor('#e8edf3')
      .lineWidth(0.8)
      .moveTo(left, footerY)
      .lineTo(right, footerY)
      .stroke();
    const footerLine1 = company.title || '';
    const footerLine2 = [company.address, company.phone, company.email, company.website]
      .filter(Boolean)
      .join('  ·  ');
    doc
      .fillColor('#64748b')
      .font(fonts.regular)
      .fontSize(7)
      .text(footerLine1, left, footerY + 5, {
        width,
        align: 'center',
        lineBreak: false,
      });
    doc.text(footerLine2, left, footerY + 15, {
      width,
      align: 'center',
      lineBreak: false,
    });

    doc.end();
  });
}

async function rememberCustomerEmail(customerId, email) {
  const id = String(customerId || '').trim();
  const to = String(email || '').trim().toLowerCase();
  if (!id || !isValidEmail(to)) return false;
  const result = await query(
    `
      update public.customers
      set email = $2
      where id = $1::uuid
        and coalesce(lower(btrim(email)), '') = ''
      returning id
    `,
    [id, to],
  );
  return Boolean(result.rows[0]);
}

function uniqueValidEmails(...sources) {
  const seen = new Set();
  const out = [];
  for (const source of sources) {
    const values = Array.isArray(source) ? source : [source];
    for (const value of values) {
      for (const part of String(value || '').split(/[;,]+/)) {
        const email = part.trim().toLowerCase();
        if (!isValidEmail(email) || seen.has(email)) continue;
        seen.add(email);
        out.push(email);
      }
    }
  }
  return out;
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
  emails,
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
  const recipients = uniqueValidEmails(
    email,
    emails,
    invoices[0].customer_email,
    invoices[0].customer_email_2,
    invoices[0].customer_email_3,
  );
  if (!recipients.length) {
    const error = new Error(
      'Müşteri e-postası yok. Göndermeden önce e-posta yazın.',
    );
    error.statusCode = 400;
    throw error;
  }
  const toLabel = recipients.join(', ');

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
    to: recipients,
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

  let savedToCustomer = false;
  try {
    savedToCustomer = await rememberCustomerEmail(
      invoices[0].customer_id,
      recipients[0],
    );
  } catch (error) {
    console.error('Cari e-posta kaydı:', error);
  }

  if (link) {
    await markPaymentLinkEmailed({
      linkId: link.id,
      emailedTo: toLabel,
    });
  }

  const savedNote = savedToCustomer ? ' Adres cari karta kaydedildi.' : '';
  return {
    ok: true,
    paymentUrl: paymentUrl || null,
    amount,
    currency,
    invoiceCount: invoices.length,
    emailedTo: toLabel,
    customerName,
    savedToCustomer,
    status: awaitingPayment ? 'pending' : 'paid',
    statusLabel: awaitingPayment
      ? 'Link gönderildi · ödeme bekliyor'
      : 'Ödeme teşekkür maili gönderildi',
    message: awaitingPayment
      ? `Fatura ve ödeme linki ${toLabel} adresine gönderildi.${savedNote}`
      : `Ödemeniz için teşekkür maili ${toLabel} adresine gönderildi.${savedNote}`,
  };
}

async function sendPosPaymentReminders({
  linkIds,
  createdBy,
  req,
  onlyOverdue = false,
  skipAlreadyReminded = false,
  now = new Date(),
}) {
  await ensureInvoicePaymentLinksTable();
  const requestedIds = uniqueLinkIds(linkIds);
  let rows = [];
  if (requestedIds.length) {
    const result = await query(
      `
        select
          l.*,
          c.name as customer_name,
          c.email as customer_email
        from public.invoice_payment_links l
        left join public.customers c on c.id = l.customer_id
        where l.id = any($1::uuid[])
      `,
      [requestedIds],
    );
    rows = result.rows;
  } else if (onlyOverdue) {
    const result = await query(
      `
        select
          l.*,
          c.name as customer_name,
          c.email as customer_email
        from public.invoice_payment_links l
        left join public.customers c on c.id = l.customer_id
        where coalesce(l.status, 'pending') = 'pending'
          and l.dismissed_at is null
          and coalesce(l.emailed_at, l.created_at) <= now() - interval '7 days'
          and ($1::boolean = false or l.reminded_at is null)
        order by coalesce(l.emailed_at, l.created_at) asc
        limit 80
      `,
      [skipAlreadyReminded === true],
    );
    rows = result.rows;
  } else {
    const error = new Error('Ödeme kaydı seçilmelidir.');
    error.statusCode = 400;
    throw error;
  }

  const sent = [];
  const skipped = [];
  const seller = await loadSellerForMail();

  for (const row of rows) {
    const status = String(row.status || 'pending').toLowerCase();
    if (status !== 'pending' || row.dismissed_at) {
      skipped.push(row.id);
      continue;
    }
    if (skipAlreadyReminded && row.reminded_at) {
      skipped.push(row.id);
      continue;
    }
    if (onlyOverdue && !posPaymentOverdue(row, { now })) {
      skipped.push(row.id);
      continue;
    }
    const invoiceIds = Array.isArray(row.invoice_ids) ? row.invoice_ids : [];
    if (!invoiceIds.length) {
      skipped.push(row.id);
      continue;
    }
    let invoices;
    try {
      invoices = await loadInvoicesForMail(invoiceIds);
    } catch (_) {
      skipped.push(row.id);
      continue;
    }
    const openInvoices = invoices.filter(
      (invoice) => remainingAmount(invoice) > 0.009,
    );
    if (!openInvoices.length) {
      skipped.push(row.id);
      continue;
    }
    const to = String(row.customer_email || invoices[0].customer_email || '').trim();
    if (!isValidEmail(to)) {
      skipped.push(row.id);
      continue;
    }
    const paymentUrl = buildHostedPaymentUrl({ token: row.token, req });
    const amount = Number(row.amount || 0);
    const currency = row.currency || invoices[0].currency || 'TRY';
    const customerName = row.customer_name || invoices[0].customer_name || 'Cari';
    const mailPayload = {
      customerName,
      invoices: openInvoices,
      amount,
      currency,
      paymentUrl,
      seller,
      isReminder: true,
    };
    const named = invoiceNumbersPhrase(openInvoices);
    const pdf = await buildInvoicePaymentPdf(mailPayload);
    const invoiceLabel = openInvoices
      .map((item) => localInvoiceNumber(item.invoice_number))
      .filter(Boolean)
      .join(', ');
    await sendEmail({
      to,
      subject: named
        ? `Hatırlatma · ${named} için ödeme`
        : 'Hatırlatma · Fatura ödemesi',
      html: buildPaymentEmailHtml(mailPayload),
      text: buildPaymentEmailText(mailPayload),
      attachments: [
        {
          filename: `hatirlatma-${(invoiceLabel || 'microvise')
            .replace(/[^\w.-]+/g, '_')
            .slice(0, 60)}.pdf`,
          content: pdf.toString('base64'),
          contentType: 'application/pdf',
        },
      ],
    });
    await query(
      `
        update public.invoice_payment_links
        set reminded_at = now(),
            reminded_count = coalesce(reminded_count, 0) + 1,
            expires_at = now() + interval '14 days',
            updated_at = now()
        where id = $1::uuid
      `,
      [row.id],
    );
    sent.push(row.id);
  }

  const count = sent.length;
  return {
    ok: true,
    count,
    sent,
    skipped: skipped.length,
    message:
      count === 0
        ? 'Gönderilecek hatırlatma yok.'
        : count === 1
          ? 'Hatırlatma gönderildi.'
          : `${count} hatırlatma gönderildi.`,
  };
}

module.exports = {
  sendInvoicePaymentLinkEmail,
  sendPosPaymentReminders,
  loadInvoicesForMail,
  markPaymentLinkEmailed,
  rememberCustomerEmail,
  formatMoney,
  localInvoiceNumber,
  formatDateTr,
  invoiceNumbersPhrase,
  invoiceMailCopy,
  buildPaymentEmailHtml,
  buildPaymentEmailText,
  normalizeSeller,
  wrapUnbroken,
  bankTransferPdfLines,
  buildInvoicePaymentPdf,
  combinedVatParts,
  DEFAULT_BANK_TRANSFER,
};
