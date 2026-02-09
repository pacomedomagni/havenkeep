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
    final userId = requireCurrentUserId();

    final data = await _client
        .from(kHomesTable)
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: true);

    return (data as List).map((json) => Home.fromJson(json)).toList();
  }

  /// Get a single home by ID.
  Future<Home> getHomeById(String id) async {
    final data = await _client
        .from(kHomesTable)
        .select()
        .eq('id', id)
        .single();

    return Home.fromJson(data);
  }

  /// Get the user's first (default) home.
  Future<Home?> getDefaultHome() async {
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
  }

  // ============================================
  // CREATE
  // ============================================

  /// Create a new home.
  Future<Home> createHome(Home home) async {
    final json = home.toJson();
    json.remove('id'); // Let DB generate UUID

    final data = await _client
        .from(kHomesTable)
        .insert(json)
        .select()
        .single();

    return Home.fromJson(data);
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Update an existing home.
  Future<Home> updateHome(Home home) async {
    final json = home.toJson();
    json.remove('created_at');

    final data = await _client
        .from(kHomesTable)
        .update(json)
        .eq('id', home.id)
        .select()
        .single();

    return Home.fromJson(data);
  }

  // ============================================
  // DELETE
  // ============================================

  /// Delete a home and all its items (cascade).
  Future<void> deleteHome(String id) async {
    await _client
        .from(kHomesTable)
        .delete()
        .eq('id', id);
  }
}
