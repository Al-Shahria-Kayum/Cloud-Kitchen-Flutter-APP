import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/rider_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/section_header.dart';
import '../../utils/async_guard.dart';
import '../shared/bkash_settings_sheet.dart';
import '../shared/reviews_screen.dart';
import 'rider_order_details_screen.dart';
import 'rider_order_history_screen.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> with WidgetsBindingObserver {
  double _riderLat = 23.8103; // Default Dhaka Center
  double _riderLng = 90.4125;
  bool _showLocationPanel = false;

  final TextEditingController _latController = TextEditingController(text: "23.8103");
  final TextEditingController _lngController = TextEditingController(text: "90.4125");

  double _avgRating = 0.0;
  int _ratingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRiderData();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime channels can silently drop on mobile network handoff (app
    // backgrounded, Wi-Fi<->cellular switch); re-subscribing on resume is
    // cheap since .stream() re-runs the initial SELECT too, so this restores
    // state even if the underlying socket died while backgrounded.
    if (state == AppLifecycleState.resumed) {
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final riderProvider = Provider.of<RiderProvider>(context, listen: false);
      riderProvider.subscribeToAvailableDeliveries();
      if (authProvider.user != null) {
        riderProvider.subscribeToActiveDelivery(authProvider.user!.id);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _loadRiderData() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);

    // Initial GPS Location (single fix, just so the rider has a starting point on the map).
    // Guarded with a timeout so a stalled location/network request can't leave
    // the screen looking stuck — it just falls back to the default coordinates.
    final location = await runGuarded(
      () => LocationService.getCurrentLocation(),
      onError: (e) => debugPrint('getCurrentLocation failed: $e'),
    );
    if (location != null && mounted) {
      setState(() {
        _riderLat = location['latitude']!;
        _riderLng = location['longitude']!;
        _latController.text = _riderLat.toString();
        _lngController.text = _riderLng.toString();
      });
    }

    await runGuarded(
      () => riderProvider.updateRiderLocation(authProvider.user!.id, _riderLat, _riderLng),
      onError: (e) => debugPrint('updateRiderLocation failed: $e'),
    );
    await runGuarded(
      () => riderProvider.loadEarnings(authProvider.user!.id),
      onError: (e) => debugPrint('loadEarnings failed: $e'),
    );
    final stats = await runGuarded(
      () => riderProvider.getRiderRatingStats(authProvider.user!.id),
      onError: (e) => debugPrint('getRiderRatingStats failed: $e'),
    );
    if (stats != null && mounted) {
      setState(() {
        _avgRating = stats['rating'] as double;
        _ratingCount = stats['count'] as int;
      });
    }
    riderProvider.subscribeToAvailableDeliveries();
    riderProvider.subscribeToActiveDelivery(authProvider.user!.id);

    // If the rider already has an active (in-progress) delivery — e.g. app was
    // restarted mid-delivery — resume continuous GPS broadcasting immediately.
    if (riderProvider.activeDelivery != null) {
      riderProvider.startLocationTracking(authProvider.user!.id);
    }
  }

  /// Keeps continuous GPS tracking in sync with whether a delivery is active,
  /// so location broadcasting starts the moment a delivery is accepted and
  /// stops once it's out of the rider's hands.
  void _syncLocationTracking(RiderProvider riderProvider, String riderId) {
    final hasActive = riderProvider.activeDelivery != null;
    if (hasActive && !riderProvider.isTrackingLocation) {
      riderProvider.startLocationTracking(riderId);
    } else if (!hasActive && riderProvider.isTrackingLocation) {
      riderProvider.stopLocationTracking();
    }
  }

  void _applyRiderMockLocation() async {
    final lat = double.tryParse(_latController.text);
    final lng = double.tryParse(_lngController.text);
    if (lat != null && lng != null) {
      LocationService.setMockLocation(lat, lng);
      setState(() {
        _riderLat = lat;
        _riderLng = lng;
      });

      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      final riderProvider = Provider.of<RiderProvider>(context, listen: false);

      await riderProvider.updateRiderLocation(authProvider.user!.id, lat, lng);
      if (!mounted) return;
      final scheme = Theme.of(context).colorScheme;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Rider location updated to: ($lat, $lng)'), backgroundColor: scheme.secondary),
      );
    }
  }

  Future<void> _refresh() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final riderProvider = Provider.of<RiderProvider>(context, listen: false);
    if (authProvider.user == null) return;
    await riderProvider.loadEarnings(authProvider.user!.id);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final riderProvider = context.watch<RiderProvider>();
    final scheme = Theme.of(context).colorScheme;

    if (authProvider.user != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncLocationTracking(riderProvider, authProvider.user!.id);
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rider Dashboard'),
        actions: [
          IconButton(
            tooltip: 'Your bKash number',
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => showBkashNumberSheet(context),
          ),
          IconButton(
            tooltip: 'Delivery History',
            icon: const Icon(Icons.receipt_long_outlined),
            onPressed: authProvider.user == null
                ? null
                : () => Navigator.of(context).push(
                      appPageRoute(RiderOrderHistoryScreen(riderId: authProvider.user!.id)),
                    ),
          ),
          IconButton(
            tooltip: 'My Reviews',
            icon: const Icon(Icons.star_outline_rounded),
            onPressed: authProvider.user == null
                ? null
                : () => Navigator.of(context).push(
                      appPageRoute(
                        ReviewsScreen(
                          title: 'My Reviews',
                          avgRating: _avgRating,
                          reviewCount: _ratingCount,
                          loadReviews: () => riderProvider.getRiderReviews(authProvider.user!.id),
                        ),
                      ),
                    ),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await authProvider.logout();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Earnings hero card — the rider's most-checked number.
              _EarningsCard(earnings: riderProvider.earnings),
              const SizedBox(height: AppSpacing.lg),

              // Live location status + manual override (for testing without real GPS movement)
              _GpsStatusCard(
                isTracking: riderProvider.isTrackingLocation,
                showPanel: _showLocationPanel,
                onTogglePanel: () => setState(() => _showLocationPanel = !_showLocationPanel),
                latController: _latController,
                lngController: _lngController,
                onApply: _applyRiderMockLocation,
              ),
              const SizedBox(height: AppSpacing.xl),

              // Active delivery tracker
              if (riderProvider.activeDelivery != null) ...[
                const SectionHeader(title: 'Current Active Delivery'),
                _ActiveDeliveryCard(
                  order: riderProvider.activeDelivery!,
                  onTap: () {
                    Navigator.of(context).push(
                      appPageRoute(RiderOrderDetailsScreen(order: riderProvider.activeDelivery!)),
                    );
                  },
                ),
                const SizedBox(height: AppSpacing.xl),
              ],

              // Available Deliveries List
              SectionHeader(
                title: 'Available Deliveries Nearby',
                trailing: '${riderProvider.availableDeliveries.length}',
              ),
              if (riderProvider.isLoading && riderProvider.availableDeliveries.isEmpty)
                Column(children: List.generate(3, (_) => const SkeletonCardRow()))
              else if (riderProvider.availableDeliveries.isEmpty)
                const EmptyState(
                  icon: Icons.moped_outlined,
                  title: 'No deliveries available right now',
                  message: 'New delivery requests nearby will show up here automatically.',
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: riderProvider.availableDeliveries.length,
                  itemBuilder: (context, index) {
                    final order = riderProvider.availableDeliveries[index];
                    return _AvailableDeliveryCard(
                      key: ValueKey(order.id),
                      index: index,
                      kitchenName: order.kitchenName ?? 'Kitchen',
                      kitchenLatitude: order.kitchenLatitude,
                      kitchenLongitude: order.kitchenLongitude,
                      deliveryAddress: order.deliveryAddress,
                      riderFee: order.riderFee,
                      hasActiveDelivery: riderProvider.activeDelivery != null,
                      onAccept: () async {
                        final success = await riderProvider.acceptDelivery(order.id, authProvider.user!.id);
                        if (!mounted) return;
                        if (success) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: const Text('Delivery accepted!'), backgroundColor: context.appColors.success),
                          );
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(friendlyErrorMessage(riderProvider.errorMessage, fallback: 'Failed to accept delivery. Please try again.')), backgroundColor: scheme.error),
                          );
                        }
                      },
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Earnings hero card — a considered gradient + type treatment for the
/// rider's most-checked number, rather than a flat bright-green box.
class _EarningsCard extends StatelessWidget {
  final double earnings;
  const _EarningsCard({required this.earnings});

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.lg),
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgBr,
        gradient: LinearGradient(
          colors: [colors.success, Color.lerp(colors.success, Colors.black, 0.35)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.success.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'MY EARNINGS',
                style: text.labelMedium?.copyWith(
                  color: colors.onSuccess.withValues(alpha: 0.75),
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.onSuccess.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.payments_rounded, color: colors.onSuccess, size: 20),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            formatCurrency(earnings),
            style: text.displayLarge?.copyWith(color: colors.onSuccess, letterSpacing: -0.6),
          ),
          const SizedBox(height: 2),
          Text(
            'Accumulated rider fees from completed deliveries',
            style: text.bodySmall?.copyWith(color: colors.onSuccess.withValues(alpha: 0.7)),
          ),
        ],
      ),
    );
  }
}

