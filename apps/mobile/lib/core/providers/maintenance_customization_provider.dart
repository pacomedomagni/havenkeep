import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/maintenance_customization_service.dart';

/// Per-item maintenance schedule customization. Loads from local prefs
/// and persists every mutation back so the customization survives restart.
///
/// Server-side customization is the long-term plan (see CLAUDE.md Part 3
/// §C); this provider is shaped so a server-backed implementation is a
/// drop-in swap of the persistence layer.
final maintenanceCustomizationProvider = AsyncNotifierProvider.family<
    MaintenanceCustomizationNotifier,
    MaintenanceCustomization,
    String>(MaintenanceCustomizationNotifier.new);

class MaintenanceCustomizationNotifier
    extends FamilyAsyncNotifier<MaintenanceCustomization, String> {
  @override
  Future<MaintenanceCustomization> build(String itemId) {
    return MaintenanceCustomizationService.load(itemId);
  }

  /// Override the cadence for a single default schedule. Pass null to
  /// clear an existing override (revert to the catalog default).
  Future<void> setFrequencyOverride(String scheduleId, int? months) async {
    final current = state.value ?? MaintenanceCustomization.empty(arg);
    final next = Map<String, int>.from(current.frequencyOverrides);
    if (months == null) {
      next.remove(scheduleId);
    } else {
      next[scheduleId] = months;
    }
    final updated = current.copyWith(frequencyOverrides: next);
    await MaintenanceCustomizationService.save(updated);
    state = AsyncValue.data(updated);
  }

  /// Toggle whether a default schedule is enabled for this item.
  Future<void> setEnabled(String scheduleId, bool enabled) async {
    final current = state.value ?? MaintenanceCustomization.empty(arg);
    final next = Set<String>.from(current.disabledScheduleIds);
    if (enabled) {
      next.remove(scheduleId);
    } else {
      next.add(scheduleId);
    }
    final updated = current.copyWith(disabledScheduleIds: next);
    await MaintenanceCustomizationService.save(updated);
    state = AsyncValue.data(updated);
  }

  /// Add a custom maintenance task on top of the catalog defaults.
  Future<void> addExtraTask(CustomMaintenanceTask task) async {
    final current = state.value ?? MaintenanceCustomization.empty(arg);
    final next = [...current.extraTasks, task];
    final updated = current.copyWith(extraTasks: next);
    await MaintenanceCustomizationService.save(updated);
    state = AsyncValue.data(updated);
  }

  /// Remove a previously-added custom task.
  Future<void> removeExtraTask(String id) async {
    final current = state.value ?? MaintenanceCustomization.empty(arg);
    final next = current.extraTasks.where((t) => t.id != id).toList();
    final updated = current.copyWith(extraTasks: next);
    await MaintenanceCustomizationService.save(updated);
    state = AsyncValue.data(updated);
  }
}
