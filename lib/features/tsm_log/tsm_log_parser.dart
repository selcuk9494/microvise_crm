import 'dart:convert';
import 'dart:typed_data';

import 'package:excel/excel.dart' as excel;
import 'package:spreadsheet_decoder/spreadsheet_decoder.dart';

enum TsmLogOperation { terminalSorgu, isemriAcma }

enum TsmLogResultKind { approved, serialMismatch, other }

enum TsmOrderKind { kurulum, ekleme, geriAlim, unknown }

class TsmWorkOrderDetails {
  const TsmWorkOrderDetails({
    this.bankName = '',
    this.acquirerId = '',
    this.terminalId = '',
    this.merchantName = '',
    this.merchantNo = '',
    this.bkmMerchantId = '',
    this.address = '',
    this.city = '',
    this.district = '',
    this.phone = '',
    this.orderCode = '',
    this.description = '',
    this.orderKind = TsmOrderKind.unknown,
  });

  final String bankName;
  final String acquirerId;
  final String terminalId;
  final String merchantName;
  final String merchantNo;
  final String bkmMerchantId;
  final String address;
  final String city;
  final String district;
  final String phone;
  final String orderCode;
  final String description;
  final TsmOrderKind orderKind;

  bool get isEmpty =>
      bankName.isEmpty &&
      acquirerId.isEmpty &&
      terminalId.isEmpty &&
      merchantName.isEmpty &&
      merchantNo.isEmpty &&
      bkmMerchantId.isEmpty &&
      address.isEmpty &&
      city.isEmpty &&
      district.isEmpty &&
      phone.isEmpty &&
      orderCode.isEmpty &&
      description.isEmpty &&
      orderKind == TsmOrderKind.unknown;

  int get richness {
    var score = 0;
    for (final value in [
      bankName,
      acquirerId,
      terminalId,
      merchantName,
      merchantNo,
      bkmMerchantId,
      address,
      city,
      district,
      phone,
      orderCode,
      description,
    ]) {
      if (value.isNotEmpty) score += 1;
    }
    if (orderKind != TsmOrderKind.unknown) score += 2;
    return score;
  }

  String get displayAddress {
    final parts = <String>[];
    if (address.isNotEmpty) parts.add(address);
    final upperAddress = address.toUpperCase();
    if (city.isNotEmpty && !upperAddress.contains(city.toUpperCase())) {
      parts.add(city);
    }
    if (district.isNotEmpty &&
        !upperAddress.contains(district.toUpperCase())) {
      parts.add(district);
    }
    return parts.join(', ');
  }

  String get merchantLine {
    final parts = <String>[];
    if (merchantName.isNotEmpty) parts.add(merchantName);
    if (merchantNo.isNotEmpty) parts.add(merchantNo);
    if (bkmMerchantId.isNotEmpty) parts.add('BKM $bkmMerchantId');
    return parts.join(' · ');
  }
}

class TsmLogOutcome {
  const TsmLogOutcome({
    required this.operation,
    required this.resultMessage,
  });

  final TsmLogOperation operation;
  final String resultMessage;

  @override
  bool operator ==(Object other) =>
      other is TsmLogOutcome &&
      other.operation == operation &&
      other.resultMessage == resultMessage;

  @override
  int get hashCode => Object.hash(operation, resultMessage);
}

class TsmLogEntry {
  const TsmLogEntry({
    required this.serialNumber,
    required this.operation,
    required this.resultKind,
    required this.excelRow,
    this.resultMessage = '',
    this.workOrder,
    this.occurredAt,
  });

  final String serialNumber;
  final TsmLogOperation operation;
  final TsmLogResultKind resultKind;
  final String resultMessage;
  final int excelRow;
  final TsmWorkOrderDetails? workOrder;
  final DateTime? occurredAt;
}

class TsmLogSerial {
  const TsmLogSerial({
    required this.serialNumber,
    required this.operations,
    required this.resultKinds,
    required this.count,
    this.outcomes = const <TsmLogOutcome>{},
    this.workOrder,
    this.occurredAt,
  });

  final String serialNumber;
  final Set<TsmLogOperation> operations;
  final Set<TsmLogResultKind> resultKinds;
  final Set<TsmLogOutcome> outcomes;
  final int count;
  final TsmWorkOrderDetails? workOrder;
  final DateTime? occurredAt;

  Set<String> get resultMessages => {
    for (final outcome in outcomes)
      if (outcome.resultMessage.isNotEmpty) outcome.resultMessage,
  };
}

class TsmLogParseResult {
  const TsmLogParseResult({
    required this.fileName,
    required this.totalRows,
    required this.matchedRows,
    required this.skippedRows,
    required this.entries,
    required this.uniqueSerials,
    this.resultMessageOptions = const [],
    this.error,
  });

  final String fileName;
  final int totalRows;
  final int matchedRows;
  final int skippedRows;
  final List<TsmLogEntry> entries;
  final List<TsmLogSerial> uniqueSerials;
  final List<String> resultMessageOptions;
  final String? error;

  bool get isEmpty => uniqueSerials.isEmpty;
}

