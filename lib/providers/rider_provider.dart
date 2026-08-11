import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/order.dart';
import '../models/review.dart';
import '../services/location_service.dart';
import '../utils/async_guard.dart';

class RiderProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  List<Order> _availableDeliveries = [];
  Order? _activeDelivery;
  double _earnings = 0.0;
  bool _isLoading = false;
  String? _errorMessage;
  bool _isTrackingLocation = false;

  StreamSubscription<List<Map<String, dynamic>>>? _availableSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _activeSubscription;
  StreamSubscription<Position>? _positionSubscription;

  List<Order> get availableDeliveries => _availableDeliveries;
  Order? get activeDelivery => _activeDelivery;
  double get earnings => _earnings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTrackingLocation => _isTrackingLocation;

  /// Subscribes to available delivery orders (status = 'awaiting_rider').
  void subscribeToAvailableDeliveries() {
    _availableSubscription?.cancel();
    _availableSubscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'awaiting_rider')
        .listen((List<Map<String, dynamic>> data) async {
          final List<Order> resolved = [];
          for (var item in data) {
            try {
              final kitchenData = await _client
                  .from('kitchens')
                  .select('name, address, latitude, longitude')
                  .eq('id', item['kitchen_id'])
                  .single();

              final combined = Map<String, dynamic>.from(item);
              combined['kitchens'] = {'name': kitchenData['name']};
              combined['kitchen_latitude'] = kitchenData['latitude'];
              combined['kitchen_longitude'] = kitchenData['longitude'];

              resolved.add(Order.fromJson(combined));
            } catch (e) {
              resolved.add(Order.fromJson(item));
            }
          }
          _availableDeliveries = resolved;
          notifyListeners();
        });
  }

  /// Subscribes to current active delivery (assigned to rider and not delivered).
  void subscribeToActiveDelivery(String riderId) {
    _activeSubscription?.cancel();
    _activeSubscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('rider_id', riderId)
        .listen((List<Map<String, dynamic>> data) async {
          final activeRows = data
              .where((o) => o['status'] != 'completed' && o['status'] != 'rejected')
              .toList();
          if (activeRows.isNotEmpty) {
            final item = activeRows.first;
            try {
              final kitchenData = await _client
                  .from('kitchens')
                  .select('name, address, latitude, longitude')
                  .eq('id', item['kitchen_id'])
                  .single();

              final customerData = await _client
                  .from('profiles')
                  .select('full_name, phone')
                  .eq('id', item['customer_id'])
                  .single();

              final combined = Map<String, dynamic>.from(item);
              combined['kitchens'] = {'name': kitchenData['name']};
              combined['profiles_customer'] = {'full_name': customerData['full_name'], 'phone': customerData['phone']};

              _activeDelivery = Order.fromJson(combined);
            } catch (e) {
              _activeDelivery = Order.fromJson(item);
            }
          } else {
            _activeDelivery = null;
          }
          notifyListeners();
        });
  }

  /// Accepts an available delivery (changes status to 'rider_assigned' and assigns rider_id),
  /// and immediately starts continuous GPS broadcasting for the duration of the delivery.
  Future<bool> acceptDelivery(String orderId, String riderId) async {
    _setLoading(true);
    try {
      final rows = await runGuarded(
        () => _client
            .from('orders')
            .update({
              'status': 'rider_assigned',
              'rider_id': riderId,
            })
            .eq('id', orderId)
            .eq('status', 'awaiting_rider')
            .filter('rider_id', 'is', null)
            .select(),
        onError: (e) => _errorMessage = e.toString(),
      );
      if (rows == null) {
        _errorMessage ??= 'Could not accept this delivery. Please check your connection and try again.';
        return false;
      }
      if (rows.isEmpty) {
        // A plain .update().eq() reports success even if RLS filtered the row
        // to zero matches (e.g. another rider claimed it first) — verify.
        _errorMessage = 'This delivery is no longer available. Someone else may have already accepted it.';
        return false;
      }
      _errorMessage = null;
      startLocationTracking(riderId);
      return true;
    } finally {
      _setLoading(false);
    }
  }

  /// Validates the current status allows the requested transition before writing,
  /// so the rider cannot pick up before accepting, mark delivered twice, etc.
  Future<bool> _transitionTo(String orderId, String requiredCurrentStatus, String newStatus) async {
    if (_activeDelivery == null || _activeDelivery!.id != orderId) {
      _errorMessage = 'No active delivery found for this order.';
      notifyListeners();
      return false;
    }
    if (_activeDelivery!.status != requiredCurrentStatus) {
      _errorMessage = 'Cannot move to "$newStatus" from "${_activeDelivery!.status}".';
      notifyListeners();
      return false;
    }
    return updateDeliveryStatus(orderId, newStatus);
  }

  Future<bool> markPickedUp(String orderId) => _transitionTo(orderId, 'rider_assigned', 'picked_up');
  Future<bool> markOnTheWay(String orderId) => _transitionTo(orderId, 'picked_up', 'on_the_way');
  Future<bool> markArrived(String orderId) => _transitionTo(orderId, 'on_the_way', 'arrived');

  Future<bool> markDelivered(String orderId) async {
    final success = await _transitionTo(orderId, 'arrived', 'delivered');
    if (success) stopLocationTracking();
    return success;
  }

  /// Updates status of the active delivery. Prefer the dedicated mark* methods above,
  /// which validate the transition; this is the raw setter they (and acceptDelivery) use.
  Future<bool> updateDeliveryStatus(String orderId, String newStatus) async {
    final rows = await runGuarded(
      () => _client.from('orders').update({'status': newStatus}).eq('id', orderId).select(),
      onError: (e) => _errorMessage = e.toString(),
    );
    if (rows == null) {
      _errorMessage ??= 'Could not update this order. Please check your connection and try again.';
      notifyListeners();
      return false;
    }
    if (rows.isEmpty) {
      _errorMessage = 'This order could not be updated. It may have changed already, or you may not have permission.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    return true;
  }

  /// Rider confirms they actually received the payout the kitchen owner
  /// marked as sent — this is the final step that unblocks the customer's
  /// delivery confirmation (see Order.isDeliveryConfirmationBlocked). Only
  /// possible after the kitchen owner has already marked the rider as paid
  /// (enforced by the DB trigger).
  Future<bool> confirmPaymentReceived(String orderId) async {
    final rows = await runGuarded(
      () => _client.from('orders').update({'rider_payment_confirmed': true}).eq('id', orderId).select(),
      onError: (e) => _errorMessage = e.toString(),
    );
    if (rows == null) {
      _errorMessage ??= 'Could not confirm payment. Please check your connection and try again.';
      notifyListeners();
      return false;
    }
    if (rows.isEmpty) {
      _errorMessage = 'This order could not be updated. It may have changed already, or you may not have permission.';
      notifyListeners();
      return false;
    }
    _errorMessage = null;
    notifyListeners();
    return true;
  }

  /// Loads earnings for a rider (sums rider_fee for completed orders,
  /// matching when the DB actually pays out — after customer confirmation).
  Future<void> loadEarnings(String riderId) async {
    try {
      final response = await _client
          .from('orders')
          .select('rider_fee')
          .eq('rider_id', riderId)
          .eq('status', 'completed');

      final list = response as List;
      _earnings = list.fold(0.0, (sum, item) => sum + (item['rider_fee'] as num).toDouble());
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    }
  }

  /// Refreshes/updates rider current location coordinates in their profile.
  Future<bool> updateRiderLocation(String riderId, double lat, double lng) async {
    try {
      await _client.from('profiles').update({
        'latitude': lat,
        'longitude': lng,
      }).eq('id', riderId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  /// Starts a continuous GPS stream and pushes every update to the rider's profile
  /// row, which customer/kitchen screens are already subscribed to in real time.
  Future<void> startLocationTracking(String riderId) async {
    if (_isTrackingLocation) return;
    final granted = await LocationService.ensurePermissions();
    if (!granted) {
      _errorMessage = 'Location permission denied — live tracking unavailable.';
      notifyListeners();
      return;
    }
    _isTrackingLocation = true;
    notifyListeners();
    _positionSubscription?.cancel();
    _positionSubscription = LocationService.getPositionStream().listen(
      (Position position) {
        updateRiderLocation(riderId, position.latitude, position.longitude);
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

  /// Fetches average rating for the rider.
  Future<Map<String, dynamic>> getRiderRatingStats(String riderId) async {
    try {
      final response = await _client
          .from('ratings')
          .select('score')
          .eq('ratee_id', riderId)
          .eq('rating_type', 'rider');

      final ratings = response as List;
      if (ratings.isEmpty) return {'rating': 0.0, 'count': 0};

      final total = ratings.map((r) => r['score'] as int).reduce((a, b) => a + b);
      final avg = total / ratings.length;
      return {'rating': avg, 'count': ratings.length};
    } catch (e) {
      return {'rating': 0.0, 'count': 0};
    }
  }

  /// Loads the rider's completed-delivery history — kitchen, customer name +
  /// phone + delivery address, and items, newest first.
  Future<List<Order>> loadDeliveryHistory(String riderId) async {
    try {
      final data = await _client
          .from('orders')
          .select()
          .eq('rider_id', riderId)
          .eq('status', 'completed')
          .order('completed_at', ascending: false);

      final List<Order> resolved = [];
      for (var item in data as List) {
        try {
          final kitchenData = await _client
              .from('kitchens')
              .select('name')
              .eq('id', item['kitchen_id'])
              .single();
          final customerData = await _client
              .from('profiles')
              .select('full_name, phone')
              .eq('id', item['customer_id'])
              .single();
          final orderItemsData = await _client
              .from('order_items')
              .select('*, menu_items(name)')
              .eq('order_id', item['id']);

          final combined = Map<String, dynamic>.from(item);
          combined['kitchens'] = {'name': kitchenData['name']};
          combined['profiles_customer'] = {'full_name': customerData['full_name'], 'phone': customerData['phone']};
          combined['order_items'] = orderItemsData;
          resolved.add(Order.fromJson(combined));
        } catch (e) {
          resolved.add(Order.fromJson(item as Map<String, dynamic>));
        }
      }
      return resolved;
    } catch (e) {
      _errorMessage = e.toString();
      return [];
    }
  }

  /// Loads all reviews customers have left for this rider, newest first.
  Future<List<Review>> getRiderReviews(String riderId) async {
    try {
      final data = await _client
          .from('ratings')
          .select('id, order_id, rater_id, score, review, created_at, photo_urls')
          .eq('ratee_id', riderId)
          .eq('rating_type', 'rider')
          .order('created_at', ascending: false);

      final List<Review> resolved = [];
      for (var item in data as List) {
        try {
          final raterData = await _client
              .from('profiles')
              .select('full_name')
              .eq('id', item['rater_id'])
              .single();
          final combined = Map<String, dynamic>.from(item);
          combined['profiles_rater'] = {'full_name': raterData['full_name']};
          resolved.add(Review.fromJson(combined));
        } catch (e) {
          resolved.add(Review.fromJson(item as Map<String, dynamic>));
        }
      }
      return resolved;
    } catch (e) {
      _errorMessage = e.toString();
      return [];
    }
  }

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  @override
  void dispose() {
    _availableSubscription?.cancel();
    _activeSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
