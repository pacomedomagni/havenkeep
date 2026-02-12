import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';

import '../providers/auth_provider.dart';
import '../providers/homes_provider.dart';
import '../providers/demo_mode_provider.dart';
import '../widgets/main_scaffold.dart';
import '../../features/onboarding/splash_screen.dart';
import '../../features/onboarding/preview_screen.dart';
import '../../features/onboarding/demo_dashboard_wrapper.dart';
import '../../features/onboarding/welcome_screen.dart';
import '../../features/onboarding/home_setup_screen.dart';
import '../../features/onboarding/first_action_screen.dart';
import '../../features/onboarding/bulk_add/room_setup_screen.dart';
import '../../features/onboarding/bulk_add/bulk_add_complete_screen.dart';
import '../../features/onboarding/referral_handler_screen.dart';
import '../../features/home/dashboard_screen.dart';
import '../../features/items/items_screen.dart';
import '../../features/item_detail/item_detail_screen.dart';
import '../../features/item_detail/edit_item_screen.dart';
import '../../features/item_detail/share_claim_sheet.dart';
import '../../features/add_item/add_item_screen.dart';
import '../../features/add_item/quick_add_screen.dart';
import '../../features/add_item/manual_entry_screen.dart';
import '../../features/add_item/item_added_screen.dart';
import '../../features/add_item/receipt_scan_screen.dart';
import '../../features/add_item/barcode_scan_screen.dart';
import '../../features/item_detail/pdf_preview_screen.dart';
import '../../features/premium/premium_screen.dart';
import '../../features/premium/premium_success_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/settings/profile_screen.dart';
import '../../features/settings/notification_preferences_screen.dart';
import '../../features/settings/home_detail_screen.dart';
import '../../features/settings/archived_items_screen.dart';
import '../../features/settings/change_password_screen.dart';
import '../../features/settings/delete_account_screen.dart';
import '../../features/notifications/notifications_screen.dart';

/// Route path constants.
abstract class AppRoutes {
  static const splash = '/';
  static const preview = '/preview';
  static const demo = '/demo';
  static const welcome = '/welcome';
  static const firstAction = '/first-action';
  static const homeSetup = '/home-setup';
  static const roomSetup = '/home-setup/rooms';
  static const bulkAddComplete = '/home-setup/complete';
  static const dashboard = '/dashboard';
  static const items = '/items';
  static const itemDetail = '/items/:id';
  static const editItem = '/items/:id/edit';
  static const addItem = '/add-item';
  static const quickAdd = '/add-item/quick/:category';
  static const manualEntry = '/add-item/manual';
  static const addItemSuccess = '/add-item/success/:id';
  static const settings = '/settings';
  static const profile = '/profile';
  static const notifications = '/notifications';
  static const notificationPreferences = '/settings/notifications';
  static const homeDetail = '/settings/home/:id';
  static const archivedItems = '/settings/archived';
  static const changePassword = '/settings/change-password';
  static const deleteAccount = '/settings/delete-account';
  static const scanReceipt = '/add-item/scan-receipt';
  static const scanBarcode = '/add-item/scan-barcode';
  static const pdfPreview = '/items/:id/pdf';
  static const premium = '/premium';
  static const premiumSuccess = '/premium/success';
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

      // Authenticated but no home → allow first-action, home-setup, and
      // room-setup flows; redirect everything else to first-action
      if (!hasHome) {
        const allowedPaths = [
          AppRoutes.firstAction,
          AppRoutes.homeSetup,
        ];
        // Allow first-action, home-setup, and any sub-paths of home-setup
        if (allowedPaths.contains(location) ||
            location.startsWith('/home-setup/')) {
          return null;
        }
        return AppRoutes.firstAction;
      }

