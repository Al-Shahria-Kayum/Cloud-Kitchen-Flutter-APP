class MenuItem {
  final String id;
  final String kitchenId;
  final String name;
  final String? description;
  final double price;
  final List<String> imageUrls;
  final bool isAvailable;
  final DateTime createdAt;

  /// The single thumbnail shown in list/card contexts that only have room
  /// for one photo — the first of [imageUrls], or null if none were uploaded.
  String? get imageUrl => imageUrls.isNotEmpty ? imageUrls.first : null;

  MenuItem({
    required this.id,
    required this.kitchenId,
    required this.name,
    this.description,
    required this.price,
    this.imageUrls = const [],
    required this.isAvailable,
    required this.createdAt,
  });

  factory MenuItem.fromJson(Map<String, dynamic> json) {
    List<String> urls = json['image_urls'] != null ? List<String>.from(json['image_urls'] as List) : const [];
    // Fall back to the legacy single-image column for rows that predate the
    // image_urls migration and, for any reason, weren't backfilled.
    if (urls.isEmpty && json['image_url'] != null) {
      urls = [json['image_url'] as String];
    }
    return MenuItem(
      id: json['id'] as String,
      kitchenId: json['kitchen_id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      price: (json['price'] as num).toDouble(),
      imageUrls: urls,
      isAvailable: json['is_available'] as bool,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'kitchen_id': kitchenId,
      'name': name,
      'description': description,
      'price': price,
      'image_url': imageUrl,
      'image_urls': imageUrls,
      'is_available': isAvailable,
      'created_at': createdAt.toIso8601String(),
    };
  }
}
