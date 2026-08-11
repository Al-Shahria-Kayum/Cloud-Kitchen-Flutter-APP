import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/kitchen.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../services/location_service.dart';

class CustomerProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<Kitchen> _kitchens = [];
  List<MenuItem> _currentMenu = [];
  List<Order> _myOrders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isTrackingLocation = false;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _menuSubscription;
  StreamSubscription<Position>? _positionSubscription;

  List<Kitchen> get kitchens => _kitchens;
  List<MenuItem> get currentMenu => _currentMenu;
  List<Order> get myOrders => _myOrders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTrackingLocation => _isTrackingLocation;

  /// Loads kitchens, filters only active ones, and sorts by proximity to customer coordinates.
  Future<void> loadNearbyKitchens(double customerLat, double customerLng) async {
    _setLoading(true);
    try {
      // Embed the owner's avatar + live position in one query (no N+1 per-card
      // fetch) so the kitchen list can fall back to the avatar before the
      // kitchen sets its own cover photo, and can show the owner's live
      // location (via GeocodingService) instead of the registered address.
      final response = await _client
          .from('kitchens')
          .select('*, profiles:owner_id(avatar_url, latitude, longitude)')
          .eq('is_active', true);

      final List<Kitchen> loaded = (response as List)
          .map((k) => Kitchen.fromJson(k as Map<String, dynamic>))
          .toList();

      // Sort by distance using Haversine formula
      loaded.sort((a, b) {
        final distA = LocationService.calculateDistance(
            customerLat, customerLng, a.latitude, a.longitude);
        final distB = LocationService.calculateDistance(
            customerLat, customerLng, b.latitude, b.longitude);
        return distA.compareTo(distB);
      });

      _kitchens = loaded;
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Loads available menu items for a specific kitchen.
  Future<void> loadKitchenMenu(String kitchenId) async {
    _setLoading(true);
    try {
      final response = await _client
          .from('menu_items')
          .select()
          .eq('kitchen_id', kitchenId)
          .eq('is_available', true);

      _currentMenu = (response as List)
          .map((m) => MenuItem.fromJson(m as Map<String, dynamic>))
          .toList();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Fetches a kitchen owner's public profile (name + avatar + live
  /// position) so customers can see who they're ordering from and where the
  /// kitchen actually is right now. Returns null on failure/missing row.
  Future<Map<String, dynamic>?> getKitchenOwnerProfile(String ownerId) async {
    try {
      return await _client
          .from('profiles')
          .select('full_name, avatar_url, latitude, longitude')
          .eq('id', ownerId)
          .maybeSingle();
    } catch (e) {
      return null;
    }
  }

  /// Subscribes to live updates for a kitchen's menu (name/price/availability/
  /// image changes), so edits the owner makes appear immediately instead of
  /// only on the next fresh navigation into this screen.
  void subscribeToKitchenMenu(String kitchenId) {
    _menuSubscription?.cancel();
    _menuSubscription = _client
        .from('menu_items')
        .stream(primaryKey: ['id'])
        .eq('kitchen_id', kitchenId)
        .listen((List<Map<String, dynamic>> data) {
          _currentMenu = data
              .where((m) => m['is_available'] == true)
              .map((m) => MenuItem.fromJson(m))
              .toList();
          notifyListeners();
        });
  }

  /// Places a single-item order using the secure SQL RPC function.
  Future<String?> placeOrder({
    required String kitchenId,
    required String menuItemId,
    required int quantity,
    required String deliveryAddress,
    required double deliveryLatitude,
    required double deliveryLongitude,
  }) async {
    _setLoading(true);
    try {
      final response = await _client.rpc('create_order', params: {
        'p_kitchen_id': kitchenId,
        'p_menu_item_id': menuItemId,
        'p_quantity': quantity,
        'p_delivery_address': deliveryAddress,
        'p_delivery_latitude': deliveryLatitude,
        'p_delivery_longitude': deliveryLongitude,
      });
      _errorMessage = null;
      return response as String?;
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    } finally {
      _setLoading(false);
    }
  }

  /// Subscribes to customer orders in real time.
  void subscribeToMyOrders(String customerId) {
    _ordersSubscription?.cancel();
    _ordersSubscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('customer_id', customerId)
        .order('created_at', ascending: false)
        .listen((List<Map<String, dynamic>> data) async {
          // Resolve joined data for display (kitchen name)
          final List<Order> resolvedOrders = [];
          for (var item in data) {
            try {
              final kitchenData = await _client
                  .from('kitchens')
                  .select('name')
                  .eq('id', item['kitchen_id'])
                  .single();
              
              final orderItemsData = await _client
                  .from('order_items')
                  .select('*, menu_items(name)')
                  .eq('order_id', item['id']);

              // Combine into JSON payload for parsing
              final combined = Map<String, dynamic>.from(item);
              combined['kitchens'] = {'name': kitchenData['name']};
              combined['order_items'] = orderItemsData;

              resolvedOrders.add(Order.fromJson(combined));
            } catch (e) {
              resolvedOrders.add(Order.fromJson(item));
            }
          }
          _myOrders = resolvedOrders;
          notifyListeners();
        });
  }

  /// Refreshes/updates the customer's current location coordinates in their
  /// profile — same `profiles` table/columns riders broadcast to, so
  /// kitchen/rider screens already subscribed to it pick this up for free.
  Future<bool> updateCustomerLocation(String customerId, double lat, double lng) async {
    try {
      await _client.from('profiles').update({
        'latitude': lat,
        'longitude': lng,
      }).eq('id', customerId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  /// Starts a continuous GPS stream and pushes every update to the customer's
  /// profile row from the moment they're logged in — same `profiles` row a
  /// rider only actually gets shown once an order they're delivering reaches
  /// 'picked_up' (see rider_order_details_screen's pickup gate).
  Future<void> startLocationTracking(String customerId) async {
    if (_isTrackingLocation) return;
    final granted = await LocationService.ensurePermissions();
    if (!granted) {
      _errorMessage = 'Location permission denied — live tracking unavailable. Enable location services and grant permission to broadcast your real position to the rider instead of your delivery address.';
      notifyListeners();
      return;
    }
    _isTrackingLocation = true;
    _errorMessage = null;
    notifyListeners();

    // Push one immediate fix so the rider sees the real position right away,
    // rather than waiting for the device to physically move far enough to
    // trigger the first stream event (see getPositionStream's distanceFilter).
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await updateCustomerLocation(customerId, position.latitude, position.longitude);
    } catch (_) {
      // Fall through to the stream below; it will retry on the next fix.
    }

    _positionSubscription?.cancel();
    _positionSubscription = LocationService.getPositionStream().listen(
      (Position position) {
        updateCustomerLocation(customerId, position.latitude, position.longitude);
      },
      onError: (_) {
        // Keep the subscription alive; geolocator will retry on the next fix.
      },
    );
  }

  void stopLocationTracking() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _isTrackingLocation = false;
    notifyListeners();
  }

  /// Customer reports having sent the bKash payment for this order, along
  /// with the transaction ID bKash texted back — the kitchen owner sees this
  /// and taps "Confirm Payment Received" before accepting the order. The DB
  /// trigger enforces that only the customer on this order can call this and
  /// that a non-empty transaction ID is provided.
  Future<bool> reportPayment({required String orderId, required String bkashTxnId}) async {
    try {
      final rows = await _client.from('orders').update({
        'payment_status': 'payment_reported',
        'customer_bkash_txn_id': bkashTxnId.trim(),
      }).eq('id', orderId).select();
      if (rows.isEmpty) {
        _errorMessage = 'Could not report this payment. Please check your connection and try again.';
        notifyListeners();
        return false;
      }
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Customer confirms they received the order after the rider marks it 'delivered'.
  /// Transitions status 'delivered' -> 'completed', which is what triggers the
  /// DB payout to rider + kitchen owner (see handle_order_status_change trigger).
  Future<bool> confirmDelivery(String orderId) async {
    try {
      final rows = await _client.from('orders').update({
        'status': 'completed',
        'confirmed_by_customer': true,
      }).eq('id', orderId).select();
      if (rows.isEmpty) {
        _errorMessage = 'This order could not be confirmed. It may have changed already, or you may not have permission.';
        notifyListeners();
        return false;
      }
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Uploads a single review photo to the public `review-photos` bucket,
  /// under the rater's own folder (mirrors the avatar/cover-photo upload
  /// pattern elsewhere in the app). Returns the public URL, or null on
  /// failure — callers should skip that photo and keep going rather than
  /// fail the whole review over one bad upload.
  Future<String?> uploadReviewPhoto(Uint8List imageBytes, String fileName, String raterId) async {
    final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
    final unique = DateTime.now().microsecondsSinceEpoch;
    final objectName = '$unique.$ext';
    final path = '$raterId/$objectName';

    try {
      await _client.storage
          .from('review-photos')
          .uploadBinary(path, imageBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
          .timeout(const Duration(seconds: 10));
      return _client.storage.from('review-photos').getPublicUrl(path);
    } on TimeoutException {
      final files = await _client.storage.from('review-photos').list(path: raterId);
      if (files.any((f) => f.name == objectName)) {
        return _client.storage.from('review-photos').getPublicUrl(path);
      }
      _errorMessage = 'Photo upload timed out. Please try again.';
      notifyListeners();
      return null;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Submits rating for kitchen or rider.
  Future<bool> submitRating({
    required String orderId,
    required String raterId,
    required String rateeId,
    required String ratingType, // 'kitchen' or 'rider'
    required int score,
    String? review,
    List<String> photoUrls = const [],
  }) async {
    try {
      await _client.from('ratings').insert({
        'order_id': orderId,
        'rater_id': raterId,
        'ratee_id': rateeId,
        'rating_type': ratingType,
        'score': score,
        'review': review,
        'photo_urls': photoUrls,
      });
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _menuSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
