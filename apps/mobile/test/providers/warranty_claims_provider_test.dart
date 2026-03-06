import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/warranty_claims_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/warranty_claims_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'warranty_claims_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

/// Helper to create a test WarrantyClaim.
WarrantyClaim createTestClaim({
  String? id,
  String? itemId,
  String? userId,
  ClaimStatus? status,
  double repairCost = 150.0,
  double amountSaved = 150.0,
}) {
  final now = DateTime.now();
  return WarrantyClaim(
    id: id ?? 'claim-${now.millisecondsSinceEpoch}',
    userId: userId ?? TestHelpers.testUserId,
    itemId: itemId ?? 'test-item-1',
    claimDate: now,
    repairCost: repairCost,
    amountSaved: amountSaved,
    status: status ?? ClaimStatus.pending,
    createdAt: now,
    updatedAt: now,
  );
}

@GenerateMocks([WarrantyClaimsRepository])
void main() {
  late MockWarrantyClaimsRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockWarrantyClaimsRepository();
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
        claimsRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  group('claimsProvider', () {
    test('returns empty list when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final claims = await container.read(claimsProvider.future);

      expect(claims, isEmpty);
      verifyNever(mockRepository.getClaims());
    });

    test('fetches claims when authenticated', () async {
      when(mockRepository.getClaims()).thenAnswer((_) async => [
            createTestClaim(id: 'claim-1'),
            createTestClaim(id: 'claim-2'),
            createTestClaim(id: 'claim-3'),
          ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final claims = await container.read(claimsProvider.future);

      expect(claims, hasLength(3));
      verify(mockRepository.getClaims()).called(1);
    });

    test('addClaim prepends new claim to state', () async {
      final existingClaim = createTestClaim(id: 'claim-existing');
      final newClaim = createTestClaim(id: 'claim-new');

      when(mockRepository.getClaims())
          .thenAnswer((_) async => [existingClaim]);
      when(mockRepository.createClaim(any))
          .thenAnswer((_) async => newClaim);

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(claimsProvider.future);

      await container.read(claimsProvider.notifier).addClaim(newClaim);

      final claims = container.read(claimsProvider).value;
      expect(claims, hasLength(2));
      expect(claims![0].id, 'claim-new'); // new claim at front
      expect(claims[1].id, 'claim-existing');
      verify(mockRepository.createClaim(newClaim)).called(1);
    });

    test('deleteClaim removes claim from state', () async {
      final claims = [
        createTestClaim(id: 'claim-1'),
        createTestClaim(id: 'claim-2'),
        createTestClaim(id: 'claim-3'),
      ];

      when(mockRepository.getClaims()).thenAnswer((_) async => claims);
      when(mockRepository.deleteClaim('claim-2'))
          .thenAnswer((_) async => {});

      container = createContainer();
      await container.read(currentUserProvider.future);
      await container.read(claimsProvider.future);

      await container.read(claimsProvider.notifier).deleteClaim('claim-2');

      final result = container.read(claimsProvider).value;
      expect(result, hasLength(2));
      expect(result!.any((c) => c.id == 'claim-2'), isFalse);
      expect(result[0].id, 'claim-1');
      expect(result[1].id, 'claim-3');
    });

    test('handles error during fetch', () async {
      when(mockRepository.getClaims()).thenThrow(Exception('Network error'));

      container = createContainer();
      await container.read(currentUserProvider.future);

      expect(
        () => container.read(claimsProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('claimSavingsProvider', () {
    test('returns empty map when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final savings = await container.read(claimSavingsProvider.future);

      expect(savings, isEmpty);
      verifyNever(mockRepository.getSavings());
    });

    test('fetches savings when authenticated', () async {
      when(mockRepository.getClaims()).thenAnswer((_) async => []);
      when(mockRepository.getSavings()).thenAnswer((_) async => {
            'total_saved': 350.0,
            'claim_count': 3,
          });

      container = createContainer();
      await container.read(currentUserProvider.future);

      final savings = await container.read(claimSavingsProvider.future);

      expect(savings['total_saved'], 350.0);
      expect(savings['claim_count'], 3);
      verify(mockRepository.getSavings()).called(1);
    });
  });

  group('savingsFeedProvider', () {
    test('returns empty list when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final feed = await container.read(savingsFeedProvider.future);

      expect(feed, isEmpty);
      verifyNever(mockRepository.getSavingsFeed());
    });

    test('fetches savings feed when authenticated', () async {
      when(mockRepository.getClaims()).thenAnswer((_) async => []);
      when(mockRepository.getSavingsFeed(limit: anyNamed('limit')))
          .thenAnswer((_) async => [
                {'amount': 150.0, 'category': 'refrigerator'},
                {'amount': 200.0, 'category': 'hvac'},
              ]);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final feed = await container.read(savingsFeedProvider.future);

      expect(feed, hasLength(2));
      verify(mockRepository.getSavingsFeed(limit: anyNamed('limit'))).called(1);
    });
  });
}
