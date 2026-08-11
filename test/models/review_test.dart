import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_kitchen_mvp/models/review.dart';

void main() {
  group('Review.fromJson', () {
    test('parses rater name, score and review text', () {
      final json = {
        'id': 'rating-1',
        'order_id': 'order-1',
        'rater_id': 'customer-1',
        'score': 4,
        'review': 'Great food, fast delivery!',
        'created_at': '2026-08-01T12:00:00Z',
        'profiles_rater': {'full_name': 'Alex Rider'},
      };

      final review = Review.fromJson(json);

      expect(review.id, 'rating-1');
      expect(review.raterName, 'Alex Rider');
      expect(review.score, 4);
      expect(review.review, 'Great food, fast delivery!');
      expect(review.createdAt, DateTime.parse('2026-08-01T12:00:00Z'));
    });

    test('raterName is null when profiles_rater is not embedded', () {
      final json = {
        'id': 'rating-2',
        'order_id': 'order-2',
        'rater_id': 'customer-2',
        'score': 5,
        'review': null,
        'created_at': '2026-08-02T12:00:00Z',
      };

      final review = Review.fromJson(json);

      expect(review.raterName, isNull);
      expect(review.review, isNull);
      expect(review.score, 5);
    });

    test('parses photo_urls when present', () {
      final json = {
        'id': 'rating-3',
        'order_id': 'order-3',
        'rater_id': 'customer-3',
        'score': 5,
        'review': 'Loved it',
        'created_at': '2026-08-03T12:00:00Z',
        'photo_urls': ['https://example.com/a.jpg', 'https://example.com/b.jpg'],
      };

      final review = Review.fromJson(json);

      expect(review.photoUrls, ['https://example.com/a.jpg', 'https://example.com/b.jpg']);
    });

    test('photoUrls defaults to an empty list when photo_urls is absent', () {
      final json = {
        'id': 'rating-4',
        'order_id': 'order-4',
        'rater_id': 'customer-4',
        'score': 3,
        'review': null,
        'created_at': '2026-08-04T12:00:00Z',
      };

      final review = Review.fromJson(json);

      expect(review.photoUrls, isEmpty);
    });
  });
}
