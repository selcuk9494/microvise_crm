// Stub for non-web platforms
void downloadExcelFile(List<int> bytes, String filename) {
  // On non-web platforms, this would need to use file_saver or similar
  // For now, this is a stub since we're targeting web
  throw UnimplementedError('Excel download is only supported on web');
}
