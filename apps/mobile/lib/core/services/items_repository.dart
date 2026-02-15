import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles CRUD operations for items and warranty data via the Express API.
class ItemsRepository {
  final ApiClient _client;

  ItemsRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all items for the current user.
  Future<List<Item>> getItems({
    String? homeId,
    ItemCategory? category,
    ItemRoom? room,
    bool includeArchived = false,
  }) async {
    try {
      final params = <String, String>{
        'page': '1',
        'limit': '1000',
      };

      if (homeId != null) params['home_id'] = homeId;
      if (!includeArchived) params['archived'] = 'false';

      final data = await _client.get('/api/v1/items', queryParams: params);
      final items = (data['items'] as List)
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();

      // Client-side filtering for category and room
      var filtered = items;
      if (category != null) {
        filtered = filtered.where((i) => i.category == category).toList();
      }
      if (room != null) {
        filtered = filtered.where((i) => i.room == room).toList();
      }

      return filtered;
    } catch (e) {
      debugPrint('[ItemsRepository] getItems failed: $e');
      rethrow;
    }
  }

  /// Get a single item by ID.
  Future<Item> getItemById(String id) async {
    try {
      final data = await _client.get('/api/v1/items/$id');
      return Item.fromJson(data['item'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ItemsRepository] getItemById failed: $e');
      rethrow;
    }
  }

  /// Get items with computed warranty status.
  /// The Express API returns raw items; status is computed client-side.
  Future<List<Item>> getItemsWithStatus({String? homeId}) async {
    try {
      final params = <String, String>{
        'page': '1',
        'limit': '1000',
        'archived': 'false',
      };
      if (homeId != null) params['home_id'] = homeId;

      final data = await _client.get('/api/v1/items', queryParams: params);
      return (data['items'] as List)
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ItemsRepository] getItemsWithStatus failed: $e');
      rethrow;
    }
  }

  /// Get warranty stats for the dashboard.
  Future<Map<String, dynamic>?> getDashboardSummary() async {
    try {
      final data = await _client.get('/api/v1/stats/dashboard');
      return data['data'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('[ItemsRepository] getDashboardSummary failed: $e');
      rethrow;
    }
  }

  /// Get items that need attention (expiring + expired).
  Future<List<Item>> getNeedsAttention({int limit = kNeedsAttentionLimit}) async {
    try {
      final data = await _client.get('/api/v1/stats/items-needing-attention',
          queryParams: {'limit': limit.toString()});

      final items = data['data'] as List? ?? [];
      return items
          .map((json) => Item.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[ItemsRepository] getNeedsAttention failed: $e');
      rethrow;
    }
  }

  /// Get warranty stats counts.
  ///
  /// Lets errors propagate to the caller instead of masking them with
  /// fallback zeros — callers should handle errors explicitly.
  Future<Map<String, int>> getWarrantyStats() async {
    final summary = await getDashboardSummary();

    if (summary == null) {
      throw StateError('Dashboard summary returned null — server may be unavailable');
    }

    return {
      'active': summary['active_warranties'] as int? ?? 0,
      'expiring': summary['expiring_soon'] as int? ?? 0,
      'expired': summary['expired'] as int? ?? 0,
    };
  }

  /// Count non-archived items (for free plan limit check).
  Future<int> countActiveItems() async {
    try {
      final data = await _client.get('/api/v1/items/count');
      return data['count'] as int? ?? 0;
    } catch (e) {
      debugPrint('[ItemsRepository] countActiveItems failed: $e');
      rethrow;
    }
  }

  // ============================================
  // CREATE
  // ============================================

  /// Create a new item.
  Future<Item> createItem(Item item) async {
    try {
      final data = await _client.post('/api/v1/items', body: item.toInsertJson());
      return Item.fromJson(data['item'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ItemsRepository] createItem failed: $e');
      rethrow;
    }
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Update an existing item.
  Future<Item> updateItem(Item item) async {
    try {
      final json = item.toJson();
      // Remove fields that shouldn't be sent in updates
      json.remove('warranty_end_date');
      json.remove('created_at');
      json.remove('updated_at');
      json.remove('id');
      json.remove('user_id');

      final data = await _client.put('/api/v1/items/${item.id}', body: json);
      return Item.fromJson(data['item'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[ItemsRepository] updateItem failed: $e');
      rethrow;
    }
  }

  /// Archive an item (soft delete — doesn't count toward free limit).
  Future<void> archiveItem(String id) async {
    try {
      await _client.put('/api/v1/items/$id', body: {'isArchived': true});
    } catch (e) {
      debugPrint('[ItemsRepository] archiveItem failed: $e');
      rethrow;
    }
  }

  /// Unarchive an item.
  Future<void> unarchiveItem(String id) async {
    try {
      await _client.put('/api/v1/items/$id', body: {'isArchived': false});
    } catch (e) {
      debugPrint('[ItemsRepository] unarchiveItem failed: $e');
      rethrow;
    }
  }

  // ============================================
  // DELETE
  // ============================================

  /// Permanently delete an item.
  Future<void> deleteItem(String id) async {
    try {
      await _client.delete('/api/v1/items/$id');
    } catch (e) {
      debugPrint('[ItemsRepository] deleteItem failed: $e');
      rethrow;
    }
  }
}
