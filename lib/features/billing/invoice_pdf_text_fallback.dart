import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Syncfusion bazı NotoSans Identity-H subset PDF'lerde ToUnicode
/// çözümlerken kısmi/boş metin döndürebiliyor. Bu fallback CID hex
/// stringlerini ToUnicode CMap ile çözer.
class InvoicePdfTextFallback {
  static String extract(Uint8List bytes) {
    try {
      return _extract(bytes);
    } catch (_) {
      return '';
    }
  }

  static bool looksReadableInvoiceText(String text) {
    final normalized = text.replaceAll('\u00A0', ' ');
    final hasInvoiceNo = RegExp(
      r'Fatura\s*No\s*:',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasTotal = RegExp(
      r'Ara\s*Toplam|Ödenecek\s*Toplam|Odenecek\s*Toplam',
      caseSensitive: false,
    ).hasMatch(normalized);
    final hasMoney = RegExp(r'[₺\$€£]\s*[0-9]').hasMatch(normalized);
    return hasInvoiceNo && (hasTotal || hasMoney);
  }

  static String _extract(Uint8List bytes) {
    final source = latin1.decode(bytes, allowInvalid: true);
    final streams = _inflateStreams(bytes, source);
    final fontXrefToUnicode = <int, int>{};

    for (final match in RegExp(
      r'(\d+)\s+0\s+obj\s*<<([^>]*?/Type\s*/Font[^>]*)>>',
      dotAll: true,
    ).allMatches(source)) {
      final xref = int.parse(match.group(1)!);
      final body = match.group(2) ?? '';
      final toUni = RegExp(
        r'/ToUnicode\s+(\d+)\s+0\s+R',
      ).firstMatch(body)?.group(1);
      if (toUni != null) {
        fontXrefToUnicode[xref] = int.parse(toUni);
      }
    }

    final cmaps = <int, Map<int, String>>{};
    for (final xref in fontXrefToUnicode.values.toSet()) {
      final stream = streams[xref];
      if (stream == null) continue;
      cmaps[xref] = _parseCMap(utf8.decode(stream, allowMalformed: true));
    }

    final localFontToUnicode = <String, int>{};
    for (final match in RegExp(
      r'/Font\s*<<([^>]*)>>',
      dotAll: true,
    ).allMatches(source)) {
      for (final fontRef in RegExp(
        r'/([A-Za-z0-9]+)\s+(\d+)\s+0\s+R',
      ).allMatches(match.group(1)!)) {
        final toUni = fontXrefToUnicode[int.parse(fontRef.group(2)!)];
        if (toUni != null) localFontToUnicode[fontRef.group(1)!] = toUni;
      }
    }

    final contentXrefs = <int>{
      for (final match in RegExp(
        r'/Contents\s+(\d+)\s+0\s+R',
      ).allMatches(source))
        int.parse(match.group(1)!),
    };
    for (final match in RegExp(
      r'/Contents\s*\[(.*?)\]',
      dotAll: true,
    ).allMatches(source)) {
      for (final ref in RegExp(r'(\d+)\s+0\s+R').allMatches(match.group(1)!)) {
        contentXrefs.add(int.parse(ref.group(1)!));
      }
    }
    if (contentXrefs.isEmpty) return '';

    final out = StringBuffer();
    Map<int, String> activeMap = const {};
    for (final xref in contentXrefs) {
      final stream = streams[xref];
      if (stream == null) continue;
      final text = latin1.decode(stream, allowInvalid: true);
      final tokenRe = RegExp(
        r'/([A-Za-z0-9]+)\s+\d+(?:\.\d+)?\s+Tf|'
        r'\[\s*((?:<[^>]+>|\s|-?\d+(?:\.\d+)?)*)\s*\]\s*TJ|'
        r'<([0-9A-Fa-f]+)>\s*Tj|'
        r'\b(?:T\*|Td|TD|Tm)\b',
      );
      var pendingSpace = false;
      for (final match in tokenRe.allMatches(text)) {
        final full = match.group(0)!;
        if (full.endsWith('Tf')) {
          final fontLocal = match.group(1);
          final toUni = fontLocal == null ? null : localFontToUnicode[fontLocal];
          if (toUni != null && cmaps.containsKey(toUni)) {
            activeMap = cmaps[toUni]!;
          }
          pendingSpace = true;
          continue;
        }
        if (full == 'T*' || full == 'Td' || full == 'TD' || full == 'Tm') {
          pendingSpace = true;
          continue;
        }

        String chunk = '';
        final tjBody = match.group(2);
        final tjHex = match.group(3);
        if (tjBody != null) {
          chunk = [
            for (final hex in RegExp(r'<([0-9A-Fa-f]+)>').allMatches(tjBody))
              _decodeHexCid(hex.group(1)!, activeMap),
          ].join();
        } else if (tjHex != null) {
          chunk = _decodeHexCid(tjHex, activeMap);
        }
        if (chunk.isEmpty) continue;
        if (pendingSpace && out.isNotEmpty && !out.toString().endsWith('\n') && !out.toString().endsWith(' ')) {
          out.write(' ');
        }
        out.write(chunk);
        pendingSpace = false;
      }
      out.writeln();
    }
    return out.toString().replaceAll(RegExp(r'[ \t]+'), ' ').trim();
  }

  static Map<int, Uint8List> _inflateStreams(Uint8List bytes, String source) {
    final streams = <int, Uint8List>{};
    for (final match in RegExp(
      r'(\d+)\s+0\s+obj\s*<<([^>]*)>>\s*stream(\r\n|\n|\r)',
      dotAll: true,
    ).allMatches(source)) {
      final xref = int.parse(match.group(1)!);
      final dict = match.group(2) ?? '';
      if (dict.contains('/Subtype /Image') || dict.contains('/Length1')) {
        continue;
      }
      final start = match.end;
      final lengthMatch = RegExp(r'/Length\s+(\d+)').firstMatch(dict);
      late Uint8List raw;
      if (lengthMatch != null) {
        final length = int.parse(lengthMatch.group(1)!);
        if (start + length > bytes.length) continue;
        raw = Uint8List.sublistView(bytes, start, start + length);
      } else {
        final end = source.indexOf('endstream', start);
        if (end <= start) continue;
        raw = Uint8List.fromList(latin1.encode(source.substring(start, end)));
        while (raw.isNotEmpty &&
            (raw.last == 0x0a || raw.last == 0x0d)) {
          raw = Uint8List.sublistView(raw, 0, raw.length - 1);
        }
      }
      if (dict.contains('/FlateDecode')) {
        final decoded = _inflate(raw);
        if (decoded == null) continue;
        raw = decoded;
      }
      streams[xref] = raw;
    }
    return streams;
  }

  static Uint8List? _inflate(Uint8List raw) {
    try {
      return Uint8List.fromList(const ZLibDecoder().decodeBytes(raw));
    } catch (_) {}
    try {
      // Bazı üreticiler zlib sarmalayıcısız raw deflate yazar.
      return Uint8List.fromList(Inflate(raw).getBytes());
    } catch (_) {
      return null;
    }
  }

  static Map<int, String> _parseCMap(String cmap) {
    final map = <int, String>{};
    for (final block in RegExp(
      r'beginbfchar(.*?)endbfchar',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(cmap)) {
      for (final row in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(block.group(1)!)) {
        map[int.parse(row.group(1)!, radix: 16)] = _utf16HexToString(
          row.group(2)!,
        );
      }
    }
    for (final block in RegExp(
      r'beginbfrange(.*?)endbfrange',
      dotAll: true,
      caseSensitive: false,
    ).allMatches(cmap)) {
      final body = block.group(1)!;
      for (final row in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*\[(.*?)\]',
        dotAll: true,
      ).allMatches(body)) {
        var cid = int.parse(row.group(1)!, radix: 16);
        for (final dest in RegExp(
          r'<([0-9A-Fa-f]+)>',
        ).allMatches(row.group(3)!)) {
          map[cid] = _utf16HexToString(dest.group(1)!);
          cid += 1;
        }
      }
      for (final row in RegExp(
        r'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>',
      ).allMatches(body)) {
        final start = int.parse(row.group(1)!, radix: 16);
        final end = int.parse(row.group(2)!, radix: 16);
        if (map.containsKey(start)) continue;
        var dest = int.parse(row.group(3)!, radix: 16);
        for (var cid = start; cid <= end; cid += 1) {
          map[cid] = String.fromCharCode(dest);
          dest += 1;
        }
      }
    }
    return map;
  }

  static String _decodeHexCid(String hex, Map<int, String> map) {
    final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty || map.isEmpty) return '';
    final out = StringBuffer();
    final width = cleaned.length % 4 == 0 ? 4 : 2;
    for (var i = 0; i + width <= cleaned.length; i += width) {
      final cid = int.parse(cleaned.substring(i, i + width), radix: 16);
      final ch = map[cid];
      if (ch != null && ch.isNotEmpty) out.write(ch);
    }
    return out.toString();
  }

  static String _utf16HexToString(String hex) {
    final cleaned = hex.replaceAll(RegExp(r'\s+'), '');
    if (cleaned.isEmpty) return '';
    final codes = <int>[];
    for (var i = 0; i + 4 <= cleaned.length; i += 4) {
      codes.add(int.parse(cleaned.substring(i, i + 4), radix: 16));
    }
    return String.fromCharCodes(codes.where((c) => c != 0));
  }
}