      // Authenticated with home, trying to visit welcome/first-action → go to dashboard
      if (location == AppRoutes.welcome ||
          location == AppRoutes.firstAction) {
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

      // Preview screens (shown before auth)
      GoRoute(
        path: AppRoutes.preview,
        builder: (context, state) => PreviewScreen(
          onGetStarted: () => context.go(AppRoutes.welcome),
          onTryDemo: () {
            final container = ProviderScope.containerOf(context);
            container.read(demoModeProvider.notifier).enterDemoMode();
            context.go(AppRoutes.demo);
          },
        ),
      ),

      // Demo mode dashboard
      GoRoute(
        path: AppRoutes.demo,
        builder: (context, state) => DemoDashboardWrapper(
          onExitDemo: () => context.go(AppRoutes.welcome),
        ),
      ),

      // Welcome / onboarding
      GoRoute(
        path: AppRoutes.welcome,
        builder: (context, state) => const WelcomeScreen(),
      ),

      // First action — choose onboarding path after auth
      GoRoute(
        path: AppRoutes.firstAction,
        builder: (context, state) => const FirstActionScreen(),
      ),

      // Home setup (first-time flow)
      GoRoute(
        path: AppRoutes.homeSetup,
        builder: (context, state) => const HomeSetupScreen(),
      ),

      // Room setup — bulk-add walkthrough
      GoRoute(
        path: AppRoutes.roomSetup,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const RoomSetupScreen(),
      ),

      // Bulk-add complete
      GoRoute(
        path: AppRoutes.bulkAddComplete,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const BulkAddCompleteScreen(),
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

      // Edit item
      GoRoute(
        path: AppRoutes.editItem,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return EditItemScreen(itemId: id);
        },
      ),

      // Add item (full-screen modal — method selection)
      GoRoute(
        path: AppRoutes.addItem,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: AddItemScreen(),
        ),
      ),

      // Quick-add for a specific category
      GoRoute(
        path: AppRoutes.quickAdd,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final categoryName = state.pathParameters['category']!;
          final category = ItemCategory.values.firstWhere(
            (c) => c.name == categoryName,
            orElse: () => ItemCategory.other,
          );
          return MaterialPage(
            fullscreenDialog: true,
            child: QuickAddScreen(category: category),
          );
        },
      ),

      // Full manual entry
      GoRoute(
        path: AppRoutes.manualEntry,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: ManualEntryScreen(),
        ),
      ),

      // Item added success
      GoRoute(
        path: AppRoutes.addItemSuccess,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return ItemAddedScreen(itemId: id);
        },
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

      // Notifications
      GoRoute(
        path: AppRoutes.notifications,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationsScreen(),
      ),

      // Notification Preferences
      GoRoute(
        path: AppRoutes.notificationPreferences,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const NotificationPreferencesScreen(),
      ),

      // Home Detail / Edit
      GoRoute(
        path: AppRoutes.homeDetail,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final id = state.pathParameters['id']!;
          return HomeDetailScreen(homeId: id);
        },
      ),

      // Archived Items
      GoRoute(
        path: AppRoutes.archivedItems,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ArchivedItemsScreen(),
      ),

      // Change Password
      GoRoute(
        path: AppRoutes.changePassword,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const ChangePasswordScreen(),
      ),

      // Delete Account
      GoRoute(
        path: AppRoutes.deleteAccount,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const DeleteAccountScreen(),
      ),

      // Scan Receipt
      GoRoute(
        path: AppRoutes.scanReceipt,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: ReceiptScanScreen(),
        ),
      ),

      // Scan Barcode
      GoRoute(
        path: AppRoutes.scanBarcode,
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: BarcodeScanScreen(),
        ),
      ),

      // PDF Preview
      GoRoute(
        path: AppRoutes.pdfPreview,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) {
          final item = state.extra as Item;
          return PdfPreviewScreen(item: item);
        },
      ),

      // Premium Upgrade
      GoRoute(
        path: AppRoutes.premium,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PremiumScreen(),
      ),

      // Premium Success
      GoRoute(
        path: AppRoutes.premiumSuccess,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const PremiumSuccessScreen(),
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
