import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'app_shimmer.dart';
import 'full_screen_image_viewer.dart';

/// The one place food/kitchen photos are rendered. Handles the loading
/// shimmer and the broken/missing-image fallback consistently everywhere
/// (menu cards, kitchen banners, chat image messages).
class NetworkFoodImage extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final BorderRadius radius;
  final IconData fallbackIcon;

  /// When true and [url] is set, tapping the thumbnail opens it full-screen
  /// with pinch-to-zoom, so the photo can be seen clearly instead of only as
  /// a small cropped thumbnail.
  final bool enableFullScreenTap;

  /// When this thumbnail is one photo in a larger set (e.g. a menu item's
  /// multi-photo carousel), pass the full list here so the full-screen
  /// viewer opens as a swipeable gallery starting at [galleryIndex] instead
  /// of being stuck on just this one photo with no way to see the rest.
  final List<String>? galleryUrls;
  final int galleryIndex;

  const NetworkFoodImage({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.fallbackIcon = Icons.restaurant_rounded,
    this.enableFullScreenTap = false,
    this.galleryUrls,
    this.galleryIndex = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    Widget fallback() => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: radius),
          child: Icon(fallbackIcon, color: scheme.onPrimaryContainer, size: (width < 56 ? 20 : 28)),
        );

    if (url == null || url!.isEmpty) {
      return ClipRRect(borderRadius: radius, child: fallback());
    }

    Widget cachedImage() => CachedNetworkImage(
          imageUrl: url!,
          width: width,
          height: height,
          fit: BoxFit.cover,
          fadeInDuration: AppMotion.base,
          placeholder: (ctx, u) => SkeletonBone(width: width, height: height, radius: radius),
          errorWidget: (ctx, u, e) => fallback(),
        );

    if (!enableFullScreenTap) {
      return ClipRRect(borderRadius: radius, child: cachedImage());
    }

    final gallery = galleryUrls;
    return GestureDetector(
      onTap: () => gallery != null && gallery.length > 1
          ? FullScreenImageViewer.showGallery(context, gallery, initialIndex: galleryIndex)
          : FullScreenImageViewer.show(context, url!),
      child: ClipRRect(borderRadius: radius, child: cachedImage()),
    );
  }
}
