function foldTurkishAsciiPreserveCase(input) {
  return String(input || '')
    .replace(/ç/g, 'c')
    .replace(/Ç/g, 'C')
    .replace(/ğ/g, 'g')
    .replace(/Ğ/g, 'G')
    .replace(/ı/g, 'i')
    .replace(/İ/g, 'I')
    .replace(/ö/g, 'o')
    .replace(/Ö/g, 'O')
    .replace(/ş/g, 's')
    .replace(/Ş/g, 'S')
    .replace(/ü/g, 'u')
    .replace(/Ü/g, 'U');
}

function safeFilenamePart(value, fallback = 'fatura', maxLen = 80) {
  const cleaned = foldTurkishAsciiPreserveCase(value)
    .normalize('NFKD')
    .replace(/[\u0300-\u036f]/g, '')
    .replace(/[^a-zA-Z0-9._-]+/g, '_')
    .replace(/_+/g, '_')
    .replace(/^_|_$/g, '')
    .slice(0, maxLen)
    .replace(/_+$/g, '');
  return cleaned || fallback;
}

function safeDownloadFilename(
  input,
  { fallback = 'e_fatura.pdf', maxLen = 120 } = {},
) {
  const trimmed = String(input || '').trim();
  if (!trimmed) return fallback;
  const dot = trimmed.lastIndexOf('.');
  const hasExt = dot > 0 && dot < trimmed.length - 1;
  const stemRaw = hasExt ? trimmed.slice(0, dot) : trimmed;
  const extRaw = hasExt ? trimmed.slice(dot) : '';
  let stem = safeFilenamePart(stemRaw, '', maxLen);
  const ext = extRaw.toLowerCase().replace(/[^a-z0-9.]/g, '');
  if (!stem) {
    const fallbackDot = fallback.lastIndexOf('.');
    stem = fallbackDot > 0 ? fallback.slice(0, fallbackDot) : fallback;
  }
  if (!ext) {
    return stem.toLowerCase().endsWith('.pdf') ? stem : `${stem}.pdf`;
  }
  return `${stem}${ext}`;
}

module.exports = {
  foldTurkishAsciiPreserveCase,
  safeFilenamePart,
  safeDownloadFilename,
};
