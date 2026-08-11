class Rating {
  final String id;
  final String orderId;
  final String raterId;
  final String rateeId;
  final String ratingType; // 'kitchen' or 'rider'
  final int score;
  final String? review;
  final DateTime createdAt;

  Rating({
    required this.id,
    required this.orderId,
    required this.raterId,
    required this.rateeId,
    required this.ratingType,
    required this.score,
    this.review,
    required this.createdAt,
  });

  factory Rating.fromJson(Map<String, dynamic> json) {
    return Rating(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      raterId: json['rater_id'] as String,
      rateeId: json['ratee_id'] as String,
      ratingType: json['rating_type'] as String,
      score: json['score'] as int,
      review: json['review'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'order_id': orderId,
      'rater_id': raterId,
      'ratee_id': rateeId,
      'rating_type': ratingType,
      'score': score,
      'review': review,
    };
  }
}
