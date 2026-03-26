class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.customerId,
    required this.customerName,
    required this.status,
    required this.branchId,
    required this.assignedTo,
    required this.scheduledDate,
    required this.isActive,
  });

  final String id;
  final String title;
  final String customerId;
  final String? customerName;
  final String status;
  final String? branchId;
  final String? assignedTo;
  final DateTime? scheduledDate;
  final bool isActive;

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerId: json['customer_id'].toString(),
      customerName: json['customer_name']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      branchId: json['branch_id']?.toString(),
      assignedTo: json['assigned_to']?.toString(),
      scheduledDate: DateTime.tryParse(json['scheduled_date']?.toString() ?? ''),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  WorkOrder copyWith({String? status, String? branchId}) {
    return WorkOrder(
      id: id,
      title: title,
      customerId: customerId,
      customerName: customerName,
      status: status ?? this.status,
      branchId: branchId ?? this.branchId,
      assignedTo: assignedTo,
      scheduledDate: scheduledDate,
      isActive: isActive,
    );
  }
}
