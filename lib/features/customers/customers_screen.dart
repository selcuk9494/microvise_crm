import 'package:excel/excel.dart' as excel;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';

import '../../app/theme/app_theme.dart';
import '../../core/api/api_client.dart';
import '../../core/auth/user_profile_provider.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import '../../core/ui/empty_state_card.dart';
import '../../core/supabase/supabase_providers.dart';
import 'customer_form_dialog.dart';
import 'customer_model.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart' if (dart.library.io) 'io_download_helper.dart';

class CustomerCompactViewNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() => state = !state;
}

final customerCompactViewProvider =
    NotifierProvider<CustomerCompactViewNotifier, bool>(
  CustomerCompactViewNotifier.new,
);

class CustomersScreen extends ConsumerStatefulWidget {
  const CustomersScreen({super.key});

  @override
  ConsumerState<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends ConsumerState<CustomersScreen> {
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

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

  Future<void> _exportCustomers() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dışarı aktarma web üzerinde desteklenir.')),
      );
      return;
    }

    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final response = await apiClient.getJson(
      '/customers',
      queryParameters: {'export': 'true', 'showPassive': 'true'},
    );
    final items = ((response['items'] as List?) ?? const [])
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList(growable: false);

    final book = excel.Excel.createExcel();
    final sheet = book.tables[book.getDefaultSheet()]!;

    excel.CellValue textCell(Object? value) =>
        excel.TextCellValue((value ?? '').toString());

    sheet.appendRow([
      textCell('id'),
      textCell('name'),
      textCell('city'),
      textCell('address'),
      textCell('director_name'),
      textCell('email'),
      textCell('vkn'),
      textCell('tckn_ms'),
      textCell('phone_1_title'),
      textCell('phone_1'),
      textCell('phone_2_title'),
      textCell('phone_2'),
      textCell('phone_3_title'),
      textCell('phone_3'),
      textCell('notes'),
      textCell('is_active'),
      textCell('created_at'),
    ]);

    for (final row in items) {
      sheet.appendRow([
        textCell(row['id']),
        textCell(row['name']),
        textCell(row['city']),
        textCell(row['address']),
        textCell(row['director_name']),
        textCell(row['email']),
        textCell(row['vkn']),
        textCell(row['tckn_ms']),
        textCell(row['phone_1_title']),
        textCell(row['phone_1']),
        textCell(row['phone_2_title']),
        textCell(row['phone_2']),
        textCell(row['phone_3_title']),
        textCell(row['phone_3']),
        textCell(row['notes']),
        textCell(row['is_active']),
        textCell(row['created_at']),
      ]);
    }

    final bytes = book.encode();
    if (bytes == null) return;
    downloadExcelFile(bytes, 'musteriler.xlsx');
  }

  Future<void> _downloadLinesGmp3Template() async {
    if (!kIsWeb) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şablon indirme web üzerinde desteklenir.')),
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

  Future<void> _importLinesAndGmp3() async {
    final apiClient = ref.read(apiClientProvider);
    final client = ref.read(supabaseClientProvider);
    if (apiClient == null && client == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
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
      lookupItems = (rows as List)
          .cast<Map<String, dynamic>>()
          .toList(growable: false);
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
      companyRows = (rows as List)
          .cast<Map<String, dynamic>>()
          .toList(growable: false);
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

    final book = excel.Excel.decodeBytes(bytes);
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

    String cellString(
      List<excel.Data?> row,
      List<String> header,
      String key,
    ) {
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
            rows = (result as List)
                .cast<Map<String, dynamic>>()
                .toList(growable: false);
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
              final existingSim =
                  (existingRow['sim_number'] ?? '').toString().trim();
              final existingOperator =
                  (existingRow['operator'] ?? '').toString().trim();

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
        final companyId = companyKey.isEmpty ? null : companyIdByName[companyKey];
        if (companyKey.isNotEmpty && (companyId ?? '').isEmpty) {
          errors.add('GMP3 satır $excelRowNo: Yazılım firması bulunamadı: $companyText');
          continue;
        }
        licenseRows.add({
          '_rowIndex': excelRowNo,
          'customer_id': customerId,
          'name': name.isEmpty ? 'GMP3 Lisansı' : name,
          'license_type': 'gmp3',
          'software_company_id': companyId,
          'registry_number': registryNumber.trim().isEmpty ? null : registryNumber.trim(),
          'starts_at': startsAt,
          'ends_at': endIso,
          'expires_at': expIso,
          'is_active': cellBool(row, gmp3Header, 'is_active'),
          'created_by': createdBy,
        });
      }
    }

    if (lineRows.isEmpty && licenseRows.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aktarılacak kayıt bulunamadı.')),
      );
      return;
    }

    if (!mounted) return;
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
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted),
              ),
              const Gap(8),
              SizedBox(
                height: 160,
                child: ListView.builder(
                  itemCount: errors.length > 30 ? 30 : errors.length,
                  itemBuilder: (context, index) => Text(
                    '• ${errors[index]}',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textMuted),
                  ),
                ),
              ),
              if (errors.length > 30)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    '… ${errors.length - 30} satır daha',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppTheme.textMuted),
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

    if (!mounted) return;
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
                    body: {'op': 'insertMany', 'table': table, 'rows': [one]},
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
        final values = (row['values'] as Map?)?.cast<String, dynamic>() ?? const {};
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
      if (mounted) Navigator.of(context).pop();
    }

    ref.invalidate(customersProvider);
    ref.invalidate(customerCitiesProvider);
    if (!mounted) return;
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

  Future<void> _importCustomers() async {
    final apiClient = ref.read(apiClientProvider);
    if (apiClient == null) return;

    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['xlsx'],
      withData: true,
    );
    final file = result?.files.firstOrNull;
    final bytes = file?.bytes;
    if (bytes == null || bytes.isEmpty) return;

    final book = excel.Excel.decodeBytes(bytes);
    final sheetName = book.tables.keys.isEmpty ? null : book.tables.keys.first;
    if (sheetName == null) return;
    final table = book.tables[sheetName];
    final rows = table?.rows ?? const [];
    if (rows.length < 2) return;

    final header = rows.first
        .map((c) => (c?.value ?? '').toString().trim().toLowerCase())
        .toList(growable: false);
    int indexOf(String key) => header.indexOf(key);
    String cellString(List<excel.Data?> row, String key) {
      final idx = indexOf(key);
      if (idx < 0 || idx >= row.length) return '';
      return (row[idx]?.value ?? '').toString().trim();
    }

    bool cellBool(List<excel.Data?> row, String key) {
      final raw = cellString(row, key).toLowerCase();
      if (raw == 'true' || raw == '1' || raw == 'aktif') return true;
      if (raw == 'false' || raw == '0' || raw == 'pasif') return false;
      return true;
    }

    int imported = 0;
    for (final row in rows.skip(1)) {
      final id = cellString(row, 'id');
      final name = cellString(row, 'name');
      if (name.isEmpty) continue;
      final values = <String, dynamic>{
        if (id.isNotEmpty) 'id': id,
        'name': name,
        'city': cellString(row, 'city').isEmpty ? null : cellString(row, 'city'),
        'address':
            cellString(row, 'address').isEmpty ? null : cellString(row, 'address'),
        'director_name': cellString(row, 'director_name').isEmpty
            ? null
            : cellString(row, 'director_name'),
        'email': cellString(row, 'email').isEmpty ? null : cellString(row, 'email'),
        'vkn': cellString(row, 'vkn').isEmpty ? null : cellString(row, 'vkn'),
        'tckn_ms':
            cellString(row, 'tckn_ms').isEmpty ? null : cellString(row, 'tckn_ms'),
        'phone_1_title': cellString(row, 'phone_1_title').isEmpty
            ? null
            : cellString(row, 'phone_1_title'),
        'phone_1':
            cellString(row, 'phone_1').isEmpty ? null : cellString(row, 'phone_1'),
        'phone_2_title': cellString(row, 'phone_2_title').isEmpty
            ? null
            : cellString(row, 'phone_2_title'),
        'phone_2':
            cellString(row, 'phone_2').isEmpty ? null : cellString(row, 'phone_2'),
        'phone_3_title': cellString(row, 'phone_3_title').isEmpty
            ? null
            : cellString(row, 'phone_3_title'),
        'phone_3':
            cellString(row, 'phone_3').isEmpty ? null : cellString(row, 'phone_3'),
        'notes': cellString(row, 'notes').isEmpty ? null : cellString(row, 'notes'),
        'is_active': cellBool(row, 'is_active'),
      };

      await apiClient.postJson(
        '/mutate',
        body: {
          'op': 'upsert',
          'table': 'customers',
          'values': values,
        },
      );
      imported += 1;
    }

    ref.invalidate(customersProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('İçe aktarıldı: $imported')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final isMobile = MediaQuery.sizeOf(context).width < 900;
    final canEdit = ref.watch(hasActionAccessProvider(kActionEditRecords));
    final canArchive =
        ref.watch(hasActionAccessProvider(kActionArchiveRecords));
    final canDelete =
        ref.watch(hasActionAccessProvider(kActionDeleteRecords));

    final filters = ref.watch(customerFiltersProvider);
    final pageDataAsync = ref.watch(customersProvider);
    final citiesAsync = ref.watch(customerCitiesProvider);
    final page = ref.watch(customerPageProvider);
    final sort = ref.watch(customerSortProvider);
    final showPassive = ref.watch(customerShowPassiveProvider);
    final compactView = ref.watch(customerCompactViewProvider);

    final nextSearch = filters.search;
    if (_searchController.text != nextSearch) {
      _searchController.text = nextSearch;
      _searchController.selection =
          TextSelection.collapsed(offset: nextSearch.length);
    }

    return AppPageLayout(
      title: 'Müşteriler',
      subtitle: 'Müşteri kayıtlarını filtreleyin, görüntüleyin ve yönetin.',
      actions: [
        OutlinedButton.icon(
          onPressed: () => ref.invalidate(customersProvider),
          icon: const Icon(Icons.refresh_rounded, size: 18),
          label: const Text('Yenile'),
        ),
        const Gap(10),
        PopupMenuButton<String>(
          tooltip: 'Aktar',
          onSelected: (value) async {
            switch (value) {
              case 'export':
                await _exportCustomers();
                break;
              case 'import':
                await _importCustomers();
                break;
              case 'template_lines_gmp3':
                await _downloadLinesGmp3Template();
                break;
              case 'import_lines_gmp3':
                await _importLinesAndGmp3();
                break;
              default:
                break;
            }
          },
          itemBuilder: (context) => const [
            PopupMenuItem(value: 'export', child: Text('Dışarı Aktar (Excel)')),
            PopupMenuItem(value: 'import', child: Text('İçeri Aktar (Excel)')),
            PopupMenuDivider(),
            PopupMenuItem(
              value: 'template_lines_gmp3',
              child: Text('Hat & GMP3 Şablon İndir'),
            ),
            PopupMenuItem(
              value: 'import_lines_gmp3',
              child: Text('Hat & GMP3 İçeri Aktar (Excel)'),
            ),
          ],
          child: const SizedBox(
            width: 44,
            height: 40,
            child: Center(child: Icon(Icons.swap_vert_rounded)),
          ),
        ),
        const Gap(10),
        FilledButton.icon(
          onPressed: canEdit
              ? () async {
                  final id = await showCreateCustomerDialog(context);
                  if (id == null || !context.mounted) return;
                  ref.invalidate(customersProvider);
                  context.go('/musteriler/$id');
                }
              : null,
          icon: const Icon(Icons.add_rounded, size: 18),
          label: const Text('Yeni Müşteri'),
        ),
      ],
      body: Builder(
        builder: (context) {
          final filterCard = AppCard(
            padding: const EdgeInsets.all(12),
            child: isMobile
                ? citiesAsync.when(
                    data: (cities) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                onChanged: (value) {
                                  ref
                                      .read(customerFiltersProvider.notifier)
                                      .setSearch(value);
                                  ref
                                      .read(customerPageProvider.notifier)
                                      .reset();
                                },
                                decoration: const InputDecoration(
                                  prefixIcon: Icon(Icons.search_rounded),
                                  hintText: 'Ara',
                                ),
                              ),
                            ),
                            const Gap(10),
                            IconButton.filledTonal(
                              onPressed: () async {
                                await showModalBottomSheet<void>(
                                  context: context,
                                  showDragHandle: true,
                                  builder: (context) => SafeArea(
                                    child: Padding(
                                      padding: const EdgeInsets.all(16),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Filtreler',
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleMedium,
                                          ),
                                          const Gap(12),
                                          DropdownButtonFormField<String?>(
                                            initialValue: filters.city,
                                            items: [
                                              const DropdownMenuItem(
                                                value: null,
                                                child: Text('Şehir: Tümü'),
                                              ),
                                              for (final c in cities)
                                                DropdownMenuItem(
                                                  value: c,
                                                  child: Text(c),
                                                ),
                                            ],
                                            onChanged: (value) {
                                              ref
                                                  .read(customerFiltersProvider
                                                      .notifier)
                                                  .setCity(value);
                                              ref
                                                  .read(customerPageProvider
                                                      .notifier)
                                                  .reset();
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Şehir',
                                            ),
                                          ),
                                          const Gap(10),
                                          SwitchListTile(
                                            value: showPassive,
                                            onChanged: (v) {
                                              ref
                                                  .read(
                                                    customerShowPassiveProvider
                                                        .notifier,
                                                  )
                                                  .set(v);
                                              ref
                                                  .read(customerPageProvider
                                                      .notifier)
                                                  .reset();
                                            },
                                            title: const Text(
                                              'Pasif kayıtları göster',
                                            ),
                                            contentPadding: EdgeInsets.zero,
                                          ),
                                          const Gap(10),
                                          DropdownButtonFormField<
                                              CustomerSortOption>(
                                            initialValue: sort,
                                            items: const [
                                              DropdownMenuItem(
                                                value: CustomerSortOption.id,
                                                child: Text('En eski'),
                                              ),
                                              DropdownMenuItem(
                                                value:
                                                    CustomerSortOption.nameAsc,
                                                child: Text('A-Z'),
                                              ),
                                              DropdownMenuItem(
                                                value:
                                                    CustomerSortOption.nameDesc,
                                                child: Text('Z-A'),
                                              ),
                                            ],
                                            onChanged: (value) {
                                              if (value == null) return;
                                              ref
                                                  .read(customerSortProvider
                                                      .notifier)
                                                  .set(value);
                                            },
                                            decoration: const InputDecoration(
                                              labelText: 'Sıralama',
                                            ),
                                          ),
                                          const Gap(10),
                                          Row(
                                            children: [
                                              Expanded(
                                                child: FilledButton.tonalIcon(
                                                  onPressed: () {
                                                    ref
                                                        .read(
                                                          customerFiltersProvider
                                                              .notifier,
                                                        )
                                                        .setSearch('');
                                                    ref
                                                        .read(
                                                          customerFiltersProvider
                                                              .notifier,
                                                        )
                                                        .setCity(null);
                                                    ref
                                                        .read(
                                                          customerShowPassiveProvider
                                                              .notifier,
                                                        )
                                                        .set(false);
                                                    ref
                                                        .read(
                                                          customerSortProvider
                                                              .notifier,
                                                        )
                                                        .set(
                                                          CustomerSortOption.id,
                                                        );
                                                    ref
                                                        .read(
                                                          customerPageProvider
                                                              .notifier,
                                                        )
                                                        .reset();
                                                    ref.invalidate(
                                                      customersProvider,
                                                    );
                                                    Navigator.of(context).pop();
                                                  },
                                                  icon: const Icon(
                                                    Icons.delete_outline_rounded,
                                                    size: 18,
                                                  ),
                                                  label: const Text('Temizle'),
                                                  style: FilledButton.styleFrom(
                                                    backgroundColor:
                                                        const Color(0xFFEF4444)
                                                            .withValues(
                                                      alpha: 0.12,
                                                    ),
                                                    foregroundColor:
                                                        const Color(0xFF7F1D1D),
                                                    minimumSize:
                                                        const Size(0, 44),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune_rounded),
                            ),
                          ],
                        ),
                        const Gap(10),
                        Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            AppBadge(
                              label: showPassive ? 'Durum: Tümü' : 'Durum: Aktif',
                              tone: showPassive
                                  ? AppBadgeTone.neutral
                                  : AppBadgeTone.success,
                            ),
                            if ((filters.city ?? '').trim().isNotEmpty)
                              AppBadge(
                                label: (filters.city ?? '').trim(),
                                tone: AppBadgeTone.primary,
                              ),
                          ],
                        ),
                      ],
                    ),
                    loading: () => const SizedBox.shrink(),
                    error: (error, stackTrace) => const SizedBox.shrink(),
                  )
                : Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: () => ref
                            .read(customerCompactViewProvider.notifier)
                            .toggle(),
                        icon: Icon(
                          compactView
                              ? Icons.view_agenda_rounded
                              : Icons.view_compact_alt_rounded,
                          size: 18,
                        ),
                        label:
                            Text(compactView ? 'Geniş Görünüm' : 'Sık Görünüm'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              AppTheme.primary.withValues(alpha: 0.12),
                          foregroundColor: AppTheme.primaryDark,
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 260,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) {
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setSearch(value);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          decoration: const InputDecoration(
                            prefixIcon: Icon(Icons.search_rounded),
                            hintText: 'Ara',
                          ),
                        ),
                      ),
                      citiesAsync.when(
                        data: (cities) => _PillDropdown<String?>(
                          value: filters.city,
                          items: [
                            const DropdownMenuItem(
                              value: null,
                              child: Text('Şehir: Tümü'),
                            ),
                            for (final c in cities)
                              DropdownMenuItem(value: c, child: Text(c)),
                          ],
                          onChanged: (value) {
                            ref
                                .read(customerFiltersProvider.notifier)
                                .setCity(value);
                            ref.read(customerPageProvider.notifier).reset();
                          },
                          backgroundColor:
                              const Color(0xFF16A34A).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF14532D),
                          icon: Icons.location_city_rounded,
                          labelBuilder: (value) => Text(
                            'Şehir: ${value?.trim().isNotEmpty ?? false ? value!.trim() : 'Tümü'}',
                          ),
                        ),
                        loading: () => const SizedBox.shrink(),
                        error: (_, _) => const SizedBox.shrink(),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          ref
                              .read(customerShowPassiveProvider.notifier)
                              .set(!showPassive);
                          ref.read(customerPageProvider.notifier).reset();
                        },
                        icon: const Icon(Icons.circle_rounded, size: 12),
                        label: Text(showPassive ? 'Durum: Tümü' : 'Durum: Aktif'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              const Color(0xFF7C3AED).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF4C1D95),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                      _PillDropdown<CustomerSortOption>(
                        value: sort,
                        items: const [
                          DropdownMenuItem(
                            value: CustomerSortOption.id,
                            child: Text('Sıralama: En eski'),
                          ),
                          DropdownMenuItem(
                            value: CustomerSortOption.nameAsc,
                            child: Text('Sıralama: A-Z'),
                          ),
                          DropdownMenuItem(
                            value: CustomerSortOption.nameDesc,
                            child: Text('Sıralama: Z-A'),
                          ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          ref.read(customerSortProvider.notifier).set(value);
                        },
                        backgroundColor:
                            const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        foregroundColor: const Color(0xFF7C2D12),
                        icon: Icons.sort_rounded,
                        labelBuilder: (value) => Text(
                          switch (value ?? CustomerSortOption.id) {
                            CustomerSortOption.id => 'Sıralama: En eski',
                            CustomerSortOption.nameAsc => 'Sıralama: A-Z',
                            CustomerSortOption.nameDesc => 'Sıralama: Z-A',
                          },
                        ),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () {
                          ref.read(customerFiltersProvider.notifier).setSearch('');
                          ref.read(customerFiltersProvider.notifier).setCity(null);
                          ref.read(customerShowPassiveProvider.notifier).set(false);
                          ref
                              .read(customerSortProvider.notifier)
                              .set(CustomerSortOption.id);
                          ref.read(customerPageProvider.notifier).reset();
                          ref.invalidate(customersProvider);
                        },
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Temizle'),
                        style: FilledButton.styleFrom(
                          backgroundColor:
                              const Color(0xFFEF4444).withValues(alpha: 0.12),
                          foregroundColor: const Color(0xFF7F1D1D),
                          minimumSize: const Size(0, 40),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                        ),
                      ),
                    ],
                  ),
          );

          Widget buildDesktop() {
            return Column(
              children: [
                filterCard,
                const Gap(12),
                Expanded(
                  child: pageDataAsync.when(
                    data: (pageData) {
                      if (pageData.items.isEmpty) {
                        return const EmptyStateCard(
                          icon: Icons.people_alt_rounded,
                          title: 'Müşteri yok',
                          message: 'Filtrelere uygun müşteri bulunamadı.',
                        );
                      }

                      return _CustomersTable(
                        items: pageData.items,
                        isAdmin: isAdmin,
                        canEdit: canEdit,
                        canArchive: canArchive,
                        canDelete: canDelete,
                        compact: compactView,
                        page: pageData.page,
                        totalPages: pageData.totalPages,
                        totalCount: pageData.totalCount,
                        hasNextPage: pageData.hasNextPage,
                        onPrevious: page <= 1
                            ? null
                            : () => ref
                                .read(customerPageProvider.notifier)
                                .previous(),
                        onNext: pageData.hasNextPage
                            ? () =>
                                ref.read(customerPageProvider.notifier).next()
                            : null,
                        onChanged: () => ref.invalidate(customersProvider),
                      );
                    },
                    loading: () => const AppCard(child: SizedBox(height: 240)),
                    error: (error, _) => AppCard(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'Müşteri listesi yüklenemedi: $error',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: AppTheme.textMuted),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          }

          Widget buildMobile() {
            return pageDataAsync.when(
              data: (pageData) {
                final items = pageData.items;

                return ListView(
                  padding: const EdgeInsets.only(bottom: 120),
                  children: [
                    filterCard,
                    const Gap(12),
                    if (items.isEmpty)
                      const EmptyStateCard(
                        icon: Icons.people_alt_rounded,
                        title: 'Müşteri yok',
                        message: 'Filtrelere uygun müşteri bulunamadı.',
                      )
                    else
                      _CustomersListMobile(
                        items: items,
                        isAdmin: isAdmin,
                        canEdit: canEdit,
                        canArchive: canArchive,
                        canDelete: canDelete,
                        onChanged: () => ref.invalidate(customersProvider),
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                      ),
                    const Gap(12),
                    AppCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: page <= 1
                                  ? null
                                  : () => ref
                                      .read(customerPageProvider.notifier)
                                      .previous(),
                              child: const Text('Önceki'),
                            ),
                          ),
                          const Gap(10),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: pageData.hasNextPage
                                  ? () => ref
                                      .read(customerPageProvider.notifier)
                                      .next()
                                  : null,
                              child: const Text('Sonraki'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
              loading: () => ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  filterCard,
                  const Gap(12),
                  const AppCard(child: SizedBox(height: 240)),
                ],
              ),
              error: (error, _) => ListView(
                padding: const EdgeInsets.only(bottom: 120),
                children: [
                  filterCard,
                  const Gap(12),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Müşteri listesi yüklenemedi: $error',
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: AppTheme.textMuted),
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          return isMobile ? buildMobile() : buildDesktop();
        },
      ),
    );
  }
}

class _CustomersListMobile extends StatelessWidget {
  const _CustomersListMobile({
    required this.items,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
    this.padding = const EdgeInsets.only(bottom: 120),
    this.shrinkWrap = false,
    this.physics,
  });

  final List<Customer> items;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: padding,
      shrinkWrap: shrinkWrap,
      physics: physics,
      itemCount: items.length,
      separatorBuilder: (context, index) => const Gap(10),
      itemBuilder: (context, index) {
        final customer = items[index];
        final vkn = customer.vkn?.trim();
        final city = customer.city?.trim();

        return AppCard(
          onTap: () => context.go('/musteriler/${customer.id}'),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: AppTheme.text,
                          ),
                    ),
                    const Gap(6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (vkn != null && vkn.isNotEmpty)
                          _MobilePill(text: 'VKN: $vkn'),
                        if (city != null && city.isNotEmpty)
                          _MobilePill(text: city.toUpperCase()),
                        _MobilePill(text: 'Hat: ${customer.activeLineCount}'),
                        _MobilePill(text: 'Lisans: ${customer.activeGmp3Count}'),
                      ],
                    ),
                  ],
                ),
              ),
              const Gap(10),
              customer.isActive
                  ? const AppBadge(label: 'Aktif', tone: AppBadgeTone.success)
                  : const AppBadge(label: 'Pasif', tone: AppBadgeTone.neutral),
              const Gap(6),
              SizedBox(
                width: 44,
                child: _CustomerRowActions(
                  customer: customer,
                  isAdmin: isAdmin,
                  canEdit: canEdit,
                  canArchive: canArchive,
                  canDelete: canDelete,
                  onChanged: onChanged,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MobilePill extends StatelessWidget {
  const _MobilePill({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppTheme.border),
      ),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: AppTheme.textMuted),
      ),
    );
  }
}

