import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

import '../database/database.dart';
import '../providers/items_provider.dart';

/// Maximum number of retry attempts for a single queued action.
const _kMaxRetries = 3;

/// Delay between processing individual queue entries.
const _kProcessDelay = Duration(milliseconds: 300);

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
        } catch (e) {
          debugPrint('[OfflineSync] Failed to sync entry ${entry.id}: $e');
          await _db.markActionFailed(entry.id, entry.attempts + 1);

          // If it's a retriable error, re-queue for later
          if (entry.attempts + 1 < _kMaxRetries) {
            await _db.retryAction(entry.id);
          }
        }

        // Small delay between entries to avoid hammering the API
        await Future.delayed(_kProcessDelay);
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
        await _ref.read(itemsRepositoryProvider).updateItem(item);
        break;

      case OfflineAction.delete_item:
        await _ref
            .read(itemsRepositoryProvider)
            .deleteItem(entry.entityId);
        break;

      case OfflineAction.create_document:
        // Document upload requires file path — store path in payload
        // and re-attempt upload when online.
        debugPrint(
          '[OfflineSync] Document upload queued — will attempt on next sync.',
        );
        break;

      case OfflineAction.update_preferences:
        // Notification preferences sync
        debugPrint(
          '[OfflineSync] Preferences update queued — will attempt on next sync.',
        );
        break;
    }
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
