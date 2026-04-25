import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/items_repository.dart';
import 'package:api_client/api_client.dart';

import '../helpers/test_helpers.dart';
import 'items_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late ItemsRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = ItemsRepository(mockClient);
  });

  /// Helper to create a valid item JSON response.
  ///
  /// Mirrors the API contract after Ch08-Item-D010: `purchase_date` and
  /// `warranty_end_date` are both NOT NULL on the wire.
  Map<String, dynamic> itemJson({
    String id = 'item-1',
    String name = 'Test Item',
    String category = 'refrigerator',
  }) {
    return {
      'id': id,
      'home_id': 'home-1',
      'user_id': 'user-1',
      'name': name,
      'category': category,
      'purchase_date': '2026-01-01',
      'warranty_months': 12,
      'warranty_end_date': '2027-01-01',
      'warranty_type': 'manufacturer',
      'is_archived': false,
      'added_via': 'manual',
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    };
  }

  group('ItemsRepository', () {
    group('getItems', () {
      test('sends page and limit parameters', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {
                  'data': [itemJson()],
                });

        final items = await repository.getItems();

        expect(items, hasLength(1));

        // Verify pagination parameters were sent
        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['page'], '1');
        expect(captured['limit'], '100');
        expect(captured['archived'], 'false');
      });

      test('paginates through multiple pages', () async {
        // First page: 100 items (full page)
        final page1Items = List.generate(100, (i) => itemJson(id: 'item-$i'));
        // Second page: fewer than limit (last page)
        final page2Items = [itemJson(id: 'item-100')];

        var callCount = 0;
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async {
          callCount++;
          return {
            'data': callCount == 1 ? page1Items : page2Items,
          };
        });

        final items = await repository.getItems();

        expect(items, hasLength(101));
        // Should have been called twice (page 1 and page 2)
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
                queryParams: anyNamed('queryParams')))
            .called(2);
      });

      test('filters by homeId when provided', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getItems(homeId: 'home-123');

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['home_id'], 'home-123');
      });

      test('includes archived when requested', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getItems(includeArchived: true);

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        // Should NOT have 'archived': 'false' when includeArchived is true
        expect(captured.containsKey('archived'), isFalse);
      });
    });

    group('getItemById', () {
      test('fetches single item by ID', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items', 'item-1']))
            .thenAnswer((_) async => {
                  'data': itemJson(id: 'item-1', name: 'My Fridge'),
                });

        final item = await repository.getItemById('item-1');

        expect(item.id, 'item-1');
        expect(item.name, 'My Fridge');
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'items', 'item-1'])).called(1);
      });
    });

    group('getItemsWithStatus', () {
      test('fetches items with pagination and non-archived filter', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {
                  'data': [
                    itemJson(id: 'item-1'),
                    itemJson(id: 'item-2'),
                  ],
                });

        final items = await repository.getItemsWithStatus();

        expect(items, hasLength(2));

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['archived'], 'false');
        expect(captured['page'], '1');
        expect(captured['limit'], '100');
      });

      test('filters by homeId when provided', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items'], queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getItemsWithStatus(homeId: 'home-42');

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'items'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['home_id'], 'home-42');
      });
    });

    group('createItem', () {
      test('sends POST request and returns created item', () async {
        final item = TestHelpers.createTestItem(name: 'New Item');

        when(mockClient.post(pathSegments: const ['api', 'v1', 'items'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': itemJson(id: 'created-1', name: 'New Item'),
                });

        final created = await repository.createItem(item);

        expect(created.id, 'created-1');
        expect(created.name, 'New Item');
        verify(mockClient.post(pathSegments: const ['api', 'v1', 'items'], body: anyNamed('body')))
            .called(1);
      });
    });

    group('updateItem', () {
      test('sends PUT request to correct endpoint', () async {
        final item = TestHelpers.createTestItem(
          id: 'item-1',
          name: 'Updated Item',
        );

        when(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': itemJson(id: 'item-1', name: 'Updated Item'),
                });

        final updated = await repository.updateItem(item);

        expect(updated.name, 'Updated Item');

        // Verify body does not include read-only fields
        final captured = verify(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'],
          body: captureAnyNamed('body'),
        )).captured.single as Map<String, dynamic>;
        expect(captured.containsKey('warranty_end_date'), isFalse);
        expect(captured.containsKey('created_at'), isFalse);
        expect(captured.containsKey('updated_at'), isFalse);
        expect(captured.containsKey('id'), isFalse);
        expect(captured.containsKey('user_id'), isFalse);
      });
    });

    group('deleteItem', () {
      test('sends DELETE request to correct endpoint', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'items', 'item-1']))
            .thenAnswer((_) async => {});

        await repository.deleteItem('item-1');

        verify(mockClient.delete(pathSegments: const ['api', 'v1', 'items', 'item-1'])).called(1);
      });

      test('rethrows errors from API', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'items', 'item-1']))
            .thenThrow(ApiException(404, 'Not found'));

        expect(
          () => repository.deleteItem('item-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('archiveItem', () {
      test('sends PUT with is_archived true', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'], body: anyNamed('body')))
            .thenAnswer((_) async => {});

        await repository.archiveItem('item-1');

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'], body: {
          'is_archived': true,
        })).called(1);
      });
    });

    group('unarchiveItem', () {
      test('sends PUT with is_archived false', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'], body: anyNamed('body')))
            .thenAnswer((_) async => {});

        await repository.unarchiveItem('item-1');

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'items', 'item-1'], body: {
          'is_archived': false,
        })).called(1);
      });
    });

    group('getWarrantyStats', () {
      test('parses dashboard summary into stats map', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'stats', 'dashboard']))
            .thenAnswer((_) async => {
                  'data': {
                    'active_warranties': 10,
                    'expiring_soon': 3,
                    'expired': 2,
                    'total_items': 15,
                  },
                });

        final stats = await repository.getWarrantyStats();

        expect(stats['active'], 10);
        expect(stats['expiring'], 3);
        expect(stats['expired'], 2);
      });

      test('throws when dashboard summary is null', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'stats', 'dashboard']))
            .thenAnswer((_) async => {'data': null});

        expect(
          () => repository.getWarrantyStats(),
          throwsA(isA<StateError>()),
        );
      });
    });

    group('getNeedsAttention', () {
      test('fetches items needing attention with limit', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'stats', 'items-needing-attention'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {
                  'data': [
                    itemJson(id: 'expiring-1'),
                  ],
                });

        final items = await repository.getNeedsAttention();

        expect(items, hasLength(1));
        expect(items[0].id, 'expiring-1');
      });
    });

    group('countActiveItems', () {
      test('returns count from API', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'items', 'count']))
            .thenAnswer((_) async => {
                  'data': {'count': 42},
                });

        final count = await repository.countActiveItems();

        expect(count, 42);
      });
    });
  });
}