class _PillDropdown<T> extends StatelessWidget {
  const _PillDropdown({
    required this.value,
    required this.items,
    required this.onChanged,
    required this.backgroundColor,
    required this.foregroundColor,
    required this.icon,
    required this.labelBuilder,
  });

  final T? value;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;
  final Color backgroundColor;
  final Color foregroundColor;
  final IconData icon;
  final Widget Function(T? value) labelBuilder;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items,
          onChanged: onChanged,
          icon: const Icon(Icons.expand_more_rounded, size: 18),
          isDense: true,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: foregroundColor),
          dropdownColor: AppTheme.surface,
          selectedItemBuilder: (context) {
            return items
                .map(
                  (item) => Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 18, color: foregroundColor),
                      const Gap(8),
                      DefaultTextStyle(
                        style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: foregroundColor) ??
                            const TextStyle(),
                        child: labelBuilder(item.value),
                      ),
                    ],
                  ),
                )
                .toList(growable: false);
          },
        ),
      ),
    );
  }
}

class _CustomersTable extends StatelessWidget {
  const _CustomersTable({
    required this.items,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.compact,
    required this.page,
    required this.totalPages,
    required this.totalCount,
    required this.hasNextPage,
    required this.onPrevious,
    required this.onNext,
    required this.onChanged,
  });

