import 'dart:typed_data';

class PickedXlsxFile {
  const PickedXlsxFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedXlsxFile?> pickXlsxFile() async => null;
