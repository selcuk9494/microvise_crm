import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;

import '../../core/supabase/supabase_providers.dart';
import 'web_download_helper.dart' if (dart.library.io) 'io_download_helper.dart';

class CustomersScreen extends ConsumerWidget {
  const CustomersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Müşteriler'),
        actions: [
          IconButton(
            onPressed: () => _exportCustomersToExcel(context, ref),
            icon: const Icon(Icons.download),
          ),
          IconButton(
            onPressed: () => _importExcel(context, ref),
            icon: const Icon(Icons.upload),
          ),
        ],
      ),
      body: const Center(
        child: Text('Müşteri listesi burada olacak'),
      ),
    );
  }
}

// ================= IMPORT MODEL =================
class _ImportCustomer {
  final String name;
  final String city;
  final String email;
  final String vkn;
  final String phone1;
  final String phone2;
  final String notes;

  const _ImportCustomer({
    required this.name,
    required this.city,
    required this.email,
    required this.vkn,
    required this.phone1,
    required this.phone2,
    required this.notes,
  });
}

// ================= EXPORT =================
Future<void> _exportCustomersToExcel(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);

  if (client == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supabase bağlantısı yok')),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final rows = await client.from('customers').select();
    final customers = rows as List;

    final file = excel.Excel.createExcel();
    final sheet = file['Müşteriler'];

    sheet.appendRow([
      excel.TextCellValue('Firma'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('Email'),
      excel.TextCellValue('Telefon'),
    ]);

    for (final c in customers) {
      sheet.appendRow([
        excel.TextCellValue(c['name'] ?? ''),
        excel.TextCellValue(c['city'] ?? ''),
        excel.TextCellValue(c['email'] ?? ''),
        excel.TextCellValue(c['phone_1'] ?? ''),
      ]);
    }

    file.delete('Sheet1');

    final bytes = file.encode();
    if (bytes == null) throw Exception('Excel hata');

    downloadExcelFile(bytes, 'musteriler.xlsx');

    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${customers.length} kayıt indirildi')),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.pop(context);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Hata: $e')),
    );
  }
}

// ================= IMPORT =================
Future<void> _importExcel(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);
  if (client == null) return;

  final result = await FilePicker.platform.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['xlsx'],
    withData: true,
  );

  if (result == null) return;

  final bytes = result.files.first.bytes!;
  final excelFile = excel.Excel.decodeBytes(bytes);
  final sheet = excelFile.tables.values.first;

  for (int i = 1; i < sheet.rows.length; i++) {
    final row = sheet.rows[i];

    await client.from('customers').insert({
      'name': row[0]?.value?.toString(),
      'city': row[1]?.value?.toString(),
      'email': row[2]?.value?.toString(),
      'phone_1': row[3]?.value?.toString(),
      'is_active': true,
    });
  }

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(content: Text('Import tamamlandı')),
  );
}
