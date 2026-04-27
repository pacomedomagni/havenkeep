import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:uuid/uuid.dart';

import '../database/database.dart';
import '../providers/auth_provider.dart';
import '../providers/documents_provider.dart';
import '../providers/items_provider.dart';
import '../providers/notifications_provider.dart';
import '../utils/conflict_resolver.dart';

/// Maximum number of retry attempts for a single queued action.
const _kMaxRetries = 3;

/// Base delay in milliseconds for exponential backoff.
const _kBaseDelayMs = 300;

/// Maximum delay cap in milliseconds for exponential backoff.
const _kMaxDelayMs = 30000;

/// Maximum number of entries allowed in the offline queue.
const _kMaxQueueSize = 500;

/// Number of oldest entries to remove when the queue exceeds _kMaxQueueSize.
const _kQueueEvictionCount = 100;

/// Maximum age in days for queue entries before they are considered stale.
const _kMaxQueueEntryAgeDays = 7;

/// Error indicating a non-retriable failure (e.g., missing local file).
/// These should be marked as permanently failed without retry.
class NonRetriableError implements Exception {
  final String message;
  NonRetriableError(this.message);

  @override
  String toString() => 'NonRetriableError: $message';
}

/// Manages offline sync — listens for connectivity changes and processes
/// pending queue entries when the device comes online.
///
/// The connectivity listener is gated on auth (C103): we deliberately do
/// not subscribe until [isAuthenticatedProvider] reports `true`, and we
/// tear the subscription down on sign-out. Without this, the service
/// would drain queued mutations against an empty/unauthenticated session
/// — the queue belongs to a specific user and we can't know which user
/// it belongs to until auth resolves.
class OfflineSyncService {
  final HavenDatabase _db;
  final Ref _ref;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  ProviderSubscription<bool>? _authSub;
  bool _isSyncing = false;

  OfflineSyncService(this._db, this._ref);

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Start the auth-gated connectivity loop.
  ///
  /// Subscribes to [isAuthenticatedProvider] first; the connectivity
  /// stream is only attached once auth flips to `true` and is detached
  /// again on `false`. This ensures we never read or mutate the
  /// per-user queue rows while the user is signed out.
  void start() {
    _authSub = _ref.listen<bool>(
      isAuthenticatedProvider,
      (previous, isAuthenticated) {
        if (isAuthenticated) {
          _attachConnectivityListener();
          // The user just signed in (or was restored) — drain anything
          // queued from the previous online session.
          syncPendingChanges();
        } else {
          _detachConnectivityListener();
        }
      },
      fireImmediately: true,
    );
  }

