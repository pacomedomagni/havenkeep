import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/maintenance_snooze_service.dart';

/// Active snoozes (key → deadline) keyed by [MaintenanceSnoozeService.storageKey].
/// The maintenance dashboard filters tasks against this map so a snoozed
/// task disappears immediately on tap rather than waiting for the next
/// fetch.
final activeMaintenanceSnoozesProvider =
    AsyncNotifierProvider<ActiveSnoozesNotifier, Map<String, DateTime>>(
  ActiveSnoozesNotifier.new,
);

class ActiveSnoozesNotifier extends AsyncNotifier<Map<String, DateTime>> {
  @override
  Future<Map<String, DateTime>> build() {
    return MaintenanceSnoozeService.loadActive();
  }

  /// Persist a snooze and update local state so the UI reflects it
  /// without a re-fetch.
  Future<void> snooze({
    required String itemId,
    required String scheduleId,
    required MaintenanceSnoozeOption option,
    required DateTime nextDue,
  }) async {
    await MaintenanceSnoozeService.snooze(
      itemId: itemId,
      scheduleId: scheduleId,
      option: option,
      nextDue: nextDue,
    );
    final refreshed = await MaintenanceSnoozeService.loadActive();
    state = AsyncValue.data(refreshed);
  }

  /// Clear a snooze (e.g. user marked the task done early).
  Future<void> clear({
    required String itemId,
    required String scheduleId,
  }) async {
    await MaintenanceSnoozeService.clear(
      itemId: itemId,
      scheduleId: scheduleId,
    );
    final refreshed = await MaintenanceSnoozeService.loadActive();
    state = AsyncValue.data(refreshed);
  }
}
