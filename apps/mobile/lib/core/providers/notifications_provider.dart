import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:api_client/api_client.dart';
import '../services/notifications_repository.dart';
import 'auth_provider.dart';

/// Provides the notifications repository instance.
final notificationsRepositoryProvider = Provider<NotificationsRepository>((ref) {
  return NotificationsRepository(ref.read(apiClientProvider));
});

/// All notifications for the current user.
final notificationsProvider =
    AsyncNotifierProvider<NotificationsNotifier, List<AppNotification>>(
  () => NotificationsNotifier(),
);

class NotificationsNotifier extends AsyncNotifier<List<AppNotification>> {
  static const _pageSize = 30;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  /// Whether more pages are available.
  bool get hasMore => _hasMore;

  /// Whether a load-more request is in-flight.
  bool get isLoadingMore => _isLoadingMore;

  @override
  Future<List<AppNotification>> build() async {
    ref.watch(currentUserProvider);

    final user = ref.read(currentUserProvider).value;
    if (user == null) return [];

    _hasMore = true;
    final page = await ref
        .read(notificationsRepositoryProvider)
        .getNotifications(limit: _pageSize, offset: 0);
    _hasMore = page.length >= _pageSize;
    return page;
  }

  /// Load the next page of notifications.
  Future<void> loadMore() async {
    if (!_hasMore || _isLoadingMore) return;
    _isLoadingMore = true;

    try {
      final current = state.value ?? [];
      final page = await ref
          .read(notificationsRepositoryProvider)
          .getNotifications(limit: _pageSize, offset: current.length);
      _hasMore = page.length >= _pageSize;
      state = AsyncValue.data([...current, ...page]);
    } finally {
      _isLoadingMore = false;
    }
  }

  /// Refresh notifications from the server.
  Future<void> refresh() async {
    _hasMore = true;
    _isLoadingMore = false;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final page = await ref
          .read(notificationsRepositoryProvider)
          .getNotifications(limit: _pageSize, offset: 0);
      _hasMore = page.length >= _pageSize;
      return page;
    });
  }

  /// Mark a notification as read.
  Future<void> markAsRead(String id) async {
    await ref.read(notificationsRepositoryProvider).markAsRead(id);

    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((n) => n.id == id ? n.copyWith(isRead: true) : n).toList(),
    );
  }

  /// Mark all notifications as read.
  Future<void> markAllAsRead() async {
    await ref.read(notificationsRepositoryProvider).markAllAsRead();

    final current = state.value ?? [];
    state = AsyncValue.data(
      current.map((n) => n.copyWith(isRead: true)).toList(),
    );
  }
}

/// Count of unread notifications.
final unreadNotificationCountProvider = Provider<int>((ref) {
  final notifications = ref.watch(notificationsProvider);
  return notifications.whenOrNull(
        data: (list) => list.where((n) => !n.isRead).length,
      ) ??
      0;
});

/// Notification preferences for the current user.
final notificationPreferencesProvider =
    FutureProvider<NotificationPreferences?>((ref) async {
  ref.watch(currentUserProvider);

  final user = ref.read(currentUserProvider).value;
  if (user == null) return null;

  return ref.read(notificationsRepositoryProvider).getPreferences();
});
