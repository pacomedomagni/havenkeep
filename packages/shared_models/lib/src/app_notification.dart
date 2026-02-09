import 'enums.dart';

/// An in-app notification (warranty expiring, tips, etc.).
///
/// Named [AppNotification] to avoid conflict with Flutter's [Notification] class.
class AppNotification {
  final String id;
  final String userId;
  final String? itemId;
  final NotificationType type;
  final String title;
  final String body;
  final bool isRead;
  final NotificationAction? actionType;
  final Map<String, dynamic>? actionData;
  final DateTime scheduledAt;
  final DateTime? sentAt;
  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.itemId,
    required this.type,
    required this.title,
    required this.body,
    this.isRead = false,
    this.actionType,
    this.actionData,
    required this.scheduledAt,
    this.sentAt,
    required this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      itemId: json['item_id'] as String?,
      type: NotificationType.fromJson(json['type'] as String),
      title: json['title'] as String,
      body: json['body'] as String,
      isRead: json['is_read'] as bool? ?? false,
      actionType: json['action_type'] != null
          ? NotificationAction.fromJson(json['action_type'] as String)
          : null,
      actionData: json['action_data'] != null
          ? Map<String, dynamic>.from(json['action_data'] as Map)
          : null,
      scheduledAt: DateTime.parse(json['scheduled_at'] as String),
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'item_id': itemId,
      'type': type.toJson(),
      'title': title,
      'body': body,
      'is_read': isRead,
      'action_type': actionType?.toJson(),
      'action_data': actionData,
      'scheduled_at': scheduledAt.toIso8601String(),
      'sent_at': sentAt?.toIso8601String(),
    };
  }

  /// Whether this notification has been sent.
  bool get isSent => sentAt != null;

  /// Whether this notification is actionable (has a tap action).
  bool get isActionable => actionType != null;

  AppNotification copyWith({
    String? id,
    String? userId,
    String? itemId,
    bool clearItemId = false,
    NotificationType? type,
    String? title,
    String? body,
    bool? isRead,
    NotificationAction? actionType,
    bool clearActionType = false,
    Map<String, dynamic>? actionData,
    bool clearActionData = false,
    DateTime? scheduledAt,
    DateTime? sentAt,
    bool clearSentAt = false,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      itemId: clearItemId ? null : (itemId ?? this.itemId),
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      isRead: isRead ?? this.isRead,
      actionType:
          clearActionType ? null : (actionType ?? this.actionType),
      actionData:
          clearActionData ? null : (actionData ?? this.actionData),
      scheduledAt: scheduledAt ?? this.scheduledAt,
      sentAt: clearSentAt ? null : (sentAt ?? this.sentAt),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() => 'AppNotification(id: $id, title: $title, type: ${type.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppNotification && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