  void _attachConnectivityListener() {
    if (_connectivitySub != null) return;
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      (results) {
        final isOnline = results.any((r) => r != ConnectivityResult.none);
        // The `_isSyncing` flag inside [syncPendingChanges] is the only
        // re-entry guard we need — kicking off a new call while one is
        // running is a no-op, and the in-progress run will pick up any
        // entries enqueued before it finishes.
        if (isOnline) {
          syncPendingChanges();
        }
      },
      onError: (e) {
        debugPrint('[OfflineSync] Connectivity stream error: $e');
      },
    );
  }

  void _detachConnectivityListener() {
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  /// Stop listening.
  void dispose() {
    _detachConnectivityListener();
    _authSub?.close();
    _authSub = null;
  }

  /// Subdirectory inside the app-support directory where queued document
  /// uploads are persisted. Files in here outlive the OS-managed temp
  /// directory so an app kill mid-upload doesn't lose user data (C106).
  static const _kQueuedUploadsDir = 'queued_uploads';

  /// Copy [sourcePath] into the app-support directory under a stable
  /// name and return the new absolute path. The persisted file is what
  /// gets stored in the offline queue payload — `getTemporaryDirectory`
  /// can be wiped by the OS at any point, so we'd lose the upload if we
  /// kept the original path. The filename derives from the source path
  /// hash so re-queueing the same file reuses the same persisted copy
  /// (idempotent on the file system side).
  Future<String> persistUploadFile(String sourcePath) async {
    final appSupport = await getApplicationSupportDirectory();
    final dir = Directory(p.join(appSupport.path, _kQueuedUploadsDir));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final source = File(sourcePath);
    if (!source.existsSync()) {
      throw NonRetriableError(
        'Source file no longer exists at $sourcePath',
      );
    }
    final hash =
        sha256.convert(utf8.encode(sourcePath)).toString().substring(0, 16);
    final ext = p.extension(sourcePath);
    final destPath = p.join(dir.path, '$hash$ext');
    final dest = File(destPath);
    if (!dest.existsSync()) {
      await source.copy(destPath);
    }
    return destPath;
  }

  /// Delete a previously persisted upload file. Idempotent — failures are
  /// swallowed because a missing file just means the cleanup already
  /// happened.
  Future<void> _deletePersistedUpload(String? path) async {
    if (path == null) return;
    try {
      final appSupport = await getApplicationSupportDirectory();
      final queuedDir = p.join(appSupport.path, _kQueuedUploadsDir);
      // Belt-and-braces: only delete files inside our managed directory.
      // We don't want a malformed payload to delete something else on disk.
      if (!p.isWithin(queuedDir, path) && p.dirname(path) != queuedDir) {
        return;
      }
      final file = File(path);
      if (file.existsSync()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('[OfflineSync] Failed to delete persisted upload $path: $e');
    }
  }

  /// Enqueue an offline action for later sync.
  Future<void> enqueueChange({
    required String entityType,
    required String entityId,
    required OfflineAction action,
    required Map<String, dynamic> payload,
  }) async {
    // Limit queue to _kMaxQueueSize entries to prevent unbounded growth
    final queueSize = await _db.getQueueSize();
    if (queueSize >= _kMaxQueueSize) {
      debugPrint(
        '[OfflineSync] Queue size ($queueSize) exceeds limit ($_kMaxQueueSize). '
        'Removing $_kQueueEvictionCount oldest entries.',
      );
      await _db.removeOldestEntries(_kQueueEvictionCount);
    }

    // S2-E: stamp a UUID at enqueue time so the same key flows through
    // every retry of this entry. Server-side idempotency middleware uses
    // (user_id, route_key, idempotency_key) to collapse duplicate writes.
    final idempotencyKey = const Uuid().v4();

    await _db.enqueueAction(OfflineQueueCompanion(
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action.toJson()),
      payload: Value(jsonEncode(payload)),
      status: const Value('pending'),
      createdAt: Value(DateTime.now()),
      attempts: const Value(0),
      idempotencyKey: Value(idempotencyKey),
    ));
  }

  /// Compute exponential backoff delay for the given attempt number.
  Duration _backoffDelay(int attempts) {
    final delayMs = math.min(
      _kBaseDelayMs * math.pow(2, attempts).toInt(),
      _kMaxDelayMs,
    );
    return Duration(milliseconds: delayMs);
  }

  /// Process all pending queue entries in FIFO order.
  Future<void> syncPendingChanges() async {
    if (_isSyncing) return;

    // Skip sync if user is not authenticated
    final isAuthenticated = _ref.read(isAuthenticatedProvider);
    if (!isAuthenticated) {
      debugPrint('[OfflineSync] Skipping sync — user is not authenticated');
      return;
    }

    _isSyncing = true;

    // Track which entity domains were touched so we can invalidate the
    // matching notifiers once the sync run finishes. Without this, queue
    // entries that succeed server-side don't reach the UI until the user
    // pulls to refresh — see C107.
    final touched = <_SyncedDomain>{};

    try {
      // Remove stale entries older than _kMaxQueueEntryAgeDays days
      final staleCutoff = DateTime.now().subtract(
        const Duration(days: _kMaxQueueEntryAgeDays),
      );
      await _db.removeEntriesOlderThan(staleCutoff);

      final pending = await _db.getPendingActions();

      for (final entry in pending) {
        if (entry.attempts >= _kMaxRetries) {
          await _db.markActionFailed(entry.id, entry.attempts);
          continue;
        }

        try {
          // S2-C: flip to `in_flight` *before* the network call. If the
          // process is killed between now and the markActionSynced below,
          // the next run will pick this entry back up via getPendingActions
          // and re-send with the same idempotency key — the server's
          // request_idempotency cache will return the cached response
          // without duplicating the underlying write.
          await _db.markActionInFlight(entry.id);
          await _processEntry(entry);
          await _db.markActionSynced(entry.id);
          final domain = _domainFor(entry.action);
          if (domain != null) touched.add(domain);
        } on NonRetriableError catch (e) {
          // Non-retriable errors (e.g., missing local file) — mark as permanently failed
          debugPrint('[OfflineSync] Non-retriable error for entry ${entry.id}: $e');
          await _db.markActionFailed(entry.id, _kMaxRetries);
        } on ApiException catch (e) {
          debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');

          // Switch over the sealed hierarchy so the compiler tells us when
          // a new failure mode is added that we'd otherwise mis-bucket.
          switch (e) {
            case ApiAuthRequiredException():
              // 401 Unauthorized: one extra retry — the ApiClient auto-refresh
              // may resolve the token issue. Bump the attempt counter and keep
              // the row pending with a single UPDATE so we never write a
              // transient `failed` we'd immediately flip back.
              if (entry.attempts == 0) {
                debugPrint('[OfflineSync] 401 on entry ${entry.id} — scheduling one retry');
                await _db.reschedulePending(entry.id, entry.attempts + 1);
                await Future.delayed(_backoffDelay(entry.attempts + 1));
              } else {
                debugPrint('[OfflineSync] 401 retry failed for entry ${entry.id} — marking permanently failed');
                await _db.markActionFailed(entry.id, _kMaxRetries);
              }
              continue;

            case ApiForbiddenException():
            case ApiNotFoundException():
            case ApiValidationException():
              // Client errors with no path to recovery. Drop them.
              debugPrint('[OfflineSync] Non-retriable client error ${e.statusCode} for entry ${entry.id} — marking permanently failed');
              await _db.markActionFailed(entry.id, _kMaxRetries);
              continue;

            case ApiConflictException():
            case ApiRateLimitedException():
            case ApiServerException():
            case ApiNetworkException():
            case ApiTimeoutException():
            case ApiUnknownException():
              // Retriable errors (5xx / network / 429 / 409): reschedule with
              // bumped attempt count, then back off before the next entry.
              final nextAttempts = entry.attempts + 1;
              if (nextAttempts < _kMaxRetries) {
                await _db.reschedulePending(entry.id, nextAttempts);
                await Future.delayed(_backoffDelay(nextAttempts));
              } else {
                await _db.markActionFailed(entry.id, nextAttempts);
              }
          }
        } catch (e) {
          debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');
          final nextAttempts = entry.attempts + 1;
          if (nextAttempts < _kMaxRetries) {
            await _db.reschedulePending(entry.id, nextAttempts);
            await Future.delayed(_backoffDelay(nextAttempts));
          } else {
            await _db.markActionFailed(entry.id, nextAttempts);
          }
        }
      }

      // Clean up synced entries
      await _db.clearSyncedActions();
    } finally {
      _isSyncing = false;
      _invalidateTouched(touched);
    }
  }

  /// Map an [OfflineAction] string to the notifier-domain it mutates so
  /// the sync loop knows which providers to invalidate (C107).
  _SyncedDomain? _domainFor(String actionJson) {
    final action = OfflineAction.fromJson(actionJson);
    switch (action) {
      case OfflineAction.create_item:
      case OfflineAction.update_item:
      case OfflineAction.delete_item:
        return _SyncedDomain.items;
      case OfflineAction.create_document:
        return _SyncedDomain.documents;
      case OfflineAction.update_preferences:
        return _SyncedDomain.notificationPreferences;
    }
  }

  /// Invalidate the matching notifier(s) so the UI reflects mutations
  /// that landed server-side via the queue. Each invalidation is wrapped
  /// in a try/catch so a notifier that hasn't been read this session
  /// can't break the sync loop's clean shutdown.
  void _invalidateTouched(Set<_SyncedDomain> domains) {
    for (final domain in domains) {
      try {
        switch (domain) {
          case _SyncedDomain.items:
            _ref.invalidate(itemsProvider);
            break;
          case _SyncedDomain.documents:
            _ref.invalidate(allDocumentsProvider);
            break;
          case _SyncedDomain.notificationPreferences:
            _ref.invalidate(notificationPreferencesProvider);
            break;
        }
      } catch (e) {
        debugPrint('[OfflineSync] Invalidate $domain failed: $e');
      }
    }
  }

  /// Process a single queue entry by dispatching to the appropriate repository.
  ///
  /// Threads [OfflineQueueData.idempotencyKey] through every mutating call so
  /// that a re-sent in-flight entry collapses to the original write
  /// server-side. Entries enqueued before the schema-v4 migration have a
  /// null key and degrade gracefully (server treats them as non-idempotent).
  Future<void> _processEntry(OfflineQueueData entry) async {
    late final OfflineAction action;
    late final Map<String, dynamic> payload;
    try {
      action = OfflineAction.fromJson(entry.action);
      payload = jsonDecode(entry.payload) as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[OfflineSync] Skipping malformed entry ${entry.id}: $e');
      return;
    }

    final idempotencyKey = entry.idempotencyKey;

    switch (action) {
      case OfflineAction.create_item:
        final item = Item.fromJson(payload);
        await _ref
            .read(itemsRepositoryProvider)
            .createItem(item, idempotencyKey: idempotencyKey);
        break;

      case OfflineAction.update_item:
        final item = Item.fromJson(payload);
        try {
          await _ref
              .read(itemsRepositoryProvider)
              .updateItem(item, idempotencyKey: idempotencyKey);
        } on ApiConflictException {
          // 409 Conflict: server version differs — park the divergence
          // for the user to resolve. We deliberately do NOT silently
          // last-write-wins.
          await _parkUpdateConflict(item);
        }
        break;

      case OfflineAction.delete_item:
        await _ref
            .read(itemsRepositoryProvider)
            .deleteItem(entry.entityId, idempotencyKey: idempotencyKey);
        break;

      case OfflineAction.create_document:
        await _processDocumentUpload(entry, payload);
        break;

      case OfflineAction.update_preferences:
        final prefs = NotificationPreferences.fromJson(payload);
        await _ref
            .read(notificationsRepositoryProvider)
            .upsertPreferences(prefs, idempotencyKey: idempotencyKey);
        break;
    }
  }

  /// Park a 409 conflict for an update_item action so the user can
  /// resolve it manually. If the timestamps actually match (server
  /// already accepted our version), simply retry the push.
  Future<void> _parkUpdateConflict(Item localItem) async {
    try {
      final serverItem = await _ref
          .read(itemsRepositoryProvider)
          .getItemById(localItem.id);

      if (!ConflictResolver.hasConflict(localItem, serverItem)) {
        await _ref.read(itemsRepositoryProvider).updateItem(localItem);
        debugPrint(
          '[OfflineSync] No actual conflict for item ${localItem.id} — retried update.',
        );
        return;
      }

      await _db.recordConflict(
        entityType: 'item',
        entityId: localItem.id,
        localVersion: localItem.toJson(),
        serverVersion: serverItem.toJson(),
      );

      // Bump the unread-conflict signal so the UI can surface a banner.
      _ref
          .read(syncConflictCountProvider.notifier)
          .state = await _db.getConflictCount();

      debugPrint(
        '[OfflineSync] Parked conflict for item ${localItem.id} — awaiting user resolution.',
      );
    } catch (e) {
      debugPrint('[OfflineSync] Failed to park conflict for item ${localItem.id}: $e');
      rethrow;
    }
  }

  /// Process a queued document upload action.
  Future<void> _processDocumentUpload(
    OfflineQueueData entry,
    Map<String, dynamic> payload,
  ) async {
    final filePath = payload['filePath'] as String?;
    final itemId = payload['itemId'] as String?;
    final fileName = payload['fileName'] as String?;
    final typeStr = payload['type'] as String?;

    if (filePath == null || itemId == null) {
      debugPrint(
        '[OfflineSync] Document upload entry ${entry.id} missing required fields.',
      );
      throw NonRetriableError('Missing filePath or itemId in payload');
    }

    // Check if the file still exists on disk
    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint(
        '[OfflineSync] File no longer exists at $filePath — marking entry ${entry.id} as permanently failed.',
      );
      throw NonRetriableError('File no longer exists at $filePath');
    }

    final docType = typeStr != null
        ? DocumentType.fromJson(typeStr)
        : DocumentType.other;

    await _ref.read(documentsRepositoryProvider).uploadDocument(
          itemId: itemId,
          filePath: filePath,
          fileName: fileName ?? file.uri.pathSegments.last,
          type: docType,
          idempotencyKey: entry.idempotencyKey,
        );

    // Upload landed — drop the persisted copy. We only delete inside the
    // managed `queued_uploads` directory so an entry pointing at the
    // original gallery path never deletes a user's file.
    await _deletePersistedUpload(filePath);

    debugPrint(
      '[OfflineSync] Document uploaded successfully for item $itemId.',
    );
  }
}

