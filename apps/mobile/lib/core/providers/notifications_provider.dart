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
  @override
  Future<List<AppNotification>> build() async {
    ref.watch(currentUserProvider);

    final user = ref.read(currentUserProvider).value;
    if (user == null) return [];

    return ref.read(notificationsRepositoryProvider).getNotifications();
  }

  /// Refresh notifications from the server.
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      return ref.read(notificationsRepositoryProvider).getNotifications();
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
