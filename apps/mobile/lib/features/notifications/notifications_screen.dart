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
            const _MarkAllReadButton(),
        ],
      ),
      body: notificationsAsync.when(
        data: (notifications) {
          if (notifications.isEmpty) {
            return _buildEmptyState();
          }
          final notifier = ref.read(notificationsProvider.notifier);
          final hasMore = notifier.hasMore;

          return RefreshIndicator(
            color: HavenColors.primary,
            onRefresh: () async {
              ref.read(notificationsProvider.notifier).refresh();
            },
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm),
              itemCount: notifications.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                color: HavenColors.border,
                indent: HavenSpacing.lg + 40, // icon width + padding
              ),
              itemBuilder: (context, index) {
                // Load-more trigger at the end
                if (index == notifications.length) {
                  notifier.loadMore();
                  return const Padding(
                    padding: EdgeInsets.all(HavenSpacing.lg),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: HavenColors.primary,
                        ),
                      ),
                    ),
                  );
                }
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
      NotificationType.maintenance_due => Icons.build_outlined,
      NotificationType.claim_update => Icons.assignment_turned_in_outlined,
      NotificationType.claim_opportunity => Icons.assignment_outlined,
      NotificationType.health_score_update => Icons.monitor_heart_outlined,
      NotificationType.gift_received => Icons.card_giftcard_outlined,
      NotificationType.gift_activated => Icons.redeem_outlined,
      NotificationType.partner_commission => Icons.payments_outlined,
      NotificationType.promotional => Icons.local_offer_outlined,
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
      NotificationType.maintenance_due => HavenColors.expiring,
      NotificationType.claim_update => HavenColors.active,
      NotificationType.claim_opportunity => HavenColors.expiring,
      NotificationType.health_score_update => HavenColors.secondary,
      NotificationType.gift_received => HavenColors.primary,
      NotificationType.gift_activated => HavenColors.active,
      NotificationType.partner_commission => HavenColors.primary,
      NotificationType.promotional => HavenColors.secondary,
      NotificationType.tip => HavenColors.secondary,
      NotificationType.system => HavenColors.textSecondary,
    };
  }

  String _timeAgo(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.isNegative || diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    final weeks = diff.inDays ~/ 7;
    if (diff.inDays < 30) return '${weeks}w ago';
    final months = diff.inDays ~/ 30;
    if (months < 12) return '${months}mo ago';
    final years = months ~/ 12;
    return '${years}y ago';
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

/// Mark all read button with loading state.
class _MarkAllReadButton extends ConsumerStatefulWidget {
  const _MarkAllReadButton();

  @override
  ConsumerState<_MarkAllReadButton> createState() => _MarkAllReadButtonState();
}

class _MarkAllReadButtonState extends ConsumerState<_MarkAllReadButton> {
  bool _isLoading = false;

  Future<void> _markAllRead() async {
    setState(() => _isLoading = true);
    try {
      await ref.read(notificationsProvider.notifier).markAllAsRead();
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: _isLoading ? null : _markAllRead,
      child: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HavenColors.secondary,
              ),
            )
          : const Text(
              'Mark All Read',
              style: TextStyle(color: HavenColors.secondary, fontSize: 13),
            ),
    );
  }
}
