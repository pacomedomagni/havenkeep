import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart' as models;

/// Handles authentication and user profile operations via the Express API.
class AuthRepository {
  final ApiClient _client;

  AuthRepository(this._client);

  // ============================================
  // AUTH STATE
  // ============================================

  /// Stream of auth state changes.
  Stream<ApiAuthState> authStateChanges() {
    return _client.authStateChanges;
  }

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _client.isAuthenticated;

  // ============================================
  // SIGN UP / SIGN IN
  // ============================================

  /// Sign up with email and password.
  Future<models.User?> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? referralCode,
  }) async {
    final body = <String, dynamic>{
      'email': email,
      'password': password,
      'fullName': fullName,
    };

    if (referralCode != null) {
      body['referralCode'] = referralCode;
    }

    final data = await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'register'],
      body: body,
    );

    final user = _extractUserAndTokens(data);
    return user;
  }

  /// Sign in with email and password.
  Future<models.User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final data = await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'login'],
      body: {
        'email': email,
        'password': password,
      },
    );

    final user = _extractUserAndTokens(data);
    return user;
  }

  /// Sign in with Google. Accepts the Google ID token from the platform SDK.
  ///
  /// H63: forward `referralCode` on first sign-up so OAuth users get the
  /// same attribution path the email flow gives. The server treats it as
  /// optional and ignores it on returning-user sign-ins.
  Future<models.User?> signInWithGoogle({
    required String idToken,
    String? referralCode,
  }) async {
    final body = <String, dynamic>{'idToken': idToken};
    if (referralCode != null && referralCode.isNotEmpty) {
      body['referralCode'] = referralCode;
    }
    final data = await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'google'],
      body: body,
    );

    final user = _extractUserAndTokens(data);
    return user;
  }

  /// Sign in with Apple. Accepts the Apple ID token from the platform SDK
  /// plus the *unhashed* per-attempt nonce. The server hashes it again and
  /// verifies the result against the `nonce` claim Apple baked into the
  /// token (S1-H — replay protection).
  Future<models.User?> signInWithApple({
    required String idToken,
    required String nonce,
    String? fullName,
    String? referralCode,
  }) async {
    final body = <String, dynamic>{
      'idToken': idToken,
      'nonce': nonce,
    };
    if (fullName != null) body['fullName'] = fullName;
    // H63: same plumbing as Google so referral attribution survives the
    // OAuth path on first sign-up.
    if (referralCode != null && referralCode.isNotEmpty) {
      body['referralCode'] = referralCode;
    }

    final data = await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'apple'],
      body: body,
    );

    final user = _extractUserAndTokens(data);
    return user;
  }

  /// Sign out the current user.
  ///
  /// If the API call fails, retries once after a short delay before
  /// clearing tokens locally. Reads `refresh_token` ONCE up front so a
  /// retry can never race with the keychain delete in the `finally`
  /// branch (C111) — a missing refresh token would silently let the
  /// server keep the session live.
  Future<void> signOut() async {
    // H51: read the refresh token through the SAME FlutterSecureStorage
    // instance ApiClient uses. The prior duplicate FlutterSecureStorage
    // here specified KeychainAccessibility.first_unlock while ApiClient
    // writes with first_unlock_this_device — on iOS those are separate
    // keychain items, so the read returned null and the logout request
    // body was empty (server couldn't revoke that specific token).
    String? refreshToken;
    try {
      refreshToken = await _client.readRefreshTokenForLogout();
    } catch (e) {
      debugPrint('[Auth] Reading refresh token before logout failed: $e');
    }

    try {
      await _signOutApiCall(refreshToken);
    } catch (e) {
      debugPrint('[Auth] Logout API call failed, retrying once: $e');
      try {
        await Future.delayed(const Duration(seconds: 1));
        await _signOutApiCall(refreshToken);
      } catch (retryError) {
        debugPrint('[Auth] Logout API retry also failed: $retryError');
      }
    } finally {
      await _client.clearTokens();
    }
  }

  /// Performs the actual logout API call. Receives the refresh token as
  /// a parameter so concurrent keychain access can't race against the
  /// post-logout `clearTokens` (see [signOut]).
  Future<void> _signOutApiCall(String? refreshToken) async {
    await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'logout'],
      body: {
        if (refreshToken != null) 'refreshToken': refreshToken,
      },
    );
  }

  /// Sign out from all devices.
  Future<void> signOutAll() async {
    try {
      await _client.post(
        pathSegments: const ['api', 'v1', 'auth', 'logout-all'],
      );
    } catch (e) {
      debugPrint('[Auth] Logout-all API call failed: $e');
    } finally {
      await _client.clearTokens();
    }
  }

  // ============================================
  // USER PROFILE
  // ============================================

  /// Get the current user's profile.
  Future<models.User?> getCurrentUser() async {
    if (!_client.isAuthenticated) return null;

    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'users', 'me'],
      );
      final userJson = data['data'];
      if (userJson is! Map<String, dynamic>) return null;
      return models.User.fromJson(userJson);
    } on ApiAuthRequiredException {
      return null;
    }
  }

  /// Update the current user's profile.
  ///
  /// 1.7: avatar URL is no longer settable here. Avatars are uploaded
  /// via POST /uploads/avatar which writes the MinIO object key
  /// directly; the /me response mints a fresh presigned URL on every
  /// fetch. To change the avatar, use [ImageUploadService.uploadProfilePhoto]
  /// then `ref.invalidate(currentUserProvider)`.
  Future<models.User> updateProfile({
    String? fullName,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['fullName'] = fullName;

    final data = await _client.put(
      pathSegments: const ['api', 'v1', 'users', 'me'],
      body: updates,
    );
    final userJson = data['data'];
    if (userJson is! Map<String, dynamic>) {
      throw const ApiServerException(500, 'Invalid response format');
    }
    return models.User.fromJson(userJson);
  }

  // ============================================
  // PASSWORD MANAGEMENT
  // ============================================

  /// Request a password reset email.
  Future<void> forgotPassword({required String email}) async {
    await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'forgot-password'],
      body: {
        'email': email,
      },
    );
  }

  /// Reset password with a token (from email link).
  Future<void> resetPassword({
    required String token,
    required String newPassword,
  }) async {
    await _client.post(
      pathSegments: const ['api', 'v1', 'auth', 'reset-password'],
      body: {
        'token': token,
        'newPassword': newPassword,
      },
    );
  }

  /// Change password for the current user (authenticated).
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.put(
      pathSegments: const ['api', 'v1', 'users', 'me', 'password'],
      body: {
        'currentPassword': currentPassword,
        'newPassword': newPassword,
      },
    );
  }

  // ============================================
  // EMAIL MANAGEMENT
  // ============================================

  /// Request an email change. Sends a verification email to the new address.
  Future<void> requestEmailChange({
    required String newEmail,
    required String password,
  }) async {
    await _client.post(
      pathSegments: const ['api', 'v1', 'users', 'me', 'change-email'],
      body: {
        'newEmail': newEmail,
        'password': password,
      },
    );
  }

  // ============================================
  // ACCOUNT MANAGEMENT
  // ============================================

  /// Delete the current user's account permanently.
  Future<void> deleteAccount({required String password}) async {
    await _client.delete(
      pathSegments: const ['api', 'v1', 'users', 'me'],
      body: {
        'password': password,
      },
    );
    await _client.clearTokens();
  }

  /// Delete an OAuth user's account (no password required).
  Future<void> deleteOAuthAccount() async {
    await _client.delete(
      pathSegments: const ['api', 'v1', 'users', 'me'],
      body: {
        'confirmDelete': true,
      },
    );
    await _client.clearTokens();
  }

  /// Safely extract tokens and user from an auth response body.
  ///
  /// The API has standardized on `{ success, data: { ... } }` for every
  /// auth endpoint. Anything that doesn't match the envelope is rejected
  /// with a specific error code so we don't fall back to a legacy flat
  /// shape and produce a misleading parse failure (C112).
  Future<models.User?> _extractUserAndTokens(Map<String, dynamic> body) async {
    final inner = body['data'];
    if (inner is! Map<String, dynamic>) {
      throw const ApiServerException(
        500,
        'Auth response missing `data` envelope',
      );
    }
    final accessToken = inner['accessToken'];
    final refreshToken = inner['refreshToken'];
    final userRaw = inner['user'];

    if (accessToken is! String ||
        refreshToken is! String ||
        userRaw is! Map<String, dynamic>) {
      throw const ApiServerException(
        500,
        'Auth response missing accessToken/refreshToken/user',
      );
    }

    final userId = userRaw['id'];
    if (userId is! String) {
      throw const ApiServerException(500, 'Auth response missing user.id');
    }

    await _client.saveTokens(
      accessToken: accessToken,
      refreshToken: refreshToken,
      userId: userId,
    );

    return models.User.fromJson(userRaw);
  }
}
