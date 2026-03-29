import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/supabase/supabase_providers.dart';

class ProductSerialInventoryRecord {
  const ProductSerialInventoryRecord({
    required this.id,
    required this.productId,
    required this.serialNumber,
    required this.isActive,
    this.productName,
    this.productCode,
    this.notes,
    this.consumedByApplicationFormId,
    this.consumedAt,
    this.createdAt,
  });

  final String id;
  final String productId;
  final String serialNumber;
  final String? productName;
  final String? productCode;
  final String? notes;
  final bool isActive;
  final String? consumedByApplicationFormId;
  final DateTime? consumedAt;
  final DateTime? createdAt;

  bool get isConsumed => consumedAt != null;

  factory ProductSerialInventoryRecord.fromJson(Map<String, dynamic> json) {
    final productData = json['products'];
    final product = productData is Map<String, dynamic> ? productData : null;
    return ProductSerialInventoryRecord(
      id: json['id'].toString(),
      productId: json['product_id'].toString(),
      serialNumber: (json['serial_number'] ?? '').toString(),
      productName: product?['name']?.toString(),
      productCode: product?['code']?.toString(),
      notes: json['notes']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      consumedByApplicationFormId: json['consumed_by_application_form_id']
          ?.toString(),
      consumedAt: json['consumed_at'] == null
          ? null
          : DateTime.tryParse(json['consumed_at'].toString())?.toLocal(),
      createdAt: json['created_at'] == null
          ? null
          : DateTime.tryParse(json['created_at'].toString())?.toLocal(),
    );
  }

  ProductSerialInventoryRecord copyWith({
    String? id,
    String? productId,
    String? serialNumber,
    String? productName,
    String? productCode,
    String? notes,
    bool? isActive,
    String? consumedByApplicationFormId,
    DateTime? consumedAt,
    DateTime? createdAt,
  }) {
    return ProductSerialInventoryRecord(
      id: id ?? this.id,
      productId: productId ?? this.productId,
      serialNumber: serialNumber ?? this.serialNumber,
      productName: productName ?? this.productName,
      productCode: productCode ?? this.productCode,
      notes: notes ?? this.notes,
      isActive: isActive ?? this.isActive,
      consumedByApplicationFormId:
          consumedByApplicationFormId ?? this.consumedByApplicationFormId,
      consumedAt: consumedAt ?? this.consumedAt,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class ProductSerialInventorySummary {
  const ProductSerialInventorySummary({
    required this.productId,
    required this.totalCount,
    required this.availableCount,
    required this.consumedCount,
  });

  final String productId;
  final int totalCount;
  final int availableCount;
  final int consumedCount;
}

final productSerialInventoryProvider =
    FutureProvider.autoDispose.family<List<ProductSerialInventoryRecord>, String?>((
      ref,
      productId,
    ) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null || (productId ?? '').trim().isEmpty) return const [];

      final rows = await client
          .from('product_serial_inventory')
          .select(
            'id,product_id,serial_number,notes,is_active,consumed_by_application_form_id,consumed_at,created_at',
          )
          .eq('product_id', productId!.trim())
          .eq('is_active', true)
          .isFilter('consumed_at', null)
          .order('serial_number');

      return (rows as List)
          .map(
            (row) => ProductSerialInventoryRecord.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
    });

final productSerialInventoryRecordsProvider =
    FutureProvider.autoDispose<List<ProductSerialInventoryRecord>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const [];

      final rows = await client
          .from('product_serial_inventory')
          .select(
            'id,product_id,serial_number,notes,is_active,consumed_by_application_form_id,consumed_at,created_at,products(name,code)',
          )
          .order('created_at', ascending: false)
          .limit(1000);

      return (rows as List)
          .map(
            (row) => ProductSerialInventoryRecord.fromJson(
              row as Map<String, dynamic>,
            ),
          )
          .toList(growable: false);
    });

final productSerialInventorySummaryProvider =
    FutureProvider.autoDispose<Map<String, ProductSerialInventorySummary>>((ref) async {
      final client = ref.watch(supabaseClientProvider);
      if (client == null) return const {};

      const pageSize = 1000;
      var from = 0;
      final rows = <Map<String, dynamic>>[];

      while (true) {
        final batch = await client
            .from('product_serial_inventory')
            .select('product_id,consumed_at,is_active')
            .eq('is_active', true)
            .range(from, from + pageSize - 1);
        final parsed = (batch as List)
            .map((row) => row as Map<String, dynamic>)
            .toList(growable: false);
        rows.addAll(parsed);
        if (parsed.length < pageSize) break;
        from += pageSize;
      }

      final summary = <String, ProductSerialInventorySummary>{};
      for (final row in rows) {
        final productId = row['product_id'].toString();
        final current = summary[productId] ??
            const ProductSerialInventorySummary(
              productId: '',
              totalCount: 0,
              availableCount: 0,
              consumedCount: 0,
            );
        final isConsumed = row['consumed_at'] != null;
        summary[productId] = ProductSerialInventorySummary(
          productId: productId,
          totalCount: current.totalCount + 1,
          availableCount: current.availableCount + (isConsumed ? 0 : 1),
          consumedCount: current.consumedCount + (isConsumed ? 1 : 0),
        );
      }

      return summary;
    });
