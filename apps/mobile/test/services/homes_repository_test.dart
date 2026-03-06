import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/homes_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'homes_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late HomesRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = HomesRepository(mockClient);
  });

  group('HomesRepository', () {
    group('getHomes', () {
      test('calls correct endpoint and parses response', () async {
        when(mockClient.get('/api/v1/homes'))
            .thenAnswer((_) async => {
                  'data': [
                    {
                      'id': 'home-1',
                      'user_id': 'user-1',
                      'name': 'Main House',
                      'home_type': 'house',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                    {
                      'id': 'home-2',
                      'user_id': 'user-1',
                      'name': 'Beach House',
                      'home_type': 'condo',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  ],
                });

        final homes = await repository.getHomes();

        expect(homes, hasLength(2));
        expect(homes[0].id, 'home-1');
        expect(homes[0].name, 'Main House');
        expect(homes[0].homeType, HomeType.house);
        expect(homes[1].id, 'home-2');
        expect(homes[1].name, 'Beach House');
        expect(homes[1].homeType, HomeType.condo);

        verify(mockClient.get('/api/v1/homes')).called(1);
      });

      test('returns empty list when no homes', () async {
        when(mockClient.get('/api/v1/homes'))
            .thenAnswer((_) async => {'data': []});

        final homes = await repository.getHomes();

        expect(homes, isEmpty);
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get('/api/v1/homes'))
            .thenThrow(ApiException(500, 'Server error'));

        expect(
          () => repository.getHomes(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getHomeById', () {
      test('calls correct endpoint with home ID', () async {
        when(mockClient.get('/api/v1/homes/home-1'))
            .thenAnswer((_) async => {
                  'data': {
                    'id': 'home-1',
                    'user_id': 'user-1',
                    'name': 'Main House',
                    'home_type': 'house',
                    'address': '123 Main St',
                    'city': 'Springfield',
                    'state': 'IL',
                    'zip': '62704',
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final home = await repository.getHomeById('home-1');

        expect(home.id, 'home-1');
        expect(home.name, 'Main House');
        expect(home.address, '123 Main St');
        expect(home.city, 'Springfield');

        verify(mockClient.get('/api/v1/homes/home-1')).called(1);
      });
    });

    group('createHome', () {
      test('sends POST to correct endpoint and returns created home', () async {
        final newHome = TestHelpers.createTestHome(
          id: 'temp-id',
          name: 'New Home',
        );

        when(mockClient.post('/api/v1/homes', body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': {
                    'id': 'server-id',
                    'user_id': 'user-1',
                    'name': 'New Home',
                    'home_type': 'house',
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final created = await repository.createHome(newHome);

        expect(created.id, 'server-id');
        expect(created.name, 'New Home');

        // Verify the body was sent without 'id' field
        final captured = verify(
          mockClient.post('/api/v1/homes', body: captureAnyNamed('body')),
        ).captured.single as Map<String, dynamic>;
        expect(captured.containsKey('id'), isFalse);
        expect(captured['name'], 'New Home');
      });
    });

    group('updateHome', () {
      test('sends PUT to correct endpoint with home ID', () async {
        final home = TestHelpers.createTestHome(
          id: 'home-1',
          name: 'Updated Home',
        );

        when(mockClient.put('/api/v1/homes/home-1', body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': {
                    'id': 'home-1',
                    'user_id': 'user-1',
                    'name': 'Updated Home',
                    'home_type': 'house',
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final updated = await repository.updateHome(home);

        expect(updated.id, 'home-1');
        expect(updated.name, 'Updated Home');

        // Verify body excludes 'id' and 'created_at'
        final captured = verify(
          mockClient.put('/api/v1/homes/home-1', body: captureAnyNamed('body')),
        ).captured.single as Map<String, dynamic>;
        expect(captured.containsKey('id'), isFalse);
        expect(captured.containsKey('created_at'), isFalse);
      });
    });

    group('deleteHome', () {
      test('sends DELETE to correct endpoint', () async {
        when(mockClient.delete('/api/v1/homes/home-1'))
            .thenAnswer((_) async => {});

        await repository.deleteHome('home-1');

        verify(mockClient.delete('/api/v1/homes/home-1')).called(1);
      });

      test('rethrows error on delete failure', () async {
        when(mockClient.delete('/api/v1/homes/home-1'))
            .thenThrow(ApiException(404, 'Not found'));

        expect(
          () => repository.deleteHome('home-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getDefaultHome', () {
      test('returns first home when homes exist', () async {
        when(mockClient.get('/api/v1/homes'))
            .thenAnswer((_) async => {
                  'data': [
                    {
                      'id': 'home-1',
                      'user_id': 'user-1',
                      'name': 'First Home',
                      'home_type': 'house',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                    {
                      'id': 'home-2',
                      'user_id': 'user-1',
                      'name': 'Second Home',
                      'home_type': 'condo',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  ],
                });

        final home = await repository.getDefaultHome();

        expect(home, isNotNull);
        expect(home!.id, 'home-1');
      });

      test('returns null when no homes exist', () async {
        when(mockClient.get('/api/v1/homes'))
            .thenAnswer((_) async => {'data': []});

        final home = await repository.getDefaultHome();

        expect(home, isNull);
      });
    });
  });
}