  final List<Customer> items;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final bool compact;
  final int page;
  final int totalPages;
  final int totalCount;
  final bool hasNextPage;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final rowHeight = compact ? 54.0 : 62.0;

    return Column(
      children: [
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                Container(
                  height: 42,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceMuted,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(AppTheme.radiusMd),
                    ),
                    border: Border(bottom: BorderSide(color: AppTheme.border)),
                  ),
                  child: Row(
                    children: [
                      const SizedBox(width: 36, child: _TableHeaderCheckbox()),
                      const SizedBox(width: 360, child: _TableHeaderCell('Ad')),
                      const SizedBox(width: 140, child: _TableHeaderCell('VKN')),
                      const SizedBox(width: 140, child: _TableHeaderCell('Şehir')),
                      const SizedBox(width: 90, child: _TableHeaderCell('Hat')),
                      const SizedBox(width: 90, child: _TableHeaderCell('Lisans')),
                      const SizedBox(width: 120, child: _TableHeaderCell('Durum')),
                      const Spacer(),
                      const SizedBox(width: 44),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: items.length,
                    itemBuilder: (context, index) {
                      return _CustomerTableRow(
                        height: rowHeight,
                        customer: items[index],
                        isAdmin: isAdmin,
                        canEdit: canEdit,
                        canArchive: canArchive,
                        canDelete: canDelete,
                        onChanged: onChanged,
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const Gap(10),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Text(
                'Toplam $totalCount kayıt',
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: AppTheme.textMuted),
              ),
              const Spacer(),
              OutlinedButton.icon(
                onPressed: onPrevious,
                icon: const Icon(Icons.chevron_left_rounded),
                label: const Text('Önceki'),
              ),
              const Gap(10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppTheme.surfaceMuted,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  '$page / $totalPages',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              const Gap(10),
              FilledButton.icon(
                onPressed: onNext,
                icon: const Icon(Icons.chevron_right_rounded),
                label: const Text('Sonraki'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF475569),
          ),
    );
  }
}

class _TableHeaderCheckbox extends StatelessWidget {
  const _TableHeaderCheckbox();

  @override
  Widget build(BuildContext context) {
    return Checkbox(
      value: false,
      onChanged: null,
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _CustomerTableRow extends StatelessWidget {
  const _CustomerTableRow({
    required this.height,
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final double height;
  final Customer customer;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final initials = customer.name
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .take(2)
        .map((p) => p.characters.first.toUpperCase())
        .join();

    final vkn = customer.vkn?.trim();
    final city = customer.city?.trim();

    return InkWell(
      onTap: () => context.go('/musteriler/${customer.id}'),
      child: Container(
        height: height,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              child: Checkbox(
                value: false,
                onChanged: null,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            SizedBox(
              width: 360,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: AppTheme.primary.withValues(alpha: 0.10),
                    foregroundColor: AppTheme.primaryDark,
                    child: Text(
                      initials.isEmpty ? 'M' : initials,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w900,
                            color: AppTheme.primary,
                          ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: AppTheme.text,
                              ),
                        ),
                        if (vkn != null && vkn.isNotEmpty)
                          Text(
                            'VKN: $vkn',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                vkn == null || vkn.isEmpty ? '-' : vkn,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(
                city == null || city.isEmpty ? '-' : city.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                customer.activeLineCount.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 90,
              child: Text(
                customer.activeGmp3Count.toString(),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: customer.isActive
                    ? const AppBadge(
                        label: 'Aktif',
                        tone: AppBadgeTone.success,
                      )
                    : const AppBadge(
                        label: 'Pasif',
                        tone: AppBadgeTone.neutral,
                      ),
              ),
            ),
            const Spacer(),
            SizedBox(
              width: 44,
              child: _CustomerRowActions(
                customer: customer,
                isAdmin: isAdmin,
                canEdit: canEdit,
                canArchive: canArchive,
                canDelete: canDelete,
                onChanged: onChanged,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CustomerRowActions extends ConsumerWidget {
  const _CustomerRowActions({
    required this.customer,
    required this.isAdmin,
    required this.canEdit,
    required this.canArchive,
    required this.canDelete,
    required this.onChanged,
  });

  final Customer customer;
  final bool isAdmin;
  final bool canEdit;
  final bool canArchive;
  final bool canDelete;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final apiClient = ref.watch(apiClientProvider);

    return PopupMenuButton<String>(
      tooltip: 'İşlemler',
      onSelected: (value) async {
        switch (value) {
          case 'open':
            context.go('/musteriler/${customer.id}');
            break;
          case 'edit':
            if (!canEdit) break;
            await showEditCustomerDialog(
              context,
              initialData: CustomerFormData(
                id: customer.id,
                name: customer.name,
                city: customer.city,
                address: customer.address,
                directorName: customer.directorName,
                email: customer.email,
                vkn: customer.vkn,
                tcknMs: customer.tcknMs,
                phone1Title: customer.phone1Title,
                phone1: customer.phone1,
                phone2Title: customer.phone2Title,
                phone2: customer.phone2,
                phone3Title: customer.phone3Title,
                phone3: customer.phone3,
                notes: customer.notes,
                isActive: customer.isActive,
                locations: const [],
              ),
            );
            onChanged();
            break;
          case 'toggle':
            if (!canArchive || apiClient == null) break;
            await apiClient.postJson(
              '/mutate',
              body: {
                'op': 'updateWhere',
                'table': 'customers',
                'filters': [
                  {'col': 'id', 'op': 'eq', 'value': customer.id},
                ],
                'values': {'is_active': !customer.isActive},
              },
            );
            onChanged();
            break;
          case 'delete':
            if (!canDelete || apiClient == null) break;
            await apiClient.postJson(
              '/mutate',
              body: {'op': 'delete', 'table': 'customers', 'id': customer.id},
            );
            onChanged();
            break;
          default:
            break;
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'open', child: Text('Detayı Aç')),
        if (canEdit) const PopupMenuItem(value: 'edit', child: Text('Düzenle')),
        if (canArchive)
          PopupMenuItem(
            value: 'toggle',
            child: Text(customer.isActive ? 'Pasife Al' : 'Aktifleştir'),
          ),
        if (!customer.isActive && canDelete)
          const PopupMenuItem(value: 'delete', child: Text('Kalıcı Sil')),
      ],
      child: const Icon(Icons.more_horiz_rounded),
    );
  }
}
