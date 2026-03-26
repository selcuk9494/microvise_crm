class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.city,
    required this.isActive,
  });

  final String id;
  final String name;
  final String? city;
  final bool isActive;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
    );
  }
}

