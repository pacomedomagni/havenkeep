import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import '../services/auth_repository.dart';
import '../services/push_notification_service.dart';
import 'demo_mode_provider.dart';

/// Provides the auth repository instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider));
});

/// Stream of API auth state changes.
final authStateProvider = StreamProvider<ApiAuthState>((ref) {
  return ref.watch(authRepositoryProvider).authStateChanges();
});

/// Whether the user is currently authenticated.
final isAuthenticatedProvider = Provider<bool>((ref) {
  // Check the API client's token state directly
  final client = ref.watch(apiClientProvider);

  // Also watch the auth state stream so we react to login/logout events
  ref.watch(authStateProvider);

  return client.isAuthenticated;
});

/// Current user profile from the API.
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

    try {
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
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sign in with email and password.
  Future<User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final repo = ref.read(authRepositoryProvider);

    try {
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
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sign in with Google.
  Future<User?> signInWithGoogle({required String idToken}) async {
    final repo = ref.read(authRepositoryProvider);

    try {
      final user = await repo.signInWithGoogle(idToken: idToken);

      _skipNextRebuild = true;
      state = AsyncValue.data(user);

      if (user != null) {
        _registerPushToken(user.id);
      }

      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sign in with Apple.
  Future<User?> signInWithApple({
    required String idToken,
    String? fullName,
  }) async {
    final repo = ref.read(authRepositoryProvider);

    try {
      final user = await repo.signInWithApple(
        idToken: idToken,
        fullName: fullName,
      );

      _skipNextRebuild = true;
      state = AsyncValue.data(user);

      if (user != null) {
        _registerPushToken(user.id);
      }

      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    await ref.read(authRepositoryProvider).signOut();
    ref.read(demoModeProvider.notifier).exitDemoMode();
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

  /// Request a password reset email.
  Future<void> forgotPassword({required String email}) async {
    await ref.read(authRepositoryProvider).forgotPassword(email: email);
  }

  /// Change password for the current user.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await ref.read(authRepositoryProvider).changePassword(
          currentPassword: currentPassword,
          newPassword: newPassword,
        );
  }

  /// Delete the current user's account permanently.
  Future<void> deleteAccount({required String password}) async {
    await ref.read(authRepositoryProvider).deleteAccount(password: password);
    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Delete an OAuth user's account (no password required).
  Future<void> deleteOAuthAccount() async {
    await ref.read(authRepositoryProvider).deleteOAuthAccount();
    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Sign out from all devices.
  Future<void> signOutAll() async {
    await ref.read(authRepositoryProvider).signOutAll();
    ref.read(demoModeProvider.notifier).exitDemoMode();
    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }
}
