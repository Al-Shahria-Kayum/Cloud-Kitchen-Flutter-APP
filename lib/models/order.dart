class OrderItem {
  final String id;
  final String orderId;
  final String menuItemId;
  final String menuItemName;
  final int quantity;
  final double price;

  OrderItem({
    required this.id,
    required this.orderId,
    required this.menuItemId,
    required this.menuItemName,
    required this.quantity,
    required this.price,
  });

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    return OrderItem(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      menuItemId: json['menu_item_id'] as String,
      menuItemName: json['menu_items'] != null ? (json['menu_items']['name'] as String) : '',
      quantity: json['quantity'] as int,
      price: (json['price'] as num).toDouble(),
    );
  }
}

class Order {
  final String id;
  final String customerId;
  final String kitchenId;
  final String? riderId;
  final String status;
  // pending, accepted, rejected, preparing, ready, awaiting_rider, rider_assigned,
  // picked_up, on_the_way, arrived, delivered (awaiting customer confirmation), completed
  final double totalAmount;
  final double commissionAmount;
  final double riderFee;
  final String deliveryAddress;
  final double deliveryLatitude;
  final double deliveryLongitude;
  final bool confirmedByCustomer;
  final DateTime? acceptedAt;
  final DateTime? readyAt;
  final DateTime? pickedUpAt;
  final DateTime? deliveredAt;
  final DateTime? confirmedAt;
  final DateTime? completedAt;
  final DateTime createdAt;

  // Manual bKash payment lifecycle: customer sends money via bKash "Send
  // Money", reports the transaction ID, and the kitchen owner confirms
  // receipt before accepting the order.
  final String paymentStatus; // awaiting_payment, payment_reported, payment_confirmed
  final String? customerBkashTxnId;
  final DateTime? paymentReportedAt;
  final DateTime? paymentConfirmedAt;

  // Rider payout: kitchen owner sends the rider's fee via bKash once the
  // order is delivered, then the rider confirms they actually received it —
  // that final confirmation, not the kitchen owner's claim, is what unblocks
  // the customer (see isDeliveryConfirmationBlocked).
  final bool riderPayoutConfirmed;
  final String? riderPayoutTxnId;
  final DateTime? riderPaidAt;
  final bool riderPaymentConfirmed;
  final DateTime? riderPaymentConfirmedAt;

  // Set once the kitchen owner issues an in-app payment receipt to the customer.
  final DateTime? receiptIssuedAt;

  // Safety valve for the riderPayoutConfirmed gate on customer delivery
  // confirmation (see isDeliveryConfirmationBlocked): if the kitchen owner
  // never pays the rider, the order would otherwise stay stuck "delivered"
  // forever. Once delivered_at is older than the timeout, confirmation is
  // allowed to proceed anyway, and this timestamp is stamped so the kitchen
  // owner's account can be flagged for payout follow-up/collection.
  final DateTime? payoutOverdueFlaggedAt;

  // Joined fields for easy UI display
  final String? kitchenName;
  final String? customerName;
  final String? customerPhone;
  final String? riderName;
  final String? kitchenBkashNumber;
  final String? riderBkashNumber;
  final double? kitchenLatitude;
  final double? kitchenLongitude;
  final List<OrderItem>? items;

  Order({
    required this.id,
    required this.customerId,
    required this.kitchenId,
    this.riderId,
    required this.status,
    required this.totalAmount,
    required this.commissionAmount,
    required this.riderFee,
    required this.deliveryAddress,
    required this.deliveryLatitude,
    required this.deliveryLongitude,
    this.confirmedByCustomer = false,
    this.acceptedAt,
    this.readyAt,
    this.pickedUpAt,
    this.deliveredAt,
    this.confirmedAt,
    this.completedAt,
    required this.createdAt,
    this.paymentStatus = 'awaiting_payment',
    this.customerBkashTxnId,
    this.paymentReportedAt,
    this.paymentConfirmedAt,
    this.riderPayoutConfirmed = false,
    this.riderPayoutTxnId,
    this.riderPaidAt,
    this.riderPaymentConfirmed = false,
    this.riderPaymentConfirmedAt,
    this.receiptIssuedAt,
    this.payoutOverdueFlaggedAt,
    this.kitchenName,
    this.customerName,
    this.customerPhone,
    this.riderName,
    this.kitchenBkashNumber,
    this.riderBkashNumber,
    this.kitchenLatitude,
    this.kitchenLongitude,
    this.items,
  });

  bool get isPaymentConfirmed => paymentStatus == 'payment_confirmed';

  /// The timeout after which a customer's delivery confirmation is allowed
  /// to proceed even if the kitchen owner still hasn't paid the rider (see
  /// [isDeliveryConfirmationBlocked]) — the safety valve for item 3's
  /// riderPaid gate, so an unpaid rider never traps the customer's order in
  /// "delivered" limbo indefinitely.
  static const Duration riderPayoutTimeout = Duration(hours: 24);

