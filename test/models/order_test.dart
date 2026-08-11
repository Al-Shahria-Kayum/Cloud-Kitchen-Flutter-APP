import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_kitchen_mvp/models/order.dart';

Map<String, dynamic> _baseOrderJson() => {
      'id': 'order-1',
      'customer_id': 'customer-1',
      'kitchen_id': 'kitchen-1',
      'rider_id': 'rider-1',
      'status': 'picked_up',
      'total_amount': 25.5,
      'commission_amount': 2.5,
      'rider_fee': 5.0,
      'delivery_address': '123 Main St',
      'delivery_latitude': 23.81,
      'delivery_longitude': 90.41,
      'created_at': '2026-08-01T10:00:00Z',
    };

void main() {
  group('Order.fromJson customer contact fields', () {
    test('parses customerName and customerPhone when profiles_customer is present', () {
      final json = _baseOrderJson()
        ..['profiles_customer'] = {'full_name': 'Jane Doe', 'phone': '+8801700000000'};

      final order = Order.fromJson(json);

      expect(order.customerName, 'Jane Doe');
      expect(order.customerPhone, '+8801700000000');
    });

    test('customerPhone is null when the customer has no phone on file', () {
      final json = _baseOrderJson()
        ..['profiles_customer'] = {'full_name': 'Jane Doe', 'phone': null};

      final order = Order.fromJson(json);

      expect(order.customerName, 'Jane Doe');
      expect(order.customerPhone, isNull);
    });

    test('customerName and customerPhone are null when profiles_customer is absent entirely', () {
      final json = _baseOrderJson();

      final order = Order.fromJson(json);

      expect(order.customerName, isNull);
      expect(order.customerPhone, isNull);
    });
  });

  group('rider payment-confirmation gate on delivery confirmation', () {
    test('blocked when delivered and rider has not confirmed payment, well within the timeout', () {
      final json = _baseOrderJson()
        ..['status'] = 'delivered'
        ..['delivered_at'] = DateTime.now().toUtc().subtract(const Duration(hours: 1)).toIso8601String()
        ..['rider_payment_confirmed'] = false;

      final order = Order.fromJson(json);

      expect(order.isRiderPayoutOverdue, isFalse);
      expect(order.isDeliveryConfirmationBlocked, isTrue);
    });

    test('still blocked when the kitchen marked it paid but the rider has not yet confirmed', () {
      // The kitchen owner's claim alone is not enough — the rider must
      // acknowledge actually receiving the money.
      final json = _baseOrderJson()
        ..['status'] = 'delivered'
        ..['delivered_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String()
        ..['rider_payout_confirmed'] = true
        ..['rider_payment_confirmed'] = false;

      final order = Order.fromJson(json);

      expect(order.isDeliveryConfirmationBlocked, isTrue);
    });

    test('not blocked once the rider has confirmed payment, even immediately after delivery', () {
      final json = _baseOrderJson()
        ..['status'] = 'delivered'
        ..['delivered_at'] = DateTime.now().toUtc().subtract(const Duration(minutes: 1)).toIso8601String()
        ..['rider_payout_confirmed'] = true
        ..['rider_payment_confirmed'] = true;

      final order = Order.fromJson(json);

      expect(order.isDeliveryConfirmationBlocked, isFalse);
    });

    test('safety valve: unblocked once the payout timeout has elapsed, even if the rider never confirmed', () {
      final json = _baseOrderJson()
        ..['status'] = 'delivered'
        ..['delivered_at'] = DateTime.now().toUtc().subtract(const Duration(hours: 25)).toIso8601String()
        ..['rider_payment_confirmed'] = false;

      final order = Order.fromJson(json);

      expect(order.isRiderPayoutOverdue, isTrue);
      expect(order.isDeliveryConfirmationBlocked, isFalse);
    });

    test('not blocked for statuses other than delivered, regardless of payment-confirmation state', () {
      final json = _baseOrderJson()
        ..['status'] = 'on_the_way'
        ..['rider_payment_confirmed'] = false;

      final order = Order.fromJson(json);

      expect(order.isDeliveryConfirmationBlocked, isFalse);
    });

    test('never overdue when delivered_at is missing', () {
      final json = _baseOrderJson()
        ..['status'] = 'delivered'
        ..['rider_payment_confirmed'] = false;

      final order = Order.fromJson(json);

      expect(order.isRiderPayoutOverdue, isFalse);
      expect(order.isDeliveryConfirmationBlocked, isTrue);
    });
  });
}
