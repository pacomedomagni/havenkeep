import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/services/offline_sync_service.dart';
import 'package:havenkeep_mobile/core/services/items_repository.dart';
import 'package:havenkeep_mobile/core/database/database.dart';
import 'package:havenkeep_mobile/core/providers/items_provider.dart';
import 'package:shared_models/shared_models.dart';
import 'package:drift/drift.dart';

import '../helpers/test_helpers.dart';
import 'offline_sync_service_test.mocks.dart';

@GenerateMocks([HavenDatabase, ItemsRepository])
void main() {
  late MockHavenDatabase mockDb;
  late MockItemsRepository mockItemsRepo;
  late ProviderContainer container;
  late OfflineSyncService service;

  setUp(() {
    mockDb = MockHavenDatabase();
    mockItemsRepo = MockItemsRepository();

    container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(mockDb),
        itemsRepositoryProvider.overrideWithValue(mockItemsRepo),
      ],
    );

    service = OfflineSyncService(mockDb, container);
  });

  tearDown(() {
    service.dispose();
    container.dispose();
  });

  OfflineQueueData createQueueEntry({
    int? id,
    String? entityType,
    String? entityId,
    String? action,
    String? payload,
    int attempts = 0,
    String status = 'pending',
  }) {
    return OfflineQueueData(
      id: id ?? 1,
      entityType: entityType ?? 'item',
      entityId: entityId ?? 'test-item-id',
      action: action ?? OfflineAction.create_item.toJson(),
      payload: payload ??
          '{"id":"test-item-id","name":"Test Item","home_id":"home-1","user_id":"user-1","category":"refrigerator","warranty_months":12,"created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z"}',
      status: status,
      attempts: attempts,
      createdAt: DateTime.now(),
    );
  }

  group('OfflineSyncService - enqueueChange', () {
    test('enqueues action to database', () async {
      final item = TestHelpers.createTestItem();

      when(mockDb.enqueueAction(any)).thenAnswer((_) async => 1);

      await service.enqueueChange(
        entityType: 'item',
        entityId: item.id,
        action: OfflineAction.create_item,
        payload: item.toJson(),
      );

      verify(mockDb.enqueueAction(any)).called(1);
    });

    test('sets status to pending for new entries', () async {
      OfflineQueueCompanion? capturedCompanion;

      when(mockDb.enqueueAction(any)).thenAnswer((invocation) {
        capturedCompanion =
            invocation.positionalArguments[0] as OfflineQueueCompanion;
        return Future.value(1);
      });

      await service.enqueueChange(
        entityType: 'item',
        entityId: 'test-id',
        action: OfflineAction.update_item,
        payload: {'test': 'data'},
      );

      expect(capturedCompanion!.status.value, 'pending');
      expect(capturedCompanion!.attempts.value, 0);
    });
  });

  group('OfflineSyncService - syncPendingChanges', () {
    test('processes pending actions in FIFO order', () async {
      final entries = [
        createQueueEntry(id: 1, action: OfflineAction.create_item.toJson()),
        createQueueEntry(id: 2, action: OfflineAction.update_item.toJson()),
        createQueueEntry(id: 3, action: OfflineAction.delete_item.toJson()),
      ];

      when(mockDb.getPendingActions()).thenAnswer((_) async => entries);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 3);

      when(mockItemsRepo.createItem(any))
          .thenAnswer((_) async => TestHelpers.createTestItem());
      when(mockItemsRepo.updateItem(any))
          .thenAnswer((_) async => TestHelpers.createTestItem());
      when(mockItemsRepo.deleteItem(any)).thenAnswer((_) async => {});

      await service.syncPendingChanges();

      verify(mockDb.getPendingActions()).called(1);
      verify(mockDb.markActionSynced(1)).called(1);
      verify(mockDb.markActionSynced(2)).called(1);
      verify(mockDb.markActionSynced(3)).called(1);
      verify(mockDb.clearSyncedActions()).called(1);
    });

    test('skips entries that exceeded max retries', () async {
      final entries = [
        createQueueEntry(id: 1, attempts: 3), // Max retries exceeded
        createQueueEntry(id: 2, attempts: 0), // Should be processed
      ];

      when(mockDb.getPendingActions()).thenAnswer((_) async => entries);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any))
          .thenAnswer((_) async => TestHelpers.createTestItem());

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 3)).called(1);
      verify(mockDb.markActionSynced(2)).called(1);
      verifyNever(mockDb.markActionSynced(1));
    });

    test('retries failed actions up to max attempts', () async {
      final entry = createQueueEntry(id: 1, attempts: 1);

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.retryAction(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Network error'));

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 2)).called(1);
      verify(mockDb.retryAction(1)).called(1);
    });

    test('does not retry when max attempts reached', () async {
      final entry = createQueueEntry(id: 1, attempts: 2); // Will be 3 after fail

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Network error'));

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 3)).called(1);
      verifyNever(mockDb.retryAction(any));
    });

    test('prevents concurrent syncs', () async {
      when(mockDb.getPendingActions()).thenAnswer((_) async {
        // Simulate long-running sync
        await Future.delayed(const Duration(milliseconds: 100));
        return [];
      });
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      // Start first sync
      final firstSync = service.syncPendingChanges();

      // Try to start second sync while first is running
      await service.syncPendingChanges();

      // Wait for first to complete
      await firstSync;

      // Should only call getPendingActions once
      verify(mockDb.getPendingActions()).called(1);
    });

    test('clears synced actions after processing', () async {
      when(mockDb.getPendingActions()).thenAnswer((_) async => []);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 5);

      await service.syncPendingChanges();

      verify(mockDb.clearSyncedActions()).called(1);
    });

    test('sets isSyncing flag during sync', () async {
      when(mockDb.getPendingActions()).thenAnswer((_) async {
        expect(service.isSyncing, isTrue);
        return [];
      });
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      expect(service.isSyncing, isFalse);

      await service.syncPendingChanges();

      expect(service.isSyncing, isFalse);
    });
  });

  group('OfflineSyncService - action processing', () {
    test('processes create_item action', () async {
      final item = TestHelpers.createTestItem();
      final entry = createQueueEntry(
        action: OfflineAction.create_item.toJson(),
        payload: item.toJson().toString(),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any))
          .thenAnswer((_) async => item);

      await service.syncPendingChanges();

      verify(mockItemsRepo.createItem(any)).called(1);
      verify(mockDb.markActionSynced(entry.id)).called(1);
    });

    test('processes update_item action', () async {
      final item = TestHelpers.createTestItem();
      final entry = createQueueEntry(
        action: OfflineAction.update_item.toJson(),
        payload: item.toJson().toString(),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.updateItem(any))
          .thenAnswer((_) async => item);

      await service.syncPendingChanges();

      verify(mockItemsRepo.updateItem(any)).called(1);
      verify(mockDb.markActionSynced(entry.id)).called(1);
    });

    test('processes delete_item action', () async {
      final entry = createQueueEntry(
        action: OfflineAction.delete_item.toJson(),
        entityId: 'item-to-delete',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.deleteItem('item-to-delete'))
          .thenAnswer((_) async => {});

      await service.syncPendingChanges();

      verify(mockItemsRepo.deleteItem('item-to-delete')).called(1);
      verify(mockDb.markActionSynced(entry.id)).called(1);
    });

    test('handles create_document action gracefully', () async {
      final entry = createQueueEntry(
        action: OfflineAction.create_document.toJson(),
        payload: '{"file_path":"/path/to/doc.pdf"}',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      // Document upload is not yet implemented, should not throw
      await service.syncPendingChanges();

      verify(mockDb.markActionSynced(entry.id)).called(1);
    });

    test('handles update_preferences action gracefully', () async {
      final entry = createQueueEntry(
        action: OfflineAction.update_preferences.toJson(),
        payload: '{"notifications_enabled":true}',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      // Preferences sync not yet implemented, should not throw
      await service.syncPendingChanges();

      verify(mockDb.markActionSynced(entry.id)).called(1);
    });
  });

  group('OfflineSyncService - error handling', () {
    test('marks action as failed on repository error', () async {
      final entry = createQueueEntry(id: 1, attempts: 0);

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.retryAction(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Repository error'));

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 1)).called(1);
      verify(mockDb.retryAction(1)).called(1);
    });

    test('continues processing after single entry failure', () async {
      final entries = [
        createQueueEntry(id: 1), // Will fail
        createQueueEntry(id: 2), // Should still be processed
      ];

      when(mockDb.getPendingActions()).thenAnswer((_) async => entries);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.retryAction(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any)).thenAnswer((invocation) {
        // First call fails, second succeeds
        final item = invocation.positionalArguments[0] as Item;
        if (item.id == 'test-item-id') {
          throw Exception('Network error');
        }
        return Future.value(item);
      });

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 1)).called(1);
      verify(mockDb.markActionSynced(2)).called(1);
    });

    test('handles JSON decode errors gracefully', () async {
      final entry = createQueueEntry(
        payload: 'invalid-json{{{',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.retryAction(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(entry.id, 1)).called(1);
    });
  });

  group('OfflineSyncService - lifecycle', () {
    test('starts listening on start()', () {
      // Just verify it doesn't throw
      expect(() => service.start(), returnsNormally);
    });

    test('stops listening on dispose()', () {
      service.start();
      expect(() => service.dispose(), returnsNormally);
    });

    test('can be started and stopped multiple times', () {
      service.start();
      service.dispose();
      service.start();
      service.dispose();
    });
  });

  group('OfflineSyncService - integration', () {
    test('complete flow: enqueue, sync, mark synced', () async {
      final item = TestHelpers.createTestItem();

      // Enqueue
      when(mockDb.enqueueAction(any)).thenAnswer((_) async => 1);

      await service.enqueueChange(
        entityType: 'item',
        entityId: item.id,
        action: OfflineAction.create_item,
        payload: item.toJson(),
      );

      // Sync
      final entry = createQueueEntry(
        id: 1,
        payload: item.toJson().toString(),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(1)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any))
          .thenAnswer((_) async => item);

      await service.syncPendingChanges();

      verify(mockDb.enqueueAction(any)).called(1);
      verify(mockItemsRepo.createItem(any)).called(1);
      verify(mockDb.markActionSynced(1)).called(1);
      verify(mockDb.clearSyncedActions()).called(1);
    });

    test('handles multiple sequential syncs correctly', () async {
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      // First sync with entries
      when(mockDb.getPendingActions()).thenAnswer((_) async => [
            createQueueEntry(id: 1),
          ]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockItemsRepo.createItem(any))
          .thenAnswer((_) async => TestHelpers.createTestItem());

      await service.syncPendingChanges();

      // Second sync with no entries
      when(mockDb.getPendingActions()).thenAnswer((_) async => []);

      await service.syncPendingChanges();

      verify(mockDb.getPendingActions()).called(2);
      verify(mockDb.clearSyncedActions()).called(2);
    });
  });
}
