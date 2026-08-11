import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kitchen_provider.dart';
import '../../providers/rider_provider.dart';
import '../../services/notification_service.dart';
import '../../services/receipt_pdf_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/delivery_stage.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/status_pill.dart';
import '../shared/chat_screen.dart';
import '../shared/reviews_screen.dart';

class KitchenOrderDetailsScreen extends StatefulWidget {
  final Order order;
  const KitchenOrderDetailsScreen({super.key, required this.order});

  @override
  State<KitchenOrderDetailsScreen> createState() => _KitchenOrderDetailsScreenState();
}

class _KitchenOrderDetailsScreenState extends State<KitchenOrderDetailsScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  LatLng? _riderLatLng;
  LatLng? _deliveryLatLng;
  LatLng? _kitchenLatLng;
  LatLng? _customerLatLng;
  bool _isLoadingMap = true;
  StreamSubscription<List<Map<String, dynamic>>>? _orderSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _riderLocationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _customerLocationSubscription;
  Order? _currentOrder;

  final TextEditingController _riderPayoutTxnController = TextEditingController();
  bool _isConfirmingPayment = false;
  bool _isPayingRider = false;
  bool _isIssuingReceipt = false;
  bool _isDownloadingReceipt = false;

  @override
  void initState() {
    super.initState();
    _currentOrder = widget.order;
    _deliveryLatLng = LatLng(widget.order.deliveryLatitude, widget.order.deliveryLongitude);
    _loadCoordinatesAndSubscribe();
  }

  @override
  void dispose() {
    _orderSubscription?.cancel();
    _riderLocationSubscription?.cancel();
    _customerLocationSubscription?.cancel();
    _riderPayoutTxnController.dispose();
    super.dispose();
  }

  Future<void> _loadCoordinatesAndSubscribe() async {
    try {
      final kitchenData = await _client
          .from('kitchens')
          .select('latitude, longitude')
          .eq('id', _currentOrder!.kitchenId)
          .single();

      _kitchenLatLng = LatLng(
        (kitchenData['latitude'] as num).toDouble(),
        (kitchenData['longitude'] as num).toDouble(),
      );

      _subscribeToCustomerLocation(_currentOrder!.customerId);

      setState(() {
        _isLoadingMap = false;
      });

      // Stream updates to current order
      _orderSubscription = _client
          .from('orders')
          .stream(primaryKey: ['id'])
          .eq('id', _currentOrder!.id)
          .listen((List<Map<String, dynamic>> data) async {
            if (data.isNotEmpty) {
              final item = data.first;

              final customerDetails = await _client
                  .from('profiles')
                  .select('full_name, phone')
                  .eq('id', item['customer_id'])
                  .single();

              final orderItemsData = await _client
                  .from('order_items')
                  .select('*, menu_items(name)')
                  .eq('order_id', item['id']);

              final combined = Map<String, dynamic>.from(item);
              combined['profiles_customer'] = {'full_name': customerDetails['full_name'], 'phone': customerDetails['phone']};
              combined['order_items'] = orderItemsData;

              if (item['rider_id'] != null) {
                final riderDetails = await _client
                    .from('profiles')
                    .select('full_name, bkash_number')
                    .eq('id', item['rider_id'])
                    .single();
                combined['profiles_rider'] = {'full_name': riderDetails['full_name']};
                combined['rider_bkash'] = riderDetails['bkash_number'];

                _subscribeToRiderLocation(item['rider_id'] as String);
              }

              final String previousStatus = _currentOrder?.status ?? '';
              final Order updated = Order.fromJson(combined);
              if (updated.status != previousStatus) {
                final msg = NotificationService.messageForStatus(updated.status, role: 'kitchen');
                if (msg != null) NotificationService.show('Order Update', msg);
              }

              setState(() {
                _currentOrder = updated;
              });
            }
          });
    } catch (e) {
      setState(() {
        _isLoadingMap = false;
      });
    }
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

  /// Tracks the customer's live position while they broadcast it (i.e. while
  /// this order is active). Shown as a distinct pin from the static delivery
  /// address, and only appears once the customer has actually broadcast.
  void _subscribeToCustomerLocation(String customerId) {
    _customerLocationSubscription?.cancel();
    _customerLocationSubscription = _client
        .from('profiles')
        .stream(primaryKey: ['id'])
        .eq('id', customerId)
        .listen((List<Map<String, dynamic>> data) {
          if (data.isNotEmpty) {
            final profile = data.first;
            if (profile['latitude'] != null && profile['longitude'] != null) {
              setState(() {
                _customerLatLng = LatLng(
                  (profile['latitude'] as num).toDouble(),
                  (profile['longitude'] as num).toDouble(),
                );
              });
            } else {
              setState(() {
                _customerLatLng = null;
              });
            }
          }
        });
  }

  void _updateStatus(String newStatus) async {
    final success = await Provider.of<KitchenProvider>(context, listen: false)
        .updateOrderStatus(_currentOrder!.id, newStatus);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Order updated to: ${newStatus.toUpperCase()}'), backgroundColor: context.appColors.success),
      );
    }
  }

  Future<void> _confirmPayment() async {
    setState(() => _isConfirmingPayment = true);
    final kitchenProvider = Provider.of<KitchenProvider>(context, listen: false);
    final success = await kitchenProvider.confirmPaymentReceived(_currentOrder!.id);
    if (!mounted) return;
    setState(() => _isConfirmingPayment = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Payment confirmed — you can now accept this order.' : friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Could not confirm payment. Please try again.')),
        backgroundColor: success ? context.appColors.success : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _confirmRiderPaid() async {
    setState(() => _isPayingRider = true);
    final kitchenProvider = Provider.of<KitchenProvider>(context, listen: false);
    final success = await kitchenProvider.confirmRiderPaid(_currentOrder!.id, txnId: _riderPayoutTxnController.text.trim());
    if (!mounted) return;
    setState(() => _isPayingRider = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Rider marked as paid.' : friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Could not mark the rider as paid. Please try again.')),
        backgroundColor: success ? context.appColors.success : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _issueReceipt() async {
    setState(() => _isIssuingReceipt = true);
    final kitchenProvider = Provider.of<KitchenProvider>(context, listen: false);
    final success = await kitchenProvider.issueReceipt(_currentOrder!.id);
    if (!mounted) return;
    setState(() => _isIssuingReceipt = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? 'Receipt sent to the customer.' : friendlyErrorMessage(kitchenProvider.errorMessage, fallback: 'Could not send the receipt. Please try again.')),
        backgroundColor: success ? context.appColors.success : Theme.of(context).colorScheme.error,
      ),
    );
  }

  Future<void> _downloadReceiptPdf() async {
    setState(() => _isDownloadingReceipt = true);
    try {
      await ReceiptPdfService.downloadReceipt(order: _currentOrder!, forKitchenOwner: true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Could not generate the statement. Please try again.'), backgroundColor: Theme.of(context).colorScheme.error),
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

  @override
  Widget build(BuildContext context) {
    if (_currentOrder == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final String status = _currentOrder!.status;
    final double netPayout = _currentOrder!.totalAmount - _currentOrder!.commissionAmount - _currentOrder!.riderFee;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Order Details'),
        flexibleSpace: Container(
          decoration: const BoxDecoration(gradient: LinearGradient(colors: kBrandGradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
        ),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
              child: _StatusHero(status: status),
            ),
            const SizedBox(height: AppSpacing.lg),

            // Map
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: _MapCard(
                height: 210,
                isLoading: _isLoadingMap,
                // Center on the delivery destination (or the rider's live position,
                // once assigned) rather than the kitchen's own fixed location —
                // the kitchen owner already knows where their kitchen is; what
                // they need to see is where the order is actually going.
                initialCenter: _riderLatLng ?? _deliveryLatLng ?? _kitchenLatLng ?? const LatLng(23.8103, 90.4125),
                kitchenLatLng: _kitchenLatLng,
                deliveryLatLng: _deliveryLatLng,
                riderLatLng: _riderLatLng,
                customerLatLng: _customerLatLng,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
              child: Row(
                children: [
                  Text('Delivering to: ', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                  Expanded(
                    child: LiveLocationText(
                      latitude: _deliveryLatLng?.latitude,
                      longitude: _deliveryLatLng?.longitude,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Payment: manual bKash confirmation gate before Accept.
                  if (status == 'pending') ...[
                    _buildPaymentCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Status & Action Panel
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: _buildStatusTransitionButtons(status),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Receipt: available once payment is confirmed.
                  if (_currentOrder!.isPaymentConfirmed) ...[
                    _buildReceiptCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Rider payout: visible once picked up, actionable once completed.
                  if (isRiderContactUnlocked(status) && _currentOrder!.riderId != null) ...[
                    _buildRiderPayoutCard(),
                    const SizedBox(height: AppSpacing.lg),
                  ],

                  // Fee Summary Card — net payout reads as the headline number.
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Earnings & fee summary', style: textTheme.titleMedium),
                              Icon(Icons.receipt_long_rounded, size: 18, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.4)),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text('Net kitchen payout', style: textTheme.labelMedium),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            formatCurrency(netPayout),
                            style: textTheme.displaySmall?.copyWith(color: context.appColors.success),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          const Divider(height: 1),
                          const SizedBox(height: AppSpacing.md),
                          _buildFeeRow('Gross order amount', formatCurrency(_currentOrder!.totalAmount)),
                          _buildFeeRow('Platform commission', '-${formatCurrency(_currentOrder!.commissionAmount)}'),
                          _buildFeeRow('Rider delivery fee', '-${formatCurrency(_currentOrder!.riderFee)}'),
                        ],
                      ),
                    ),
                  ),
                  if (status == 'completed') ...[
                    const SizedBox(height: AppSpacing.md),
                    OutlinedButton.icon(
                      onPressed: _isDownloadingReceipt ? null : _downloadReceiptPdf,
                      icon: _isDownloadingReceipt
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.download_rounded),
                      label: const Text('Download Payout Statement'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),

                  // Order items list
                  Text('Items ordered', style: textTheme.titleMedium),
                  const SizedBox(height: AppSpacing.sm),
                  if (_currentOrder!.items != null)
                    ..._currentOrder!.items!.map((item) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${item.menuItemName} x${item.quantity}'),
                          trailing: Text(formatCurrency(item.price * item.quantity), style: textTheme.titleSmall),
                        )),

                  const Divider(),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text('Customer', style: textTheme.titleMedium),
                    subtitle: Text(_currentOrder!.customerName ?? "Anonymous Customer"),
                    trailing: IconButton(
                      icon: const Icon(Icons.chat_bubble_outline),
                      onPressed: () {
                        Navigator.of(context).push(
                          appPageRoute(
                            ChatScreen(
                              orderId: _currentOrder!.id,
                              senderId: Provider.of<AuthProvider>(context, listen: false).profile!.id,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The manual bKash confirmation gate shown while an order is still
  /// 'pending' — mirrors what the customer sees on their side.
  Widget _buildPaymentCard() {
    final order = _currentOrder!;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payments_outlined, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Text('bKash Payment', style: textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            if (order.paymentStatus == 'awaiting_payment')
              Text(
                "Waiting for the customer to send ${formatCurrency(order.totalAmount)} via bKash.",
                style: textTheme.bodyMedium,
              )
            else if (order.paymentStatus == 'payment_reported') ...[
              Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: appColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Customer reported sending ${formatCurrency(order.totalAmount)}.',
                      style: textTheme.bodyMedium?.copyWith(color: appColors.warning),
                    ),
                  ),
                ],
              ),
              if (order.customerBkashTxnId != null) ...[
                const SizedBox(height: AppSpacing.sm),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: AppRadius.mdBr),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text('TrxID: ${order.customerBkashTxnId}', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.sm),
              Text(
                'Check your own bKash app for this transaction before confirming.',
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(height: AppSpacing.md),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isConfirmingPayment ? null : _confirmPayment,
                  style: ElevatedButton.styleFrom(backgroundColor: appColors.success, foregroundColor: appColors.onSuccess),
                  icon: _isConfirmingPayment
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.verified_rounded, size: 18),
                  label: const Text('Confirm Payment Received'),
                ),
              ),
            ] else
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: appColors.success),
                  const SizedBox(width: 6),
                  Expanded(child: Text('Payment confirmed', style: textTheme.bodyMedium?.copyWith(color: appColors.success))),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// One-shot action to issue the customer's in-app receipt, once payment is confirmed.
  Widget _buildReceiptCard() {
    final order = _currentOrder!;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Icon(Icons.receipt_long_outlined, size: 18, color: scheme.onSurfaceVariant),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                order.receiptIssuedAt != null ? 'Receipt sent to customer' : 'Send the customer a payment receipt',
                style: textTheme.bodyMedium,
              ),
            ),
            if (order.receiptIssuedAt != null)
              Icon(Icons.check_circle_rounded, size: 18, color: appColors.success)
            else
              ElevatedButton(
                onPressed: _isIssuingReceipt ? null : _issueReceipt,
                child: _isIssuingReceipt
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Send Receipt'),
              ),
          ],
        ),
      ),
    );
  }

  /// Rider's bKash number (visible from pickup onward) and the "mark paid"
  /// action, which only actually does anything once the order is completed.
  Widget _buildRiderPayoutCard() {
    final order = _currentOrder!;
    final textTheme = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.two_wheeler_rounded, size: 18, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    order.riderName != null ? 'Rider Payout — ${order.riderName}' : 'Rider Payout',
                    style: textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (order.riderId != null)
                  InkWell(
                    borderRadius: AppRadius.mdBr,
                    onTap: () => _showRiderReviews(order.riderId!, order.riderName ?? 'Rider'),
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
            const SizedBox(height: AppSpacing.md),
            if (order.riderBkashNumber == null || order.riderBkashNumber!.isEmpty)
              Text("The rider hasn't set up their bKash number yet.", style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))
            else
              Row(
                children: [
                  Text('bKash: ', style: textTheme.bodyMedium),
                  Text(order.riderBkashNumber!, style: textTheme.titleMedium?.copyWith(letterSpacing: 0.5)),
                  IconButton(
                    tooltip: 'Copy number',
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: order.riderBkashNumber!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Rider bKash number copied')));
                      }
                    },
                  ),
                ],
              ),
            const SizedBox(height: 4),
            Text('Fee to send: ${formatCurrency(order.riderFee)}', style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
            if (order.payoutOverdueFlaggedAt != null && !order.riderPayoutConfirmed) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: 0.5), borderRadius: AppRadius.mdBr),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber_rounded, size: 18, color: scheme.error),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        "Overdue: the customer's order was auto-completed after 24h because this rider hadn't been paid yet. Please send the fee now — this account is flagged for payout follow-up.",
                        style: textTheme.bodySmall?.copyWith(color: scheme.error),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            if (order.riderPayoutConfirmed && order.riderPaymentConfirmed)
              Row(
                children: [
                  Icon(Icons.check_circle_rounded, size: 16, color: appColors.success),
                  const SizedBox(width: 6),
                  Text('Rider paid — confirmed received', style: textTheme.bodyMedium?.copyWith(color: appColors.success)),
                ],
              )
            else if (order.riderPayoutConfirmed)
              Row(
                children: [
                  Icon(Icons.hourglass_top_rounded, size: 16, color: appColors.warning),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('Marked as paid — waiting for the rider to confirm receipt', style: textTheme.bodyMedium?.copyWith(color: appColors.warning)),
                  ),
                ],
              )
            else if (order.status == 'delivered' || order.status == 'completed') ...[
              TextField(
                controller: _riderPayoutTxnController,
                decoration: const InputDecoration(
                  labelText: 'bKash Transaction ID (optional, for your records)',
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isPayingRider ? null : _confirmRiderPaid,
                  style: ElevatedButton.styleFrom(backgroundColor: appColors.success, foregroundColor: appColors.onSuccess),
                  icon: _isPayingRider
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.send_rounded, size: 18),
                  label: const Text('Mark Rider Paid'),
                ),
              ),
            ] else
              Text(
                "You'll be able to mark the rider paid once they've delivered the order.",
                style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeeRow(String label, String val) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: textTheme.bodyMedium),
          Text(val, style: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _buildStatusTransitionButtons(String status) {
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;

    if (status == 'pending') {
      final paymentConfirmed = _currentOrder!.isPaymentConfirmed;
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _updateStatus('rejected'),
              style: OutlinedButton.styleFrom(foregroundColor: scheme.error, side: BorderSide(color: scheme.error.withValues(alpha: 0.4))),
              child: const Text('Reject'),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: ElevatedButton(
              onPressed: paymentConfirmed ? () => _updateStatus('accepted') : null,
              style: ElevatedButton.styleFrom(backgroundColor: appColors.success),
              child: Text(paymentConfirmed ? 'Accept' : 'Confirm payment first'),
            ),
          ),
        ],
      );
    }

    if (status == 'accepted') {
      return ElevatedButton(
        onPressed: () => _updateStatus('preparing'),
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        child: const Text('Start Preparing'),
      );
    }

    if (status == 'preparing') {
      return ElevatedButton(
        onPressed: () => _updateStatus('ready'),
        style: ElevatedButton.styleFrom(backgroundColor: appColors.success, minimumSize: const Size.fromHeight(44)),
        child: const Text('Food is Ready'),
      );
    }

    if (status == 'ready') {
      return ElevatedButton(
        onPressed: () => _updateStatus('awaiting_rider'),
        style: ElevatedButton.styleFrom(minimumSize: const Size.fromHeight(44)),
        child: const Text('Request Rider Delivery'),
      );
    }

    if (status == 'awaiting_rider') {
      return _buildAwaitingText('Awaiting rider assignment…');
    }
    if (status == 'rider_assigned') {
      return _buildAwaitingText('Rider is on the way to pick up food.');
    }
    if (status == 'picked_up') {
      return _buildAwaitingText('Rider has picked up the order.');
    }
    if (status == 'on_the_way') {
      return _buildAwaitingText('Rider is on the way to the customer.');
    }
    if (status == 'arrived') {
      return _buildAwaitingText("Rider has arrived at the customer's location.");
    }
    if (status == 'delivered') {
      return _buildAwaitingText('Delivered by rider — awaiting customer confirmation.');
    }
    if (status == 'completed') {
      return _buildAwaitingText('Customer confirmed delivery. Order completed!', emphasize: true);
    }

    return const SizedBox.shrink();
  }

  Widget _buildAwaitingText(String text, {bool emphasize = false}) {
    final meta = OrderStatusMeta.of(context, _currentOrder!.status);
    final textTheme = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(meta.icon, size: 16, color: meta.fg),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            text,
            style: (emphasize ? textTheme.titleSmall : textTheme.bodyMedium)?.copyWith(color: meta.fg),
          ),
        ),
      ],
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
  final LatLng? customerLatLng;

  const _MapCard({
    required this.height,
    required this.isLoading,
    required this.initialCenter,
    this.kitchenLatLng,
    this.deliveryLatLng,
    this.riderLatLng,
    this.customerLatLng,
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
                      if (customerLatLng != null)
                        Marker(
                          point: customerLatLng!,
                          width: 40,
                          height: 40,
                          child: _MapPin(icon: Icons.person_pin_circle_rounded, color: appColors.mapCustomer),
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
