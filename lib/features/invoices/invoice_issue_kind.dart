/// Satış faturası kaleminin Hat / GMP3 listesine yazılıp yazılmayacağı.
///
/// Stok adı **Gprs Data** (hat SIM) veya **GMP3** içeren hizmetler otomatik
/// işaretlenir; kullanıcı faturada işareti kaldırabilir.
const kInvoiceItemTypeLineSale = 'line_sale';
const kInvoiceItemTypeGmp3Sale = 'gmp3_sale';

String? detectInvoiceIssueKind({
  String? description,
  String? notes,
  String? productName,
  String? productCode,
  String? productCategory,
}) {
  final hay = [
    description,
    notes,
    productName,
    productCode,
    productCategory,
  ].whereType<String>().join(' ');
  return detectInvoiceIssueKindFromText(hay);
}

String? detectInvoiceIssueKindFromText(String raw) {
  final n = raw
      .toLowerCase()
      .replaceAll('ı', 'i')
      .replaceAll('i̇', 'i')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (n.isEmpty) return null;
  if (RegExp(r'gmp\s*-?\s*3').hasMatch(n)) return 'gmp3';
  if (RegExp(r'gprs\s*data').hasMatch(n) || RegExp(r'\bgprs\b').hasMatch(n)) {
    return 'line';
  }
  return null;
}

String? invoiceItemTypeForIssueKind(String? kind) {
  switch (kind) {
    case 'line':
      return kInvoiceItemTypeLineSale;
    case 'gmp3':
      return kInvoiceItemTypeGmp3Sale;
    default:
      return null;
  }
}

String? issueKindFromInvoiceItemType(String? itemType) {
  switch ((itemType ?? '').trim()) {
    case kInvoiceItemTypeLineSale:
      return 'line';
    case kInvoiceItemTypeGmp3Sale:
      return 'gmp3';
    default:
      return null;
  }
}
