class WorkOrder {
  const WorkOrder({
    required this.id,
    required this.title,
    required this.customerName,
    required this.status,
    required this.isActive,
  });

  final String id;
  final String title;
  final String? customerName;
  final String status;
  final bool isActive;

  factory WorkOrder.fromJson(Map<String, dynamic> json) {
    return WorkOrder(
      id: json['id'].toString(),
      title: (json['title'] ?? '').toString(),
      customerName: json['customer_name']?.toString(),
      status: (json['status'] ?? 'open').toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }

  WorkOrder copyWith({String? status}) {
    return WorkOrder(
      id: id,
      title: title,
      customerName: customerName,
      status: status ?? this.status,
      isActive: isActive,
    );
  }
}

