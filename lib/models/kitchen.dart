class Kitchen {
  final String id;
  final String ownerId;
  final String name;
  final String? description;
  final String? address;
  final String? imageUrl;
  final double latitude;
  final double longitude;
  final bool isActive;
  final DateTime createdAt;

  /// Owner's profile photo — only populated when fetched with the
  /// `profiles:owner_id(avatar_url)` embed (e.g. loadNearbyKitchens). Used
  /// as a fallback cover image before the kitchen sets its own photo.
  final String? ownerAvatarUrl;

  /// Owner's live broadcast position — only populated when fetched with the
  /// `profiles:owner_id(latitude, longitude)` embed. Null whenever the owner
  /// has never broadcast (or the query didn't ask for it), in which case
  /// [effectiveLatitude]/[effectiveLongitude] fall back to the kitchen's
  /// static registered coordinates.
  final double? ownerLatitude;
  final double? ownerLongitude;

  /// The coordinates to actually show as "where this kitchen is" — the
  /// owner's live position when they're broadcasting it, otherwise the
  /// kitchen's registered address coordinates. Feed this into
  /// [GeocodingService]/[LiveLocationText] rather than [latitude]/[longitude]
  /// directly wherever a kitchen's location is displayed.
  double get effectiveLatitude => ownerLatitude ?? latitude;
  double get effectiveLongitude => ownerLongitude ?? longitude;

  Kitchen({
    required this.id,
    required this.ownerId,
    required this.name,
    this.description,
    this.address,
    this.imageUrl,
    required this.latitude,
    required this.longitude,
    required this.isActive,
    required this.createdAt,
    this.ownerAvatarUrl,
    this.ownerLatitude,
    this.ownerLongitude,
  });

  factory Kitchen.fromJson(Map<String, dynamic> json) {
    final ownerProfile = json['profiles'];
    final ownerMap = ownerProfile is Map ? ownerProfile : null;
    return Kitchen(
      id: json['id'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      address: json['address'] as String?,
      imageUrl: json['image_url'] as String?,
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      isActive: json['is_active'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
      ownerAvatarUrl: ownerMap?['avatar_url'] as String?,
      ownerLatitude: ownerMap?['latitude'] != null ? (ownerMap!['latitude'] as num).toDouble() : null,
      ownerLongitude: ownerMap?['longitude'] != null ? (ownerMap!['longitude'] as num).toDouble() : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'owner_id': ownerId,
      'name': name,
      'description': description,
      'address': address,
      'image_url': imageUrl,
      'latitude': latitude,
      'longitude': longitude,
      'is_active': isActive,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
