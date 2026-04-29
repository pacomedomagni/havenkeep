import 'package:flutter/foundation.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

/// Handles maintenance CRUD via the Express API.
class MaintenanceRepository {
  final ApiClient _client;

  MaintenanceRepository(this._client);

  /// Get due/overdue maintenance tasks across all user items.
  ///
  /// 2.13: when [homeId] is supplied, the API scopes the summary to a
  /// single home so the dashboard agrees with the home-switcher.
  Future<MaintenanceDueSummary> getDueTasks({String? homeId}) async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'maintenance', 'due'],
        queryParams: homeId != null ? {'home_id': homeId} : null,
      );
      return MaintenanceDueSummary.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[MaintenanceRepository] getDueTasks failed: $e');
      rethrow;
    }
  }

  /// Get maintenance schedules for a category.
  Future<List<MaintenanceSchedule>> getSchedules(String category) async {
    try {
      final data = await _client.get(
        pathSegments: ['api', 'v1', 'maintenance', 'schedules', category],
      );
      return (data['data'] as List)
          .map((json) => MaintenanceSchedule.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MaintenanceRepository] getSchedules failed: $e');
      rethrow;
    }
  }

  /// Log a completed maintenance task.
  Future<MaintenanceHistory> logTask(MaintenanceHistory entry) async {
    try {
      final data = await _client.post(
        pathSegments: const ['api', 'v1', 'maintenance', 'log'],
        body: entry.toCreateJson(),
      );
      return MaintenanceHistory.fromJson(data['data'] as Map<String, dynamic>);
    } catch (e) {
      debugPrint('[MaintenanceRepository] logTask failed: $e');
      rethrow;
    }
  }

  /// Get maintenance history with optional item / home filter.
  Future<List<MaintenanceHistory>> getHistory({String? itemId, String? homeId}) async {
    try {
      final params = <String, String>{
        'limit': '100',
        'page': '1',
      };
      if (itemId != null) params['item_id'] = itemId;
      if (homeId != null) params['home_id'] = homeId;

      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'maintenance', 'history'],
        queryParams: params,
      );
      return (data['data'] as List)
          .map((json) => MaintenanceHistory.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MaintenanceRepository] getHistory failed: $e');
      rethrow;
    }
  }

  /// Get paginated maintenance history.
  Future<List<MaintenanceHistory>> getHistoryPaginated({
    required int limit,
    required int page,
    String? itemId,
  }) async {
    try {
      final params = <String, String>{
        'limit': limit.toString(),
        'page': page.toString(),
      };
      if (itemId != null) params['item_id'] = itemId;

      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'maintenance', 'history'],
        queryParams: params,
      );
      return (data['data'] as List)
          .map((json) => MaintenanceHistory.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('[MaintenanceRepository] getHistoryPaginated failed: $e');
      rethrow;
    }
  }

  /// Delete a maintenance log entry.
  Future<void> deleteLog(String id) async {
    try {
      await _client.delete(
        pathSegments: ['api', 'v1', 'maintenance', 'history', id],
      );
    } catch (e) {
      debugPrint('[MaintenanceRepository] deleteLog failed: $e');
      rethrow;
    }
  }

  /// Get preventive maintenance savings.
  Future<Map<String, dynamic>> getSavings() async {
    try {
      final data = await _client.get(
        pathSegments: const ['api', 'v1', 'maintenance', 'savings'],
      );
      return data['data'] as Map<String, dynamic>;
    } catch (e) {
      debugPrint('[MaintenanceRepository] getSavings failed: $e');
      rethrow;
    }
  }
}
