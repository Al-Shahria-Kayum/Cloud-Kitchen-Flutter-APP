import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/profile.dart';
import '../../providers/auth_provider.dart';
import '../customer/customer_home_screen.dart';
import '../kitchen/kitchen_home_screen.dart';
import '../rider/rider_home_screen.dart';
import 'login_screen.dart';
import 'splash_screen.dart';

/// Routes to the correct screen based on the live auth restoration state,
/// so a refresh/cold-start with a valid persisted session never bounces
/// the user back to the login screen.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, AuthStatus>(
      selector: (_, auth) => auth.status,
      builder: (context, status, _) {
        switch (status) {
          case AuthStatus.uninitialized:
            return const SplashScreen();
          case AuthStatus.unauthenticated:
            return const LoginScreen();
          case AuthStatus.authenticated:
            return const RoleRouter();
        }
      },
    );
  }
}

/// Reactively routes an authenticated user to their role's home screen.
/// Shows the splash while the profile row (fetched async) hasn't arrived yet,
/// instead of falling back to the login screen.
class RoleRouter extends StatelessWidget {
  const RoleRouter({super.key});

  @override
  Widget build(BuildContext context) {
    return Selector<AuthProvider, Profile?>(
      selector: (_, auth) => auth.profile,
      builder: (context, profile, _) {
        if (profile == null) {
          return const SplashScreen();
        }
        switch (profile.role) {
          case 'kitchen_owner':
            return const KitchenHomeScreen();
          case 'rider':
            return const RiderHomeScreen();
          case 'customer':
          default:
            return const CustomerHomeScreen();
        }
      },
    );
  }
}
