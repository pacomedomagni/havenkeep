import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/maintenance_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'maintenance_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late MaintenanceRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = MaintenanceRepository(mockClient);
  });

  /// Helper to build a valid maintenance schedule JSON.
  ///
  /// Mirrors the API contract after Phase 8: `updated_at` is now NOT
  /// NULL on the wire (Ch08-MaintenanceSchedule).
  Map<String, dynamic> scheduleJson({
    String id = 'sched-1',
    String category = 'refrigerator',
    String taskName = 'Clean condenser coils',
    int frequencyMonths = 6,
  }) {
    return {
      'id': id,
      'category': category,
      'task_name': taskName,
      'frequency_months': frequencyMonths,
      'created_at': '2026-01-01T00:00:00.000Z',
      'updated_at': '2026-01-01T00:00:00.000Z',
    };
  }

  /// Helper to build a valid maintenance history JSON.
  Map<String, dynamic> historyJson({
    String id = 'hist-1',
    String itemId = 'item-1',
    String taskName = 'Changed filter',
  }) {
    return {
      'id': id,
      'user_id': 'user-1',
      'item_id': itemId,
      'task_name': taskName,
      'completed_date': '2026-01-15T00:00:00.000Z',
      'created_at': '2026-01-15T00:00:00.000Z',
    };
  }

  /// Helper to build a valid due summary JSON.
  Map<String, dynamic> dueSummaryJson({
    int totalDue = 2,
    int totalOverdue = 1,
  }) {
    return {
      'total_due': totalDue,
      'total_overdue': totalOverdue,
      'items': [],
    };
  }

  group('MaintenanceRepository', () {
    group('getDueTasks', () {
      test('calls correct endpoint', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'due']))
            .thenAnswer((_) async => {
                  'data': dueSummaryJson(),
                });

        await repository.getDueTasks();

        verify(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'due'])).called(1);
      });

      test('returns parsed MaintenanceDueSummary', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'due']))
            .thenAnswer((_) async => {
                  'data': dueSummaryJson(totalDue: 5, totalOverdue: 2),
                });

        final summary = await repository.getDueTasks();

        expect(summary.totalDue, 5);
        expect(summary.totalOverdue, 2);
        expect(summary.items, isEmpty);
      });

      test('rethrows errors from API client', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'due']))
            .thenThrow(ApiException.fromResponse(500, 'Server error'));

        expect(
          () => repository.getDueTasks(),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getSchedules', () {
      test('includes category in URL path', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'schedules', 'refrigerator']))
            .thenAnswer((_) async => {'data': []});

        await repository.getSchedules('refrigerator');

        verify(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'schedules', 'refrigerator']))
            .called(1);
      });

      test('returns parsed list of schedules', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'schedules', 'hvac']))
            .thenAnswer((_) async => {
                  'data': [
                    scheduleJson(
                      id: 'sched-1',
                      category: 'hvac',
                      taskName: 'Replace air filter',
                    ),
                    scheduleJson(
                      id: 'sched-2',
                      category: 'hvac',
                      taskName: 'Clean ducts',
                    ),
                  ],
                });

        final schedules = await repository.getSchedules('hvac');

        expect(schedules, hasLength(2));
        expect(schedules[0].id, 'sched-1');
        expect(schedules[0].taskName, 'Replace air filter');
        expect(schedules[1].taskName, 'Clean ducts');
      });
    });

    group('logTask', () {
      test('sends POST to correct endpoint with entry body', () async {
        final now = DateTime.now();
        final entry = MaintenanceHistory(
          id: 'temp-id',
          userId: 'user-1',
          itemId: 'item-1',
          taskName: 'Replaced water filter',
          completedDate: now,
          createdAt: now,
        );

        when(mockClient.post(pathSegments: const ['api', 'v1', 'maintenance', 'log'],
          body: anyNamed('body'),
        )).thenAnswer((_) async => {
              'data': historyJson(id: 'created-hist', taskName: 'Replaced water filter'),
            });

        final logged = await repository.logTask(entry);

        expect(logged.id, 'created-hist');
        expect(logged.taskName, 'Replaced water filter');
        verify(mockClient.post(pathSegments: const ['api', 'v1', 'maintenance', 'log'],
          body: anyNamed('body'),
        )).called(1);
      });
    });

    group('getHistory', () {
      test('calls correct endpoint with pagination params', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'history'],
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getHistory();

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'history'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['page'], '1');
        expect(captured['limit'], '100');
      });

      test('sends item_id query param when itemId is provided', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'history'],
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {'data': []});

        await repository.getHistory(itemId: 'item-55');

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'history'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;
        expect(captured['item_id'], 'item-55');
      });

      test('returns parsed list of history entries', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'history'],
          queryParams: anyNamed('queryParams'),
        )).thenAnswer((_) async => {
              'data': [
                historyJson(id: 'hist-1', taskName: 'Changed filter'),
                historyJson(id: 'hist-2', taskName: 'Cleaned coils'),
              ],
            });

        final history = await repository.getHistory();

        expect(history, hasLength(2));
        expect(history[0].id, 'hist-1');
        expect(history[0].taskName, 'Changed filter');
      });
    });

    group('deleteLog', () {
      test('sends DELETE to correct endpoint with ID', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'maintenance', 'history', 'hist-99']))
            .thenAnswer((_) async => {});

        await repository.deleteLog('hist-99');

        verify(mockClient.delete(pathSegments: const ['api', 'v1', 'maintenance', 'history', 'hist-99']))
            .called(1);
      });

      test('rethrows errors on delete failure', () async {
        when(mockClient.delete(pathSegments: const ['api', 'v1', 'maintenance', 'history', 'hist-1']))
            .thenThrow(ApiException.fromResponse(404, 'Not found'));

        expect(
          () => repository.deleteLog('hist-1'),
          throwsA(isA<ApiException>()),
        );
      });
    });

    group('getSavings', () {
      test('calls correct endpoint and returns parsed data', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'savings']))
            .thenAnswer((_) async => {
                  'data': {
                    'total_saved': 800.0,
                    'task_count': 12,
                  },
                });

        final savings = await repository.getSavings();

        expect(savings['total_saved'], 800.0);
        expect(savings['task_count'], 12);
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'maintenance', 'savings'])).called(1);
      });
    });
  });
}
