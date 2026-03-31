import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_client.dart';

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
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null || (productId ?? '').trim().isEmpty) return const [];

      final response = await apiClient.getJson(
        '/data',
        queryParameters: {
          'resource': 'product_serial_inventory',
          'productId': productId!.trim(),
          'includeConsumed': 'false',
        },
      );
      return ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductSerialInventoryRecord.fromJson)
          .toList(growable: false);
    });

final productSerialInventoryRecordsProvider =
    FutureProvider.autoDispose<List<ProductSerialInventoryRecord>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null) return const [];
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'product_serial_inventory', 'includeConsumed': 'true'},
      );
      return ((response['items'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(ProductSerialInventoryRecord.fromJson)
          .toList(growable: false);
    });

final productSerialInventorySummaryProvider =
    FutureProvider.autoDispose<Map<String, ProductSerialInventorySummary>>((ref) async {
      final apiClient = ref.watch(apiClientProvider);
      if (apiClient == null) return const {};
      final response = await apiClient.getJson(
        '/data',
        queryParameters: {'resource': 'product_serial_inventory_summary'},
      );
      final rows = (response['items'] as List?) ?? const [];
      return {
        for (final row in rows.whereType<Map<String, dynamic>>())
          row['product_id'].toString(): ProductSerialInventorySummary(
            productId: row['product_id'].toString(),
            totalCount: (row['total_count'] as num?)?.toInt() ?? 0,
            availableCount: (row['available_count'] as num?)?.toInt() ?? 0,
            consumedCount: (row['consumed_count'] as num?)?.toInt() ?? 0,
          ),
      };
    });
