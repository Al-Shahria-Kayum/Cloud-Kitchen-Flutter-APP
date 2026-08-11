import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shared page transition: a soft fade + gentle upward slide, used everywhere
/// instead of the platform-default MaterialPageRoute so navigation reads as
/// one considered motion system rather than default push/pop.
Route<T> appPageRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    transitionDuration: AppMotion.base,
    reverseTransitionDuration: AppMotion.fast,
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(parent: animation, curve: AppMotion.curve);
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(curved),
          child: child,
        ),
      );
    },
  );
}