/// Provider for the offline sync service.
final offlineSyncServiceProvider = Provider<OfflineSyncService>((ref) {
  final db = ref.read(localDatabaseProvider);
  final service = OfflineSyncService(db, ref);
  service.start();
  // Hydrate the conflict count from disk so the settings banner is
  // accurate the moment the user opens the app, not just after the
  // first 409 lands this session.
  () async {
    try {
      final count = await db.getConflictCount();
      ref.read(syncConflictCountProvider.notifier).state = count;
    } catch (_) {
      // Best-effort; the UI will pick up the count when conflicts arrive.
    }
  }();
  ref.onDispose(() => service.dispose());
  return service;
});

/// Whether a sync is currently in progress.
final isSyncingProvider = Provider<bool>((ref) {
  return ref.watch(offlineSyncServiceProvider).isSyncing;
});

/// Number of parked sync conflicts awaiting user resolution.
///
/// Updated by [OfflineSyncService] when a 409 is parked, and by the UI
/// after the user resolves a conflict. Initial value is 0; the UI may
/// hydrate it on startup by calling
/// `ref.read(localDatabaseProvider).getConflictCount()`.
final syncConflictCountProvider = StateProvider<int>((ref) => 0);

/// Open conflicts that the user needs to resolve. Re-reads on every
/// invalidation — call `ref.invalidate(openSyncConflictsProvider)` after
/// resolving one to refresh the list.
final openSyncConflictsProvider =
    FutureProvider<List<SyncConflict>>((ref) async {
  // Re-fetch when the count changes (a new 409 lands).
  ref.watch(syncConflictCountProvider);
  return ref.read(localDatabaseProvider).getOpenConflicts();
});

/// Per-domain invalidation buckets used by [OfflineSyncService] so the
/// service can map queued actions to the providers that hold their
/// reactive cache and refresh exactly those when the run finishes.
enum _SyncedDomain { items, documents, notificationPreferences }
