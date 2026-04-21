import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/items_provider.dart';

/// Threshold: warranties expired more than this many days ago
/// are silently archived to keep the active list clean.
const int _archiveAfterExpiredDays = 90;

/// Run the auto-archive job at most once every [_minIntervalHours].
const int _minIntervalHours = 24;

const String _prefsKeyLastRun = 'auto_archive_last_run_ms';
const String _prefsKeyEnabled = 'auto_archive_enabled';

/// Archives items whose warranty expired > 90 days ago so power users
/// aren't drowning in stale entries. Idempotent; runs at most once per day.
///
/// Users can disable it (settings toggle writes `auto_archive_enabled=false`).
/// Archived items remain restorable from Settings → Archive.
class AutoArchiveService {
  final Ref ref;

  AutoArchiveService(this.ref);

  /// Runs the sweep if enough time has passed since the last run.
  /// Returns the number of items archived, or `null` if the job was skipped.
  Future<int?> runIfDue() async {
    final prefs = await SharedPreferences.getInstance();

    final enabled = prefs.getBool(_prefsKeyEnabled) ?? true;
    if (!enabled) return null;

    final lastRunMs = prefs.getInt(_prefsKeyLastRun) ?? 0;
    final now = DateTime.now();
    final hoursSince =
        now.difference(DateTime.fromMillisecondsSinceEpoch(lastRunMs)).inHours;
    if (hoursSince < _minIntervalHours) return null;

    try {
      final archivedCount = await _sweep();
      await prefs.setInt(_prefsKeyLastRun, now.millisecondsSinceEpoch);
      return archivedCount;
    } catch (e) {
      debugPrint('[AutoArchive] sweep failed: $e');
      return null;
    }
  }

  Future<int> _sweep() async {
    final items = await ref.read(itemsRepositoryProvider).getItems(
          includeArchived: false,
        );
    final cutoff =
        DateTime.now().subtract(const Duration(days: _archiveAfterExpiredDays));

    final toArchive = items
        .where((item) => _isExpiredBefore(item, cutoff))
        .map((i) => i.id)
        .toList();

    if (toArchive.isEmpty) return 0;

    var archived = 0;
    for (final id in toArchive) {
      try {
        await ref.read(itemsRepositoryProvider).archiveItem(id);
        archived++;
      } catch (e) {
        debugPrint('[AutoArchive] failed to archive $id: $e');
      }
    }

    if (archived > 0) {
      ref.invalidate(archivedItemsProvider);
      ref.invalidate(itemsProvider);
    }

    return archived;
  }

  bool _isExpiredBefore(Item item, DateTime cutoff) {
    final end = item.warrantyEndDate;
    if (end == null) return false;
    return end.isBefore(cutoff);
  }

  /// User-facing toggle. Default is enabled.
  static Future<bool> isEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_prefsKeyEnabled) ?? true;
  }

  static Future<void> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_prefsKeyEnabled, value);
  }
}

final autoArchiveServiceProvider = Provider<AutoArchiveService>((ref) {
  return AutoArchiveService(ref);
});
