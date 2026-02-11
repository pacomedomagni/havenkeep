import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';

import 'auth_provider.dart';

/// Whether the current user has a premium subscription.
final isPremiumProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return user?.plan == UserPlan.premium;
});

/// Mock premium subscription handler.
///
/// In production, this would integrate with Stripe. For now, it
/// updates the user's plan via the Express API.
class PremiumService {
  final Ref _ref;

  PremiumService(this._ref);

  /// Subscribe to premium (mock — updates user plan via API).
  Future<void> subscribeToPremium({String plan = 'monthly'}) async {
    try {
      final client = _ref.read(apiClientProvider);

      // Mock: directly update user plan via API
      await client.put('/api/v1/users/me', body: {'plan': 'premium'});

      // Refresh user data
      _ref.invalidate(currentUserProvider);

      debugPrint('[Premium] User subscribed to $plan plan');
    } catch (e) {
      debugPrint('[Premium] Subscription failed: $e');
      rethrow;
    }
  }

  /// Restore a previous purchase (mock — checks current plan via API).
  Future<bool> restorePurchase() async {
    try {
      final client = _ref.read(apiClientProvider);
      final data = await client.get('/api/v1/users/me');

      final user = data['user'] as Map<String, dynamic>;
      final isPremium = user['plan'] == 'premium';
      if (isPremium) {
        _ref.invalidate(currentUserProvider);
      }
      return isPremium;
    } catch (e) {
      debugPrint('[Premium] Restore failed: $e');
      return false;
    }
  }
}

/// Riverpod provider for the premium service.
final premiumServiceProvider = Provider<PremiumService>((ref) {
  return PremiumService(ref);
});
