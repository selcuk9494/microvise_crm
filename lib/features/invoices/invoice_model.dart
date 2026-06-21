import '../../core/format/app_date_time.dart';

double _jsonDouble(dynamic value, {double fallback = 0}) {
  return _jsonNullableDouble(value) ?? fallback;
}

double? _jsonNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  final text = value.toString().trim();
  if (text.isEmpty) return null;
  return double.tryParse(text.replaceAll(',', '.'));
}

// Fatura Modelleri
class Invoice {
  final String id;
  final String invoiceNumber;
  final String invoiceType; // 'purchase' or 'sales'
  final String customerId;
  final String? customerName;
  final DateTime invoiceDate;
  final DateTime? dueDate;
  final String currency;
  final double exchangeRate;
  final double subtotal;
  final double taxTotal;
  final double discountTotal;
  final double grandTotal;
  final double paidAmount;
  final String status; // 'draft', 'open', 'partial', 'paid', 'cancelled'
  final String? notes;
  final String? serviceRecordId;
  final String? workOrderId;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;
  final List<InvoiceItem> items;

  const Invoice({
    required this.id,
    required this.invoiceNumber,
    required this.invoiceType,
    required this.customerId,
    this.customerName,
    required this.invoiceDate,
    this.dueDate,
    required this.currency,
    this.exchangeRate = 1.0,
    this.subtotal = 0,
    this.taxTotal = 0,
    this.discountTotal = 0,
    this.grandTotal = 0,
    this.paidAmount = 0,
    required this.status,
    this.notes,
    this.serviceRecordId,
    this.workOrderId,
    this.isActive = true,
    this.createdBy,
    required this.createdAt,
    this.items = const [],
  });

  double get remainingAmount => grandTotal - paidAmount;
  bool get isPaid => status == 'paid';
  bool get isOpen => status == 'open' || status == 'partial';

