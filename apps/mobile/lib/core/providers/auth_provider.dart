import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';
import '../services/auth_repository.dart';
import '../services/push_notification_service.dart';

/// Provides the auth repository instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(supabaseClientProvider));
});

/// Stream of Supabase auth state changes.
final authStateProvider = StreamProvider<AuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Whether the user is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  final authState = ref.watch(authStateProvider);
  return authState.whenOrNull(
        data: (state) => state.session != null,
      ) ??
      false;
});

/// Current user profile from public.users.
final currentUserProvider =
    AsyncNotifierProvider<CurrentUserNotifier, User?>(
  () => CurrentUserNotifier(),
);

class CurrentUserNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    // Re-fetch when auth state changes
    ref.watch(authStateProvider);

    final repo = ref.read(authRepositoryProvider);
    if (!repo.isAuthenticated) return null;

    return repo.getCurrentUser();
  }

  /// Register push notification token for the current user.
  Future<void> _registerPushToken(String userId) async {
    try {
      final pushService = ref.read(pushNotificationServiceProvider);
      await pushService.registerToken(userId);
    } catch (e) {
      debugPrint('[Auth] Push token registration failed: $e');
    }
  }

  /// Sign up with email and password.
  Future<User?> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? referralCode,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.signUpWithEmail(
      email: email,
      password: password,
      fullName: fullName,
      referralCode: referralCode,
    );
    state = AsyncValue.data(user);

    // Register push token after signup
    if (user != null) {
      _registerPushToken(user.id);
    }

    return user;
  }

  /// Sign in with email and password.
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);
    final user = await repo.signInWithEmail(
      email: email,
      password: password,
    );
    state = AsyncValue.data(user);

    // Register push token after login
    if (user != null) {
      _registerPushToken(user.id);
    }

    return user;
  }

  /// Sign in with Google.
  Future<void> signInWithGoogle() async {
    await ref.read(authRepositoryProvider).signInWithGoogle();
  }

  /// Sign in with Apple.
  Future<void> signInWithApple() async {
    await ref.read(authRepositoryProvider).signInWithApple();
  }

  /// Sign out.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    state = const AsyncValue.data(null);
  }

  /// Update profile.
  Future<void> updateProfile({String? fullName, String? avatarUrl}) async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            fullName: fullName,
            avatarUrl: avatarUrl,
          );
      return user;
    });
  }
}
