import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../router/router.dart';
import 'notification_display_service.dart';

/// Handles Firebase Cloud Messaging for push notifications.
///
/// Responsibilities:
/// - Request notification permission from the user
/// - Obtain and register the FCM device token with the Express API
/// - Listen for foreground and background messages
/// - Handle notification tap navigation
class PushNotificationService {
  final Ref _ref;

  PushNotificationService(this._ref);

  /// Initialize the push notification system.
  ///
  /// Call this once after Firebase has been initialized and the user is
  /// authenticated.
  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Request permission (iOS will show a dialog; Android auto-grants)
      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        provisional: false,
      );

      debugPrint(
        '[Push] Permission status: ${settings.authorizationStatus}',
      );

      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        debugPrint('[Push] User denied notification permission.');
        return;
      }

      // Get the FCM token
      final token = await messaging.getToken();
      if (token != null) {
        debugPrint('[Push] FCM Token: ${token.substring(0, 20)}...');
      }

      // Listen for token refresh
      messaging.onTokenRefresh.listen((newToken) {
        debugPrint('[Push] Token refreshed.');
        _registerTokenWithBackend(newToken);
      });

      // Foreground messages — display a local notification
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // When the user taps a notification while app is in background
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if the app was opened from a terminated state via notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        _handleNotificationTap(initialMessage);
      }
    } catch (e) {
      // Firebase may not be configured yet (placeholder keys).
      // Fail silently so the app still works without push.
      debugPrint('[Push] Initialization failed (expected with stub config): $e');
    }
  }

  /// Register the user's FCM token with the backend.
  Future<void> registerToken(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      final token = await messaging.getToken();
      if (token == null) return;

      await _registerTokenWithBackend(token, userId: userId);
    } catch (e) {
      debugPrint('[Push] Token registration failed: $e');
    }
  }

  /// Save the FCM token via the Express API.
  Future<void> _registerTokenWithBackend(
    String token, {
    String? userId,
  }) async {
    try {
      final client = _ref.read(apiClientProvider);
      await client.post('/api/v1/users/push-token', body: {
        'fcmToken': token,
        'platform': defaultTargetPlatform.name,
      });
    } catch (e) {
      debugPrint('[Push] Failed to save token to backend: $e');
    }
  }

  /// Handle a message received while the app is in the foreground.
  void _handleForegroundMessage(RemoteMessage message) {
    debugPrint('[Push] Foreground message: ${message.notification?.title}');

    final notification = message.notification;
    if (notification == null) return;

    // Show a local notification so the user sees it
    _ref.read(notificationDisplayServiceProvider).showNotification(
          title: notification.title ?? 'HavenKeep',
          body: notification.body ?? '',
          payload: message.data['route'] ?? '',
        );
  }

  /// Handle a notification tap (background or terminated state).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[Push] Notification tapped: ${message.data}');

    final route = message.data['route'] as String?;
    if (route == null || route.isEmpty) return;

    // Navigate to the specified route
    try {
      final router = _ref.read(routerProvider);
      router.push(route);
    } catch (e) {
      debugPrint('[Push] Navigation failed: $e');
    }
  }
}

/// Riverpod provider for the push notification service.
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  return PushNotificationService(ref);
});
