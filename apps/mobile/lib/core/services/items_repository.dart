import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Handles CRUD operations for items and warranty data.
class ItemsRepository {
  final SupabaseClient _client;

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
    final userId = requireCurrentUserId();

    var query = _client
        .from(kItemsTable)
        .select()
        .eq('user_id', userId);

    if (homeId != null) {
      query = query.eq('home_id', homeId);
    }
    if (category != null) {
      query = query.eq('category', category.toJson());
    }
    if (room != null) {
      query = query.eq('room', room.toJson());
    }
    if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    final data = await query.order('created_at', ascending: false);
    return (data as List).map((json) => Item.fromJson(json)).toList();
  }

  /// Get a single item by ID.
  Future<Item> getItemById(String id) async {
    final data = await _client
        .from(kItemsTable)
        .select()
        .eq('id', id)
        .single();

    return Item.fromJson(data);
  }

  /// Get items with computed warranty status (uses the view).
  Future<List<Item>> getItemsWithStatus({String? homeId}) async {
    final userId = requireCurrentUserId();

    var query = _client
        .from(kItemsWithStatusView)
        .select()
        .eq('user_id', userId);

    if (homeId != null) {
      query = query.eq('home_id', homeId);
    }

    final data = await query.order('warranty_end_date', ascending: true);
    return (data as List).map((json) => Item.fromJson(json)).toList();
  }

  /// Get warranty stats for the dashboard.
  Future<Map<String, dynamic>?> getDashboardSummary() async {
    final userId = requireCurrentUserId();

    final data = await _client
        .from(kDashboardSummaryView)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    return data;
  }

  /// Get items that need attention (expiring + expired).
  Future<List<Item>> getNeedsAttention({int limit = kNeedsAttentionLimit}) async {
    final userId = requireCurrentUserId();

    final data = await _client
        .from(kNeedsAttentionView)
        .select()
        .eq('user_id', userId)
        .limit(limit);

    return (data as List).map((json) => Item.fromJson(json)).toList();
  }

  /// Get warranty stats counts.
  Future<Map<String, int>> getWarrantyStats() async {
    final summary = await getDashboardSummary();

    if (summary == null) {
      return {'active': 0, 'expiring': 0, 'expired': 0};
    }

    return {
      'active': summary['active_count'] as int? ?? 0,
      'expiring': summary['expiring_count'] as int? ?? 0,
      'expired': summary['expired_count'] as int? ?? 0,
    };
  }

  /// Count non-archived items (for free plan limit check).
  Future<int> countActiveItems() async {
    final userId = requireCurrentUserId();

    final data = await _client
        .rpc(kCountActiveItemsFn, params: {'p_user_id': userId});

    return data as int? ?? 0;
  }

  // ============================================
  // CREATE
  // ============================================

  /// Create a new item.
  Future<Item> createItem(Item item) async {
    final data = await _client
        .from(kItemsTable)
        .insert(item.toInsertJson())
        .select()
        .single();

    return Item.fromJson(data);
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Update an existing item.
  Future<Item> updateItem(Item item) async {
    final json = item.toJson();
    // Remove fields that shouldn't be updated
    json.remove('warranty_end_date');
    json.remove('created_at');

    final data = await _client
        .from(kItemsTable)
        .update(json)
        .eq('id', item.id)
        .select()
        .single();

    return Item.fromJson(data);
  }

  /// Archive an item (soft delete — doesn't count toward free limit).
  Future<void> archiveItem(String id) async {
    await _client
        .from(kItemsTable)
        .update({'is_archived': true})
        .eq('id', id);
  }

  /// Unarchive an item.
  Future<void> unarchiveItem(String id) async {
    await _client
        .from(kItemsTable)
        .update({'is_archived': false})
        .eq('id', id);
  }

  // ============================================
  // DELETE
  // ============================================

  /// Permanently delete an item.
  Future<void> deleteItem(String id) async {
    await _client
        .from(kItemsTable)
        .delete()
        .eq('id', id);
  }

  // ============================================
  // REALTIME
  // ============================================

  /// Watch items changes in realtime.
  Stream<List<Map<String, dynamic>>> watchItems() {
    final userId = requireCurrentUserId();

    return _client
        .from(kItemsTable)
        .stream(primaryKey: ['id'])
        .eq('user_id', userId);
  }
}
