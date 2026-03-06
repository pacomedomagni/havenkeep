import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/warranty_purchases_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/warranty_purchases_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'warranty_purchases_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

/// Helper to create a test WarrantyPurchase.
WarrantyPurchase createTestPurchase({
  String? id,
  String? itemId,
  WarrantyPurchaseStatus? status,
}) {
  final now = DateTime.now();
  return WarrantyPurchase(
    id: id ?? 'purchase-${now.millisecondsSinceEpoch}',
    itemId: itemId ?? 'test-item-1',
    userId: TestHelpers.testUserId,
    provider: 'SquareTrade',
    planName: '3-Year Protection',
    durationMonths: 36,
    startsAt: now,
    expiresAt: now.add(const Duration(days: 365 * 3)),
    price: 99.99,
    deductible: 25.0,
    purchaseDate: now,
    status: status ?? WarrantyPurchaseStatus.active,
    createdAt: now,
    updatedAt: now,
  );
}

@GenerateMocks([WarrantyPurchasesRepository])
void main() {
  late MockWarrantyPurchasesRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockWarrantyPurchasesRepository();
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
        warrantyPurchasesRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  group('warrantyPurchasesProvider', () {
    test('returns empty list when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final purchases = await container.read(warrantyPurchasesProvider.future);

      expect(purchases, isEmpty);
      verifyNever(mockRepository.getPurchases());
    });

    test('fetches purchases when authenticated', () async {
      when(mockRepository.getPurchases()).thenAnswer((_) async => [
            createTestPurchase(id: 'purchase-1'),
            createTestPurchase(id: 'purchase-2'),
          ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final purchases = await container.read(warrantyPurchasesProvider.future);

      expect(purchases, hasLength(2));
      verify(mockRepository.getPurchases()).called(1);
    });

    test('addPurchase prepends new purchase to state', () async {
      final existingPurchase = createTestPurchase(id: 'purchase-existing');
      final newPurchase = createTestPurchase(id: 'purchase-new');

      when(mockRepository.getPurchases())
          .thenAnswer((_) async => [existingPurchase]);
      when(mockRepository.createPurchase(any))
          .thenAnswer((_) async => newPurchase);

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(warrantyPurchasesProvider.future);

      await container
          .read(warrantyPurchasesProvider.notifier)
          .addPurchase(newPurchase);

      final purchases = container.read(warrantyPurchasesProvider).value;
      expect(purchases, hasLength(2));
      expect(purchases![0].id, 'purchase-new'); // new purchase at front
      expect(purchases[1].id, 'purchase-existing');
      verify(mockRepository.createPurchase(newPurchase)).called(1);
    });

    test('cancelPurchase updates item status in state', () async {
      final activePurchase = createTestPurchase(
        id: 'purchase-1',
        status: WarrantyPurchaseStatus.active,
      );
      final cancelledPurchase = createTestPurchase(
        id: 'purchase-1',
        status: WarrantyPurchaseStatus.cancelled,
      );

      when(mockRepository.getPurchases())
          .thenAnswer((_) async => [activePurchase]);
      when(mockRepository.cancelPurchase('purchase-1',
              reason: anyNamed('reason')))
          .thenAnswer((_) async => cancelledPurchase);

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(warrantyPurchasesProvider.future);

      await container
          .read(warrantyPurchasesProvider.notifier)
          .cancelPurchase('purchase-1', reason: 'No longer needed');

      final purchases = container.read(warrantyPurchasesProvider).value;
      expect(purchases, hasLength(1));
      expect(purchases![0].id, 'purchase-1');
      expect(purchases[0].status, WarrantyPurchaseStatus.cancelled);
    });

    test('refresh re-fetches purchases from repository', () async {
      final initial = [createTestPurchase(id: 'purchase-old')];
      final refreshed = [
        createTestPurchase(id: 'purchase-new-1'),
        createTestPurchase(id: 'purchase-new-2'),
      ];

      when(mockRepository.getPurchases()).thenAnswer((_) async => initial);

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(warrantyPurchasesProvider.future);

      // Change mock response before refresh
      when(mockRepository.getPurchases()).thenAnswer((_) async => refreshed);

      await container.read(warrantyPurchasesProvider.notifier).refresh();

      final purchases = container.read(warrantyPurchasesProvider).value;
      expect(purchases, hasLength(2));
      expect(purchases![0].id, 'purchase-new-1');
    });

    test('handles error during fetch', () async {
      when(mockRepository.getPurchases())
          .thenThrow(Exception('Network error'));

      container = createContainer();
      await container.read(currentUserProvider.future);

      expect(
        () => container.read(warrantyPurchasesProvider.future),
        throwsA(isA<Exception>()),
      );
    });

    test('handles error during refresh and sets error state', () async {
      when(mockRepository.getPurchases()).thenAnswer((_) async => []);

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(warrantyPurchasesProvider.future);

      when(mockRepository.getPurchases())
          .thenThrow(Exception('Network error'));

      await container.read(warrantyPurchasesProvider.notifier).refresh();

      final state = container.read(warrantyPurchasesProvider);
      expect(state.hasError, isTrue);
    });
  });
}
