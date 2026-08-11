import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom photo viewer opened by tapping a thumbnail.
/// Supports either a single photo ([show]) or a swipeable gallery starting
/// at a given photo ([showGallery]).
///
/// No Hero transition: menu-item thumbnails commonly reuse the same
/// seed/placeholder image URL, which caused Hero-tag collisions (Flutter
/// requires at most one Hero per tag per route), freezing the transition.
/// A plain fade is collision-proof.
class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const FullScreenImageViewer(
      {super.key, required this.imageUrls, this.initialIndex = 0});

  static void show(BuildContext context, String imageUrl) {
    showGallery(context, [imageUrl]);
  }

  static void showGallery(BuildContext context, List<String> imageUrls,
      {int initialIndex = 0}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black,
        pageBuilder: (context, animation, secondaryAnimation) =>
            FadeTransition(
          opacity: animation,
          child: FullScreenImageViewer(
              imageUrls: imageUrls, initialIndex: initialIndex),
        ),
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _controller =
      PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.imageUrls.length > 1;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Page view fills the entire screen. Each page is a constrained
          // box that gives InteractiveViewer a definite size to work with —
          // without explicit width/height Flutter Web collapses the viewer
          // to the image's intrinsic (tiny) size, showing a black screen.
          PageView.builder(
            controller: _controller,
            itemCount: widget.imageUrls.length,
            onPageChanged: (i) => setState(() => _page = i),
            itemBuilder: (context, i) {
              return SizedBox(
                width: size.width,
                height: size.height,
                child: GestureDetector(
                  onTap: () => Navigator.of(context).pop(),
                  child: InteractiveViewer(
                    minScale: 0.5,
                    maxScale: 5,
                    child: SizedBox(
                      width: size.width,
                      height: size.height,
                      child: _image(widget.imageUrls[i], size),
                    ),
                  ),
                ),
              );
            },
          ),

          // Close button + page counter
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  if (multiple) ...[
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_page + 1} / ${widget.imageUrls.length}',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    // Spacer to balance the close button on the left
                    const SizedBox(width: 44),
                  ],
                ],
              ),
            ),
          ),

          // Dot indicators at the bottom (only for galleries)
          if (multiple)
            Positioned(
              bottom: 24,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) {
                  final active = i == _page;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: active ? 9 : 7,
                    height: active ? 9 : 7,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image(String url, Size size) {
    return CachedNetworkImage(
      imageUrl: url,
      // fit: fill within the explicit SizedBox so the image actually covers
      // the screen, then InteractiveViewer lets the user zoom/pan it.
      fit: BoxFit.contain,
      width: size.width,
      height: size.height,
      placeholder: (ctx, u) => const Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorWidget: (ctx, u, e) => const Center(
        child: Icon(Icons.broken_image_outlined,
            color: Colors.white54, size: 64),
      ),
    );
  }
}
