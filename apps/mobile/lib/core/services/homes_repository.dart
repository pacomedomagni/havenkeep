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
      final data = await _client.get('/api/v1/homes');
      final homes = data['homes'] as List;
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
      final data = await _client.get('/api/v1/homes/$id');
      return Home.fromJson(data['home'] as Map<String, dynamic>);
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

  /// Create a new home.
  Future<Home> createHome(Home home) async {
    try {
      final json = home.toJson();
      json.remove('id');

      final data = await _client.post('/api/v1/homes', body: json);
      return Home.fromJson(data['home'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[HomesRepository] createHome failed: $e');
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
      json.remove('id');

      final data = await _client.put('/api/v1/homes/${home.id}', body: json);
      return Home.fromJson(data['home'] as Map<String, dynamic>);
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
      await _client.delete('/api/v1/homes/$id');
    } catch (e) {
      debugPrint('[HomesRepository] deleteHome failed: $e');
      rethrow;
    }
  }
}
