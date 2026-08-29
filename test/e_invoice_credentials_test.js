const assert = require('node:assert/strict');
const test = require('node:test');

const {
  credentialsForEnvironment,
  humanizeTokenError,
  hydrateCredentialSettings,
  preserveExistingSecrets,
  redactCredentialSettings,
  syncActiveCredentialsFromEnvironment,
} = require('../api/_lib/e_invoice_credentials');

test('eski tek kullanıcıyı test ve canlıya kopyalar', () => {
  const row = hydrateCredentialSettings({
    username: 'test-user',
    password: 'test-pass',
  });
  assert.equal(row.test_username, 'test-user');
  assert.equal(row.test_password, 'test-pass');
  assert.equal(row.prod_username, 'test-user');
  assert.equal(row.prod_password, 'test-pass');
});

test('ortama göre ayrı şifre kullanır', () => {
  const settings = {
    environment: 'production',
    test_username: 'test-user',
    test_password: 'test-pass',
    prod_username: 'prod-user',
    prod_password: 'prod-pass',
  };
  assert.deepEqual(credentialsForEnvironment(settings), {
    environment: 'production',
    username: 'prod-user',
    password: 'prod-pass',
  });
  assert.equal(
    credentialsForEnvironment({ ...settings, environment: 'test' }).username,
    'test-user',
  );
});

test('aktif ortamın şifresini username/password ile eşitler', () => {
  const synced = syncActiveCredentialsFromEnvironment({
    environment: 'test',
    test_username: 't1',
    test_password: 'p1',
    prod_username: 'c1',
    prod_password: 'c2',
    username: 'old',
    password: 'oldpass',
  });
  assert.equal(synced.username, 't1');
  assert.equal(synced.password, 'p1');
});

test('boş şifre kaydında mevcut sırrı korur', () => {
  const picked = preserveExistingSecrets(
    { test_password: '', smtp_pass: null, prod_username: 'yeni' },
    { test_password: 'sakla', smtp_pass: 'mail', prod_username: 'eski' },
    ['test_password', 'prod_password', 'smtp_pass'],
  );
  assert.equal(picked.test_password, undefined);
  assert.equal(picked.smtp_pass, undefined);
  assert.equal(picked.prod_username, 'yeni');
});

test('GET yanıtında şifreleri gizler', () => {
  const publicRow = redactCredentialSettings({
    test_password: 'gizli',
    prod_password: '',
    password: '',
  });
  assert.equal(publicRow.test_password, '');
  assert.equal(publicRow.prod_password, '');
  assert.equal(publicRow.password, '');
  assert.equal(publicRow.test_password_set, true);
  assert.equal(publicRow.prod_password_set, false);
});

test('hatalı şifre mesajını ortama göre çevirir', () => {
  assert.match(
    humanizeTokenError('Invalid user credentials', 'test'),
    /test kullanıcısı\/şifresi hatalı/i,
  );
  assert.match(
    humanizeTokenError('invalid_grant', 'production'),
    /canlı kullanıcısı\/şifresi hatalı/i,
  );
});