final _termSeriNoPattern = RegExp(
  r'&lt;(?:[\w]+:)?TermSeriNo&gt;\s*([^&<]+)\s*&lt;/(?:[\w]+:)?TermSeriNo&gt;|'
  r'<(?:[\w]+:)?TermSeriNo>\s*([^<]+)\s*</(?:[\w]+:)?TermSeriNo>',
  caseSensitive: false,
);

const _allowedOperations = <String, TsmLogOperation>{
  'TERMINALSORGU': TsmLogOperation.terminalSorgu,
  'ISEMRIACMA': TsmLogOperation.isemriAcma,
};

TsmLogParseResult parseTsmLogExcel(
  Uint8List bytes, {
  String fileName = 'tsm.xlsx',
}) {
  if (bytes.isEmpty) {
    return TsmLogParseResult(
      fileName: fileName,
      totalRows: 0,
      matchedRows: 0,
      skippedRows: 0,
      entries: const [],
      uniqueSerials: const [],
      error: 'Dosya boş.',
    );
  }

  final errors = <String>[];
  TsmLogParseResult? emptyMatch;
  TsmLogParseResult? bestWithoutDates;
  for (final rows in _decodeSpreadsheetTables(bytes, errors: errors)) {
    final parsed = parseTsmLogRows(rows, fileName: fileName);
    if (parsed.uniqueSerials.isEmpty) {
      if (parsed.error == null) emptyMatch = parsed;
      if (parsed.error != null) errors.add(parsed.error!);
      continue;
    }
    if (parsed.uniqueSerials.any((item) => item.occurredAt != null)) {
      return parsed;
    }
    bestWithoutDates ??= parsed;
  }

  final raw = _parseTsmLogRawBytes(bytes, fileName: fileName);
  if (raw.uniqueSerials.any((item) => item.occurredAt != null)) return raw;
  if (bestWithoutDates != null) return bestWithoutDates;
  if (raw.uniqueSerials.isNotEmpty) return raw;
  if (emptyMatch != null) return emptyMatch;

  return TsmLogParseResult(
    fileName: fileName,
    totalRows: 0,
    matchedRows: 0,
    skippedRows: 0,
    entries: const [],
    uniqueSerials: const [],
    error: 'Excel okunamadı. .xls veya .xlsx dosyası yükleyin.',
  );
}

Iterable<List<List<String>>> _decodeSpreadsheetTables(
  Uint8List bytes, {
  required List<String> errors,
}) sync* {
  final zipOffset = _zipOffset(bytes);
  if (zipOffset >= 0) {
    final payload = zipOffset == 0 ? bytes : Uint8List.sublistView(bytes, zipOffset);
    final xlsxRows = _decodeXlsx(payload, errors: errors);
    if (xlsxRows != null) yield xlsxRows;
  }

  final xlsRows = _decodeBinaryXls(bytes, errors: errors);
  if (xlsRows != null) yield xlsRows;

  for (final text in _textViews(bytes)) {
    final htmlTables = _parseHtmlTables(text);
    if (htmlTables.isNotEmpty) yield* htmlTables;
    final xmlRows = _parseXmlSpreadsheet(text);
    if (xmlRows != null) yield xmlRows;
    final csvRows = _parseDelimited(text);
    if (csvRows != null) yield csvRows;
  }
}

TsmLogParseResult _parseTsmLogRawBytes(
  Uint8List bytes, {
  required String fileName,
}) {
  final entries = <TsmLogEntry>[];
  for (final text in _textViews(bytes)) {
    entries.addAll(_extractEntriesFromText(text));
  }
  if (entries.isEmpty) {
    return TsmLogParseResult(
      fileName: fileName,
      totalRows: 0,
      matchedRows: 0,
      skippedRows: 0,
      entries: const [],
      uniqueSerials: const [],
      error: 'Excel okunamadı. .xls veya .xlsx dosyası yükleyin.',
    );
  }
  return TsmLogParseResult(
    fileName: fileName,
    totalRows: entries.length,
    matchedRows: entries.length,
    skippedRows: 0,
    entries: entries,
    uniqueSerials: groupTsmLogSerials(entries),
  );
}

Iterable<String> _textViews(Uint8List bytes) sync* {
  yield _decodeText(bytes);
  yield latin1.decode(bytes, allowInvalid: true);
  yield latin1.decode(bytes, allowInvalid: true).replaceAll('\u0000', '');
  yield _decodeUtf16(bytes, littleEndian: true, skipBom: false);
}

List<TsmLogEntry> _extractEntriesFromText(String text) {
  final entries = <TsmLogEntry>[];
  for (final match in _termSeriNoPattern.allMatches(text)) {
    final serial = (match.group(1) ?? match.group(2) ?? '').trim();
    if (serial.isEmpty || !serial.startsWith('2')) continue;
    final start = match.start - 2500 < 0 ? 0 : match.start - 2500;
    final end = match.end + 800 > text.length ? text.length : match.end + 800;
    final window = text.substring(start, end);
    final operation = parseTsmLogOperation(window);
    final resultKind = parseTsmLogResultKind(window);
    if (resultKind == null) continue;
    if (operation == null && resultKind != TsmLogResultKind.serialMismatch) {
      continue;
    }
    final resolvedOperation = operation ?? TsmLogOperation.terminalSorgu;
    entries.add(
      TsmLogEntry(
        serialNumber: serial,
        operation: resolvedOperation,
        resultKind: resultKind,
        resultMessage: normalizeTsmResultMessage(window),
        excelRow: 0,
        occurredAt: parseTsmLogDateTime(window),
        workOrder:
            resolvedOperation == TsmLogOperation.isemriAcma &&
                resultKind == TsmLogResultKind.approved
            ? parseTsmWorkOrderDetails(window)
            : null,
      ),
    );
  }
  return entries;
}

