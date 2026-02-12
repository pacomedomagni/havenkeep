import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles notification fetching and management via the Express API.
class NotificationsRepository {
  final ApiClient _client;

  NotificationsRepository(this._client);

  // ============================================
  // READ
  // ============================================

  /// Get notifications for the current user with pagination.
  Future<List<AppNotification>> getNotifications({
    int limit = 30,
    int offset = 0,
    bool unreadOnly = false,
  }) async {
    final params = <String, String>{
      'limit': '$limit',
      'offset': '$offset',
    };

    if (unreadOnly) {
      params['unread'] = 'true';
    }

    final data = await _client.get('/api/v1/notifications', queryParams: params);
    final notifications = data['data'] as List;
    return notifications
        .map((json) => AppNotification.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Get the count of unread notifications.
  Future<int> getUnreadCount() async {
    final data = await _client.get('/api/v1/notifications/unread-count');
    return (data['data'] as Map<String, dynamic>)['count'] as int? ?? 0;
  }

  // ============================================
  // UPDATE
  // ============================================

  /// Mark a single notification as read.
  Future<void> markAsRead(String notificationId) async {
    await _client.put('/api/v1/notifications/$notificationId/read');
  }

  /// Mark all notifications as read for the current user.
  Future<void> markAllAsRead() async {
    await _client.put('/api/v1/notifications/read-all');
  }

  // ============================================
  // NOTIFICATION PREFERENCES
  // ============================================

  /// Get the current user's notification preferences.
  Future<NotificationPreferences?> getPreferences() async {
    final data = await _client.get('/api/v1/notifications/preferences');
    final prefsData = data['data'];
    if (prefsData == null) return null;
    return NotificationPreferences.fromJson(prefsData as Map<String, dynamic>);
  }

  /// Create or update notification preferences.
  Future<NotificationPreferences> upsertPreferences(
    NotificationPreferences prefs,
  ) async {
    final data = await _client.put(
      '/api/v1/notifications/preferences',
      body: prefs.toJson(),
    );
    return NotificationPreferences.fromJson(
        data['data'] as Map<String, dynamic>);
  }
}
