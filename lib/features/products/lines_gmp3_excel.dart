import 'package:excel/excel.dart' as excel;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/platform/pick_xlsx.dart';
import '../../core/supabase/supabase_providers.dart';
import '../customers/customers_providers.dart';
import '../customers/web_download_helper.dart'
    if (dart.library.io) '../customers/io_download_helper.dart';

String _normalizeHeader(String value) {
  var t = value.trim().toLowerCase();
  t = t
      .replaceAll('ı', 'i')
      .replaceAll('İ', 'i')
      .replaceAll('ğ', 'g')
      .replaceAll('Ğ', 'g')
      .replaceAll('ş', 's')
      .replaceAll('Ş', 's')
      .replaceAll('ç', 'c')
      .replaceAll('Ç', 'c')
      .replaceAll('ö', 'o')
      .replaceAll('Ö', 'o')
      .replaceAll('ü', 'u')
      .replaceAll('Ü', 'u');
  t = t.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  t = t.replaceAll(RegExp(r'_+'), '_');
  t = t.replaceAll(RegExp(r'^_+|_+$'), '');
  return t;
}

String _coerceNumberLike(String raw) {
  final t = raw.trim();
  if (t.isEmpty) return '';
  final lowered = t.toLowerCase();
  if (lowered.contains('e')) {
    final d = double.tryParse(lowered.replaceAll('+', ''));
    if (d != null && d.isFinite) {
      return d.round().toString();
    }
  }
  if (RegExp(r'^\d+\.0+$').hasMatch(t)) {
    return t.split('.').first;
  }
  return t;
}

String _digitsOnly(String raw) => raw.replaceAll(RegExp(r'[^0-9]'), '');

String _normalizeVkn(String raw) {
  final coerced = _coerceNumberLike(raw);
  return _digitsOnly(coerced);
}

String? _toIsoDate(Object? raw) {
  if (raw == null) return null;
  if (raw is DateTime) {
    final y = raw.year.toString().padLeft(4, '0');
    final m = raw.month.toString().padLeft(2, '0');
    final d = raw.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  if (raw is num && raw.isFinite) {
    final days = raw.round();
    if (days > 0) {
      final base = DateTime(1899, 12, 30);
      final dt = base.add(Duration(days: days));
      final y = dt.year.toString().padLeft(4, '0');
      final m = dt.month.toString().padLeft(2, '0');
      final d = dt.day.toString().padLeft(2, '0');
      return '$y-$m-$d';
    }
  }
  final text = _coerceNumberLike(raw.toString());
  if (text.isEmpty) return null;
  final normalized = text.replaceAll('/', '.');
  final iso = DateTime.tryParse(normalized);
  if (iso != null) {
    final y = iso.year.toString().padLeft(4, '0');
    final m = iso.month.toString().padLeft(2, '0');
    final d = iso.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
  final parts = normalized.split('.');
  if (parts.length == 3) {
    final d = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    final y = int.tryParse(parts[2]);
    if (d != null && m != null && y != null) {
      final dt = DateTime(y, m, d);
      final yy = dt.year.toString().padLeft(4, '0');
      final mm = dt.month.toString().padLeft(2, '0');
      final dd = dt.day.toString().padLeft(2, '0');
      return '$yy-$mm-$dd';
    }
  }
  return null;
}

Future<void> downloadLinesGmp3Template(BuildContext context) async {
  if (!kIsWeb) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Şablon indirme web üzerinde desteklenir.'),
      ),
    );
    return;
  }

  final book = excel.Excel.createExcel();
  final hats = book['Hatlar'];
  final gmp3 = book['GMP3'];

  excel.CellValue t(Object? v) => excel.TextCellValue((v ?? '').toString());

  hats.appendRow([
    t('customer_vkn'),
    t('line_number'),
    t('operator'),
    t('line_label'),
    t('sim_no'),
    t('starts_at'),
    t('ends_at'),
    t('expires_at'),
    t('is_active'),
  ]);
  hats.appendRow([
    t('0000000000'),
    t('0533XXXXXXX'),
    t('turkcell'),
    t('Hat Satışı'),
    t('SIM123'),
    t('2026-01-01'),
    t('2026-12-31'),
    t('2026-12-31'),
    t('true'),
  ]);

  gmp3.appendRow([
    t('customer_vkn'),
    t('license_name'),
    t('software_company'),
    t('registry_number'),
    t('starts_at'),
    t('ends_at'),
    t('expires_at'),
    t('is_active'),
  ]);
  gmp3.appendRow([
    t('0000000000'),
    t('GMP3 Lisansı'),
    t('Örn: Microvise'),
    t('SICIL123456'),
    t('2026-01-01'),
    t('2026-12-31'),
    t('2026-12-31'),
    t('true'),
  ]);

  final bytes = book.encode();
  if (bytes == null) return;
  downloadExcelFile(bytes, 'hat_gmp3_sablon.xlsx');
}

