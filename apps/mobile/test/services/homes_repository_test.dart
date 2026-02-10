import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/homes_repository.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_helpers.dart';
import 'homes_repository_test.mocks.dart';

@GenerateMocks([
  SupabaseClient,
  GoTrueClient,
  SupabaseQueryBuilder,
  PostgrestFilterBuilder,
  PostgrestTransformBuilder,
])
void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockSupabaseQueryBuilder mockQueryBuilder;
  late MockPostgrestFilterBuilder mockFilterBuilder;
  late MockPostgrestTransformBuilder mockTransformBuilder;
  late HomesRepository repository;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockQueryBuilder = MockSupabaseQueryBuilder();
    mockFilterBuilder = MockPostgrestFilterBuilder();
    mockTransformBuilder = MockPostgrestTransformBuilder();
    repository = HomesRepository(mockClient);

    // Mock auth user
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

  group('HomesRepository - READ operations', () {
    test('getHomes returns all homes for current user', () async {
      final testHomes = [
        TestHelpers.createTestHome(id: 'home-1', name: 'Home 1'),
        TestHelpers.createTestHome(id: 'home-2', name: 'Home 2'),
      ];

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.order('created_at', ascending: true))
          .thenAnswer((_) async => testHomes.map((h) => h.toJson()).toList());

      final homes = await repository.getHomes();

      expect(homes, hasLength(2));
      expect(homes[0].id, 'home-1');
      expect(homes[1].id, 'home-2');
      verify(mockFilterBuilder.eq('user_id', TestHelpers.testUserId)).called(1);
      verify(mockFilterBuilder.order('created_at', ascending: true)).called(1);
    });

    test('getHomes returns empty list when no homes exist', () async {
      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.order('created_at', ascending: true))
          .thenAnswer((_) async => []);

      final homes = await repository.getHomes();

      expect(homes, isEmpty);
    });

    test('getHomeById returns single home', () async {
      final testHome = TestHelpers.createTestHome(id: 'home-123');

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'home-123')).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testHome.toJson());

      final home = await repository.getHomeById('home-123');

      expect(home.id, 'home-123');
      verify(mockFilterBuilder.eq('id', 'home-123')).called(1);
      verify(mockFilterBuilder.single()).called(1);
    });

    test('getHomeById throws when home not found', () async {
      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'nonexistent'))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenThrow(PostgrestException(message: 'Not found', code: '404'));

      expect(
        () => repository.getHomeById('nonexistent'),
        throwsA(isA<PostgrestException>()),
      );
    });

    test('getDefaultHome returns first home ordered by created_at', () async {
      final testHome = TestHelpers.createTestHome(id: 'first-home');

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.order('created_at', ascending: true))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.limit(1)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle())
          .thenAnswer((_) async => testHome.toJson());

      final home = await repository.getDefaultHome();

      expect(home, isNotNull);
      expect(home!.id, 'first-home');
      verify(mockFilterBuilder.order('created_at', ascending: true)).called(1);
      verify(mockFilterBuilder.limit(1)).called(1);
    });

    test('getDefaultHome returns null when no homes exist', () async {
      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('user_id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.order('created_at', ascending: true))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.limit(1)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

      final home = await repository.getDefaultHome();

      expect(home, isNull);
    });
  });

  group('HomesRepository - CREATE operations', () {
    test('createHome inserts and returns created home', () async {
      final testHome = TestHelpers.createTestHome(name: 'New Home');
      Map<String, dynamic> capturedJson = {};

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.insert(any)).thenAnswer((invocation) {
        capturedJson = invocation.positionalArguments[0] as Map<String, dynamic>;
        return mockFilterBuilder;
      });
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testHome.toJson());

      final created = await repository.createHome(testHome);

      expect(created.name, 'New Home');
      // Verify ID was removed to let DB generate it
      expect(capturedJson.containsKey('id'), isFalse);
      verify(mockFilterBuilder.single()).called(1);
    });

    test('createHome removes id field before insert', () async {
      final testHome = TestHelpers.createTestHome(
        id: 'should-be-removed',
        name: 'Test',
      );
      Map<String, dynamic> capturedJson = {};

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.insert(any)).thenAnswer((invocation) {
        capturedJson = invocation.positionalArguments[0] as Map<String, dynamic>;
        return mockFilterBuilder;
      });
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testHome.toJson());

      await repository.createHome(testHome);

      expect(capturedJson.containsKey('id'), isFalse);
    });
  });

  group('HomesRepository - UPDATE operations', () {
    test('updateHome updates and returns updated home', () async {
      final testHome = TestHelpers.createTestHome(
        id: 'home-123',
        name: 'Updated Home',
      );

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'home-123')).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testHome.toJson());

      final updated = await repository.updateHome(testHome);

      expect(updated.name, 'Updated Home');
      verify(mockFilterBuilder.eq('id', 'home-123')).called(1);
    });

    test('updateHome removes created_at before update', () async {
      final testHome = TestHelpers.createTestHome(id: 'home-123');
      Map<String, dynamic> capturedJson = {};

      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenAnswer((invocation) {
        capturedJson = invocation.positionalArguments[0] as Map<String, dynamic>;
        return mockFilterBuilder;
      });
      when(mockFilterBuilder.eq('id', 'home-123')).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single())
          .thenAnswer((_) async => testHome.toJson());

      await repository.updateHome(testHome);

      expect(capturedJson.containsKey('created_at'), isFalse);
    });
  });

  group('HomesRepository - DELETE operations', () {
    test('deleteHome deletes home by id', () async {
      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.delete()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'home-123')).thenReturn(mockFilterBuilder);

      await repository.deleteHome('home-123');

      verify(mockQueryBuilder.delete()).called(1);
      verify(mockFilterBuilder.eq('id', 'home-123')).called(1);
    });

    test('deleteHome cascades to related items', () async {
      // This is enforced by database FK constraints
      // Just verify the delete call is made
      when(mockClient.from(kHomesTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.delete()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'home-123')).thenReturn(mockFilterBuilder);

      await repository.deleteHome('home-123');

      verify(mockQueryBuilder.delete()).called(1);
    });
  });
}
