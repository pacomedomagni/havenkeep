import 'enums.dart';

/// Difficulty rating for a maintenance task. Mirrors the
/// `maintenance_schedules.difficulty` CHECK enum (Ch08-MaintenanceSchedule-D033).
enum MaintenanceDifficulty {
  easy,
  medium,
  hard;

  static const Map<String, MaintenanceDifficulty> _byName = {
    'easy': MaintenanceDifficulty.easy,
    'medium': MaintenanceDifficulty.medium,
    'hard': MaintenanceDifficulty.hard,
  };

  factory MaintenanceDifficulty.fromJson(String value) {
    return _byName[value] ?? MaintenanceDifficulty.easy;
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        MaintenanceDifficulty.easy => 'Easy',
        MaintenanceDifficulty.medium => 'Medium',
        MaintenanceDifficulty.hard => 'Hard',
      };
}

/// Maintenance schedule for an item category.
class MaintenanceSchedule {
  final String id;

  /// Ch08-MaintenanceSchedule-D032: typed as [ItemCategory] (was free-text
  /// `String`) so the mobile drift detector catches new categories that the
  /// schedule seed forgets to add.
  final ItemCategory category;

  final String taskName;
  final String? description;
  final int frequencyMonths;

  /// Ch08-MaintenanceSchedule-D034: matches the `priority INTEGER DEFAULT 5`
  /// on the `maintenance_schedules` table. Was 0 (silently downgraded every
  /// task to lowest priority on hydrate-render round-trip).
  final int priority;

  final String? frequencyLabel;
  final int? estimatedDurationMinutes;
  final MaintenanceDifficulty? difficulty;
  final double? preventsCost;
  final String? howToUrl;
  final String? videoUrl;
  final List<String>? toolsNeeded;
  final bool isRequiredForWarranty;
  final DateTime createdAt;

  /// Ch08-MaintenanceSchedule-D035: column added by mig 002 + mig 045's
  /// trigger but the model never surfaced it.
  final DateTime updatedAt;

  const MaintenanceSchedule({
    required this.id,
    required this.category,
    required this.taskName,
    this.description,
    required this.frequencyMonths,
    this.priority = 5,
    this.frequencyLabel,
    this.estimatedDurationMinutes,
    this.difficulty,
    this.preventsCost,
    this.howToUrl,
    this.videoUrl,
    this.toolsNeeded,
    this.isRequiredForWarranty = false,
    required this.createdAt,
    required this.updatedAt,
  });

