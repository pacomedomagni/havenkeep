import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/notifications_provider.dart';
import '../../core/widgets/error_state_widget.dart';

/// Notifications list screen.
///
/// Shows all notifications with unread indicators, type icons, and time-ago text.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Notifications'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        actions: [
          if (unreadCount > 0)
            TextButton(
              onPressed: () {
                ref.read(notificationsProvider.notifier).markAllAsRead();
              },
              child: const Text(
                'Mark All Read',
                style: TextStyle(color: HavenColors.secondary, fontSize: 13),
              ),
            ),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return _buildEmptyState();
          }
          return RefreshIndicator(
            color: HavenColors.primary,
            onRefresh: () async {
              ref.read(notificationsProvider.notifier).refresh();
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm),
              itemCount: notifications.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: HavenColors.border,
                indent: HavenSpacing.lg + 40, // icon width + padding
              ),
              itemBuilder: (context, index) {
                return _NotificationCard(
                  notification: notifications[index],
                );
              },
            ),
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: const [
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
          ],
        ),
        error: (_, __) => ErrorStateWidget(
          message: 'Could not load notifications',
          onRetry: () => ref.read(notificationsProvider.notifier).refresh(),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none,
            size: 64,
            color: HavenColors.textTertiary,
          ),
          SizedBox(height: HavenSpacing.md),
          Text(
            'No notifications yet',
            style: TextStyle(
              fontSize: 18,
              color: HavenColors.textSecondary,
            ),
          ),
          SizedBox(height: HavenSpacing.xs),
          Text(
            "We'll notify you when warranties\nneed attention.",
            textAlign: TextAlign.center,
            style: TextStyle(
              color: HavenColors.textTertiary,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// A single notification card.
class _NotificationCard extends ConsumerWidget {
  final AppNotification notification;

  const _NotificationCard({required this.notification});

  IconData _iconForType(NotificationType type) {
    return switch (type) {
      NotificationType.warranty_expiring => Icons.warning_amber_rounded,
      NotificationType.warranty_expired => Icons.error_outline,
      NotificationType.item_added => Icons.add_circle_outline,
      NotificationType.warranty_extended => Icons.verified_outlined,
      NotificationType.tip => Icons.lightbulb_outline,
      NotificationType.system => Icons.info_outline,
    };
  }

  Color _colorForType(NotificationType type) {
    return switch (type) {
      NotificationType.warranty_expiring => HavenColors.expiring,
      NotificationType.warranty_expired => HavenColors.expired,
      NotificationType.item_added => HavenColors.active,
      NotificationType.warranty_extended => HavenColors.active,
      NotificationType.tip => HavenColors.secondary,
      NotificationType.system => HavenColors.textSecondary,
    };
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    if (diff.inDays < 30) return '${diff.inDays ~/ 7}w ago';
    return '${diff.inDays ~/ 30}mo ago';
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    // Mark as read
    if (!notification.isRead) {
      ref.read(notificationsProvider.notifier).markAsRead(notification.id);
    }

    // Navigate based on action type
    if (notification.actionType == NotificationAction.view_item &&
        notification.actionData != null) {
      final itemId = notification.actionData!['item_id'] as String?;
      if (itemId != null) {
        context.push('/items/$itemId');
        return;
      }
    }

    // For protection actions, navigate to premium screen
    if (notification.actionType == NotificationAction.get_protection) {
      context.push('/premium');
      return;
    }

    // For repair actions, open search for repair services
    if (notification.actionType == NotificationAction.find_repair) {
      final itemId = notification.actionData?['item_id'] as String?;
      if (itemId != null) {
        context.push('/items/$itemId');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typeColor = _colorForType(notification.type);

    return Semantics(
      label: notification.isRead ? '' : 'Unread',
      child: InkWell(
        onTap: () => _handleTap(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.md,
            vertical: HavenSpacing.md,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Unread dot
              SizedBox(
                width: 12,
                child: notification.isRead
                    ? const SizedBox.shrink()
                    : Container(
                        margin: const EdgeInsets.only(top: 6),
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: HavenColors.primary,
                          shape: BoxShape.circle,
                        ),
                      ),
              ),

              // Type icon
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: typeColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  _iconForType(notification.type),
                  color: typeColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: HavenSpacing.md),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight:
                            notification.isRead ? FontWeight.w400 : FontWeight.w600,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: const TextStyle(
                        fontSize: 13,
                        color: HavenColors.textSecondary,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: HavenSpacing.xs),
                    Text(
                      _timeAgo(notification.createdAt),
                      style: const TextStyle(
                        fontSize: 12,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron only for navigable actions (view_item)
              if (notification.actionType == NotificationAction.view_item &&
                  notification.actionData != null)
                const Icon(
                  Icons.chevron_right,
                  color: HavenColors.textTertiary,
                  size: 18,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
