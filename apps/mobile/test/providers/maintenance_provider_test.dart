import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/maintenance_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/maintenance_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'maintenance_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

/// Helper to create test MaintenanceSchedule instances.
MaintenanceSchedule createTestSchedule({
  String? id,
  ItemCategory? category,
  String? taskName,
  int frequencyMonths = 3,
}) {
  final now = DateTime.now();
  return MaintenanceSchedule(
    id: id ?? 'schedule-${now.millisecondsSinceEpoch}',
    category: category ?? ItemCategory.refrigerator,
    taskName: taskName ?? 'Clean condenser coils',
    frequencyMonths: frequencyMonths,
    createdAt: now,
    updatedAt: now,
  );
}

/// Helper to create test MaintenanceHistory instances.
MaintenanceHistory createTestHistory({
  String? id,
  String? itemId,
  String? taskName,
}) {
  return MaintenanceHistory(
    id: id ?? 'history-${DateTime.now().millisecondsSinceEpoch}',
    userId: TestHelpers.testUserId,
    itemId: itemId ?? 'test-item-1',
    taskName: taskName ?? 'Changed filter',
    completedDate: DateTime.now(),
    createdAt: DateTime.now(),
  );
}

@GenerateMocks([MaintenanceRepository])
void main() {
  late MockMaintenanceRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockMaintenanceRepository();
  });

  tearDown(() {
    container.dispose();
  });

  ProviderContainer createContainer({bool authenticated = true}) {
    final testUser = authenticated
        ? TestHelpers.createTestUser(id: TestHelpers.testUserId)
        : null;

    return ProviderContainer(
      overrides: [
        maintenanceRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  group('maintenanceDueProvider', () {
    test('returns empty summary when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final summary = await container.read(maintenanceDueProvider.future);

      expect(summary.totalDue, 0);
      expect(summary.totalOverdue, 0);
      expect(summary.items, isEmpty);
      verifyNever(mockRepository.getDueTasks());
    });

    test('fetches due tasks when authenticated', () async {
      final dueSummary = MaintenanceDueSummary(
        totalDue: 3,
        totalOverdue: 1,
        summaryState: MaintenanceSummaryState.hasDue,
        items: [
          MaintenanceDueItem(
            itemId: 'item-1',
            itemName: 'Refrigerator',
            category: ItemCategory.refrigerator,
            dueCount: 2,
            overdueCount: 1,
            tasks: [
              MaintenanceDueTask(
                scheduleId: 'sched-1',
                taskName: 'Clean coils',
                nextDue: DateTime.now(),
                isOverdue: true,
                daysUntilDue: -5,
              ),
            ],
          ),
        ],
      );

      when(mockRepository.getDueTasks())
          .thenAnswer((_) async => dueSummary);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final summary = await container.read(maintenanceDueProvider.future);

      expect(summary.totalDue, 3);
      expect(summary.totalOverdue, 1);
      expect(summary.items, hasLength(1));
      expect(summary.items[0].itemName, 'Refrigerator');
      verify(mockRepository.getDueTasks()).called(1);
    });

    test('handles error when fetching due tasks', () async {
      when(mockRepository.getDueTasks())
          .thenThrow(Exception('Network error'));

      container = createContainer();
      await container.read(currentUserProvider.future);

      expect(
        () => container.read(maintenanceDueProvider.future),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('maintenanceHistoryProvider', () {
    test('returns empty list when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final history = await container.read(maintenanceHistoryProvider.future);

      expect(history, isEmpty);
      verifyNever(mockRepository.getHistory());
    });

    test('fetches history when authenticated', () async {
      final testHistory = [
        createTestHistory(id: 'hist-1', taskName: 'Changed filter'),
        createTestHistory(id: 'hist-2', taskName: 'Cleaned coils'),
      ];

      when(mockRepository.getHistory())
          .thenAnswer((_) async => testHistory);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final history = await container.read(maintenanceHistoryProvider.future);

      expect(history, hasLength(2));
      expect(history[0].taskName, 'Changed filter');
      expect(history[1].taskName, 'Cleaned coils');
      verify(mockRepository.getHistory()).called(1);
    });
  });

  group('maintenanceSchedulesProvider', () {
    test('returns schedules for a specific category', () async {
      final schedules = [
        createTestSchedule(
          id: 'sched-1',
          category: ItemCategory.refrigerator,
          taskName: 'Clean condenser coils',
          frequencyMonths: 6,
        ),
        createTestSchedule(
          id: 'sched-2',
          category: ItemCategory.refrigerator,
          taskName: 'Replace water filter',
          frequencyMonths: 6,
        ),
      ];

      when(mockRepository.getSchedules('refrigerator'))
          .thenAnswer((_) async => schedules);

      container = createContainer();

      final result = await container
          .read(maintenanceSchedulesProvider('refrigerator').future);

      expect(result, hasLength(2));
      expect(result[0].taskName, 'Clean condenser coils');
      expect(result[1].taskName, 'Replace water filter');
      verify(mockRepository.getSchedules('refrigerator')).called(1);
    });

    test('returns different schedules per category', () async {
      final fridgeSchedules = [
        createTestSchedule(
          category: ItemCategory.refrigerator,
          taskName: 'Clean coils',
        ),
      ];
      final hvacSchedules = [
        createTestSchedule(
          category: ItemCategory.hvac,
          taskName: 'Replace air filter',
        ),
        createTestSchedule(
          category: ItemCategory.hvac,
          taskName: 'Clean ducts',
        ),
      ];

      when(mockRepository.getSchedules('refrigerator'))
          .thenAnswer((_) async => fridgeSchedules);
      when(mockRepository.getSchedules('hvac'))
          .thenAnswer((_) async => hvacSchedules);

      container = createContainer();

      final fridge = await container
          .read(maintenanceSchedulesProvider('refrigerator').future);
      final hvac = await container
          .read(maintenanceSchedulesProvider('hvac').future);

      expect(fridge, hasLength(1));
      expect(hvac, hasLength(2));
    });

    test('handles error when fetching schedules', () async {
      when(mockRepository.getSchedules(any))
          .thenThrow(Exception('Network error'));

      container = createContainer();

      expect(
        () => container.read(maintenanceSchedulesProvider('refrigerator').future),
        throwsA(isA<Exception>()),
      );
    });
  });
}