List<List<String>>? _decodeXlsx(Uint8List bytes, {required List<String> errors}) {
  try {
    final book = excel.Excel.decodeBytes(bytes);
    final sheet = book.tables.values.isEmpty ? null : book.tables.values.first;
    if (sheet == null || sheet.rows.isEmpty) {
      errors.add('Excel içinde sayfa bulunamadı.');
      return null;
    }
    return sheet.rows
        .map(
          (row) => row.map(_cellToText).toList(growable: false),
        )
        .toList(growable: false);
  } catch (error) {
    errors.add('Excel okunamadı: $error');
    return null;
  }
}

List<List<String>>? _decodeBinaryXls(
  Uint8List bytes, {
  required List<String> errors,
}) {
  try {
    final decoder = SpreadsheetDecoder.decodeBytes(bytes, update: false);
    if (decoder.tables.isEmpty) {
      errors.add('Excel içinde sayfa bulunamadı.');
      return null;
    }
    final table = decoder.tables.values.first;
    if (table.rows.isEmpty) {
      errors.add('Excel içinde satır bulunamadı.');
      return null;
    }
    return table.rows
        .map(
          (row) => row.map(_cellToText).toList(growable: false),
        )
        .toList(growable: false);
  } catch (error) {
    errors.add('Excel okunamadı: $error');
    return null;
  }
}

TsmLogParseResult parseTsmLogRows(
  List<List<String>> rows, {
  String fileName = 'tsm.xlsx',
}) {
  final header = _findHeader(rows);
  if (header == null) {
    return TsmLogParseResult(
      fileName: fileName,
      totalRows: 0,
      matchedRows: 0,
      skippedRows: 0,
      entries: const [],
      uniqueSerials: const [],
      error:
          'Excel içinde "İşlem" ve "Sonuç Mesajı" kolonları bulunamadı.',
    );
  }

  final entries = <TsmLogEntry>[];
  final messageOptions = <String>{};
  var skipped = 0;
  for (var i = header.rowIndex + 1; i < rows.length; i++) {
    final row = rows[i];
    final operationRaw = _cellAt(row, header.operationIndex);
    final messageRaw = _cellAt(row, header.messageIndex);
    if (operationRaw.isEmpty && messageRaw.isEmpty) continue;

    final operation = parseTsmLogOperation(operationRaw);
    if (operation == null) continue;

    final resultKind =
        parseTsmLogResultKind(messageRaw) ?? TsmLogResultKind.other;
    final resultMessage = normalizeTsmResultMessage(messageRaw);
    messageOptions.add(resultMessage.isEmpty ? '(Boş)' : resultMessage);

    final params = _cellAt(row, header.paramIndex);
    final serials = extractTermSeriNos('$messageRaw\n$params\n${row.join('\n')}');
    if (serials.isEmpty) {
      skipped += 1;
      continue;
    }

    final workOrder =
        operation == TsmLogOperation.isemriAcma &&
            resultKind == TsmLogResultKind.approved
        ? parseTsmWorkOrderDetails(params.isEmpty ? messageRaw : params)
        : null;
    final occurredAt = parseTsmLogDateTime(
      _cellAt(row, header.dateIndex),
      _cellAt(row, header.timeIndex),
    );

    for (final serial in serials) {
      entries.add(
        TsmLogEntry(
          serialNumber: serial,
          operation: operation,
          resultKind: resultKind,
          resultMessage: resultMessage,
          excelRow: i + 1,
          workOrder: workOrder,
          occurredAt: occurredAt,
        ),
      );
    }
  }

  return TsmLogParseResult(
    fileName: fileName,
    totalRows: (rows.length - header.rowIndex - 1).clamp(0, rows.length),
    matchedRows: entries.length,
    skippedRows: skipped,
    entries: entries,
    uniqueSerials: groupTsmLogSerials(entries),
    resultMessageOptions: tsmSortedResultMessages(messageOptions),
  );
}

List<TsmLogSerial> groupTsmLogSerials(List<TsmLogEntry> entries) {
  final grouped = <String, TsmLogSerial>{};
  for (final entry in entries) {
    final outcome = TsmLogOutcome(
      operation: entry.operation,
      resultMessage: entry.resultMessage.isEmpty
          ? '(Boş)'
          : entry.resultMessage,
    );
    final existing = grouped[entry.serialNumber];
    if (existing == null) {
      grouped[entry.serialNumber] = TsmLogSerial(
        serialNumber: entry.serialNumber,
        operations: {entry.operation},
        resultKinds: {entry.resultKind},
        outcomes: {outcome},
        count: 1,
        workOrder: entry.workOrder,
        occurredAt: entry.occurredAt,
      );
      continue;
    }
    grouped[entry.serialNumber] = TsmLogSerial(
      serialNumber: existing.serialNumber,
      operations: {...existing.operations, entry.operation},
      resultKinds: {...existing.resultKinds, entry.resultKind},
      outcomes: {...existing.outcomes, outcome},
      count: existing.count + 1,
      workOrder: _preferWorkOrder(existing.workOrder, entry.workOrder),
      occurredAt: _laterDate(existing.occurredAt, entry.occurredAt),
    );
  }
  final serials = grouped.values.toList(growable: false)
    ..sort(_compareSerialsNewestFirst);
  return serials;
}

