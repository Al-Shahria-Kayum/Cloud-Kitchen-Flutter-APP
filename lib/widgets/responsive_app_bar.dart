import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../utils/responsive.dart';

/// One action shown in a [ResponsiveAppBar]. Renders as an inline
/// [IconButton] whenever there's room, and collapses into a single
/// overflow [PopupMenuButton] — with this as a labeled menu row — once
/// the bar gets too narrow to fit every action comfortably (phones, or a
/// desktop window/browser tab narrowed for screen-share).
class AppBarActionItem {
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  /// If true, this action always stays inline even in the collapsed
  /// mobile layout, instead of being swept into the overflow menu with
  /// the rest — use for something that should always stay one tap away
  /// (e.g. Log out).
  final bool alwaysInline;

  /// Optional widget shown instead of `Icon(icon)` in the inline slot
  /// (e.g. a small spinner while the action is busy). The overflow menu
  /// always shows the static [icon].
  final Widget? iconOverride;

  const AppBarActionItem({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.alwaysInline = false,
    this.iconOverride,
  });
}

/// A drop-in [AppBar] replacement that:
///  - keeps the title mathematically centered on every platform and
///    width. Material's own `centerTitle` default is inconsistent —
///    centered on iOS/macOS, left-aligned on Android/web/desktop — so
///    left at its default, the exact same screen reads centered on one
///    platform and off-centre on another. This always centers it the
///    same way, everywhere.
///  - boxes and centers its content at [maxContentWidth] so it doesn't
///    stretch edge-to-edge on very wide desktop / full-screen / ultra-wide
///    windows — the header reads as a contained bar instead of a lone
///    title on the left and a faraway cluster of icons on the right.
///  - collapses [actions] into a single overflow menu below
///    [Breakpoints.mobile] once there are more than two, so it never
///    overflows on narrow phone widths, while still showing every action
///    as a full icon row once there's room.
///
/// Uses [LayoutBuilder] — the bar's own available width — rather than
/// [MediaQuery] alone, since that's the width that actually constrains
/// this widget, it re-measures automatically on every resize (desktop
/// window drag, browser resize/screen-share, orientation change), and it
/// stays correct even if this is ever nested inside something narrower
/// than the full window.
class ResponsiveAppBar extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final List<AppBarActionItem> actions;

  /// Optional custom leading widget. If null, falls back to a normal back
  /// button whenever there's a route to pop — matching stock [AppBar]
  /// behavior — or an empty spacer at the root route.
  final Widget? leading;

  /// Optional gradient background (used by the kitchen-branded screens).
  final Gradient? backgroundGradient;

  /// Solid background color. Ignored if [backgroundGradient] is set;
  /// falls back to the theme's AppBar color if neither is given.
  final Color? backgroundColor;

  /// Icon/title color. Defaults to the theme's onSurface color, or white
  /// automatically when [backgroundGradient] is supplied.
  final Color? foregroundColor;

  /// Optional bottom widget (e.g. a typing-indicator strip), same as
  /// [AppBar.bottom].
  final PreferredSizeWidget? bottom;

  /// Content max width before boxing + centering kicks in. Defaults to
  /// [Breakpoints.maxContentWidth]; override per-screen if a bar needs a
  /// different reading width.
  final double maxContentWidth;

  const ResponsiveAppBar({
    super.key,
    required this.title,
    this.actions = const [],
    this.leading,
    this.backgroundGradient,
    this.backgroundColor,
    this.foregroundColor,
    this.bottom,
    this.maxContentWidth = Breakpoints.maxContentWidth,
  });

  @override
  Size get preferredSize =>
      Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final resolvedForeground =
        foregroundColor ??
        (backgroundGradient != null ? Colors.white : scheme.onSurface);
    final canPop = Navigator.of(context).canPop();

    return AppBar(
      automaticallyImplyLeading: false,
      centerTitle: false, // we do our own centering below
      titleSpacing: 0,
      elevation: 0,
      backgroundColor: backgroundGradient != null
          ? Colors.transparent
          : backgroundColor,
      foregroundColor: resolvedForeground,
      iconTheme: IconThemeData(color: resolvedForeground),
      flexibleSpace: backgroundGradient != null
          ? Container(decoration: BoxDecoration(gradient: backgroundGradient))
          : null,
      bottom: bottom,
      title: LayoutBuilder(
        builder: (context, constraints) {
          final size = screenSizeFor(constraints.maxWidth);
          final isMobile = size == ScreenSize.mobile;

          return Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxContentWidth),
              child: SizedBox(
                height: kToolbarHeight,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Title — truly centered relative to the (boxed) bar,
                    // independent of how wide leading/actions end up
                    // being. The horizontal inset below is a deliberately
                    // generous approximation of the leading/actions
                    // cluster width, not a precise measurement — if a
                    // screen ever pairs an unusually wide actions row
                    // with a very long title, the title simply ellipsizes
                    // a little earlier than the theoretical minimum; the
                    // icons stay fully tappable regardless, since they're
                    // painted on top (see the Stack ordering below).
                    Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 96 : 160,
                      ),
                      child: Semantics(
                        header: true,
                        child: Text(
                          title,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(color: resolvedForeground),
                        ),
                      ),
                    ),
                    // Leading (left) + actions (right), painted on top so
                    // they always stay tappable even if the centered
                    // title's box were ever wide enough to reach under
                    // them. Stack hit-tests in reverse paint order, so
                    // this Row — the last child — wins taps over the
                    // Text underneath it.
                    Row(
                      children: [
                        leading ??
                            (canPop
                                ? BackButton(color: resolvedForeground)
                                : const SizedBox(width: 4)),
                        const Spacer(),
                        _ActionsRow(
                          actions: actions,
                          isMobile: isMobile,
                          foregroundColor: resolvedForeground,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Renders [actions] inline whenever there's room (tablet/desktop, or
/// mobile with two or fewer actions), or collapses everything except
/// [AppBarActionItem.alwaysInline] items into one overflow menu on
/// narrow mobile widths.
class _ActionsRow extends StatelessWidget {
  final List<AppBarActionItem> actions;
  final bool isMobile;
  final Color foregroundColor;

  const _ActionsRow({
    required this.actions,
    required this.isMobile,
    required this.foregroundColor,
  });

  @override
  Widget build(BuildContext context) {
    if (actions.isEmpty) return const SizedBox(width: 4);

    // Plenty of room (tablet/desktop), or few enough actions to just
    // fit — show every action as its own icon button, no overflow needed.
    final showAllInline = !isMobile || actions.length <= 2;
    if (showAllInline) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: actions
            .map(
              (a) => IconButton(
                icon: a.iconOverride ?? Icon(a.icon),
                tooltip: a.label,
                color: foregroundColor,
                onPressed: a.onPressed,
              ),
            )
            .toList(),
      );
    }

    // Narrow phone width with more than two actions: pin the
    // always-inline ones, sweep the rest into a single "more" menu.
    final pinned = actions.where((a) => a.alwaysInline).toList();
    final collapsible = actions.where((a) => !a.alwaysInline).toList();

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...pinned.map(
          (a) => IconButton(
            icon: a.iconOverride ?? Icon(a.icon),
            tooltip: a.label,
            color: foregroundColor,
            onPressed: a.onPressed,
          ),
        ),
        if (collapsible.isNotEmpty)
          PopupMenuButton<int>(
            icon: Icon(Icons.more_vert_rounded, color: foregroundColor),
            tooltip: 'More',
            itemBuilder: (context) => List.generate(collapsible.length, (i) {
              final a = collapsible[i];
              return PopupMenuItem<int>(
                value: i,
                enabled: a.onPressed != null,
                child: Row(
                  children: [
                    Icon(a.icon, size: 20),
                    const SizedBox(width: AppSpacing.md),
                    Text(a.label),
                  ],
                ),
              );
            }),
            onSelected: (i) => collapsible[i].onPressed?.call(),
          ),
      ],
    );
  }
}
