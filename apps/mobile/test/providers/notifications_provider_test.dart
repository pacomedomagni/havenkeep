import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:havenkeep_mobile/core/providers/notifications_provider.dart';
import 'package:havenkeep_mobile/core/providers/auth_provider.dart';
import 'package:havenkeep_mobile/core/services/notifications_repository.dart';
import 'package:shared_models/shared_models.dart';

import '../helpers/test_helpers.dart';
import 'notifications_provider_test.mocks.dart';

/// Test notifier that immediately resolves to a fixed user value.
class _TestCurrentUserNotifier extends CurrentUserNotifier {
  final User? _user;
  _TestCurrentUserNotifier(this._user);

  @override
  Future<User?> build() async => _user;
}

/// Helper to create test AppNotification instances.
///
/// `isRead` is now a getter on the model (true iff `openedAt != null`)
/// — see Ch08-Notification-D041. Pass `isRead: true` to mark this row
/// as opened so the helper sets a synthetic `openedAt`.
AppNotification createTestNotification({
  String? id,
  String? title,
  String? body,
  bool isRead = false,
  NotificationType type = NotificationType.warranty_expiring,
}) {
  final now = DateTime.now();
  return AppNotification(
    id: id ?? 'notif-${now.millisecondsSinceEpoch}',
    userId: TestHelpers.testUserId,
    type: type,
    title: title ?? 'Test Notification',
    body: body ?? 'Test notification body',
    sentAt: now,
    openedAt: isRead ? now : null,
    createdAt: now,
  );
}

@GenerateMocks([NotificationsRepository])
void main() {
  late MockNotificationsRepository mockRepository;
  late ProviderContainer container;

  setUp(() {
    mockRepository = MockNotificationsRepository();
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
        notificationsRepositoryProvider.overrideWithValue(mockRepository),
        currentUserProvider.overrideWith(
          () => _TestCurrentUserNotifier(testUser),
        ),
      ],
    );
  }

  /// Pre-resolve the currentUserProvider, then read the notificationsProvider.
  /// NotificationsNotifier.build() watches currentUserProvider and needs it
  /// to be settled before it can fetch notifications.
  Future<List<AppNotification>> readNotifications(ProviderContainer c) async {
    await c.read(currentUserProvider.future);
    return c.read(notificationsProvider.future);
  }

  group('NotificationsNotifier', () {
    group('build', () {
      test('returns empty list when user is not authenticated', () async {
        container = createContainer(authenticated: false);

        final notifications = await readNotifications(container);

        expect(notifications, isEmpty);
        verifyNever(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        ));
      });

      test('fetches notifications when user is authenticated', () async {
        final testNotifications = [
          createTestNotification(id: 'notif-1', title: 'Warranty Expiring'),
          createTestNotification(id: 'notif-2', title: 'Maintenance Due'),
        ];

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => testNotifications);

        container = createContainer();

        final notifications = await readNotifications(container);

        expect(notifications, hasLength(2));
        expect(notifications[0].title, 'Warranty Expiring');
        expect(notifications[1].title, 'Maintenance Due');
        verify(mockRepository.getNotifications(
          limit: 30,
          page: 1,
        )).called(1);
      });

      test('handles error during initial load', () async {
        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenThrow(Exception('Network error'));

        container = createContainer();
        await container.read(currentUserProvider.future);

        expect(
          () => container.read(notificationsProvider.future),
          throwsA(isA<Exception>()),
        );
      });
    });

    group('markAsRead', () {
      test('marks single notification as read in state', () async {
        final notifications = [
          createTestNotification(id: 'notif-1', isRead: false),
          createTestNotification(id: 'notif-2', isRead: false),
        ];

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => notifications);
        when(mockRepository.markAsRead('notif-1'))
            .thenAnswer((_) async => {});

        container = createContainer();
        await readNotifications(container);

        await container.read(notificationsProvider.notifier).markAsRead('notif-1');

        final result = container.read(notificationsProvider).value;
        expect(result![0].isRead, isTrue);
        expect(result[1].isRead, isFalse);

        verify(mockRepository.markAsRead('notif-1')).called(1);
      });
    });

    group('markAllAsRead', () {
      test('marks all notifications as read in state', () async {
        final notifications = [
          createTestNotification(id: 'notif-1', isRead: false),
          createTestNotification(id: 'notif-2', isRead: false),
          createTestNotification(id: 'notif-3', isRead: false),
        ];

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => notifications);
        when(mockRepository.markAllAsRead())
            .thenAnswer((_) async => {});

        container = createContainer();
        await readNotifications(container);

        await container
            .read(notificationsProvider.notifier)
            .markAllAsRead();

        final result = container.read(notificationsProvider).value;
        expect(result!.every((n) => n.isRead), isTrue);

        verify(mockRepository.markAllAsRead()).called(1);
      });
    });

    group('refresh', () {
      test('refreshes notifications from repository', () async {
        final initialNotifications = [
          createTestNotification(id: 'notif-1', title: 'Initial'),
        ];
        final refreshedNotifications = [
          createTestNotification(id: 'notif-2', title: 'Refreshed 1'),
          createTestNotification(id: 'notif-3', title: 'Refreshed 2'),
        ];

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => initialNotifications);

        container = createContainer();
        await readNotifications(container);

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => refreshedNotifications);

        await container.read(notificationsProvider.notifier).refresh();

        final result = container.read(notificationsProvider).value;
        expect(result, hasLength(2));
        expect(result![0].title, 'Refreshed 1');
      });
    });

    group('loadMore', () {
      test('appends next page of notifications', () async {
        final page1 = List.generate(
          30,
          (i) => createTestNotification(id: 'notif-$i'),
        );
        final page2 = [
          createTestNotification(id: 'notif-30', title: 'Page 2'),
        ];

        var callCount = 0;
        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async {
          callCount++;
          return callCount == 1 ? page1 : page2;
        });

        container = createContainer();
        await readNotifications(container);

        await container.read(notificationsProvider.notifier).loadMore();

        final result = container.read(notificationsProvider).value;
        expect(result, hasLength(31));
        expect(result!.last.title, 'Page 2');
      });

      test('does not load more when no more pages', () async {
        // Return fewer than page size (30) to indicate no more pages
        final notifications = [
          createTestNotification(id: 'notif-1'),
        ];

        when(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).thenAnswer((_) async => notifications);

        container = createContainer();
        await readNotifications(container);

        // Should have hasMore = false since 1 < 30
        await container.read(notificationsProvider.notifier).loadMore();

        // Only called once for initial build, not again for loadMore
        verify(mockRepository.getNotifications(
          limit: anyNamed('limit'),
          page: anyNamed('page'),
        )).called(1);
      });
    });
  });

  group('unreadNotificationCountProvider', () {
    test('returns 0 when not authenticated', () async {
      container = createContainer(authenticated: false);
      await container.read(currentUserProvider.future);

      final count = await container.read(unreadNotificationCountProvider.future);

      expect(count, 0);
    });

    test('returns count from repository when authenticated', () async {
      when(mockRepository.getUnreadCount())
          .thenAnswer((_) async => 5);

      container = createContainer();
      await container.read(currentUserProvider.future);

      final count = await container.read(unreadNotificationCountProvider.future);

      expect(count, 5);
      verify(mockRepository.getUnreadCount()).called(1);
    });
  });
}