int _compareSerialsNewestFirst(TsmLogSerial a, TsmLogSerial b) {
  final da = a.occurredAt;
  final db = b.occurredAt;
  if (da != null && db != null) {
    final byDate = db.compareTo(da);
    if (byDate != 0) return byDate;
  } else if (da != null) {
    return -1;
  } else if (db != null) {
    return 1;
  }
  return a.serialNumber.toLowerCase().compareTo(b.serialNumber.toLowerCase());
}

DateTime? _laterDate(DateTime? current, DateTime? next) {
  if (next == null) return current;
  if (current == null) return next;
  return next.isAfter(current) ? next : current;
}

TsmLogOperation? parseTsmLogOperation(String raw) {
  return _allowedOperations[_compactKey(raw)];
}

TsmLogResultKind? parseTsmLogResultKind(String raw) {
  final normalized = _foldTurkish(raw).toUpperCase();
  if (normalized.contains('ISLEM ONAYLANDI')) {
    return TsmLogResultKind.approved;
  }
  final compact = _compactKey(raw);
  if (compact.contains('SERINOYAAITVERGINOTCNOESLESMEDI')) {
    return TsmLogResultKind.serialMismatch;
  }
  return null;
}

String normalizeTsmResultMessage(String raw) {
  var text = _unescapeHtml(raw).replaceAll('\u0000', ' ').trim();
  final xmlStart = text.indexOf('<');
  if (xmlStart >= 0) text = text.substring(0, xmlStart);
  return text.replaceAll(RegExp(r'\s+'), ' ').trim();
}

const kTsmBankFilterEmpty = '__EMPTY__';
const kTsmOrderKindFilterEmpty = '__EMPTY_ORDER__';

TsmLogOperation? tsmOperationFromFilter(String value) {
  return switch (value) {
    'TERMINAL_SORGU' => TsmLogOperation.terminalSorgu,
    'ISEMRI_ACMA' => TsmLogOperation.isemriAcma,
    _ => null,
  };
}

List<String> tsmSortedResultMessages(Iterable<String> values) {
  final list = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList();
  list.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
}

String tsmResultKindLabel(TsmLogResultKind kind) {
  return switch (kind) {
    TsmLogResultKind.approved => 'İŞLEM ONAYLANDI',
    TsmLogResultKind.serialMismatch =>
      'SERİNO YA AİT VERGİNO/TCNO EŞLEŞMEDİ',
    TsmLogResultKind.other => 'Diğer',
  };
}

List<String> tsmResultMessagesForOperation(
  Iterable<TsmLogSerial> serials,
  TsmLogOperation? operation, {
  Iterable<String> catalog = const [],
}) {
  final messages = <String>{};
  for (final item in serials) {
    var added = false;
    for (final outcome in item.outcomes) {
      if (outcome.resultMessage.isEmpty) continue;
      if (operation != null && outcome.operation != operation) continue;
      messages.add(outcome.resultMessage);
      added = true;
    }
    if (!added) {
      if (operation == null || item.operations.contains(operation)) {
        messages.addAll(item.resultMessages);
        for (final kind in item.resultKinds) {
          if (kind == TsmLogResultKind.other) continue;
          messages.add(tsmResultKindLabel(kind));
        }
      }
    }
  }
  if (messages.isEmpty) messages.addAll(catalog);
  return tsmSortedResultMessages(messages);
}

List<String> extractTermSeriNos(String raw) {
  final found = <String>{};
  for (final match in _termSeriNoPattern.allMatches(raw)) {
    final value = (match.group(1) ?? match.group(2) ?? '').trim();
    if (value.isEmpty || !value.startsWith('2')) continue;
    found.add(value);
  }
  return found.toList(growable: false);
}

DateTime? parseTsmLogDateTime(String dateRaw, [String timeRaw = '']) {
  final dateText = dateRaw.trim();
  final timeText = timeRaw.trim();
  if (dateText.isEmpty && timeText.isEmpty) return null;

  final fromSerial = _excelSerialDate(dateText);
  final date = fromSerial ?? _parseDatePart(dateText) ?? _parseDatePart(timeText);
  if (date == null) return null;

  final time = _parseTimePart(timeText.isNotEmpty ? timeText : dateText);
  if (time == null) {
    return DateTime(date.year, date.month, date.day);
  }
  return DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
    time.second,
  );
}

