function cleanText(value) {
  return String(value ?? '').trim();
}

function environmentKey(environment) {
  return environment === 'production' ? 'production' : 'test';
}

function environmentLabel(environment) {
  return environmentKey(environment) === 'production' ? 'canlı' : 'test';
}

function hydrateCredentialSettings(settings) {
  const row = settings && typeof settings === 'object' ? { ...settings } : {};
  const legacyUser = cleanText(row.username);
  const legacyPass = cleanText(row.password);
  if (!cleanText(row.test_username)) row.test_username = legacyUser;
  if (!cleanText(row.test_password)) row.test_password = legacyPass;
  if (!cleanText(row.prod_username)) row.prod_username = legacyUser;
  if (!cleanText(row.prod_password)) row.prod_password = legacyPass;
  return row;
}

function credentialsForEnvironment(settings) {
  const hydrated = hydrateCredentialSettings(settings);
  const env = environmentKey(hydrated.environment);
  const prefix = env === 'production' ? 'prod' : 'test';
  return {
    environment: env,
    username: cleanText(hydrated[`${prefix}_username`]),
    password: cleanText(hydrated[`${prefix}_password`]),
  };
}

function syncActiveCredentialsFromEnvironment(settings) {
  const hydrated = hydrateCredentialSettings(settings);
  const creds = credentialsForEnvironment(hydrated);
  hydrated.username = creds.username;
  hydrated.password = creds.password;
  return hydrated;
}

function redactCredentialSettings(settings) {
  const row = hydrateCredentialSettings(settings);
  return {
    ...row,
    password_set: Boolean(cleanText(row.password)),
    test_password_set: Boolean(cleanText(row.test_password)),
    prod_password_set: Boolean(cleanText(row.prod_password)),
    password: '',
    test_password: '',
    prod_password: '',
  };
}

function preserveExistingSecrets(picked, current, keys) {
  const next = { ...picked };
  for (const key of keys) {
    if (
      Object.prototype.hasOwnProperty.call(next, key) &&
      !cleanText(next[key]) &&
      cleanText(current?.[key])
    ) {
      delete next[key];
    }
  }
  return next;
}

function humanizeTokenError(detail, environment) {
  const label = environmentLabel(environment);
  const raw = cleanText(detail) || 'Token alınamadı.';
  if (
    /invalid user credentials|invalid login credentials|invalid_grant/i.test(
      raw,
    )
  ) {
    return (
      `Maliye ${label} kullanıcısı/şifresi hatalı. ` +
      'E-Fatura > Ayarlar’da test ve canlı girişlerini ayrı girin.'
    );
  }
  return `Maliye ${label} oturumu açılamadı: ${raw}`;
}

module.exports = {
  credentialsForEnvironment,
  environmentLabel,
  humanizeTokenError,
  hydrateCredentialSettings,
  preserveExistingSecrets,
  redactCredentialSettings,
  syncActiveCredentialsFromEnvironment,
};
