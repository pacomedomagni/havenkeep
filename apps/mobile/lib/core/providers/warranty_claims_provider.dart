import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import '../services/warranty_claims_repository.dart';
import 'auth_provider.dart';
import 'homes_provider.dart';

/// Provides the warranty claims repository instance.
final claimsRepositoryProvider = Provider<WarrantyClaimsRepository>((ref) {
  return WarrantyClaimsRepository(ref.read(apiClientProvider));
});

/// All warranty claims for the current user.
final claimsProvider =
    AsyncNotifierProvider<ClaimsNotifier, List<WarrantyClaim>>(
  () => ClaimsNotifier(),
);

class ClaimsNotifier extends AsyncNotifier<List<WarrantyClaim>> {
  @override
  Future<List<WarrantyClaim>> build() async {
    final userAsync = ref.watch(currentUserProvider);
    final user = userAsync.valueOrNull;
    if (user == null) return [];

    // 2.13: re-fetch when the user switches homes.
    final currentHome = ref.watch(currentHomeProvider);
    return ref.read(claimsRepositoryProvider).getClaims(homeId: currentHome?.id);
  }

  /// Add a new claim.
  Future<WarrantyClaim> addClaim(WarrantyClaim claim) async {
    final newClaim = await ref.read(claimsRepositoryProvider).createClaim(claim);

    final current = state.value ?? [];
    state = AsyncValue.data([newClaim, ...current]);

    ref.invalidate(claimSavingsProvider);
    return newClaim;
  }

  /// Delete a claim.
  Future<void> deleteClaim(String id) async {
    await ref.read(claimsRepositoryProvider).deleteClaim(id);

    final current = state.value ?? [];
    state = AsyncValue.data(current.where((c) => c.id != id).toList());

    ref.invalidate(claimSavingsProvider);
  }
}

/// Claims for a specific item.
final claimsByItemProvider =
    FutureProvider.family.autoDispose<List<WarrantyClaim>, String>((ref, itemId) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return [];

  return ref.read(claimsRepositoryProvider).getClaims(itemId: itemId);
});

/// Total savings from warranty claims.
final claimSavingsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return {};

  return ref.read(claimsRepositoryProvider).getSavings();
});

/// Public savings feed (anonymized community social proof).
final savingsFeedProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);
  if (userAsync.valueOrNull == null) return [];

  return ref.read(claimsRepositoryProvider).getSavingsFeed(limit: 10);
});