DateTime? _excelSerialDate(String raw) {
  final value = double.tryParse(raw.replaceAll(',', '.'));
  if (value == null || value < 20000 || value > 80000) return null;
  if (RegExp(r'^\d{4}').hasMatch(raw)) return null;
  final millis = (value * 86400000).round();
  final utc = DateTime.utc(1899, 12, 30).add(Duration(milliseconds: millis));
  return DateTime(utc.year, utc.month, utc.day, utc.hour, utc.minute, utc.second);
}

DateTime? _parseDatePart(String raw) {
  final text = raw.trim();
  if (text.isEmpty) return null;
  final ymd = RegExp(
    r'^(\d{4})[./-](\d{1,2})[./-](\d{1,2})',
  ).firstMatch(text);
  if (ymd != null) {
    final year = int.parse(ymd.group(1)!);
    final month = int.parse(ymd.group(2)!);
    final day = int.parse(ymd.group(3)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day);
    }
  }
  final dotted = RegExp(
    r'^(\d{1,2})[./](\d{1,2})[./](\d{4})',
  ).firstMatch(text);
  if (dotted != null) {
    final day = int.parse(dotted.group(1)!);
    final month = int.parse(dotted.group(2)!);
    final year = int.parse(dotted.group(3)!);
    if (month >= 1 && month <= 12 && day >= 1 && day <= 31) {
      return DateTime(year, month, day);
    }
  }
  final iso = DateTime.tryParse(text.replaceFirst(' ', 'T'));
  if (iso != null) {
    final local = iso.toLocal();
    return DateTime(local.year, local.month, local.day);
  }
  return null;
}

({int hour, int minute, int second})? _parseTimePart(String raw) {
  final match = RegExp(r'(\d{1,2}):(\d{2})(?::(\d{2}))?').firstMatch(raw);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  final second = int.parse(match.group(3) ?? '0');
  if (hour > 23 || minute > 59 || second > 59) return null;
  return (hour: hour, minute: minute, second: second);
}

TsmWorkOrderDetails? parseTsmWorkOrderDetails(String raw) {
  final xml = _unescapeHtml(raw);
  if (xml.isEmpty) return null;
  final compact = _compactKey(xml);
  final looksLikeWorkOrder =
      compact.contains('ISEMRIGIRIS') ||
      compact.contains('OPENTASK') ||
      compact.contains('ISEMRIKODU') ||
      compact.contains('ACQUIREREKRANADI') ||
      compact.contains('ACQUIRERID');
  if (!looksLikeWorkOrder) return null;

  final orderCode = _xmlTag(xml, 'IsEmriKodu') ?? '';
  final description = _xmlTag(xml, 'Aciklama') ?? '';
  final details = TsmWorkOrderDetails(
    bankName: _xmlTag(xml, 'AcquirerEkranAdi') ?? '',
    acquirerId: normalizeBkmAcquirerId(_xmlTag(xml, 'AcquirerId') ?? ''),
    terminalId: _xmlTag(xml, 'TermId') ?? '',
    merchantName: _xmlTag(xml, 'IsyeriAdi') ?? '',
    merchantNo: _xmlTag(xml, 'IsyeriNo') ?? '',
    bkmMerchantId: _xmlTag(xml, 'BkmMerchantId') ?? '',
    address: [
      _xmlTag(xml, 'IsyeriAdres1'),
      _xmlTag(xml, 'IsyeriAdres2'),
      _xmlTag(xml, 'IsyeriAdres3'),
      _xmlTag(xml, 'IsyeriAdres4'),
    ].whereType<String>().where((part) => part.isNotEmpty).join(' '),
    city: _xmlTag(xml, 'IsyeriSehir') ?? '',
    district: _xmlTag(xml, 'IsyeriIlce') ?? '',
    phone: _xmlTag(xml, 'IsyeriTel') ?? '',
    orderCode: orderCode,
    description: description,
    orderKind: classifyTsmOrderKind(orderCode, description),
  );
  return details.isEmpty ? null : details;
}

TsmOrderKind classifyTsmOrderKind(String orderCode, String description) {
  final compact = _foldTurkish(description).toUpperCase();
  if (compact.contains('GERI ALIM') ||
      compact.contains('GERIALIM') ||
      compact.contains('SILME')) {
    return TsmOrderKind.geriAlim;
  }
  if (compact.contains('KURULUM')) return TsmOrderKind.kurulum;
  if (compact.contains('EKLEME')) return TsmOrderKind.ekleme;
  switch (orderCode.trim().toUpperCase()) {
    case 'K':
      return TsmOrderKind.kurulum;
    case 'TE':
      return TsmOrderKind.ekleme;
    case 'TS':
      return TsmOrderKind.geriAlim;
    default:
      return TsmOrderKind.unknown;
  }
}

String tsmOrderKindLabel(TsmOrderKind kind) {
  return switch (kind) {
    TsmOrderKind.kurulum => 'Kurulum',
    TsmOrderKind.ekleme => 'Ekleme',
    TsmOrderKind.geriAlim => 'Geri Alım',
    TsmOrderKind.unknown => '',
  };
}

TsmOrderKind? tsmOrderKindFromFilter(String filter) {
  return switch (filter) {
    'KURULUM' => TsmOrderKind.kurulum,
    'EKLEME' => TsmOrderKind.ekleme,
    'GERI_ALIM' => TsmOrderKind.geriAlim,
    _ => null,
  };
}

