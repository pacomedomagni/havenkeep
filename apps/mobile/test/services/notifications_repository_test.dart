import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:havenkeep_mobile/core/services/notifications_repository.dart';
import 'package:api_client/api_client.dart';
import 'package:shared_models/shared_models.dart';

import 'notifications_repository_test.mocks.dart';

@GenerateMocks([ApiClient])
void main() {
  late MockApiClient mockClient;
  late NotificationsRepository repository;

  setUp(() {
    mockClient = MockApiClient();
    repository = NotificationsRepository(mockClient);
  });

  /// Helper to create a valid notification JSON.
  ///
  /// Mirrors the API contract after Phase 8: `sent_at` is now NOT NULL
  /// on the wire (Ch08-Notification-D040), `is_read` is derived from
  /// `opened_at` rather than stored as a column (Ch08-Notification-D041),
  /// and `scheduled_at` is removed (Ch08-Notification-D043).
  Map<String, dynamic> notificationJson({
    String id = 'notif-1',
    String title = 'Test Notification',
    bool isRead = false,
  }) {
    return {
      'id': id,
      'user_id': 'user-1',
      'type': 'warranty_expiring',
      'title': title,
      'body': 'Your warranty is expiring soon.',
      'sent_at': '2026-01-15T09:00:00.000Z',
      if (isRead) 'opened_at': '2026-01-15T10:00:00.000Z',
      'created_at': '2026-01-01T00:00:00.000Z',
    };
  }

  group('NotificationsRepository', () {
    group('getNotifications', () {
      test('sends page parameter (not offset) for pagination', () async {
        // This verifies the recent fix: the API uses `page` not `offset`
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {
                  'data': [notificationJson()],
                });

        await repository.getNotifications(limit: 30, page: 2);

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;

        // Must use 'page' NOT 'offset'
        expect(captured['page'], '2');
        expect(captured['limit'], '30');
        expect(captured.containsKey('offset'), isFalse);
      });

      test('parses list of notifications', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {
                  'data': [
                    notificationJson(id: 'notif-1', title: 'First'),
                    notificationJson(id: 'notif-2', title: 'Second'),
                    notificationJson(id: 'notif-3', title: 'Third'),
                  ],
                });

        final notifications = await repository.getNotifications();

        expect(notifications, hasLength(3));
        expect(notifications[0].id, 'notif-1');
        expect(notifications[0].title, 'First');
        expect(notifications[1].id, 'notif-2');
        expect(notifications[2].id, 'notif-3');
      });

      test('sends default pagination parameters', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getNotifications();

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;

        expect(captured['limit'], '30');
        expect(captured['page'], '1');
      });

      test('includes unread filter when requested', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getNotifications(unreadOnly: true);

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;

        expect(captured['unread'], 'true');
      });

      test('does not include unread filter by default', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
                queryParams: anyNamed('queryParams')))
            .thenAnswer((_) async => {'data': []});

        await repository.getNotifications();

        final captured = verify(mockClient.get(pathSegments: const ['api', 'v1', 'notifications'],
          queryParams: captureAnyNamed('queryParams'),
        )).captured.single as Map<String, String>;

        expect(captured.containsKey('unread'), isFalse);
      });
    });

    group('getUnreadCount', () {
      test('calls correct endpoint and returns count', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications', 'unread-count']))
            .thenAnswer((_) async => {
                  'data': {'count': 7},
                });

        final count = await repository.getUnreadCount();

        expect(count, 7);
        verify(mockClient.get(pathSegments: const ['api', 'v1', 'notifications', 'unread-count'])).called(1);
      });

      test('returns 0 when count is null', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications', 'unread-count']))
            .thenAnswer((_) async => {
                  'data': {'count': null},
                });

        final count = await repository.getUnreadCount();

        expect(count, 0);
      });
    });

    group('markAsRead', () {
      test('calls correct endpoint with notification ID', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'notif-1', 'read']))
            .thenAnswer((_) async => {});

        await repository.markAsRead('notif-1');

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'notif-1', 'read'])).called(1);
      });
    });

    group('markAllAsRead', () {
      test('calls correct endpoint', () async {
        when(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'read-all']))
            .thenAnswer((_) async => {});

        await repository.markAllAsRead();

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'read-all'])).called(1);
      });
    });

    group('getPreferences', () {
      test('returns notification preferences', () async {
        // Phase 8 made `created_at`/`updated_at` NOT NULL on the wire —
        // include them in the fixture so `fromJson` doesn't blow up.
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications', 'preferences']))
            .thenAnswer((_) async => {
                  'data': {
                    'user_id': 'user-1',
                    'reminders_enabled': true,
                    'first_reminder_days': 30,
                    'reminder_time': '09:00',
                    'warranty_offers_enabled': false,
                    'tips_enabled': true,
                    'push_enabled': true,
                    'email_enabled': false,
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final prefs = await repository.getPreferences();

        expect(prefs, isNotNull);
        expect(prefs!.userId, 'user-1');
        expect(prefs.remindersEnabled, isTrue);
        expect(prefs.warrantyOffersEnabled, isFalse);
        expect(prefs.firstReminderDays, 30);
      });

      test('returns null when no preferences set', () async {
        when(mockClient.get(pathSegments: const ['api', 'v1', 'notifications', 'preferences']))
            .thenAnswer((_) async => {'data': null});

        final prefs = await repository.getPreferences();

        expect(prefs, isNull);
      });
    });

    group('upsertPreferences', () {
      test('sends PUT with preferences JSON', () async {
        final prefs = NotificationPreferences(
          userId: 'user-1',
          remindersEnabled: true,
          pushEnabled: false,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        when(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'preferences'],
                body: anyNamed('body')))
            .thenAnswer((_) async => {
                  'data': {
                    'user_id': 'user-1',
                    'reminders_enabled': true,
                    'first_reminder_days': 30,
                    'reminder_time': '09:00',
                    'warranty_offers_enabled': true,
                    'tips_enabled': true,
                    'push_enabled': false,
                    'email_enabled': false,
                    'created_at': '2026-01-01T00:00:00.000Z',
                    'updated_at': '2026-01-01T00:00:00.000Z',
                  },
                });

        final result = await repository.upsertPreferences(prefs);

        expect(result.pushEnabled, isFalse);

        verify(mockClient.put(pathSegments: const ['api', 'v1', 'notifications', 'preferences'],
          body: anyNamed('body'),
        )).called(1);
      });
    });
  });
}
