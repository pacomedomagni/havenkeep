import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';

import '../../main.dart';
import 'auth_provider.dart';

/// RevenueCat entitlement identifier for HavenKeep Premium.
const _premiumEntitlementId = 'premium';

/// RevenueCat offering identifier for the default offering.
const _defaultOfferingId = 'default';

/// Whether the current user has a premium subscription.
///
/// Single source of truth: the `plan` field on the API-side user record.
/// That field is kept current by RevenueCat webhooks (and by the
/// `verify-premium` round-trip after a successful local purchase), so the
/// client never needs to OR-join two sources that can disagree.
final isPremiumProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return user?.plan == UserPlan.premium;
});

/// Service that manages the full in-app purchase lifecycle via RevenueCat.
///
/// Handles SDK initialization, purchasing, restoring purchases, and listening
/// for customer info changes to keep premium status in sync.
class PremiumService {
  final Ref _ref;
  bool _initialized = false;

  PremiumService(this._ref);

  /// Initialize the RevenueCat Purchases SDK.
  ///
  /// Must be called once at app startup (after the environment config is loaded).
  /// Sets the app user ID to the authenticated user's ID so that RevenueCat
  /// subscriptions are tied to the HavenKeep account.
  Future<void> initialize() async {
    if (_initialized) return;

    final config = _ref.read(environmentConfigProvider);
    final apiKey = config.revenueCatApiKey;

    if (apiKey.isEmpty) {
      debugPrint('[Premium] RevenueCat API key not configured, skipping initialization');
      return;
    }

    final apiClient = _ref.read(apiClientProvider);
    final userId = apiClient.currentUserId;

    final purchasesConfig = PurchasesConfiguration(apiKey);
    if (userId != null) {
      purchasesConfig.appUserID = userId;
    }

    await Purchases.configure(purchasesConfig);

    // Listen for customer info changes (renewals, cancellations, etc.).
    // Removed in dispose() so provider rebuilds don't stack listeners.
    Purchases.addCustomerInfoUpdateListener(_onCustomerInfoUpdated);

    _initialized = true;
    debugPrint('[Premium] RevenueCat SDK initialized');

    // Check current entitlement status
    await checkSubscriptionStatus();
  }

  /// Handle customer info updates from RevenueCat.
  ///
  /// Called whenever the subscription state changes — initial purchase, renewal,
  /// cancellation, expiration, billing issue, etc. Triggers server-side
  /// verification so the canonical `user.plan` field is brought in sync;
  /// the local UI then re-reads from `currentUserProvider`.
  void _onCustomerInfoUpdated(CustomerInfo customerInfo) {
    final isPremium = customerInfo.entitlements.all[_premiumEntitlementId]?.isActive ?? false;
    debugPrint('[Premium] Customer info updated — premium: $isPremium');

    // Sync status with the backend asynchronously, then refresh the user
    // record so `isPremiumProvider` (derived from user.plan) sees the
    // updated value.
    if (isPremium) {
      _verifyPremiumWithServer().then((_) {
        _ref.invalidate(currentUserProvider);
      });
    } else {
      // Entitlement lapsed — re-fetch the user so the server-side downgrade
      // (handled by the RC webhook) is reflected locally.
      _ref.invalidate(currentUserProvider);
    }
  }

  /// Resolve the active offering from RevenueCat (or null if none configured).
  Future<Offering?> getActiveOffering() async {
    if (!_initialized) {
      throw StateError('PremiumService not initialized. Call initialize() first.');
    }
    final offerings = await Purchases.getOfferings();
    return offerings.getOffering(_defaultOfferingId) ?? offerings.current;
  }

  /// Subscribe to premium by displaying the available offering and initiating
  /// the platform-native purchase flow.
  ///
  /// [plan] is either 'monthly' or 'annual', corresponding to package types
  /// in the RevenueCat offering.
  ///
  /// Throws on purchase failure (cancellation, network error, etc.).
  Future<void> subscribeToPremium({String plan = 'monthly'}) async {
    if (!_initialized) {
      throw StateError('PremiumService not initialized. Call initialize() first.');
    }

    // Fetch the current offerings from RevenueCat
    final offerings = await Purchases.getOfferings();
    final offering = offerings.getOffering(_defaultOfferingId) ?? offerings.current;

    if (offering == null) {
      throw StateError('No offerings available. Check RevenueCat dashboard configuration.');
    }

    // Select the package matching the requested plan
    final Package? package;
    switch (plan) {
      case 'annual':
      case 'yearly':
        package = offering.annual;
        break;
      case 'monthly':
      default:
        package = offering.monthly;
        break;
    }

    if (package == null) {
      throw StateError(
        'No "$plan" package found in the "$_defaultOfferingId" offering. '
        'Available packages: ${offering.availablePackages.map((p) => p.identifier).join(", ")}',
      );
    }

    // Initiate the purchase. This displays the native payment sheet.
    // RevenueCat handles receipt validation automatically.
    final customerInfo = await Purchases.purchasePackage(package);

    final isPremium = customerInfo.entitlements.all[_premiumEntitlementId]?.isActive ?? false;

    if (isPremium) {
      await _verifyPremiumWithServer();
      // Refresh user data so the API-side plan is reflected locally
      _ref.invalidate(currentUserProvider);
    }

    debugPrint('[Premium] Purchase completed — premium: $isPremium');
  }