bool tsmIsSameDay(DateTime a, DateTime b) {
  final left = a.toLocal();
  final right = b.toLocal();
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}

DateTime tsmDateOnly(DateTime value) {
  final local = value.toLocal();
  return DateTime(local.year, local.month, local.day);
}

bool tsmDateInRange(DateTime value, DateTime? from, DateTime? to) {
  final day = tsmDateOnly(value);
  if (from != null && day.isBefore(tsmDateOnly(from))) return false;
  if (to != null && day.isAfter(tsmDateOnly(to))) return false;
  return true;
}

bool tsmLogSerialMatchesFilters(
  TsmLogSerial item, {
  String resultFilter = 'TUMU',
  String resultMessageFilter = '',
  String operationFilter = 'TUMU',
  String orderKindFilter = 'TUMU',
  String bankFilter = '',
  DateTime? dateFilter,
  DateTime? dateFrom,
  DateTime? dateTo,
  bool fileHasDates = false,
  Map<String, String> bkmNames = const {},
}) {
  final resultOk =
      resultFilter == 'TUMU' ||
      (resultFilter == 'ONAY' &&
          item.resultKinds.contains(TsmLogResultKind.approved)) ||
      (resultFilter == 'ESLESMEDI' &&
          item.resultKinds.contains(TsmLogResultKind.serialMismatch));
  final selectedOperation = tsmOperationFromFilter(operationFilter);
  final operationOk =
      selectedOperation == null ||
      item.operations.contains(selectedOperation);
  final messageOk = tsmSerialHasResultMessage(
    item,
    resultMessageFilter: resultMessageFilter,
    operation: selectedOperation,
  );
  final bankName = tsmDisplayBankName(item.workOrder, bkmNames);
  final bankOk =
      bankFilter.isEmpty ||
      (bankFilter == kTsmBankFilterEmpty && bankName.isEmpty) ||
      bankName == bankFilter;
  final orderKind = item.workOrder?.orderKind ?? TsmOrderKind.unknown;
  final orderKindOk =
      orderKindFilter == 'TUMU' ||
      (orderKindFilter == kTsmOrderKindFilterEmpty &&
          orderKind == TsmOrderKind.unknown) ||
      orderKind == tsmOrderKindFromFilter(orderKindFilter);
  final from = dateFrom ?? dateFilter;
  final to = dateTo ?? dateFilter;
  final dateOk =
      !fileHasDates ||
      (from == null && to == null) ||
      (item.occurredAt != null && tsmDateInRange(item.occurredAt!, from, to));
  return resultOk &&
      operationOk &&
      messageOk &&
      bankOk &&
      orderKindOk &&
      dateOk;
}

bool tsmOutcomeMatchesResultMessage(
  TsmLogOutcome outcome,
  String resultMessageFilter,
) {
  if (resultMessageFilter.isEmpty) return true;
  if (outcome.resultMessage == resultMessageFilter) return true;
  final wanted = parseTsmLogResultKind(resultMessageFilter);
  return wanted != null &&
      parseTsmLogResultKind(outcome.resultMessage) == wanted;
}

bool tsmSerialHasResultMessage(
  TsmLogSerial item, {
  required String resultMessageFilter,
  TsmLogOperation? operation,
}) {
  if (resultMessageFilter.isEmpty) return true;
  if (item.outcomes.isNotEmpty) {
    return item.outcomes.any((outcome) {
      if (operation != null && outcome.operation != operation) return false;
      return tsmOutcomeMatchesResultMessage(outcome, resultMessageFilter);
    });
  }
  if (operation != null && !item.operations.contains(operation)) return false;
  if (item.resultMessages.contains(resultMessageFilter)) return true;
  final wanted = parseTsmLogResultKind(resultMessageFilter);
  return wanted != null && item.resultKinds.contains(wanted);
}

String normalizeBkmAcquirerId(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final parsed = int.tryParse(value);
  return parsed == null ? value : '$parsed';
}

String tsmDisplayBankName(
  TsmWorkOrderDetails? order,
  Map<String, String> bkmNames,
) {
  if (order == null) return '';
  final id = normalizeBkmAcquirerId(order.acquirerId);
  final mapped = id.isEmpty ? null : bkmNames[id];
  if (mapped != null && mapped.isNotEmpty) return mapped;
  if (order.bankName.isNotEmpty) return order.bankName;
  if (id.isNotEmpty) return 'BKM $id';
  return '';
}

TsmWorkOrderDetails? _preferWorkOrder(
  TsmWorkOrderDetails? current,
  TsmWorkOrderDetails? next,
) {
  if (next == null) return current;
  if (current == null) return next;
  return next.richness >= current.richness ? next : current;
}

String? _xmlTag(String xml, String tag) {
  final pattern = RegExp(
    '<(?:[\\w]+:)?$tag>([^<]*)</(?:[\\w]+:)?$tag>',
    caseSensitive: false,
  );
  final value = pattern.firstMatch(xml)?.group(1)?.trim() ?? '';
  return value.isEmpty ? null : value;
}

