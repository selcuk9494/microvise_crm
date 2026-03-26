class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.city,
    required this.isActive,
    required this.activeLineCount,
    required this.activeGmp3Count,
  });

  final String id;
  final String name;
  final String? city;
  final bool isActive;
  final int activeLineCount;
  final int activeGmp3Count;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      activeLineCount: (json['active_line_count'] as num?)?.toInt() ?? 0,
      activeGmp3Count: (json['active_gmp3_count'] as num?)?.toInt() ?? 0,
    );
  }
}
