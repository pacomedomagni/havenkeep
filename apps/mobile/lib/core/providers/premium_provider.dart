import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

import 'auth_provider.dart';

/// Whether the current user has a premium subscription.
final isPremiumProvider = Provider<bool>((ref) {
  final user = ref.watch(currentUserProvider).value;
  return user?.plan == UserPlan.premium;
});

/// Mock premium subscription handler.
///
/// In production, this would integrate with Stripe. For now, it
/// directly updates the user's plan in Supabase.
class PremiumService {
  final Ref _ref;

  PremiumService(this._ref);

  /// Subscribe to premium (mock — updates user metadata directly).
  Future<void> subscribeToPremium({String plan = 'monthly'}) async {
    try {
      final client = _ref.read(supabaseClientProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) throw Exception('Not authenticated');

      // Mock: directly update user plan
      await client
          .from('users')
          .update({'plan': 'premium'})
          .eq('id', userId);

      // Refresh user data
      _ref.invalidate(currentUserProvider);

      debugPrint('[Premium] User $userId subscribed to $plan plan');
    } catch (e) {
      debugPrint('[Premium] Subscription failed: $e');
      rethrow;
    }
  }

  /// Restore a previous purchase (mock — checks current plan).
  Future<bool> restorePurchase() async {
    try {
      final client = _ref.read(supabaseClientProvider);
      final userId = client.auth.currentUser?.id;
      if (userId == null) return false;

      final result = await client
          .from('users')
          .select('plan')
          .eq('id', userId)
          .single();

      final isPremium = result['plan'] == 'premium';
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
