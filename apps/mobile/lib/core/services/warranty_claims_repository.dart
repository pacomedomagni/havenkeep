import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles warranty claims CRUD via the Express API.
class WarrantyClaimsRepository {
  final ApiClient _client;

  WarrantyClaimsRepository(this._client);

  /// Get all claims for the current user.
  Future<List<WarrantyClaim>> getClaims({String? itemId}) async {
    try {
      final params = <String, String>{
        'limit': '100',
        'offset': '0',
      };
      if (itemId != null) params['item_id'] = itemId;

      final data = await _client.get('/api/v1/warranty-claims', queryParams: params);
      final claims = (data['data'] as List)
          .map((json) => WarrantyClaim.fromJson(json as Map<String, dynamic>))
          .toList();

      return claims;
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getClaims failed: $e');
      rethrow;
    }
  }

  /// Get a single claim by ID.
  Future<WarrantyClaim> getClaimById(String id) async {
    try {
      final data = await _client.get('/api/v1/warranty-claims/$id');
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getClaimById failed: $e');
      rethrow;
    }
  }

  /// Create a new warranty claim.
  Future<WarrantyClaim> createClaim(WarrantyClaim claim) async {
    try {
      final data = await _client.post(
        '/api/v1/warranty-claims',
        body: claim.toCreateJson(),
      );
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] createClaim failed: $e');
      rethrow;
    }
  }

  /// Update an existing claim.
  Future<WarrantyClaim> updateClaim(String id, Map<String, dynamic> updates) async {
    try {
      final data = await _client.put('/api/v1/warranty-claims/$id', body: updates);
      return WarrantyClaim.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] updateClaim failed: $e');
      rethrow;
    }
  }

  /// Delete a claim.
  Future<void> deleteClaim(String id) async {
    try {
      await _client.delete('/api/v1/warranty-claims/$id');
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] deleteClaim failed: $e');
      rethrow;
    }
  }

  /// Get total savings from warranty claims.
  Future<Map<String, dynamic>> getSavings() async {
    try {
      final data = await _client.get('/api/v1/warranty-claims/savings');
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[WarrantyClaimsRepository] getSavings failed: $e');
      rethrow;
    }
  }
}
