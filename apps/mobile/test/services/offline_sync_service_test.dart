import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/services/offline_sync_service.dart';
import 'package:havenkeep_mobile/core/services/items_repository.dart';
import 'package:havenkeep_mobile/core/services/notifications_repository.dart';
import 'package:havenkeep_mobile/core/database/database.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/providers/items_provider.dart';
import 'package:havenkeep_mobile/core/providers/notifications_provider.dart';
import 'package:shared_models/shared_models.dart';
import '../helpers/test_helpers.dart';
import 'offline_sync_service_test.mocks.dart';

class _MockNotificationsRepository extends Mock
    implements NotificationsRepository {
  // Override to handle Mockito's null-unsafe `any` matcher with non-nullable
  // NotificationPreferences parameter.
  @override
  Future<NotificationPreferences> upsertPreferences(
    NotificationPreferences prefs, {
    String? idempotencyKey,
  }) {
    final epoch = DateTime.utc(1970);
    final fallback = NotificationPreferences(
      userId: 'test-user',
      createdAt: epoch,
      updatedAt: epoch,
    );
    return super.noSuchMethod(
      Invocation.method(
        #upsertPreferences,
        [prefs],
        {#idempotencyKey: idempotencyKey},
      ),
      returnValue: Future.value(fallback),
      returnValueForMissingStub: Future.value(fallback),
    ) as Future<NotificationPreferences>;
  }
}

/// A provider used solely to capture a [Ref] for constructing the
/// [OfflineSyncService] in tests.
final _testRefProvider = Provider<Ref>((ref) => ref);

@GenerateMocks([HavenDatabase, ItemsRepository])
void main() {
  // Register fallback for non-nullable types used with Mockito's `any` matcher.
  // `createdAt` and `updatedAt` are required after Phase 8 — use the epoch.
  final epoch = DateTime.utc(1970);
  provideDummy(NotificationPreferences(
    userId: '',
    createdAt: epoch,
    updatedAt: epoch,
  ));

  // Required for Connectivity plugin used by OfflineSyncService.start()
  WidgetsFlutterBinding.ensureInitialized();

  late MockHavenDatabase mockDb;
  late MockItemsRepository mockItemsRepo;
  late _MockNotificationsRepository mockNotificationsRepo;
  late ProviderContainer container;
  late OfflineSyncService service;

  setUp(() {
    mockDb = MockHavenDatabase();
    mockItemsRepo = MockItemsRepository();
    mockNotificationsRepo = _MockNotificationsRepository();

    container = ProviderContainer(
      overrides: [
        localDatabaseProvider.overrideWithValue(mockDb),
        itemsRepositoryProvider.overrideWithValue(mockItemsRepo),
        notificationsRepositoryProvider
            .overrideWithValue(mockNotificationsRepo),
        // syncPendingChanges checks auth state before syncing
        isAuthenticatedProvider.overrideWithValue(true),
      ],
    );

    // Stub queue-size check used by enqueueChange
    when(mockDb.getQueueSize()).thenAnswer((_) async => 0);
    // Stub stale-entry cleanup used by syncPendingChanges
    when(mockDb.removeEntriesOlderThan(any)).thenAnswer((_) async {});
    // Default stub for the auth-gated sync triggered when start() runs
    // with `fireImmediately: true` against the authenticated override.
    // Per-test overrides re-stub this when they need a different list.
    when(mockDb.getPendingActions()).thenAnswer((_) async => []);
    when(mockDb.clearSyncedActions()).thenAnswer((_) async {});

    final ref = container.read(_testRefProvider);
    service = OfflineSyncService(mockDb, ref);
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
      // Item.fromJson now requires `purchase_date` and `warranty_end_date`
      // (Ch08-Item-D010) — both are NOT NULL on the wire.
      payload: payload ??
          '{"id":"test-item-id","name":"Test Item","home_id":"home-1","user_id":"user-1","category":"refrigerator","purchase_date":"2026-01-01","warranty_months":12,"warranty_end_date":"2027-01-01","created_at":"2026-01-01T00:00:00.000Z","updated_at":"2026-01-01T00:00:00.000Z"}',
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

    test('reschedules transient failures up to max attempts', () async {
      final entry = createQueueEntry(id: 1, attempts: 1);

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.reschedulePending(any, any)).thenAnswer((_) async {});
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Network error'));

      await service.syncPendingChanges();

      // Single status write: row stays `pending` with bumped attempt count.
      verify(mockDb.reschedulePending(1, 2)).called(1);
      verifyNever(mockDb.markActionFailed(any, any));
    });

    test('marks failed when max attempts reached', () async {
      final entry =
          createQueueEntry(id: 1, attempts: 2); // Will be 3 after fail

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.reschedulePending(any, any)).thenAnswer((_) async {});
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Network error'));

      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(1, 3)).called(1);
      verifyNever(mockDb.reschedulePending(any, any));
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
        payload: jsonEncode(item.toJson()),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any)).thenAnswer((_) async => item);

      await service.syncPendingChanges();

      verify(mockItemsRepo.createItem(any)).called(1);
      verify(mockDb.markActionSynced(entry.id)).called(1);
    });

    test('processes update_item action', () async {
      final item = TestHelpers.createTestItem();
      final entry = createQueueEntry(
        action: OfflineAction.update_item.toJson(),
        payload: jsonEncode(item.toJson()),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.updateItem(any)).thenAnswer((_) async => item);

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

    test('handles create_document with missing fields gracefully', () async {
      final entry = createQueueEntry(
        action: OfflineAction.create_document.toJson(),
        payload: '{"file_path":"/path/to/doc.pdf"}',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      // Missing required filePath/itemId → non-retriable 400 → permanently failed
      await service.syncPendingChanges();

      verify(mockDb.markActionFailed(entry.id, 3)).called(1);
    });

    test('handles update_preferences action', () async {
      // Phase 8 made `user_id`, `created_at`, and `updated_at` required
      // on the NotificationPreferences wire format — pass a payload that
      // round-trips through `fromJson`.
      final entry = createQueueEntry(
        action: OfflineAction.update_preferences.toJson(),
        payload: jsonEncode({
          'user_id': 'test-user',
          'reminders_enabled': true,
          'first_reminder_days': 30,
          'reminder_time': '09:00',
          'warranty_offers_enabled': true,
          'tips_enabled': false,
          'push_enabled': true,
          'email_enabled': false,
          'created_at': '2026-01-01T00:00:00.000Z',
          'updated_at': '2026-01-01T00:00:00.000Z',
        }),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      // The mock's returnValueForMissingStub handles the call automatically.
      await service.syncPendingChanges();

      // Verifying markActionSynced proves the action was processed successfully.
      verify(mockDb.markActionSynced(entry.id)).called(1);
    });
  });

  group('OfflineSyncService - error handling', () {
    test('reschedules entry as pending on repository error', () async {
      final entry = createQueueEntry(id: 1, attempts: 0);

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.reschedulePending(any, any)).thenAnswer((_) async {});
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      when(mockItemsRepo.createItem(any))
          .thenThrow(Exception('Repository error'));

      await service.syncPendingChanges();

      verify(mockDb.reschedulePending(1, 1)).called(1);
      verifyNever(mockDb.markActionFailed(any, any));
    });

    test('continues processing after single entry failure', () async {
      // Phase 8: `purchase_date` + `warranty_end_date` are NOT NULL on
      // the wire — include them so the fixture parses cleanly.
      final entries = [
        createQueueEntry(id: 1), // Will fail
        createQueueEntry(
          id: 2,
          entityId: 'other-item',
          payload: jsonEncode({
            'id': 'other-item',
            'name': 'Other Item',
            'home_id': 'home-1',
            'user_id': 'user-1',
            'category': 'refrigerator',
            'purchase_date': '2026-01-01',
            'warranty_months': 12,
            'warranty_end_date': '2027-01-01',
            'created_at': '2026-01-01T00:00:00.000Z',
            'updated_at': '2026-01-01T00:00:00.000Z',
          }),
        ), // Should still be processed
      ];

      when(mockDb.getPendingActions()).thenAnswer((_) async => entries);
      when(mockDb.markActionSynced(any)).thenAnswer((_) async => 1);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.reschedulePending(any, any)).thenAnswer((_) async {});
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      var callCount = 0;
      when(mockItemsRepo.createItem(any)).thenAnswer((_) {
        callCount++;
        if (callCount == 1) {
          throw Exception('Network error');
        }
        return Future.value(TestHelpers.createTestItem());
      });

      await service.syncPendingChanges();

      verify(mockDb.reschedulePending(1, 1)).called(1);
      verify(mockDb.markActionSynced(2)).called(1);
    });

    test('handles JSON decode errors gracefully', () async {
      final entry = createQueueEntry(
        payload: 'invalid-json{{{',
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionFailed(any, any)).thenAnswer((_) async => 1);
      when(mockDb.reschedulePending(any, any)).thenAnswer((_) async {});
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 0);

      await service.syncPendingChanges();

      // Malformed JSON → _processEntry returns early → markActionSynced (entry treated as processed)
      // The behavior depends on implementation: malformed entries are skipped and marked synced
      verify(mockDb.markActionSynced(entry.id)).called(1);
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

      // Sync — use valid JSON payload matching the item
      final entry = createQueueEntry(
        id: 1,
        payload: jsonEncode(item.toJson()),
      );

      when(mockDb.getPendingActions()).thenAnswer((_) async => [entry]);
      when(mockDb.markActionSynced(1)).thenAnswer((_) async => 1);
      when(mockDb.clearSyncedActions()).thenAnswer((_) async => 1);

      when(mockItemsRepo.createItem(any)).thenAnswer((_) async => item);

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
