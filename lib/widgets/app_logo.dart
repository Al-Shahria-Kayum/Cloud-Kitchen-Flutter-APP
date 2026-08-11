import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// The Cloud Kitchen mark: a two-tone flame (cooking) with a small orbiting
/// dot at its tip (motion/delivery) — drawn as a vector shape so it stays
/// crisp at any size, from a 28px auth badge up to a splash-screen hero.
/// This replaces the old plain "CK" text mark everywhere in the app.
class AppLogoMark extends StatelessWidget {
  final double size;
  final bool onDark;

  const AppLogoMark({super.key, this.size = 40, this.onDark = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _LogoPainter(
          base: scheme.primary,
          tip: onDark ? const Color(0xFFFFC898) : const Color(0xFFFF9752),
          inner: onDark ? scheme.surface : const Color(0xFFFFF6EC),
          dot: scheme.secondary,
        ),
      ),
    );
  }
}

/// The full lockup: mark + wordmark, used on auth screens / splash.
class AppLogoLockup extends StatelessWidget {
  final double markSize;
  final Color? wordmarkColor;
  const AppLogoLockup({super.key, this.markSize = 34, this.wordmarkColor});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppLogoMark(size: markSize),
        const SizedBox(width: AppSpacing.sm),
        Text(
          'CLOUD KITCHEN',
          style: text.labelMedium?.copyWith(color: wordmarkColor ?? scheme.primary, letterSpacing: 1.6),
        ),
      ],
    );
  }
}

class _LogoPainter extends CustomPainter {
  final Color base;
  final Color tip;
  final Color inner;
  final Color dot;

  _LogoPainter({required this.base, required this.tip, required this.inner, required this.dot});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 100;
    canvas.save();
    canvas.scale(s, s);

    // Outer flame — an asymmetric two-tipped silhouette (cooking).
    final flame = Path()
      ..moveTo(50, 93)
      ..cubicTo(24, 88, 10, 70, 13, 54)
      ..cubicTo(15, 43, 24, 36, 27, 24)
      ..cubicTo(29, 34, 36, 40, 40, 36)
      ..cubicTo(35, 22, 40, 8, 55, 2)
      ..cubicTo(50, 16, 58, 20, 63, 28)
      ..cubicTo(66, 20, 65, 12, 62, 4)
      ..cubicTo(78, 12, 90, 28, 88, 46)
      ..cubicTo(87, 40, 82, 36, 78, 34)
      ..cubicTo(82, 46, 88, 58, 84, 70)
      ..cubicTo(80, 82, 66, 90, 50, 93)
      ..close();

    final flamePaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomCenter,
        end: Alignment.topCenter,
        colors: [base, tip],
      ).createShader(const Rect.fromLTWH(0, 0, 100, 100));
    canvas.drawPath(flame, flamePaint);

    // Inner counter-flame — gives the mark depth and a distinct silhouette
    // versus a flat generic flame icon.
    final inner1 = Path()
      ..moveTo(50, 82)
      ..cubicTo(36, 76, 30, 63, 34, 52)
      ..cubicTo(38, 44, 46, 40, 48, 32)
      ..cubicTo(56, 38, 62, 48, 60, 58)
      ..cubicTo(64, 54, 66, 48, 65, 42)
      ..cubicTo(72, 50, 74, 62, 68, 72)
      ..cubicTo(63, 80, 56, 82, 50, 82)
      ..close();
    canvas.drawPath(inner1, Paint()..color = inner);

    // Delivery/motion accent: a small dot orbiting near the flame's tip.
    canvas.drawCircle(const Offset(83, 22), 6.5, Paint()..color = dot);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _LogoPainter oldDelegate) {
    return oldDelegate.base != base || oldDelegate.tip != tip || oldDelegate.inner != inner || oldDelegate.dot != dot;
  }
}
