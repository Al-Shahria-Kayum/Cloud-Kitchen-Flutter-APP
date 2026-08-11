import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications used to surface order
/// lifecycle events (status changes) to whichever app/role is currently open.
class NotificationService {
  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  static bool _initialized = false;
  static int _idCounter = 0;

  static Future<void> init() async {
    if (_initialized) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings();
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: iosInit,
      macOS: iosInit,
    );
    await _plugin.initialize(initSettings);
    _initialized = true;
  }

  static Future<void> show(String title, String body) async {
    if (!_initialized) await init();
    const androidDetails = AndroidNotificationDetails(
      'order_updates',
      'Order Updates',
      channelDescription: 'Notifications about order status changes',
      importance: Importance.high,
      priority: Priority.high,
    );
    const details = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );
    _idCounter = (_idCounter + 1) % 100000;
    await _plugin.show(_idCounter, title, body, details);
  }

  /// Human-readable message for a given order status, tailored per viewing role.
  static String? messageForStatus(String status, {required String role}) {
    switch (status) {
      case 'accepted':
        return role == 'customer' ? 'Your order was accepted by the kitchen!' : null;
      case 'preparing':
        return role == 'customer' ? 'The kitchen is preparing your order.' : null;
      case 'ready':
        return role == 'kitchen' ? 'Order marked ready for pickup.' : null;
      case 'awaiting_rider':
        return role == 'customer' ? 'Looking for a rider to deliver your order.' : null;
      case 'rider_assigned':
        if (role == 'customer') return 'A rider has been assigned to your order!';
        if (role == 'kitchen') return 'A rider accepted the delivery.';
        return null;
      case 'picked_up':
        if (role == 'customer') return 'Your rider picked up the order.';
        if (role == 'kitchen') return 'Rider picked up the order.';
        return null;
      case 'on_the_way':
        if (role == 'customer') return 'Your rider is on the way!';
        if (role == 'kitchen') return 'Rider is on the way to the customer.';
        return null;
      case 'arrived':
        if (role == 'customer') return 'Your rider has arrived!';
        return null;
      case 'delivered':
        if (role == 'customer') return 'Did you receive your order? Please confirm.';
        if (role == 'kitchen') return 'Rider marked the order as delivered.';
        return null;
      case 'completed':
        if (role == 'kitchen') return 'Customer confirmed delivery. Order completed!';
        if (role == 'rider') return 'Customer confirmed delivery. Order completed!';
        return null;
      case 'rejected':
        if (role == 'customer') return 'Your order was rejected by the kitchen.';
        return null;
      default:
        return null;
    }
  }
}
