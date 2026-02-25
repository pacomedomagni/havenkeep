/// Maintenance schedule for an item category.
class MaintenanceSchedule {
  final String id;
  final String category;
  final String taskName;
  final String? description;
  final int frequencyMonths;
  final int priority;
  final DateTime createdAt;

  const MaintenanceSchedule({
    required this.id,
    required this.category,
    required this.taskName,
    this.description,
    required this.frequencyMonths,
    this.priority = 0,
    required this.createdAt,
  });

  factory MaintenanceSchedule.fromJson(Map<String, dynamic> json) {
    return MaintenanceSchedule(
      id: json['id'] as String? ?? '',
      category: json['category'] as String? ?? '',
      taskName: json['task_name'] as String? ?? '',
      description: json['description'] as String?,
      frequencyMonths: (json['frequency_months'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'category': category,
        'task_name': taskName,
        'description': description,
        'frequency_months': frequencyMonths,
        'priority': priority,
        'created_at': createdAt.toIso8601String(),
      };
}

/// A single maintenance history entry.
class MaintenanceHistory {
  final String id;
  final String userId;
  final String itemId;
  final String? scheduleId;
  final String taskName;
  final DateTime completedDate;
  final String? notes;
  final int? durationMinutes;
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
      completedDate: DateTime.tryParse(json['completed_date'] as String? ?? '') ?? DateTime.now(),
      notes: json['notes'] as String?,
      durationMinutes: (json['duration_minutes'] as num?)?.toInt(),
      cost: json['cost'] != null ? (json['cost'] as num).toDouble() : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ?? DateTime.now(),
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
        if (cost != null) 'cost': cost,
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
    this.priority = 0,
    this.isRequiredForWarranty = false,
    this.howToUrl,
    this.videoUrl,
    this.frequencyLabel,
  });

  factory MaintenanceDueTask.fromJson(Map<String, dynamic> json) {
    return MaintenanceDueTask(
      scheduleId: json['schedule_id'] as String? ?? '',
      taskName: json['task_name'] as String? ?? '',
      nextDue: DateTime.tryParse(json['next_due'] as String? ?? '') ?? DateTime.now(),
      isOverdue: json['is_overdue'] as bool? ?? false,
      daysUntilDue: (json['days_until_due'] as num?)?.toInt() ?? 0,
      priority: (json['priority'] as num?)?.toInt() ?? 0,
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
  final String category;
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
      category: json['category'] as String? ?? '',
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
