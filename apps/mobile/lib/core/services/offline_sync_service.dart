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
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final isOnline = results.any((r) => r != ConnectivityResult.none);
      if (isOnline && !_isSyncing) {
        syncPendingChanges();
      }
    });
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
  bool _isNonRetriableClientError(int statusCode) {
    return statusCode == 400 ||
        statusCode == 401 ||
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
    _isSyncing = true;

    try {
      final pending = await _db.getPendingActions();

      for (final entry in pending) {
        if (entry.attempts >= _kMaxRetries) {
          await _db.markActionFailed(entry.id, entry.attempts);
          continue;
        }

        try {
          await _processEntry(entry);
          await _db.markActionSynced(entry.id);
        } on ApiException catch (e) {
          debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');

          // Don't retry on 4xx client errors - mark as failed immediately
          if (_isNonRetriableClientError(e.statusCode)) {
            await _db.markActionFailed(entry.id, entry.attempts + 1);
            continue;
          }

          await _db.markActionFailed(entry.id, entry.attempts + 1);

          // If it's a retriable error (5xx / network), re-queue for later
          if (entry.attempts + 1 < _kMaxRetries) {
            await _db.retryAction(entry.id);
          }
        } catch (e) {
          debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');
          await _db.markActionFailed(entry.id, entry.attempts + 1);

          // Network errors are retriable
          if (entry.attempts + 1 < _kMaxRetries) {
            await _db.retryAction(entry.id);
          }
        }

        // Exponential backoff delay between entries
        await Future.delayed(_backoffDelay(entry.attempts));
      }

      // Clean up synced entries
      await _db.clearSyncedActions();
    } finally {
      _isSyncing = false;
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
            // 409 Conflict: server version differs — resolve using ConflictResolver
            await _resolveUpdateConflict(item);
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

  /// Resolve a 409 conflict for an update_item action using ConflictResolver.
  Future<void> _resolveUpdateConflict(Item localItem) async {
    try {
      // Fetch the current server version
      final serverItem = await _ref
          .read(itemsRepositoryProvider)
          .getItemById(localItem.id);

      // Verify there's an actual conflict by comparing timestamps
      if (!ConflictResolver.hasConflict(localItem, serverItem)) {
        // No real conflict — server accepted our version or timestamps match.
        // Just push the local version again.
        await _ref.read(itemsRepositoryProvider).updateItem(localItem);
        debugPrint(
          '[OfflineSync] No actual conflict for item ${localItem.id} — retried update.',
        );
        return;
      }

      final conflict = Conflict<Item>(
        localVersion: localItem,
        serverVersion: serverItem,
      );

      // Choose strategy: if auto-resolvable (non-overlapping fields), use merge;
      // otherwise fall back to mostRecent
      final strategy = ConflictResolver.canAutoResolve(conflict)
          ? ConflictResolutionStrategy.merge
          : ConflictResolutionStrategy.mostRecent;

      final resolved = ConflictResolver.resolveItem(conflict, strategy);

      // Push the resolved version to the server
      await _ref.read(itemsRepositoryProvider).updateItem(resolved);

      debugPrint(
        '[OfflineSync] Conflict resolved for item ${localItem.id} using $strategy strategy.',
      );
    } catch (e) {
      debugPrint('[OfflineSync] Conflict resolution failed for item ${localItem.id}: $e');
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
        '[OfflineSync] File no longer exists at $filePath — marking entry ${entry.id} as failed.',
      );
      throw ApiException(400, 'File no longer exists at $filePath');
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