  factory Invoice.fromJson(Map<String, dynamic> json) {
    return Invoice(
      id: json['id'].toString(),
      invoiceNumber: json['invoice_number']?.toString() ?? '',
      invoiceType: json['invoice_type']?.toString() ?? 'sales',
      customerId: json['customer_id'].toString(),
      customerName:
          json['customers']?['name']?.toString() ??
          json['customer_name']?.toString(),
      invoiceDate:
          parseAppDateTime(json['invoice_date']?.toString()) ?? appNow(),
      dueDate: json['due_date'] != null
          ? parseAppDateTime(json['due_date'].toString())
          : null,
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: _jsonDouble(json['exchange_rate'], fallback: 1.0),
      subtotal: _jsonDouble(
        json['effective_subtotal'],
        fallback: _jsonDouble(json['subtotal']),
      ),
      taxTotal: _jsonDouble(
        json['effective_tax_total'],
        fallback: _jsonDouble(json['tax_total']),
      ),
      discountTotal: _jsonDouble(
        json['effective_discount_total'],
        fallback: _jsonDouble(json['discount_total']),
      ),
      grandTotal: _jsonDouble(
        json['effective_grand_total'],
        fallback: _jsonDouble(json['grand_total']),
      ),
      paidAmount: _jsonDouble(json['paid_amount']),
      status:
          json['effective_status']?.toString() ??
          json['status']?.toString() ??
          'open',
      notes: json['notes']?.toString(),
      serviceRecordId: json['service_record_id']?.toString(),
      workOrderId: json['work_order_id']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
      items:
          (json['invoice_items'] as List?)
              ?.map((e) => InvoiceItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toInsertJson() {
    return {
      'invoice_type': invoiceType,
      'customer_id': customerId,
      'invoice_date': invoiceDate.toIso8601String().substring(0, 10),
      if (dueDate != null)
        'due_date': dueDate!.toIso8601String().substring(0, 10),
      'currency': currency,
      'exchange_rate': exchangeRate,
      'status': status,
      if (notes != null && notes!.isNotEmpty) 'notes': notes,
      if (serviceRecordId != null) 'service_record_id': serviceRecordId,
      if (workOrderId != null) 'work_order_id': workOrderId,
    };
  }
}

class InvoiceItem {
  final String id;
  final String invoiceId;
  final String? productId;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double taxRate;
  final double taxAmount;
  final double discountRate;
  final double discountAmount;
  final double lineTotal;
  final int sortOrder;

  const InvoiceItem({
    required this.id,
    required this.invoiceId,
    this.productId,
    required this.description,
    this.quantity = 1,
    this.unit = 'Adet',
    this.unitPrice = 0,
    this.taxRate = 20,
    this.taxAmount = 0,
    this.discountRate = 0,
    this.discountAmount = 0,
    this.lineTotal = 0,
    this.sortOrder = 0,
  });

  factory InvoiceItem.fromJson(Map<String, dynamic> json) {
    return InvoiceItem(
      id: json['id'].toString(),
      invoiceId: json['invoice_id'].toString(),
      productId: json['product_id']?.toString(),
      description: json['description']?.toString() ?? '',
      quantity: _jsonDouble(json['quantity'], fallback: 1.0),
      unit: json['unit']?.toString() ?? 'Adet',
      unitPrice: _jsonDouble(json['unit_price']),
      taxRate: _jsonDouble(json['tax_rate'], fallback: 20),
      taxAmount: _jsonDouble(json['tax_amount']),
      discountRate: _jsonDouble(json['discount_rate']),
      discountAmount: _jsonDouble(json['discount_amount']),
      lineTotal: _jsonDouble(json['line_total']),
      sortOrder: (json['sort_order'] as int?) ?? 0,
    );
  }

  Map<String, dynamic> toInsertJson(String invoiceId) {
    final baseAmount = quantity * unitPrice;
    final discAmt = baseAmount * (discountRate / 100);
    final afterDiscount = baseAmount - discAmt;
    final taxAmt = afterDiscount * (taxRate / 100);
    final total = afterDiscount + taxAmt;

    return {
      'invoice_id': invoiceId,
      if (productId != null) 'product_id': productId,
      'description': description,
      'quantity': quantity,
      'unit': unit,
      'unit_price': unitPrice,
      'tax_rate': taxRate,
      'tax_amount': taxAmt,
      'discount_rate': discountRate,
      'discount_amount': discAmt,
      'line_total': total,
      'sort_order': sortOrder,
    };
  }

  InvoiceItem copyWith({
    String? id,
    String? invoiceId,
    String? productId,
    String? description,
    double? quantity,
    String? unit,
    double? unitPrice,
    double? taxRate,
    double? discountRate,
  }) {
    final qty = quantity ?? this.quantity;
    final price = unitPrice ?? this.unitPrice;
    final disc = discountRate ?? this.discountRate;
    final tax = taxRate ?? this.taxRate;

    final baseAmount = qty * price;
    final discAmt = baseAmount * (disc / 100);
    final afterDiscount = baseAmount - discAmt;
    final taxAmt = afterDiscount * (tax / 100);
    final total = afterDiscount + taxAmt;

    return InvoiceItem(
      id: id ?? this.id,
      invoiceId: invoiceId ?? this.invoiceId,
      productId: productId ?? this.productId,
      description: description ?? this.description,
      quantity: qty,
      unit: unit ?? this.unit,
      unitPrice: price,
      taxRate: tax,
      taxAmount: taxAmt,
      discountRate: disc,
      discountAmount: discAmt,
      lineTotal: total,
      sortOrder: sortOrder,
    );
  }
}

// Cari İşlem (Tahsilat/Ödeme)
class Transaction {
  final String id;
  final String customerId;
  final String? customerName;
  final String transactionType; // 'collection' or 'payment'
  final double amount;
  final String currency;
  final double exchangeRate;
  final String paymentMethod;
  final DateTime transactionDate;
  final String? invoiceId;
  final String? invoiceNumber;
  final String? description;
  final bool isActive;
  final String? createdBy;
  final DateTime createdAt;

  const Transaction({
    required this.id,
    required this.customerId,
    this.customerName,
    required this.transactionType,
    required this.amount,
    this.currency = 'TRY',
    this.exchangeRate = 1.0,
    this.paymentMethod = 'cash',
    required this.transactionDate,
    this.invoiceId,
    this.invoiceNumber,
    this.description,
    this.isActive = true,
    this.createdBy,
    required this.createdAt,
  });

  factory Transaction.fromJson(Map<String, dynamic> json) {
    return Transaction(
      id: json['id'].toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customers']?['name']?.toString(),
      transactionType: json['transaction_type']?.toString() ?? 'collection',
      amount: _jsonDouble(json['amount']),
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: _jsonDouble(json['exchange_rate'], fallback: 1.0),
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      transactionDate:
          parseAppDateTime(json['transaction_date']?.toString()) ?? appNow(),
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: json['invoices']?['invoice_number']?.toString(),
      description: json['description']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
    );
  }
}

// Ürün/Hizmet
class Product {
  final String id;
  final String? code;
  final String name;
  final String? description;
  final String? category;
  final String? akinsoftGroup;
  final String? akinsoftSubGroup;
  final String productType; // 'product', 'service', 'part'
  final String unit;
  final double purchasePrice;
  final double salePrice;
  final double taxRate;
  final String currency;
  final bool trackStock;
  final double minStock;
  final double? currentStock;
  final bool isActive;

  const Product({
    required this.id,
    this.code,
    required this.name,
    this.description,
    this.category,
    this.akinsoftGroup,
    this.akinsoftSubGroup,
    this.productType = 'product',
    this.unit = 'Adet',
    this.purchasePrice = 0,
    this.salePrice = 0,
    this.taxRate = 20,
    this.currency = 'TRY',
    this.trackStock = false,
    this.minStock = 0,
    this.currentStock,
    this.isActive = true,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'].toString(),
      code: json['code']?.toString(),
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      akinsoftGroup: json['akinsoft_group']?.toString(),
      akinsoftSubGroup: json['akinsoft_sub_group']?.toString(),
      productType: json['product_type']?.toString() ?? 'product',
      unit: json['unit']?.toString() ?? 'Adet',
      purchasePrice: _jsonDouble(json['purchase_price']),
      salePrice: _jsonDouble(json['sale_price']),
      taxRate: _jsonDouble(json['tax_rate'], fallback: 20),
      currency: json['currency']?.toString() ?? 'TRY',
      trackStock: json['track_stock'] as bool? ?? false,
      minStock: _jsonDouble(json['min_stock']),
      currentStock: _jsonNullableDouble(json['current_stock']),
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}

// Cari Hesap Bakiyesi
class AccountBalance {
  final String customerId;
  final String name;
  final String accountType;
  final String currency;
  final double openingBalance;
  final double salesTotal;
  final double purchaseTotal;
  final double collectionsTotal;
  final double paymentsTotal;
  final double balance;

  const AccountBalance({
    required this.customerId,
    required this.name,
    required this.accountType,
    this.currency = 'TRY',
    this.openingBalance = 0,
    this.salesTotal = 0,
    this.purchaseTotal = 0,
    this.collectionsTotal = 0,
    this.paymentsTotal = 0,
    this.balance = 0,
  });

  factory AccountBalance.fromJson(Map<String, dynamic> json) {
    return AccountBalance(
      customerId: json['customer_id'].toString(),
      name: json['name']?.toString() ?? '',
      accountType: json['account_type']?.toString() ?? 'customer',
      currency: json['currency']?.toString() ?? 'TRY',
      openingBalance: _jsonDouble(json['opening_balance']),
      salesTotal: _jsonDouble(json['sales_total']),
      purchaseTotal: _jsonDouble(json['purchase_total']),
      collectionsTotal: _jsonDouble(json['collections_total']),
      paymentsTotal: _jsonDouble(json['payments_total']),
      balance: _jsonDouble(json['balance']),
    );
  }
}

class ExchangeRate {
  const ExchangeRate({
    required this.currency,
    required this.rateToTry,
    required this.effectiveDate,
    required this.source,
    required this.isManual,
    required this.createdAt,
  });

  final String currency;
  final double rateToTry;
  final DateTime effectiveDate;
  final String source;
  final bool isManual;
  final DateTime createdAt;

  factory ExchangeRate.fromJson(Map<String, dynamic> json) {
    return ExchangeRate(
      currency: json['currency']?.toString() ?? 'TRY',
      rateToTry: _jsonDouble(json['rate_to_try'], fallback: 1.0),
      effectiveDate:
          parseAppDateTime(json['effective_date']?.toString()) ?? appNow(),
      source: json['source']?.toString() ?? 'manual',
      isManual: json['is_manual'] as bool? ?? false,
      createdAt: parseAppDateTime(json['created_at']?.toString()) ?? appNow(),
    );
  }
}
