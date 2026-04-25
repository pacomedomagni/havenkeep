import 'enums.dart';

/// An in-app notification (warranty expiring, tips, etc.).
///
/// Mirrors the `notification_history` table on the API. Field names use
/// snake_case to match the JSON envelope returned by `notifications.service.ts`.
///
/// Ch08-Notification-D036..D047: this model previously fabricated a
/// `scheduledAt` (no DB column) and an `actionType` (no DB column), and
/// missed real columns the server emits (`template_id`, `gift_id`,
/// `delivered_at`, `action_taken`, `action_taken_at`, `platform`,
/// `fcm_message_id`). All fixed; navigation is now driven off [type] and
/// [data] rather than a phantom action enum.
///
/// Named [AppNotification] to avoid conflict with Flutter's [Notification]
/// class.
class AppNotification {
  final String id;
  final String userId;

  /// Notification template id this row was rendered from. Null for
  /// notifications created without a template (Ch08-Notification-D036).
  final String? templateId;

  /// FK to the related item. Null when the notification isn't item-scoped
  /// (e.g. partner_commission).
  final String? itemId;

  /// FK to the partner_gift this notification announces, when applicable
  /// (Ch08-Notification-D037).
  final String? giftId;

  final NotificationType type;
  final String title;
  final String body;

  /// Server-side payload. The shape varies by [type] — for `view_item` the
  /// mobile router pulls `data['item_id']`, for `get_protection` it
  /// navigates to `/premium`, etc. (Ch08-Notification-D039: the column is
  /// `data` on the server, NOT `action_data`.)
  final Map<String, dynamic> data;

  /// Notifications service stamps `sent_at = NOW()` on insert; the column
  /// is NOT NULL on the API (Ch08-Notification-D040).
  final DateTime sentAt;

  final DateTime? deliveredAt;
  final DateTime? openedAt;

  /// Free-text action label set by the client when the user taps a CTA on
  /// the notification (Ch08-Notification-D042).
  final String? actionTaken;

  final DateTime? actionTakenAt;

  /// 'mobile' | 'web' | 'email' (Ch08-Notification-D044). Nullable for
  /// pre-history rows.
  final String? platform;

  /// FCM message id when the notification was also pushed
  /// (Ch08-Notification-D045).
  final String? fcmMessageId;

  final DateTime createdAt;

  const AppNotification({
    required this.id,
    required this.userId,
    this.templateId,
    this.itemId,
    this.giftId,
    required this.type,
    required this.title,
    required this.body,
    this.data = const {},
    required this.sentAt,
    this.deliveredAt,
    this.openedAt,
    this.actionTaken,
    this.actionTakenAt,
    this.platform,
    this.fcmMessageId,
    required this.createdAt,
  });

  /// True iff the user has opened this notification.
  bool get isRead => openedAt != null;

  factory AppNotification.fromJson(Map<String, dynamic> json) {
    return AppNotification(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      templateId: json['template_id'] as String?,
      itemId: json['item_id'] as String?,
      giftId: json['gift_id'] as String?,
      type: NotificationType.fromJson(json['type'] as String? ?? 'system'),
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
      data: json['data'] is Map
          ? Map<String, dynamic>.from(json['data'] as Map)
          : const {},
      sentAt: _parseDate(json['sent_at'])!,
      deliveredAt: _parseDate(json['delivered_at']),
      openedAt: _parseDate(json['opened_at']),
      actionTaken: json['action_taken'] as String?,
      actionTakenAt: _parseDate(json['action_taken_at']),
      platform: json['platform'] as String?,
      fcmMessageId: json['fcm_message_id'] as String?,
      createdAt: _parseDate(json['created_at'])!,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      if (templateId != null) 'template_id': templateId,
      'item_id': itemId,
      if (giftId != null) 'gift_id': giftId,
      'type': type.toJson(),
      'title': title,
      'body': body,
      'data': data,
      'sent_at': sentAt.toIso8601String(),
      if (deliveredAt != null) 'delivered_at': deliveredAt!.toIso8601String(),
      if (openedAt != null) 'opened_at': openedAt!.toIso8601String(),
      if (actionTaken != null) 'action_taken': actionTaken,
      if (actionTakenAt != null)
        'action_taken_at': actionTakenAt!.toIso8601String(),
      if (platform != null) 'platform': platform,
      if (fcmMessageId != null) 'fcm_message_id': fcmMessageId,
      'created_at': createdAt.toIso8601String(),
    };
  }

  AppNotification copyWith({
    String? id,
    String? userId,
    String? templateId,
    bool clearTemplateId = false,
    String? itemId,
    bool clearItemId = false,
    String? giftId,
    bool clearGiftId = false,
    NotificationType? type,
    String? title,
    String? body,
    Map<String, dynamic>? data,
    DateTime? sentAt,
    DateTime? deliveredAt,
    bool clearDeliveredAt = false,
    DateTime? openedAt,
    bool clearOpenedAt = false,
    String? actionTaken,
    bool clearActionTaken = false,
    DateTime? actionTakenAt,
    bool clearActionTakenAt = false,
    String? platform,
    bool clearPlatform = false,
    String? fcmMessageId,
    bool clearFcmMessageId = false,
    DateTime? createdAt,
  }) {
    return AppNotification(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      templateId: clearTemplateId ? null : (templateId ?? this.templateId),
      itemId: clearItemId ? null : (itemId ?? this.itemId),
      giftId: clearGiftId ? null : (giftId ?? this.giftId),
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      data: data ?? this.data,
      sentAt: sentAt ?? this.sentAt,
      deliveredAt: clearDeliveredAt ? null : (deliveredAt ?? this.deliveredAt),
      openedAt: clearOpenedAt ? null : (openedAt ?? this.openedAt),
      actionTaken: clearActionTaken ? null : (actionTaken ?? this.actionTaken),
      actionTakenAt:
          clearActionTakenAt ? null : (actionTakenAt ?? this.actionTakenAt),
      platform: clearPlatform ? null : (platform ?? this.platform),
      fcmMessageId:
          clearFcmMessageId ? null : (fcmMessageId ?? this.fcmMessageId),
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  String toString() =>
      'AppNotification(id: $id, title: $title, type: ${type.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AppNotification && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
