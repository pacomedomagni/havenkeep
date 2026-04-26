import 'package:api_client/api_client.dart';
import 'package:flutter/foundation.dart';

/// Slim mobile-side projection of the backend `audit_log` row. Only the
/// fields surfaced by the dashboard activity feed are modeled — full audit
/// inspection lives in admin tooling, not the app.
class RecentActivity {
  final String id;
  final String action;
  final String? description;
  final String? resourceType;
  final String? resourceId;
  final DateTime createdAt;

  const RecentActivity({
    required this.id,
    required this.action,
    required this.createdAt,
    this.description,
    this.resourceType,
    this.resourceId,
  });

  factory RecentActivity.fromJson(Map<String, dynamic> json) {
    return RecentActivity(
      id: json['id'] as String,
      action: json['action'] as String,
      description: json['description'] as String?,
      resourceType: json['resource_type'] as String?,
      resourceId: json['resource_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

/// Reads the current user's audit log for the dashboard "what just happened"
/// feed. Server endpoint is `/api/v1/audit/logs/me` — same handler that
/// admin tooling hits, just scoped to the caller via JWT.
class AuditLogRepository {
  final ApiClient _client;

  AuditLogRepository(this._client);

  Future<List<RecentActivity>> getRecentActivity({int limit = 10}) async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'audit', 'logs', 'me'],
        queryParams: {'page': '1', 'limit': '$limit'},
      );
      final rows = (data['data'] as List?) ?? const [];
      return rows
          .whereType<Map<String, dynamic>>()
          .map(RecentActivity.fromJson)
          .toList();
    } catch (e) {
      debugPrint('[AuditLogRepository] getRecentActivity failed: $e');
      rethrow;
    }
  }
}
