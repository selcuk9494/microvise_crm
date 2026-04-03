import '../../core/format/app_date_time.dart';

bool? _parseFlexibleBool(dynamic value) {
  if (value is bool) return value;
  if (value is num) return value != 0;
  final text = value?.toString().trim().toLowerCase();
  if (text == null || text.isEmpty) return null;
  if (text == 'true' || text == 't' || text == '1' || text == 'yes') return true;
  if (text == 'false' || text == 'f' || text == '0' || text == 'no') return false;
  return null;
}

class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.customerId,
    required this.customerName,
    this.description,
    this.address,
    this.city,
    required this.status,
    required this.branchId,
    this.branchName,
    required this.assignedTo,
    this.assignedPersonnelName,
    required this.scheduledDate,
    this.createdAt,
    this.closedAt,
    this.workOrderTypeId,
    this.workOrderTypeName,
    this.contactPhone,
    this.locationLink,
    this.closeNotes,
    this.sortOrder = 0,
    this.payments = const [],
    this.paymentRequired,
    this.customerSignatureDataUrl,
    this.personnelSignatureDataUrl,
    required this.isActive,
  });

  final String id;
  final String title;
  final String customerId;
  final String? customerName;
  final String? description;
  final String? address;
  final String? city;
  final String status;
  final String? branchId;
  final String? branchName;
  final String? assignedTo;
  final String? assignedPersonnelName;
  final DateTime? scheduledDate;
  final DateTime? createdAt;
  final DateTime? closedAt;
  final String? workOrderTypeId;
  final String? workOrderTypeName;
  final String? contactPhone;
  final String? locationLink;
  final String? closeNotes;
  final int sortOrder;
  final List<WorkOrderPayment> payments;
  final bool? paymentRequired;
  final String? customerSignatureDataUrl;
  final String? personnelSignatureDataUrl;
  final bool isActive;

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      description: json['description']?.toString(),
      address: json['address']?.toString(),
      city: json['city']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      assignedTo: json['assigned_to']?.toString(),
      assignedPersonnelName: json['assigned_personnel_name']?.toString(),
      scheduledDate: parseAppDateTime(json['scheduled_date']?.toString()),
      createdAt: parseAppDateTime(json['created_at']?.toString()),
      closedAt: parseAppDateTime(json['closed_at']?.toString()),
      workOrderTypeId: json['work_order_type_id']?.toString(),
      workOrderTypeName: json['work_order_type_name']?.toString(),
      contactPhone: json['contact_phone']?.toString(),
      locationLink: json['location_link']?.toString(),
      closeNotes: json['close_notes']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      payments: ((json['payments'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(WorkOrderPayment.fromJson)
          .where((payment) => payment.isActive)
          .toList(growable: false),
      paymentRequired: _parseFlexibleBool(json['payment_required']),
      customerSignatureDataUrl: json['customer_signature_data_url']?.toString(),
      personnelSignatureDataUrl:
          json['personnel_signature_data_url']?.toString(),
      isActive: _parseFlexibleBool(json['is_active']) ?? true,
    );
  }

  WorkOrder copyWith({
    String? status,
    String? branchId,
    String? branchName,
    int? sortOrder,
    bool? isActive,
    String? assignedPersonnelName,
    bool? paymentRequired,
  }) {
    return WorkOrder(
      id: id,
      title: title,
      customerId: customerId,
      customerName: customerName,
      description: description,
      address: address,
      city: city,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      assignedTo: assignedTo,
      assignedPersonnelName: assignedPersonnelName ?? this.assignedPersonnelName,
      scheduledDate: scheduledDate,
      createdAt: createdAt,
      closedAt: closedAt,
      workOrderTypeId: workOrderTypeId,
      workOrderTypeName: workOrderTypeName,
      contactPhone: contactPhone,
      locationLink: locationLink,
      closeNotes: closeNotes,
      sortOrder: sortOrder ?? this.sortOrder,
      payments: payments,
      paymentRequired: paymentRequired ?? this.paymentRequired,
      isActive: isActive ?? this.isActive,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'customer_id': customerId,
      'customer_name': customerName,
      'description': description,
      'address': address,
      'city': city,
      'status': status,
      'branch_id': branchId,
      'branch_name': branchName,
      'assigned_to': assignedTo,
      'assigned_personnel_name': assignedPersonnelName,
      'scheduled_date': scheduledDate?.toIso8601String(),
      'created_at': createdAt?.toIso8601String(),
      'closed_at': closedAt?.toIso8601String(),
      'work_order_type_id': workOrderTypeId,
      'work_order_type_name': workOrderTypeName,
      'contact_phone': contactPhone,
      'location_link': locationLink,
      'close_notes': closeNotes,
      'sort_order': sortOrder,
      'payments': payments.map((p) => p.toJson()).toList(growable: false),
      'payment_required': paymentRequired,
      'customer_signature_data_url': customerSignatureDataUrl,
      'personnel_signature_data_url': personnelSignatureDataUrl,
      'is_active': isActive,
    };
  }
}

class WorkOrderPayment {
  const WorkOrderPayment({
    required this.amount,
    required this.currency,
    required this.paidAt,
    this.description,
    this.paymentMethod,
    this.isActive = true,
  });

  final double amount;
  final String currency;
  final DateTime? paidAt;
  final String? description;
  final String? paymentMethod;
  final bool isActive;

  factory WorkOrderPayment.fromJson(Map<String, dynamic> json) {
    final amountRaw = json['amount'];
    final amount = amountRaw is num
        ? amountRaw.toDouble()
        : double.tryParse(amountRaw?.toString() ?? '') ?? 0;
    return WorkOrderPayment(
      amount: amount,
      currency: json['currency']?.toString() ?? 'TRY',
      paidAt: parseAppDateTime(json['paid_at']?.toString()),
      description: json['description']?.toString(),
      paymentMethod: json['payment_method']?.toString(),
      isActive: _parseFlexibleBool(json['is_active']) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'amount': amount,
      'currency': currency,
      'paid_at': paidAt?.toIso8601String(),
      'description': description,
      'payment_method': paymentMethod,
      'is_active': isActive,
    };
  }
}
