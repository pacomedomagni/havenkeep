import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqlcipher_flutter_libs/sqlcipher_flutter_libs.dart';
import 'package:sqlite3/open.dart';

import '../services/secure_storage_service.dart';
import 'tables/offline_queue.dart';
import 'tables/sync_conflicts.dart';

part 'database.g.dart';

/// HavenKeep local SQLite database powered by Drift on top of SQLCipher.
///
/// Persists the offline-mutation queue and any sync conflicts that need
/// manual user resolution. The database file is encrypted at rest with a
/// 256-bit key persisted in platform secure storage and is scoped per
/// signed-in user (so two accounts on the same device cannot read each
/// other's data).
///
/// Run `dart run build_runner build` inside `apps/mobile/` to regenerate
/// the `database.g.dart` file after modifying table definitions.
@DriftDatabase(tables: [OfflineQueue, SyncConflicts])
class HavenDatabase extends _$HavenDatabase {
  HavenDatabase({String? userId})
      : super(_openConnection(userId: userId));

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _createIndexes();
        },
        onUpgrade: (m, from, to) async {
          for (var target = from + 1; target <= to; target++) {
            switch (target) {
              case 2:
                await _createIndexes();
                break;
              case 3:
                await m.createTable(syncConflicts);
                break;
              case 4:
                // S2-E: thread an Idempotency-Key per queue entry so a
                // re-sent in-flight action can't duplicate writes.
                await m.addColumn(offlineQueue, offlineQueue.idempotencyKey);
                break;
              case 5:
                // 1.10: drop the never-populated offline-read cache.
                // `local_items` / `local_homes` were never written to; the
                // sign-out wipe and the conflicts-screen "drop cached row"
                // were no-ops. Drop the tables so the encrypted DB file
                // stops carrying dead schema.
                await customStatement('DROP TABLE IF EXISTS local_items');
                await customStatement('DROP TABLE IF EXISTS local_homes');
                break;
            }
          }
        },
      );

  Future<void> _createIndexes() async {
    await customStatement(
        'CREATE INDEX IF NOT EXISTS idx_offline_queue_status_created ON offline_queue (status, created_at)');
  }

  // ---------------------------------------------------------------------------
  // OFFLINE QUEUE
  // ---------------------------------------------------------------------------

  /// Fetch all queue entries the sync loop should attempt — both `pending`
  /// (never sent) and `in_flight` (sent but not yet acknowledged because
  /// the previous run crashed mid-write). Ordered oldest first. Re-sending
  /// an `in_flight` entry is safe because the entry carries an
  /// idempotency key the server uses to collapse duplicate writes (S2-C).
  Future<List<OfflineQueueData>> getPendingActions() =>
      (select(offlineQueue)
            ..where((t) => t.status.isIn(['pending', 'in_flight']))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Mark a queued action as currently being sent. Persisted before the
  /// network call so a crash mid-flight leaves a recoverable record.
  Future<void> markActionInFlight(int actionId) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(const OfflineQueueCompanion(status: Value('in_flight')));

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

  /// H50: park a queued action when it deferred to user conflict
  /// resolution (e.g. a 409 from update_item). Distinct from `synced`
  /// so the clearSyncedActions sweep doesn't delete it while the
  /// conflict UI is still waiting for the user to choose a side.
  Future<void> markActionParked(int actionId) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(const OfflineQueueCompanion(status: Value('parked')));

  /// Mark a queued action as permanently failed and record the attempt count.
  Future<void> markActionFailed(int actionId, int attemptCount) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(OfflineQueueCompanion(
        status: const Value('failed'),
        attempts: Value(attemptCount),
      ));

  /// Reschedule a transient failure: keep the row in `pending` and bump the
  /// attempt counter in a single UPDATE so we never write a `failed` state
  /// we'd immediately flip back to `pending`.
  Future<void> reschedulePending(int actionId, int attemptCount) =>
      (update(offlineQueue)..where((t) => t.id.equals(actionId)))
          .write(OfflineQueueCompanion(
        status: const Value('pending'),
        attempts: Value(attemptCount),
      ));

  /// Fetch all failed queue entries, ordered oldest first.
  Future<List<OfflineQueueData>> getFailedActions() =>
      (select(offlineQueue)
            ..where((t) => t.status.equals('failed'))
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Count of failed sync items.
  Future<int> get failedCount async {
    final countExpr = countAll();
    final query = selectOnly(offlineQueue)
      ..where(offlineQueue.status.equals('failed'))
      ..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Re-queue all failed actions for retry (resets status to 'pending' and attempts to 0).
  Future<void> retryAllFailedActions() =>
      (update(offlineQueue)..where((t) => t.status.equals('failed')))
          .write(const OfflineQueueCompanion(
        status: Value('pending'),
        attempts: Value(0),
      ));

  /// Remove all synced actions from the queue.
  Future<void> clearSyncedActions() =>
      (delete(offlineQueue)..where((t) => t.status.equals('synced'))).go();

  /// Drop every row in the offline queue (used on sign-out / per-user wipe).
  Future<void> clearAllQueueEntries() => delete(offlineQueue).go();

  /// Get the total number of entries in the offline queue.
  Future<int> getQueueSize() async {
    final countExpr = countAll();
    final query = selectOnly(offlineQueue)..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Remove the oldest [count] entries from the offline queue.
  Future<void> removeOldestEntries(int count) async {
    final oldest = await (select(offlineQueue)
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)])
          ..limit(count))
        .get();
    for (final entry in oldest) {
      await (delete(offlineQueue)..where((t) => t.id.equals(entry.id))).go();
    }
  }

  /// Remove all queue entries older than [cutoff].
  Future<void> removeEntriesOlderThan(DateTime cutoff) =>
      (delete(offlineQueue)..where((t) => t.createdAt.isSmallerThanValue(cutoff))).go();

  // ---------------------------------------------------------------------------
  // SYNC CONFLICTS
  // ---------------------------------------------------------------------------

  /// Park a conflict for manual user resolution.
  Future<int> recordConflict({
    required String entityType,
    required String entityId,
    required Map<String, dynamic> localVersion,
    required Map<String, dynamic> serverVersion,
  }) {
    return into(syncConflicts).insert(
      SyncConflictsCompanion(
        entityType: Value(entityType),
        entityId: Value(entityId),
        localVersionJson: Value(jsonEncode(localVersion)),
        serverVersionJson: Value(jsonEncode(serverVersion)),
      ),
    );
  }

  /// All currently parked conflicts, oldest first.
  Future<List<SyncConflict>> getOpenConflicts() =>
      (select(syncConflicts)
            ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
          .get();

  /// Number of currently parked conflicts.
  Future<int> getConflictCount() async {
    final countExpr = countAll();
    final query = selectOnly(syncConflicts)..addColumns([countExpr]);
    final result = await query.getSingle();
    return result.read(countExpr) ?? 0;
  }

  /// Remove a parked conflict once the user has resolved it.
  Future<int> removeConflict(int conflictId) =>
      (delete(syncConflicts)..where((t) => t.id.equals(conflictId))).go();

  /// Remove every parked conflict (used on sign-out / per-user wipe).
  Future<void> clearAllConflicts() => delete(syncConflicts).go();
}

/// Compute the on-disk filename for the per-user database, falling back to
/// a global file when no user is signed in (used for the very first launch
/// before any auth happens).
String _databaseFileName(String? userId) {
  if (userId == null || userId.isEmpty) {
    return 'havenkeep.sqlite';
  }
  // SHA-256 truncated to 16 hex chars is more than enough entropy to
  // disambiguate accounts on a single device while keeping the path short.
  final digest = sha256.convert(utf8.encode(userId));
  final shortHash = digest.toString().substring(0, 16);
  return 'havenkeep-$shortHash.sqlite';
}

/// Compute the absolute file system path Drift will use for [userId].
Future<File> resolveDatabaseFile({String? userId}) async {
  final dir = await getApplicationDocumentsDirectory();
  return File(p.join(dir.path, _databaseFileName(userId)));
}

/// Delete the per-user database file from disk (idempotent).
Future<void> deleteDatabaseFile({String? userId}) async {
  try {
    final file = await resolveDatabaseFile(userId: userId);
    if (file.existsSync()) {
      await file.delete();
    }
  } catch (e) {
    debugPrint('[HavenDatabase] Failed to delete db file: $e');
  }
}

LazyDatabase _openConnection({String? userId}) {
  return LazyDatabase(() async {
    // sqlcipher_flutter_libs ships an Android workaround required when
    // both SQLCipher and the system SQLite are linked into the same
    // process — it needs to run before sqlite3 is opened.
    if (Platform.isAndroid) {
      await applyWorkaroundToOpenSqlCipherOnOldAndroidVersions();
    }
    open.overrideFor(OperatingSystem.android, openCipherOnAndroid);
    open.overrideFor(OperatingSystem.iOS, _openCipherOnIos);

    final file = await resolveDatabaseFile(userId: userId);
    final keyBytes = await SecureStorageService.getOrCreateDbEncryptionKey();
    // S2-G: minimise the lifetime of the raw key in the Dart heap. Convert
    // to the SQLCipher `x'…'` blob literal once, zero out the byte buffer
    // immediately, and don't capture the passphrase outside the setup
    // closure. Dart's GC won't proactively zero memory for us — this is
    // best-effort under the language's memory model, but it shrinks the
    // window where a heap dump could recover the key from minutes to one
    // database open.
    return NativeDatabase(
      file,
      setup: (db) {
        // Verify SQLCipher is the linked sqlite3, then activate the key
        // before any other statement runs.
        final cipherCheck =
            db.select('PRAGMA cipher_version;');
        if (cipherCheck.isEmpty) {
          throw StateError(
            'sqlite3 is not SQLCipher — refusing to open an unencrypted '
            'HavenKeep database.',
          );
        }
        final passphrase = "x'${_bytesToHex(keyBytes)}'";
        try {
          db.execute('PRAGMA key = "$passphrase";');
        } finally {
          // Wipe the bytes; the hex string and `passphrase` go out of
          // scope when this closure returns.
          for (var i = 0; i < keyBytes.length; i++) {
            keyBytes[i] = 0;
          }
        }
      },
    );
  });
}

/// iOS ships SQLCipher via the `sqlcipher_flutter_libs` pod. The
/// Podfile uses dynamic framework linkage so SQLCipher.framework lands
/// inside the app bundle at runtime as a real .dylib — Dart's
/// `DynamicLibrary.open` resolves the bare framework name against the
/// app's @rpath search list.
///
/// We can NOT use `DynamicLibrary.process()` here because that performs
/// a global symbol lookup that also sees the system `-lsqlite3` linked
/// by `sqflite_darwin` (pulled in transitively via flutter_cache_manager).
/// The system sqlite3 wins the global lookup, Drift ends up calling
/// system sqlite3, `PRAGMA cipher_version;` returns empty, and the
/// SQLCipher guard throws "sqlite3 is not SQLCipher" — the splash-
/// stuck bug we hit on the iOS simulator.
DynamicLibrary _openCipherOnIos() =>
    DynamicLibrary.open('SQLCipher.framework/SQLCipher');

String _bytesToHex(List<int> bytes) {
  final buf = StringBuffer();
  for (final b in bytes) {
    buf.write(b.toRadixString(16).padLeft(2, '0'));
  }
  return buf.toString();
}

/// Riverpod provider for the local Drift database singleton.
///
/// The instance is bound to the currently signed-in user id so that
/// switching accounts (sign-out + sign-in) yields a fresh, isolated
/// database. The provider is invalidated by [authProvider] when auth
/// state changes.
final localDatabaseProvider = Provider<HavenDatabase>((ref) {
  // Read once at construction time. Re-reads on auth change happen via
  // explicit invalidation in the auth provider.
  final db = HavenDatabase(userId: _activeUserIdSync);
  ref.onDispose(() => db.close());
  return db;
});

/// In-memory cache of the active user id used by the database opener.
///
/// Updated by the auth flow before the local DB provider is read so that
/// the right per-user file is opened on the current process. Persistence
/// across launches is handled by [SecureStorageService.setActiveUserId].
String? _activeUserIdSync;

/// Set the active user id for subsequent [HavenDatabase] instances.
///
/// Call this BEFORE invalidating [localDatabaseProvider]; otherwise the
/// new instance will fall back to the legacy global db file.
void setActiveDatabaseUser(String? userId) {
  _activeUserIdSync = userId;
}
