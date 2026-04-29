import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import '../services/warranty_purchases_repository.dart';
import 'auth_provider.dart';
import 'homes_provider.dart';

final warrantyPurchasesRepositoryProvider = Provider<WarrantyPurchasesRepository>((ref) {
  return WarrantyPurchasesRepository(ref.read(apiClientProvider));
});

final warrantyPurchasesProvider =
    AsyncNotifierProvider<WarrantyPurchasesNotifier, List<WarrantyPurchase>>(
  () => WarrantyPurchasesNotifier(),
);

class WarrantyPurchasesNotifier extends AsyncNotifier<List<WarrantyPurchase>> {
  @override
  Future<List<WarrantyPurchase>> build() async {
    final userAsync = ref.watch(currentUserProvider);
    if (userAsync.valueOrNull == null) return [];
    // 2.13: scope purchases to the active home so the coverage tab matches
    // the home-switcher state.
    final currentHome = ref.watch(currentHomeProvider);
    return ref
        .read(warrantyPurchasesRepositoryProvider)
        .getPurchases(homeId: currentHome?.id);
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final currentHome = ref.read(currentHomeProvider);
      return ref
          .read(warrantyPurchasesRepositoryProvider)
          .getPurchases(homeId: currentHome?.id);
    });
  }

  Future<WarrantyPurchase> addPurchase(WarrantyPurchase purchase) async {
    final created = await ref.read(warrantyPurchasesRepositoryProvider).createPurchase(purchase);
    final current = state.value ?? [];
    state = AsyncValue.data([created, ...current]);
    return created;
  }

  Future<void> cancelPurchase(String id, {String? reason}) async {
    final updated =
        await ref.read(warrantyPurchasesRepositoryProvider).cancelPurchase(id, reason: reason);
    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((p) => p.id == id ? updated : p).toList(),
    );
  }
}
