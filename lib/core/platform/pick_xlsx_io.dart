import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedXlsxFile {
  const PickedXlsxFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedXlsxFile?> pickXlsxFile() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['xlsx'],
    withData: true,
  );
  final file = result?.files.firstOrNull;
  final bytes = file?.bytes;
  if (file == null || bytes == null || bytes.isEmpty) return null;
  return PickedXlsxFile(name: file.name, bytes: Uint8List.fromList(bytes));
}
