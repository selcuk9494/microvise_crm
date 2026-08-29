function cleanText(value) {
  return String(value ?? '').trim();
}

function branchEntry(code, name) {
  const normalizedCode = cleanText(code);
  if (!normalizedCode) return null;
  const label = cleanText(name);
  return {
    code: normalizedCode,
    name: label || normalizedCode,
  };
}

function environmentKey(environment) {
  return environment === 'production' ? 'production' : 'test';
}

function configuredBranches(settings, environment) {
  const env = environmentKey(environment || settings?.environment);
  const prefix = env === 'production' ? 'prod' : 'test';
  const first =
    branchEntry(
      settings?.[`${prefix}_branch_code`] || settings?.seller_branch_code,
      settings?.[`${prefix}_branch_name`],
    ) || branchEntry(settings?.seller_branch_code, settings?.seller_branch_name);
  const second = branchEntry(
    settings?.[`${prefix}_branch_code_2`],
    settings?.[`${prefix}_branch_name_2`],
  );
  const list = [];
  if (first) list.push(first);
  if (
    second &&
    (!first || second.code.toUpperCase() !== first.code.toUpperCase())
  ) {
    list.push(second);
  }
  return list;
}

function hydrateBranchSettings(settings) {
  const row = settings && typeof settings === 'object' ? { ...settings } : {};
  const fallback = cleanText(row.seller_branch_code) || '1';
  if (!cleanText(row.test_branch_code)) row.test_branch_code = fallback;
  if (!cleanText(row.prod_branch_code)) row.prod_branch_code = fallback;
  if (!cleanText(row.test_branch_name)) {
    row.test_branch_name = cleanText(row.seller_branch_name) || 'Merkez';
  }
  if (!cleanText(row.prod_branch_name)) {
    row.prod_branch_name = cleanText(row.seller_branch_name) || 'Merkez';
  }
  return row;
}

function applyBranchToSettings(settings, branch) {
  const next = hydrateBranchSettings(settings);
  if (!branch?.code) return next;
  next.seller_branch_code = branch.code;
  next.seller_branch_name = branch.name || branch.code;
  return next;
}

function resolveSelectedBranch(
  settings,
  branchCode,
  { required = false } = {},
) {
  const hydrated = hydrateBranchSettings(settings);
  const env = environmentKey(hydrated.environment);
  const branches = configuredBranches(hydrated, env);
  if (!branches.length) {
    const error = new Error(
      'E-Fatura ayarlarında en az bir şube kodu tanımlayın.',
    );
    error.statusCode = 400;
    throw error;
  }
  const requested = cleanText(branchCode);
  if (!requested) {
    if (required) {
      const error = new Error('Hangi şubeden kesileceğini seçin.');
      error.statusCode = 400;
      throw error;
    }
    return branches[0];
  }
  const match = branches.find(
    (item) => item.code.toUpperCase() === requested.toUpperCase(),
  );
  if (!match) {
    const labels = branches
      .map((item) => (item.name === item.code ? item.code : `${item.name} (${item.code})`))
      .join(', ');
    const error = new Error(
      `Seçilen şube bu ortam için tanımlı değil: ${requested}. Tanımlı şubeler: ${labels}.`,
    );
    error.statusCode = 400;
    throw error;
  }
  return match;
}

function syncActiveBranchFromEnvironment(settings) {
  const hydrated = hydrateBranchSettings(settings);
  const primary = configuredBranches(hydrated, hydrated.environment)[0];
  if (primary) {
    hydrated.seller_branch_code = primary.code;
    hydrated.seller_branch_name = primary.name;
  }
  return hydrated;
}

module.exports = {
  applyBranchToSettings,
  configuredBranches,
  hydrateBranchSettings,
  resolveSelectedBranch,
  syncActiveBranchFromEnvironment,
};
