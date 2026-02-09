import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_models/shared_models.dart';
import 'package:supabase_client/supabase_client.dart';

/// Handles notification fetching and management.
class NotificationsRepository {
  final SupabaseClient _client;

  NotificationsRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get all notifications for the current user.
  Future<List<AppNotification>> getNotifications({
    bool unreadOnly = false,
  }) async {
    final userId = requireCurrentUserId();

    var query = _client
        .from(kNotificationsTable)
        .select()
        .eq('user_id', userId);

    if (unreadOnly) {
      query = query.eq('is_read', false);
    }

    final data = await query.order('scheduled_at', ascending: false);
    return (data as List)
        .map((json) => AppNotification.fromJson(json))
        .toList();
  }

  /// Get the count of unread notifications.
  Future<int> getUnreadCount() async {
    final userId = requireCurrentUserId();

    final data = await _client
        .from(kNotificationsTable)
        .select('id')
        .eq('user_id', userId)
        .eq('is_read', false);

    return (data as List).length;
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _client
        .from(kNotificationsTable)
        .update({'is_read': true})
        .eq('id', notificationId);
  }

  /// Mark all notifications as read for the current user.
  Future<void> markAllAsRead() async {
    final userId = requireCurrentUserId();

    await _client
        .from(kNotificationsTable)
        .update({'is_read': true})
        .eq('user_id', userId)
        .eq('is_read', false);
  }

  // ============================================
  // NOTIFICATION PREFERENCES
  // ============================================

  /// Get the current user's notification preferences.
  Future<NotificationPreferences?> getPreferences() async {
    final userId = requireCurrentUserId();

    final data = await _client
        .from(kNotificationPreferencesTable)
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (data == null) return null;
    return NotificationPreferences.fromJson(data);
  }

  /// Create or update notification preferences.
  Future<NotificationPreferences> upsertPreferences(
    NotificationPreferences prefs,
  ) async {
    final data = await _client
        .from(kNotificationPreferencesTable)
        .upsert(prefs.toJson())
        .select()
        .single();

    return NotificationPreferences.fromJson(data);
  }

  // ============================================
  // REALTIME
  // ============================================

  /// Watch unread notification count in realtime.
  Stream<List<Map<String, dynamic>>> watchNotifications() {
    final userId = requireCurrentUserId();

    return _client
        .from(kNotificationsTable)
        .stream(primaryKey: ['id'])
        .eq('user_id', userId);
  }
}
