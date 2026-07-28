String? buildOfficialEInvoiceUrl({
  required String? verificationCode,
  required String environment,
}) {
  final code = verificationCode?.trim() ?? '';
  if (code.isEmpty) return null;

  final host = environment == 'production'
      ? 'efatura.maliye.gov.ct.tr'
      : 'test-efatura.maliye.gov.ct.tr';
  return Uri.https(host, '/dogrula/', {'code': code}).toString();
}
