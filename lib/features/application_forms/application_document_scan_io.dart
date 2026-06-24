import 'dart:io';
import 'dart:typed_data';

import 'package:cunning_document_scanner/cunning_document_scanner.dart';

Future<Uint8List?> scanSingleDocumentPage() async {
  final paths = await CunningDocumentScanner.getPictures(
    noOfPages: 1,
    isGalleryImportAllowed: false,
    androidScannerMode: AndroidScannerMode.base,
    iosScannerOptions: const IosScannerOptions(
      imageFormat: IosImageFormat.jpg,
      jpgCompressionQuality: 0.85,
    ),
  );
  if (paths == null || paths.isEmpty) return null;
  final path = paths.first.trim();
  if (path.isEmpty) return null;
  return File(path).readAsBytes();
}
