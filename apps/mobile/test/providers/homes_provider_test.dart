import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/homes_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/homes_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'homes_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

@GenerateMocks([HomesRepository])
void main() {
  late MockHomesRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockHomesRepository();
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
        homesRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  /// Pre-resolve the currentUserProvider, then read the homesProvider.
  /// HomesNotifier.build() checks userAsync.isLoading and needs the user
  /// provider to be settled before it can call getHomes().
  Future<List<Home>> readHomes(ProviderContainer c) async {
    await c.read(currentUserProvider.future);
    return c.read(homesProvider.future);
  }

  group('HomesNotifier', () {
    group('build', () {
      test('returns empty list when user is not authenticated', () async {
        container = createContainer(authenticated: false);

        final homes = await readHomes(container);

        expect(homes, isEmpty);
        verifyNever(mockRepository.getHomes());
      });

      test('fetches homes when user is authenticated', () async {
        final testHomes = [
          TestHelpers.createTestHome(id: 'home-1', name: 'Main House'),
          TestHelpers.createTestHome(id: 'home-2', name: 'Beach House'),
        ];
        when(mockRepository.getHomes())
            .thenAnswer((_) async => testHomes);

        container = createContainer();

        final homes = await readHomes(container);

        expect(homes, hasLength(2));
        expect(homes[0].name, 'Main House');
        expect(homes[1].name, 'Beach House');
        verify(mockRepository.getHomes()).called(1);
      });

      test('propagates error from repository', () async {
        when(mockRepository.getHomes())
            .thenThrow(Exception('Network error'));

        container = createContainer();
        await container.read(currentUserProvider.future);

        expect(
          () => container.read(homesProvider.future),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('addHome', () {
      test('adds home to state', () async {
        final existingHomes = [
          TestHelpers.createTestHome(id: 'home-1', name: 'Existing Home'),
        ];
        final newHome = TestHelpers.createTestHome(
          id: 'home-2',
          name: 'New Home',
        );

        when(mockRepository.getHomes())
            .thenAnswer((_) async => existingHomes);
        when(mockRepository.createHome(any))
            .thenAnswer((_) async => newHome);

        container = createContainer();
        await readHomes(container);

        final result =
            await container.read(homesProvider.notifier).addHome(newHome);

        expect(result.id, 'home-2');
        expect(result.name, 'New Home');

        final homes = container.read(homesProvider).value;
        expect(homes, hasLength(2));
        expect(homes![0].id, 'home-1');
        expect(homes[1].id, 'home-2');

        verify(mockRepository.createHome(newHome)).called(1);
      });

      test('handles error when adding home', () async {
        when(mockRepository.getHomes())
            .thenAnswer((_) async => []);
        when(mockRepository.createHome(any))
            .thenThrow(Exception('Failed to create'));

        container = createContainer();
        await readHomes(container);

        final newHome = TestHelpers.createTestHome(id: 'new-home');

        expect(
          () => container.read(homesProvider.notifier).addHome(newHome),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('updateHome', () {
      test('updates home in state', () async {
        final originalHome = TestHelpers.createTestHome(
          id: 'home-1',
          name: 'Original',
        );
        final updatedHome = TestHelpers.createTestHome(
          id: 'home-1',
          name: 'Updated',
        );

        when(mockRepository.getHomes())
            .thenAnswer((_) async => [originalHome]);
        when(mockRepository.updateHome(any))
            .thenAnswer((_) async => updatedHome);

        container = createContainer();
        await readHomes(container);

        await container.read(homesProvider.notifier).updateHome(updatedHome);

        final homes = container.read(homesProvider).value;
        expect(homes, hasLength(1));
        expect(homes![0].name, 'Updated');
      });

      test('maintains list order when updating', () async {
        final homes = [
          TestHelpers.createTestHome(id: 'home-1', name: 'First'),
          TestHelpers.createTestHome(id: 'home-2', name: 'Second'),
          TestHelpers.createTestHome(id: 'home-3', name: 'Third'),
        ];
        final updatedHome = TestHelpers.createTestHome(
          id: 'home-2',
          name: 'Updated Second',
        );

        when(mockRepository.getHomes())
            .thenAnswer((_) async => homes);
        when(mockRepository.updateHome(any))
            .thenAnswer((_) async => updatedHome);

        container = createContainer();
        await readHomes(container);

        await container.read(homesProvider.notifier).updateHome(updatedHome);

        final result = container.read(homesProvider).value;
        expect(result![0].id, 'home-1');
        expect(result[1].id, 'home-2');
        expect(result[1].name, 'Updated Second');
        expect(result[2].id, 'home-3');
      });
    });

    group('deleteHome', () {
      test('removes home from state', () async {
        final homes = [
          TestHelpers.createTestHome(id: 'home-1'),
          TestHelpers.createTestHome(id: 'home-2'),
          TestHelpers.createTestHome(id: 'home-3'),
        ];

        when(mockRepository.getHomes())
            .thenAnswer((_) async => homes);
        when(mockRepository.deleteHome('home-2'))
            .thenAnswer((_) async => {});

        container = createContainer();
        await readHomes(container);

        await container.read(homesProvider.notifier).deleteHome('home-2');

        final result = container.read(homesProvider).value;
        expect(result, hasLength(2));
        expect(result!.any((h) => h.id == 'home-2'), isFalse);
        expect(result[0].id, 'home-1');
        expect(result[1].id, 'home-3');
      });
    });
  });

  group('currentHomeProvider', () {
    test('returns null when no homes exist', () async {
      when(mockRepository.getHomes())
          .thenAnswer((_) async => []);

      container = createContainer();
      await readHomes(container);

      final currentHome = container.read(currentHomeProvider);
      expect(currentHome, isNull);
    });

    test('returns first home when none is selected', () async {
      final homes = [
        TestHelpers.createTestHome(id: 'home-1', name: 'First'),
        TestHelpers.createTestHome(id: 'home-2', name: 'Second'),
      ];

      when(mockRepository.getHomes())
          .thenAnswer((_) async => homes);

      container = createContainer();
      await readHomes(container);

      final currentHome = container.read(currentHomeProvider);
      expect(currentHome, isNotNull);
      expect(currentHome!.id, 'home-1');
    });

    test('returns selected home when selectedHomeId is set', () async {
      final homes = [
        TestHelpers.createTestHome(id: 'home-1', name: 'First'),
        TestHelpers.createTestHome(id: 'home-2', name: 'Second'),
      ];

      when(mockRepository.getHomes())
          .thenAnswer((_) async => homes);

      container = createContainer();
      await readHomes(container);

      container.read(selectedHomeIdProvider.notifier).state = 'home-2';

      final currentHome = container.read(currentHomeProvider);
      expect(currentHome, isNotNull);
      expect(currentHome!.id, 'home-2');
    });
  });

  group('hasHomeProvider', () {
    test('returns false when no homes exist', () async {
      when(mockRepository.getHomes())
          .thenAnswer((_) async => []);

      container = createContainer();
      await readHomes(container);

      final hasHome = container.read(hasHomeProvider);
      expect(hasHome.valueOrNull, isFalse);
    });

    test('returns true when homes exist', () async {
      when(mockRepository.getHomes())
          .thenAnswer((_) async => [TestHelpers.createTestHome()]);

      container = createContainer();
      await readHomes(container);

      final hasHome = container.read(hasHomeProvider);
      expect(hasHome.valueOrNull, isTrue);
    });

    test('stays in AsyncLoading until homes resolve (C101)', () async {
      // Repository never resolves — provider must remain loading.
      final completer = Completer<List<Home>>();
      when(mockRepository.getHomes())
          .thenAnswer((_) => completer.future);

      container = createContainer();
      // Kick off a read so the AsyncNotifier starts building.
      // ignore: unawaited_futures
      container.read(homesProvider.future);

      final hasHome = container.read(hasHomeProvider);
      expect(hasHome.isLoading, isTrue);
      expect(hasHome.valueOrNull, isNull);

      completer.complete([]);
    });
  });
}
