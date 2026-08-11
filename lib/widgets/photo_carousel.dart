import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import 'network_food_image.dart';

/// A swipeable gallery for a menu item's (or review's) photos — the "big
/// single photo" spot everywhere gets upgraded to this once there's more
/// than one, with dot indicators; falls back to the plain single-photo/
/// empty-state look of [NetworkFoodImage] when there's 0 or 1.
class PhotoCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final double height;
  final BorderRadius radius;
  final IconData fallbackIcon;

  const PhotoCarousel({
    super.key,
    required this.imageUrls,
    required this.height,
    this.radius = const BorderRadius.all(Radius.circular(AppRadius.md)),
    this.fallbackIcon = Icons.restaurant_rounded,
  });

  @override
  State<PhotoCarousel> createState() => _PhotoCarouselState();
}

class _PhotoCarouselState extends State<PhotoCarousel> {
  final PageController _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imageUrls.length <= 1) {
      return NetworkFoodImage(
        url: widget.imageUrls.isNotEmpty ? widget.imageUrls.first : null,
        width: double.infinity,
        height: widget.height,
        radius: widget.radius,
        fallbackIcon: widget.fallbackIcon,
        enableFullScreenTap: true,
      );
    }

    return ClipRRect(
      borderRadius: widget.radius,
      child: SizedBox(
        height: widget.height,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => NetworkFoodImage(
                url: widget.imageUrls[i],
                width: double.infinity,
                height: widget.height,
                radius: BorderRadius.zero,
                fallbackIcon: widget.fallbackIcon,
                enableFullScreenTap: true,
                galleryUrls: widget.imageUrls,
                galleryIndex: i,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(widget.imageUrls.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: AppMotion.fast,
                    margin: const EdgeInsets.symmetric(horizontal: 2),
                    width: active ? 8 : 6,
                    height: active ? 8 : 6,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                      boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 2)],
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
