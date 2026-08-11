import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../providers/rider_provider.dart';
import '../../services/notification_service.dart';
import '../../services/receipt_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/status_pill.dart';
import '../shared/chat_screen.dart';
import '../shared/ratings_screen.dart';
import '../shared/reviews_screen.dart';

class CustomerOrderDetailsScreen extends StatefulWidget {
  final Order order;
  const CustomerOrderDetailsScreen({super.key, required this.order});

  @override
  State<CustomerOrderDetailsScreen> createState() =>
      _CustomerOrderDetailsScreenState();
}

class _CustomerOrderDetailsScreenState
    extends State<CustomerOrderDetailsScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  LatLng? _kitchenLatLng;
  LatLng? _kitchenStaticLatLng;
  LatLng? _riderLatLng;
  LatLng? _deliveryLatLng;
  bool _isLoadingMap = true;
  StreamSubscription<List<Map<String, dynamic>>>? _orderStatusSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _riderLocationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _kitchenLocationSubscription;
  Order? _currentOrder;

  String? _kitchenBkashNumber;
  final TextEditingController _txnIdController = TextEditingController();
  bool _isSubmittingPayment = false;
  bool _isDownloadingReceipt = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _deliveryLatLng = LatLng(
      widget.order.deliveryLatitude,
      widget.order.deliveryLongitude,
    );
    _loadCoordinatesAndSubscribe();
  }

  @override
  void dispose() {
    _orderStatusSubscription?.cancel();
    _riderLocationSubscription?.cancel();
    _kitchenLocationSubscription?.cancel();
    _txnIdController.dispose();
    super.dispose();
  }

  Future<void> _loadCoordinatesAndSubscribe() async {
    try {
      // Load kitchen coordinates (+ owner_id so we can track the kitchen live)
      final kitchenData = await _client
          .from('kitchens')
          .select('latitude, longitude, owner_id')
          .eq('id', _currentOrder!.kitchenId)
          .single();

      _kitchenStaticLatLng = LatLng(
        (kitchenData['latitude'] as num).toDouble(),
        (kitchenData['longitude'] as num).toDouble(),
      );
      _kitchenLatLng = _kitchenStaticLatLng;

      if (kitchenData['owner_id'] != null) {
        _subscribeToKitchenLocation(kitchenData['owner_id'] as String);
      }

      setState(() {
        _isLoadingMap = false;
      });

      // Subscribe to order changes (to update status and rider ID in real-time)
      _orderStatusSubscription = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('id', _currentOrder!.id)
          .listen((List<Map<String, dynamic>> data) async {
            if (data.isNotEmpty) {
              final item = data.first;

              // Load joined names
              final kitchenDetails = await _client
                  .from('kitchens')
                  .select('name')
                  .eq('id', item['kitchen_id'])
                  .single();

              final customerDetails = await _client
                  .from('profiles')
                  .select('full_name')
                  .eq('id', item['customer_id'])
                  .single();

              final orderItemsData = await _client
                  .from('order_items')
                  .select('*, menu_items(name)')
                  .eq('order_id', item['id']);

              final combined = Map<String, dynamic>.from(item);
              combined['kitchens'] = {'name': kitchenDetails['name']};
              combined['profiles_customer'] = {
                'full_name': customerDetails['full_name'],
              };
              combined['order_items'] = orderItemsData;

              if (item['rider_id'] != null) {
                final riderDetails = await _client
                    .from('profiles')
                    .select('full_name')
                    .eq('id', item['rider_id'])
                    .single();
                combined['profiles_rider'] = {
                  'full_name': riderDetails['full_name'],
                };

                // Track Rider coordinates in real-time
                _subscribeToRiderLocation(item['rider_id'] as String);
              }

              final String previousStatus = _currentOrder?.status ?? '';
              final Order updated = Order.fromJson(combined);
              if (updated.status != previousStatus) {
                final msg = NotificationService.messageForStatus(updated.status, role: 'customer');
                if (msg != null) NotificationService.show('Order Update', msg);
              }

              setState(() {
                _currentOrder = updated;
              });

              // Re-checked on every update (not just status changes) because
              // the rider-payout confirmation that unblocks this is a
              // separate field flip while status stays 'delivered'.
              _maybeHandleDeliveryConfirmation(updated);
            }
          });
    } catch (e) {
      setState(() {
        _isLoadingMap = false;
      });
    }
  }

  /// Tracks the kitchen owner's live position while they broadcast it (e.g.
  /// while the kitchen is open). Falls back to the kitchen's static address
  /// coordinates if the owner's profile has never broadcast a location.
  void _subscribeToKitchenLocation(String ownerId) {
    _kitchenLocationSubscription?.cancel();
    _kitchenLocationSubscription = _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', ownerId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            final profile = data.first;
            setState(() {
              if (profile['latitude'] != null && profile['longitude'] != null) {
                _kitchenLatLng = LatLng(
                  (profile['latitude'] as num).toDouble(),
                  (profile['longitude'] as num).toDouble(),
                );
              } else {
                _kitchenLatLng = _kitchenStaticLatLng;
              }
              // The kitchen owner's bKash number — private until an order
              // exists between this customer and this kitchen, which is
              // exactly the context this screen only opens in.
              _kitchenBkashNumber = profile['bkash_number'] as String?;
            });
          }
        });
  }

  Future<void> _reportPayment() async {
    final txnId = _txnIdController.text.trim();
    if (txnId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Enter the bKash transaction ID from your payment SMS.'), backgroundColor: Theme.of(context).colorScheme.error),
      );
      return;
    }
    setState(() => _isSubmittingPayment = true);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final success = await customerProvider.reportPayment(orderId: _currentOrder!.id, bkashTxnId: txnId);
    if (!mounted) return;
    setState(() => _isSubmittingPayment = false);
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text("Payment reported! We'll notify you once the kitchen confirms."), backgroundColor: context.appColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(customerProvider.errorMessage, fallback: 'Could not report payment. Please try again.')), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _showReceiptSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ReceiptSheet(order: _currentOrder!, kitchenBkashNumber: _kitchenBkashNumber),
    );
  }

  Future<void> _downloadReceiptPdf() async {
    setState(() => _isDownloadingReceipt = true);
    try {
      await ReceiptPdfService.downloadReceipt(order: _currentOrder!, forKitchenOwner: false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Could not generate the receipt. Please try again.'), backgroundColor: Theme.of(context).colorScheme.error),
        );
      }
    } finally {
      if (mounted) setState(() => _isDownloadingReceipt = false);
    }
  }

  Future<void> _showRiderReviews(String riderId, String riderName) async {
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    final stats = await riderProvider.getRiderRatingStats(riderId);
    if (!mounted) return;
    Navigator.of(context).push(
      appPageRoute(
        ReviewsScreen(
          title: '$riderName — Reviews',
          avgRating: stats['rating'] as double,
          reviewCount: stats['count'] as int,
          loadReviews: () => riderProvider.getRiderReviews(riderId),
        ),
      ),
    );
  }

  void _subscribeToRiderLocation(String riderId) {
    _riderLocationSubscription?.cancel();
    _riderLocationSubscription = _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', riderId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            final profile = data.first;
            if (profile['latitude'] != null && profile['longitude'] != null) {
              setState(() {
                _riderLatLng = LatLng(
                  (profile['latitude'] as num).toDouble(),
                  (profile['longitude'] as num).toDouble(),
                );
              });
            }
          }
        });
  }

  bool _confirmDialogShown = false;
  bool _autoConfirmAttempted = false;

  /// Decides what to do once an order sits at 'delivered': prompt the
  /// customer once the kitchen has paid the rider, or — if the 24h payout
  /// timeout has elapsed and the rider still hasn't been paid — auto-confirm
  /// without waiting for a tap, so an unpaid rider can never trap this order.
  /// Called on every realtime update while 'delivered' (not just the status
  /// transition into it), since the payout confirmation that unblocks this
  /// is a separate field flip that doesn't change `status`.
  void _maybeHandleDeliveryConfirmation(Order order) {
    if (order.status != 'delivered' || order.confirmedByCustomer) return;

    if (!order.isDeliveryConfirmationBlocked) {
      if (order.riderPaymentConfirmed) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _showConfirmDeliveryDialog());
      } else if (order.isRiderPayoutOverdue && !_autoConfirmAttempted) {
        _autoConfirmAttempted = true;
        _autoConfirmAfterPayoutTimeout();
      }
    }
  }

  Future<void> _autoConfirmAfterPayoutTimeout() async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final success = await customerProvider.confirmDelivery(_currentOrder!.id);
    if (!mounted || !success) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text(
          "Your order has been auto-confirmed — the kitchen hadn't paid the rider within 24h, so we didn't make you wait any longer. Their account has been flagged for follow-up.",
        ),
        backgroundColor: context.appColors.warning,
        duration: const Duration(seconds: 6),
      ),
    );
  }

  void _showConfirmDeliveryDialog() {
    if (_confirmDialogShown || !mounted) return;
    if (_currentOrder?.status != 'delivered') return;
    _confirmDialogShown = true;

    final scheme = Theme.of(context).colorScheme;
    final success = context.appColors.success;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Did you receive your order?'),
        content: const Text(
          'The rider has marked this order as delivered. Please confirm to complete the order.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _confirmDialogShown = false;
            },
            child: const Text('Not yet'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: success, foregroundColor: scheme.onPrimary),
            onPressed: () async {
              Navigator.pop(ctx);
              await _confirmDelivery();
            },
            child: const Text('Confirm Delivery'),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelivery() async {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final success = await customerProvider.confirmDelivery(_currentOrder!.id);
    if (!mounted) return;
    final appColors = context.appColors;
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Delivery confirmed! Order completed.'), backgroundColor: appColors.success),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(customerProvider.errorMessage, fallback: 'Failed to confirm delivery. Please try again.')), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_currentOrder == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String status = _currentOrder!.status;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Order'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: kBrandGradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Live status hero — fades between states as realtime updates arrive.
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: _StatusHero(status: status),
            ),

            const SizedBox(height: AppSpacing.lg),

            // Map card
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _MapCard(
                height: 230,
                isLoading: _isLoadingMap,
                initialCenter: _riderLatLng ?? _kitchenLatLng ?? _deliveryLatLng ?? const LatLng(23.8103, 90.4125),
                kitchenLatLng: _kitchenLatLng,
                deliveryLatLng: _deliveryLatLng,
                riderLatLng: _riderLatLng,
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('From: ${_currentOrder!.kitchenName ?? "Kitchen"}', style: textTheme.titleMedium),
                          const SizedBox(height: 2),
                          LiveLocationText(
                            latitude: _kitchenLatLng?.latitude,
                            longitude: _kitchenLatLng?.longitude,
                            style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                            icon: Icons.storefront_rounded,
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text('Delivery Address: ${_currentOrder!.deliveryAddress}', style: textTheme.bodyMedium),
                          if (_currentOrder!.riderName != null && _currentOrder!.riderId != null) ...[
                            const Divider(),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Rider: ${_currentOrder!.riderName}', style: textTheme.titleSmall),
                                InkWell(
                                  borderRadius: AppRadius.mdBr,
                                  onTap: () => _showRiderReviews(_currentOrder!.riderId!, _currentOrder!.riderName!),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(Icons.star_rounded, size: 15, color: context.appColors.ratingStar),
                                        const SizedBox(width: 2),
                                        Text('Reviews', style: textTheme.labelSmall),
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (status != 'rejected') _buildPaymentCard(),
                  if (status != 'rejected') const SizedBox(height: AppSpacing.lg),
                  _buildProgressTimeline(status),
                  const SizedBox(height: AppSpacing.lg),

                  // Order items list
                  Text('Items ordered', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (_currentOrder!.items != null)
                    ..._currentOrder!.items!.map(
                      (item) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text('${item.menuItemName} x${item.quantity}'),
                        trailing: Text(
                          formatCurrency(item.price * item.quantity),
                          style: textTheme.titleSmall,
                        ),
                      ),
                    ),

                  const Divider(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Total Paid', style: textTheme.titleMedium),
                      Text(
                        formatCurrency(_currentOrder!.totalAmount),
                        style: textTheme.headlineSmall?.copyWith(color: scheme.primary),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Confirm delivery prompt (in case the popup was dismissed) —
                  // gated on the kitchen having paid the rider (with the 24h
                  // timeout safety valve so this can never block indefinitely).
                  if (status == 'delivered') ...[
                    if (_currentOrder!.isDeliveryConfirmationBlocked)
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(color: context.appColors.warningContainer, borderRadius: AppRadius.mdBr),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.hourglass_top_rounded, size: 18, color: context.appColors.warning),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                'Waiting for the rider to confirm they received their payment from the kitchen before you can confirm delivery. '
                                "This will unlock automatically within 24h even if that doesn't happen in time.",
                                style: textTheme.bodyMedium?.copyWith(color: context.appColors.onWarningContainer),
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      ElevatedButton.icon(
                        onPressed: _confirmDelivery,
                        style: ElevatedButton.styleFrom(backgroundColor: context.appColors.success),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Confirm Delivery'),
                      ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Actions row: Chat (if active)
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            Navigator.of(context).push(
                              appPageRoute(
                                ChatScreen(
                                  orderId: _currentOrder!.id,
                                  senderId: Provider.of<AuthProvider>(
                                    context,
                                    listen: false,
                                  ).profile!.id,
                                ),
                              ),
                            );
                          },
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Order Chat'),
                        ),
                      ),

                      // Ratings screen trigger (only once fully completed)
                      if (status == 'completed') ...[
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.of(context).push(
                                appPageRoute(RatingsScreen(order: _currentOrder!)),
                              );
                            },
                            icon: Icon(Icons.star_outline, color: context.appColors.ratingStar),
                            label: const Text('Rate Order'),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (status == 'completed') ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _isDownloadingReceipt ? null : _downloadReceiptPdf,
                      icon: _isDownloadingReceipt
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: const Text('Download Receipt'),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The manual bKash payment step — instructions to send money, a place to
  /// report the transaction ID, or (once confirmed) the receipt entry point.
  Widget _buildPaymentCard() {
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final order = _currentOrder!;

    switch (order.paymentStatus) {
      case 'payment_confirmed':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.check_circle_rounded, color: appColors.success, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('Payment confirmed', style: textTheme.titleMedium?.copyWith(color: appColors.success))),
                  ],
                ),
                if (order.customerBkashTxnId != null) ...[
                  const SizedBox(height: 4),
                  Text('TrxID: ${order.customerBkashTxnId}', style: textTheme.bodySmall),
                ],
                const SizedBox(height: AppSpacing.md),
                if (order.receiptIssuedAt != null)
                  OutlinedButton.icon(
                    onPressed: _showReceiptSheet,
                    icon: const Icon(Icons.receipt_long_outlined, size: 18),
                    label: const Text('View Receipt'),
                  )
                else
                  Row(
                    children: [
                      Icon(Icons.info_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          "The kitchen hasn't sent your receipt yet.",
                          style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        );

      case 'payment_reported':
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.hourglass_top_rounded, color: appColors.warning, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(child: Text('Payment reported', style: textTheme.titleMedium?.copyWith(color: appColors.warning))),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  "We've told the kitchen you sent ${formatCurrency(order.totalAmount)} via bKash. "
                  "They'll confirm once they've verified it in their bKash app.",
                  style: textTheme.bodyMedium,
                ),
                if (order.customerBkashTxnId != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text('TrxID: ${order.customerBkashTxnId}', style: textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ],
            ),
          ),
        );

      default: // awaiting_payment
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.payments_outlined, color: scheme.primary, size: 20),
                    const SizedBox(width: AppSpacing.sm),
                    Text('Pay via bKash', style: textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (_kitchenBkashNumber == null || _kitchenBkashNumber!.isEmpty)
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.4), borderRadius: AppRadius.mdBr),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline_rounded, size: 15, color: scheme.error),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            "This kitchen hasn't set up their bKash number yet. Please contact them via chat.",
                            style: textTheme.bodySmall?.copyWith(color: scheme.error),
                          ),
                        ),
                      ],
                    ),
                  )
                else ...[
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: AppRadius.mdBr),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('1. Open bKash → Send Money to:', style: textTheme.bodyMedium),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _kitchenBkashNumber!,
                                style: textTheme.headlineSmall?.copyWith(letterSpacing: 1.0),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Copy number',
                              icon: const Icon(Icons.copy_rounded, size: 18),
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: _kitchenBkashNumber!));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('bKash number copied')));
                                }
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text('2. Send exactly:', style: textTheme.bodyMedium),
                        const SizedBox(height: 2),
                        Text(
                          formatCurrency(order.totalAmount),
                          style: textTheme.headlineSmall?.copyWith(color: scheme.primary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text('3. Enter the Transaction ID from your bKash confirmation SMS:', style: textTheme.bodyMedium),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(
                    controller: _txnIdController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'bKash Transaction ID',
                      hintText: 'e.g. 8N7A9X2K1P',
                      prefixIcon: Icon(Icons.confirmation_number_outlined),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSubmittingPayment ? null : _reportPayment,
                      child: _isSubmittingPayment
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text("I've Sent the Payment"),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
    }
  }

  Widget _buildProgressTimeline(String status) {
    const stages = [
      {'key': 'pending', 'label': 'Placed'},
      {'key': 'accepted', 'label': 'Accepted'},
      {'key': 'preparing', 'label': 'Preparing'},
      {'key': 'ready', 'label': 'Ready'},
      {'key': 'rider_assigned', 'label': 'Rider Assigned'},
      {'key': 'picked_up', 'label': 'Picked Up'},
      {'key': 'on_the_way', 'label': 'On The Way'},
      {'key': 'delivered', 'label': 'Delivered'},
      {'key': 'completed', 'label': 'Completed'},
    ];

    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final success = context.appColors.success;

    if (status == 'rejected') {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(color: scheme.error.withValues(alpha: 0.1), borderRadius: AppRadius.mdBr),
        child: Row(
          children: [
            Icon(Icons.cancel_rounded, color: scheme.error, size: 18),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                'This order was rejected by the kitchen.',
                style: textTheme.labelLarge?.copyWith(color: scheme.error),
              ),
            ),
          ],
        ),
      );
    }

    // 'awaiting_rider' and 'arrived' collapse onto the nearest visible stage for a compact timeline.
    final effectiveStatus = status == 'awaiting_rider'
        ? 'ready'
        : status == 'arrived'
        ? 'picked_up'
        : status;
    final currentIndex = stages.indexWhere((s) => s['key'] == effectiveStatus);

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg, horizontal: AppSpacing.md),
        child: SizedBox(
          height: 72,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: stages.length,
            itemBuilder: (context, index) {
              final bool done = currentIndex >= 0 && index <= currentIndex;
              final bool isCurrent = index == currentIndex;
              return Row(
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AnimatedContainer(
                        duration: AppMotion.base,
                        curve: AppMotion.curve,
                        width: isCurrent ? 26 : 22,
                        height: isCurrent ? 26 : 22,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? success : scheme.outline.withValues(alpha: 0.25),
                          border: isCurrent ? Border.all(color: success.withValues(alpha: 0.35), width: 4) : null,
                        ),
                        child: Icon(
                          done ? Icons.check_rounded : Icons.circle,
                          color: done ? Colors.white : Colors.transparent,
                          size: isCurrent ? 15 : 12,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: 62,
                        child: Text(
                          stages[index]['label'] as String,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textTheme.labelSmall?.copyWith(
                            color: done ? scheme.onSurface : scheme.onSurface.withValues(alpha: 0.45),
                            fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (index != stages.length - 1)
                    Container(
                      width: 28,
                      height: 2.5,
                      margin: const EdgeInsets.only(bottom: 22),
                      decoration: BoxDecoration(
                        color: done && index < currentIndex ? success : scheme.outline.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A bigger, more premium status presence than a plain pill — used at the top
/// of every order-detail screen. Fades between states so a realtime update
/// reads as a transition rather than a snap.
class _StatusHero extends StatelessWidget {
  final String status;
  const _StatusHero({required this.status});

  @override
  Widget build(BuildContext context) {
    final meta = OrderStatusMeta.of(context, status);
    final textTheme = Theme.of(context).textTheme;
    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(animation), child: child),
      ),
      child: Container(
        key: ValueKey(status),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md + 2),
        decoration: BoxDecoration(color: meta.bg, borderRadius: AppRadius.lgBr),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: meta.fg.withValues(alpha: 0.16), shape: BoxShape.circle),
              child: Icon(meta.icon, color: meta.fg, size: 22),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(meta.label, style: textTheme.titleLarge?.copyWith(color: meta.fg)),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared framed map: rounded card, subtle shadow, pin-style markers instead
/// of bare floating icons. Tile layer/attribution left untouched.
class _MapCard extends StatelessWidget {
  final double height;
  final bool isLoading;
  final LatLng initialCenter;
  final LatLng? kitchenLatLng;
  final LatLng? deliveryLatLng;
  final LatLng? riderLatLng;

  const _MapCard({
    required this.height,
    required this.isLoading,
    required this.initialCenter,
    this.kitchenLatLng,
    this.deliveryLatLng,
    this.riderLatLng,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    return Container(
      height: height,
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgBr,
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.10), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: scheme.surfaceContainerHighest,
        child: isLoading
            ? Center(child: CircularProgressIndicator(color: scheme.primary))
            : FlutterMap(
                options: MapOptions(initialCenter: initialCenter, initialZoom: 14.0),
                children: [
                  TileLayer(
                    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'com.cloudkitchen.mvp',
                  ),
                  MarkerLayer(
                    markers: [
                      if (kitchenLatLng != null)
                        Marker(
                          point: kitchenLatLng!,
                          width: 40,
                          height: 40,
                          child: _MapPin(icon: Icons.store, color: appColors.mapKitchen),
                        ),
                      if (deliveryLatLng != null)
                        Marker(
                          point: deliveryLatLng!,
                          width: 40,
                          height: 40,
                          child: _MapPin(icon: Icons.location_on, color: appColors.mapCustomer),
                        ),
                      if (riderLatLng != null)
                        Marker(
                          point: riderLatLng!,
                          width: 40,
                          height: 40,
                          child: _MapPin(icon: Icons.delivery_dining, color: appColors.mapRider),
                        ),
                    ],
                  ),
                ],
              ),
      ),
    );
  }
}

/// A pin-styled marker: white circular backing + colored border/icon so it
/// reads as a map pin rather than a floating icon.
class _MapPin extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _MapPin({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2.5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 4, offset: const Offset(0, 2))],
      ),
      child: Icon(icon, color: color, size: 18),
    );
  }
}

/// The in-app payment receipt — generated on the fly from the order's own
/// fields rather than a separately-stored document, and issued to the
/// customer the moment the kitchen owner taps "Send Receipt" (see
/// kitchen_order_details_screen). No SMS/email is sent; it simply appears here.
class _ReceiptSheet extends StatelessWidget {
  final Order order;
  final String? kitchenBkashNumber;
  const _ReceiptSheet({required this.order, required this.kitchenBkashNumber});

  String _formatDate(DateTime dt) {
    final local = dt.toLocal();
    return '${local.day}/${local.month}/${local.year} at ${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.xl, AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: AppSpacing.lg),
                decoration: BoxDecoration(color: scheme.outline, borderRadius: AppRadius.pillBr),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: appColors.successContainer, shape: BoxShape.circle),
                  child: Icon(Icons.receipt_long_rounded, color: appColors.onSuccessContainer, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Payment Receipt', style: text.titleLarge)),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            _ReceiptRow(label: 'Kitchen', value: order.kitchenName ?? 'Kitchen'),
            _ReceiptRow(label: 'Order ID', value: '#${order.id.substring(0, 8).toUpperCase()}'),
            if (kitchenBkashNumber != null) _ReceiptRow(label: 'Paid to (bKash)', value: kitchenBkashNumber!),
            if (order.customerBkashTxnId != null) _ReceiptRow(label: 'Transaction ID', value: order.customerBkashTxnId!),
            if (order.paymentConfirmedAt != null) _ReceiptRow(label: 'Confirmed on', value: _formatDate(order.paymentConfirmedAt!)),
            const SizedBox(height: AppSpacing.md),
            const Divider(),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Amount Paid', style: text.titleMedium),
                Text(
                  formatCurrency(order.totalAmount),
                  style: text.headlineSmall?.copyWith(color: appColors.success),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReceiptRow extends StatelessWidget {
  final String label;
  final String value;
  const _ReceiptRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
          Flexible(
            child: Text(value, textAlign: TextAlign.right, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}
