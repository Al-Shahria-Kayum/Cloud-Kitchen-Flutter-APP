import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A gentle left-to-right shimmer sweep used for skeleton loading placeholders.
/// Wrap any bone shape (a colored Container/ClipRRect) with this instead of a
/// bare spinner so lists feel like they're "already there, just loading".
class AppShimmer extends StatefulWidget {
  final Widget child;
  const AppShimmer({super.key, required this.child});

  @override
  State<AppShimmer> createState() => _AppShimmerState();
}

class _AppShimmerState extends State<AppShimmer> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            final dx = bounds.width * 2;
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [colors.shimmerBase, colors.shimmerHighlight, colors.shimmerBase],
              stops: const [0.35, 0.5, 0.65],
              transform: _SweepGradientTransform(_controller.value * dx - bounds.width),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SweepGradientTransform extends GradientTransform {
  final double dx;
  const _SweepGradientTransform(this.dx);
  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, 0, 0);
}

/// A rounded placeholder "bone" for skeleton screens.
class SkeletonBone extends StatelessWidget {
  final double width;
  final double height;
  final BorderRadius? radius;
  const SkeletonBone({super.key, this.width = double.infinity, required this.height, this.radius});

  @override
  Widget build(BuildContext context) {
    return AppShimmer(
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: context.appColors.shimmerBase,
          borderRadius: radius ?? BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Skeleton stand-in for a restaurant/food card while data loads.
class SkeletonCardRow extends StatelessWidget {
  const SkeletonCardRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SkeletonBone(width: 72, height: 72, radius: BorderRadius.circular(16)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SkeletonBone(height: 16, width: 160),
                const SizedBox(height: 8),
                const SkeletonBone(height: 12, width: 220),
                const SizedBox(height: 8),
                SkeletonBone(height: 12, width: 90, radius: BorderRadius.circular(6)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
