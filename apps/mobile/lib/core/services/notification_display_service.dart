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

  /// H-B11 (audit): monotonic counter for notification IDs.
  ///
  /// The prior shape used `DateTime.now().millisecondsSinceEpoch ~/ 1000`
  /// which had two problems:
  ///   1. `~/ 1000` truncates to seconds — two foreground pushes in the
  ///      same second collide. The plugin silently replaces the first
  ///      with the second.
  ///   2. flutter_local_notifications uses int32 on Android. The
  ///      epoch-seconds value is currently ~1.78 × 10⁹; it overflows
  ///      int32 max on 2038-01-19 (Y2K38) and the plugin rejects
  ///      negative IDs.
  ///
  /// A monotonic counter wraps cleanly at int32 max and never collides
  /// within the process. Cross-process collisions don't matter — these
  /// IDs are only meaningful for the local plugin's "replace this
  /// existing notification" semantics.
  int _nextNotificationId = 0;
  static const int _kInt32Max = 2147483647;

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

    final id = _nextNotificationId++;
    if (_nextNotificationId > _kInt32Max) {
      _nextNotificationId = 0;
    }
    await _plugin.show(id, title, body, details, payload: payload);
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
