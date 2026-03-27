class Customer {
  const Customer({
    required this.id,
    required this.name,
    required this.city,
    required this.email,
    required this.phone1,
    required this.phone1Title,
    required this.phone2,
    required this.phone2Title,
    required this.phone3,
    required this.phone3Title,
    required this.vkn,
    required this.notes,
    required this.isActive,
    required this.activeLineCount,
    required this.activeGmp3Count,
  });

  final String id;
  final String name;
  final String? city;
  final String? email;
  final String? phone1;
  final String? phone1Title;
  final String? phone2;
  final String? phone2Title;
  final String? phone3;
  final String? phone3Title;
  final String? vkn;
  final String? notes;
  final bool isActive;
  final int activeLineCount;
  final int activeGmp3Count;

  factory Customer.fromJson(Map<String, dynamic> json) {
    return Customer(
      id: json['id'].toString(),
      name: (json['name'] ?? '').toString(),
      city: json['city']?.toString(),
      email: json['email']?.toString(),
      phone1: json['phone_1']?.toString(),
      phone1Title: json['phone_1_title']?.toString(),
      phone2: json['phone_2']?.toString(),
      phone2Title: json['phone_2_title']?.toString(),
      phone3: json['phone_3']?.toString(),
      phone3Title: json['phone_3_title']?.toString(),
      vkn: json['vkn']?.toString(),
      notes: json['notes']?.toString(),
      isActive: (json['is_active'] as bool?) ?? true,
      activeLineCount: (json['active_line_count'] as num?)?.toInt() ?? 0,
      activeGmp3Count: (json['active_gmp3_count'] as num?)?.toInt() ?? 0,
    );
  }
}
