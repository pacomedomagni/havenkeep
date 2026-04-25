import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:api_client/api_client.dart';

import '../router/router.dart';
import 'notification_display_service.dart';

/// Allowed route prefixes for deep link navigation from push notifications.
/// Routes not matching any of these prefixes will be rejected.
const _kAllowedRoutePrefixes = [
  '/items',
  '/homes',
  '/warranties',
  '/notifications',
  '/settings',
  '/profile',
];

/// Handles Firebase Cloud Messaging for push notifications.
///
/// Responsibilities:
/// - Request notification permission from the user
/// - Obtain and register the FCM device token with the Express API
/// - Listen for foreground and background messages
/// - Handle notification tap navigation
class PushNotificationService {
  final Ref _ref;
  final List<StreamSubscription> _subscriptions = [];

  PushNotificationService(this._ref);

  /// Initialize the push notification system *streams* (foreground,
  /// background tap, terminated-launch) and check for any pending
  /// notification tap, but **do not** trigger the system prompt yet —
  /// that's deferred until the user has added their first item
  /// (Ch05-F077). Call this once after Firebase has been initialized
  /// and the user is authenticated.
  Future<void> initialize() async {
    try {
      final messaging = FirebaseMessaging.instance;

      // Listen for token refresh — this is cheap and doesn't trigger
      // the permission prompt; the token only materialises once the
      // user has actually granted permission.
      _subscriptions.add(
        messaging.onTokenRefresh.listen(
          (newToken) {
            if (kDebugMode) {
              debugPrint('[Push] Token refreshed.');
            }
            _registerTokenWithBackend(newToken);
          },
          onError: (Object error) {
            debugPrint('[Push] onTokenRefresh stream error: $error');
          },
        ),
      );

      // Foreground messages — display a local notification
      _subscriptions.add(
        FirebaseMessaging.onMessage.listen(
          _handleForegroundMessage,
          onError: (Object error) {
            debugPrint('[Push] onMessage stream error: $error');
          },
        ),
      );

      // When the user taps a notification while app is in background
      _subscriptions.add(
        FirebaseMessaging.onMessageOpenedApp.listen(
          _handleNotificationTap,
          onError: (Object error) {
            debugPrint('[Push] onMessageOpenedApp stream error: $error');
          },
        ),
      );

      // Check if the app was opened from a terminated state via notification
      final initialMessage = await messaging.getInitialMessage();
      if (initialMessage != null) {
        try {
          _handleNotificationTap(initialMessage);
        } catch (e) {
          debugPrint('[Push] Failed to handle initial message tap: $e');
        }
      }
    } catch (e) {
      // Firebase may not be configured yet (placeholder keys).
      // Fail silently so the app still works without push.
      debugPrint('[Push] Initialization failed (expected with stub config): $e');
    }
  }

  /// Trigger the OS notification permission prompt and pull the FCM
  /// token. Idempotent — once the user has answered the system prompt
  /// we won't ask again, and this method is safe to call repeatedly
  /// (e.g. after every "Add item" success).
  ///
  /// Ch05-F077: surfacing the prompt at this point — right after a
  /// concrete moment of value (the first saved warranty) — converts
  /// far better than the historical "ask on splash" flow that
  /// front-loaded a permission with no context.
  Future<void> requestPermissionAndRegisterToken() async {
    try {
      final messaging = FirebaseMessaging.instance;
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

      final token = await messaging.getToken();
      if (token != null && kDebugMode) {
        debugPrint('[Push] FCM Token: ${token.substring(0, 20)}...');
      }
    } catch (e) {
      debugPrint('[Push] requestPermissionAndRegisterToken failed: $e');
    }
  }

  /// Cancel all stream subscriptions.
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
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
      await client.post(
        pathSegments: const ['api', 'v1', 'users', 'push-token'],
        body: {
          'fcm_token': token,
          'platform': defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        },
      );
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

  /// Check whether a route matches the allowed deep link whitelist.
  bool _isAllowedRoute(String route) {
    return _kAllowedRoutePrefixes.any((prefix) => route.startsWith(prefix));
  }

  /// Handle a notification tap (background or terminated state).
  void _handleNotificationTap(RemoteMessage message) {
    debugPrint('[Push] Notification tapped: ${message.data}');

    final route = message.data['route'] as String?;
    if (route == null || route.isEmpty) return;

    // Validate route against whitelist before navigating
    if (!_isAllowedRoute(route)) {
      debugPrint('[Push] Blocked navigation to disallowed route: $route');
      return;
    }

    // Navigate to the specified route.
    // Wrapped in try-catch to prevent crashes if the service or router
    // has been disposed (e.g., app lifecycle edge cases).
    try {
      final router = _ref.read(routerProvider);
      router.push(route);
    } catch (e) {
      debugPrint('[Push] Navigation failed (router may be disposed): $e');
    }
  }
}

/// Riverpod provider for the push notification service.
final pushNotificationServiceProvider = Provider<PushNotificationService>((ref) {
  final service = PushNotificationService(ref);
  ref.onDispose(() => service.dispose());
  return service;
});
