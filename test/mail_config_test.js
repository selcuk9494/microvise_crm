const assert = require('node:assert/strict');
const test = require('node:test');

const {
  smtpFromRow,
  smtpFromEnv,
  isUsableSmtp,
  formatFrom,
  mergeSmtp,
  isValidEmail,
} = require('../api/_lib/mail');

test('Gmail uygulama şifresindeki boşlukları temizler', () => {
  const smtp = smtpFromRow({
    smtp_host: 'smtp.gmail.com',
    smtp_port: '587',
    smtp_secure: 'false',
    smtp_user: 'microvisefood@gmail.com',
    smtp_pass: 'abcd efgh ijkl mnop',
  });
  assert.equal(smtp.pass, 'abcdefghijklmnop');
  assert.equal(smtp.secure, false);
  assert.equal(isUsableSmtp(smtp), true);
});

test('SMTP_SECURE true iken 465/ssl kabul eder', () => {
  const smtp = smtpFromRow({
    smtp_host: 'smtp.gmail.com',
    smtp_port: '465',
    smtp_secure: 'true',
    smtp_user: 'a@b.com',
    smtp_pass: 'secret',
  });
  assert.equal(smtp.secure, true);
});

test('eksik şifrede SMTP kullanılamaz', () => {
  assert.equal(
    isUsableSmtp(
      smtpFromRow({
        smtp_host: 'smtp.gmail.com',
        smtp_user: 'a@b.com',
        smtp_pass: '',
      }),
    ),
    false,
  );
});

test('gönderen adresi kullanıcıdan üretilir', () => {
  assert.equal(
    formatFrom({ user: 'microvisefood@gmail.com' }),
    'Microvise Innovation <microvisefood@gmail.com>',
  );
  assert.equal(
    formatFrom({ from: 'Fatura <fatura@microvise.net>', user: 'x@y.com' }),
    'Fatura <fatura@microvise.net>',
  );
});

test('kayıtlı ayar env değerinin üzerine yazar', () => {
  const merged = mergeSmtp(
    smtpFromRow({
      smtp_host: 'smtp.gmail.com',
      smtp_user: 'stored@microvise.net',
      smtp_pass: 'storedpass',
    }),
    smtpFromEnv(),
  );
  assert.equal(merged.user, 'stored@microvise.net');
});

test('e-posta doğrulaması', () => {
  assert.equal(isValidEmail('microvisefood@gmail.com'), true);
  assert.equal(isValidEmail('not-an-email'), false);
});
