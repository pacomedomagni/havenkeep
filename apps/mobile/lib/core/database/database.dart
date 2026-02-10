import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'tables/local_items.dart';
import 'tables/local_homes.dart';
import 'tables/offline_queue.dart';

part 'database.g.dart';

/// HavenKeep local SQLite database powered by Drift.
///
/// Caches items and homes locally for offline support and maintains
/// a queue of mutations to sync when connectivity is restored.
///
/// Run `dart run build_runner build` inside `apps/mobile/` to regenerate
/// the `database.g.dart` file after modifying table definitions.
@DriftDatabase(tables: [LocalItems, LocalHomes, OfflineQueue])
class HavenDatabase extends _$HavenDatabase {
  HavenDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  // ---------------------------------------------------------------------------
  // LOCAL ITEMS
  // ---------------------------------------------------------------------------

  /// Fetch all locally cached items.
  Future<List<LocalItem>> getAllItems() => select(localItems).get();

  /// Fetch all non-archived items.
  Future<List<LocalItem>> getActiveItems() =>
      (select(localItems)..where((t) => t.isArchived.equals(false))).get();

  /// Fetch a single item by ID.
  Future<LocalItem?> getItemById(String itemId) =>
      (select(localItems)..where((t) => t.id.equals(itemId))).getSingleOrNull();

  /// Insert or update an item (upsert).
  Future<void> upsertItem(LocalItemsCompanion entry) =>
      into(localItems).insertOnConflictUpdate(entry);

  /// Delete an item by ID.
  Future<int> removeItem(String itemId) =>
      (delete(localItems)..where((t) => t.id.equals(itemId))).go();

  /// Remove all locally cached items.
  Future<void> clearAllItems() => delete(localItems).go();

  // ---------------------------------------------------------------------------
  // LOCAL HOMES
  // ---------------------------------------------------------------------------

  /// Fetch all locally cached homes.
  Future<List<LocalHome>> getAllHomes() => select(localHomes).get();

  /// Insert or update a home (upsert).
  Future<void> upsertHome(LocalHomesCompanion entry) =>
      into(localHomes).insertOnConflictUpdate(entry);

  /// Delete a home by ID.
  Future<int> removeHome(String homeId) =>
      (delete(localHomes)..where((t) => t.id.equals(homeId))).go();

  // ---------------------------------------------------------------------------
  // OFFLINE QUEUE
  // ---------------------------------------------------------------------------

  /// Fetch all pending (un-synced) queue entries, ordered oldest first.
  Future<List<OfflineQueueData>> getPendingActions() =>
      (select(offlineQueue)
            ..where((t) => t.status.equals('pending'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Count of pending sync items.
  Future<int> get pendingCount async {
    final countExpr = countAll();
    final query = selectOnly(offlineQueue)
      ..where(offlineQueue.status.equals('pending'))
      ..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Enqueue a new offline action.
  Future<int> enqueueAction(OfflineQueueCompanion entry) =>
      into(offlineQueue).insert(entry);

  /// Mark a queued action as successfully synced.
  Future<void> markActionSynced(int actionId) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(const OfflineQueueCompanion(status: Value('synced')));

  /// Mark a queued action as failed and record the attempt count.
  Future<void> markActionFailed(int actionId, int attemptCount) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(OfflineQueueCompanion(
        status: const Value('failed'),
        attempts: Value(attemptCount),
      ));

  /// Re-queue a failed action for retry.
  Future<void> retryAction(int actionId) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(const OfflineQueueCompanion(status: Value('pending')));

  /// Remove all synced actions from the queue.
  Future<void> clearSyncedActions() =>
      (delete(offlineQueue)..where((t) => t.status.equals('synced'))).go();
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'havenkeep.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

/// Riverpod provider for the local Drift database singleton.
final localDatabaseProvider = Provider<HavenDatabase>((ref) {
  final db = HavenDatabase();
  ref.onDispose(() => db.close());
  return db;
});
