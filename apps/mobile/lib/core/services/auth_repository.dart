import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart' as models;
import 'package:supabase_client/supabase_client.dart';

/// Handles authentication and user profile operations.
class AuthRepository {
  final SupabaseClient _client;

  AuthRepository(this._client);

  // ============================================
  // AUTH STATE
  // ============================================

  /// Stream of auth state changes.
  Stream<AuthState> authStateChanges() {
    return _client.auth.onAuthStateChange;
  }

  /// The current Supabase auth session, if any.
  Session? get currentSession => _client.auth.currentSession;

  /// Whether the user is currently authenticated.
  bool get isAuthenticated => _client.auth.currentUser != null;

  // ============================================
  // SIGN UP / SIGN IN
  // ============================================

  /// Sign up with email and password. Creates auth user + public profile.
  Future<models.User?> signUpWithEmail({
    required String email,
    required String password,
    required String fullName,
    String? referralCode,
  }) async {
    final response = await _client.auth.signUp(
      email: email,
      password: password,
      data: {'full_name': fullName},
    );

    if (response.user == null) return null;

    // Create public profile
    final profile = {
      'id': response.user!.id,
      'email': email,
      'full_name': fullName,
      'auth_provider': 'email',
    };

    // If referred, look up partner and link
    if (referralCode != null) {
      final partner = await _client
          .from(kReferralPartnersTable)
          .select('id')
          .eq('referral_code', referralCode)
          .eq('is_active', true)
          .maybeSingle();

      if (partner != null) {
        profile['referred_by'] = partner['id'];
      }
    }

    final data = await _client
        .from(kUsersTable)
        .insert(profile)
        .select()
        .single();

    return models.User.fromJson(data);
  }

  /// Sign in with email and password.
  Future<models.User?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: password,
    );

    return getCurrentUser();
  }

  /// Sign in with Google OAuth.
  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: 'io.havenkeep.app://login-callback',
    );
  }

  /// Sign in with Apple OAuth.
  Future<void> signInWithApple() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.apple,
      redirectTo: 'io.havenkeep.app://login-callback',
    );
  }

  /// Sign out the current user.
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  // ============================================
  // USER PROFILE
  // ============================================

  /// Get the current user's profile from public.users.
  Future<models.User?> getCurrentUser() async {
    final userId = getCurrentUserId();
    if (userId == null) return null;

    final data = await _client
        .from(kUsersTable)
        .select()
        .eq('id', userId)
        .maybeSingle();

    if (data == null) return null;
    return models.User.fromJson(data);
  }

  /// Update the current user's profile.
  Future<models.User> updateProfile({
    String? fullName,
    String? avatarUrl,
  }) async {
    final userId = requireCurrentUserId();

    final updates = <String, dynamic>{};
    if (fullName != null) updates['full_name'] = fullName;
    if (avatarUrl != null) updates['avatar_url'] = avatarUrl;

    final data = await _client
        .from(kUsersTable)
        .update(updates)
        .eq('id', userId)
        .select()
        .single();

    return models.User.fromJson(data);
  }

  /// Create a user profile after OAuth sign-in (if it doesn't exist yet).
  Future<models.User> ensureProfile({
    required String authProvider,
  }) async {
    final authUser = _client.auth.currentUser!;

    // Check if profile already exists
    final existing = await _client
        .from(kUsersTable)
        .select()
        .eq('id', authUser.id)
        .maybeSingle();

    if (existing != null) return models.User.fromJson(existing);

    // Create new profile from auth metadata
    final metadata = authUser.userMetadata ?? {};
    final data = await _client.from(kUsersTable).insert({
      'id': authUser.id,
      'email': authUser.email!,
      'full_name': metadata['full_name'] as String? ??
          metadata['name'] as String? ??
          'User',
      'avatar_url': metadata['avatar_url'] as String? ??
          metadata['picture'] as String?,
      'auth_provider': authProvider,
    }).select().single();

    return models.User.fromJson(data);
  }
}