class _TsmLogHeader {
  const _TsmLogHeader({
    required this.rowIndex,
    required this.operationIndex,
    required this.messageIndex,
    required this.paramIndex,
    required this.dateIndex,
    required this.timeIndex,
  });

  final int rowIndex;
  final int operationIndex;
  final int messageIndex;
  final int paramIndex;
  final int dateIndex;
  final int timeIndex;
}

_TsmLogHeader? _findHeader(List<List<String>> rows) {
  final limit = rows.length < 15 ? rows.length : 15;
  for (var i = 0; i < limit; i++) {
    final normalized = rows[i].map(_normalizeHeader).toList(growable: false);
    final operationIndex = _findOperationColumn(normalized);
    final messageIndex = _findMessageColumn(normalized);
    if (operationIndex >= 0 &&
        messageIndex >= 0 &&
        operationIndex != messageIndex) {
      return _TsmLogHeader(
        rowIndex: i,
        operationIndex: operationIndex,
        messageIndex: messageIndex,
        paramIndex: _findParamColumn(normalized),
        dateIndex: _findDateColumn(normalized),
        timeIndex: _findTimeColumn(normalized),
      );
    }
  }
  return null;
}

int _indexOfPreferred(List<String> headers, List<String> keys) {
  for (final key in keys) {
    final index = headers.indexOf(key);
    if (index >= 0) return index;
  }
  return -1;
}

int _findOperationColumn(List<String> headers) {
  final preferred = _indexOfPreferred(headers, const [
    'islem',
    'islem_tipi',
    'islem_turu',
    'operation',
  ]);
  if (preferred >= 0) return preferred;
  return headers.indexWhere(
    (header) =>
        header.contains('islem') &&
        !header.contains('sonuc') &&
        !header.contains('mesaj') &&
        !header.contains('kanal') &&
        !header.contains('adi'),
  );
}

int _findMessageColumn(List<String> headers) {
  final preferred = _indexOfPreferred(headers, const [
    'sonuc_mesaji',
    'sonuc_mesaj',
    'result_message',
    'sonuc',
    'mesaj',
  ]);
  if (preferred >= 0) return preferred;
  return headers.indexWhere(
    (header) =>
        (header.contains('sonuc') || header.contains('mesaj')) &&
        !header.contains('kod'),
  );
}

int _findParamColumn(List<String> headers) {
  final preferred = _indexOfPreferred(headers, const [
    'giris_parametreleri',
    'parametreler',
    'request',
    'xml',
    'giris',
  ]);
  if (preferred >= 0) return preferred;
  return headers.indexWhere((header) => header.contains('parametre'));
}

int _findDateColumn(List<String> headers) {
  final preferred = _indexOfPreferred(headers, const [
    'eklenme_tarihi',
    'ekleme_tarihi',
    'kayit_tarihi',
    'tarih',
    'date',
  ]);
  if (preferred >= 0) return preferred;
  return headers.indexWhere(
    (header) => header.contains('tarih') && !header.contains('saat'),
  );
}

int _findTimeColumn(List<String> headers) {
  final preferred = _indexOfPreferred(headers, const [
    'ekleme_saati',
    'eklenme_saati',
    'saat',
    'time',
  ]);
  if (preferred >= 0) return preferred;
  return headers.indexWhere((header) => header.contains('saat'));
}

String _cellToText(dynamic cell) {
  if (cell == null) return '';
  if (cell is DateTime) return cell.toIso8601String();
  if (cell is num) {
    if (cell >= 20000 && cell <= 80000) {
      final utc = DateTime.utc(
        1899,
        12,
        30,
      ).add(Duration(milliseconds: (cell * 86400000).round()));
      if (utc.hour == 0 && utc.minute == 0 && utc.second == 0) {
        return '${utc.year.toString().padLeft(4, '0')}-'
            '${utc.month.toString().padLeft(2, '0')}-'
            '${utc.day.toString().padLeft(2, '0')}';
      }
      return utc.toIso8601String();
    }
    return cell.toString();
  }
  final value = cell is excel.Data ? cell.value : cell;
  if (!identical(value, cell)) return _cellToText(value);
  return value.toString().trim();
}

String _cellAt(List<String> row, int index) {
  if (index < 0 || index >= row.length) return '';
  return row[index].trim();
}

String _normalizeHeader(String value) {
  var text = _foldTurkish(value).toLowerCase();
  text = text.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  text = text.replaceAll(RegExp(r'_+'), '_');
  return text.replaceAll(RegExp(r'^_+|_+$'), '');
}

String _compactKey(String value) {
  return _foldTurkish(value).toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
}

String _foldTurkish(String value) {
  return value
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'I')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'G')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 'S')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'C')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'O')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'U');
}

int _zipOffset(Uint8List bytes) {
  final limit = bytes.length < 8 ? bytes.length - 1 : 6;
  for (var i = 0; i <= limit; i++) {
    if (i + 1 < bytes.length && bytes[i] == 0x50 && bytes[i + 1] == 0x4B) {
      return i;
    }
  }
  return -1;
}

