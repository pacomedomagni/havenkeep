import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:api_client/api_client.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

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
class OfflineSyncService {
  final HavenDatabase _db;
  final Ref _ref;

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _isSyncing = false;

  OfflineSyncService(this._db, this._ref);

  /// Whether a sync is currently in progress.
  bool get isSyncing => _isSyncing;

  /// Start listening for connectivity changes.
  void start() {
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

  /// Stop listening.
  void dispose() {
    _connectivitySub?.cancel();
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

    await _db.enqueueAction(OfflineQueueCompanion(
      entityType: Value(entityType),
      entityId: Value(entityId),
      action: Value(action.toJson()),
      payload: Value(jsonEncode(payload)),
      status: const Value('pending'),
      createdAt: Value(DateTime.now()),
      attempts: const Value(0),
    ));
  }

  /// Whether a status code is a client error that should not be retried.
  /// Note: 401 is excluded here — it is handled separately to allow one
  /// retry (the ApiClient auto-refresh may resolve it).
  bool _isNonRetriableClientError(int statusCode) {
    return statusCode == 400 ||
        statusCode == 403 ||
        statusCode == 404;
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

          // 401 Unauthorized: attempt one retry — the ApiClient auto-refresh
          // may resolve the token issue. Bump the attempt counter and keep
          // the row in `pending` with a single UPDATE so we never write a
          // transient `failed` we'd immediately flip back.
          if (e.statusCode == 401) {
            if (entry.attempts == 0) {
              debugPrint('[OfflineSync] 401 on entry ${entry.id} — scheduling one retry');
              await _db.reschedulePending(entry.id, entry.attempts + 1);
              await Future.delayed(_backoffDelay(entry.attempts + 1));
            } else {
              debugPrint('[OfflineSync] 401 retry failed for entry ${entry.id} — marking permanently failed');
              await _db.markActionFailed(entry.id, _kMaxRetries);
            }
            continue;
          }

          // Don't retry on other 4xx client errors - mark as permanently failed
          if (_isNonRetriableClientError(e.statusCode)) {
            debugPrint('[OfflineSync] Non-retriable client error ${e.statusCode} for entry ${entry.id} — marking permanently failed');
            await _db.markActionFailed(entry.id, _kMaxRetries);
            continue;
          }

          // Retriable error (5xx / network): reschedule with bumped attempt
          // count using a single update, then back off before processing
          // the next entry. Backoff is scoped to THIS entry's retry only.
          final nextAttempts = entry.attempts + 1;
          if (nextAttempts < _kMaxRetries) {
            await _db.reschedulePending(entry.id, nextAttempts);
            await Future.delayed(_backoffDelay(nextAttempts));
          } else {
            await _db.markActionFailed(entry.id, nextAttempts);
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

    switch (action) {
      case OfflineAction.create_item:
        final item = Item.fromJson(payload);
        await _ref.read(itemsRepositoryProvider).createItem(item);
        break;

      case OfflineAction.update_item:
        final item = Item.fromJson(payload);
        try {
          await _ref.read(itemsRepositoryProvider).updateItem(item);
        } on ApiException catch (e) {
          if (e.isConflict) {
            // 409 Conflict: server version differs — park the divergence
            // for the user to resolve. We deliberately do NOT silently
            // last-write-wins.
            await _parkUpdateConflict(item);
          } else {
            rethrow;
          }
        }
        break;

      case OfflineAction.delete_item:
        await _ref
            .read(itemsRepositoryProvider)
            .deleteItem(entry.entityId);
        break;

      case OfflineAction.create_document:
        await _processDocumentUpload(entry, payload);
        break;

      case OfflineAction.update_preferences:
        final prefs = NotificationPreferences.fromJson(payload);
        await _ref.read(notificationsRepositoryProvider).upsertPreferences(prefs);
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
      throw ApiException(400, 'Missing filePath or itemId in payload');
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
        );

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

/// Per-domain invalidation buckets used by [OfflineSyncService] so the
/// service can map queued actions to the providers that hold their
/// reactive cache and refresh exactly those when the run finishes.
enum _SyncedDomain { items, documents, notificationPreferences }
