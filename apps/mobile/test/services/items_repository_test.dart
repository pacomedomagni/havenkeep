import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/items_repository.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_helpers.dart';
import 'items_repository_test.mocks.dart';

// Generate mocks for Supabase client and query builders
@GenerateMocks([
  SupabaseClient,
  SupabaseQueryBuilder,
  PostgrestFilterBuilder,
  PostgrestTransformBuilder,
])
void main() {
  late MockSupabaseClient mockClient;
  late MockSupabaseQueryBuilder mockQueryBuilder;
  late MockPostgrestFilterBuilder mockFilterBuilder;
  late MockPostgrestTransformBuilder mockTransformBuilder;
  late ItemsRepository repository;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockQueryBuilder = MockSupabaseQueryBuilder();
    mockFilterBuilder = MockPostgrestFilterBuilder();
    mockTransformBuilder = MockPostgrestTransformBuilder();
    repository = ItemsRepository(mockClient);

    // Mock the auth user ID
    final mockAuth = MockGoTrueClient();
    final mockUser = User(
      id: TestHelpers.testUserId,
      appMetadata: {},
      userMetadata: {},
      aud: 'authenticated',
      createdAt: DateTime.now().toIso8601String(),
    );
    when(mockClient.auth).thenReturn(mockAuth);
    when(mockAuth.currentUser).thenReturn(mockUser);
  });

  group('ItemsRepository - READ operations', () {
    group('getItems', () {
      test('returns list of items for current user', () async {
        final testItems = [
          TestHelpers.createTestItem(id: '1', name: 'Item 1'),
          TestHelpers.createTestItem(id: '2', name: 'Item 2'),
        ];

        // Setup mock chain
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('is_archived', false))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order('created_at', ascending: false))
            .thenAnswer((_) async => testItems.map((i) => i.toJson()).toList());

        final items = await repository.getItems();

        expect(items, hasLength(2));
        expect(items[0].id, '1');
        expect(items[1].id, '2');
        verify(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
            .called(1);
      });

      test('filters by homeId when provided', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq(any, any)).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItems(homeId: 'home-123');

        verify(mockFilterBuilder.eq('home_id', 'home-123')).called(1);
      });

      test('filters by category when provided', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq(any, any)).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItems(category: ItemCategory.refrigerator);

        verify(mockFilterBuilder.eq('category', ItemCategory.refrigerator.toJson()))
            .called(1);
      });

      test('filters by room when provided', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq(any, any)).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItems(room: ItemRoom.kitchen);

        verify(mockFilterBuilder.eq('room', ItemRoom.kitchen.toJson())).called(1);
      });

      test('includes archived items when includeArchived is true', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItems(includeArchived: true);

        // Should NOT filter by is_archived
        verifyNever(mockFilterBuilder.eq('is_archived', any));
      });

      test('excludes archived items by default', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq(any, any)).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItems();

        verify(mockFilterBuilder.eq('is_archived', false)).called(1);
      });
    });

    group('getItemById', () {
      test('returns single item by ID', () async {
        final testItem = TestHelpers.createTestItem(id: 'test-id');

        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('id', 'test-id'))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.single())
            .thenAnswer((_) async => testItem.toJson());

        final item = await repository.getItemById('test-id');

        expect(item.id, 'test-id');
        verify(mockFilterBuilder.eq('id', 'test-id')).called(1);
        verify(mockFilterBuilder.single()).called(1);
      });

      test('throws when item not found', () async {
        when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('id', 'nonexistent'))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.single())
            .thenThrow(PostgrestException(message: 'Not found', code: '404'));

        expect(
          () => repository.getItemById('nonexistent'),
          throwsA(isA<PostgrestException>()),
        );
      });
    });

    group('getItemsWithStatus', () {
      test('queries from view with status', () async {
        final testItems = [
          TestHelpers.createTestItem(
            status: WarrantyStatus.active,
          ),
        ];

        when(mockClient.from(kItemsWithStatusView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order('warranty_end_date', ascending: true))
            .thenAnswer((_) async => testItems.map((i) => i.toJson()).toList());

        final items = await repository.getItemsWithStatus();

        expect(items, hasLength(1));
        verify(mockClient.from(kItemsWithStatusView)).called(1);
        verify(mockFilterBuilder.order('warranty_end_date', ascending: true))
            .called(1);
      });

      test('filters by homeId when provided', () async {
        when(mockClient.from(kItemsWithStatusView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq(any, any)).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.order(any, ascending: anyNamed('ascending')))
            .thenAnswer((_) async => []);

        await repository.getItemsWithStatus(homeId: 'home-123');

        verify(mockFilterBuilder.eq('home_id', 'home-123')).called(1);
      });
    });

    group('getDashboardSummary', () {
      test('returns summary data for current user', () async {
        final summaryData = {
          'user_id': TestHelpers.testUserId,
          'active_count': 10,
          'expiring_count': 3,
          'expired_count': 2,
        };

        when(mockClient.from(kDashboardSummaryView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.maybeSingle())
            .thenAnswer((_) async => summaryData);

        final summary = await repository.getDashboardSummary();

        expect(summary, isNotNull);
        expect(summary!['active_count'], 10);
        expect(summary['expiring_count'], 3);
        expect(summary['expired_count'], 2);
      });

      test('returns null when no data exists', () async {
        when(mockClient.from(kDashboardSummaryView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

        final summary = await repository.getDashboardSummary();

        expect(summary, isNull);
      });
    });

    group('getNeedsAttention', () {
      test('returns items from needs attention view', () async {
        final testItems = [
          TestHelpers.createTestItem(status: WarrantyStatus.expiring),
          TestHelpers.createTestItem(status: WarrantyStatus.expired),
        ];

        when(mockClient.from(kNeedsAttentionView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.limit(any))
            .thenAnswer((_) async => testItems.map((i) => i.toJson()).toList());

        final items = await repository.getNeedsAttention();

        expect(items, hasLength(2));
        verify(mockFilterBuilder.limit(kNeedsAttentionLimit)).called(1);
      });

      test('respects custom limit', () async {
        when(mockClient.from(kNeedsAttentionView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.limit(any)).thenAnswer((_) async => []);

        await repository.getNeedsAttention(limit: 5);

        verify(mockFilterBuilder.limit(5)).called(1);
      });
    });

    group('getWarrantyStats', () {
      test('returns stats from dashboard summary', () async {
        final summaryData = {
          'active_count': 10,
          'expiring_count': 3,
          'expired_count': 2,
        };

        when(mockClient.from(kDashboardSummaryView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.maybeSingle())
            .thenAnswer((_) async => summaryData);

        final stats = await repository.getWarrantyStats();

        expect(stats['active'], 10);
        expect(stats['expiring'], 3);
        expect(stats['expired'], 2);
      });

      test('returns zero stats when summary is null', () async {
        when(mockClient.from(kDashboardSummaryView))
            .thenReturn(mockQueryBuilder);
        when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.eq('user_id', any))
            .thenReturn(mockFilterBuilder);
        when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

        final stats = await repository.getWarrantyStats();

        expect(stats['active'], 0);
        expect(stats['expiring'], 0);
        expect(stats['expired'], 0);
      });
    });

    group('countActiveItems', () {
      test('returns count from RPC function', () async {
        when(mockClient.rpc(kCountActiveItemsFn, params: anyNamed('params')))
            .thenAnswer((_) async => 42);

        final count = await repository.countActiveItems();

        expect(count, 42);
        verify(mockClient.rpc(
          kCountActiveItemsFn,
          params: {'p_user_id': TestHelpers.testUserId},
        )).called(1);
      });

      test('returns 0 when RPC returns null', () async {
        when(mockClient.rpc(any, params: anyNamed('params')))
            .thenAnswer((_) async => null);

        final count = await repository.countActiveItems();

        expect(count, 0);
      });
    });
  });

  group('ItemsRepository - CREATE operations', () {
    test('createItem inserts and returns created item', () async {
      final testItem = TestHelpers.createTestItem(name: 'New Item');

      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testItem.toJson());

      final created = await repository.createItem(testItem);

      expect(created.name, 'New Item');
      verify(mockQueryBuilder.insert(testItem.toInsertJson())).called(1);
      verify(mockFilterBuilder.single()).called(1);
    });
  });

  group('ItemsRepository - UPDATE operations', () {
    test('updateItem updates and returns updated item', () async {
      final testItem = TestHelpers.createTestItem(name: 'Updated Item');

      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testItem.toJson());

      final updated = await repository.updateItem(testItem);

      expect(updated.name, 'Updated Item');
      verify(mockFilterBuilder.eq('id', testItem.id)).called(1);
    });

    test('updateItem removes computed fields before updating', () async {
      final testItem = TestHelpers.createTestItem();
      Map<String, dynamic> capturedJson = {};

      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenAnswer((invocation) {
        capturedJson = invocation.positionalArguments[0] as Map<String, dynamic>;
        return mockFilterBuilder;
      });
      when(mockFilterBuilder.eq('id', any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testItem.toJson());

      await repository.updateItem(testItem);

      expect(capturedJson.containsKey('warranty_end_date'), isFalse);
      expect(capturedJson.containsKey('created_at'), isFalse);
    });

    test('archiveItem sets is_archived to true', () async {
      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'item-123')).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {});

      await repository.archiveItem('item-123');

      verify(mockQueryBuilder.update({'is_archived': true})).called(1);
      verify(mockFilterBuilder.eq('id', 'item-123')).called(1);
    });

    test('unarchiveItem sets is_archived to false', () async {
      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'item-123')).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {});

      await repository.unarchiveItem('item-123');

      verify(mockQueryBuilder.update({'is_archived': false})).called(1);
      verify(mockFilterBuilder.eq('id', 'item-123')).called(1);
    });
  });

  group('ItemsRepository - DELETE operations', () {
    test('deleteItem permanently deletes item', () async {
      when(mockClient.from(kItemsTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.delete()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'item-123'))
          .thenReturn(mockFilterBuilder);

      await repository.deleteItem('item-123');

      verify(mockQueryBuilder.delete()).called(1);
      verify(mockFilterBuilder.eq('id', 'item-123')).called(1);
    });
  });
}

// Mock for GoTrueClient
@GenerateMocks([GoTrueClient])
class MockGoTrueClient extends Mock implements GoTrueClient {}