/// GPS status row with a meaningful pulse/glow while actively broadcasting,
/// plus the manual location override tucked away as a secondary/testing control.
class _GpsStatusCard extends StatefulWidget {
  final bool isTracking;
  final bool showPanel;
  final VoidCallback onTogglePanel;
  final TextEditingController latController;
  final TextEditingController lngController;
  final VoidCallback onApply;

  const _GpsStatusCard({
    required this.isTracking,
    required this.showPanel,
    required this.onTogglePanel,
    required this.latController,
    required this.lngController,
    required this.onApply,
  });

  @override
  State<_GpsStatusCard> createState() => _GpsStatusCardState();
}

class _GpsStatusCardState extends State<_GpsStatusCard> with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: widget.isTracking
                      ? AnimatedBuilder(
                          animation: _pulseController,
                          builder: (context, child) {
                            final t = _pulseController.value;
                            return Stack(
                              alignment: Alignment.center,
                              children: [
                                Container(
                                  width: 40 * (0.6 + t * 0.6),
                                  height: 40 * (0.6 + t * 0.6),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: colors.success.withValues(alpha: (1 - t) * 0.35),
                                  ),
                                ),
                                child!,
                              ],
                            );
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: colors.successContainer,
                            ),
                            child: Icon(Icons.gps_fixed_rounded, color: colors.success, size: 18),
                          ),
                        )
                      : Container(
                          width: 34,
                          height: 34,
                          margin: const EdgeInsets.all(3),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: scheme.outline.withValues(alpha: 0.2),
                          ),
                          child: Icon(Icons.gps_off_rounded, color: scheme.onSurface.withValues(alpha: 0.5), size: 18),
                        ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    widget.isTracking
                        ? 'Live GPS tracking active — broadcasting your location'
                        : 'GPS tracking starts automatically once you accept a delivery',
                    style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w700, color: Theme.of(context).colorScheme.onSurface),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Container(
              decoration: BoxDecoration(
                color: scheme.outline.withValues(alpha: 0.08),
                borderRadius: AppRadius.mdBr,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  InkWell(
                    borderRadius: AppRadius.mdBr,
                    onTap: widget.onTogglePanel,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm + 2),
                      child: Row(
                        children: [
                          Icon(Icons.science_outlined, size: 16, color: scheme.onSurface.withValues(alpha: 0.55)),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              'Manual location override (testing only)',
                              style: text.labelMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                            ),
                          ),
                          AnimatedRotation(
                            turns: widget.showPanel ? 0.5 : 0,
                            duration: AppMotion.fast,
                            child: Icon(Icons.expand_more_rounded, size: 18, color: scheme.onSurface.withValues(alpha: 0.55)),
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    duration: AppMotion.base,
                    sizeCurve: AppMotion.curve,
                    crossFadeState: widget.showPanel ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                    firstChild: Padding(
                      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Divider(height: AppSpacing.lg),
                          Row(
                            children: [
                              Expanded(
                                child: TextField(
                                  controller: widget.latController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                  decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: TextField(
                                  controller: widget.lngController,
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                                  decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.tonalIcon(
                              onPressed: widget.onApply,
                              icon: const Icon(Icons.my_location_rounded, size: 16),
                              label: const Text('Update & Broadcast Location'),
                            ),
                          ),
                        ],
                      ),
                    ),
                    secondChild: const SizedBox(width: double.infinity),
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

/// The rider's single most important piece of context while working —
/// a distinct, higher-presence treatment than the available-deliveries list.
class _ActiveDeliveryCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;
  const _ActiveDeliveryCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        borderRadius: AppRadius.lgBr,
        border: Border.all(color: colors.warning.withValues(alpha: 0.5), width: 1.5),
        color: colors.warningContainer.withValues(alpha: 0.35),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.lgBr,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(color: colors.warning.withValues(alpha: 0.18), shape: BoxShape.circle),
                  child: Icon(Icons.two_wheeler_rounded, color: colors.warning, size: 26),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deliver from ${order.kitchenName ?? "Kitchen"}',
                        style: text.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        order.deliveryAddress,
                        style: text.bodyMedium,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'In progress — tap for details',
                        style: text.labelMedium?.copyWith(color: colors.onWarningContainer),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, color: scheme.onSurface.withValues(alpha: 0.4), size: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A real delivery-request card: kitchen, address, and the fee front and
/// center (the number riders decide on), with a clear primary Accept action.
class _AvailableDeliveryCard extends StatefulWidget {
  final int index;
  final String kitchenName;
  final double? kitchenLatitude;
  final double? kitchenLongitude;
  final String deliveryAddress;
  final double riderFee;
  final bool hasActiveDelivery;
  final VoidCallback onAccept;

  const _AvailableDeliveryCard({
    super.key,
    required this.index,
    required this.kitchenName,
    this.kitchenLatitude,
    this.kitchenLongitude,
    required this.deliveryAddress,
    required this.riderFee,
    required this.hasActiveDelivery,
    required this.onAccept,
  });

  @override
  State<_AvailableDeliveryCard> createState() => _AvailableDeliveryCardState();
}

class _AvailableDeliveryCardState extends State<_AvailableDeliveryCard> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
    _fade = curved;
    _slide = Tween<Offset>(begin: const Offset(0, 0.08), end: Offset.zero).animate(curved);
    Future.delayed(Duration(milliseconds: 30 * widget.index.clamp(0, 6)), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = context.appColors;
    final text = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.storefront_rounded, size: 15, color: scheme.onSurface.withValues(alpha: 0.55)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.kitchenName,
                                  style: text.titleMedium,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (widget.kitchenLatitude != null && widget.kitchenLongitude != null) ...[
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.only(left: 19),
                              child: LiveLocationText(
                                latitude: widget.kitchenLatitude,
                                longitude: widget.kitchenLongitude,
                                style: text.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.55)),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(Icons.location_on_outlined, size: 15, color: scheme.onSurface.withValues(alpha: 0.55)),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  widget.deliveryAddress,
                                  style: text.bodyMedium,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: colors.successContainer,
                        borderRadius: AppRadius.mdBr,
                      ),
                      child: Column(
                        children: [
                          Text(
                            formatCurrency(widget.riderFee),
                            style: text.titleLarge?.copyWith(color: colors.onSuccessContainer),
                          ),
                          Text('fee', style: text.labelSmall?.copyWith(color: colors.onSuccessContainer.withValues(alpha: 0.8))),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                if (widget.hasActiveDelivery)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
                    decoration: BoxDecoration(
                      color: scheme.outline.withValues(alpha: 0.1),
                      borderRadius: AppRadius.mdBr,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.info_outline_rounded, size: 15, color: scheme.onSurface.withValues(alpha: 0.55)),
                        const SizedBox(width: 6),
                        Text(
                          'Finish your current delivery first',
                          style: text.labelMedium?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                        ),
                      ],
                    ),
                  )
                else
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: widget.onAccept,
                      icon: const Icon(Icons.check_rounded, size: 18),
                      label: const Text('Accept Delivery'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
