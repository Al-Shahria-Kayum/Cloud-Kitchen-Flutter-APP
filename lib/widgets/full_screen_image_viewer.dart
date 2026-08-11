import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom photo viewer opened by tapping a thumbnail.
/// Supports either a single photo ([show]) or a swipeable gallery starting
/// at a given photo ([showGallery]) — the latter is what lets a menu item's
/// multi-photo carousel actually be browsed once opened full-screen, instead
/// of always landing on just the one photo that was tapped.
///
/// Deliberately no Hero flight in/out of this viewer: menu-item thumbnails
/// commonly reuse the same seed/placeholder image URL across several cards,
/// and Hero tags derived from that URL then collide (Flutter requires at
/// most one Hero per tag within a route), which froze the transition on a
/// small thumbnail instead of opening the viewer. A plain fade is simpler
/// and can't collide.
class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const FullScreenImageViewer({super.key, required this.imageUrls, this.initialIndex = 0});

  static void show(BuildContext context, String imageUrl) {
    showGallery(context, [imageUrl]);
  }

  static void showGallery(BuildContext context, List<String> imageUrls, {int initialIndex = 0}) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: FullScreenImageViewer(imageUrls: imageUrls, initialIndex: initialIndex),
        ),
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _controller = PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.imageUrls.length > 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.imageUrls.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, i) => GestureDetector(
                onTap: () => Navigator.of(context).pop(),
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(child: _image(i)),
                ),
              ),
            ),
          ),
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
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${_page + 1} / ${widget.imageUrls.length}',
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 44),
                  ],
                ],
              ),
            ),
          ),
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
                      color: active ? Colors.white : Colors.white.withValues(alpha: 0.5),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }

  Widget _image(int index) {
    return CachedNetworkImage(
      imageUrl: widget.imageUrls[index],
      fit: BoxFit.contain,
      placeholder: (ctx, u) => const Padding(
        padding: EdgeInsets.all(48.0),
        child: CircularProgressIndicator(color: Colors.white),
      ),
      errorWidget: (ctx, u, e) => const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64),
    );
  }
}
