class Profile {
  final String id;
  final String email;
  final String? fullName;
  final String role; // 'customer', 'kitchen_owner', 'rider'
  final String? phone;
  final String? bkashNumber;
  final String? avatarUrl;
  final double? latitude;
  final double? longitude;
  final DateTime createdAt;

  Profile({
    required this.id,
    required this.email,
    this.fullName,
    required this.role,
    this.phone,
    this.bkashNumber,
    this.avatarUrl,
    this.latitude,
    this.longitude,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) {
    return Profile(
      id: json['id'] as String,
      email: json['email'] as String,
      fullName: json['full_name'] as String?,
      role: json['role'] as String,
      phone: json['phone'] as String?,
      bkashNumber: json['bkash_number'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      latitude: json['latitude'] != null ? (json['latitude'] as num).toDouble() : null,
      longitude: json['longitude'] != null ? (json['longitude'] as num).toDouble() : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'full_name': fullName,
      'role': role,
      'phone': phone,
      'bkash_number': bkashNumber,
      'avatar_url': avatarUrl,
      'latitude': latitude,
      'longitude': longitude,
      'created_at': createdAt.toIso8601String(),
    };
  }

  Profile copyWith({
    String? id,
    String? email,
    String? fullName,
    String? role,
    String? phone,
    String? bkashNumber,
    String? avatarUrl,
    double? latitude,
    double? longitude,
    DateTime? createdAt,
  }) {
    return Profile(
      id: id ?? this.id,
      email: email ?? this.email,
      fullName: fullName ?? this.fullName,
      role: role ?? this.role,
      phone: phone ?? this.phone,
      bkashNumber: bkashNumber ?? this.bkashNumber,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
