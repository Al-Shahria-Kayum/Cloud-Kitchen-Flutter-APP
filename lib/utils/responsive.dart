/// Shared breakpoints for responsive layout decisions across the app.
/// Any screen or widget that needs to branch mobile/tablet/desktop layout
/// should read from here instead of hardcoding pixel widths ad hoc, so
/// breakpoint behavior stays consistent everywhere — this file is the one
/// place to tune it.
class Breakpoints {
  const Breakpoints._();

  /// Below this width: phone-style compact layout.
  static const double mobile = 600;

  /// Below this width (and >= [mobile]): tablet / narrow-desktop layout.
  static const double tablet = 1024;

  /// The maximum width app content should stretch to before being boxed
  /// and centered — prevents edge-to-edge sprawl on large desktop
  /// monitors and full-screen browser windows.
  static const double maxContentWidth = 1200;
}

enum ScreenSize { mobile, tablet, desktop }

/// Classifies [width] into a [ScreenSize] using [Breakpoints]. The
/// 600 / 1024 cutoffs match Material Design's own phone / tablet / desktop
/// breakpoint guidance rather than being picked arbitrarily.
ScreenSize screenSizeFor(double width) {
  if (width < Breakpoints.mobile) return ScreenSize.mobile;
  if (width < Breakpoints.tablet) return ScreenSize.tablet;
  return ScreenSize.desktop;
}
