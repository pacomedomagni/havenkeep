/// User notification preferences.
class NotificationPreferences {
  final String userId;
  final bool remindersEnabled;
  final int firstReminderDays;
  final String reminderTime; // Stored as 'HH:mm' string
  final bool warrantyOffersEnabled;
  final bool tipsEnabled;
  final bool pushEnabled;
  final bool emailEnabled;

  const NotificationPreferences({
    required this.userId,
    this.remindersEnabled = true,
    this.firstReminderDays = 30,
    this.reminderTime = '09:00',
    this.warrantyOffersEnabled = true,
    this.tipsEnabled = true,
    this.pushEnabled = true,
    this.emailEnabled = false,
  });

  factory NotificationPreferences.fromJson(Map<String, dynamic> json) {
    return NotificationPreferences(
      userId: json['user_id'] as String,
      remindersEnabled: json['reminders_enabled'] as bool? ?? true,
      firstReminderDays: json['first_reminder_days'] as int? ?? 30,
      reminderTime: json['reminder_time'] as String? ?? '09:00',
      warrantyOffersEnabled:
          json['warranty_offers_enabled'] as bool? ?? true,
      tipsEnabled: json['tips_enabled'] as bool? ?? true,
      pushEnabled: json['push_enabled'] as bool? ?? true,
      emailEnabled: json['email_enabled'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'reminders_enabled': remindersEnabled,
      'first_reminder_days': firstReminderDays,
      'reminder_time': reminderTime,
      'warranty_offers_enabled': warrantyOffersEnabled,
      'tips_enabled': tipsEnabled,
      'push_enabled': pushEnabled,
      'email_enabled': emailEnabled,
    };
  }

  /// Parse reminder time into hour and minute.
  int get reminderHour {
    final parts = reminderTime.split(':');
    if (parts.length != 2) return 9; // fallback
    final h = int.tryParse(parts[0]) ?? 9;
    return h.clamp(0, 23);
  }

  int get reminderMinute {
    final parts = reminderTime.split(':');
    if (parts.length != 2) return 0; // fallback
    final m = int.tryParse(parts[1]) ?? 0;
    return m.clamp(0, 59);
  }

  NotificationPreferences copyWith({
    String? userId,
    bool? remindersEnabled,
    int? firstReminderDays,
    String? reminderTime,
    bool? warrantyOffersEnabled,
    bool? tipsEnabled,
    bool? pushEnabled,
    bool? emailEnabled,
  }) {
    return NotificationPreferences(
      userId: userId ?? this.userId,
      remindersEnabled: remindersEnabled ?? this.remindersEnabled,
      firstReminderDays: firstReminderDays ?? this.firstReminderDays,
      reminderTime: reminderTime ?? this.reminderTime,
      warrantyOffersEnabled:
          warrantyOffersEnabled ?? this.warrantyOffersEnabled,
      tipsEnabled: tipsEnabled ?? this.tipsEnabled,
      pushEnabled: pushEnabled ?? this.pushEnabled,
      emailEnabled: emailEnabled ?? this.emailEnabled,
    );
  }

  @override
  String toString() => 'NotificationPreferences(userId: $userId)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationPreferences && other.userId == userId;

  @override
  int get hashCode => userId.hashCode;
}
