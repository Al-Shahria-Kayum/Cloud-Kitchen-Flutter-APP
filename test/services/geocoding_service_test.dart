import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:cloud_kitchen_mvp/services/geocoding_service.dart';

void main() {
  setUp(() {
    GeocodingService.clearCacheForTesting();
  });

  test('resolves a suburb + city from a successful Nominatim response', () async {
    GeocodingService.debugClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'display_name': 'Bosila, Mohammadpur, Dhaka, Bangladesh',
          'address': {
            'suburb': 'Bosila',
            'city': 'Dhaka',
          },
        }),
        200,
      );
    });

    final result = await GeocodingService.reverseGeocode(23.7717, 90.3510);
    expect(result, 'Bosila, Dhaka');
  });

  test('falls back to display_name when no suburb/city fields present', () async {
    GeocodingService.debugClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'display_name': 'Some Road, Some District',
          'address': <String, dynamic>{},
        }),
        200,
      );
    });

    final result = await GeocodingService.reverseGeocode(23.81, 90.41);
    expect(result, 'Some Road, Some District');
  });

  test('falls back to a coordinate string on a non-200 response', () async {
    GeocodingService.debugClient = MockClient((request) async {
      return http.Response('Service Unavailable', 503);
    });

    final result = await GeocodingService.reverseGeocode(23.81, 90.41);
    expect(result, '23.8100, 90.4100');
  });

  test('falls back to a coordinate string when the request throws', () async {
    GeocodingService.debugClient = MockClient((request) async {
      throw Exception('network unreachable');
    });

    final result = await GeocodingService.reverseGeocode(1.2345, 6.7891);
    expect(result, '1.2345, 6.7891');
  });

  test('caches the resolved value — a second call does not hit the network again', () async {
    var callCount = 0;
    GeocodingService.debugClient = MockClient((request) async {
      callCount++;
      return http.Response(
        jsonEncode({
          'display_name': 'Bosila, Mohammadpur, Dhaka, Bangladesh',
          'address': {'suburb': 'Bosila', 'city': 'Dhaka'},
        }),
        200,
      );
    });

    final first = await GeocodingService.reverseGeocode(23.7717, 90.3510);
    final second = await GeocodingService.reverseGeocode(23.7717, 90.3510);

    expect(first, second);
    expect(callCount, 1);
  });
}
