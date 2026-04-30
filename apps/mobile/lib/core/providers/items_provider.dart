import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';
import '../services/items_repository.dart';
import '../services/category_repository.dart';
import '../services/offline_sync_service.dart';
import '../services/push_notification_service.dart';
import 'auth_provider.dart';
import 'homes_provider.dart';

/// C14: a network/timeout exception is treated as "queue and continue"
/// rather than "rollback and rethrow". Other ApiException variants
/// (validation, conflict, forbidden, server) still propagate so the UI
/// surfaces them as real errors. The offline-sync service drains the
/// queue on next online tick (auth-gated, FIFO, with idempotency keys
/// stamped at enqueue time).
bool _isOfflineError(Object e) =>
    e is ApiNetworkException || e is ApiTimeoutException;

/// Thrown by [ItemsNotifier.addItems] when a bulk add partially succeeds.
/// The UI can use `failed` to offer a targeted retry without re-sending
/// items that already made it.
class BulkAddPartialFailure implements Exception {
  BulkAddPartialFailure({
    required this.succeeded,
    required this.failed,
    required this.reasons,
  });

  final List<Item> succeeded;
  final List<Item> failed;
  final List<String> reasons;

  @override
  String toString() =>
      'Failed to create ${failed.length}/${succeeded.length + failed.length} items';
}

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

    // Re-fetch when selected home changes
    final currentHome = ref.watch(currentHomeProvider);

    return ref.read(itemsRepositoryProvider).getItemsWithStatus(
      homeId: currentHome?.id,
    );
  }

  /// Refresh the items list from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    final currentHome = ref.read(currentHomeProvider);
    state = await AsyncValue.guard(() async {
      return ref.read(itemsRepositoryProvider).getItemsWithStatus(
        homeId: currentHome?.id,
      );
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

      // Ch05-F077: ask for push permission only after the user has felt
      // the value of the app. The first save is the strongest moment;
      // subsequent calls are idempotent because iOS won't re-prompt
      // and Android already auto-grants below API 33.
      if (previousCount == 0) {
        unawaited(_promptForPushPermission());
      }

      return (newItem, previousCount);
    } catch (e) {
      // C14: network/timeout → enqueue and continue with the optimistic
      // item. Other ApiException variants (validation 400, server 5xx,
      // forbidden 403, conflict 409) still rollback because they reflect
      // a server-side decision the queue can't replay-fix.
      if (_isOfflineError(e)) {
        try {
          await ref.read(offlineSyncServiceProvider).enqueueChange(
                entityType: 'item',
                entityId: item.id,
                action: OfflineAction.create_item,
                payload: item.toJson(),
              );
          state = AsyncValue.data([item, ...currentItems]);
          if (previousCount == 0) {
            unawaited(_promptForPushPermission());
          }
          return (item, previousCount);
        } catch (queueErr) {
          debugPrint('[ItemsNotifier] addItem offline-enqueue failed: $queueErr');
          state = previousState;
          rethrow;
        }
      }
      // Rollback to previous state on non-offline failure
      debugPrint('[ItemsNotifier] addItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }

  Future<void> _promptForPushPermission() async {
    try {
      await ref
          .read(pushNotificationServiceProvider)
          .requestPermissionAndRegisterToken();
    } catch (_) {
      // Permission UX is non-blocking; the user can grant it later
      // from Settings if the prompt was suppressed.
    }
  }

  /// Update an existing item.
  Future<Item> updateItem(Item item) async {
    final repo = ref.read(itemsRepositoryProvider);
    final currentItems = state.value ?? [];

    // Save previous state for rollback
    final previousState = AsyncValue.data(List<Item>.from(currentItems));

    try {
      // The PUT response already carries the canonical row with all
      // computed fields. Don't follow up with a GET — it doubles latency
      // and a transient network failure would silently roll back a
      // mutation the server already accepted (see C113).
      final updated = await repo.updateItem(item);

      state = AsyncValue.data(
        currentItems.map((i) => i.id == updated.id ? updated : i).toList(),
      );

      return updated;
    } catch (e) {
      // C14: network/timeout → enqueue + apply optimistically. The queue
      // replays via repo.updateItem; the server responds with the
      // canonical row on next sync and the conflict path
      // (ApiConflictException → _parkUpdateConflict) handles version
      // divergence then.
      if (_isOfflineError(e)) {
        try {
          await ref.read(offlineSyncServiceProvider).enqueueChange(
                entityType: 'item',
                entityId: item.id,
                action: OfflineAction.update_item,
                payload: item.toJson(),
              );
          state = AsyncValue.data(
            currentItems.map((i) => i.id == item.id ? item : i).toList(),
          );
          return item;
        } catch (queueErr) {
          debugPrint('[ItemsNotifier] updateItem offline-enqueue failed: $queueErr');
          state = previousState;
          rethrow;
        }
      }
      // Rollback to previous state on non-offline failure
      debugPrint('[ItemsNotifier] updateItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }

  /// Delete an item.
  Future<void> deleteItem(String id) async {
    final currentItems = state.value ?? [];
    final previousState = AsyncValue.data(List<Item>.from(currentItems));

    try {
      await ref.read(itemsRepositoryProvider).deleteItem(id);

      state = AsyncValue.data(
        currentItems.where((i) => i.id != id).toList(),
      );
    } catch (e) {
      // C14: queue + remove from local state. The replay will issue the
      // DELETE; if the server returns 404 (item already gone) the queue
      // entry naturally drains as a no-op.
      if (_isOfflineError(e)) {
        try {
          await ref.read(offlineSyncServiceProvider).enqueueChange(
                entityType: 'item',
                entityId: id,
                action: OfflineAction.delete_item,
                payload: <String, dynamic>{},
              );
          state = AsyncValue.data(
            currentItems.where((i) => i.id != id).toList(),
          );
          return;
        } catch (queueErr) {
          debugPrint('[ItemsNotifier] deleteItem offline-enqueue failed: $queueErr');
          state = previousState;
          rethrow;
        }
      }
      state = previousState;
      rethrow;
    }
  }

  /// Batch-add multiple items at once (used by bulk-add flow).
  ///
  /// Re-checks the free-plan quota BEFORE each item (C114): a single
  /// up-front check would let a partial-failure batch silently push the
  /// account past the limit if the server's count had drifted. Anything
  /// beyond the cap is recorded as a quota failure so the caller can
  /// surface a single "you hit the limit, upgrade to add the remaining
  /// N items" prompt instead of N separate snackbars.
  ///
  /// On partial failure throws [BulkAddPartialFailure] carrying the list
  /// of inputs that didn't make it, so the caller can offer a targeted
  /// "retry failed" instead of re-submitting the whole batch.
  Future<List<Item>> addItems(List<Item> items) async {
    final repo = ref.read(itemsRepositoryProvider);
    final user = ref.read(currentUserProvider).valueOrNull;
    final isPremium = user?.plan == UserPlan.premium;

    final currentItems = state.value ?? [];
    final createdItems = <Item>[];
    final failedItems = <Item>[];
    final failureReasons = <String>[];

    // Snapshot of how many active items the user already has. Each
    // successful create on the free plan bumps this by one — when it
    // hits the limit the rest of the batch is rejected locally so we
    // don't spam the API with calls we know will 403.
    var activeCount = currentItems.where((i) => !i.isArchived).length;

    for (int i = 0; i < items.length; i++) {
      if (!isPremium && activeCount >= kFreePlanItemLimit) {
        debugPrint(
          '[ItemsNotifier] Item ${i + 1}/${items.length} blocked: free-plan limit ($kFreePlanItemLimit) reached.',
        );
        failedItems.add(items[i]);
        failureReasons.add('Free plan limit ($kFreePlanItemLimit) reached');
        continue;
      }

      try {
        final newItem = await repo.createItem(items[i]);
        createdItems.add(newItem);
        activeCount++;
      } catch (e) {
        debugPrint('[ItemsNotifier] Item ${i + 1}/${items.length} creation failed: $e');
        failedItems.add(items[i]);
        failureReasons.add(e.toString());
      }
    }

    state = AsyncValue.data([...createdItems, ...currentItems]);

    if (failedItems.isNotEmpty) {
      throw BulkAddPartialFailure(
        succeeded: createdItems,
        failed: failedItems,
        reasons: failureReasons,
      );
    }

    return createdItems;
  }

  /// Archive an item (soft delete).
  Future<void> archiveItem(String id) async {
    final currentItems = state.value ?? [];
    final previousState = AsyncValue.data(List<Item>.from(currentItems));
    final target = currentItems.firstWhere((i) => i.id == id, orElse: () => currentItems.first);

    // Optimistically remove from active list
    state = AsyncValue.data(
      currentItems.where((i) => i.id != id).toList(),
    );

    try {
      await ref.read(itemsRepositoryProvider).archiveItem(id);
      ref.invalidate(archivedItemsProvider);
    } catch (e) {
      if (_isOfflineError(e)) {
        try {
          // archive is an update_item with is_archived=true; replay uses
          // repo.updateItem which sends the full row.
          final archived = target.copyWith(isArchived: true);
          await ref.read(offlineSyncServiceProvider).enqueueChange(
                entityType: 'item',
                entityId: id,
                action: OfflineAction.update_item,
                payload: archived.toJson(),
              );
          // Optimistic UI already removed from active list above; archive
          // list will pick it up on next ref.invalidate when replay completes.
          return;
        } catch (queueErr) {
          debugPrint('[ItemsNotifier] archiveItem offline-enqueue failed: $queueErr');
          state = previousState;
          rethrow;
        }
      }
      // Rollback to previous state on non-offline failure
      debugPrint('[ItemsNotifier] archiveItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }

  /// Unarchive an item (restore from archive).
  Future<void> unarchiveItem(String id) async {
    final currentItems = state.value ?? [];
    final previousState = AsyncValue.data(List<Item>.from(currentItems));

    try {
      await ref.read(itemsRepositoryProvider).unarchiveItem(id);

      // Re-fetch to get the restored item with computed fields
      final restored = await ref.read(itemsRepositoryProvider).getItemById(id);

      state = AsyncValue.data([restored, ...currentItems]);

      ref.invalidate(archivedItemsProvider);
    } catch (e) {
      // C14: unarchive doesn't have a clean offline shape — the
      // post-success path needs a getItemById to merge the restored row
      // back into state, which itself needs network. Rather than fake an
      // optimistic Item from cache (we don't have it in `currentItems`
      // by definition), fall through to rollback so the user sees the
      // failure and can retry when online. The queued PUT pattern fits
      // archive (which removes from a list we already have) but not
      // unarchive (which adds to it).
      debugPrint('[ItemsNotifier] unarchiveItem failed, rolling back: $e');
      state = previousState;
      rethrow;
    }
  }
}

/// Warranty stats for the dashboard (active, expiring, expired counts).
/// Fetched from the server-side stats endpoint.
final warrantyStatsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(currentUserProvider);
  return ref.read(itemsRepositoryProvider).getWarrantyStats();
});

/// Items that need attention (expiring + expired, max 3 for dashboard).
/// Derived from itemsProvider so it respects the current home filter.
final needsAttentionProvider = Provider<AsyncValue<List<Item>>>((ref) {
  final itemsAsync = ref.watch(itemsProvider);
  return itemsAsync.whenData((items) {
    final attention = items.where((item) {
      final status = item.computedWarrantyStatus;
      return status == WarrantyStatus.expiring || status == WarrantyStatus.expired;
    }).toList();
    attention.sort((a, b) => a.computedDaysRemaining.compareTo(b.computedDaysRemaining));
    return attention.take(kNeedsAttentionLimit).toList();
  });
});

/// Single item detail by ID.
///
/// S2-Q: `autoDispose` so closing a detail screen releases the cached
/// row instead of accumulating one entry per item the user has ever
/// inspected this session. The list providers (`itemsProvider`,
/// `topItemsProvider`, etc.) are still long-lived — only this per-id
/// family is bounded.
final itemDetailProvider =
    FutureProvider.family.autoDispose<Item, String>((ref, itemId) async {
  return ref.read(itemsRepositoryProvider).getItemById(itemId);
});

/// Category defaults (reference data).
final categoryDefaultsProvider =
    FutureProvider<List<CategoryDefault>>((ref) async {
  return ref.read(categoryRepositoryProvider).getCategoryDefaults();
});

/// Brand suggestions for a specific category.
///
/// H-B8: autoDispose so a user who browses many categories doesn't
/// accumulate one cached future per category for the lifetime of the
/// ProviderScope. Same hygiene as itemDetailProvider above.
final brandSuggestionsProvider =
    FutureProvider.family.autoDispose<List<String>, ItemCategory>((ref, category) async {
  return ref.read(categoryRepositoryProvider).getBrandNames(category);
});

/// Count of non-archived items (for free plan limit check).
/// Derived from itemsProvider so it respects the current home filter.
final activeItemCountProvider = Provider<AsyncValue<int>>((ref) {
  final itemsAsync = ref.watch(itemsProvider);
  return itemsAsync.whenData((items) => items.length);
});

/// Whether the user has hit the free plan item limit.
final isAtItemLimitProvider = Provider<AsyncValue<bool>>((ref) {
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (user == null || user.plan == UserPlan.premium) {
    return const AsyncValue.data(false);
  }
  final countAsync = ref.watch(activeItemCountProvider);
  return countAsync.whenData((count) => count >= kFreePlanItemLimit);
});

/// Archived items for the current user, filtered by selected home.
final archivedItemsProvider = FutureProvider<List<Item>>((ref) async {
  final userAsync = ref.watch(currentUserProvider);

  final user = userAsync.valueOrNull;
  if (user == null) return [];

  final currentHome = ref.watch(currentHomeProvider);

  final allItems = await ref.read(itemsRepositoryProvider).getItems(
    homeId: currentHome?.id,
    includeArchived: true,
  );
  return allItems.where((item) => item.isArchived).toList();
});

/// Items imported via email scanning (addedVia == 'email').
/// Derived from itemsProvider so it respects the current home filter.
final emailImportedItemsProvider = Provider<AsyncValue<List<Item>>>((ref) {
  final itemsAsync = ref.watch(itemsProvider);
  return itemsAsync.whenData(
    (items) => items
        .where((item) => item.addedVia == ItemAddedVia.email)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt)),
  );
});
