import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// A section title with an optional trailing count/action — used to open
/// every list section (Kitchens near you, Incoming orders, Items ordered...)
/// with one consistent rhythm instead of ad-hoc bold Text widgets.
class SectionHeader extends StatelessWidget {
  final String title;
  final String? trailing;
  final VoidCallback? onTrailingTap;

  const SectionHeader({super.key, required this.title, this.trailing, this.onTrailingTap});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: text.headlineSmall),
          if (trailing != null)
            GestureDetector(
              onTap: onTrailingTap,
              child: Text(
                trailing!,
                style: text.labelMedium?.copyWith(color: Theme.of(context).colorScheme.primary),
              ),
            ),
        ],
      ),
    );
  }
}

/// Small initials avatar used in chat + wherever a person needs representing
/// without a photo (kept intentionally simple — no photo upload flow exists).
class InitialsAvatar extends StatelessWidget {
  final String name;
  final double size;
  final Color? background;
  const InitialsAvatar({super.key, required this.name, this.size = 36, this.background});

  String get _initials {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first.substring(0, 1) + parts.last.substring(0, 1)).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CircleAvatar(
      radius: size / 2,
      backgroundColor: background ?? scheme.secondary,
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: size * 0.38),
      ),
    );
  }
}