  /// Whether the timeout above has elapsed for this delivered order.
  bool get isRiderPayoutOverdue {
    if (deliveredAt == null) return false;
    return DateTime.now().toUtc().difference(deliveredAt!.toUtc()) > riderPayoutTimeout;
  }

  /// True while the customer's "Confirm Delivery" action should be blocked
  /// because the rider hasn't yet confirmed receiving their bKash payout
  /// from the kitchen owner (the kitchen marking it "paid" alone isn't
  /// enough — the rider has to acknowledge it) — unless the timeout safety
  /// valve has kicked in, in which case confirmation is allowed through
  /// (and the kitchen owner's account gets flagged).
  bool get isDeliveryConfirmationBlocked =>
      status == 'delivered' && !riderPaymentConfirmed && !isRiderPayoutOverdue;

  factory Order.fromJson(Map<String, dynamic> json) {
    // Parse items if available
    List<OrderItem>? itemsList;
    if (json['order_items'] != null) {
      itemsList = (json['order_items'] as List)
          .map((i) => OrderItem.fromJson(i as Map<String, dynamic>))
          .toList();
    }

    return Order(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      kitchenId: json['kitchen_id'] as String,
      riderId: json['rider_id'] as String?,
      status: json['status'] as String,
      totalAmount: (json['total_amount'] as num).toDouble(),
      commissionAmount: (json['commission_amount'] as num).toDouble(),
      riderFee: (json['rider_fee'] as num).toDouble(),
      deliveryAddress: json['delivery_address'] as String,
      deliveryLatitude: (json['delivery_latitude'] as num).toDouble(),
      deliveryLongitude: (json['delivery_longitude'] as num).toDouble(),
      confirmedByCustomer: json['confirmed_by_customer'] as bool? ?? false,
      acceptedAt: json['accepted_at'] != null ? DateTime.parse(json['accepted_at'] as String) : null,
      readyAt: json['ready_at'] != null ? DateTime.parse(json['ready_at'] as String) : null,
      pickedUpAt: json['picked_up_at'] != null ? DateTime.parse(json['picked_up_at'] as String) : null,
      deliveredAt: json['delivered_at'] != null ? DateTime.parse(json['delivered_at'] as String) : null,
      confirmedAt: json['confirmed_at'] != null ? DateTime.parse(json['confirmed_at'] as String) : null,
      completedAt: json['completed_at'] != null ? DateTime.parse(json['completed_at'] as String) : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      paymentStatus: json['payment_status'] as String? ?? 'awaiting_payment',
      customerBkashTxnId: json['customer_bkash_txn_id'] as String?,
      paymentReportedAt: json['payment_reported_at'] != null ? DateTime.parse(json['payment_reported_at'] as String) : null,
      paymentConfirmedAt: json['payment_confirmed_at'] != null ? DateTime.parse(json['payment_confirmed_at'] as String) : null,
      riderPayoutConfirmed: json['rider_payout_confirmed'] as bool? ?? false,
      riderPayoutTxnId: json['rider_payout_txn_id'] as String?,
      riderPaidAt: json['rider_paid_at'] != null ? DateTime.parse(json['rider_paid_at'] as String) : null,
      riderPaymentConfirmed: json['rider_payment_confirmed'] as bool? ?? false,
      riderPaymentConfirmedAt: json['rider_payment_confirmed_at'] != null ? DateTime.parse(json['rider_payment_confirmed_at'] as String) : null,
      receiptIssuedAt: json['receipt_issued_at'] != null ? DateTime.parse(json['receipt_issued_at'] as String) : null,
      payoutOverdueFlaggedAt: json['payout_overdue_flagged_at'] != null ? DateTime.parse(json['payout_overdue_flagged_at'] as String) : null,
      kitchenName: json['kitchens'] != null ? json['kitchens']['name'] as String? : null,
      customerName: json['profiles_customer'] != null ? json['profiles_customer']['full_name'] as String? : null,
      customerPhone: json['profiles_customer'] != null ? json['profiles_customer']['phone'] as String? : null,
      riderName: json['profiles_rider'] != null ? json['profiles_rider']['full_name'] as String? : null,
      kitchenBkashNumber: json['kitchen_owner_bkash'] as String?,
      riderBkashNumber: json['rider_bkash'] as String?,
      kitchenLatitude: json['kitchen_latitude'] != null ? (json['kitchen_latitude'] as num).toDouble() : null,
      kitchenLongitude: json['kitchen_longitude'] != null ? (json['kitchen_longitude'] as num).toDouble() : null,
      items: itemsList,
    );
  }
}
