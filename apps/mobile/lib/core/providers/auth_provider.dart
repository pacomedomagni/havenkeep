import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';
import '../database/database.dart';
import '../services/auth_repository.dart';
import '../services/push_notification_service.dart';
import '../services/secure_storage_service.dart';
import 'demo_mode_provider.dart';
import 'documents_provider.dart';
import 'items_provider.dart';
import 'maintenance_provider.dart';
import 'notifications_provider.dart';
import 'premium_provider.dart';
import 'warranty_claims_provider.dart';
import 'warranty_purchases_provider.dart';
import 'homes_provider.dart';
import 'email_scanner_provider.dart';

/// Provides the auth repository instance.
final authRepositoryProvider = Provider<AuthRepository>((ref) {
  return AuthRepository(ref.read(apiClientProvider));
});

/// Stream of API auth state changes.
///
/// Seeds with the current auth state so that providers don't stay stuck
/// in AsyncLoading when the broadcast-stream event from `restoreSession()`
/// was emitted before this subscription started.
final authStateProvider = StreamProvider<ApiAuthState>((ref) async* {
  final client = ref.watch(apiClientProvider);

  // Emit current state immediately so downstream providers resolve
  if (client.isAuthenticated) {
    yield ApiAuthState.signedIn;
  }

  // Then forward all future state changes
  await for (final state in client.authStateChanges) {
    yield state;
  }
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
        await _bindActiveUser(user.id);
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
        await _bindActiveUser(user.id);
        _registerPushToken(user.id);

        // Log in to RevenueCat with authenticated user
        try {
          await ref.read(premiumServiceProvider).logIn(user.id);
        } catch (e) {
          debugPrint('[Auth] RevenueCat login failed (non-fatal): $e');
        }
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
        await _bindActiveUser(user.id);
        _registerPushToken(user.id);

        // Log in to RevenueCat with authenticated user
        try {
          await ref.read(premiumServiceProvider).logIn(user.id);
        } catch (e) {
          debugPrint('[Auth] RevenueCat login failed (non-fatal): $e');
        }
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
        await _bindActiveUser(user.id);
        _registerPushToken(user.id);

        // Log in to RevenueCat with authenticated user
        try {
          await ref.read(premiumServiceProvider).logIn(user.id);
        } catch (e) {
          debugPrint('[Auth] RevenueCat login failed (non-fatal): $e');
        }
      }

      return user;
    } catch (e, st) {
      state = AsyncValue.error(e, st);
      rethrow;
    }
  }

  /// Sign out.
  Future<void> signOut() async {
    final userId = state.valueOrNull?.id;

    try {
      await ref.read(authRepositoryProvider).signOut();
    } catch (e) {
      debugPrint('[Auth] API signOut failed (non-fatal): $e');
    }

    try {
      ref.read(demoModeProvider.notifier).exitDemoMode();
    } catch (e) {
      debugPrint('[Auth] exitDemoMode failed (non-fatal): $e');
    }

    // Log out of RevenueCat to prevent stale premium status
    try {
      await ref.read(premiumServiceProvider).logOut();
    } catch (e) {
      debugPrint('[Auth] RevenueCat logout failed (non-fatal): $e');
    }

    // Wipe local state BEFORE invalidating providers so any disposers
    // that grab the DB find an empty file (or no file at all).
    await _wipeLocalState(userId: userId);

    // Invalidate all data providers to prevent stale data between accounts
    _safeInvalidateAll();

    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Update profile.
  ///
  /// Keeps the current user value visible during the PUT instead of
  /// flapping every consumer (dashboard / settings / claims) through an
  /// `AsyncLoading` state — see C117. On failure we rethrow so callers
  /// can show a snackbar without losing the previously rendered profile.
  Future<void> updateProfile({String? fullName, String? avatarUrl}) async {
    final previous = state.valueOrNull;
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            fullName: fullName,
            avatarUrl: avatarUrl,
          );
      _skipNextRebuild = true;
      state = AsyncValue.data(user);
    } catch (e, st) {
      // Restore the previously rendered user so the UI keeps showing
      // the old name/avatar instead of flashing an empty profile.
      state = previous == null
          ? AsyncValue.error(e, st)
          : AsyncValue.data(previous);
      rethrow;
    }
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

  /// Request email change — sends a verification to the new address.
  Future<void> requestEmailChange({
    required String newEmail,
    required String password,
  }) async {
    await ref.read(authRepositoryProvider).requestEmailChange(
          newEmail: newEmail,
          password: password,
        );
  }

  /// Delete the current user's account permanently.
  Future<void> deleteAccount({required String password}) async {
    final userId = state.valueOrNull?.id;
    await ref.read(authRepositoryProvider).deleteAccount(password: password);
    await _wipeLocalState(userId: userId);
    _safeInvalidateAll();
    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Delete an OAuth user's account (no password required).
  Future<void> deleteOAuthAccount() async {
    final userId = state.valueOrNull?.id;
    await ref.read(authRepositoryProvider).deleteOAuthAccount();
    await _wipeLocalState(userId: userId);
    _safeInvalidateAll();
    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Sign out from all devices.
  Future<void> signOutAll() async {
    final userId = state.valueOrNull?.id;

    try {
      await ref.read(authRepositoryProvider).signOutAll();
    } catch (e) {
      debugPrint('[Auth] API signOutAll failed (non-fatal): $e');
    }

    try {
      ref.read(demoModeProvider.notifier).exitDemoMode();
    } catch (e) {
      debugPrint('[Auth] exitDemoMode failed (non-fatal): $e');
    }

    // Log out of RevenueCat to prevent stale premium status
    try {
      await ref.read(premiumServiceProvider).logOut();
    } catch (e) {
      debugPrint('[Auth] RevenueCat logout failed (non-fatal): $e');
    }

    await _wipeLocalState(userId: userId);

    // Invalidate all data providers to prevent stale data between accounts
    _safeInvalidateAll();

    _skipNextRebuild = false;
    state = const AsyncValue.data(null);
  }

  /// Wipe every piece of local state tied to [userId] (or the currently
  /// active user when null): the per-user encrypted DB file, the in-memory
  /// caches, the offline queue, all secure-storage keys (tokens, biometric
  /// pref, push token, DB encryption key, etc.), and the active-user
  /// pointer used by the database opener.
  ///
  /// Catches and logs each failure so a partial wipe never blocks logout
  /// — but keeps going through the rest of the cleanup.
  Future<void> _wipeLocalState({required String? userId}) async {
    final effectiveUserId =
        userId ?? await SecureStorageService.getActiveUserId();

    // 1. Drop in-memory caches and close + delete the per-user DB file.
    try {
      final db = ref.read(localDatabaseProvider);
      await db.clearAllItems();
      await db.clearAllQueueEntries();
      await db.clearAllConflicts();
      await db.close();
    } catch (e) {
      debugPrint('[Auth] DB wipe failed (non-fatal): $e');
    }

    try {
      await deleteDatabaseFile(userId: effectiveUserId);
    } catch (e) {
      debugPrint('[Auth] DB file delete failed (non-fatal): $e');
    }

    // 2. Clear ALL secure-storage entries — tokens, encryption key, biometric
    //    pref, etc. The next sign-in will regenerate what it needs.
    try {
      await SecureStorageService.clearAll();
    } catch (e) {
      debugPrint('[Auth] SecureStorage clear failed (non-fatal): $e');
    }

    // 3. Drop the active-user pointer the DB opener consults.
    setActiveDatabaseUser(null);

    // 4. Force the next [localDatabaseProvider] read to reconstruct against
    //    the (now empty) state.
    try {
      ref.invalidate(localDatabaseProvider);
    } catch (_) {}
  }

  /// Persist the active user id so the database opener can scope per user
  /// across cold starts.
  Future<void> _bindActiveUser(String userId) async {
    setActiveDatabaseUser(userId);
    await SecureStorageService.setActiveUserId(userId);
    // Force a fresh DB instance bound to this user's file.
    try {
      ref.invalidate(localDatabaseProvider);
    } catch (_) {}
  }

  /// Safely invalidate all data providers (won't crash if any fail).
  void _safeInvalidateAll() {
    try { ref.invalidate(itemsProvider); } catch (_) {}
    try { ref.invalidate(archivedItemsProvider); } catch (_) {}
    try { ref.invalidate(homesProvider); } catch (_) {}
    try { ref.invalidate(selectedHomeIdProvider); } catch (_) {}
    try { ref.invalidate(notificationsProvider); } catch (_) {}
    try { ref.invalidate(unreadNotificationCountProvider); } catch (_) {}
    try { ref.invalidate(notificationPreferencesProvider); } catch (_) {}
    try { ref.invalidate(warrantyPurchasesProvider); } catch (_) {}
    try { ref.invalidate(claimsProvider); } catch (_) {}
    try { ref.invalidate(claimSavingsProvider); } catch (_) {}
    try { ref.invalidate(maintenanceSchedulesProvider); } catch (_) {}
    try { ref.invalidate(maintenanceDueProvider); } catch (_) {}
    try { ref.invalidate(maintenanceHistoryProvider); } catch (_) {}
    try { ref.invalidate(allDocumentsProvider); } catch (_) {}
    try { ref.invalidate(emailScansProvider); } catch (_) {}
  }
}
