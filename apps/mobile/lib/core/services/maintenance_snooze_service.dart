import 'package:shared_preferences/shared_preferences.dart';

/// Local-only persistence for per-task maintenance reminder snoozes.
/// Server-side snooze is the long-term plan, but this keeps the UI honest
/// today: a "Snooze 1 week" tap silently dismisses the task from the due
/// list until the snooze window passes.
///
/// Keyed on `(itemId, scheduleId)` so the same schedule on a different item
/// has its own snooze state. Schedule id is required — tasks without a
/// `scheduleId` aren't recurring and so can't be snoozed.
class MaintenanceSnoozeService {
  MaintenanceSnoozeService._();

  static const _prefix = 'maintenance_snooze_';

  /// Snooze options surfaced in the UI. Order is the order of presentation.
  static const List<MaintenanceSnoozeOption> options = [
    MaintenanceSnoozeOption.oneDay,
    MaintenanceSnoozeOption.oneWeek,
    MaintenanceSnoozeOption.oneMonth,
    MaintenanceSnoozeOption.nextOccurrence,
  ];

  /// Storage key for a given item + schedule pair. Public so tests can
  /// assert against persisted state without re-implementing the format.
  static String storageKey(String itemId, String scheduleId) =>
      '$_prefix${itemId}_$scheduleId';

  /// Persist a snooze. [nextDue] is required for [MaintenanceSnoozeOption.nextOccurrence]
  /// so we can pin the snooze to the actual next-due date — without it the
  /// "next occurrence" option would behave like a permanent dismissal.
  static Future<void> snooze({
    required String itemId,
    required String scheduleId,
    required MaintenanceSnoozeOption option,
    required DateTime nextDue,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final base = now ?? DateTime.now();
    final until = switch (option) {
      MaintenanceSnoozeOption.oneDay => base.add(const Duration(days: 1)),
      MaintenanceSnoozeOption.oneWeek => base.add(const Duration(days: 7)),
      MaintenanceSnoozeOption.oneMonth => base.add(const Duration(days: 30)),
      // Park the task until the regularly-scheduled next occurrence is past.
      // We add an extra day so the user gets the new reminder on the day it
      // actually becomes due rather than a stale "due in 0 days" the night
      // before.
      MaintenanceSnoozeOption.nextOccurrence =>
        nextDue.add(const Duration(days: 1)),
    };
    await prefs.setString(storageKey(itemId, scheduleId), until.toIso8601String());
  }

  /// Returns the snooze deadline if one is set and still in the future.
  /// Returns null when no snooze is set or the snooze has elapsed (and
  /// silently clears expired entries so SharedPreferences doesn't grow
  /// unbounded as users churn through tasks).
  static Future<DateTime?> activeSnoozeUntil({
    required String itemId,
    required String scheduleId,
    DateTime? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey(itemId, scheduleId));
    if (raw == null) return null;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      await prefs.remove(storageKey(itemId, scheduleId));
      return null;
    }
    final base = now ?? DateTime.now();
    if (!parsed.isAfter(base)) {
      await prefs.remove(storageKey(itemId, scheduleId));
      return null;
    }
    return parsed;
  }

  /// Clear a snooze (e.g. user marked the task done early).
  static Future<void> clear({
    required String itemId,
    required String scheduleId,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(storageKey(itemId, scheduleId));
  }

  /// Bulk-load active snoozes so the maintenance list can filter without
  /// awaiting one prefs lookup per task on every rebuild.
  static Future<Map<String, DateTime>> loadActive({DateTime? now}) async {
    final prefs = await SharedPreferences.getInstance();
    final base = now ?? DateTime.now();
    final out = <String, DateTime>{};
    for (final key in prefs.getKeys()) {
      if (!key.startsWith(_prefix)) continue;
      final raw = prefs.getString(key);
      if (raw == null) continue;
      final parsed = DateTime.tryParse(raw);
      if (parsed == null || !parsed.isAfter(base)) {
        await prefs.remove(key);
        continue;
      }
      out[key] = parsed;
    }
    return out;
  }
}

/// User-facing snooze choices.
enum MaintenanceSnoozeOption {
  oneDay,
  oneWeek,
  oneMonth,
  nextOccurrence;

  String get displayLabel => switch (this) {
        MaintenanceSnoozeOption.oneDay => '1 day',
        MaintenanceSnoozeOption.oneWeek => '1 week',
        MaintenanceSnoozeOption.oneMonth => '1 month',
        MaintenanceSnoozeOption.nextOccurrence => 'Next occurrence',
      };
}
