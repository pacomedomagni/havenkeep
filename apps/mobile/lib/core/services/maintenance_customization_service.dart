import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Local persistence for per-item maintenance schedule customizations.
/// The server still owns the catalog of default schedules per category;
/// this layer lets a user override the cadence for a specific item or
/// suppress a default task entirely.
///
/// Backend post-Phase 7 doesn't expose a `user_maintenance_schedules`
/// table, so we keep this client-side. The shape is intentionally narrow
/// so a future server migration is a straight swap of this service for an
/// API repository — the [MaintenanceCustomization] data class is what the
/// UI consumes either way.
class MaintenanceCustomizationService {
  MaintenanceCustomizationService._();

  static const _prefix = 'maintenance_customization_';

  /// Storage key used by tests + this service. Public so we have a single
  /// source of truth for the prefs format.
  static String storageKey(String itemId) => '$_prefix$itemId';

  /// Load the customization for an item. Returns an empty customization
  /// (no overrides, no disabled tasks) when the user hasn't tweaked it yet.
  static Future<MaintenanceCustomization> load(String itemId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(storageKey(itemId));
    if (raw == null) return MaintenanceCustomization.empty(itemId);
    try {
      final json = jsonDecode(raw) as Map<String, dynamic>;
      return MaintenanceCustomization.fromJson(itemId, json);
    } catch (_) {
      // Corrupt prefs entries should not crash the screen; behave as if
      // the user had never customized.
      await prefs.remove(storageKey(itemId));
      return MaintenanceCustomization.empty(itemId);
    }
  }

  /// Persist a customization. Empty customizations are removed so we
  /// don't leave dead keys behind.
  static Future<void> save(MaintenanceCustomization custom) async {
    final prefs = await SharedPreferences.getInstance();
    if (custom.isEmpty) {
      await prefs.remove(storageKey(custom.itemId));
      return;
    }
    await prefs.setString(storageKey(custom.itemId), jsonEncode(custom.toJson()));
  }
}

/// Per-item override of the default maintenance catalog.
///
/// - [frequencyOverrides] maps a default scheduleId → frequency in months
///   the user prefers (e.g. "do this every 3 months instead of 6").
/// - [disabledScheduleIds] lists default tasks the user opted out of.
/// - [extraTasks] is for custom tasks the user added on top of the defaults.
class MaintenanceCustomization {
  final String itemId;
  final Map<String, int> frequencyOverrides;
  final Set<String> disabledScheduleIds;
  final List<CustomMaintenanceTask> extraTasks;

  const MaintenanceCustomization({
    required this.itemId,
    required this.frequencyOverrides,
    required this.disabledScheduleIds,
    required this.extraTasks,
  });

  factory MaintenanceCustomization.empty(String itemId) =>
      MaintenanceCustomization(
        itemId: itemId,
        frequencyOverrides: const {},
        disabledScheduleIds: const {},
        extraTasks: const [],
      );

  bool get isEmpty =>
      frequencyOverrides.isEmpty &&
      disabledScheduleIds.isEmpty &&
      extraTasks.isEmpty;

  MaintenanceCustomization copyWith({
    Map<String, int>? frequencyOverrides,
    Set<String>? disabledScheduleIds,
    List<CustomMaintenanceTask>? extraTasks,
  }) {
    return MaintenanceCustomization(
      itemId: itemId,
      frequencyOverrides: frequencyOverrides ?? this.frequencyOverrides,
      disabledScheduleIds: disabledScheduleIds ?? this.disabledScheduleIds,
      extraTasks: extraTasks ?? this.extraTasks,
    );
  }

  Map<String, dynamic> toJson() => {
        'frequency_overrides': frequencyOverrides,
        'disabled_schedule_ids': disabledScheduleIds.toList(),
        'extra_tasks': extraTasks.map((t) => t.toJson()).toList(),
      };

  factory MaintenanceCustomization.fromJson(
      String itemId, Map<String, dynamic> json) {
    final freq = <String, int>{};
    final rawFreq = json['frequency_overrides'];
    if (rawFreq is Map) {
      rawFreq.forEach((k, v) {
        if (k is String && v is num) freq[k] = v.toInt();
      });
    }
    final disabled = <String>{};
    final rawDisabled = json['disabled_schedule_ids'];
    if (rawDisabled is List) {
      for (final e in rawDisabled) {
        if (e is String) disabled.add(e);
      }
    }
    final extras = <CustomMaintenanceTask>[];
    final rawExtras = json['extra_tasks'];
    if (rawExtras is List) {
      for (final e in rawExtras) {
        if (e is Map<String, dynamic>) {
          extras.add(CustomMaintenanceTask.fromJson(e));
        }
      }
    }
    return MaintenanceCustomization(
      itemId: itemId,
      frequencyOverrides: freq,
      disabledScheduleIds: disabled,
      extraTasks: extras,
    );
  }
}

/// A task the user added on top of the default catalog. `id` is locally
/// generated; if/when this moves server-side, the server will mint the
/// canonical id.
class CustomMaintenanceTask {
  final String id;
  final String name;
  final int frequencyMonths;

  const CustomMaintenanceTask({
    required this.id,
    required this.name,
    required this.frequencyMonths,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'frequency_months': frequencyMonths,
      };

  factory CustomMaintenanceTask.fromJson(Map<String, dynamic> json) {
    return CustomMaintenanceTask(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      frequencyMonths: (json['frequency_months'] as num?)?.toInt() ?? 12,
    );
  }
}
