import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../models/order.dart';
import '../../providers/auth_provider.dart';
import '../../providers/kitchen_provider.dart';
import '../../services/geocoding_service.dart';
import '../../services/location_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/network_food_image.dart';
import '../../widgets/status_pill.dart';
import '../shared/bkash_settings_sheet.dart';
import '../shared/reviews_screen.dart';
import 'kitchen_menu_screen.dart';
import 'kitchen_order_details_screen.dart';
import 'kitchen_order_history_screen.dart';

class KitchenHomeScreen extends StatefulWidget {
  const KitchenHomeScreen({super.key});

  @override
  State<KitchenHomeScreen> createState() => _KitchenHomeScreenState();
}

class _KitchenHomeScreenState extends State<KitchenHomeScreen>
    with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _addressController = TextEditingController();
  bool _isActive = true;

  // Onboarding captures the device's live GPS position once, automatically,
  // instead of asking the owner to type coordinates — that manual-entry
  // field used to default to Dhaka's center and silently register the
  // kitchen there whenever the owner left it untouched.
  double? _onboardLat;
  double? _onboardLng;
  bool _detectingOnboardLocation = true;

  bool _isUpdatingLocation = false;

  double _avgRating = 0.0;
  int _ratingCount = 0;

  final ImagePicker _avatarPicker = ImagePicker();
  bool _isUploadingAvatar = false;

  final ImagePicker _coverPicker = ImagePicker();
  bool _isUploadingCover = false;

  Future<void> _pickAndUploadAvatar() async {
    final XFile? file = await _avatarPicker.pickImage(
      source: ImageSource.gallery,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    setState(() => _isUploadingAvatar = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final success = await authProvider.uploadAndSetAvatar(bytes, file.name);

    if (!mounted) return;
    setState(() => _isUploadingAvatar = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Profile picture updated!'
              : friendlyErrorMessage(
                  authProvider.errorMessage,
                  fallback: 'Failed to update profile picture.',
                ),
        ),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  Future<void> _pickAndUploadCoverPhoto() async {
    final XFile? file = await _coverPicker.pickImage(
      source: ImageSource.gallery,
    );
    if (file == null || !mounted) return;

    final bytes = await file.readAsBytes();
    setState(() => _isUploadingCover = true);

    final kitchenProvider = Provider.of<KitchenProvider>(
      context,
      listen: false,
    );
    final success = await kitchenProvider.uploadKitchenCoverImage(
      bytes,
      file.name,
    );

    if (!mounted) return;
    setState(() => _isUploadingCover = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Cover photo updated!'
              : friendlyErrorMessage(
                  kitchenProvider.errorMessage,
                  fallback: 'Failed to update cover photo.',
                ),
        ),
        backgroundColor: success ? Colors.green : Colors.redAccent,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadKitchenDetails();
      _detectOnboardLocation();
    });
  }

  /// Fetches the device's current GPS position once, for use as the
  /// kitchen's permanent registered coordinates if this owner hasn't set up
  /// a kitchen yet. Harmless (just unused) if they already have one.
  Future<void> _detectOnboardLocation() async {
    final location = await LocationService.getCurrentLocation();
    if (!mounted) return;
    setState(() {
      _onboardLat = location['latitude'];
      _onboardLng = location['longitude'];
      _detectingOnboardLocation = false;
    });

    if (_addressController.text.trim().isEmpty) {
      final resolved = await GeocodingService.reverseGeocode(
        _onboardLat!,
        _onboardLng!,
      );
      if (!mounted || _addressController.text.trim().isNotEmpty) return;
      setState(() => _addressController.text = resolved);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Realtime channels can silently drop on mobile network handoff;
    // re-subscribing on resume is cheap since .stream() re-runs the initial
    // SELECT too, restoring state even if the socket died while backgrounded.
    if (state == AppLifecycleState.resumed) {
      final kitchenProvider = Provider.of<KitchenProvider>(
        context,
        listen: false,
      );
      if (kitchenProvider.kitchen != null) {
        kitchenProvider.subscribeToOrders();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nameController.dispose();
    _descController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _loadKitchenDetails() async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final kitchenProvider = Provider.of<KitchenProvider>(
      context,
      listen: false,
    );
    await kitchenProvider.loadKitchen(authProvider.user!.id);

    if (kitchenProvider.kitchen != null) {
      kitchenProvider.subscribeToOrders();
      final stats = await kitchenProvider.getKitchenRatingStats();
      if (!mounted) return;
      setState(() {
        _avgRating = stats['rating'] as double;
        _ratingCount = stats['count'] as int;
      });

      // Broadcast the owner's real live location as soon as they land on the
      // dashboard, so riders/customers see their actual position instead of
      // the kitchen's static registered address from the moment they log in.
      kitchenProvider.startLocationTracking(authProvider.user!.id);
    }
  }

  void _onboardKitchen() async {
    if (!_formKey.currentState!.validate()) return;
    if (_detectingOnboardLocation) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still detecting your location — one moment…'),
        ),
      );
      return;
    }

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final kitchenProvider = Provider.of<KitchenProvider>(
      context,
      listen: false,
    );

    final success = await kitchenProvider.saveKitchen(
      ownerId: authProvider.user!.id,
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      address: _addressController.text.trim(),
      // Falls back to LocationService's own default (Dhaka center) only if
      // GPS was genuinely unavailable/denied — see _detectOnboardLocation.
      latitude: _onboardLat ?? 23.8103,
      longitude: _onboardLng ?? 90.4125,
      isActive: _isActive,
    );

    if (success && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Kitchen profile set up successfully!'),
          backgroundColor: Colors.green,
        ),
      );
      _loadKitchenDetails();
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            friendlyErrorMessage(
              kitchenProvider.errorMessage,
              fallback: 'Onboarding failed. Please try again.',
            ),
          ),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  /// Lets the owner re-capture their kitchen's registered pickup location
  /// from wherever they currently are — e.g. after moving premises — without
  /// having to type coordinates. Keeps every other kitchen field unchanged.
  Future<void> _updateKitchenLocation() async {
    if (_isUpdatingLocation) return;
    setState(() => _isUpdatingLocation = true);

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final kitchenProvider = Provider.of<KitchenProvider>(
      context,
      listen: false,
    );
    final kitchen = kitchenProvider.kitchen;
    if (kitchen == null) {
      setState(() => _isUpdatingLocation = false);
      return;
    }

    final location = await LocationService.getCurrentLocation();
    final resolvedAddress = await GeocodingService.reverseGeocode(
      location['latitude']!,
      location['longitude']!,
    );

    final success = await kitchenProvider.saveKitchen(
      ownerId: authProvider.user!.id,
      name: kitchen.name,
      description: kitchen.description,
      address: resolvedAddress,
      imageUrl: kitchen.imageUrl,
      latitude: location['latitude']!,
      longitude: location['longitude']!,
      isActive: kitchen.isActive,
    );

    if (!mounted) return;
    setState(() => _isUpdatingLocation = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Kitchen location updated to $resolvedAddress'
              : friendlyErrorMessage(
                  kitchenProvider.errorMessage,
                  fallback: 'Could not update location. Please try again.',
                ),
        ),
        backgroundColor: success
            ? context.appColors.success
            : Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _toggleKitchenActive(bool val) async {
    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final kitchenProvider = Provider.of<KitchenProvider>(
      context,
      listen: false,
    );
    if (kitchenProvider.kitchen == null) return;

    final success = await kitchenProvider.saveKitchen(
      ownerId: authProvider.user!.id,
      name: kitchenProvider.kitchen!.name,
      description: kitchenProvider.kitchen!.description,
      address: kitchenProvider.kitchen!.address,
      imageUrl: kitchenProvider.kitchen!.imageUrl,
      latitude: kitchenProvider.kitchen!.latitude,
      longitude: kitchenProvider.kitchen!.longitude,
      isActive: val,
    );

    if (success) {
      setState(() {
        _isActive = val;
      });
      // Live location broadcasting stays on regardless of open/closed —
      // it's tied to being logged in, not to accepting orders.
    }
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final kitchenProvider = context.watch<KitchenProvider>();

    if (kitchenProvider.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (kitchenProvider.kitchen == null) {
      return _buildOnboardingScreen();
    }

    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    final pendingOrders = kitchenProvider.orders
        .where((o) => o.status == 'pending')
        .toList();
    final activeOrders = kitchenProvider.orders
        .where(
          (o) =>
              o.status != 'pending' &&
              o.status != 'completed' &&
              o.status != 'rejected',
        )
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(kitchenProvider.kitchen!.name),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: kBrandGradient,
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        titleTextStyle: text.headlineSmall?.copyWith(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Update kitchen location',
            icon: _isUpdatingLocation
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.edit_location_alt_outlined),
            onPressed: _isUpdatingLocation ? null : _updateKitchenLocation,
          ),
          IconButton(
            tooltip: 'Your bKash number',
            icon: const Icon(Icons.payments_outlined),
            onPressed: () => showBkashNumberSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () async {
              kitchenProvider.stopLocationTracking();
              await authProvider.logout();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadKitchenDetails,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Cover photo — shown to customers on the kitchen list and
              // details banner; tap to add/replace.
              GestureDetector(
                onTap: _isUploadingCover ? null : _pickAndUploadCoverPhoto,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: AppRadius.lgBr,
                      child:
                          (kitchenProvider.kitchen!.imageUrl != null &&
                              kitchenProvider.kitchen!.imageUrl!.isNotEmpty)
                          ? NetworkFoodImage(
                              url: kitchenProvider.kitchen!.imageUrl,
                              width: double.infinity,
                              height: 150,
                              radius: BorderRadius.zero,
                              fallbackIcon: Icons.storefront_rounded,
                            )
                          : Container(
                              width: double.infinity,
                              height: 150,
                              color: scheme.surfaceContainerHighest,
                              child: Icon(
                                Icons.storefront_rounded,
                                size: 40,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.4,
                                ),
                              ),
                            ),
                    ),
                    if (_isUploadingCover)
                      Container(
                        color: Colors.black45,
                        width: double.infinity,
                        height: 150,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      )
                    else
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: AppRadius.pillBr,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.camera_alt,
                                color: Colors.white,
                                size: 14,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                (kitchenProvider.kitchen!.imageUrl != null &&
                                        kitchenProvider
                                            .kitchen!
                                            .imageUrl!
                                            .isNotEmpty)
                                    ? 'Change cover'
                                    : 'Add cover photo',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // Dashboard Header Card
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: kBrandGradient,
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: AppRadius.lgBr,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        GestureDetector(
                          onTap: _isUploadingAvatar
                              ? null
                              : _pickAndUploadAvatar,
                          child: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                radius: 28,
                                backgroundColor: Colors.white.withValues(
                                  alpha: 0.15,
                                ),
                                backgroundImage:
                                    (authProvider.profile?.avatarUrl != null &&
                                        authProvider
                                            .profile!
                                            .avatarUrl!
                                            .isNotEmpty)
                                    ? CachedNetworkImageProvider(
                                        authProvider.profile!.avatarUrl!,
                                      )
                                    : null,
                                child: _isUploadingAvatar
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : (authProvider.profile?.avatarUrl ==
                                              null ||
                                          authProvider
                                              .profile!
                                              .avatarUrl!
                                              .isEmpty)
                                    ? const Icon(
                                        Icons.person,
                                        color: Colors.white,
                                        size: 28,
                                      )
                                    : null,
                              ),
                              Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.camera_alt,
                                  color: Colors.white,
                                  size: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                kitchenProvider.kitchen!.name,
                                style: text.headlineSmall?.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              LiveLocationText(
                                latitude:
                                    authProvider.profile?.latitude ??
                                    kitchenProvider.kitchen!.latitude,
                                longitude:
                                    authProvider.profile?.longitude ??
                                    kitchenProvider.kitchen!.longitude,
                                style: text.bodySmall?.copyWith(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    // Open/Closed state control — the single most consequential
                    // switch on this screen (toggling it stops new orders).
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.06),
                        borderRadius: AppRadius.mdBr,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.14),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: kitchenProvider.kitchen!.isActive
                                  ? context.appColors.success
                                  : Colors.white38,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  kitchenProvider.kitchen!.isActive
                                      ? 'Open for orders'
                                      : 'Closed',
                                  style: text.titleMedium?.copyWith(
                                    color: Colors.white,
                                  ),
                                ),
                                Text(
                                  kitchenProvider.kitchen!.isActive
                                      ? 'Customers can order from you now'
                                      : 'New orders are paused',
                                  style: text.bodySmall?.copyWith(
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Switch(
                            value: kitchenProvider.kitchen!.isActive,
                            activeThumbColor: context.appColors.success,
                            onChanged: _toggleKitchenActive,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _LiveLocationBadge(
                      isTracking: kitchenProvider.isTrackingLocation,
                    ),
                    if (!kitchenProvider.isTrackingLocation &&
                        kitchenProvider.errorMessage != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        kitchenProvider.errorMessage!,
                        style: text.bodySmall?.copyWith(
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    Divider(
                      color: Colors.white.withValues(alpha: 0.14),
                      height: 1,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Row(
                      children: [
                        Expanded(
                          flex: 4,
                          child: _buildMetricColumn(
                            context,
                            'Avg rating',
                            _avgRating > 0
                                ? _avgRating.toStringAsFixed(1)
                                : '—',
                            valueStyle: text.displaySmall?.copyWith(
                              color: context.appColors.ratingStar,
                            ),
                            icon: Icons.star_rounded,
                            iconColor: context.appColors.ratingStar,
                          ),
                        ),
                        _headerDivider(),
                        Expanded(
                          flex: 3,
                          child: Semantics(
                            button: true,
                            label: '$_ratingCount reviews, view details',
                            child: InkWell(
                              borderRadius: AppRadius.mdBr,
                              onTap: () => Navigator.of(context).push(
                                appPageRoute(
                                  ReviewsScreen(
                                    title:
                                        '${kitchenProvider.kitchen!.name} Reviews',
                                    avgRating: _avgRating,
                                    reviewCount: _ratingCount,
                                    loadReviews:
                                        kitchenProvider.getKitchenReviews,
                                  ),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: _buildMetricColumn(
                                  context,
                                  'Reviews',
                                  '$_ratingCount',
                                  valueStyle: text.titleLarge?.copyWith(
                                    color: Colors.white,
                                  ),
                                  tappable: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                        _headerDivider(),
                        Expanded(
                          flex: 3,
                          child: Semantics(
                            button: true,
                            label:
                                '${kitchenProvider.orders.length} orders, view order history',
                            child: InkWell(
                              borderRadius: AppRadius.mdBr,
                              onTap: () => Navigator.of(context).push(
                                appPageRoute(const KitchenOrderHistoryScreen()),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: AppSpacing.sm,
                                ),
                                child: _buildMetricColumn(
                                  context,
                                  'Orders',
                                  '${kitchenProvider.orders.length}',
                                  valueStyle: text.titleLarge?.copyWith(
                                    color: Colors.white,
                                  ),
                                  tappable: true,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.lg),

              // Navigation to Menu CRUD
              ElevatedButton.icon(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(appPageRoute(const KitchenMenuScreen()));
                },
                icon: const Icon(Icons.restaurant_menu),
                label: const Text('Manage Menu Items'),
              ),
              const SizedBox(height: AppSpacing.xxl),

              // Pending Orders
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Incoming orders', style: text.headlineSmall),
                  if (pendingOrders.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: AppRadius.pillBr,
                      ),
                      child: Text(
                        '${pendingOrders.length}',
                        style: text.labelMedium?.copyWith(
                          color: scheme.onPrimaryContainer,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              if (pendingOrders.isEmpty)
                const EmptyState(
                  icon: Icons.inbox_rounded,
                  title: 'No pending orders',
                  message: 'New orders will show up here as they come in.',
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: pendingOrders.length,
                  itemBuilder: (context, index) {
                    final order = pendingOrders[index];
                    return _IncomingOrderCard(
                      order: order,
                      onAccept: () => kitchenProvider.updateOrderStatus(
                        order.id,
                        'accepted',
                      ),
                      onReject: () => kitchenProvider.updateOrderStatus(
                        order.id,
                        'rejected',
                      ),
                      onConfirmPayment: () =>
                          kitchenProvider.confirmPaymentReceived(order.id),
                      onTap: () => Navigator.of(context).push(
                        appPageRoute(KitchenOrderDetailsScreen(order: order)),
                      ),
                    );
                  },
                ),

              const SizedBox(height: AppSpacing.xxl),

              // Active Orders
              Text('Active orders', style: text.headlineSmall),
              const SizedBox(height: AppSpacing.md),
              if (activeOrders.isEmpty)
                const EmptyState(
                  icon: Icons.soup_kitchen_rounded,
                  title: 'No active orders',
                  message:
                      'Orders you accept will be tracked here until delivery.',
                )
              else
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: activeOrders.length,
                  itemBuilder: (context, index) {
                    final order = activeOrders[index];
                    return _ActiveOrderCard(
                      order: order,
                      onTap: () => Navigator.of(context).push(
                        appPageRoute(KitchenOrderDetailsScreen(order: order)),
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _headerDivider() => Container(
    width: 1,
    height: 36,
    color: Colors.white.withValues(alpha: 0.14),
  );

  Widget _buildMetricColumn(
    BuildContext context,
    String label,
    String value, {
    TextStyle? valueStyle,
    IconData? icon,
    Color? iconColor,
    bool tappable = false,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 18, color: iconColor ?? Colors.white),
              const SizedBox(width: 4),
            ],
            Text(value, style: valueStyle),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(color: Colors.white60),
            ),
            if (tappable) ...[
              const SizedBox(width: 1),
              const Icon(
                Icons.chevron_right_rounded,
                size: 13,
                color: Colors.white60,
              ),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildOnboardingScreen() {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Setup Kitchen Profile')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.storefront_rounded,
                    size: 44,
                    color: scheme.onPrimaryContainer,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'Welcome aboard!',
                textAlign: TextAlign.center,
                style: text.headlineMedium,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                "Let's set up your cloud kitchen profile so customers can start finding and ordering from you.",
                textAlign: TextAlign.center,
                style: text.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xxl),
              Text('Kitchen details', style: text.titleSmall),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Kitchen Name',
                  hintText: 'e.g. Grandma\'s Kitchen',
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter kitchen name' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _descController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Description',
                  hintText: 'What makes your food special?',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              TextFormField(
                controller: _addressController,
                decoration: const InputDecoration(
                  labelText: 'Address',
                  hintText: 'Where customers will be ordering from',
                ),
                validator: (val) =>
                    val == null || val.isEmpty ? 'Enter address' : null,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text('Kitchen location', style: text.titleSmall),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Captured automatically from your device\'s current position — this is saved permanently as your kitchen\'s pickup location. You can update it any time from your dashboard.',
                style: text.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm + 2,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: AppRadius.mdBr,
                ),
                child: Row(
                  children: [
                    Icon(
                      _detectingOnboardLocation
                          ? Icons.gps_not_fixed_rounded
                          : Icons.gps_fixed_rounded,
                      size: 18,
                      color: _detectingOnboardLocation
                          ? scheme.onSurfaceVariant
                          : context.appColors.success,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        _detectingOnboardLocation
                            ? 'Detecting your live location…'
                            : 'Location detected (${_onboardLat!.toStringAsFixed(4)}, ${_onboardLng!.toStringAsFixed(4)})',
                        style: text.bodySmall,
                      ),
                    ),
                    if (_detectingOnboardLocation)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      IconButton(
                        tooltip: 'Re-detect location',
                        icon: const Icon(Icons.refresh_rounded, size: 20),
                        onPressed: () {
                          setState(() {
                            _detectingOnboardLocation = true;
                            _addressController.clear();
                          });
                          _detectOnboardLocation();
                        },
                      ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              ElevatedButton(
                onPressed: _onboardKitchen,
                child: const Text('Save Profile & Start'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pulsing badge on the dashboard header showing whether the kitchen's
/// live location is currently broadcasting — the kitchen-owner equivalent of
/// the rider dashboard's GPS status indicator.
class _LiveLocationBadge extends StatefulWidget {
  final bool isTracking;
  const _LiveLocationBadge({required this.isTracking});

  @override
  State<_LiveLocationBadge> createState() => _LiveLocationBadgeState();
}

class _LiveLocationBadgeState extends State<_LiveLocationBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    return Row(
      children: [
        SizedBox(
          width: 22,
          height: 22,
          child: widget.isTracking
              ? AnimatedBuilder(
                  animation: _pulseController,
                  builder: (context, child) {
                    final t = _pulseController.value;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 22 * (0.6 + t * 0.6),
                          height: 22 * (0.6 + t * 0.6),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(
                              alpha: (1 - t) * 0.35,
                            ),
                          ),
                        ),
                        child!,
                      ],
                    );
                  },
                  child: const Icon(
                    Icons.gps_fixed_rounded,
                    color: Colors.white,
                    size: 15,
                  ),
                )
              : Icon(
                  Icons.gps_not_fixed_rounded,
                  color: Colors.white.withValues(alpha: 0.6),
                  size: 15,
                ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Text(
            widget.isTracking
                ? 'Sharing your live location with customers & riders'
                : 'Preparing to share live location…',
            style: text.labelMedium?.copyWith(color: Colors.white70),
          ),
        ),
      ],
    );
  }
}

/// Compact human-readable summary of an order's items, e.g. "2x Burger, 1x Fries".
String _itemSummary(Order order) {
  final items = order.items;
  if (items == null || items.isEmpty) return '';
  return items.map((i) => '${i.quantity}x ${i.menuItemName}').join(', ');
}

class _IncomingOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onAccept;
  final VoidCallback onReject;
  final VoidCallback onConfirmPayment;
  final VoidCallback onTap;

  const _IncomingOrderCard({
    required this.order,
    required this.onAccept,
    required this.onReject,
    required this.onConfirmPayment,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final appColors = context.appColors;
    final summary = _itemSummary(order);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: AppRadius.lgBr,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
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
                        Text(
                          order.customerName ?? 'Customer',
                          style: text.titleMedium,
                        ),
                        if (summary.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            summary,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                  Text(
                    formatCurrency(order.totalAmount),
                    style: text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              _PaymentStatusChip(order: order),
              const SizedBox(height: AppSpacing.md),
              if (order.paymentStatus == 'awaiting_payment')
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                            color: scheme.error.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.pillBr,
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                      ),
                    ),
                  ],
                )
              else if (order.paymentStatus == 'payment_reported')
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (order.customerBkashTxnId != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          'bKash TrxID: ${order.customerBkashTxnId}',
                          style: text.bodySmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: onReject,
                            style: OutlinedButton.styleFrom(
                              foregroundColor: scheme.error,
                              side: BorderSide(
                                color: scheme.error.withValues(alpha: 0.4),
                              ),
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.pillBr,
                              ),
                            ),
                            child: const Text('Reject'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton.icon(
                            onPressed: onConfirmPayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: appColors.success,
                              foregroundColor: appColors.onSuccess,
                              padding: const EdgeInsets.symmetric(
                                vertical: AppSpacing.sm,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: AppRadius.pillBr,
                              ),
                              elevation: 0,
                            ),
                            icon: const Icon(Icons.verified_rounded, size: 18),
                            label: const Text('Confirm Payment'),
                          ),
                        ),
                      ],
                    ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: onReject,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: scheme.error,
                          side: BorderSide(
                            color: scheme.error.withValues(alpha: 0.4),
                          ),
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.pillBr,
                          ),
                        ),
                        icon: const Icon(Icons.close_rounded, size: 18),
                        label: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: onAccept,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: appColors.success,
                          foregroundColor: appColors.onSuccess,
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.pillBr,
                          ),
                          elevation: 0,
                        ),
                        icon: const Icon(Icons.check_rounded, size: 18),
                        label: const Text('Accept'),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small pill summarizing where an order stands in the manual bKash payment
/// flow — awaiting the customer to send money, reported and awaiting the
/// owner's confirmation, or confirmed and ready to accept.
class _PaymentStatusChip extends StatelessWidget {
  final Order order;
  const _PaymentStatusChip({required this.order});

  @override
  Widget build(BuildContext context) {
    final appColors = context.appColors;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    late final Color fg;
    late final Color bg;
    late final IconData icon;
    late final String label;

    switch (order.paymentStatus) {
      case 'payment_confirmed':
        fg = appColors.success;
        bg = appColors.successContainer;
        icon = Icons.check_circle_rounded;
        label = 'Payment confirmed';
        break;
      case 'payment_reported':
        fg = appColors.warning;
        bg = appColors.warningContainer;
        icon = Icons.hourglass_top_rounded;
        label = 'Customer reported payment — verify & confirm';
        break;
      default:
        fg = scheme.onSurfaceVariant;
        bg = scheme.surfaceContainerHighest;
        icon = Icons.schedule_rounded;
        label = 'Awaiting customer bKash payment';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: AppRadius.pillBr),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: text.labelSmall?.copyWith(color: fg),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActiveOrderCard extends StatelessWidget {
  final Order order;
  final VoidCallback onTap;

  const _ActiveOrderCard({required this.order, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final summary = _itemSummary(order);

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: InkWell(
        borderRadius: AppRadius.lgBr,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      order.customerName ?? 'Customer',
                      style: text.titleMedium,
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.bodySmall,
                      ),
                    ],
                    const SizedBox(height: AppSpacing.sm),
                    StatusPill(status: order.status),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    formatCurrency(order.totalAmount),
                    style: text.titleMedium?.copyWith(color: scheme.primary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Icon(
                    Icons.arrow_forward_ios_rounded,
                    size: 14,
                    color: scheme.onSurface.withValues(alpha: 0.4),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
