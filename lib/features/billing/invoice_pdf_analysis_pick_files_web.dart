// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedPdfFile {
  const PickedPdfFile({
    required this.name,
    required this.bytes,
  });

  final String name;
  final List<int> bytes;
}

Future<List<PickedPdfFile>> pickInvoicePdfFiles() async {
  final input = html.FileUploadInputElement()
    ..accept = 'application/pdf,.pdf'
    ..multiple = true
    ..style.display = 'none';
  html.document.body?.append(input);

  try {
    input.click();
    await Future.any([
      input.onChange.first,
      input.onInput.first,
    ]);
    final files = input.files;
    if (files == null || files.isEmpty) return const [];

    final picked = <PickedPdfFile>[];
    for (final file in files) {
      final bytes = await _readFileBytes(file);
      if (bytes.isEmpty) continue;
      picked.add(PickedPdfFile(name: file.name, bytes: bytes));
    }
    return picked;
  } finally {
    input.remove();
  }
}

Future<Uint8List> _readFileBytes(html.File file) async {
  final reader = html.FileReader();
  final completer = Completer<Uint8List>();

  reader.onLoadEnd.listen((_) {
    if (completer.isCompleted) return;
    final result = reader.result;
    if (result is ByteBuffer) {
      completer.complete(result.asUint8List());
      return;
    }
    if (result is Uint8List) {
      completer.complete(result);
      return;
    }
    if (result is List<int>) {
      completer.complete(Uint8List.fromList(result));
      return;
    }
    completer.complete(Uint8List(0));
  });
  reader.onError.listen((_) {
    if (!completer.isCompleted) {
      completer.completeError(
        reader.error ?? StateError('PDF dosyasi okunamadi.'),
      );
    }
  });

  reader.readAsArrayBuffer(file);
  return completer.future;
}
