import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Displays local notifications when the app is in the foreground.
///
/// Uses `flutter_local_notifications` to show system notifications on
/// both Android and iOS while the app is open.
class NotificationDisplayService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Callback invoked when the user taps a displayed notification.
  void Function(String? payload)? onNotificationTap;

  /// Initialize the local notification plugin with platform-specific settings.
  Future<void> initialize({
    void Function(String? payload)? onTap,
  }) async {
    onNotificationTap = onTap;

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );

    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false, // Already requested via FCM
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _plugin.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        final payload = response.payload;
        debugPrint('[LocalNotif] Tapped notification with payload: $payload');
        onNotificationTap?.call(payload);
      },
    );

    // Create the Android notification channel
    await _createAndroidChannel();
  }

  /// Show a local notification.
  Future<void> showNotification({
    required String title,
    required String body,
    String? payload,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'havenkeep_default',
      'HavenKeep Notifications',
      channelDescription: 'Warranty reminders and updates from HavenKeep',
      importance: Importance.high,
      priority: Priority.high,
      showWhen: true,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    const details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _plugin.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000, // Unique ID
      title,
      body,
      details,
      payload: payload,
    );
  }

  /// Create the default Android notification channel.
  Future<void> _createAndroidChannel() async {
    final androidPlugin =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();

    if (androidPlugin != null) {
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          'havenkeep_default',
          'HavenKeep Notifications',
          description: 'Warranty reminders and updates from HavenKeep',
          importance: Importance.high,
        ),
      );
    }
  }
}

/// Riverpod provider for the notification display service.
final notificationDisplayServiceProvider =
    Provider<NotificationDisplayService>((ref) {
  return NotificationDisplayService();
});
