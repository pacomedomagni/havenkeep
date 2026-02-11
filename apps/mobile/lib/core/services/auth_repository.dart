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

    final data = await _client.post('/api/v1/auth/register', body: body);

    await _client.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: data['user']['id'] as String,
    );

    final userJson = data['user'] as Map<String, dynamic>;
    return models.User.fromJson(_normalizeUserJson(userJson));
  }

  /// Sign in with email and password.
  Future<models.User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final data = await _client.post('/api/v1/auth/login', body: {
      'email': email,
      'password': password,
    });

    await _client.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: data['user']['id'] as String,
    );

    final userJson = data['user'] as Map<String, dynamic>;
    return models.User.fromJson(_normalizeUserJson(userJson));
  }

  /// Sign in with Google. Accepts the Google ID token from the platform SDK.
  Future<models.User?> signInWithGoogle({required String idToken}) async {
    final data = await _client.post('/api/v1/auth/google', body: {
      'idToken': idToken,
    });

    await _client.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: data['user']['id'] as String,
    );

    final userJson = data['user'] as Map<String, dynamic>;
    return models.User.fromJson(_normalizeUserJson(userJson));
  }

  /// Sign in with Apple. Accepts the Apple ID token from the platform SDK.
  Future<models.User?> signInWithApple({
    required String idToken,
    String? fullName,
  }) async {
    final body = <String, dynamic>{'idToken': idToken};
    if (fullName != null) body['fullName'] = fullName;

    final data = await _client.post('/api/v1/auth/apple', body: body);

    await _client.saveTokens(
      accessToken: data['accessToken'] as String,
      refreshToken: data['refreshToken'] as String,
      userId: data['user']['id'] as String,
    );

    final userJson = data['user'] as Map<String, dynamic>;
    return models.User.fromJson(_normalizeUserJson(userJson));
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    try {
      await _client.post('/api/v1/auth/logout', body: {});
    } catch (e) {
      debugPrint('[Auth] Logout API call failed: $e');
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
      final data = await _client.get('/api/v1/users/me');
      final userJson = data['user'] as Map<String, dynamic>;
      return models.User.fromJson(userJson);
    } on ApiException catch (e) {
      if (e.isUnauthorized) return null;
      rethrow;
    }
  }

  /// Update the current user's profile.
  Future<models.User> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final updates = <String, dynamic>{};
    if (fullName != null) updates['fullName'] = fullName;
    if (avatarUrl != null) updates['avatarUrl'] = avatarUrl;

    final data = await _client.put('/api/v1/users/me', body: updates);
    final userJson = data['user'] as Map<String, dynamic>;
    return models.User.fromJson(userJson);
  }

  /// Normalize API user response to match the User model's fromJson expectations.
  Map<String, dynamic> _normalizeUserJson(Map<String, dynamic> json) {
    return {
      ...json,
      if (json.containsKey('fullName') && !json.containsKey('full_name'))
        'full_name': json['fullName'],
      if (json.containsKey('isAdmin') && !json.containsKey('is_admin'))
        'is_admin': json['isAdmin'],
    };
  }
}
