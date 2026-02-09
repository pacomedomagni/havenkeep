import 'enums.dart';

/// An entry in the offline sync queue.
class OfflineQueueEntry {
  final String id;
  final String userId;
  final OfflineAction action;
  final Map<String, dynamic> payload;
  final OfflineStatus status;
  final DateTime createdAt;
  final DateTime? syncedAt;
  final int retryCount;

  const OfflineQueueEntry({
    required this.id,
    required this.userId,
    required this.action,
    required this.payload,
    this.status = OfflineStatus.pending,
    required this.createdAt,
    this.syncedAt,
    this.retryCount = 0,
  });

  factory OfflineQueueEntry.fromJson(Map<String, dynamic> json) {
    return OfflineQueueEntry(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      action: OfflineAction.fromJson(json['action'] as String),
      payload: Map<String, dynamic>.from(json['payload'] as Map),
      status: OfflineStatus.fromJson(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      syncedAt: json['synced_at'] != null
          ? DateTime.parse(json['synced_at'] as String)
          : null,
      retryCount: json['retry_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'action': action.toJson(),
      'payload': payload,
      'status': status.toJson(),
      'synced_at': syncedAt?.toIso8601String(),
      'retry_count': retryCount,
    };
  }

  /// Whether this entry can be retried.
  bool get canRetry => status == OfflineStatus.failed && retryCount < 3;

  /// Whether this entry is waiting to sync.
  bool get isPending => status == OfflineStatus.pending;

  OfflineQueueEntry copyWith({
    String? id,
    String? userId,
    OfflineAction? action,
    Map<String, dynamic>? payload,
    OfflineStatus? status,
    DateTime? createdAt,
    DateTime? syncedAt,
    bool clearSyncedAt = false,
    int? retryCount,
  }) {
    return OfflineQueueEntry(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      action: action ?? this.action,
      payload: payload ?? this.payload,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      syncedAt: clearSyncedAt ? null : (syncedAt ?? this.syncedAt),
      retryCount: retryCount ?? this.retryCount,
    );
  }

  @override
  String toString() =>
      'OfflineQueueEntry(id: $id, action: ${action.name}, status: ${status.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is OfflineQueueEntry && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
