import 'dart:math';
import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Requests the permissions required for continuous location tracking.
  /// Returns true if at least foreground ("while in use") access was granted.
  static Future<bool> ensurePermissions() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return false;

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) return false;
    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  /// Streams live device position updates. Emits a new [Position] whenever the
  /// device moves more than [distanceFilterMeters], so this is what should
  /// drive continuous rider-location broadcasting during an active delivery
  /// (as opposed to [getCurrentLocation], which only fetches a single fix).
  static Stream<Position> getPositionStream({int distanceFilterMeters = 15}) {
    final LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilterMeters,
    );
    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  // Static mock locations for testing in emulators
  static double? _mockLatitude;
  static double? _mockLongitude;

  static void setMockLocation(double lat, double lng) {
    _mockLatitude = lat;
    _mockLongitude = lng;
  }

  static void clearMockLocation() {
    _mockLatitude = null;
    _mockLongitude = null;
  }

  static bool get isMocked => _mockLatitude != null && _mockLongitude != null;

  static double? get mockLatitude => _mockLatitude;
  static double? get mockLongitude => _mockLongitude;

  /// Fetches current position (or returns mock position if set).
  /// Falls back to a default location (e.g., Dhaka, Bangladesh) if permissions are denied or disabled.
  static Future<Map<String, double>> getCurrentLocation() async {
    if (isMocked) {
      return {'latitude': _mockLatitude!, 'longitude': _mockLongitude!};
    }

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        // Fallback default coordinates (e.g., Dhaka Center)
        return {'latitude': 23.8103, 'longitude': 90.4125};
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return {'latitude': 23.8103, 'longitude': 90.4125};
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return {'latitude': 23.8103, 'longitude': 90.4125};
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      return {'latitude': position.latitude, 'longitude': position.longitude};
    } catch (e) {
      // General fallback
      return {'latitude': 23.8103, 'longitude': 90.4125};
    }
  }

  /// Calculates the distance in kilometers between two coordinates using the Haversine formula.
  static double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 -
        cos((lat2 - lat1) * p) / 2 +
        cos(lat1 * p) * cos(lat2 * p) * (1 - cos((lon2 - lon1) * p)) / 2;
    return 12742 * asin(sqrt(a)); // 2 * R; R = 6371 km
  }
}
