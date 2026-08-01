/// İmzalı URL yerine PDF dosyasını paylaşır. Desteklenmeyen platformda
/// `false` döner ve çağıran taraf bağlantıyı açmaya geri düşer.
Future<bool> shareEInvoicePdf({
  required String url,
  required String fileName,
  required String shareText,
}) async {
  return false;
}

/// Birden çok e-fatura PDF'ini indirir/paylaşır.
Future<bool> shareEInvoicePdfBundle({
  required List<EInvoicePdfDownload> files,
  required String shareText,
}) async {
  return false;
}

/// Birden çok PDF'i ayrı dosya olarak indirir (ZIP yok).
Future<bool> downloadEInvoicePdfs({
  required List<EInvoicePdfDownload> files,
}) async {
  return false;
}

class EInvoicePdfDownload {
  const EInvoicePdfDownload({
    required this.url,
    required this.fileName,
    this.localPath,
  });

  final String url;
  final String fileName;
  final String? localPath;
}
