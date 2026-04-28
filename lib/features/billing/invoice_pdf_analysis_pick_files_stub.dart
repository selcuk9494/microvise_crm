class PickedPdfFile {
  const PickedPdfFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

Future<List<PickedPdfFile>> pickInvoicePdfFiles() {
  throw UnsupportedError('PDF secme bu platformda desteklenmiyor.');
}
