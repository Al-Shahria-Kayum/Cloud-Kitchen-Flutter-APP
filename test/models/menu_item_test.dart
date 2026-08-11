import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_kitchen_mvp/models/menu_item.dart';

Map<String, dynamic> _baseJson() => {
      'id': 'item-1',
      'kitchen_id': 'kitchen-1',
      'name': 'Beef Tehari',
      'price': 250.0,
      'is_available': true,
      'created_at': '2026-08-01T10:00:00Z',
    };

void main() {
  group('MenuItem.fromJson multi-photo handling', () {
    test('parses multiple image_urls and exposes the first as imageUrl', () {
      final json = _baseJson()..['image_urls'] = ['https://a.jpg', 'https://b.jpg', 'https://c.jpg'];

      final item = MenuItem.fromJson(json);

      expect(item.imageUrls, ['https://a.jpg', 'https://b.jpg', 'https://c.jpg']);
      expect(item.imageUrl, 'https://a.jpg');
    });

    test('falls back to the legacy image_url column when image_urls is empty', () {
      final json = _baseJson()
        ..['image_urls'] = <String>[]
        ..['image_url'] = 'https://legacy.jpg';

      final item = MenuItem.fromJson(json);

      expect(item.imageUrls, ['https://legacy.jpg']);
      expect(item.imageUrl, 'https://legacy.jpg');
    });

    test('imageUrl is null when no photos exist at all', () {
      final item = MenuItem.fromJson(_baseJson());

      expect(item.imageUrls, isEmpty);
      expect(item.imageUrl, isNull);
    });

    test('toJson round-trips image_urls and mirrors the first into image_url', () {
      final item = MenuItem(
        id: 'item-2',
        kitchenId: 'kitchen-1',
        name: 'Kacchi',
        price: 300.0,
        imageUrls: const ['https://x.jpg', 'https://y.jpg'],
        isAvailable: true,
        createdAt: DateTime.parse('2026-08-01T10:00:00Z'),
      );

      final json = item.toJson();

      expect(json['image_urls'], ['https://x.jpg', 'https://y.jpg']);
      expect(json['image_url'], 'https://x.jpg');
    });
  });
}
