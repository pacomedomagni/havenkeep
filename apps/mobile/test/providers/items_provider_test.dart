import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/items_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/items_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'items_provider_test.mocks.dart';

@GenerateMocks([ItemsRepository])
void main() {
  late MockItemsRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockItemsRepository();
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer createContainer({bool authenticated = true}) {
    final testUser = authenticated
        ? TestHelpers.createTestUser(id: TestHelpers.testUserId)
        : null;

    return ProviderContainer(
      overrides: [
        itemsRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          (ref) => AsyncValue.data(testUser),
        ),
      ],
    );
  }

  group('ItemsNotifier', () {
    group('build', () {
      test('returns empty list when user is not authenticated', () async {
        container = createContainer(authenticated: false);

        final items = await container.read(itemsProvider.future);

        expect(items, isEmpty);
        verifyNever(mockRepository.getItemsWithStatus());
      });

      test('fetches items when user is authenticated', () async {
        final testItems = TestHelpers.createTestItems(count: 3);
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => testItems);

        container = createContainer();

        final items = await container.read(itemsProvider.future);

        expect(items, hasLength(3));
        verify(mockRepository.getItemsWithStatus()).called(1);
      });

      test('re-fetches items when user changes', () async {
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => []);

        container = createContainer();

        await container.read(itemsProvider.future);
        verify(mockRepository.getItemsWithStatus()).called(1);

        // Invalidate user provider to trigger refetch
        container.invalidate(currentUserProvider);
        await container.read(itemsProvider.future);

        verify(mockRepository.getItemsWithStatus()).called(2);
      });
    });

    group('refresh', () {
      test('refreshes items from repository', () async {
        final initialItems = [TestHelpers.createTestItem(name: 'Initial')];
        final refreshedItems = [
          TestHelpers.createTestItem(name: 'Refreshed 1'),
          TestHelpers.createTestItem(name: 'Refreshed 2'),
        ];

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => initialItems);

        container = createContainer();
        await container.read(itemsProvider.future);

        // Change mock response for refresh
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => refreshedItems);

        await container.read(itemsProvider.notifier).refresh();

        final items = container.read(itemsProvider).value;
        expect(items, hasLength(2));
        expect(items![0].name, 'Refreshed 1');
      });

      test('handles errors during refresh', () async {
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => []);

        container = createContainer();
        await container.read(itemsProvider.future);

        when(mockRepository.getItemsWithStatus())
            .thenThrow(Exception('Network error'));

        await container.read(itemsProvider.notifier).refresh();

        final state = container.read(itemsProvider);
        expect(state.hasError, isTrue);
      });
    });

    group('addItem', () {
      test('adds item to state and invalidates stats', () async {
        final existingItems = [
          TestHelpers.createTestItem(id: 'existing-1'),
        ];
        final newItem = TestHelpers.createTestItem(
          id: 'new-item',
          name: 'New Item',
        );

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => existingItems);
        when(mockRepository.createItem(any))
            .thenAnswer((_) async => newItem);
        when(mockRepository.getItemById('new-item'))
            .thenAnswer((_) async => newItem);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).addItem(newItem);

        final items = container.read(itemsProvider).value;
        expect(items, hasLength(2));
        expect(items![0].id, 'new-item'); // New item at front
        expect(items[1].id, 'existing-1');

        verify(mockRepository.createItem(newItem)).called(1);
        verify(mockRepository.getItemById('new-item')).called(1);
      });

      test('invalidates related providers after adding', () async {
        final newItem = TestHelpers.createTestItem(id: 'new-item');

        when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
        when(mockRepository.createItem(any))
            .thenAnswer((_) async => newItem);
        when(mockRepository.getItemById('new-item'))
            .thenAnswer((_) async => newItem);
        when(mockRepository.getWarrantyStats())
            .thenAnswer((_) async => {'active': 1, 'expiring': 0, 'expired': 0});
        when(mockRepository.getNeedsAttention())
            .thenAnswer((_) async => []);

        container = createContainer();
        await container.read(itemsProvider.future);

        // Force stats to be computed
        await container.read(warrantyStatsProvider.future);
        await container.read(needsAttentionProvider.future);

        await container.read(itemsProvider.notifier).addItem(newItem);

        // Stats should be invalidated and recomputed
        final stats = await container.read(warrantyStatsProvider.future);
        expect(stats['active'], 1);
      });
    });

    group('updateItem', () {
      test('updates item in state', () async {
        final originalItem = TestHelpers.createTestItem(
          id: 'item-1',
          name: 'Original',
        );
        final updatedItem = TestHelpers.createTestItem(
          id: 'item-1',
          name: 'Updated',
        );

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => [originalItem]);
        when(mockRepository.updateItem(any))
            .thenAnswer((_) async => updatedItem);
        when(mockRepository.getItemById('item-1'))
            .thenAnswer((_) async => updatedItem);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).updateItem(updatedItem);

        final items = container.read(itemsProvider).value;
        expect(items, hasLength(1));
        expect(items![0].name, 'Updated');
      });

      test('maintains list order when updating', () async {
        final items = [
          TestHelpers.createTestItem(id: 'item-1', name: 'First'),
          TestHelpers.createTestItem(id: 'item-2', name: 'Second'),
          TestHelpers.createTestItem(id: 'item-3', name: 'Third'),
        ];
        final updatedItem = TestHelpers.createTestItem(
          id: 'item-2',
          name: 'Updated Second',
        );

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => items);
        when(mockRepository.updateItem(any))
            .thenAnswer((_) async => updatedItem);
        when(mockRepository.getItemById('item-2'))
            .thenAnswer((_) async => updatedItem);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).updateItem(updatedItem);

        final result = container.read(itemsProvider).value;
        expect(result![0].id, 'item-1');
        expect(result[1].id, 'item-2');
        expect(result[1].name, 'Updated Second');
        expect(result[2].id, 'item-3');
      });
    });

    group('deleteItem', () {
      test('removes item from state', () async {
        final items = [
          TestHelpers.createTestItem(id: 'item-1'),
          TestHelpers.createTestItem(id: 'item-2'),
          TestHelpers.createTestItem(id: 'item-3'),
        ];

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => items);
        when(mockRepository.deleteItem('item-2'))
            .thenAnswer((_) async => {});

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).deleteItem('item-2');

        final result = container.read(itemsProvider).value;
        expect(result, hasLength(2));
        expect(result!.any((i) => i.id == 'item-2'), isFalse);
        expect(result[0].id, 'item-1');
        expect(result[1].id, 'item-3');
      });

      test('invalidates stats after deletion', () async {
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => [TestHelpers.createTestItem(id: 'item-1')]);
        when(mockRepository.deleteItem('item-1'))
            .thenAnswer((_) async => {});
        when(mockRepository.getWarrantyStats())
            .thenAnswer((_) async => {'active': 0, 'expiring': 0, 'expired': 0});

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).deleteItem('item-1');

        // Verify stats were invalidated
        final stats = await container.read(warrantyStatsProvider.future);
        expect(stats['active'], 0);
      });
    });

    group('addItems (batch)', () {
      test('adds multiple items at once', () async {
        final newItems = [
          TestHelpers.createTestItem(id: 'new-1', name: 'New 1'),
          TestHelpers.createTestItem(id: 'new-2', name: 'New 2'),
          TestHelpers.createTestItem(id: 'new-3', name: 'New 3'),
        ];

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => []);
        when(mockRepository.createItem(any))
            .thenAnswer((invocation) async {
          final item = invocation.positionalArguments[0] as Item;
          return item;
        });
        when(mockRepository.getItemById(any))
            .thenAnswer((invocation) async {
          final id = invocation.positionalArguments[0] as String;
          return newItems.firstWhere((i) => i.id == id);
        });

        container = createContainer();
        await container.read(itemsProvider.future);

        final created = await container
            .read(itemsProvider.notifier)
            .addItems(newItems);

        expect(created, hasLength(3));
        final items = container.read(itemsProvider).value;
        expect(items, hasLength(3));

        verify(mockRepository.createItem(any)).called(3);
        verify(mockRepository.getItemById(any)).called(3);
      });

      test('maintains order when batch adding', () async {
        final existing = [TestHelpers.createTestItem(id: 'existing')];
        final newItems = [
          TestHelpers.createTestItem(id: 'new-1'),
          TestHelpers.createTestItem(id: 'new-2'),
        ];

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => existing);
        when(mockRepository.createItem(any))
            .thenAnswer((invocation) async => invocation.positionalArguments[0]);
        when(mockRepository.getItemById(any))
            .thenAnswer((invocation) async {
          final id = invocation.positionalArguments[0] as String;
          return newItems.firstWhere((i) => i.id == id);
        });

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).addItems(newItems);

        final items = container.read(itemsProvider).value;
        // New items should be at front, in order
        expect(items![0].id, 'new-1');
        expect(items[1].id, 'new-2');
        expect(items[2].id, 'existing');
      });
    });

    group('archiveItem', () {
      test('removes item from active list', () async {
        final items = [
          TestHelpers.createTestItem(id: 'item-1'),
          TestHelpers.createTestItem(id: 'item-2'),
        ];

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => items);
        when(mockRepository.archiveItem('item-1'))
            .thenAnswer((_) async => {});

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).archiveItem('item-1');

        final result = container.read(itemsProvider).value;
        expect(result, hasLength(1));
        expect(result![0].id, 'item-2');
      });

      test('invalidates archived items provider', () async {
        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => [TestHelpers.createTestItem(id: 'item-1')]);
        when(mockRepository.archiveItem('item-1'))
            .thenAnswer((_) async => {});
        when(mockRepository.getItems(includeArchived: true))
            .thenAnswer((_) async => [
                  TestHelpers.createTestItem(id: 'item-1', isArchived: true)
                ]);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).archiveItem('item-1');

        // Archived items should be invalidated
        final archived = await container.read(archivedItemsProvider.future);
        expect(archived, hasLength(1));
        expect(archived[0].isArchived, isTrue);
      });
    });

    group('unarchiveItem', () {
      test('adds item back to active list', () async {
        final archivedItem = TestHelpers.createTestItem(
          id: 'item-1',
          isArchived: true,
        );
        final restoredItem = TestHelpers.createTestItem(
          id: 'item-1',
          isArchived: false,
        );

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => []);
        when(mockRepository.unarchiveItem('item-1'))
            .thenAnswer((_) async => {});
        when(mockRepository.getItemById('item-1'))
            .thenAnswer((_) async => restoredItem);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).unarchiveItem('item-1');

        final result = container.read(itemsProvider).value;
        expect(result, hasLength(1));
        expect(result![0].id, 'item-1');
        expect(result[0].isArchived, isFalse);
      });

      test('adds restored item to front of list', () async {
        final existing = [TestHelpers.createTestItem(id: 'existing')];
        final restoredItem = TestHelpers.createTestItem(id: 'restored');

        when(mockRepository.getItemsWithStatus())
            .thenAnswer((_) async => existing);
        when(mockRepository.unarchiveItem('restored'))
            .thenAnswer((_) async => {});
        when(mockRepository.getItemById('restored'))
            .thenAnswer((_) async => restoredItem);

        container = createContainer();
        await container.read(itemsProvider.future);

        await container.read(itemsProvider.notifier).unarchiveItem('restored');

        final result = container.read(itemsProvider).value;
        expect(result![0].id, 'restored'); // Restored item at front
        expect(result[1].id, 'existing');
      });
    });
  });

  group('warrantyStatsProvider', () {
    test('returns zero stats when not authenticated', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);

      container = createContainer(authenticated: false);

      final stats = await container.read(warrantyStatsProvider.future);

      expect(stats['active'], 0);
      expect(stats['expiring'], 0);
      expect(stats['expired'], 0);
      verifyNever(mockRepository.getWarrantyStats());
    });

    test('fetches stats from repository when authenticated', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.getWarrantyStats())
          .thenAnswer((_) async => {'active': 10, 'expiring': 3, 'expired': 2});

      container = createContainer();

      final stats = await container.read(warrantyStatsProvider.future);

      expect(stats['active'], 10);
      expect(stats['expiring'], 3);
      expect(stats['expired'], 2);
      verify(mockRepository.getWarrantyStats()).called(1);
    });
  });

  group('needsAttentionProvider', () {
    test('returns empty list when not authenticated', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);

      container = createContainer(authenticated: false);

      final items = await container.read(needsAttentionProvider.future);

      expect(items, isEmpty);
      verifyNever(mockRepository.getNeedsAttention());
    });

    test('fetches needs attention items when authenticated', () async {
      final items = [
        TestHelpers.createTestItem(status: WarrantyStatus.expiring),
        TestHelpers.createTestItem(status: WarrantyStatus.expired),
      ];

      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.getNeedsAttention())
          .thenAnswer((_) async => items);

      container = createContainer();

      final result = await container.read(needsAttentionProvider.future);

      expect(result, hasLength(2));
      verify(mockRepository.getNeedsAttention()).called(1);
    });
  });

  group('itemDetailProvider', () {
    test('fetches single item by ID', () async {
      final item = TestHelpers.createTestItem(id: 'detail-item');

      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.getItemById('detail-item'))
          .thenAnswer((_) async => item);

      container = createContainer();

      final result = await container.read(itemDetailProvider('detail-item').future);

      expect(result.id, 'detail-item');
      verify(mockRepository.getItemById('detail-item')).called(1);
    });
  });

  group('activeItemCountProvider', () {
    test('returns count from repository', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.countActiveItems()).thenAnswer((_) async => 42);

      container = createContainer();

      final count = await container.read(activeItemCountProvider.future);

      expect(count, 42);
      verify(mockRepository.countActiveItems()).called(1);
    });

    test('re-fetches when items change', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.countActiveItems()).thenAnswer((_) async => 1);

      container = createContainer();

      await container.read(activeItemCountProvider.future);
      verify(mockRepository.countActiveItems()).called(1);

      // Invalidate items to trigger refetch
      container.invalidate(itemsProvider);
      await container.read(activeItemCountProvider.future);

      verify(mockRepository.countActiveItems()).called(2);
    });
  });

  group('isAtItemLimitProvider', () {
    test('returns false when user is premium', () async {
      final premiumUser = TestHelpers.createTestUser(plan: UserPlan.premium);

      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.countActiveItems()).thenAnswer((_) async => 100);

      container = ProviderContainer(
        overrides: [
          itemsRepositoryProvider.overrideWithValue(mockRepository),
          currentUserProvider.overrideWith(
            (ref) => AsyncValue.data(premiumUser),
          ),
        ],
      );

      final atLimit = await container.read(isAtItemLimitProvider.future);

      expect(atLimit, isFalse);
    });

    test('returns true when free user at limit', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.countActiveItems())
          .thenAnswer((_) async => kFreePlanItemLimit);

      container = createContainer();

      final atLimit = await container.read(isAtItemLimitProvider.future);

      expect(atLimit, isTrue);
    });

    test('returns false when free user below limit', () async {
      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.countActiveItems())
          .thenAnswer((_) async => kFreePlanItemLimit - 1);

      container = createContainer();

      final atLimit = await container.read(isAtItemLimitProvider.future);

      expect(atLimit, isFalse);
    });
  });

  group('archivedItemsProvider', () {
    test('returns only archived items', () async {
      final allItems = [
        TestHelpers.createTestItem(id: 'active-1', isArchived: false),
        TestHelpers.createTestItem(id: 'archived-1', isArchived: true),
        TestHelpers.createTestItem(id: 'active-2', isArchived: false),
        TestHelpers.createTestItem(id: 'archived-2', isArchived: true),
      ];

      when(mockRepository.getItemsWithStatus()).thenAnswer((_) async => []);
      when(mockRepository.getItems(includeArchived: true))
          .thenAnswer((_) async => allItems);

      container = createContainer();

      final archived = await container.read(archivedItemsProvider.future);

      expect(archived, hasLength(2));
      expect(archived[0].id, 'archived-1');
      expect(archived[1].id, 'archived-2');
      expect(archived.every((i) => i.isArchived), isTrue);
    });
  });
}
