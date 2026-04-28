import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

class PickedPdfFile {
  const PickedPdfFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

Future<List<PickedPdfFile>> pickInvoicePdfFiles() async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: const ['pdf'],
    allowMultiple: true,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return const [];

  return result.files
      .where((file) => (file.bytes?.isNotEmpty ?? false))
      .map(
        (file) => PickedPdfFile(
          name: file.name,
          bytes: Uint8List.fromList(file.bytes!),
        ),
      )
      .toList(growable: false);
}
