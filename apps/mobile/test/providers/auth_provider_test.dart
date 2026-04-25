import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/providers/premium_provider.dart';
import 'package:havenkeep_mobile/core/services/auth_repository.dart';
import 'package:havenkeep_mobile/core/services/push_notification_service.dart';
import 'package:api_client/api_client.dart';

import '../helpers/test_helpers.dart';
import 'auth_provider_test.mocks.dart';

/// Minimal stub for PushNotificationService used in tests.
class _FakePushNotificationService extends Fake
    implements PushNotificationService {
  @override
  Future<void> registerToken(String userId) async {}
}

/// Minimal stub for PremiumService used in tests.
class _FakePremiumService extends Fake implements PremiumService {
  @override
  Future<void> logIn(String userId) async {}

  @override
  Future<void> logOut() async {}
}

@GenerateMocks([AuthRepository, ApiClient])
void main() {
  late MockAuthRepository mockAuthRepo;
  late MockApiClient mockApiClient;
  late ProviderContainer container;

  setUp(() {
    mockAuthRepo = MockAuthRepository();
    mockApiClient = MockApiClient();

    // Default stubs for ApiClient properties
    when(mockApiClient.isAuthenticated).thenReturn(false);
    when(mockApiClient.authStateChanges).thenAnswer((_) => const Stream.empty());
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer createContainer() {
    return ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(mockAuthRepo),
        apiClientProvider.overrideWithValue(mockApiClient),
        pushNotificationServiceProvider
            .overrideWithValue(_FakePushNotificationService()),
        premiumServiceProvider.overrideWithValue(_FakePremiumService()),
      ],
    );
  }

  group('CurrentUserNotifier', () {
    group('build', () {
      test('returns null when not authenticated', () async {
        when(mockAuthRepo.isAuthenticated).thenReturn(false);

        container = createContainer();

        final user = await container.read(currentUserProvider.future);

        expect(user, isNull);
      });

      test('fetches user when authenticated', () async {
        final testUser = TestHelpers.createTestUser(
          id: 'user-1',
          email: 'test@example.com',
        );

        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenAnswer((_) async => testUser);

        container = createContainer();

        final user = await container.read(currentUserProvider.future);

        expect(user, isNotNull);
        expect(user!.id, 'user-1');
        expect(user.email, 'test@example.com');
        verify(mockAuthRepo.getCurrentUser()).called(1);
      });

      test('returns null when getCurrentUser fails', () async {
        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenThrow(Exception('Network error'));

        container = createContainer();

        final user = await container.read(currentUserProvider.future);

        // Auth provider catches exceptions and returns null
        expect(user, isNull);
      });
    });

    group('signInWithEmail', () {
      test('sets user state on successful sign in', () async {
        final testUser = TestHelpers.createTestUser(
          id: 'user-1',
          email: 'test@example.com',
          fullName: 'Test User',
        );

        when(mockAuthRepo.isAuthenticated).thenReturn(false);
        when(mockAuthRepo.signInWithEmail(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenAnswer((_) async => testUser);

        container = createContainer();

        // Wait for initial build
        await container.read(currentUserProvider.future);

        final user = await container
            .read(currentUserProvider.notifier)
            .signInWithEmail(
              email: 'test@example.com',
              password: 'password123',
            );

        expect(user, isNotNull);
        expect(user!.id, 'user-1');
        expect(user.email, 'test@example.com');

        final currentUser = container.read(currentUserProvider).value;
        expect(currentUser, isNotNull);
        expect(currentUser!.id, 'user-1');
      });

      test('sets error state on failed sign in', () async {
        when(mockAuthRepo.isAuthenticated).thenReturn(false);
        when(mockAuthRepo.signInWithEmail(
          email: anyNamed('email'),
          password: anyNamed('password'),
        )).thenThrow(ApiException.fromResponse(401, 'Invalid credentials'));

        container = createContainer();
        await container.read(currentUserProvider.future);

        expect(
          () => container
              .read(currentUserProvider.notifier)
              .signInWithEmail(
                email: 'wrong@example.com',
                password: 'wrongpassword',
              ),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('signUpWithEmail', () {
      test('sets user state on successful sign up', () async {
        final testUser = TestHelpers.createTestUser(
          id: 'new-user',
          email: 'new@example.com',
          fullName: 'New User',
        );

        when(mockAuthRepo.isAuthenticated).thenReturn(false);
        when(mockAuthRepo.signUpWithEmail(
          email: anyNamed('email'),
          password: anyNamed('password'),
          fullName: anyNamed('fullName'),
          referralCode: anyNamed('referralCode'),
        )).thenAnswer((_) async => testUser);

        container = createContainer();
        await container.read(currentUserProvider.future);

        final user = await container
            .read(currentUserProvider.notifier)
            .signUpWithEmail(
              email: 'new@example.com',
              password: 'password123',
              fullName: 'New User',
            );

        expect(user, isNotNull);
        expect(user!.id, 'new-user');

        final currentUser = container.read(currentUserProvider).value;
        expect(currentUser!.id, 'new-user');
      });

      test('sets error state on failed sign up', () async {
        when(mockAuthRepo.isAuthenticated).thenReturn(false);
        when(mockAuthRepo.signUpWithEmail(
          email: anyNamed('email'),
          password: anyNamed('password'),
          fullName: anyNamed('fullName'),
          referralCode: anyNamed('referralCode'),
        )).thenThrow(ApiException.fromResponse(409, 'Email already in use'));

        container = createContainer();
        await container.read(currentUserProvider.future);

        expect(
          () => container
              .read(currentUserProvider.notifier)
              .signUpWithEmail(
                email: 'existing@example.com',
                password: 'password123',
                fullName: 'Test',
              ),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('signOut', () {
      test('clears user state on sign out', () async {
        final testUser = TestHelpers.createTestUser(id: 'user-1');

        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenAnswer((_) async => testUser);
        when(mockAuthRepo.signOut()).thenAnswer((_) async => {});

        container = createContainer();
        await container.read(currentUserProvider.future);

        final userBefore = container.read(currentUserProvider).value;
        expect(userBefore, isNotNull);

        await container.read(currentUserProvider.notifier).signOut();

        final userAfter = container.read(currentUserProvider).value;
        expect(userAfter, isNull);

        verify(mockAuthRepo.signOut()).called(1);
      });

      test('clears state even if API call fails', () async {
        final testUser = TestHelpers.createTestUser(id: 'user-1');

        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenAnswer((_) async => testUser);
        when(mockAuthRepo.signOut())
            .thenThrow(Exception('Network error'));

        container = createContainer();
        await container.read(currentUserProvider.future);

        await container.read(currentUserProvider.notifier).signOut();

        // State should still be cleared even if API fails
        final userAfter = container.read(currentUserProvider).value;
        expect(userAfter, isNull);
      });
    });

    group('updateProfile', () {
      test('updates user state after profile change', () async {
        final originalUser = TestHelpers.createTestUser(
          id: 'user-1',
          fullName: 'Original Name',
        );
        final updatedUser = TestHelpers.createTestUser(
          id: 'user-1',
          fullName: 'Updated Name',
        );

        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenAnswer((_) async => originalUser);
        when(mockAuthRepo.updateProfile(
          fullName: anyNamed('fullName'),
          avatarUrl: anyNamed('avatarUrl'),
        )).thenAnswer((_) async => updatedUser);

        container = createContainer();
        await container.read(currentUserProvider.future);

        await container.read(currentUserProvider.notifier).updateProfile(
              fullName: 'Updated Name',
            );

        final user = container.read(currentUserProvider).value;
        expect(user, isNotNull);
        expect(user!.fullName, 'Updated Name');
      });
    });

    group('deleteAccount', () {
      test('clears user state after account deletion', () async {
        final testUser = TestHelpers.createTestUser(id: 'user-1');

        when(mockAuthRepo.isAuthenticated).thenReturn(true);
        when(mockAuthRepo.getCurrentUser())
            .thenAnswer((_) async => testUser);
        when(mockAuthRepo.deleteAccount(password: anyNamed('password')))
            .thenAnswer((_) async => {});

        container = createContainer();
        await container.read(currentUserProvider.future);

        await container
            .read(currentUserProvider.notifier)
            .deleteAccount(password: 'password123');

        final userAfter = container.read(currentUserProvider).value;
        expect(userAfter, isNull);
      });
    });
  });

  group('isAuthenticatedProvider', () {
    test('returns false when not authenticated', () {
      when(mockApiClient.isAuthenticated).thenReturn(false);

      container = createContainer();

      final isAuth = container.read(isAuthenticatedProvider);
      expect(isAuth, isFalse);
    });

    test('returns true when authenticated', () {
      when(mockApiClient.isAuthenticated).thenReturn(true);

      container = createContainer();

      final isAuth = container.read(isAuthenticatedProvider);
      expect(isAuth, isTrue);
    });
  });
}
