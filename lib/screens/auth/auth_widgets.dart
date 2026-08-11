import 'package:flutter/material.dart';
import '../../theme/app_theme.dart';
import '../../widgets/app_logo.dart';

/// Shared visual language for the Login and Signup screens: a warm,
/// typographic hero (no dark gradient, no oversized stock icon), a tactile
/// press effect for primary actions, and the role-selector cards used on
/// signup. Kept local to lib/screens/auth since nothing else needs them.

/// A considered backdrop for the auth screens — two soft, oversized glow
/// blobs in the brand palette on a warm wash, so the form reads as sitting
/// in front of something rather than floating on flat white. Meant to be
/// the first (bottommost) child of a Stack behind the scrollable content.
class AuthBackdrop extends StatelessWidget {
  const AuthBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDark
                ? [scheme.surface, Theme.of(context).scaffoldBackgroundColor]
                : [const Color(0xFFFFF7EE), Theme.of(context).scaffoldBackgroundColor],
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: -140,
              right: -110,
              child: _Glow(color: scheme.primary, size: 340, opacity: isDark ? 0.20 : 0.16),
            ),
            Positioned(
              bottom: -160,
              left: -130,
              child: _Glow(color: scheme.secondary, size: 380, opacity: isDark ? 0.28 : 0.10),
            ),
          ],
        ),
      ),
    );
  }
}

class _Glow extends StatelessWidget {
  final Color color;
  final double size;
  final double opacity;
  const _Glow({required this.color, required this.size, required this.opacity});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ),
      ),
    );
  }
}

/// Wordmark + headline used to open both auth screens.
class AuthHero extends StatelessWidget {
  final String title;
  final String subtitle;
  const AuthHero({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AppLogoLockup(markSize: 34),
        const SizedBox(height: AppSpacing.xl),
        Text(title, style: text.displayLarge),
        const SizedBox(height: AppSpacing.xs),
        Text(subtitle, style: text.bodyLarge),
      ],
    );
  }
}

/// Wraps a button-like child with a subtle press-down scale. Uses a
/// [Listener] (raw pointer events) rather than a [GestureDetector] so it
/// never competes with the child's own tap recognizer.
class PressableScale extends StatefulWidget {
  final Widget child;
  const PressableScale({super.key, required this.child});

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  double _scale = 1;

  void _set(double v) {
    if (mounted) setState(() => _scale = v);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => _set(0.97),
      onPointerUp: (_) => _set(1),
      onPointerCancel: (_) => _set(1),
      child: AnimatedScale(
        scale: _scale,
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        child: widget.child,
      ),
    );
  }
}

/// One selectable role in [RoleSelector].
class RoleOption {
  final String value;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  const RoleOption({
    required this.value,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
  });
}

/// A row of selectable role cards (icon + label + short description) used in
/// place of a generic dropdown — this is the most consequential choice a new
/// user makes, so it gets real visual weight.
class RoleSelector extends StatelessWidget {
  final List<RoleOption> options;
  final String value;
  final ValueChanged<String> onChanged;

  const RoleSelector({super.key, required this.options, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('I am a...', style: text.titleSmall),
        const SizedBox(height: AppSpacing.sm),
        for (final option in options)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: _RoleCard(
              option: option,
              selected: option.value == value,
              scheme: scheme,
              text: text,
              onTap: () => onChanged(option.value),
            ),
          ),
      ],
    );
  }
}

class _RoleCard extends StatelessWidget {
  final RoleOption option;
  final bool selected;
  final ColorScheme scheme;
  final TextTheme text;
  final VoidCallback onTap;

  const _RoleCard({
    required this.option,
    required this.selected,
    required this.scheme,
    required this.text,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: AppMotion.fast,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: selected ? option.color.withValues(alpha: 0.08) : scheme.surface,
        borderRadius: AppRadius.mdBr,
        border: Border.all(color: selected ? option.color : scheme.outline, width: selected ? 1.6 : 1),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: AppRadius.mdBr,
        child: InkWell(
          borderRadius: AppRadius.mdBr,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: option.color.withValues(alpha: 0.15), shape: BoxShape.circle),
                  child: Icon(option.icon, color: option.color, size: 20),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(option.label, style: text.titleMedium),
                      Text(option.description, style: text.bodySmall),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? option.color : scheme.outline,
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
