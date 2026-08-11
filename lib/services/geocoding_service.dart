import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Reverse-geocodes coordinates into a short, human-readable
/// "neighborhood, city" string (e.g. "Bosila, Mohammadpur") instead of
/// showing raw lat/lng or a stale hand-typed address everywhere a kitchen's
/// or delivery's location is displayed.
///
/// Uses OpenStreetMap's free Nominatim API — no key required, and this app
/// already renders OSM tiles elsewhere, so it's the same provider stack.
/// Nominatim's usage policy caps public callers at ~1 request/second and
/// asks for a descriptive User-Agent; for anything beyond MVP/demo volume,
/// swap this for a paid geocoder (Google/Mapbox) or a self-hosted Nominatim
/// instance — the call site (reverseGeocode) is the only thing to change.
class GeocodingService {
  GeocodingService._();

  static http.Client _client = http.Client();

  /// Test-only seam to swap in a fake client (e.g. http.testing.MockClient).
  @visibleForTesting
  static set debugClient(http.Client client) => _client = client;

  /// In-memory cache keyed by coordinates rounded to ~11m precision, so
  /// repeated renders/screens for the same location never re-hit the network.
  static final Map<String, String> _cache = {};

  static String _keyFor(double lat, double lng) =>
      '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';

  /// Returns a short human-readable location, e.g. "Bosila, Mohammadpur".
  /// Falls back to a coordinate string only if geocoding genuinely fails
  /// (offline, API error, or an address the response couldn't name).
  static Future<String> reverseGeocode(double lat, double lng) async {
    final key = _keyFor(lat, lng);
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=jsonv2&lat=$lat&lon=$lng&zoom=16&addressdetails=1',
      );
      final response = await _client
          .get(uri, headers: const {'User-Agent': 'cloud_kitchen_mvp (student project)'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final address = data['address'] as Map<String, dynamic>?;

        final area = address?['suburb'] ??
            address?['neighbourhood'] ??
            address?['residential'] ??
            address?['quarter'] ??
            address?['road'];
        final city = address?['city'] ?? address?['town'] ?? address?['county'];

        final parts = [area, city]
            .where((p) => p != null && (p as String).trim().isNotEmpty)
            .toList();

        final resolved = parts.isNotEmpty
            ? parts.join(', ')
            : (data['display_name'] as String? ?? _fallback(lat, lng));

        _cache[key] = resolved;
        return resolved;
      }
    } catch (_) {
      // Network/parse failure — fall through to the coordinate fallback below.
    }
    return _fallback(lat, lng);
  }

  static String _fallback(double lat, double lng) =>
      '${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}';

  /// Test-only escape hatch to reset the cache between test cases.
  static void clearCacheForTesting() => _cache.clear();
}
