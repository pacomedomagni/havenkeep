import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/auth_repository.dart';
import 'package:api_client/api_client.dart';

import 'auth_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late AuthRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = AuthRepository(mockClient);
  });

  group('AuthRepository', () {
    group('isAuthenticated', () {
      test('delegates to ApiClient.isAuthenticated', () {
        when(mockClient.isAuthenticated).thenReturn(true);
        expect(repository.isAuthenticated, isTrue);

        when(mockClient.isAuthenticated).thenReturn(false);
        expect(repository.isAuthenticated, isFalse);
      });
    });

    group('signInWithEmail', () {
      test('sends correct request to login endpoint', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'login'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'test-access-token',
                    'refreshToken': 'test-refresh-token',
                    'user': {
                      'id': 'user-1',
                      'email': 'test@example.com',
                      'full_name': 'Test User',
                      'auth_provider': 'email',
                      'plan': 'free',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  },
                });
        when(mockClient.saveTokens(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          userId: anyNamed('userId'),
        )).thenAnswer((_) async => {});

        final user = await repository.signInWithEmail(
          email: 'test@example.com',
          password: 'password123',
        );

        expect(user, isNotNull);
        expect(user!.id, 'user-1');
        expect(user.email, 'test@example.com');

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'login'], body: {
          'email': 'test@example.com',
          'password': 'password123',
        })).called(1);

        verify(mockClient.saveTokens(
          accessToken: 'test-access-token',
          refreshToken: 'test-refresh-token',
          userId: 'user-1',
        )).called(1);
      });

      test('throws ApiException on invalid credentials', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'login'], body: anyNamed('body')))
            .thenThrow(ApiException.fromResponse(401, 'Invalid credentials'));

        expect(
          () => repository.signInWithEmail(
            email: 'wrong@example.com',
            password: 'wrong',
          ),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('signUpWithEmail', () {
      test('sends correct request to register endpoint', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'register'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'new-access-token',
                    'refreshToken': 'new-refresh-token',
                    'user': {
                      'id': 'new-user',
                      'email': 'new@example.com',
                      'full_name': 'New User',
                      'auth_provider': 'email',
                      'plan': 'free',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  },
                });
        when(mockClient.saveTokens(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          userId: anyNamed('userId'),
        )).thenAnswer((_) async => {});

        final user = await repository.signUpWithEmail(
          email: 'new@example.com',
          password: 'password123',
          fullName: 'New User',
        );

        expect(user, isNotNull);
        expect(user!.id, 'new-user');

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'register'], body: {
          'email': 'new@example.com',
          'password': 'password123',
          'fullName': 'New User',
        })).called(1);
      });

      test('includes referral code when provided', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'register'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'token',
                    'refreshToken': 'refresh',
                    'user': {
                      'id': 'user-1',
                      'email': 'test@example.com',
                      'full_name': 'Test',
                      'auth_provider': 'email',
                      'plan': 'free',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  },
                });
        when(mockClient.saveTokens(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          userId: anyNamed('userId'),
        )).thenAnswer((_) async => {});

        await repository.signUpWithEmail(
          email: 'test@example.com',
          password: 'password123',
          fullName: 'Test',
          referralCode: 'REF-ABC',
        );

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'register'], body: {
          'email': 'test@example.com',
          'password': 'password123',
          'fullName': 'Test',
          'referralCode': 'REF-ABC',
        })).called(1);
      });

      test('throws on invalid response format', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'register'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'token',
                    // Missing refreshToken and user — should reject.
                  },
                });

        expect(
          () => repository.signUpWithEmail(
            email: 'test@example.com',
            password: 'password123',
            fullName: 'Test',
          ),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getCurrentUser', () {
      test('returns null when not authenticated', () async {
        when(mockClient.isAuthenticated).thenReturn(false);

        final user = await repository.getCurrentUser();

        expect(user, isNull);
        verifyNever(mockClient.get(pathSegments: anyNamed('pathSegments')));
      });

      test('parses data[data] correctly', () async {
        // This tests the specific pattern: data['data'] where the API wraps
        // the user object inside a 'data' key.
        when(mockClient.isAuthenticated).thenReturn(true);
        when(mockClient.get(pathSegments: const ['api', 'v1', 'users', 'me']))
            .thenAnswer((_) async => {
                  'data': {
                    'id': 'user-1',
                    'email': 'test@example.com',
                    'full_name': 'Test User',
                    'auth_provider': 'email',
                    'plan': 'free',
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final user = await repository.getCurrentUser();

        expect(user, isNotNull);
        expect(user!.id, 'user-1');
        expect(user.email, 'test@example.com');
        expect(user.fullName, 'Test User');
      });

      test('returns null when data[data] is not a Map', () async {
        when(mockClient.isAuthenticated).thenReturn(true);
        when(mockClient.get(pathSegments: const ['api', 'v1', 'users', 'me']))
            .thenAnswer((_) async => {
                  'data': 'not a map',
                });

        final user = await repository.getCurrentUser();

        expect(user, isNull);
      });

      test('returns null on 401 ApiException', () async {
        when(mockClient.isAuthenticated).thenReturn(true);
        when(mockClient.get(pathSegments: const ['api', 'v1', 'users', 'me']))
            .thenThrow(ApiException.fromResponse(401, 'Unauthorized'));

        final user = await repository.getCurrentUser();

        expect(user, isNull);
      });

      test('rethrows non-401 ApiException', () async {
        when(mockClient.isAuthenticated).thenReturn(true);
        when(mockClient.get(pathSegments: const ['api', 'v1', 'users', 'me']))
            .thenThrow(ApiException.fromResponse(500, 'Server error'));

        expect(
          () => repository.getCurrentUser(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('updateProfile', () {
      test('sends correct PUT request', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'users', 'me'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': {
                    'id': 'user-1',
                    'email': 'test@example.com',
                    'full_name': 'Updated Name',
                    'auth_provider': 'email',
                    'plan': 'free',
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final user = await repository.updateProfile(fullName: 'Updated Name');

        expect(user.fullName, 'Updated Name');
        verify(mockClient.put(pathSegments: const ['api', 'v1', 'users', 'me'], body: {
          'fullName': 'Updated Name',
        })).called(1);
      });
    });

    group('forgotPassword', () {
      test('sends email to forgot-password endpoint', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'forgot-password'],
                body: anyNamed('body')))
            .thenAnswer((_) async => {});

        await repository.forgotPassword(email: 'test@example.com');

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'forgot-password'], body: {
          'email': 'test@example.com',
        })).called(1);
      });
    });

    group('changePassword', () {
      test('sends correct request to change password', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'users', 'me', 'password'],
                body: anyNamed('body')))
            .thenAnswer((_) async => {});

        await repository.changePassword(
          currentPassword: 'old-password',
          newPassword: 'new-password',
        );

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'users', 'me', 'password'], body: {
          'currentPassword': 'old-password',
          'newPassword': 'new-password',
        })).called(1);
      });
    });

    group('deleteAccount', () {
      test('sends DELETE request with password', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'users', 'me'], body: anyNamed('body')))
            .thenAnswer((_) async => {});
        when(mockClient.clearTokens()).thenAnswer((_) async => {});

        await repository.deleteAccount(password: 'password123');

        verify(mockClient.delete(pathSegments: const ['api', 'v1', 'users', 'me'], body: {
          'password': 'password123',
        })).called(1);
        verify(mockClient.clearTokens()).called(1);
      });
    });

    group('deleteOAuthAccount', () {
      test('sends DELETE request with confirmDelete flag', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'users', 'me'], body: anyNamed('body')))
            .thenAnswer((_) async => {});
        when(mockClient.clearTokens()).thenAnswer((_) async => {});

        await repository.deleteOAuthAccount();

        verify(mockClient.delete(pathSegments: const ['api', 'v1', 'users', 'me'], body: {
          'confirmDelete': true,
        })).called(1);
        verify(mockClient.clearTokens()).called(1);
      });
    });

    group('signInWithGoogle', () {
      test('sends Google ID token to correct endpoint', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'google'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'google-access-token',
                    'refreshToken': 'google-refresh-token',
                    'user': {
                      'id': 'google-user',
                      'email': 'google@example.com',
                      'full_name': 'Google User',
                      'auth_provider': 'google',
                      'plan': 'free',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  },
                });
        when(mockClient.saveTokens(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          userId: anyNamed('userId'),
        )).thenAnswer((_) async => {});

        final user = await repository.signInWithGoogle(idToken: 'google-id-token');

        expect(user, isNotNull);
        expect(user!.id, 'google-user');

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'google'], body: {
          'idToken': 'google-id-token',
        })).called(1);
      });
    });

    group('signInWithApple', () {
      test('sends Apple ID token to correct endpoint', () async {
        when(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'apple'], body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'success': true,
                  'data': {
                    'accessToken': 'apple-access-token',
                    'refreshToken': 'apple-refresh-token',
                    'user': {
                      'id': 'apple-user',
                      'email': 'apple@example.com',
                      'full_name': 'Apple User',
                      'auth_provider': 'apple',
                      'plan': 'free',
                      'created_at': '2026-01-01T00:00:00.000Z',
                      'updated_at': '2026-01-01T00:00:00.000Z',
                    },
                  },
                });
        when(mockClient.saveTokens(
          accessToken: anyNamed('accessToken'),
          refreshToken: anyNamed('refreshToken'),
          userId: anyNamed('userId'),
        )).thenAnswer((_) async => {});

        final user = await repository.signInWithApple(
          idToken: 'apple-id-token',
          nonce: 'apple-nonce-raw',
          fullName: 'Apple User',
        );

        expect(user, isNotNull);
        expect(user!.id, 'apple-user');

        verify(mockClient.post(pathSegments: const ['api', 'v1', 'auth', 'apple'], body: {
          'idToken': 'apple-id-token',
          'nonce': 'apple-nonce-raw',
          'fullName': 'Apple User',
        })).called(1);
      });
    });
  });
}
