import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Handles CRUD operations for homes/properties.
class HomesRepository {
  final SupabaseClient _client;

  HomesRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all homes for the current user.
  Future<List<Home>> getHomes() async {
    try {
      final userId = requireCurrentUserId();

      final data = await _client
          .from(kHomesTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true);

      return (data as List).map((json) => Home.fromJson(json)).toList();
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] getHomes failed: ${e.message}');
      rethrow;
    }
  }

  /// Get a single home by ID.
  Future<Home> getHomeById(String id) async {
    try {
      final data = await _client
          .from(kHomesTable)
          .select()
          .eq('id', id)
          .single();

      return Home.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] getHomeById failed: ${e.message}');
      rethrow;
    }
  }

  /// Get the user's first (default) home.
  Future<Home?> getDefaultHome() async {
    try {
      final userId = requireCurrentUserId();

      final data = await _client
          .from(kHomesTable)
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: true)
          .limit(1)
          .maybeSingle();

      if (data == null) return null;
      return Home.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] getDefaultHome failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // CREATE
  // ============================================

  /// Create a new home.
  Future<Home> createHome(Home home) async {
    try {
      final json = home.toJson();
      json.remove('id'); // Let DB generate UUID

      final data = await _client
          .from(kHomesTable)
          .insert(json)
          .select()
          .single();

      return Home.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] createHome failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Update an existing home.
  Future<Home> updateHome(Home home) async {
    try {
      final json = home.toJson();
      json.remove('created_at');

      final data = await _client
          .from(kHomesTable)
          .update(json)
          .eq('id', home.id)
          .select()
          .single();

      return Home.fromJson(data);
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] updateHome failed: ${e.message}');
      rethrow;
    }
  }

  // ============================================
  // DELETE
  // ============================================

  /// Delete a home and all its items (cascade).
  Future<void> deleteHome(String id) async {
    try {
      await _client
          .from(kHomesTable)
          .delete()
          .eq('id', id);
    } on PostgrestException catch (e) {
      debugPrint('[HomesRepository] deleteHome failed: ${e.message}');
      rethrow;
    }
  }
}
