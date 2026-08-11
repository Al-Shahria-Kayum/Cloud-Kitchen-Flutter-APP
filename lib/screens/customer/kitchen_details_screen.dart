import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/kitchen.dart';
import '../../models/menu_item.dart';
import '../../providers/customer_provider.dart';
import '../../providers/kitchen_provider.dart';
import '../../services/geocoding_service.dart';
import '../../theme/app_theme.dart';
import '../../utils/currency_format.dart';
import '../../utils/error_mapper.dart';
import '../../widgets/app_page_route.dart';
import '../../widgets/app_shimmer.dart';
import '../../widgets/empty_state.dart';
import '../../widgets/live_location_text.dart';
import '../../widgets/network_food_image.dart';
import '../../widgets/photo_carousel.dart';
import '../../widgets/section_header.dart';
import '../shared/reviews_screen.dart';

class KitchenDetailsScreen extends StatefulWidget {
  final Kitchen kitchen;

  /// The customer's own live position — used to default the delivery
  /// address to where they actually are right now, instead of the
  /// kitchen's own address or a fake offset from it. Null falls back to
  /// letting the customer type an address with no live-location default.
  final double? customerLatitude;
  final double? customerLongitude;

  const KitchenDetailsScreen({
    super.key,
    required this.kitchen,
    this.customerLatitude,
    this.customerLongitude,
  });

  @override
  State<KitchenDetailsScreen> createState() => _KitchenDetailsScreenState();
}

