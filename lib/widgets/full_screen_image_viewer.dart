import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Full-screen, pinch-to-zoom photo viewer with smooth page transitions.
/// Arrow buttons + tappable dot indicators handle navigation (swipe is
/// unreliable on Flutter Web when InteractiveViewer is present).
class FullScreenImageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const FullScreenImageViewer({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
  });

  static void show(BuildContext context, String imageUrl) {
    showGallery(context, [imageUrl]);
  }

  static void showGallery(
    BuildContext context,
    List<String> imageUrls, {
    int initialIndex = 0,
  }) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 220),
        reverseTransitionDuration: const Duration(milliseconds: 180),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullScreenImageViewer(
              imageUrls: imageUrls,
              initialIndex: initialIndex,
            ),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late int _page = widget.initialIndex;

  // Animated values drive the cross-fade between pages.
  // We keep the "leaving" image visible while the "entering" one fades in,
  // giving a smooth dissolve instead of a hard cut or a laggy slide.
  String? _leavingUrl;
  String get _currentUrl => widget.imageUrls[_page];
  bool _transitioning = false;

  Future<void> _goTo(int index) async {
    if (index < 0 || index >= widget.imageUrls.length || _transitioning) return;

    setState(() {
      _leavingUrl = _currentUrl;
      _transitioning = true;
    });

    // Short settle before we flip — lets the arrow press feel acknowledged.
    await Future.delayed(const Duration(milliseconds: 30));
    if (!mounted) return;

    setState(() {
      _page = index;
    });

    // Hold the cross-fade duration, then clear the ghost.
    await Future.delayed(const Duration(milliseconds: 320));
    if (!mounted) return;
    setState(() {
      _leavingUrl = null;
      _transitioning = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final multiple = widget.imageUrls.length > 1;
    final hasPrev = _page > 0;
    final hasNext = _page < widget.imageUrls.length - 1;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // ── Leaving ghost (stays put while new image fades over it) ──────
          if (_leavingUrl != null)
            Positioned.fill(
              child: _PhotoFrame(url: _leavingUrl!, opacity: 1.0),
            ),

          // ── Incoming image — fades in over the ghost ─────────────────────
          Positioned.fill(
            child: _AnimatedPhotoFrame(key: ValueKey(_page), url: _currentUrl),
          ),

          // ── Left arrow ───────────────────────────────────────────────────
          if (multiple)
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: hasPrev ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _NavArrow(
                    icon: Icons.chevron_left_rounded,
                    onTap: hasPrev && !_transitioning
                        ? () => _goTo(_page - 1)
                        : null,
                  ),
                ),
              ),
            ),

          // ── Right arrow ──────────────────────────────────────────────────
          if (multiple)
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: hasNext ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _NavArrow(
                    icon: Icons.chevron_right_rounded,
                    onTap: hasNext && !_transitioning
                        ? () => _goTo(_page + 1)
                        : null,
                  ),
                ),
              ),
            ),

          // ── Top bar: close + "X / N" ──────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white,
                        size: 28,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                  if (multiple) ...[
                    const Spacer(),
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        child: Container(
                          key: ValueKey(_page),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '${_page + 1} / ${widget.imageUrls.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const Spacer(),
                    const SizedBox(width: 48),
                  ],
                ],
              ),
            ),
          ),

          // ── Tappable pill dot indicators ──────────────────────────────────
          if (multiple)
            Positioned(
              bottom: 20,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.imageUrls.length, (i) {
                  final active = i == _page;
                  return GestureDetector(
                    onTap: _transitioning ? null : () => _goTo(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeOutCubic,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

/// Statically renders one image at a fixed opacity (used for the leaving ghost).
class _PhotoFrame extends StatelessWidget {
  final String url;
  final double opacity;
  const _PhotoFrame({required this.url, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(child: _buildImage(context, url)),
      ),
    );
  }

  Widget _buildImage(BuildContext context, String u) {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final w = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.of(ctx).size.width;
        final h = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : MediaQuery.of(ctx).size.height;
        return CachedNetworkImage(
          imageUrl: u,
          fit: BoxFit.contain,
          width: w,
          height: h,
          placeholder: (_, __) => const Center(
            child: CircularProgressIndicator(color: Colors.white),
          ),
          errorWidget: (_, __, ___) => const Center(
            child: Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          ),
        );
      },
    );
  }
}

/// Fades in from transparent to fully opaque when first mounted.
/// The [key] (set to ValueKey(_page)) forces a fresh widget each navigation,
/// restarting the fade-in animation every time.
class _AnimatedPhotoFrame extends StatefulWidget {
  final String url;
  const _AnimatedPhotoFrame({super.key, required this.url});

  @override
  State<_AnimatedPhotoFrame> createState() => _AnimatedPhotoFrameState();
}

class _AnimatedPhotoFrameState extends State<_AnimatedPhotoFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
  );
  late final Animation<double> _opacity = CurvedAnimation(
    parent: _ctrl,
    curve: Curves.easeOut,
  );

  @override
  void initState() {
    super.initState();
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: InteractiveViewer(
        minScale: 0.5,
        maxScale: 5,
        child: Center(
          child: LayoutBuilder(
            builder: (ctx, constraints) {
              final w = constraints.maxWidth.isFinite
                  ? constraints.maxWidth
                  : MediaQuery.of(ctx).size.width;
              final h = constraints.maxHeight.isFinite
                  ? constraints.maxHeight
                  : MediaQuery.of(ctx).size.height;
              return CachedNetworkImage(
                imageUrl: widget.url,
                fit: BoxFit.contain,
                width: w,
                height: h,
                placeholder: (_, __) => const Center(
                  child: CircularProgressIndicator(color: Colors.white),
                ),
                errorWidget: (_, __, ___) => const Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 64,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Translucent circular arrow button.
class _NavArrow extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _NavArrow({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: onTap != null
              ? Colors.black.withValues(alpha: 0.50)
              : Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1,
          ),
        ),
        child: Icon(
          icon,
          color: onTap != null
              ? Colors.white
              : Colors.white.withValues(alpha: 0.0),
          size: 30,
        ),
      ),
    );
  }
}