  factory MaintenanceSchedule.fromJson(Map<String, dynamic> json) {
    return MaintenanceSchedule(
      id: json['id'] as String? ?? '',
      category: ItemCategory.fromJson(json['category'] as String? ?? 'other'),
      taskName: json['task_name'] as String? ?? '',
      description: json['description'] as String?,
      frequencyMonths: (json['frequency_months'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 5,
      frequencyLabel: json['frequency_label'] as String?,
      estimatedDurationMinutes:
          (json['estimated_duration_minutes'] as num?)?.toInt(),
      difficulty: json['difficulty'] != null
          ? MaintenanceDifficulty.fromJson(json['difficulty'] as String)
          : null,
      preventsCost: json['prevents_cost'] != null
          ? (json['prevents_cost'] as num).toDouble()
          : null,
      howToUrl: json['how_to_url'] as String?,
      videoUrl: json['video_url'] as String?,
      toolsNeeded: json['tools_needed'] != null
          ? (json['tools_needed'] as List).map((e) => e as String).toList()
          : null,
      isRequiredForWarranty:
          json['is_required_for_warranty'] as bool? ?? false,
      // 4.1: server-stamped timestamps fall back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category.toJson(),
        'task_name': taskName,
        'description': description,
        'frequency_months': frequencyMonths,
        'priority': priority,
        'frequency_label': frequencyLabel,
        'estimated_duration_minutes': estimatedDurationMinutes,
        'difficulty': difficulty?.toJson(),
        'prevents_cost': preventsCost,
        'how_to_url': howToUrl,
        'video_url': videoUrl,
        'tools_needed': toolsNeeded,
        'is_required_for_warranty': isRequiredForWarranty,
        'created_at': createdAt.toIso8601String(),
        'updated_at': updatedAt.toIso8601String(),
      };
}

/// A single maintenance history entry.
class MaintenanceHistory {
  final String id;
  final String userId;
  final String itemId;
  final String? scheduleId;
  final String taskName;

  /// Required on both the Joi side and Dart side
  /// (Ch08-MaintenanceLog-D030).
  final DateTime completedDate;

  final String? notes;
  final int? durationMinutes;

  /// Tri-state cost (Ch08-MaintenanceLog-D031):
  ///   - `null` ⇒ user didn't enter a cost
  ///   - `0`    ⇒ user explicitly logged zero cost (e.g. cleaning)
  ///   - `> 0`  ⇒ real out-of-pocket cost
  final double? cost;

  final DateTime createdAt;

  // Joined fields
  final String? itemName;
  final String? itemBrand;

  const MaintenanceHistory({
    required this.id,
    required this.userId,
    required this.itemId,
    this.scheduleId,
    required this.taskName,
    required this.completedDate,
    this.notes,
    this.durationMinutes,
    this.cost,
    required this.createdAt,
    this.itemName,
    this.itemBrand,
  });

  factory MaintenanceHistory.fromJson(Map<String, dynamic> json) {
    return MaintenanceHistory(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      itemId: json['item_id'] as String? ?? '',
      scheduleId: json['schedule_id'] as String?,
      taskName: json['task_name'] as String? ?? '',
      completedDate: _parseDate(json['completed_date'])!,
      notes: json['notes'] as String?,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      cost: json['cost'] != null ? (json['cost'] as num).toDouble() : null,
      // 4.1: server-stamped timestamp falls back instead of crashing.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      itemName: json['item_name'] as String?,
      itemBrand: json['item_brand'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'item_id': itemId,
        'schedule_id': scheduleId,
        'task_name': taskName,
        'completed_date': completedDate.toIso8601String(),
        'notes': notes,
        'duration_minutes': durationMinutes,
        'cost': cost,
        'created_at': createdAt.toIso8601String(),
      };

  Map<String, dynamic> toCreateJson() => {
        'item_id': itemId,
        if (scheduleId != null) 'schedule_id': scheduleId,
        'task_name': taskName,
        'completed_date': completedDate.toIso8601String(),
        if (notes != null) 'notes': notes,
        if (durationMinutes != null) 'duration_minutes': durationMinutes,
        // Tri-state: emit null explicitly so the server knows the user
        // chose "unknown" rather than omitted the key.
        'cost': cost,
      };
}

/// A due/overdue maintenance task (from the /due endpoint).
class MaintenanceDueTask {
  final String scheduleId;
  final String taskName;
  final DateTime nextDue;
  final bool isOverdue;
  final int daysUntilDue;
  final int priority;
  final bool isRequiredForWarranty;
  final String? howToUrl;
  final String? videoUrl;
  final String? frequencyLabel;

  const MaintenanceDueTask({
    required this.scheduleId,
    required this.taskName,
    required this.nextDue,
    required this.isOverdue,
    required this.daysUntilDue,
    this.priority = 5,
    this.isRequiredForWarranty = false,
    this.howToUrl,
    this.videoUrl,
    this.frequencyLabel,
  });

  factory MaintenanceDueTask.fromJson(Map<String, dynamic> json) {
    return MaintenanceDueTask(
      scheduleId: json['schedule_id'] as String? ?? '',
      taskName: json['task_name'] as String? ?? '',
      nextDue: _parseDate(json['next_due'])!,
      isOverdue: json['is_overdue'] as bool? ?? false,
      daysUntilDue: (json['days_until_due'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 5,
      isRequiredForWarranty: json['is_required_for_warranty'] as bool? ?? false,
      howToUrl: json['how_to_url'] as String?,
      videoUrl: json['video_url'] as String?,
      frequencyLabel: json['frequency_label'] as String?,
    );
  }
}

/// An item with its due maintenance tasks.
class MaintenanceDueItem {
  final String itemId;
  final String itemName;
  final ItemCategory category;
  final int dueCount;
  final int overdueCount;
  final List<MaintenanceDueTask> tasks;

  const MaintenanceDueItem({
    required this.itemId,
    required this.itemName,
    required this.category,
    required this.dueCount,
    required this.overdueCount,
    required this.tasks,
  });

  factory MaintenanceDueItem.fromJson(Map<String, dynamic> json) {
    return MaintenanceDueItem(
      itemId: json['item_id'] as String? ?? '',
      itemName: json['item_name'] as String? ?? '',
      category: ItemCategory.fromJson(json['category'] as String? ?? 'other'),
      dueCount: (json['due_count'] as num?)?.toInt() ?? 0,
      overdueCount: (json['overdue_count'] as num?)?.toInt() ?? 0,
      tasks: json['tasks'] is List
          ? (json['tasks'] as List)
              .map((t) => MaintenanceDueTask.fromJson(t as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

/// Summary of due maintenance across all items.
class MaintenanceDueSummary {
  final int totalDue;
  final int totalOverdue;
  final List<MaintenanceDueItem> items;

  const MaintenanceDueSummary({
    required this.totalDue,
    required this.totalOverdue,
    required this.items,
  });

  factory MaintenanceDueSummary.fromJson(Map<String, dynamic> json) {
    return MaintenanceDueSummary(
      totalDue: (json['total_due'] as num?)?.toInt() ?? 0,
      totalOverdue: (json['total_overdue'] as num?)?.toInt() ?? 0,
      items: json['items'] is List
          ? (json['items'] as List)
              .map((i) => MaintenanceDueItem.fromJson(i as Map<String, dynamic>))
              .toList()
          : [],
    );
  }
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
