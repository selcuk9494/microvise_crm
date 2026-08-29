const assert = require('node:assert/strict');
const test = require('node:test');

const {
  buildPaymentEmailHtml,
  buildPaymentEmailText,
  formatMoney,
  localInvoiceNumber,
  formatDateTr,
  invoiceMailCopy,
  normalizeSeller,
  buildInvoicePaymentPdf,
} = require('../api/_lib/invoice_mail');

const sampleInvoices = [
  {
    invoice_number: '620009058-2026-1-00000000042',
    invoice_date: '2026-08-29',
    grand_total: 1250,
    paid_amount: 0,
    currency: 'TRY',
    subtotal: 1068.38,
    tax_total: 181.62,
    items: [
      {
        description: 'Worldline A910',
        quantity: 1,
        unit: 'Adet',
        unit_price: 1068.38,
        tax_rate: 17,
        line_total: 1250,
      },
    ],
  },
];

test('fatura numarası VKN önekini gizler', () => {
  assert.equal(localInvoiceNumber('620009058-2026-1-00000000042'), '2026-1-00000000042');
});

test('para birimini TR formatında yazar', () => {
  assert.equal(formatMoney(1250, 'TRY'), '1.250,00 ₺');
});

test('tarih Kıbrıs takvimine göre formatlanır', () => {
  assert.equal(formatDateTr('2026-08-29'), '29.08.2026');
});

test('HTML mail kurumsal şablon ve ödeme bağlantısı içerir', () => {
  const html = buildPaymentEmailHtml({
    customerName: 'Örnek Ticaret Ltd <script>',
    invoices: sampleInvoices,
    amount: 1250,
    currency: 'TRY',
    paymentUrl: 'https://crm.microvise.net/pay/abc',
  });
  assert.match(html, /MICROVISE/);
  assert.match(html, /Sayın/);
  assert.match(html, /Örnek Ticaret Ltd/);
  assert.doesNotMatch(html, /<script>/);
  assert.match(html, /Güvenli ödeme yap/);
  assert.match(html, /https:\/\/crm\.microvise\.net\/pay\/abc/);
  assert.match(html, /1\.250,00 ₺/);
  assert.match(html, /KDV hariç tutar/);
  assert.match(html, /1\.068,38 ₺/);
  assert.match(html, /KDV/);
  assert.match(html, /181,62 ₺/);
  assert.match(html, /TR57 0006 4000 0016 8010 3409 94/);
  assert.match(html, /TR41 0006 4000 0026 8010 4107 29/);
  assert.match(html, /Türkiye İş Bankası/);
  assert.match(html, /overflow-wrap:anywhere/);
  assert.match(html, /2026-1-00000000042 nolu faturanız için ödeme beklenmektedir/);
  assert.match(html, /Worldline A910/);
  assert.match(html, /3D Secure/);
  assert.match(html, /Microvise Innovation Ltd/);
});

test('düz metin kopyası ödeme linkini içerir', () => {
  const text = buildPaymentEmailText({
    customerName: 'Örnek Ticaret Ltd',
    invoices: sampleInvoices,
    amount: 1250,
    currency: 'TRY',
    paymentUrl: 'https://crm.microvise.net/pay/abc',
  });
  assert.match(text, /Sayın Örnek Ticaret Ltd/);
  assert.match(text, /2026-1-00000000042 nolu faturanız/);
  assert.match(text, /https:\/\/crm\.microvise\.net\/pay\/abc/);
  assert.match(text, /1\.250,00 ₺/);
  assert.match(text, /KDV hariç tutar: 1\.068,38 ₺/);
  assert.match(text, /KDV: 181,62 ₺/);
  assert.match(text, /TR57 0006 4000 0016 8010 3409 94/);
});

test('satıcı bilgisi boş alanlarda varsayılana düşer', () => {
  const seller = normalizeSeller({ seller_title: '  ', seller_email: 'fatura@microvise.net' });
  assert.equal(seller.title, 'Microvise Innovation Ltd');
  assert.equal(seller.email, 'fatura@microvise.net');
});

test('ödeme sonrası teşekkür mailinde fatura no geçer', () => {
  const html = buildPaymentEmailHtml({
    customerName: 'Örnek Ticaret Ltd',
    invoices: [{ ...sampleInvoices[0], paid_amount: 1250 }],
    amount: 1250,
    currency: 'TRY',
    paymentUrl: '',
  });
  assert.match(html, /Ödemeniz için teşekkür ederiz/);
  assert.match(html, /2026-1-00000000042 nolu faturanız kesilmiş/);
  assert.doesNotMatch(html, /Güvenli ödeme yap/);
});

test('PDF eki üretilir', async () => {
  const pdf = await buildInvoicePaymentPdf({
    customerName: 'Örnek Ticaret Ltd',
    invoices: sampleInvoices,
    amount: 1250,
    currency: 'TRY',
    paymentUrl: 'https://crm.microvise.net/pay/abc',
  });
  assert.ok(Buffer.isBuffer(pdf));
  assert.ok(pdf.length > 800);
  assert.equal(pdf.subarray(0, 4).toString(), '%PDF');
});

test('hatırlatma kopyası 1 hafta dilini kullanır', () => {
  const copy = invoiceMailCopy({
    invoices: sampleInvoices,
    awaitingPayment: true,
    isReminder: true,
  });
  assert.equal(copy.headerLabel, 'Ödeme hatırlatması');
  assert.match(copy.body, /1 haftadır ödeme beklenmektedir/);
  assert.match(copy.preheader, /ödeme hatırlatması/);
});

test('hatırlatma HTML mailinde ödeme linki ve hatırlatma başlığı vardır', () => {
  const html = buildPaymentEmailHtml({
    customerName: 'Örnek Ticaret Ltd',
    invoices: sampleInvoices,
    amount: 1250,
    currency: 'TRY',
    paymentUrl: 'https://crm.microvise.net/pay/abc',
    isReminder: true,
  });
  assert.match(html, /Ödeme hatırlatması/);
  assert.match(html, /1 haftadır ödeme beklenmektedir/);
  assert.match(html, /https:\/\/crm\.microvise\.net\/pay\/abc/);
  assert.match(html, /Güvenli ödeme yap/);
});