class _KitchenDetailsScreenState extends State<KitchenDetailsScreen> {
  String? _ownerName;
  String? _ownerAvatarUrl;
  double? _ownerLat;
  double? _ownerLng;
  double _avgRating = 0.0;
  int _ratingCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<CustomerProvider>(context, listen: false).subscribeToKitchenMenu(widget.kitchen.id);
      _loadOwnerProfile();
      _loadRatingStats();
    });
  }

  Future<void> _loadRatingStats() async {
    final stats = await Provider.of<KitchenProvider>(context, listen: false)
        .getKitchenRatingStats(ownerId: widget.kitchen.ownerId);
    if (!mounted) return;
    setState(() {
      _avgRating = stats['rating'] as double;
      _ratingCount = stats['count'] as int;
    });
  }

  Future<void> _loadOwnerProfile() async {
    final owner = await Provider.of<CustomerProvider>(context, listen: false).getKitchenOwnerProfile(widget.kitchen.ownerId);
    if (!mounted || owner == null) return;
    setState(() {
      _ownerName = owner['full_name'] as String?;
      _ownerAvatarUrl = owner['avatar_url'] as String?;
      _ownerLat = owner['latitude'] != null ? (owner['latitude'] as num).toDouble() : null;
      _ownerLng = owner['longitude'] != null ? (owner['longitude'] as num).toDouble() : null;
    });
  }

  void _showOrderSheet(MenuItem item) {
    int quantity = 1;
    final addressController = TextEditingController();
    final hasCustomerLocation = widget.customerLatitude != null && widget.customerLongitude != null;
    bool isResolvingAddress = hasCustomerLocation;
    bool addressWasAutoFilled = false;

    // Default the delivery address to the customer's own current location
    // (reverse-geocoded), not the kitchen's address and not a fake offset
    // from it. Only fills the field if the customer hasn't already typed
    // something themselves by the time it resolves.
    Future<void> resolveDefaultAddress(void Function(void Function()) setModalState) async {
      if (!hasCustomerLocation) return;
      final resolved = await GeocodingService.reverseGeocode(widget.customerLatitude!, widget.customerLongitude!);
      if (addressController.text.isEmpty || addressWasAutoFilled) {
        addressController.text = resolved;
        addressWasAutoFilled = true;
      }
      setModalState(() => isResolvingAddress = false);
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (isResolvingAddress && addressController.text.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                resolveDefaultAddress(setModalState);
              });
            }
            final scheme = Theme.of(context).colorScheme;
            final text = Theme.of(context).textTheme;
            final double price = item.price;
            final double total = price * quantity;

            return SafeArea(
              child: SingleChildScrollView(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.of(context).viewInsets.bottom,
                ),
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
                          decoration: BoxDecoration(
                            color: scheme.outline,
                            borderRadius: AppRadius.pillBr,
                          ),
                        ),
                      ),
                      PhotoCarousel(imageUrls: item.imageUrls, height: 180),
                      const SizedBox(height: AppSpacing.md),
                      Text(item.name, style: text.headlineSmall),
                      const SizedBox(height: 2),
                      Text(
                        item.description ?? 'A delicious selection.',
                        style: text.bodyMedium,
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      // Quantity stepper
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: AppRadius.mdBr,
                          border: Border.all(color: scheme.outline),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Quantity', style: text.titleMedium),
                            Row(
                              children: [
                                _StepperButton(
                                  icon: Icons.remove_rounded,
                                  onTap: quantity > 1 ? () => setModalState(() => quantity--) : null,
                                ),
                                SizedBox(
                                  width: 32,
                                  child: Text(
                                    '$quantity',
                                    textAlign: TextAlign.center,
                                    style: text.titleLarge,
                                  ),
                                ),
                                _StepperButton(
                                  icon: Icons.add_rounded,
                                  onTap: () => setModalState(() => quantity++),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      TextField(
                        controller: addressController,
                        minLines: 1,
                        maxLines: 2,
                        onChanged: (_) => addressWasAutoFilled = false,
                        decoration: InputDecoration(
                          labelText: 'Delivery Address',
                          hintText: isResolvingAddress ? 'Locating you…' : (hasCustomerLocation ? null : 'Enter your delivery address'),
                          prefixIcon: isResolvingAddress
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                                )
                              : const Icon(Icons.location_on_outlined),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),

                      // Order total + how payment works from here
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: AppRadius.mdBr,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('Order Total', style: text.titleMedium),
                                Text(
                                  formatCurrency(total),
                                  style: text.titleLarge?.copyWith(color: scheme.primary),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Row(
                              children: [
                                Icon(Icons.info_outline_rounded, size: 15, color: scheme.onSurfaceVariant),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    "You'll pay via bKash right after placing this order.",
                                    style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xl),

                      ElevatedButton(
                        onPressed: () async {
                          final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
                          // Delivery coordinates are the customer's own live
                          // position — falling back to the kitchen's location
                          // only if we genuinely never got the customer's (so
                          // the pin still lands somewhere sane on the map).
                          final orderId = await customerProvider.placeOrder(
                            kitchenId: widget.kitchen.id,
                            menuItemId: item.id,
                            quantity: quantity,
                            deliveryAddress: addressController.text.trim().isNotEmpty
                                ? addressController.text.trim()
                                : 'Delivery address not provided',
                            deliveryLatitude: widget.customerLatitude ?? widget.kitchen.latitude,
                            deliveryLongitude: widget.customerLongitude ?? widget.kitchen.longitude,
                          );

                          if (orderId != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Order placed! Open it from "My Orders" to send your bKash payment.'),
                              ),
                            );
                            Navigator.pop(context); // Close sheet
                            Navigator.pop(context); // Go back to Home / Order List
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(friendlyErrorMessage(customerProvider.errorMessage, fallback: 'Failed to place order. Please try again.')),
                              ),
                            );
                          }
                        },
                        child: Text('Confirm Order · ${formatCurrency(total)}'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customerProvider = context.watch<CustomerProvider>();
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 220,
            backgroundColor: scheme.surface,
            flexibleSpace: FlexibleSpaceBar(
              background: Hero(
                tag: 'kitchen-photo-${widget.kitchen.id}',
                child: NetworkFoodImage(
                  // Fall back to the owner's profile photo when the kitchen
                  // hasn't set its own cover photo yet, instead of a blank banner.
                  url: (widget.kitchen.imageUrl != null && widget.kitchen.imageUrl!.isNotEmpty) ? widget.kitchen.imageUrl : _ownerAvatarUrl,
                  width: double.infinity,
                  height: 220,
                  radius: BorderRadius.zero,
                  fallbackIcon: Icons.storefront_rounded,
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(widget.kitchen.name, style: text.displaySmall),
                  const SizedBox(height: 6),
                  Text(
                    widget.kitchen.description ?? 'A curated culinary experience.',
                    style: text.bodyMedium,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  LiveLocationText(
                    latitude: _ownerLat ?? widget.kitchen.latitude,
                    longitude: _ownerLng ?? widget.kitchen.longitude,
                    style: text.bodySmall,
                    icon: Icons.location_pin,
                    iconSize: 16,
                    iconColor: scheme.primary,
                  ),
                  if (_ownerName != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 14,
                          backgroundColor: scheme.primaryContainer,
                          backgroundImage: (_ownerAvatarUrl != null && _ownerAvatarUrl!.isNotEmpty)
                              ? CachedNetworkImageProvider(_ownerAvatarUrl!)
                              : null,
                          child: (_ownerAvatarUrl == null || _ownerAvatarUrl!.isEmpty)
                              ? Icon(Icons.person, size: 16, color: scheme.onPrimaryContainer)
                              : null,
                        ),
                        const SizedBox(width: 8),
                        Text('Owned by $_ownerName', style: text.bodySmall),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.sm),
                  InkWell(
                    borderRadius: AppRadius.mdBr,
                    onTap: () => Navigator.of(context).push(
                      appPageRoute(
                        ReviewsScreen(
                          title: '${widget.kitchen.name} Reviews',
                          avgRating: _avgRating,
                          reviewCount: _ratingCount,
                          loadReviews: () => Provider.of<KitchenProvider>(context, listen: false)
                              .getKitchenReviews(ownerId: widget.kitchen.ownerId),
                        ),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        children: [
                          Icon(Icons.star_rounded, size: 18, color: context.appColors.ratingStar),
                          const SizedBox(width: 4),
                          Text(
                            _avgRating > 0 ? _avgRating.toStringAsFixed(1) : 'No ratings yet',
                            style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          if (_ratingCount > 0) Text(' ($_ratingCount)', style: text.bodySmall),
                          const SizedBox(width: 4),
                          Icon(Icons.chevron_right_rounded, size: 16, color: scheme.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  const SectionHeader(title: 'Menu Offerings'),

                  if (customerProvider.isLoading)
                    Column(children: List.generate(3, (_) => const SkeletonCardRow()))
                  else if (customerProvider.currentMenu.isEmpty)
                    const EmptyState(
                      icon: Icons.menu_book_outlined,
                      title: 'No menu items available',
                      message: 'This kitchen has not published its menu yet.',
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: customerProvider.currentMenu.length,
                      itemBuilder: (context, index) {
                        final item = customerProvider.currentMenu[index];
                        return _MenuItemCard(
                          item: item,
                          onAdd: () => _showOrderSheet(item),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.pillBr,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled ? scheme.primaryContainer : scheme.outline.withValues(alpha: 0.2),
        ),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? scheme.onPrimaryContainer : scheme.onSurface.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

/// A considered menu item card: photo, name, short description, price and an
/// unmistakable Add affordance.
class _MenuItemCard extends StatelessWidget {
  final MenuItem item;
  final VoidCallback onAdd;
  const _MenuItemCard({required this.item, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 72,
              height: 72,
              child: PhotoCarousel(imageUrls: item.imageUrls, height: 72),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name, style: text.titleLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 4),
                  Text(
                    item.description ?? 'Prepared fresh on order.',
                    style: text.bodySmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        formatCurrency(item.price),
                        style: text.titleLarge?.copyWith(color: scheme.primary),
                      ),
                      FilledButton.icon(
                        onPressed: onAdd,
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Add'),
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
