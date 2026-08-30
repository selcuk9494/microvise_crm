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
import 'issued_license_type.dart';

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
  final iresto = book['iResto'];

  excel.CellValue t(Object? v) => excel.TextCellValue((v ?? '').toString());

  hats.appendRow([
    t('customer_vkn'),
    t('line_number'),
    t('operator'),
    t('line_label'),
    t('sim_no'),
    t('sicil_no'),
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
    t('SICIL123456'),
    t('2026-01-01'),
    t('2026-12-31'),
    t('2026-12-31'),
    t('true'),
  ]);

  void licenseTemplate(excel.Sheet sheet, String sampleName) {
    sheet.appendRow([
      t('customer_vkn'),
      t('license_name'),
      t('software_company'),
      t('sicil_no'),
      t('starts_at'),
      t('ends_at'),
      t('expires_at'),
      t('is_active'),
    ]);
    sheet.appendRow([
      t('0000000000'),
      t(sampleName),
      t('Örn: Microvise'),
      t('SICIL123456'),
      t('2026-01-01'),
      t('2026-12-31'),
      t('2026-12-31'),
      t('true'),
    ]);
  }

  licenseTemplate(gmp3, 'GMP3 Lisansı');
  licenseTemplate(iresto, 'iResto Lisansı');

  final bytes = book.encode();
  if (bytes == null) return;
  downloadExcelFile(bytes, 'hat_lisans_sablon.xlsx');
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
  final gmp3Sheet = findSheet({'gmp3'});
  final irestoSheet = findSheet({'iresto'});

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
      final sicil = cellStringAny(row, linesHeader, [
        'sicil_no',
        'sicil',
        'registry_number',
        'cihaz_sicil',
        'cihaz_sicil_no',
      ]).trim().toUpperCase();
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
        'registry_number': sicil.isEmpty ? null : sicil,
        'starts_at': startsAt,
        'ends_at': endIso,
        'expires_at': expIso,
        'is_active': cellBool(row, linesHeader, 'is_active'),
        'created_by': createdBy,
      });
    }
  }

  final seenLineKeys = <String>{};
  final uniqueLineRows = <Map<String, dynamic>>[];
  for (final row in lineRows) {
    final cid = (row['customer_id'] ?? '').toString().trim();
    final num = (row['number'] ?? '').toString().trim();
    if (cid.isEmpty || num.isEmpty) continue;
    final key = '$cid::$num';
    if (seenLineKeys.contains(key)) {
      errors.add('Hat satır ${row['_rowIndex']}: excel içinde tekrar, atlandı: $num');
      continue;
    }
    seenLineKeys.add(key);
    uniqueLineRows.add(row);
  }
  lineRows
    ..clear()
    ..addAll(uniqueLineRows);

  void parseLicenseSheet({
    required excel.Sheet? sheet,
    required String licenseType,
    required String typeLabel,
  }) {
    final rows = safeRows(sheet);
    final header = headerOf(rows);
    if (rows.length < 2 || header.isEmpty) return;
    for (var rowIndex = 1; rowIndex < rows.length; rowIndex++) {
      final row = rows[rowIndex];
      final excelRowNo = rowIndex + 1;
      final vkn = _normalizeVkn(
        cellStringAny(row, header, [
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
          errors.add('$typeLabel satır $excelRowNo: VKN bulunamadı: $vkn');
        }
        continue;
      }

      final startsAt = cellDateIso(row, header, 'starts_at') ?? defaultStartIso;
      final endsAt = cellDateIso(row, header, 'ends_at');
      final expiresAt = cellDateIso(row, header, 'expires_at');
      final endIso = endsAt ?? expiresAt ?? defaultEndIso;
      final expIso = expiresAt ?? endIso;

      final name = cellStringAny(row, header, [
        'license_name',
        'name',
        'lisans_adi',
        'lisans',
      ]);
      final companyText = cellStringAny(row, header, [
        'software_company',
        'yazilim_firmasi',
        'yazılım firması',
        'firma',
      ]);
      final registryNumber = cellStringAny(row, header, [
        'sicil_no',
        'sicil',
        'registry_number',
        'cihaz_sicil',
        'cihaz_sicil_no',
      ]).trim().toUpperCase();
      final typeFromCell = IssuedLicenseType.normalize(
        cellStringAny(row, header, ['license_type', 'lisans_tipi', 'tip']),
      );
      final resolvedType =
          typeFromCell == IssuedLicenseType.gmp3 ||
              typeFromCell == IssuedLicenseType.iresto
          ? typeFromCell
          : licenseType;
      final companyKey = normalizeCompanyName(companyText);
      final companyId = companyKey.isEmpty
          ? null
          : companyIdByName[companyKey];
      if (companyKey.isNotEmpty && (companyId ?? '').isEmpty) {
        errors.add(
          '$typeLabel satır $excelRowNo: Yazılım firması bulunamadı: $companyText',
        );
        continue;
      }
      licenseRows.add({
        '_rowIndex': excelRowNo,
        'customer_id': customerId,
        'name': name.isEmpty
            ? IssuedLicenseType.defaultName(resolvedType)
            : name,
        'license_type': resolvedType,
        'software_company_id': companyId,
        'registry_number': registryNumber.trim().isEmpty
            ? null
            : registryNumber.trim(),
        'starts_at': startsAt,
        'ends_at': endIso,
        'expires_at': expIso,
        'is_active': cellBool(row, header, 'is_active'),
        'created_by': createdBy,
      });
    }
  }

  parseLicenseSheet(
    sheet: gmp3Sheet,
    licenseType: IssuedLicenseType.gmp3,
    typeLabel: 'GMP3',
  );
  parseLicenseSheet(
    sheet: irestoSheet,
    licenseType: IssuedLicenseType.iresto,
    typeLabel: 'iResto',
  );

  final gmp3Count = licenseRows
      .where((e) => IssuedLicenseType.isGmp3(e['license_type']?.toString()))
      .length;
  final irestoCount = licenseRows
      .where((e) => IssuedLicenseType.isIresto(e['license_type']?.toString()))
      .length;

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
          const Text(
            'Mevcut hat, GMP3 ve iResto kayıtları silinecek, ardından Excel yüklenecek.',
          ),
          const Gap(12),
          Text('Hat: ${lineRows.length}'),
          Text('GMP3: $gmp3Count'),
          Text('iResto: $irestoCount'),
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
          child: const Text('Sil ve Yükle'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  if (!context.mounted) return;
  final navigator = Navigator.of(context, rootNavigator: true);
  final loaderRoute = DialogRoute<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      return const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('Eski kayıtlar siliniyor, Excel yükleniyor...'),
              ],
            ),
          ),
        ),
      );
    },
  );
  navigator.push(loaderRoute);
  await WidgetsBinding.instance.endOfFrame;

  int insertedLines = 0;
  int insertedLicenses = 0;
  var replaceFailed = false;

  try {
    if (apiClient != null) {
      await apiClient.postJson(
        '/mutate',
        body: {'op': 'clearIssuedLinesAndLicenses', 'confirm': 'SİL'},
        timeout: const Duration(seconds: 120),
      );
    } else {
      if (client == null) {
        throw StateError('Veritabanı bağlantısı yok.');
      }
      await client.from('invoice_items').delete().inFilter('source_table', [
        'lines',
        'licenses',
      ]);
      await client.from('line_transfers').delete().neq('id', '');
      await client.from('lines').delete().neq('id', '');
      await client.from('licenses').delete().neq('id', '');
    }

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
              timeout: const Duration(seconds: 120),
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
                  timeout: const Duration(seconds: 120),
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

    await insertManySafe(
      table: 'licenses',
      rows: licenseRows,
      onInserted: () => insertedLicenses += 1,
    );
  } catch (e) {
    replaceFailed = true;
    errors.add('Aktarım hatası: $e');
  } finally {
    if (loaderRoute.isActive) {
      navigator.removeRoute(loaderRoute);
    }
  }

  ref.invalidate(customersProvider);
  ref.invalidate(customerCitiesProvider);
  onImported?.call();
  if (!context.mounted) return;
  final failedWithoutInsert =
      replaceFailed && insertedLines == 0 && insertedLicenses == 0;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        failedWithoutInsert
            ? 'Yükleme başarısız: ${errors.last}'
            : 'Yeniden yüklendi: Hat $insertedLines • GMP3 $gmp3Count • iResto $irestoCount'
                '${errors.isEmpty ? '' : ' • Uyarı/Hata ${errors.length}'}',
      ),
    ),
  );
}
