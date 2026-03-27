class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.customerId,
    required this.customerName,
    this.description,
    this.city,
    required this.status,
    required this.branchId,
    this.branchName,
    required this.assignedTo,
    required this.scheduledDate,
    this.workOrderTypeId,
    this.workOrderTypeName,
    this.contactPhone,
    this.locationLink,
    this.closeNotes,
    this.sortOrder = 0,
    required this.isActive,
  });

  final String id;
  final String title;
  final String customerId;
  final String? customerName;
  final String? description;
  final String? city;
  final String status;
  final String? branchId;
  final String? branchName;
  final String? assignedTo;
  final DateTime? scheduledDate;
  final String? workOrderTypeId;
  final String? workOrderTypeName;
  final String? contactPhone;
  final String? locationLink;
  final String? closeNotes;
  final int sortOrder;
  final bool isActive;

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      description: json['description']?.toString(),
      city: json['city']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      branchId: json['branch_id']?.toString(),
      branchName: json['branch_name']?.toString(),
      assignedTo: json['assigned_to']?.toString(),
      scheduledDate: DateTime.tryParse(
        json['scheduled_date']?.toString() ?? '',
      ),
      workOrderTypeId: json['work_order_type_id']?.toString(),
      workOrderTypeName: json['work_order_type_name']?.toString(),
      contactPhone: json['contact_phone']?.toString(),
      locationLink: json['location_link']?.toString(),
      closeNotes: json['close_notes']?.toString(),
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  WorkOrder copyWith({
    String? status,
    String? branchId,
    String? branchName,
    int? sortOrder,
  }) {
    return WorkOrder(
      id: id,
      title: title,
      customerId: customerId,
      customerName: customerName,
      description: description,
      city: city,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      branchName: branchName ?? this.branchName,
      assignedTo: assignedTo,
      scheduledDate: scheduledDate,
      workOrderTypeId: workOrderTypeId,
      workOrderTypeName: workOrderTypeName,
      contactPhone: contactPhone,
      locationLink: locationLink,
      closeNotes: closeNotes,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive,
    );
  }
}
