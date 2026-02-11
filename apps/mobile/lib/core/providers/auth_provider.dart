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
  /// Flag to skip the auto-rebuild when we've already set the user
  /// from a sign-up/sign-in method (avoids race condition).
  bool _skipNextRebuild = false;

  @override
  Future<User?> build() async {
    // Re-fetch when auth state changes
    ref.watch(authStateProvider);

    // If we just set the user manually from sign-up/sign-in,
    // skip the rebuild to avoid a race where profile isn't yet in DB.
    if (_skipNextRebuild) {
      _skipNextRebuild = false;
      return state.valueOrNull;
    }

    final repo = ref.read(authRepositoryProvider);
    if (!repo.isAuthenticated) return null;

    try {
      return await repo.getCurrentUser();
    } catch (e) {
      debugPrint('[Auth] Failed to fetch user profile: $e');
      return null;
    }
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

    // signUpWithEmail creates both auth user AND public profile atomically,
    // so we set the user directly and skip the auth-state-triggered rebuild
    // to avoid a race where the profile query runs before insert completes.
    final user = await repo.signUpWithEmail(
      email: email,
      password: password,
      fullName: fullName,
      referralCode: referralCode,
    );

    _skipNextRebuild = true;
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

    _skipNextRebuild = true;
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
    _skipNextRebuild = false;
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
