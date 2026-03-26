// 🔥 IMPORTLAR (DÜZELTİLDİ)
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gap/gap.dart';
import 'package:go_router/go_router.dart';
import 'package:skeletonizer/skeletonizer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart' as excel;

import '../../app/theme/app_theme.dart';
import '../../core/supabase/supabase_providers.dart';
import '../../core/ui/app_badge.dart';
import '../../core/ui/app_card.dart';
import '../../core/ui/app_page_layout.dart';
import 'customers_providers.dart';
import 'web_download_helper.dart' if (dart.library.io) 'io_download_helper.dart';


// 🔥 IMPORT MODEL
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


// 🔥 EXCEL EXPORT (TAM DÜZGÜN)
Future<void> _exportCustomersToExcel(BuildContext context, WidgetRef ref) async {
  final client = ref.read(supabaseClientProvider);

  if (client == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Supabase bağlantısı bulunamadı.')),
    );
    return;
  }

  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );

  try {
    final rows = await client
        .from('customers')
        .select('name,city,email,vkn,phone_1,phone_2,phone_3,notes,is_active')
        .order('name');

    final customers = rows as List;

    final excelFile = excel.Excel.createExcel();
    final sheet = excelFile['Müşteriler'];

    // HEADER
    sheet.appendRow([
      excel.TextCellValue('Firma Adı'),
      excel.TextCellValue('Şehir'),
      excel.TextCellValue('E-posta'),
      excel.TextCellValue('VKN'),
      excel.TextCellValue('Telefon 1'),
      excel.TextCellValue('Telefon 2'),
      excel.TextCellValue('Telefon 3'),
      excel.TextCellValue('Not'),
      excel.TextCellValue('Durum'),
    ]);

    // DATA
    for (final row in customers) {
      sheet.appendRow([
        excel.TextCellValue(row['name']?.toString() ?? ''),
        excel.TextCellValue(row['city']?.toString() ?? ''),
        excel.TextCellValue(row['email']?.toString() ?? ''),
        excel.TextCellValue(row['vkn']?.toString() ?? ''),
        excel.TextCellValue(row['phone_1']?.toString() ?? ''),
        excel.TextCellValue(row['phone_2']?.toString() ?? ''),
        excel.TextCellValue(row['phone_3']?.toString() ?? ''),
        excel.TextCellValue(row['notes']?.toString() ?? ''),
        excel.TextCellValue(row['is_active'] == true ? 'Aktif' : 'Pasif'),
      ]);
    }

    excelFile.delete('Sheet1');

    final bytes = excelFile.encode();
    if (bytes == null) throw Exception('Excel oluşturulamadı');

    final now = DateTime.now();
    final filename =
        'musteriler_${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}.xlsx';

    downloadExcelFile(bytes, filename);

    if (!context.mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${customers.length} müşteri dışa aktarıldı.')),
    );
  } catch (e) {
    if (!context.mounted) return;
    Navigator.of(context).pop();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Excel oluşturulurken hata: $e')),
    );
  }
}