  /// Restore previously purchased subscriptions.
  ///
  /// Returns true if a premium entitlement was found and restored.
  Future<bool> restorePurchase() async {
    if (!_initialized) {
      throw StateError('PremiumService not initialized. Call initialize() first.');
    }

    final customerInfo = await Purchases.restorePurchases();

    final isPremium = customerInfo.entitlements.all[_premiumEntitlementId]?.isActive ?? false;

    if (isPremium) {
      await _verifyPremiumWithServer();
      _ref.invalidate(currentUserProvider);
    }

    debugPrint('[Premium] Restore completed — premium: $isPremium');
    return isPremium;
  }

  /// Check the current subscription status from RevenueCat.
  ///
  /// Triggers server-side verification when premium so the canonical
  /// `user.plan` field is kept in sync. Called during initialization and
  /// can be called on-demand to refresh status.
  Future<void> checkSubscriptionStatus() async {
    if (!_initialized) return;

    try {
      final customerInfo = await Purchases.getCustomerInfo();
      final isPremium = customerInfo.entitlements.all[_premiumEntitlementId]?.isActive ?? false;

      debugPrint('[Premium] Subscription status check — premium: $isPremium');

      if (isPremium) {
        await _verifyPremiumWithServer();
        _ref.invalidate(currentUserProvider);
      }
    } catch (e) {
      debugPrint('[Premium] Failed to check subscription status: $e');
    }
  }

  /// Verify the premium subscription with the HavenKeep backend.
  ///
  /// Sends the RevenueCat app user ID to the server, which verifies the
  /// subscription via the RevenueCat REST API and updates the user's plan
  /// in the database. This ensures the server-side record stays in sync.
  ///
  /// Retries up to 3 times with increasing delays (5s, 30s, 5min) if the
  /// server call fails.
  Future<void> _verifyPremiumWithServer({int attempt = 0}) async {
    const maxRetries = 3;
    const retryDelays = [
      Duration(seconds: 5),
      Duration(seconds: 30),
      Duration(minutes: 5),
    ];

    try {
      final appUserId = await Purchases.appUserID;
      final client = _ref.read(apiClientProvider);

      await client.post(
        pathSegments: const ['api', 'v1', 'users', 'me', 'verify-premium'],
        body: {
          'revenueCatAppUserId': appUserId,
        },
      );

      debugPrint('[Premium] Server-side verification completed');
    } catch (e) {
      // Non-fatal: the webhook will also update the server.
      // Log but don't throw — the user already has their entitlement.
      debugPrint('[Premium] Server-side verification failed (attempt ${attempt + 1}/$maxRetries): $e');

      if (attempt < maxRetries - 1) {
        final delay = retryDelays[attempt];
        debugPrint('[Premium] Scheduling retry in ${delay.inSeconds}s');
        Timer(delay, () => _verifyPremiumWithServer(attempt: attempt + 1));
      } else {
        debugPrint('[Premium] Server-side verification failed after $maxRetries attempts (non-fatal)');
      }
    }
  }

  /// Log in to RevenueCat with the given user ID.
  ///
  /// Called after authentication to associate the RevenueCat customer with
  /// the HavenKeep user account.
  Future<void> logIn(String userId) async {
    if (!_initialized) return;

    try {
      final result = await Purchases.logIn(userId);
      _onCustomerInfoUpdated(result.customerInfo);
      debugPrint('[Premium] RevenueCat user logged in: $userId');
    } catch (e) {
      debugPrint('[Premium] RevenueCat login failed: $e');
    }
  }

  /// Log out of RevenueCat.
  ///
  /// Called when the user signs out of HavenKeep. Resets the RevenueCat
  /// customer to an anonymous user.
  Future<void> logOut() async {
    if (!_initialized) return;

    try {
      final isAnonymous = await Purchases.isAnonymous;
      if (!isAnonymous) {
        await Purchases.logOut();
      }
      debugPrint('[Premium] RevenueCat user logged out');
    } catch (e) {
      debugPrint('[Premium] RevenueCat logout failed: $e');
    }
  }

  /// Called when the owning provider is disposed. Detaches the RevenueCat
  /// customer-info listener so it doesn't fire after the Ref is invalid
  /// and so re-created services don't double-subscribe.
  void dispose() {
    if (!_initialized) return;
    try {
      Purchases.removeCustomerInfoUpdateListener(_onCustomerInfoUpdated);
    } catch (e) {
      debugPrint('[Premium] removeCustomerInfoUpdateListener failed: $e');
    }
  }
}

/// Riverpod provider for the premium service. On dispose (e.g. sign-out
/// rebuilds the auth-dependent providers) we must remove the RevenueCat
/// listener; otherwise repeated sign-in/sign-out cycles accumulate
/// duplicate listeners and wedge memory.
final premiumServiceProvider = Provider<PremiumService>((ref) {
  final service = PremiumService(ref);
  ref.onDispose(() {
    service.dispose();
  });
  return service;
});
