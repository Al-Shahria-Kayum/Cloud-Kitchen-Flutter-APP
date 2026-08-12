import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../widgets/responsive_app_bar.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/network_food_image.dart';
import '../../widgets/section_header.dart';
import '../../widgets/status_pill.dart';
import '../shared/bkash_settings_sheet.dart';
import 'kitchen_details_screen.dart';
import 'customer_order_details_screen.dart';

class CustomerHomeScreen extends StatefulWidget {
  const CustomerHomeScreen({super.key});

  @override
  State<CustomerHomeScreen> createState() => _CustomerHomeScreenState();
}

class _CustomerHomeScreenState extends State<CustomerHomeScreen>
    with WidgetsBindingObserver {
  int _currentIndex = 0;
  double _currentLat = 23.8103; // Default Dhaka Center
  double _currentLng = 90.4125;
  bool _showLocationPanel = false;

  final TextEditingController _mockLatController = TextEditingController(
    text: "23.8103",
  );
  final TextEditingController _mockLngController = TextEditingController(
    text: "90.4125",
  );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchCurrentLocationAndLoadKitchens();
      _subscribeToMyOrders();
      _startLiveLocationTracking();
    });
  }

  void _subscribeToMyOrders() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).subscribeToMyOrders(authProvider.user!.id);
    }
  }

  /// Broadcasts the customer's real live location as soon as they're logged
  /// in — rider screens still only reveal it once a delivery reaches
  /// 'picked_up' (see rider_order_details_screen's pickup gate), but the
  /// broadcast itself should not wait for that so it's already live by then.
  void _startLiveLocationTracking() {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    if (authProvider.user != null) {
      Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).startLocationTracking(authProvider.user!.id);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime channels can silently drop on mobile network handoff;
    // re-subscribing on resume is cheap since .stream() re-runs the initial
    // SELECT too, restoring state even if the socket died while backgrounded.
    if (state == AppLifecycleState.resumed) {
      _subscribeToMyOrders();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _mockLatController.dispose();
    _mockLngController.dispose();
    super.dispose();
  }

  /// Fetches a one-off fix purely to center the "nearby kitchens" search —
  /// a generic fallback point here is harmless for that purpose, so this
  /// intentionally does NOT write to the profile's live-location columns.
  /// Real live-location broadcasting is owned by [_startLiveLocationTracking]
  /// (via CustomerProvider.startLocationTracking), which only ever writes a
  /// genuine GPS fix, never this fallback.
  Future<void> _fetchCurrentLocationAndLoadKitchens() async {
    final location = await LocationService.getCurrentLocation();
    setState(() {
      _currentLat = location['latitude']!;
      _currentLng = location['longitude']!;
      _mockLatController.text = _currentLat.toString();
      _mockLngController.text = _currentLng.toString();
    });

    if (mounted) {
      await Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).loadNearbyKitchens(_currentLat, _currentLng);
    }
  }

  void _applyMockLocation() async {
    final lat = double.tryParse(_mockLatController.text);
    final lng = double.tryParse(_mockLngController.text);
    if (lat != null && lng != null) {
      LocationService.setMockLocation(lat, lng);
      setState(() {
        _currentLat = lat;
        _currentLng = lng;
      });
      final authProvider = Provider.of<AuthProvider>(context, listen: false);
      await authProvider.updateProfileLocation(lat, lng);
      await Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).loadNearbyKitchens(lat, lng);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Mock location applied: ($lat, $lng)')),
      );
    }
  }

  void _clearMockLocation() {
    LocationService.clearMockLocation();
    _fetchCurrentLocationAndLoadKitchens();
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Mock location cleared. Using GPS fallback.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerProvider = context.watch<CustomerProvider>();

    return Scaffold(
      appBar: ResponsiveAppBar(
        title: 'Cloud Kitchen',
        actions: [
          AppBarActionItem(
            icon: Icons.payments_outlined,
            label: 'Your bKash number',
            onPressed: () => showBkashNumberSheet(context),
          ),
          AppBarActionItem(
            icon: Icons.logout_rounded,
            label: 'Log out',
            alwaysInline: true,
            onPressed: () async {
              Provider.of<CustomerProvider>(
                context,
                listen: false,
              ).stopLocationTracking();
              await Provider.of<AuthProvider>(context, listen: false).logout();
              if (mounted)
                Navigator.of(context).popUntil((route) => route.isFirst);
            },
          ),
        ],
      ),
      body: _currentIndex == 0
          ? _buildBrowseTab(context, customerProvider)
          : _buildOrdersTab(context, customerProvider),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.explore_outlined),
            label: 'Explore',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.receipt_long_outlined),
            label: 'My Orders',
          ),
        ],
      ),
    );
  }

  Widget _buildBrowseTab(
    BuildContext context,
    CustomerProvider customerProvider,
  ) {
    final text = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () => Provider.of<CustomerProvider>(
        context,
        listen: false,
      ).loadNearbyKitchens(_currentLat, _currentLng),
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!customerProvider.isTrackingLocation &&
                customerProvider.errorMessage != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: AppRadius.lgBr,
                  border: Border.all(
                    color: Colors.orangeAccent.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.location_off_rounded,
                      color: Colors.orangeAccent,
                      size: 18,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        customerProvider.errorMessage!,
                        style: text.bodySmall?.copyWith(
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
            ],
            // Location simulator panel — subtle, collapsible test tool.
            _buildLocationSimulator(context),
            const SizedBox(height: AppSpacing.xl),

            const SectionHeader(title: 'Kitchens Near You'),

            if (customerProvider.isLoading)
              Column(children: List.generate(3, (_) => const SkeletonCardRow()))
            else if (customerProvider.kitchens.isEmpty)
              const EmptyState(
                icon: Icons.storefront_outlined,
                title: 'No kitchens found nearby',
                message:
                    'Try adjusting your location to discover kitchens in another area.',
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: customerProvider.kitchens.length,
                itemBuilder: (context, index) {
                  final kitchen = customerProvider.kitchens[index];
                  final dist = LocationService.calculateDistance(
                    _currentLat,
                    _currentLng,
                    kitchen.latitude,
                    kitchen.longitude,
                  );

                  return _KitchenCard(
                    key: ValueKey(kitchen.id),
                    index: index,
                    kitchenId: kitchen.id,
                    imageUrl: kitchen.imageUrl,
                    ownerAvatarUrl: kitchen.ownerAvatarUrl,
                    name: kitchen.name,
                    description: kitchen.description,
                    latitude: kitchen.effectiveLatitude,
                    longitude: kitchen.effectiveLongitude,
                    distanceKm: dist,
                    onTap: () {
                      Navigator.of(context).push(
                        appPageRoute(
                          KitchenDetailsScreen(
                            kitchen: kitchen,
                            customerLatitude: _currentLat,
                            customerLongitude: _currentLng,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationSimulator(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.mdBr,
        border: Border.all(color: scheme.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: AppRadius.mdBr,
            onTap: () =>
                setState(() => _showLocationPanel = !_showLocationPanel),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: scheme.onSurface.withValues(alpha: 0.55),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      'Location testing (${_currentLat.toStringAsFixed(3)}, ${_currentLng.toStringAsFixed(3)})',
                      style: text.labelMedium?.copyWith(
                        color: scheme.onSurface.withValues(alpha: 0.6),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  AnimatedRotation(
                    turns: _showLocationPanel ? 0.5 : 0,
                    duration: AppMotion.fast,
                    child: Icon(
                      Icons.expand_more_rounded,
                      size: 18,
                      color: scheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            duration: AppMotion.base,
            sizeCurve: AppMotion.curve,
            crossFadeState: _showLocationPanel
                ? CrossFadeState.showFirst
                : CrossFadeState.showSecond,
            firstChild: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                0,
                AppSpacing.md,
                AppSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Divider(height: AppSpacing.lg),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _mockLatController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Lat',
                            isDense: true,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: TextField(
                          controller: _mockLngController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Lng',
                            isDense: true,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton.icon(
                        onPressed: _clearMockLocation,
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reset'),
                      ),
                      FilledButton.tonal(
                        onPressed: _applyMockLocation,
                        child: const Text('Apply Mock'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            secondChild: const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildOrdersTab(
    BuildContext context,
    CustomerProvider customerProvider,
  ) {
    if (customerProvider.isLoading && customerProvider.myOrders.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: List.generate(4, (_) => const SkeletonCardRow()),
      );
    }

    if (customerProvider.myOrders.isEmpty) {
      return const Center(
        child: EmptyState(
          icon: Icons.receipt_long_outlined,
          title: 'No orders placed yet',
          message: 'Browse kitchens near you and place your first order.',
        ),
      );
    }

    final text = Theme.of(context).textTheme;

    return ListView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      itemCount: customerProvider.myOrders.length,
      itemBuilder: (context, index) {
        final order = customerProvider.myOrders[index];

        return Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: InkWell(
            borderRadius: AppRadius.lgBr,
            onTap: () {
              Navigator.of(
                context,
              ).push(appPageRoute(CustomerOrderDetailsScreen(order: order)));
            },
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          order.kitchenName ?? 'Kitchen Order',
                          style: text.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Total: ${formatCurrency(order.totalAmount)}',
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Placed: ${order.createdAt.toLocal().toString().substring(0, 16)}',
                          style: text.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      StatusPill(status: order.status, dense: true),
                      const SizedBox(height: 8),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 18,
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A restaurant card for the kitchen browse list, with a subtle staggered
/// fade/slide entrance so the list doesn't feel like it just snapped in.
class _KitchenCard extends StatefulWidget {
  final int index;
  final String kitchenId;
  final String? imageUrl;
  final String? ownerAvatarUrl;
  final String name;
  final String? description;
  final double latitude;
  final double longitude;
  final double distanceKm;
  final VoidCallback onTap;

  const _KitchenCard({
    super.key,
    required this.index,
    required this.kitchenId,
    required this.imageUrl,
    this.ownerAvatarUrl,
    required this.name,
    required this.description,
    required this.latitude,
    required this.longitude,
    required this.distanceKm,
    required this.onTap,
  });

  @override
  State<_KitchenCard> createState() => _KitchenCardState();
}

class _KitchenCardState extends State<_KitchenCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: AppMotion.slow);
    final curved = CurvedAnimation(parent: _controller, curve: AppMotion.curve);
    _fade = curved;
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(curved);
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
    final text = Theme.of(context).textTheme;

    return FadeTransition(
      opacity: _fade,
      child: SlideTransition(
        position: _slide,
        child: Card(
          margin: const EdgeInsets.only(bottom: AppSpacing.md),
          child: InkWell(
            borderRadius: AppRadius.lgBr,
            onTap: widget.onTap,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Hero(
                    tag: 'kitchen-owner-photo-${widget.kitchenId}',
                    child: NetworkFoodImage(
                      // The list card shows the owner's profile photo (not
                      // the kitchen's cover photo) — falls back to the cover
                      // photo only if the owner hasn't set one either.
                      url:
                          (widget.ownerAvatarUrl != null &&
                              widget.ownerAvatarUrl!.isNotEmpty)
                          ? widget.ownerAvatarUrl
                          : widget.imageUrl,
                      width: 88,
                      height: 88,
                      radius: AppRadius.mdBr,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.name,
                          style: Theme.of(context).textTheme.headlineSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.description ?? 'Delectable food delivery',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodyMedium,
                        ),
                        const SizedBox(height: 4),
                        LiveLocationText(
                          latitude: widget.latitude,
                          longitude: widget.longitude,
                          style: text.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                          icon: Icons.location_on_outlined,
                          iconSize: 13,
                          iconColor: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primaryContainer,
                                borderRadius: AppRadius.pillBr,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.near_me_rounded,
                                    size: 12,
                                    color: scheme.onPrimaryContainer,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    '${widget.distanceKm.toStringAsFixed(1)} km',
                                    style: text.labelSmall?.copyWith(
                                      color: scheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
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
          ),
        ),
      ),
    );
  }
}
