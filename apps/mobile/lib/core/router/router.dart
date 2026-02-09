import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/homes_provider.dart';
import '../widgets/main_scaffold.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/welcome_screen.dart';
import '../../features/onboarding/home_setup_screen.dart';
import '../../features/onboarding/referral_handler_screen.dart';
import '../../features/home/dashboard_screen.dart';
import '../../features/items/items_screen.dart';
import '../../features/item_detail/item_detail_screen.dart';
import '../../features/add_item/add_item_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/profile_screen.dart';

/// Route path constants.
abstract class AppRoutes {
  static const splash = '/';
  static const welcome = '/welcome';
  static const homeSetup = '/home-setup';
  static const dashboard = '/dashboard';
  static const items = '/items';
  static const itemDetail = '/items/:id';
  static const addItem = '/add-item';
  static const settings = '/settings';
  static const profile = '/profile';
  static const referral = '/referral/:code';
}

/// Navigator keys for the shell route.
final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// GoRouter configuration with auth guards.
final routerProvider = Provider<GoRouter>((ref) {
  final isAuthenticated = ref.watch(isAuthenticatedProvider);
  final hasHome = ref.watch(hasHomeProvider);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: true,
    redirect: (context, state) {
      final location = state.matchedLocation;

      // Allow splash to load
      if (location == AppRoutes.splash) return null;

      // Allow referral deep links to pass through (handled by the screen)
      if (location.startsWith('/referral/')) return null;

      // Not authenticated → go to welcome
      if (!isAuthenticated) {
        if (location == AppRoutes.welcome) return null;
        return AppRoutes.welcome;
      }

      // Authenticated but no home → go to home setup
      if (!hasHome) {
        if (location == AppRoutes.homeSetup) return null;
        return AppRoutes.homeSetup;
      }

      // Authenticated with home, trying to visit welcome → go to dashboard
      if (location == AppRoutes.welcome) {
        return AppRoutes.dashboard;
      }

      return null; // No redirect needed
    },
    routes: [
      // Splash screen
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),

      // Welcome / onboarding
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),

      // Home setup (first-time flow)
      GoRoute(
        path: AppRoutes.homeSetup,
        builder: (context, state) => const HomeSetupScreen(),
      ),

      // Main app shell with bottom nav (Dashboard + Items tabs)
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScaffold(child: child),
        routes: [
          GoRoute(
            path: AppRoutes.dashboard,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: DashboardScreen(),
            ),
          ),
          GoRoute(
            path: AppRoutes.items,
            pageBuilder: (context, state) => const NoTransitionPage(
              child: ItemsScreen(),
            ),
          ),
        ],
      ),

      // Item detail (opens above the shell)
      GoRoute(
        path: AppRoutes.itemDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ItemDetailScreen(itemId: id);
        },
      ),

      // Add item (full-screen modal)
      GoRoute(
        path: AppRoutes.addItem,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: AddItemScreen(),
        ),
      ),

      // Settings
      GoRoute(
        path: AppRoutes.settings,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const SettingsScreen(),
      ),

      // Profile
      GoRoute(
        path: AppRoutes.profile,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ProfileScreen(),
      ),

      // Referral deep link handler
      GoRoute(
        path: AppRoutes.referral,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final code = state.pathParameters['code']!;
          return ReferralHandlerScreen(code: code);
        },
      ),
    ],
  );
});
