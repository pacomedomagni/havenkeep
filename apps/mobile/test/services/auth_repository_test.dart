import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/auth_repository.dart';
import 'package:shared_models/shared_models.dart' as models;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/test_helpers.dart';
import 'auth_repository_test.mocks.dart';

@GenerateMocks([
  SupabaseClient,
  GoTrueClient,
  SupabaseQueryBuilder,
  PostgrestFilterBuilder,
])
void main() {
  late MockSupabaseClient mockClient;
  late MockGoTrueClient mockAuth;
  late MockSupabaseQueryBuilder mockQueryBuilder;
  late MockPostgrestFilterBuilder mockFilterBuilder;
  late AuthRepository repository;

  setUp(() {
    mockClient = MockSupabaseClient();
    mockAuth = MockGoTrueClient();
    mockQueryBuilder = MockSupabaseQueryBuilder();
    mockFilterBuilder = MockPostgrestFilterBuilder();
    repository = AuthRepository(mockClient);

    when(mockClient.auth).thenReturn(mockAuth);
  });

  group('AuthRepository - Auth State', () {
    test('authStateChanges returns stream of auth state changes', () {
      final streamController = StreamController<AuthState>();
      when(mockAuth.onAuthStateChange).thenAnswer((_) => streamController.stream);

      final stream = repository.authStateChanges();

      expect(stream, isA<Stream<AuthState>>());
      streamController.close();
    });

    test('currentSession returns current session', () {
      final session = Session(
        accessToken: 'test-token',
        tokenType: 'bearer',
        user: User(
          id: TestHelpers.testUserId,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      when(mockAuth.currentSession).thenReturn(session);

      expect(repository.currentSession, equals(session));
    });

    test('isAuthenticated returns true when user exists', () {
      final user = User(
        id: TestHelpers.testUserId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(user);

      expect(repository.isAuthenticated, isTrue);
    });

    test('isAuthenticated returns false when user is null', () {
      when(mockAuth.currentUser).thenReturn(null);

      expect(repository.isAuthenticated, isFalse);
    });
  });

  group('AuthRepository - Sign Up', () {
    test('signUpWithEmail creates auth user and profile', () async {
      final authUser = User(
        id: 'new-user-id',
        email: 'test@example.com',
        appMetadata: {},
        userMetadata: {'full_name': 'Test User'},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      final authResponse = AuthResponse(
        session: null,
        user: authUser,
      );

      final profileData = {
        'id': 'new-user-id',
        'email': 'test@example.com',
        'full_name': 'Test User',
        'auth_provider': 'email',
        'plan': 'free',
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      when(mockAuth.signUp(
        email: anyNamed('email'),
        password: anyNamed('password'),
        data: anyNamed('data'),
      )).thenAnswer((_) async => authResponse);

      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => profileData);

      final user = await repository.signUpWithEmail(
        email: 'test@example.com',
        password: 'password123',
        fullName: 'Test User',
      );

      expect(user, isNotNull);
      expect(user!.email, 'test@example.com');
      expect(user.fullName, 'Test User');

      verify(mockAuth.signUp(
        email: 'test@example.com',
        password: 'password123',
        data: {'full_name': 'Test User'},
      )).called(1);
    });

    test('signUpWithEmail links referral partner when code provided', () async {
      final authUser = User(
        id: 'new-user-id',
        email: 'test@example.com',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      final authResponse = AuthResponse(session: null, user: authUser);

      when(mockAuth.signUp(
        email: anyNamed('email'),
        password: anyNamed('password'),
        data: anyNamed('data'),
      )).thenAnswer((_) async => authResponse);

      // Mock referral partner lookup
      final mockReferralQueryBuilder = MockSupabaseQueryBuilder();
      final mockReferralFilterBuilder = MockPostgrestFilterBuilder();

      when(mockClient.from(kReferralPartnersTable))
          .thenReturn(mockReferralQueryBuilder);
      when(mockReferralQueryBuilder.select()).thenReturn(mockReferralFilterBuilder);
      when(mockReferralFilterBuilder.eq('referral_code', 'PARTNER123'))
          .thenReturn(mockReferralFilterBuilder);
      when(mockReferralFilterBuilder.eq('is_active', true))
          .thenReturn(mockReferralFilterBuilder);
      when(mockReferralFilterBuilder.maybeSingle())
          .thenAnswer((_) async => {'id': 'partner-id'});

      // Mock profile creation
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': 'new-user-id',
            'email': 'test@example.com',
            'full_name': 'Test User',
            'auth_provider': 'email',
            'referred_by': 'partner-id',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final user = await repository.signUpWithEmail(
        email: 'test@example.com',
        password: 'password123',
        fullName: 'Test User',
        referralCode: 'PARTNER123',
      );

      expect(user, isNotNull);
      expect(user!.referredBy, 'partner-id');

      verify(mockReferralFilterBuilder.eq('referral_code', 'PARTNER123')).called(1);
    });

    test('signUpWithEmail returns null when auth response has no user', () async {
      final authResponse = AuthResponse(session: null, user: null);

      when(mockAuth.signUp(
        email: anyNamed('email'),
        password: anyNamed('password'),
        data: anyNamed('data'),
      )).thenAnswer((_) async => authResponse);

      final user = await repository.signUpWithEmail(
        email: 'test@example.com',
        password: 'password123',
        fullName: 'Test User',
      );

      expect(user, isNull);
    });
  });

  group('AuthRepository - Sign In', () {
    test('signInWithEmail signs in and returns user profile', () async {
      final authResponse = AuthResponse(
        session: Session(
          accessToken: 'token',
          tokenType: 'bearer',
          user: User(
            id: TestHelpers.testUserId,
            appMetadata: {},
            userMetadata: {},
            aud: 'authenticated',
            createdAt: DateTime.now().toIso8601String(),
          ),
        ),
        user: User(
          id: TestHelpers.testUserId,
          appMetadata: {},
          userMetadata: {},
          aud: 'authenticated',
          createdAt: DateTime.now().toIso8601String(),
        ),
      );

      when(mockAuth.signInWithPassword(
        email: anyNamed('email'),
        password: anyNamed('password'),
      )).thenAnswer((_) async => authResponse);

      when(mockAuth.currentUser).thenReturn(authResponse.user);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => {
            'id': TestHelpers.testUserId,
            'email': 'test@example.com',
            'full_name': 'Test User',
            'auth_provider': 'email',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final user = await repository.signInWithEmail(
        email: 'test@example.com',
        password: 'password123',
      );

      expect(user, isNotNull);
      expect(user!.email, 'test@example.com');

      verify(mockAuth.signInWithPassword(
        email: 'test@example.com',
        password: 'password123',
      )).called(1);
    });

    test('signInWithGoogle calls OAuth with correct provider', () async {
      when(mockAuth.signInWithOAuth(
        any,
        redirectTo: anyNamed('redirectTo'),
      )).thenAnswer((_) async => true);

      await repository.signInWithGoogle();

      verify(mockAuth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'io.havenkeep.app://login-callback',
      )).called(1);
    });

    test('signInWithApple calls OAuth with correct provider', () async {
      when(mockAuth.signInWithOAuth(
        any,
        redirectTo: anyNamed('redirectTo'),
      )).thenAnswer((_) async => true);

      await repository.signInWithApple();

      verify(mockAuth.signInWithOAuth(
        OAuthProvider.apple,
        redirectTo: 'io.havenkeep.app://login-callback',
      )).called(1);
    });
  });

  group('AuthRepository - Sign Out', () {
    test('signOut calls auth signOut', () async {
      when(mockAuth.signOut()).thenAnswer((_) async => {});

      await repository.signOut();

      verify(mockAuth.signOut()).called(1);
    });
  });

  group('AuthRepository - User Profile', () {
    test('getCurrentUser returns user profile', () async {
      final user = User(
        id: TestHelpers.testUserId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(user);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => {
            'id': TestHelpers.testUserId,
            'email': 'test@example.com',
            'full_name': 'Test User',
            'auth_provider': 'email',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final profile = await repository.getCurrentUser();

      expect(profile, isNotNull);
      expect(profile!.id, TestHelpers.testUserId);
      expect(profile.email, 'test@example.com');
    });

    test('getCurrentUser returns null when not authenticated', () async {
      when(mockAuth.currentUser).thenReturn(null);

      final profile = await repository.getCurrentUser();

      expect(profile, isNull);
    });

    test('getCurrentUser returns null when profile not found', () async {
      final user = User(
        id: TestHelpers.testUserId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(user);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

      final profile = await repository.getCurrentUser();

      expect(profile, isNull);
    });

    test('updateProfile updates user fields', () async {
      final user = User(
        id: TestHelpers.testUserId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(user);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': TestHelpers.testUserId,
            'email': 'test@example.com',
            'full_name': 'Updated Name',
            'avatar_url': 'https://example.com/avatar.jpg',
            'auth_provider': 'email',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final updated = await repository.updateProfile(
        fullName: 'Updated Name',
        avatarUrl: 'https://example.com/avatar.jpg',
      );

      expect(updated.fullName, 'Updated Name');
      expect(updated.avatarUrl, 'https://example.com/avatar.jpg');

      verify(mockQueryBuilder.update({
        'full_name': 'Updated Name',
        'avatar_url': 'https://example.com/avatar.jpg',
      })).called(1);
    });

    test('updateProfile only updates provided fields', () async {
      final user = User(
        id: TestHelpers.testUserId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(user);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.update(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': TestHelpers.testUserId,
            'email': 'test@example.com',
            'full_name': 'Updated Name',
            'auth_provider': 'email',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      await repository.updateProfile(fullName: 'Updated Name');

      verify(mockQueryBuilder.update({'full_name': 'Updated Name'})).called(1);
    });
  });

  group('AuthRepository - OAuth Profile Creation', () {
    test('ensureProfile returns existing profile if found', () async {
      final authUser = User(
        id: TestHelpers.testUserId,
        email: 'test@example.com',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(authUser);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', TestHelpers.testUserId))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => {
            'id': TestHelpers.testUserId,
            'email': 'test@example.com',
            'full_name': 'Existing User',
            'auth_provider': 'google',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final profile = await repository.ensureProfile(authProvider: 'google');

      expect(profile.fullName, 'Existing User');
      verifyNever(mockQueryBuilder.insert(any));
    });

    test('ensureProfile creates new profile from OAuth metadata', () async {
      final authUser = User(
        id: 'new-oauth-user',
        email: 'oauth@example.com',
        appMetadata: {},
        userMetadata: {
          'full_name': 'OAuth User',
          'avatar_url': 'https://example.com/avatar.jpg',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(authUser);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'new-oauth-user'))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': 'new-oauth-user',
            'email': 'oauth@example.com',
            'full_name': 'OAuth User',
            'avatar_url': 'https://example.com/avatar.jpg',
            'auth_provider': 'google',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final profile = await repository.ensureProfile(authProvider: 'google');

      expect(profile.fullName, 'OAuth User');
      expect(profile.avatarUrl, 'https://example.com/avatar.jpg');
      expect(profile.authProvider, models.AuthProvider.google);

      verify(mockQueryBuilder.insert({
        'id': 'new-oauth-user',
        'email': 'oauth@example.com',
        'full_name': 'OAuth User',
        'avatar_url': 'https://example.com/avatar.jpg',
        'auth_provider': 'google',
      })).called(1);
    });

    test('ensureProfile uses name fallback when full_name not in metadata', () async {
      final authUser = User(
        id: 'new-oauth-user',
        email: 'oauth@example.com',
        appMetadata: {},
        userMetadata: {
          'name': 'OAuth Name',
        },
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(authUser);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'new-oauth-user'))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': 'new-oauth-user',
            'email': 'oauth@example.com',
            'full_name': 'OAuth Name',
            'auth_provider': 'google',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final profile = await repository.ensureProfile(authProvider: 'google');

      expect(profile.fullName, 'OAuth Name');
    });

    test('ensureProfile defaults to "User" when no name in metadata', () async {
      final authUser = User(
        id: 'new-oauth-user',
        email: 'oauth@example.com',
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: DateTime.now().toIso8601String(),
      );

      when(mockAuth.currentUser).thenReturn(authUser);
      when(mockClient.from(kUsersTable)).thenReturn(mockQueryBuilder);
      when(mockQueryBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.eq('id', 'new-oauth-user'))
          .thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.maybeSingle()).thenAnswer((_) async => null);

      when(mockQueryBuilder.insert(any)).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.select()).thenReturn(mockFilterBuilder);
      when(mockFilterBuilder.single()).thenAnswer((_) async => {
            'id': 'new-oauth-user',
            'email': 'oauth@example.com',
            'full_name': 'User',
            'auth_provider': 'google',
            'plan': 'free',
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          });

      final profile = await repository.ensureProfile(authProvider: 'google');

      expect(profile.fullName, 'User');
    });
  });
}
