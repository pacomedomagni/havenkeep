import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  @override
  Future<User?> build() async {
    // Listen (not watch) the auth stream so we don't re-trigger build()
    // on every emission. Direct sign-in / sign-up handlers in this
    // notifier already set `state` themselves; the stream listener
    // exists only to clear the user on sign-out events that originate
    // outside the notifier (e.g. server force-revoke). This replaces
    // the previous `_skipNextRebuild` flag, which was a workaround for
    // the same race where post-sign-up the profile wasn't yet visible
    // to /users/me (C116).
    ref.listen<AsyncValue<ApiAuthState>>(authStateProvider, (previous, next) {
      final value = next.valueOrNull;
      if (value == ApiAuthState.signedOut) {
        if (state.valueOrNull != null) {
          state = const AsyncValue.data(null);
        }
      }
      // signedIn / tokenRefreshed: leave state alone — sign-in handlers
      // already populated it, and a token refresh doesn't change the
      // user identity.
    });

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
  Future<User?> signInWithGoogle({
    required String idToken,
    String? referralCode,
  }) async {
    final repo = ref.read(authRepositoryProvider);

    try {
      final user = await repo.signInWithGoogle(
        idToken: idToken,
        referralCode: referralCode,
      );

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
    required String nonce,
    String? fullName,
    String? referralCode,
  }) async {
    final repo = ref.read(authRepositoryProvider);

    try {
      final user = await repo.signInWithApple(
        idToken: idToken,
        nonce: nonce,
        fullName: fullName,
        referralCode: referralCode,
      );

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

    state = const AsyncValue.data(null);
  }

  /// Update profile.
  ///
  /// Keeps the current user value visible during the PUT instead of
  /// flapping every consumer (dashboard / settings / claims) through an
  /// `AsyncLoading` state — see C117. On failure we rethrow so callers
  /// can show a snackbar without losing the previously rendered profile.
  Future<void> updateProfile({String? fullName}) async {
    final previous = state.valueOrNull;
    try {
      final user = await ref.read(authRepositoryProvider).updateProfile(
            fullName: fullName,
          );
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

  /// C0-14: cancel a pending account deletion using the short-lived
  /// recovery token the API hands back on a within-grace login.
  ///
  /// Doesn't go through [AuthRepository] because the repo paths assume
  /// the client carries the user's normal access token — here the
  /// recovery JWT is the credential. After a successful recover, the
  /// user is back to "soft-deleted=false, plan=their-original" on the
  /// server side; they still need to sign in normally to obtain real
  /// access/refresh tokens.
  Future<void> recoverAccount(String recoveryToken) async {
    await ref.read(apiClientProvider).recoverAccount(recoveryToken);
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
    state = const AsyncValue.data(null);
  }

  /// Delete an OAuth user's account (no password required).
  Future<void> deleteOAuthAccount() async {
    final userId = state.valueOrNull?.id;
    await ref.read(authRepositoryProvider).deleteOAuthAccount();
    await _wipeLocalState(userId: userId);
    _safeInvalidateAll();
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

    // 3. Clear cross-user SharedPreferences artefacts. The deep-link gift
    //    flow stashes 'pending_gift_code' for unauthenticated visitors —
    //    if user A leaves a half-redeemed code on a shared device and
    //    user B signs in afterwards, the stale code must not auto-replay
    //    on user B's session. Audit finding C5.
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('pending_gift_code');
    } catch (e) {
      debugPrint('[Auth] SharedPreferences cleanup failed (non-fatal): $e');
    }

    // 4. Drop the active-user pointer the DB opener consults.
    setActiveDatabaseUser(null);

    // 5. Force the next [localDatabaseProvider] read to reconstruct against
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
    try { ref.invalidate(maintenanceHistoryByItemProvider); } catch (_) {}
    try { ref.invalidate(allDocumentsProvider); } catch (_) {}
    try { ref.invalidate(emailScansProvider); } catch (_) {}
  }
}
