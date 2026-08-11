import 'package:flutter_test/flutter_test.dart';
import 'package:cloud_kitchen_mvp/utils/delivery_stage.dart';

void main() {
  group('isCustomerContactUnlocked', () {
    test('locked before pickup', () {
      expect(isCustomerContactUnlocked('pending'), isFalse);
      expect(isCustomerContactUnlocked('accepted'), isFalse);
      expect(isCustomerContactUnlocked('preparing'), isFalse);
      expect(isCustomerContactUnlocked('ready'), isFalse);
      expect(isCustomerContactUnlocked('awaiting_rider'), isFalse);
      expect(isCustomerContactUnlocked('rider_assigned'), isFalse);
    });

    test('unlocked from pickup onward', () {
      expect(isCustomerContactUnlocked('picked_up'), isTrue);
      expect(isCustomerContactUnlocked('on_the_way'), isTrue);
      expect(isCustomerContactUnlocked('arrived'), isTrue);
      expect(isCustomerContactUnlocked('delivered'), isTrue);
    });

    test('locked again once fully completed (no active delivery to protect)', () {
      // 'completed' is intentionally excluded — the rider's UI navigates away
      // before this status is reachable, but the rule itself must not treat
      // "completed" as an ongoing delivery.
      expect(isCustomerContactUnlocked('completed'), isFalse);
    });

    test('null and unknown statuses stay locked (fail closed)', () {
      expect(isCustomerContactUnlocked(null), isFalse);
      expect(isCustomerContactUnlocked('rejected'), isFalse);
      expect(isCustomerContactUnlocked('bogus_status'), isFalse);
    });
  });

  group('isRiderContactUnlocked', () {
    test('locked before pickup', () {
      expect(isRiderContactUnlocked('pending'), isFalse);
      expect(isRiderContactUnlocked('accepted'), isFalse);
      expect(isRiderContactUnlocked('awaiting_rider'), isFalse);
      expect(isRiderContactUnlocked('rider_assigned'), isFalse);
    });

    test('unlocked from pickup through completed — the owner needs it at payout time', () {
      expect(isRiderContactUnlocked('picked_up'), isTrue);
      expect(isRiderContactUnlocked('on_the_way'), isTrue);
      expect(isRiderContactUnlocked('arrived'), isTrue);
      expect(isRiderContactUnlocked('delivered'), isTrue);
      expect(isRiderContactUnlocked('completed'), isTrue);
    });

    test('null and unknown statuses stay locked (fail closed)', () {
      expect(isRiderContactUnlocked(null), isFalse);
      expect(isRiderContactUnlocked('rejected'), isFalse);
      expect(isRiderContactUnlocked('bogus_status'), isFalse);
    });
  });
}
