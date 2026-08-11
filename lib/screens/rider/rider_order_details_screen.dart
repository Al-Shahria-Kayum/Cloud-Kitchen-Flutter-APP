import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rider_provider.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/delivery_stage.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/status_pill.dart';
import '../shared/chat_screen.dart';

class RiderOrderDetailsScreen extends StatefulWidget {
  final Order order;
  const RiderOrderDetailsScreen({super.key, required this.order});

  @override
  State<RiderOrderDetailsScreen> createState() => _RiderOrderDetailsScreenState();
}

class _RiderOrderDetailsScreenState extends State<RiderOrderDetailsScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  LatLng? _kitchenLatLng;
  LatLng? _kitchenStaticLatLng;
  LatLng? _deliveryLatLng;
  LatLng? _riderLatLng;
  LatLng? _customerLatLng;
  bool _isLoadingMap = true;
  StreamSubscription<List<Map<String, dynamic>>>? _orderSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _riderLocationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _kitchenLocationSubscription;
  StreamSubscription<List<Map<String, dynamic>>>? _customerLocationSubscription;
  Order? _currentOrder;

  bool get _isCustomerLocationUnlocked => isCustomerContactUnlocked(_currentOrder?.status);

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
    _kitchenLocationSubscription?.cancel();
    _customerLocationSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadCoordinatesAndSubscribe() async {
    try {
      // Load kitchen coordinates (+ owner_id so we can track the kitchen live)
      final kitchenData = await _client
          .from('kitchens')
          .select('latitude, longitude, name, owner_id')
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
      // Customer's live location stays locked until the rider has picked up
      // the food — see _isCustomerLocationUnlocked and the order stream below.
      if (_isCustomerLocationUnlocked) {
        _subscribeToCustomerLocation(_currentOrder!.customerId);
      }

      // Load current rider coordinates
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final riderProfile = await _client
          .from('profiles')
          .select('latitude, longitude')
          .eq('id', authProvider.user!.id)
          .single();

      if (riderProfile['latitude'] != null && riderProfile['longitude'] != null) {
        _riderLatLng = LatLng(
          (riderProfile['latitude'] as num).toDouble(),
          (riderProfile['longitude'] as num).toDouble(),
        );
      }

      setState(() {
        _isLoadingMap = false;
      });

      // Stream current order updates
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

              final combined = Map<String, dynamic>.from(item);
              combined['kitchens'] = {'name': kitchenData['name']};
              combined['profiles_customer'] = {'full_name': customerDetails['full_name'], 'phone': customerDetails['phone']};

              final String previousStatus = _currentOrder?.status ?? '';
              final Order updated = Order.fromJson(combined);
              if (updated.status != previousStatus) {
                final msg = NotificationService.messageForStatus(updated.status, role: 'rider');
                if (msg != null) NotificationService.show('Delivery Update', msg);

                if (updated.status == 'completed') {
                  final riderProvider = Provider.of<RiderProvider>(context, listen: false);
                  await riderProvider.loadEarnings(authProvider.user!.id);
                  if (mounted) Navigator.pop(context);
                  return;
                }
              }

              setState(() {
                _currentOrder = updated;
              });

              // The pickup just happened — unlock the customer's live location now.
              if (isCustomerContactUnlocked(updated.status) &&
                  _customerLocationSubscription == null) {
                _subscribeToCustomerLocation(updated.customerId);
              }
            }
          });

      // Stream rider coordinates updates in real-time
      _riderLocationSubscription = _client
          .from('profiles')
          .stream(primaryKey: ['id'])
          .eq('id', authProvider.user!.id)
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
            if (profile['latitude'] != null && profile['longitude'] != null) {
              setState(() {
                _kitchenLatLng = LatLng(
                  (profile['latitude'] as num).toDouble(),
                  (profile['longitude'] as num).toDouble(),
                );
              });
            } else {
              setState(() {
                _kitchenLatLng = _kitchenStaticLatLng;
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

  void _confirmPaymentReceived() async {
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    final success = await riderProvider.confirmPaymentReceived(_currentOrder!.id);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Thanks — the customer can now confirm delivery.'), backgroundColor: context.appColors.success),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(riderProvider.errorMessage, fallback: 'Failed to confirm payment. Please try again.')), backgroundColor: Theme.of(context).colorScheme.error),
      );
    }
  }

  void _runTransition(Future<bool> Function(String orderId) action, String status) async {
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    final success = await action(_currentOrder!.id);

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delivery status updated to: ${status.toUpperCase()}'), backgroundColor: context.appColors.success),
      );
      if (status == 'delivered') {
        // Rider's part is done; wait here for the customer to confirm receipt.
        // Earnings only reload once the order reaches 'completed' (see order stream above).
      }
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(friendlyErrorMessage(riderProvider.errorMessage, fallback: 'Failed to update status. Please try again.')), backgroundColor: Theme.of(context).colorScheme.error),
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
    final appColors = context.appColors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Delivery Route'),
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
                height: 230,
                isLoading: _isLoadingMap,
                initialCenter: _riderLatLng ?? _kitchenLatLng ?? _deliveryLatLng ?? const LatLng(23.8103, 90.4125),
                kitchenLatLng: _kitchenLatLng,
                deliveryLatLng: _deliveryLatLng,
                riderLatLng: _riderLatLng,
                customerLatLng: _customerLatLng,
              ),
            ),
            if (!_isCustomerLocationUnlocked)
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Theme.of(context).colorScheme.outline),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        "Customer's live location unlocks once you pick up the food.",
                        style: textTheme.labelSmall?.copyWith(color: Theme.of(context).colorScheme.outline),
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
                  // One considered action button that changes state per stage,
                  // rather than several different flat buttons appearing in turn.
                  _RiderActionButton(
                    status: status,
                    riderPayoutConfirmed: _currentOrder!.riderPayoutConfirmed,
                    riderPaymentConfirmed: _currentOrder!.riderPaymentConfirmed,
                    onTransition: _runTransition,
                    onConfirmPaymentReceived: _confirmPaymentReceived,
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Route information details
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Route directions', style: textTheme.titleMedium),
                          const Divider(height: AppSpacing.xxl),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MapPin(icon: Icons.store, color: appColors.mapKitchen),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(_currentOrder!.kitchenName ?? 'Kitchen', style: textTheme.labelMedium),
                                    const SizedBox(height: 2),
                                    LiveLocationText(
                                      latitude: _kitchenLatLng?.latitude,
                                      longitude: _kitchenLatLng?.longitude,
                                      style: textTheme.bodyLarge,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _MapPin(icon: Icons.location_on, color: appColors.mapCustomer),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Delivery customer address', style: textTheme.labelMedium),
                                    const SizedBox(height: 2),
                                    Text(_currentOrder!.deliveryAddress, style: textTheme.bodyLarge),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Customer contact — unlocked at the same moment as their
                  // live location, once the rider has picked up the food.
                  if (_isCustomerLocationUnlocked) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _CustomerContactCard(
                      name: _currentOrder!.customerName ?? 'Customer',
                      phone: _currentOrder!.customerPhone,
                      address: _currentOrder!.deliveryAddress,
                    ),
                  ],
                  const SizedBox(height: AppSpacing.xl),

                  // Order chat link
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
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
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text('Order Chat'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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

/// The rider's one escalating action button. Same trigger logic as before
/// (`_runTransition` -> `riderProvider.markPickedUp/markOnTheWay/markArrived/
/// markDelivered`) but presented as a single button whose look/label evolves
/// with the order stage, with a soft cross-fade between stages, instead of
/// four differently-colored buttons swapping in and out.
class _RiderActionButton extends StatelessWidget {
  final String status;
  final bool riderPayoutConfirmed;
  final bool riderPaymentConfirmed;
  final void Function(Future<bool> Function(String orderId) action, String status) onTransition;
  final VoidCallback onConfirmPaymentReceived;

  const _RiderActionButton({
    required this.status,
    required this.riderPayoutConfirmed,
    required this.riderPaymentConfirmed,
    required this.onTransition,
    required this.onConfirmPaymentReceived,
  });

  @override
  Widget build(BuildContext context) {
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final textTheme = Theme.of(context).textTheme;

    VoidCallback? onPressed;
    IconData icon = Icons.hourglass_empty_rounded;
    String label = 'Delivery completed.';
    Color color = scheme.outline;
    bool isFinalWaitState = false;

    switch (status) {
      case 'rider_assigned':
        icon = Icons.inventory_2_rounded;
        label = 'Confirm Food Picked Up';
        color = scheme.primary;
        onPressed = () => onTransition(riderProvider.markPickedUp, 'picked_up');
        break;
      case 'picked_up':
        icon = Icons.moped_rounded;
        label = 'Start Delivery';
        color = scheme.primary;
        onPressed = () => onTransition(riderProvider.markOnTheWay, 'on_the_way');
        break;
      case 'on_the_way':
        icon = Icons.pin_drop_rounded;
        label = "I've Arrived";
        color = scheme.primary;
        onPressed = () => onTransition(riderProvider.markArrived, 'arrived');
        break;
      case 'arrived':
        icon = Icons.task_alt_rounded;
        label = 'Mark as Delivered';
        color = appColors.success;
        onPressed = () => onTransition(riderProvider.markDelivered, 'delivered');
        break;
      case 'delivered':
        if (riderPayoutConfirmed && !riderPaymentConfirmed) {
          icon = Icons.price_check_rounded;
          label = 'Confirm You Received the Payment';
          color = appColors.success;
          onPressed = onConfirmPaymentReceived;
        } else {
          icon = riderPaymentConfirmed ? Icons.mark_email_unread_rounded : Icons.hourglass_top_rounded;
          label = riderPaymentConfirmed
              ? 'Waiting for customer to confirm delivery…'
              : 'Waiting on the kitchen to pay you before the customer can confirm…';
          color = appColors.warning;
          isFinalWaitState = true;
        }
        break;
      default:
        icon = Icons.task_alt_rounded;
        label = 'Delivery completed.';
        color = scheme.outline;
        isFinalWaitState = true;
    }

    return AnimatedSwitcher(
      duration: AppMotion.base,
      switchInCurve: AppMotion.curve,
      switchOutCurve: AppMotion.curve,
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: isFinalWaitState
          ? Container(
              key: ValueKey(status),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: AppRadius.lgBr),
              child: Row(
                children: [
                  Icon(icon, color: color),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(label, style: textTheme.titleSmall?.copyWith(color: color))),
                ],
              ),
            )
          : SizedBox(
              key: ValueKey(status),
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: onPressed,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  minimumSize: const Size.fromHeight(52),
                ),
                icon: Icon(icon),
                label: Text(label),
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
                options: MapOptions(initialCenter: initialCenter, initialZoom: 13.0),
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

/// Customer name, phone and delivery address — revealed to the rider only
/// once they've picked up the food (see _isCustomerLocationUnlocked).
class _CustomerContactCard extends StatelessWidget {
  final String name;
  final String? phone;
  final String address;

  const _CustomerContactCard({required this.name, required this.phone, required this.address});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final appColors = context.appColors;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.contact_phone_outlined, size: 18, color: appColors.mapCustomer),
                const SizedBox(width: AppSpacing.sm),
                Text('Customer details', style: textTheme.titleMedium),
              ],
            ),
            const Divider(height: AppSpacing.xxl),
            Row(
              children: [
                _MapPin(icon: Icons.person, color: appColors.mapCustomer),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Name', style: textTheme.labelMedium),
                      const SizedBox(height: 2),
                      Text(name, style: textTheme.bodyLarge),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            Row(
              children: [
                _MapPin(icon: Icons.phone, color: appColors.mapCustomer),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Phone', style: textTheme.labelMedium),
                      const SizedBox(height: 2),
                      Text(phone?.isNotEmpty == true ? phone! : 'Not provided', style: textTheme.bodyLarge),
                    ],
                  ),
                ),
                if (phone?.isNotEmpty == true)
                  IconButton(
                    tooltip: 'Copy phone number',
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: phone!));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Phone number copied')),
                        );
                      }
                    },
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
