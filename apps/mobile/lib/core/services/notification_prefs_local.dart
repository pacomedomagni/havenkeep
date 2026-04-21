import 'package:shared_preferences/shared_preferences.dart';

/// Local-only notification preferences that complement the server-side
/// [NotificationPreferences] model. These control on-device delivery:
/// digest rollups and quiet hours.
///
/// Stored in SharedPreferences so they survive app restarts without a
/// round-trip, and degrade gracefully if the server model evolves.
class NotificationPrefsLocal {
  NotificationPrefsLocal._();

  static const _keyDigestEnabled = 'notif_digest_enabled';
  static const _keyQuietHoursEnabled = 'notif_quiet_hours_enabled';
  static const _keyQuietStartMinutes = 'notif_quiet_start_min';
  static const _keyQuietEndMinutes = 'notif_quiet_end_min';
  static const _keyReminderCascade = 'notif_reminder_cascade_days';

  /// Multi-stage reminder schedule in days-before-expiry. Defaults
  /// mirror the marketing promise ("smart reminders 30, 14, 7 days").
  static const List<int> defaultReminderCascade = [30, 14, 7];
  static const List<int> availableReminderDays = [90, 60, 30, 14, 7, 3, 1];

  /// When true, individual reminders are grouped into a single
  /// daily digest at the user's reminder time.
  static Future<bool> isDigestEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyDigestEnabled) ?? false;
  }

  static Future<void> setDigestEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyDigestEnabled, value);
  }

  static Future<bool> isQuietHoursEnabled() async {
    final p = await SharedPreferences.getInstance();
    return p.getBool(_keyQuietHoursEnabled) ?? false;
  }

  static Future<void> setQuietHoursEnabled(bool value) async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_keyQuietHoursEnabled, value);
  }

  /// Start of quiet hours in minutes since midnight. Defaults to 22:00.
  static Future<int> getQuietStartMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyQuietStartMinutes) ?? (22 * 60);
  }

  static Future<void> setQuietStartMinutes(int minutes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyQuietStartMinutes, minutes);
  }

  /// End of quiet hours in minutes since midnight. Defaults to 08:00.
  static Future<int> getQuietEndMinutes() async {
    final p = await SharedPreferences.getInstance();
    return p.getInt(_keyQuietEndMinutes) ?? (8 * 60);
  }

  static Future<void> setQuietEndMinutes(int minutes) async {
    final p = await SharedPreferences.getInstance();
    await p.setInt(_keyQuietEndMinutes, minutes);
  }

  /// User's multi-stage reminder cascade. Returns the default if unset.
  /// Always sorted descending (90 → 1) so the schedule reads chronologically.
  static Future<List<int>> getReminderCascade() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getStringList(_keyReminderCascade);
    if (raw == null || raw.isEmpty) return defaultReminderCascade;
    final parsed = raw
        .map((s) => int.tryParse(s))
        .whereType<int>()
        .where((d) => availableReminderDays.contains(d))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    return parsed.isEmpty ? defaultReminderCascade : parsed;
  }

  static Future<void> setReminderCascade(List<int> days) async {
    final p = await SharedPreferences.getInstance();
    final clean = days
        .where((d) => availableReminderDays.contains(d))
        .toSet()
        .toList()
      ..sort((a, b) => b.compareTo(a));
    await p.setStringList(
      _keyReminderCascade,
      clean.map((d) => d.toString()).toList(),
    );
  }

  /// Returns true if [time] falls inside the user's quiet window
  /// (wrap-around midnight supported). If quiet hours are disabled,
  /// returns false unconditionally.
  static Future<bool> isQuietNow(DateTime time) async {
    final enabled = await isQuietHoursEnabled();
    if (!enabled) return false;
    final start = await getQuietStartMinutes();
    final end = await getQuietEndMinutes();
    final now = time.hour * 60 + time.minute;
    if (start == end) return false;
    if (start < end) return now >= start && now < end;
    // wraps past midnight (e.g. 22:00 → 08:00)
    return now >= start || now < end;
  }
}
