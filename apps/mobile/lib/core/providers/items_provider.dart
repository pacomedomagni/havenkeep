import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';
import '../services/items_repository.dart';
import '../services/category_repository.dart';
import 'auth_provider.dart';

/// Provides the items repository instance.
final itemsRepositoryProvider = Provider<ItemsRepository>((ref) {
  return ItemsRepository(ref.read(apiClientProvider));
});

/// Provides the category repository instance (reference data).
final categoryRepositoryProvider = Provider<CategoryRepository>((ref) {
  return CategoryRepository(ref.read(apiClientProvider));
});

/// All non-archived items for the current user.
final itemsProvider =
    AsyncNotifierProvider<ItemsNotifier, List<Item>>(
  () => ItemsNotifier(),
);

class ItemsNotifier extends AsyncNotifier<List<Item>> {
  @override
  Future<List<Item>> build() async {
    // Re-fetch when user changes (sign in/out)
    final userAsync = ref.watch(currentUserProvider);

    final user = userAsync.valueOrNull;
    if (user == null) return [];

    return ref.read(itemsRepositoryProvider).getItemsWithStatus();
  }

  /// Refresh the items list from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return ref.read(itemsRepositoryProvider).getItemsWithStatus();
    });
  }

  /// Add a new item.
  /// Returns the created item and previous count for celebration logic.
  Future<(Item item, int previousCount)> addItem(Item item) async {
    final repo = ref.read(itemsRepositoryProvider);
    final currentItems = state.value ?? [];
    final previousCount = currentItems.length;

    // Save previous state for rollback
    final previousState = AsyncValue.data(List<Item>.from(currentItems));

    try {
      // createItem returns the full item with computed fields (RETURNING *)
      final newItem = await repo.createItem(item);

      state = AsyncValue.data([newItem, ...currentItems]);

      // Invalidate stats
      ref.invalidate(warrantyStatsProvider);
      ref.invalidate(needsAttentionProvider);

      return (newItem, previousCount);
    } catch (e) {
      // Rollback to previous state on failure
      debugPrint('[ItemsNotifier] addItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }

  /// Update an existing item.
  Future<Item> updateItem(Item item) async {
    final repo = ref.read(itemsRepositoryProvider);
    final currentItems = state.value ?? [];

    // Save previous state for rollback
    final previousState = AsyncValue.data(List<Item>.from(currentItems));

    try {
      await repo.updateItem(item);

      // Re-fetch to get updated computed fields
      final updated = await repo.getItemById(item.id);

      state = AsyncValue.data(
        currentItems.map((i) => i.id == updated.id ? updated : i).toList(),
      );

      ref.invalidate(warrantyStatsProvider);
      ref.invalidate(needsAttentionProvider);

      return updated;
    } catch (e) {
      // Rollback to previous state on failure
      debugPrint('[ItemsNotifier] updateItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }

  /// Delete an item.
  Future<void> deleteItem(String id) async {
    await ref.read(itemsRepositoryProvider).deleteItem(id);

    final currentItems = state.value ?? [];
    state = AsyncValue.data(
      currentItems.where((i) => i.id != id).toList(),
    );

    ref.invalidate(warrantyStatsProvider);
    ref.invalidate(needsAttentionProvider);
  }

  /// Batch-add multiple items at once (used by bulk-add flow).
  Future<List<Item>> addItems(List<Item> items) async {
    final repo = ref.read(itemsRepositoryProvider);
    final createdItems = <Item>[];

    for (final item in items) {
      // createItem returns full item with RETURNING * (includes warranty_end_date)
      final newItem = await repo.createItem(item);
      createdItems.add(newItem);
    }

    final currentItems = state.value ?? [];
    state = AsyncValue.data([...createdItems, ...currentItems]);

    ref.invalidate(warrantyStatsProvider);
    ref.invalidate(needsAttentionProvider);

    return createdItems;
  }

  /// Archive an item (soft delete).
  Future<void> archiveItem(String id) async {
    await ref.read(itemsRepositoryProvider).archiveItem(id);

    final currentItems = state.value ?? [];
    state = AsyncValue.data(
      currentItems.where((i) => i.id != id).toList(),
    );

    ref.invalidate(warrantyStatsProvider);
    ref.invalidate(needsAttentionProvider);
    ref.invalidate(archivedItemsProvider);
  }

  /// Unarchive an item (restore from archive).
  Future<void> unarchiveItem(String id) async {
    await ref.read(itemsRepositoryProvider).unarchiveItem(id);

    // Re-fetch to get the restored item with computed fields
    final restored = await ref.read(itemsRepositoryProvider).getItemById(id);

    final currentItems = state.value ?? [];
    state = AsyncValue.data([restored, ...currentItems]);

    ref.invalidate(warrantyStatsProvider);
    ref.invalidate(needsAttentionProvider);
    ref.invalidate(archivedItemsProvider);
  }
}

/// Warranty stats for the dashboard (active, expiring, expired counts).
final warrantyStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);

  final user = userAsync.valueOrNull;
  if (user == null) return {'active': 0, 'expiring': 0, 'expired': 0};

  return ref.read(itemsRepositoryProvider).getWarrantyStats();
});

/// Items that need attention (expiring + expired, max 3 for dashboard).
final needsAttentionProvider = FutureProvider<List<Item>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);

  final user = userAsync.valueOrNull;
  if (user == null) return [];

  return ref.read(itemsRepositoryProvider).getNeedsAttention();
});

/// Single item detail by ID.
final itemDetailProvider =
    FutureProvider.family<Item, String>((ref, itemId) async {
  return ref.read(itemsRepositoryProvider).getItemById(itemId);
});

/// Category defaults (reference data).
final categoryDefaultsProvider =
    FutureProvider<List<CategoryDefault>>((ref) async {
  return ref.read(categoryRepositoryProvider).getCategoryDefaults();
});

/// Brand suggestions for a specific category.
final brandSuggestionsProvider =
    FutureProvider.family<List<String>, ItemCategory>((ref, category) async {
  return ref.read(categoryRepositoryProvider).getBrandNames(category);
});

/// Count of non-archived items (for free plan limit check).
final activeItemCountProvider = FutureProvider<int>((ref) async {
  ref.watch(itemsProvider); // Re-fetch when items change
  return ref.read(itemsRepositoryProvider).countActiveItems();
});

/// Whether the user has hit the free plan item limit.
final isAtItemLimitProvider = FutureProvider<bool>((ref) async {
  final user = ref.watch(currentUserProvider).value;
  if (user == null || user.plan == UserPlan.premium) return false;

  final count = await ref.watch(activeItemCountProvider.future);
  return count >= kFreePlanItemLimit;
});

/// Archived items for the current user.
final archivedItemsProvider = FutureProvider<List<Item>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);

  final user = userAsync.valueOrNull;
  if (user == null) return [];

  final allItems =
      await ref.read(itemsRepositoryProvider).getItems(includeArchived: true);
  return allItems.where((item) => item.isArchived).toList();
});
