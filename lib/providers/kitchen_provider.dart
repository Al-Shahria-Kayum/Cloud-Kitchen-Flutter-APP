import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/kitchen.dart';
import '../models/menu_item.dart';
import '../models/order.dart';
import '../models/review.dart';
import '../services/location_service.dart';

enum MenuItemDeleteOutcome { success, hasOrderHistory, error }

class KitchenProvider extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;

  Kitchen? _kitchen;
  List<MenuItem> _menuItems = [];
  List<Order> _orders = [];
  bool _isLoading = false;
  String? _errorMessage;
  bool _isTrackingLocation = false;
  StreamSubscription<List<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<Position>? _positionSubscription;

  Kitchen? get kitchen => _kitchen;
  List<MenuItem> get menuItems => _menuItems;
  List<Order> get orders => _orders;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isTrackingLocation => _isTrackingLocation;

  /// Loads kitchen details for a specific owner ID.
  Future<void> loadKitchen(String ownerId) async {
    _setLoading(true);
    try {
      final response = await _client
          .from('kitchens')
          .select()
          .eq('owner_id', ownerId)
          .maybeSingle();

      if (response != null) {
        _kitchen = Kitchen.fromJson(response);
        await loadMenuItems();
      } else {
        _kitchen = null;
        _menuItems = [];
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = e.toString();
    } finally {
      _setLoading(false);
    }
  }

  /// Sets up or edits kitchen profile.
  Future<bool> saveKitchen({
    required String ownerId,
    required String name,
    String? description,
    String? address,
    String? imageUrl,
    required double latitude,
    required double longitude,
    required bool isActive,
  }) async {
    _setLoading(true);
    try {
      final payload = {
        'owner_id': ownerId,
        'name': name,
        'description': description,
        'address': address,
        'image_url': imageUrl,
        'latitude': latitude,
        'longitude': longitude,
        'is_active': isActive,
      };

      if (_kitchen == null) {
        final response = await _client.from('kitchens').insert(payload).select().single();
        _kitchen = Kitchen.fromJson(response);
      } else {
        final response = await _client
            .from('kitchens')
            .update(payload)
            .eq('id', _kitchen!.id)
            .select()
            .single();
        _kitchen = Kitchen.fromJson(response);
      }
      _errorMessage = null;
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Loads menu items for the current kitchen.
  Future<void> loadMenuItems() async {
    if (_kitchen == null) return;
    try {
      final response = await _client
          .from('menu_items')
          .select()
          .eq('kitchen_id', _kitchen!.id);

      _menuItems = (response as List)
          .map((m) => MenuItem.fromJson(m as Map<String, dynamic>))
          .toList();
      notifyListeners();
    } catch (e) {
      _errorMessage = e.toString();
    }
  }

  /// Uploads menu item image to Supabase Storage and returns public URL.
  ///
  /// Uses a unique, timestamp-based path per upload (rather than reusing the
  /// original device filename) so replacing a photo always produces a new
  /// URL — otherwise CachedNetworkImage keeps serving the old cached bytes
  /// under the same URL key even after the storage object is overwritten.
  ///
  /// On Flutter Web, `uploadBinary()`'s Future can fail to resolve even
  /// though the request completed successfully server-side. Rather than
  /// blindly retry (which just creates duplicate objects while the caller
  /// still never gets an answer), a timeout falls through to checking
  /// whether the object actually landed in storage before reporting failure.
  Future<String?> uploadMenuImage(Uint8List imageBytes, String fileName) async {
    if (_kitchen == null) return null;
    final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
    final unique = DateTime.now().microsecondsSinceEpoch;
    final String objectName = '$unique.$ext';
    final String path = '${_kitchen!.id}/$objectName';

    try {
      await _client.storage
          .from('menu-images')
          .uploadBinary(path, imageBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
          .timeout(const Duration(seconds: 10));
    } on TimeoutException {
      final uploaded = await _menuImageExists(objectName);
      if (!uploaded) {
        _errorMessage = 'Image upload timed out. Please try again.';
        return null;
      }
    } catch (e) {
      _errorMessage = e.toString();
      return null;
    }

    _errorMessage = null;
    return _client.storage.from('menu-images').getPublicUrl(path);
  }

  Future<bool> _menuImageExists(String objectName) async {
    if (_kitchen == null) return false;
    try {
      final files = await _client.storage.from('menu-images').list(path: _kitchen!.id);
      return files.any((f) => f.name == objectName);
    } catch (_) {
      return false;
    }
  }

  /// Uploads a new kitchen cover photo and saves it as the kitchen's
  /// `image_url` (shown to customers on the kitchen list and details banner).
  /// Reuses the `menu-images` bucket under a `cover/` sub-path — the existing
  /// storage RLS policy only checks the first path segment against the
  /// kitchen id, so this is already permitted for the kitchen owner.
  Future<bool> uploadKitchenCoverImage(Uint8List imageBytes, String fileName) async {
    if (_kitchen == null) return false;
    final ext = fileName.contains('.') ? fileName.split('.').last : 'jpg';
    final unique = DateTime.now().microsecondsSinceEpoch;
    final objectName = 'cover/$unique.$ext';
    final path = '${_kitchen!.id}/$objectName';

    String? publicUrl;
    try {
      await _client.storage
          .from('menu-images')
          .uploadBinary(path, imageBytes, fileOptions: const FileOptions(cacheControl: '3600', upsert: true))
          .timeout(const Duration(seconds: 10));
      publicUrl = _client.storage.from('menu-images').getPublicUrl(path);
    } on TimeoutException {
      final files = await _client.storage.from('menu-images').list(path: '${_kitchen!.id}/cover');
      if (files.any((f) => f.name == objectName.split('/').last)) {
        publicUrl = _client.storage.from('menu-images').getPublicUrl(path);
      } else {
        _errorMessage = 'Image upload timed out. Please try again.';
      }
    } catch (e) {
      _errorMessage = e.toString();
    }
    if (publicUrl == null) {
      notifyListeners();
      return false;
    }

    return saveKitchen(
      ownerId: _kitchen!.ownerId,
      name: _kitchen!.name,
      description: _kitchen!.description,
      address: _kitchen!.address,
      imageUrl: publicUrl,
      latitude: _kitchen!.latitude,
      longitude: _kitchen!.longitude,
      isActive: _kitchen!.isActive,
    );
  }

  /// Creates a new menu item. [imageUrls] may hold multiple photos — the
  /// first is mirrored into the legacy `image_url` column for any code path
  /// still reading it directly.
  Future<bool> addMenuItem({
    required String name,
    String? description,
    required double price,
    List<String> imageUrls = const [],
    required bool isAvailable,
  }) async {
    if (_kitchen == null) return false;
    _setLoading(true);
    try {
      await _client.from('menu_items').insert({
        'kitchen_id': _kitchen!.id,
        'name': name,
        'description': description,
        'price': price,
        'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
        'image_urls': imageUrls,
        'is_available': isAvailable,
      });
      await loadMenuItems();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Updates an existing menu item. Same multi-photo handling as [addMenuItem].
  Future<bool> updateMenuItem({
    required String id,
    required String name,
    String? description,
    required double price,
    List<String> imageUrls = const [],
    required bool isAvailable,
  }) async {
    _setLoading(true);
    try {
      await _client.from('menu_items').update({
        'name': name,
        'description': description,
        'price': price,
        'image_url': imageUrls.isNotEmpty ? imageUrls.first : null,
        'image_urls': imageUrls,
        'is_available': isAvailable,
      }).eq('id', id);
      await loadMenuItems();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    } finally {
      _setLoading(false);
    }
  }

  /// Deletes a menu item. Items that have already been ordered can't be
  /// hard-deleted — `order_items.menu_item_id` has a plain (non-cascading)
  /// foreign key to `menu_items.id` on purpose, so past orders/receipts keep
  /// showing what was actually ordered even after the item is retired.
  /// Postgres reports that as a 23503 foreign-key-violation, which this
  /// surfaces as [MenuItemDeleteOutcome.hasOrderHistory] instead of a raw
  /// error, so the UI can offer marking it unavailable instead.
  Future<MenuItemDeleteOutcome> deleteMenuItem(String id) async {
    _setLoading(true);
    try {
      await _client.from('menu_items').delete().eq('id', id);
      await loadMenuItems();
      _errorMessage = null;
      return MenuItemDeleteOutcome.success;
    } on PostgrestException catch (e) {
      if (e.code == '23503') {
        _errorMessage = null;
        return MenuItemDeleteOutcome.hasOrderHistory;
      }
      _errorMessage = e.toString();
      return MenuItemDeleteOutcome.error;
    } catch (e) {
      _errorMessage = e.toString();
      return MenuItemDeleteOutcome.error;
    } finally {
      _setLoading(false);
    }
  }

  /// Quick availability toggle — used as the alternative to deleting a menu
  /// item that has order history (see [deleteMenuItem]), without resending
  /// every other field.
  Future<bool> setMenuItemAvailability(String id, bool isAvailable) async {
    try {
      await _client.from('menu_items').update({'is_available': isAvailable}).eq('id', id);
      await loadMenuItems();
      _errorMessage = null;
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Subscribes to real-time incoming orders for the kitchen.
  void subscribeToOrders() {
    if (_kitchen == null) return;
    _ordersSubscription?.cancel();
    _ordersSubscription = _client
        .from('orders')
        .stream(primaryKey: ['id'])
        .eq('kitchen_id', _kitchen!.id)
        .order('created_at', ascending: false)
        .listen((List<Map<String, dynamic>> data) async {
          final List<Order> resolvedOrders = [];
          for (var item in data) {
            try {
              // Resolve customer name + phone — shown on the kitchen's order
              // history so the owner can see who ordered and reach them.
              final customerData = await _client
                  .from('profiles')
                  .select('full_name, phone')
                  .eq('id', item['customer_id'])
                  .single();

              // Resolve order items
              final orderItemsData = await _client
                  .from('order_items')
                  .select('*, menu_items(name)')
                  .eq('order_id', item['id']);

              // Combine payloads
              final combined = Map<String, dynamic>.from(item);
              combined['profiles_customer'] = {'full_name': customerData['full_name'], 'phone': customerData['phone']};
              combined['order_items'] = orderItemsData;

              // Resolve rider name + bKash number if assigned. The rider's
              // bKash number is fetched regardless of stage — the UI is what
              // gates revealing it to only after pickup (see kitchen_order_details_screen).
              if (item['rider_id'] != null) {
                final riderData = await _client
                    .from('profiles')
                    .select('full_name, bkash_number')
                    .eq('id', item['rider_id'])
                    .single();
                combined['profiles_rider'] = {'full_name': riderData['full_name']};
                combined['rider_bkash'] = riderData['bkash_number'];
              }

              resolvedOrders.add(Order.fromJson(combined));
            } catch (e) {
              resolvedOrders.add(Order.fromJson(item));
            }
          }
          _orders = resolvedOrders;
          notifyListeners();
        });
  }

  /// Updates order status (accept -> preparing -> ready -> awaiting_rider).
  /// Chains `.select()` so we can tell a genuine update apart from Postgrest
  /// silently affecting zero rows (e.g. RLS filtered the row out) — a plain
  /// `.update().eq()` returns success even when nothing actually changed.
  Future<bool> updateOrderStatus(String orderId, String newStatus) async {
    try {
      final rows = await _client
          .from('orders')
          .update({'status': newStatus})
          .eq('id', orderId)
          .select();
      if (rows.isEmpty) {
        _errorMessage = 'This order could not be updated. It may have changed already, or you may not have permission.';
        notifyListeners();
        return false;
      }
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Confirms the customer's reported bKash payment has actually landed in
  /// the owner's own bKash — after checking their bKash app/SMS themselves.
  /// This is the gate the DB trigger requires before the order can be accepted.
  Future<bool> confirmPaymentReceived(String orderId) async {
    return _updatePaymentFields(orderId, {'payment_status': 'payment_confirmed'},
        fallbackError: 'Could not confirm payment. Please check your connection and try again.');
  }

  /// Marks that the rider has been paid their delivery fee via bKash "Send
  /// Money" — only possible once the order is 'completed' (enforced by the
  /// DB trigger). [txnId] is an optional reference for the owner's own records.
  Future<bool> confirmRiderPaid(String orderId, {String? txnId}) async {
    final fields = <String, dynamic>{'rider_payout_confirmed': true};
    if (txnId != null && txnId.trim().isNotEmpty) {
      fields['rider_payout_txn_id'] = txnId.trim();
    }
    return _updatePaymentFields(orderId, fields, fallbackError: 'Could not mark the rider as paid. Please check your connection and try again.');
  }

  /// Issues the in-app payment receipt for the customer — a one-shot action,
  /// only available once payment is confirmed (enforced by the DB trigger).
  Future<bool> issueReceipt(String orderId) async {
    return _updatePaymentFields(orderId, {'receipt_issued_at': DateTime.now().toUtc().toIso8601String()},
        fallbackError: 'Could not send the receipt. Please check your connection and try again.');
  }

  Future<bool> _updatePaymentFields(String orderId, Map<String, dynamic> fields, {required String fallbackError}) async {
    try {
      final rows = await _client.from('orders').update(fields).eq('id', orderId).select();
      if (rows.isEmpty) {
        _errorMessage = fallbackError;
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

  /// Fetches average rating for a kitchen owner. Defaults to the currently
  /// loaded kitchen's own owner, but accepts an explicit [ownerId] so any
  /// screen — a customer browsing a kitchen, not just the owner's own
  /// dashboard — can look up any kitchen's rating (ratings are readable by
  /// all authenticated users; nothing here is owner-scoped).
  Future<Map<String, dynamic>> getKitchenRatingStats({String? ownerId}) async {
    final id = ownerId ?? _kitchen?.ownerId;
    if (id == null) return {'rating': 0.0, 'count': 0};
    try {
      final response = await _client
          .from('ratings')
          .select('score')
          .eq('ratee_id', id)
          .eq('rating_type', 'kitchen');

      final ratings = response as List;
      if (ratings.isEmpty) return {'rating': 0.0, 'count': 0};

      final total = ratings.map((r) => r['score'] as int).reduce((a, b) => a + b);
      final avg = total / ratings.length;
      return {'rating': avg, 'count': ratings.length};
    } catch (e) {
      return {'rating': 0.0, 'count': 0};
    }
  }

  /// Loads all reviews customers have left for a kitchen owner, newest
  /// first. Same [ownerId] flexibility as [getKitchenRatingStats] — this is
  /// how customers browsing a kitchen (or anyone else) read its reviews,
  /// not just the owner viewing their own.
  Future<List<Review>> getKitchenReviews({String? ownerId}) async {
    final id = ownerId ?? _kitchen?.ownerId;
    if (id == null) return [];
    try {
      final data = await _client
          .from('ratings')
          .select('id, order_id, rater_id, score, review, created_at, photo_urls')
          .eq('ratee_id', id)
          .eq('rating_type', 'kitchen')
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

  /// Refreshes/updates the kitchen owner's current location coordinates in
  /// their profile — same `profiles` table/columns riders broadcast to, so
  /// customer/rider screens already subscribed to it pick this up for free.
  Future<bool> updateOwnerLocation(String ownerId, double lat, double lng) async {
    try {
      await _client.from('profiles').update({
        'latitude': lat,
        'longitude': lng,
      }).eq('id', ownerId);
      return true;
    } catch (e) {
      _errorMessage = e.toString();
      return false;
    }
  }

  /// Starts a continuous GPS stream and pushes every update to the kitchen
  /// owner's profile row while the kitchen is open for orders.
  Future<void> startLocationTracking(String ownerId) async {
    if (_isTrackingLocation) return;
    final granted = await LocationService.ensurePermissions();
    if (!granted) {
      _errorMessage = 'Location permission denied — live tracking unavailable. Enable location services and grant permission to broadcast your real position to riders/customers instead of your kitchen\'s registered address.';
      notifyListeners();
      return;
    }
    _isTrackingLocation = true;
    _errorMessage = null;
    notifyListeners();

    // Push one immediate fix so riders/customers see the real position right
    // away, rather than waiting for the device to physically move far enough
    // to trigger the first stream event (see getPositionStream's distanceFilter).
    try {
      final position = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      await updateOwnerLocation(ownerId, position.latitude, position.longitude);
    } catch (_) {
      // Fall through to the stream below; it will retry on the next fix.
    }

    _positionSubscription?.cancel();
    _positionSubscription = LocationService.getPositionStream().listen(
      (Position position) {
        updateOwnerLocation(ownerId, position.latitude, position.longitude);
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

  void _setLoading(bool val) {
    _isLoading = val;
    notifyListeners();
  }

  @override
  void dispose() {
    _ordersSubscription?.cancel();
    _positionSubscription?.cancel();
    super.dispose();
  }
}
