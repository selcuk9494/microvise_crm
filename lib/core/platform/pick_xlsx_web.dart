// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';

class PickedXlsxFile {
  const PickedXlsxFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

Future<PickedXlsxFile?> pickXlsxFile() async {
  final input = html.FileUploadInputElement()
    ..accept =
        '.xlsx,application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'
    ..multiple = false;
  input.style
    ..position = 'fixed'
    ..left = '0'
    ..top = '0'
    ..width = '1px'
    ..height = '1px'
    ..opacity = '0'
    ..pointerEvents = 'none';
  html.document.body?.append(input);

  final completer = Completer<PickedXlsxFile?>();

  void finish(PickedXlsxFile? value) {
    if (!completer.isCompleted) completer.complete(value);
    input.remove();
    html.window.dispatchEvent(html.Event('resize'));
  }

  input.onChange.listen((_) async {
    final files = input.files;
    if (files == null || files.isEmpty) {
      finish(null);
      return;
    }
    try {
      final file = files[0];
      final bytes = await _readFileBytes(file);
      if (bytes.isEmpty) {
        finish(null);
        return;
      }
      finish(PickedXlsxFile(name: file.name, bytes: bytes));
    } catch (_) {
      finish(null);
    }
  });
  input.addEventListener('cancel', (_) {
    finish(null);
  });

  input.click();
  return completer.future;
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
        reader.error ?? StateError('Excel dosyası okunamadı.'),
      );
    }
  });

  reader.readAsArrayBuffer(file);
  return completer.future;
}
