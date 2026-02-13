import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles warranty purchase operations via the Express API.
class WarrantyPurchasesRepository {
  final ApiClient _client;

  WarrantyPurchasesRepository(this._client);

  Future<List<WarrantyPurchase>> getPurchases({String? itemId, String? status}) async {
    try {
      final params = <String, String>{
        'limit': '100',
        'offset': '0',
      };
      if (itemId != null) params['item_id'] = itemId;
      if (status != null) params['status'] = status;

      final data = await _client.get('/api/v1/warranty-purchases', queryParams: params);
      final purchases = (data['data'] as List)
          .map((json) => WarrantyPurchase.fromJson(json as Map<String, dynamic>))
          .toList();
      return purchases;
    } catch (e) {
      debugPrint('[WarrantyPurchasesRepository] getPurchases failed: $e');
      rethrow;
    }
  }

  Future<WarrantyPurchase> getPurchaseById(String id) async {
    try {
      final data = await _client.get('/api/v1/warranty-purchases/$id');
      return WarrantyPurchase.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyPurchasesRepository] getPurchaseById failed: $e');
      rethrow;
    }
  }

  Future<WarrantyPurchase> createPurchase(WarrantyPurchase purchase) async {
    try {
      final data = await _client.post(
        '/api/v1/warranty-purchases',
        body: purchase.toCreateJson(),
      );
      return WarrantyPurchase.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyPurchasesRepository] createPurchase failed: $e');
      rethrow;
    }
  }

  Future<WarrantyPurchase> cancelPurchase(String id, {String? reason}) async {
    try {
      final data = await _client.post(
        '/api/v1/warranty-purchases/$id/cancel',
        body: {'reason': reason},
      );
      return WarrantyPurchase.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[WarrantyPurchasesRepository] cancelPurchase failed: $e');
      rethrow;
    }
  }
}