String _decodeText(Uint8List bytes) {
  if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
    return _decodeUtf16(bytes, littleEndian: true, skipBom: true);
  }
  if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
    return _decodeUtf16(bytes, littleEndian: false, skipBom: true);
  }
  if (_looksLikeUtf16Le(bytes)) {
    return _decodeUtf16(bytes, littleEndian: true, skipBom: false);
  }
  try {
    return utf8.decode(bytes);
  } catch (_) {
    return _decodeWindows1254(bytes);
  }
}

bool _looksLikeUtf16Le(Uint8List bytes) {
  final limit = bytes.length < 200 ? bytes.length : 200;
  if (limit < 8) return false;
  var zeros = 0;
  var odd = 0;
  for (var i = 1; i < limit; i += 2) {
    odd += 1;
    if (bytes[i] == 0) zeros += 1;
  }
  return odd > 0 && zeros / odd > 0.4;
}

String _decodeUtf16(
  Uint8List bytes, {
  required bool littleEndian,
  required bool skipBom,
}) {
  final start = skipBom ? 2 : 0;
  final codes = <int>[];
  for (var i = start; i + 1 < bytes.length; i += 2) {
    codes.add(
      littleEndian
          ? bytes[i] | (bytes[i + 1] << 8)
          : bytes[i + 1] | (bytes[i] << 8),
    );
  }
  return String.fromCharCodes(codes);
}

String _decodeWindows1254(Uint8List bytes) {
  const map = <int, int>{
    0xD0: 0x011E, // Ğ
    0xDD: 0x0130, // İ
    0xDE: 0x015E, // Ş
    0xF0: 0x011F, // ğ
    0xFD: 0x0131, // ı
    0xFE: 0x015F, // ş
  };
  return String.fromCharCodes(
    bytes.map((byte) => map[byte] ?? byte),
  );
}

final _htmlTablePattern = RegExp(
  r'<table\b[^>]*>([\s\S]*?)</table>',
  caseSensitive: false,
);
final _htmlRowPattern = RegExp(
  r'<tr\b[^>]*>([\s\S]*?)</tr>',
  caseSensitive: false,
);
final _htmlCellPattern = RegExp(
  r'<t[dh]\b[^>]*>([\s\S]*?)</t[dh]>',
  caseSensitive: false,
);
final _xmlRowPattern = RegExp(
  r'<Row\b[^>]*>([\s\S]*?)</Row>',
  caseSensitive: false,
);
final _xmlCellPattern = RegExp(
  r'<Cell\b[^>]*>([\s\S]*?)</Cell>',
  caseSensitive: false,
);
final _xmlDataPattern = RegExp(
  r'<Data\b[^>]*>([\s\S]*?)</Data>',
  caseSensitive: false,
);

List<List<List<String>>> _parseHtmlTables(String text) {
  final tables = <List<List<String>>>[];
  for (final tableMatch in _htmlTablePattern.allMatches(text)) {
    final rows = <List<String>>[];
    for (final rowMatch in _htmlRowPattern.allMatches(tableMatch.group(1)!)) {
      final cells = _htmlCellPattern
          .allMatches(rowMatch.group(1)!)
          .map((match) => _htmlCellText(match.group(1)!))
          .toList(growable: false);
      if (cells.isNotEmpty) rows.add(cells);
    }
    if (rows.isNotEmpty) tables.add(rows);
  }
  if (tables.isNotEmpty) return tables;

  final looseRows = <List<String>>[];
  for (final rowMatch in _htmlRowPattern.allMatches(text)) {
    final cells = _htmlCellPattern
        .allMatches(rowMatch.group(1)!)
        .map((match) => _htmlCellText(match.group(1)!))
        .toList(growable: false);
    if (cells.isNotEmpty) looseRows.add(cells);
  }
  return looseRows.isEmpty ? const [] : [looseRows];
}

List<List<String>>? _parseXmlSpreadsheet(String text) {
  if (!text.contains('<Workbook') && !text.contains('<Row')) return null;
  final rows = <List<String>>[];
  for (final rowMatch in _xmlRowPattern.allMatches(text)) {
    final cells = <String>[];
    for (final cellMatch in _xmlCellPattern.allMatches(rowMatch.group(1)!)) {
      final data = _xmlDataPattern.firstMatch(cellMatch.group(1)!);
      cells.add(_unescapeHtml(data?.group(1) ?? '').trim());
    }
    if (cells.isNotEmpty) rows.add(cells);
  }
  return rows.isEmpty ? null : rows;
}

List<List<String>>? _parseDelimited(String text) {
  final lines = const LineSplitter()
      .convert(text)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (lines.length < 2) return null;

  String delimiter = '\t';
  if (lines.first.contains(';') && !lines.first.contains('\t')) {
    delimiter = ';';
  } else if (lines.first.contains(',') && !lines.first.contains('\t')) {
    delimiter = ',';
  }
  final rows = lines
      .map((line) => line.split(delimiter).map((cell) => cell.trim()).toList())
      .toList(growable: false);
  return _findHeader(rows) == null ? null : rows;
}

String _htmlCellText(String inner) {
  var text = inner.replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n');
  text = text.replaceAll(RegExp(r'</p>', caseSensitive: false), '\n');
  return _unescapeHtml(text).trim();
}

String _unescapeHtml(String value) {
  return value
      .replaceAll('&nbsp;', ' ')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      );
}
