import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles CRUD operations for homes/properties via the Express API.
class HomesRepository {
  final ApiClient _client;

  HomesRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all homes for the current user.
  Future<List<Home>> getHomes() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'homes'],
      );
      final homes = data['data'] as List;
      return homes
          .map((json) => Home.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[HomesRepository] getHomes failed: $e');
      rethrow;
    }
  }

  /// Get a single home by ID.
  Future<Home> getHomeById(String id) async {
    try {
      final data = await _client.get(
        pathSegments: ['api', 'v1', 'homes', id],
      );
      return Home.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[HomesRepository] getHomeById failed: $e');
      rethrow;
    }
  }

  /// Get the user's first (default) home.
  Future<Home?> getDefaultHome() async {
    try {
      final homes = await getHomes();
      return homes.isNotEmpty ? homes.first : null;
    } catch (e) {
      debugPrint('[HomesRepository] getDefaultHome failed: $e');
      rethrow;
    }
  }

  // ============================================
  // CREATE
  // ============================================

  /// Create a new home. Uses [Home.toCreateJson] which already strips id +
  /// server-managed timestamps so the server can't be tricked into honoring
  /// a client-supplied `created_at` (Ch08-Home-D007).
  Future<Home> createHome(Home home) async {
    try {
      final data = await _client.post(
        pathSegments: const ['api', 'v1', 'homes'],
        body: home.toCreateJson(),
      );
      return Home.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[HomesRepository] createHome failed: $e');
      rethrow;
    }
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Update an existing home. Same shape as create — server-managed fields
  /// stripped (Ch08-Home-D007).
  Future<Home> updateHome(Home home) async {
    try {
      final data = await _client.put(
        pathSegments: ['api', 'v1', 'homes', home.id],
        body: home.toCreateJson(),
      );
      return Home.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[HomesRepository] updateHome failed: $e');
      rethrow;
    }
  }

  // ============================================
  // DELETE
  // ============================================

  /// Delete a home and all its items (cascade).
  Future<void> deleteHome(String id) async {
    try {
      await _client.delete(
        pathSegments: ['api', 'v1', 'homes', id],
      );
    } catch (e) {
      debugPrint('[HomesRepository] deleteHome failed: $e');
      rethrow;
    }
  }
}
