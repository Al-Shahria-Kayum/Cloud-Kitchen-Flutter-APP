/// A single rating left on an order — either about the kitchen or the rider.
class Review {
  final String id;
  final String orderId;
  final String raterId;
  final String? raterName;
  final int score;
  final String? review;
  final DateTime createdAt;
  final List<String> photoUrls;

  Review({
    required this.id,
    required this.orderId,
    required this.raterId,
    this.raterName,
    required this.score,
    this.review,
    required this.createdAt,
    this.photoUrls = const [],
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      raterId: json['rater_id'] as String,
      raterName: json['profiles_rater'] != null ? json['profiles_rater']['full_name'] as String? : null,
      score: json['score'] as int,
      review: json['review'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      photoUrls: json['photo_urls'] != null ? List<String>.from(json['photo_urls'] as List) : const [],
    );
  }
}