Future<void> importLinesAndGmp3Excel({
  required BuildContext context,
  required WidgetRef ref,
  VoidCallback? onImported,
}) async {
  try {
    await _importLinesAndGmp3Excel(
      context: context,
      ref: ref,
      onImported: onImported,
    );
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('İçe aktarma başarısız: $e')),
    );
  }
}

Future<void> _importLinesAndGmp3Excel({
  required BuildContext context,
  required WidgetRef ref,
  VoidCallback? onImported,
}) async {
  final apiClient = ref.read(apiClientProvider);
  final client = ref.read(supabaseClientProvider);
  if (apiClient == null && client == null) return;

  final picked = await pickXlsxFile();
  final bytes = picked?.bytes;
  if (bytes == null || bytes.isEmpty) return;

  List<Map<String, dynamic>> lookupItems;
  if (apiClient != null) {
    final lookupResponse = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'customers_lookup_vkn'},
    );
    lookupItems = ((lookupResponse['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  } else {
    final rows = await client!
        .from('customers')
        .select('id,name,vkn,is_active')
        .order('name', ascending: true)
        .limit(5000);
    lookupItems = (rows as List).cast<Map<String, dynamic>>().toList(
      growable: false,
    );
  }

  final customerIdByVkn = <String, String>{};
  for (final row in lookupItems) {
    final vkn = _normalizeVkn((row['vkn'] ?? '').toString());
    final id = (row['id'] ?? '').toString().trim();
    if (vkn.isEmpty || id.isEmpty) continue;
    customerIdByVkn[vkn] = id;
  }

  List<Map<String, dynamic>> companyRows;
  if (apiClient != null) {
    final companiesResponse = await apiClient.getJson(
      '/data',
      queryParameters: {'resource': 'definition_software_companies'},
    );
    companyRows = ((companiesResponse['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);
  } else {
    final rows = await client!
        .from('software_companies')
        .select('id,name,is_active')
        .order('name', ascending: true)
        .limit(5000);
    companyRows = (rows as List).cast<Map<String, dynamic>>().toList(
      growable: false,
    );
  }
  String normalizeCompanyName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  final companyIdByName = <String, String>{};
  for (final row in companyRows) {
    final name = normalizeCompanyName((row['name'] ?? '').toString());
    final id = (row['id'] ?? '').toString().trim();
    if (name.isEmpty || id.isEmpty) continue;
    companyIdByName[name] = id;
  }

  late final excel.Excel book;
  try {
    book = excel.Excel.decodeBytes(bytes);
  } catch (_) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Excel okunamadı. Lütfen .xlsx dosyası seçin.'),
      ),
    );
    return;
  }
  excel.Sheet? findSheet(Set<String> keys) {
    for (final name in book.tables.keys) {
      final lower = name.trim().toLowerCase();
      for (final key in keys) {
        if (lower.contains(key)) return book.tables[name];
      }
    }
    return null;
  }

  final linesSheet = findSheet({'hat', 'line'});
  final gmp3Sheet = findSheet({'gmp3', 'lisans', 'license'});

  List<List<excel.Data?>> safeRows(excel.Sheet? sheet) {
    if (sheet == null) return const [];
    return sheet.rows;
  }

  List<String> headerOf(List<List<excel.Data?>> rows) {
    if (rows.isEmpty) return const [];
    return rows.first
        .map((c) => _normalizeHeader((c?.value ?? '').toString()))
        .toList(growable: false);
  }

  int indexOf(List<String> header, String key) =>
      header.indexOf(_normalizeHeader(key));

  int indexOfAny(List<String> header, List<String> keys) {
    for (final k in keys) {
      final idx = indexOf(header, k);
      if (idx >= 0) return idx;
    }
    return -1;
  }

  String cellString(List<excel.Data?> row, List<String> header, String key) {
    final idx = indexOf(header, key);
    if (idx < 0 || idx >= row.length) return '';
    return _coerceNumberLike((row[idx]?.value ?? '').toString()).trim();
  }

  String cellStringAny(
    List<excel.Data?> row,
    List<String> header,
    List<String> keys,
  ) {
    final idx = indexOfAny(header, keys);
    if (idx < 0 || idx >= row.length) return '';
    return _coerceNumberLike((row[idx]?.value ?? '').toString()).trim();
  }

  bool cellBool(
    List<excel.Data?> row,
    List<String> header,
    String key, {
    bool defaultValue = true,
  }) {
    final raw = cellString(row, header, key).toLowerCase();
    if (raw.isEmpty) return defaultValue;
    if (raw == 'true' || raw == '1' || raw == 'aktif' || raw == 'yes') {
      return true;
    }
    if (raw == 'false' || raw == '0' || raw == 'pasif' || raw == 'no') {
      return false;
    }
    return defaultValue;
  }

  String? cellDateIso(
    List<excel.Data?> row,
    List<String> header,
    String key,
  ) {
    final idx = indexOf(header, key);
    if (idx < 0 || idx >= row.length) return null;
    return _toIsoDate(row[idx]?.value);
  }

  String? normalizeOperator(String raw) {
    final t = raw.trim().toLowerCase();
    if (t.isEmpty) return null;
    if (t.contains('turkcell')) return 'turkcell';
    if (t.contains('telsim') || t.contains('vodafone')) return 'telsim';
    return null;
  }

  final profile = await ref.read(currentUserProfileProvider.future);
  final createdBy = (profile?.id ?? '').trim().isEmpty ? null : profile!.id;

  final today = DateTime.now();
  final defaultStart = DateTime(today.year, today.month, today.day);
  final defaultEnd = DateTime(today.year, 12, 31);
  final defaultStartIso =
      '${defaultStart.year.toString().padLeft(4, '0')}-${defaultStart.month.toString().padLeft(2, '0')}-${defaultStart.day.toString().padLeft(2, '0')}';
  final defaultEndIso =
      '${defaultEnd.year.toString().padLeft(4, '0')}-${defaultEnd.month.toString().padLeft(2, '0')}-${defaultEnd.day.toString().padLeft(2, '0')}';

  final errors = <String>[];
  final lineRows = <Map<String, dynamic>>[];
  final licenseRows = <Map<String, dynamic>>[];

  final linesRows = safeRows(linesSheet);
  final linesHeader = headerOf(linesRows);
  if (linesRows.length >= 2 && linesHeader.isNotEmpty) {
    for (var rowIndex = 1; rowIndex < linesRows.length; rowIndex++) {
      final row = linesRows[rowIndex];
      final excelRowNo = rowIndex + 1;
      final vkn = _normalizeVkn(
        cellStringAny(row, linesHeader, [
          'customer_vkn',
          'vkn',
          'customer_vat',
          'vergi_no',
          'vergi',
        ]),
      );
      final customerId = customerIdByVkn[vkn];
      if ((customerId ?? '').isEmpty) {
        if (vkn.isNotEmpty) {
          errors.add('Hat satır $excelRowNo: VKN bulunamadı: $vkn');
        }
        continue;
      }
      final number = _digitsOnly(
        _coerceNumberLike(
          cellStringAny(row, linesHeader, [
            'line_number',
            'number',
            'hat_numarasi',
            'hat_no',
            'hat',
          ]),
        ),
      );
      if (number.isEmpty) continue;

      final startsAt =
          cellDateIso(row, linesHeader, 'starts_at') ?? defaultStartIso;
      final endsAt = cellDateIso(row, linesHeader, 'ends_at');
      final expiresAt = cellDateIso(row, linesHeader, 'expires_at');
      final endIso = endsAt ?? expiresAt ?? defaultEndIso;
      final expIso = expiresAt ?? endIso;

      final label = cellStringAny(row, linesHeader, [
        'line_label',
        'label',
        'etiket',
      ]);
      final sim = _coerceNumberLike(
        cellStringAny(row, linesHeader, [
          'sim_number',
          'sim_no',
          'sim',
          'sim_numarasi',
        ]),
      );
      final operatorRaw = cellStringAny(row, linesHeader, [
        'operator',
        'operator_name',
        'operatör',
        'operator',
      ]);
      final operator = normalizeOperator(operatorRaw);

      lineRows.add({
        '_rowIndex': excelRowNo,
        'customer_id': customerId,
        'label': label.isEmpty ? null : label,
        'number': number,
        'operator': operator,
        'sim_number': sim.isEmpty ? null : sim,
        'starts_at': startsAt,
        'ends_at': endIso,
        'expires_at': expIso,
        'is_active': cellBool(row, linesHeader, 'is_active'),
        'created_by': createdBy,
      });
    }
  }

  final lineUpdates = <Map<String, dynamic>>[];
  if (lineRows.isNotEmpty) {
    try {
      final uniqueCustomerIds = lineRows
          .map((e) => (e['customer_id'] ?? '').toString().trim())
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList(growable: false);

      if (uniqueCustomerIds.isNotEmpty) {
        List<Map<String, dynamic>> rows;
        if (apiClient != null) {
          final response = await apiClient.getJson(
            '/data',
            queryParameters: {
              'resource': 'customer_lines_numbers_bulk',
              'ids': uniqueCustomerIds.join(','),
            },
          );
          rows = ((response['items'] as List?) ?? const [])
              .whereType<Map>()
              .map((e) => e.cast<String, dynamic>())
              .toList(growable: false);
        } else {
          final result = await client!
              .from('lines')
              .select('id,customer_id,number,sim_number,operator')
              .inFilter('customer_id', uniqueCustomerIds)
              .limit(5000);
          rows = (result as List).cast<Map<String, dynamic>>().toList(
            growable: false,
          );
        }

        final existingByKey = <String, Map<String, dynamic>>{};
        for (final row in rows) {
          final cid = (row['customer_id'] ?? '').toString().trim();
          final num = (row['number'] ?? '').toString().trim();
          final id = (row['id'] ?? '').toString().trim();
          if (cid.isEmpty || num.isEmpty) continue;
          if (id.isEmpty) continue;
          existingByKey['$cid::$num'] = row;
        }

        final seenInImport = <String>{};
        final filtered = <Map<String, dynamic>>[];
        for (final row in lineRows) {
          final cid = (row['customer_id'] ?? '').toString().trim();
          final num = (row['number'] ?? '').toString().trim();
          if (cid.isEmpty || num.isEmpty) continue;
          final key = '$cid::$num';
          if (seenInImport.contains(key)) {
            final rn = row['_rowIndex'];
            errors.add('Hat satır $rn: excel içinde tekrar, atlandı: $num');
            continue;
          }
          seenInImport.add(key);
          final existingRow = existingByKey[key];
          if (existingRow != null) {
            final rn = row['_rowIndex'];
            final sim = (row['sim_number'] ?? '').toString().trim();
            final operator = (row['operator'] ?? '').toString().trim();
            final existingSim = (existingRow['sim_number'] ?? '')
                .toString()
                .trim();
            final existingOperator = (existingRow['operator'] ?? '')
                .toString()
                .trim();

            final updateValues = <String, dynamic>{};
            if (sim.isNotEmpty && sim != existingSim) {
              updateValues['sim_number'] = sim;
            }
            if (operator.isNotEmpty && operator != existingOperator) {
              updateValues['operator'] = operator;
            }

            if (updateValues.isNotEmpty) {
              lineUpdates.add({
                '_rowIndex': rn,
                'id': (existingRow['id'] ?? '').toString(),
                'number': num,
                'values': updateValues,
              });
            } else {
              errors.add('Hat satır $rn: aynı numara var, atlandı: $num');
            }
            continue;
          }
          filtered.add(row);
        }
        lineRows
          ..clear()
          ..addAll(filtered);
      }
    } catch (_) {}
  }

  final gmp3Rows = safeRows(gmp3Sheet);
  final gmp3Header = headerOf(gmp3Rows);
  if (gmp3Rows.length >= 2 && gmp3Header.isNotEmpty) {
    for (var rowIndex = 1; rowIndex < gmp3Rows.length; rowIndex++) {
      final row = gmp3Rows[rowIndex];
      final excelRowNo = rowIndex + 1;
      final vkn = _normalizeVkn(
        cellStringAny(row, gmp3Header, [
          'customer_vkn',
          'vkn',
          'customer_vat',
          'vergi_no',
          'vergi',
        ]),
      );
      final customerId = customerIdByVkn[vkn];
      if ((customerId ?? '').isEmpty) {
        if (vkn.isNotEmpty) {
          errors.add('GMP3 satır $excelRowNo: VKN bulunamadı: $vkn');
        }
        continue;
      }

      final startsAt =
          cellDateIso(row, gmp3Header, 'starts_at') ?? defaultStartIso;
      final endsAt = cellDateIso(row, gmp3Header, 'ends_at');
      final expiresAt = cellDateIso(row, gmp3Header, 'expires_at');
      final endIso = endsAt ?? expiresAt ?? defaultEndIso;
      final expIso = expiresAt ?? endIso;

      final name = cellStringAny(row, gmp3Header, [
        'license_name',
        'name',
        'lisans_adi',
        'lisans',
      ]);
      final companyText = cellStringAny(row, gmp3Header, [
        'software_company',
        'yazilim_firmasi',
        'yazılım firması',
        'firma',
      ]);
      final registryNumber = cellStringAny(row, gmp3Header, [
        'registry_number',
        'sicil',
        'sicil_no',
      ]);
      final companyKey = normalizeCompanyName(companyText);
      final companyId = companyKey.isEmpty
          ? null
          : companyIdByName[companyKey];
      if (companyKey.isNotEmpty && (companyId ?? '').isEmpty) {
        errors.add(
          'GMP3 satır $excelRowNo: Yazılım firması bulunamadı: $companyText',
        );
        continue;
      }
      licenseRows.add({
        '_rowIndex': excelRowNo,
        'customer_id': customerId,
        'name': name.isEmpty ? 'GMP3 Lisansı' : name,
        'license_type': 'gmp3',
        'software_company_id': companyId,
        'registry_number': registryNumber.trim().isEmpty
            ? null
            : registryNumber.trim(),
        'starts_at': startsAt,
        'ends_at': endIso,
        'expires_at': expIso,
        'is_active': cellBool(row, gmp3Header, 'is_active'),
        'created_by': createdBy,
      });
    }
  }

  if (lineRows.isEmpty && licenseRows.isEmpty) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Aktarılacak kayıt bulunamadı.')),
    );
    return;
  }

  if (!context.mounted) return;
  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => AlertDialog(
      title: const Text('Excel İçe Aktar'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Hat: ${lineRows.length}'),
          if (lineUpdates.isNotEmpty)
            Text('Hat Güncelleme: ${lineUpdates.length}'),
          Text('GMP3: ${licenseRows.length}'),
          if (errors.isNotEmpty) ...[
            const Gap(8),
            Text(
              'Uyarı: ${errors.length} satır atlandı.',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
            ),
            const Gap(8),
            SizedBox(
              height: 160,
              child: ListView.builder(
                itemCount: errors.length > 30 ? 30 : errors.length,
                itemBuilder: (context, index) => Text(
                  '• ${errors[index]}',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
              ),
            ),
            if (errors.length > 30)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '… ${errors.length - 30} satır daha',
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppTheme.textMuted),
                ),
              ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('İçe Aktar'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  if (!context.mounted) return;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => const AlertDialog(
      content: SizedBox(
        height: 72,
        child: Center(child: CircularProgressIndicator()),
      ),
    ),
  );

  int insertedLines = 0;
  int insertedLicenses = 0;
  int updatedLines = 0;

  try {
    const chunkSize = 200;

    Future<void> insertManySafe({
      required String table,
      required List<Map<String, dynamic>> rows,
      required void Function() onInserted,
    }) async {
      if (rows.isEmpty) return;
      for (var i = 0; i < rows.length; i += chunkSize) {
        final chunk = rows.sublist(
          i,
          (i + chunkSize) > rows.length ? rows.length : (i + chunkSize),
        );
        final sanitized = [
          for (final row in chunk) {...row}..remove('_rowIndex'),
        ];
        try {
          if (apiClient != null) {
            await apiClient.postJson(
              '/mutate',
              body: {'op': 'insertMany', 'table': table, 'rows': sanitized},
            );
          } else {
            await client!.from(table).insert(sanitized);
          }
          for (var k = 0; k < sanitized.length; k++) {
            onInserted();
          }
        } catch (e) {
          for (final row in chunk) {
            final rn = row['_rowIndex'];
            try {
              final one = {...row}..remove('_rowIndex');
              if (apiClient != null) {
                await apiClient.postJson(
                  '/mutate',
                  body: {
                    'op': 'insertMany',
                    'table': table,
                    'rows': [one],
                  },
                );
              } else {
                await client!.from(table).insert(one);
              }
              onInserted();
            } catch (inner) {
              errors.add('$table satır $rn: $inner');
            }
          }
          errors.add('$table: toplu aktarım hatası: $e');
        }
      }
    }

    await insertManySafe(
      table: 'lines',
      rows: lineRows,
      onInserted: () => insertedLines += 1,
    );

    for (final row in lineUpdates) {
      final id = (row['id'] ?? '').toString().trim();
      final values =
          (row['values'] as Map?)?.cast<String, dynamic>() ?? const {};
      if (id.isEmpty || values.isEmpty) continue;
      try {
        if (apiClient != null) {
          await apiClient.postJson(
            '/mutate',
            body: {
              'op': 'updateWhere',
              'table': 'lines',
              'filters': [
                {'col': 'id', 'op': 'eq', 'value': id},
              ],
              'values': values,
            },
          );
        } else {
          await client!.from('lines').update(values).eq('id', id);
        }
        updatedLines += 1;
      } catch (e) {
        errors.add('Hat güncelleme: $id: $e');
      }
    }

    await insertManySafe(
      table: 'licenses',
      rows: licenseRows,
      onInserted: () => insertedLicenses += 1,
    );
  } finally {
    if (context.mounted) Navigator.of(context).pop();
  }

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
  onImported?.call();
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'İçe aktarıldı: Hat $insertedLines • GMP3 $insertedLicenses'
        '${updatedLines == 0 ? '' : ' • Hat Güncelleme $updatedLines'}'
        '${errors.isEmpty ? '' : ' • Uyarı/Hata ${errors.length}'}',
      ),
    ),
  );
}
