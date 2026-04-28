class InvoicePdfAnalysisEntry {
  const InvoicePdfAnalysisEntry({
    required this.fileName,
    required this.customerName,
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.currency,
    required this.subtotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.items,
    required this.rawText,
  });

  final String fileName;
  final String customerName;
  final String invoiceNumber;
  final DateTime? invoiceDate;
  final String currency;
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final List<InvoicePdfLineItem> items;
  final String rawText;

  Map<String, Object?> toJson() {
    return {
      'fileName': fileName,
      'customerName': customerName,
      'invoiceNumber': invoiceNumber,
      'invoiceDate': invoiceDate?.toIso8601String(),
      'currency': currency,
      'subtotal': subtotal,
      'taxTotal': taxTotal,
      'grandTotal': grandTotal,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'rawText': rawText,
    };
  }

  factory InvoicePdfAnalysisEntry.fromJson(Map<String, dynamic> json) {
    return InvoicePdfAnalysisEntry(
      fileName: (json['fileName'] as String?) ?? '',
      customerName: (json['customerName'] as String?) ?? '',
      invoiceNumber: (json['invoiceNumber'] as String?) ?? '',
      invoiceDate: DateTime.tryParse((json['invoiceDate'] as String?) ?? ''),
      currency: (json['currency'] as String?) ?? 'TRY',
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      taxTotal: (json['taxTotal'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grandTotal'] as num?)?.toDouble() ?? 0,
      items: ((json['items'] as List?) ?? const [])
          .whereType<Map>()
          .map(
            (item) => InvoicePdfLineItem.fromJson(
              item.map((key, value) => MapEntry('$key', value)),
            ),
          )
          .toList(growable: false),
      rawText: (json['rawText'] as String?) ?? '',
    );
  }
}

class InvoicePdfLineItem {
  const InvoicePdfLineItem({
    required this.rowNo,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.currency,
    required this.discountRate,
    required this.discountAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.lineBaseAmount,
  });

  final int rowNo;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final String currency;
  final double discountRate;
  final double discountAmount;
  final double taxRate;
  final double taxAmount;
  final double lineBaseAmount;

  double get lineGrandTotal => lineBaseAmount + taxAmount;

  Map<String, Object?> toJson() {
    return {
      'rowNo': rowNo,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'unitPrice': unitPrice,
      'currency': currency,
      'discountRate': discountRate,
      'discountAmount': discountAmount,
      'taxRate': taxRate,
      'taxAmount': taxAmount,
      'lineBaseAmount': lineBaseAmount,
    };
  }

  factory InvoicePdfLineItem.fromJson(Map<String, dynamic> json) {
    return InvoicePdfLineItem(
      rowNo: (json['rowNo'] as num?)?.toInt() ?? 0,
      description: (json['description'] as String?) ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
      unit: (json['unit'] as String?) ?? '',
      unitPrice: (json['unitPrice'] as num?)?.toDouble() ?? 0,
      currency: (json['currency'] as String?) ?? 'TRY',
      discountRate: (json['discountRate'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discountAmount'] as num?)?.toDouble() ?? 0,
      taxRate: (json['taxRate'] as num?)?.toDouble() ?? 0,
      taxAmount: (json['taxAmount'] as num?)?.toDouble() ?? 0,
      lineBaseAmount: (json['lineBaseAmount'] as num?)?.toDouble() ?? 0,
    );
  }
}

class InvoicePdfCurrencySummary {
  const InvoicePdfCurrencySummary({
    required this.currency,
    required this.invoiceCount,
    required this.subtotal,
    required this.taxTotal,
    required this.grandTotal,
    required this.tlEquivalent,
    required this.vatGroups,
  });

  final String currency;
  final int invoiceCount;
  final double subtotal;
  final double taxTotal;
  final double grandTotal;
  final double tlEquivalent;
  final List<InvoicePdfVatGroup> vatGroups;
}

class InvoicePdfVatGroup {
  const InvoicePdfVatGroup({
    required this.taxRate,
    required this.baseAmount,
    required this.taxAmount,
    required this.grandTotal,
    required this.tlEquivalent,
  });

  final double taxRate;
  final double baseAmount;
  final double taxAmount;
  final double grandTotal;
  final double tlEquivalent;
}

class InvoicePdfAnalysisListRow {
  const InvoicePdfAnalysisListRow({
    required this.invoiceNumber,
    required this.invoiceDate,
    required this.currency,
    required this.invoiceTotal,
    required this.vatBreakdowns,
  });

  final String invoiceNumber;
  final DateTime? invoiceDate;
  final String currency;
  final double invoiceTotal;
  final List<InvoicePdfAnalysisVatBreakdown> vatBreakdowns;

  double taxAmountForRate(double rate) {
    for (final item in vatBreakdowns) {
      if (item.taxRate == rate) return item.taxAmount;
    }
    return 0;
  }

  double get totalTaxAmount =>
      vatBreakdowns.fold<double>(0, (sum, item) => sum + item.taxAmount);
}

class InvoicePdfAnalysisVatBreakdown {
  const InvoicePdfAnalysisVatBreakdown({
    required this.baseAmount,
    required this.taxRate,
    required this.taxAmount,
    required this.grandTotal,
  });

  final double baseAmount;
  final double taxRate;
  final double taxAmount;
  final double grandTotal;
}

class InvoicePdfFxRateRule {
  const InvoicePdfFxRateRule({
    required this.id,
    required this.currency,
    required this.startDate,
    required this.endDate,
    required this.rateToTry,
  });

  final String id;
  final String currency;
  final DateTime startDate;
  final DateTime endDate;
  final double rateToTry;

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'currency': currency,
      'startDate': startDate.toIso8601String(),
      'endDate': endDate.toIso8601String(),
      'rateToTry': rateToTry,
    };
  }

  factory InvoicePdfFxRateRule.fromJson(Map<String, dynamic> json) {
    return InvoicePdfFxRateRule(
      id: (json['id'] as String?) ?? '',
      currency: (json['currency'] as String?) ?? 'USD',
      startDate:
          DateTime.tryParse((json['startDate'] as String?) ?? '') ??
          DateTime.now(),
      endDate:
          DateTime.tryParse((json['endDate'] as String?) ?? '') ??
          DateTime.now(),
      rateToTry: (json['rateToTry'] as num?)?.toDouble() ?? 0,
    );
  }
}
