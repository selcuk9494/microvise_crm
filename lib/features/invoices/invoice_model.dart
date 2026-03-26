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
      customerName: json['customers']?['name']?.toString() ?? json['customer_name']?.toString(),
      invoiceDate: DateTime.tryParse(json['invoice_date']?.toString() ?? '') ?? DateTime.now(),
      dueDate: json['due_date'] != null ? DateTime.tryParse(json['due_date'].toString()) : null,
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: (json['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0,
      taxTotal: (json['tax_total'] as num?)?.toDouble() ?? 0,
      discountTotal: (json['discount_total'] as num?)?.toDouble() ?? 0,
      grandTotal: (json['grand_total'] as num?)?.toDouble() ?? 0,
      paidAmount: (json['paid_amount'] as num?)?.toDouble() ?? 0,
      status: json['status']?.toString() ?? 'open',
      notes: json['notes']?.toString(),
      serviceRecordId: json['service_record_id']?.toString(),
      workOrderId: json['work_order_id']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
      items: (json['invoice_items'] as List?)
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
      if (dueDate != null) 'due_date': dueDate!.toIso8601String().substring(0, 10),
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
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unit: json['unit']?.toString() ?? 'Adet',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 20,
      taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
      discountRate: (json['discount_rate'] as num?)?.toDouble() ?? 0,
      discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
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
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency']?.toString() ?? 'TRY',
      exchangeRate: (json['exchange_rate'] as num?)?.toDouble() ?? 1.0,
      paymentMethod: json['payment_method']?.toString() ?? 'cash',
      transactionDate: DateTime.tryParse(json['transaction_date']?.toString() ?? '') ?? DateTime.now(),
      invoiceId: json['invoice_id']?.toString(),
      invoiceNumber: json['invoices']?['invoice_number']?.toString(),
      description: json['description']?.toString(),
      isActive: json['is_active'] as bool? ?? true,
      createdBy: json['created_by']?.toString(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? '') ?? DateTime.now(),
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
      productType: json['product_type']?.toString() ?? 'product',
      unit: json['unit']?.toString() ?? 'Adet',
      purchasePrice: (json['purchase_price'] as num?)?.toDouble() ?? 0,
      salePrice: (json['sale_price'] as num?)?.toDouble() ?? 0,
      taxRate: (json['tax_rate'] as num?)?.toDouble() ?? 20,
      currency: json['currency']?.toString() ?? 'TRY',
      trackStock: json['track_stock'] as bool? ?? false,
      minStock: (json['min_stock'] as num?)?.toDouble() ?? 0,
      currentStock: (json['current_stock'] as num?)?.toDouble(),
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
      openingBalance: (json['opening_balance'] as num?)?.toDouble() ?? 0,
      salesTotal: (json['sales_total'] as num?)?.toDouble() ?? 0,
      purchaseTotal: (json['purchase_total'] as num?)?.toDouble() ?? 0,
      collectionsTotal: (json['collections_total'] as num?)?.toDouble() ?? 0,
      paymentsTotal: (json['payments_total'] as num?)?.toDouble() ?? 0,
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
    );
  }
}
