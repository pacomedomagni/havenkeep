import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/notifications_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/error_state_widget.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';

/// Notifications list screen.
///
/// Shows all notifications with unread indicators, type icons, and time-ago text.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsProvider);
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

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
          // 3.3: scroll-end driven load-more. The previous shape called
          // `notifier.loadMore()` from inside `itemBuilder` for the last
          // index — itemBuilder runs synchronously during paint, so a
          // throw bubbled up into the framework and the snackbar
          // ScaffoldMessenger.of(context) reached for a non-existent
          // ancestor. The notification listener pattern fires once, off
          // the paint phase, with `unawaited(...)` so the failure is
          // surfaced via state-bound `lastLoadMoreError` instead.
          return _NotificationsList(notifications: notifications);
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
          HavenIllustration(
            kind: HavenIllustrationKind.noNotifications,
            size: 180,
          ),
          SizedBox(height: HavenSpacing.md),
          Text('No notifications yet', style: HavenText.displayMedium),
          SizedBox(height: HavenSpacing.xs),
          Text(
            "We'll notify you when warranties\nneed attention.",
            textAlign: TextAlign.center,
            style: HavenText.bodySecondary,
          ),
        ],
      ),
    );
  }
}

/// 3.3: scroll-end driven pagination. Watches the inner list's scroll
/// notifications and triggers `loadMore()` exactly once per arrival at
/// the bottom. Holds `_lastError` locally so a failed page surfaces a
/// retry chip without re-entering the build path that lost the snackbar
/// before.
class _NotificationsList extends ConsumerStatefulWidget {
  final List<AppNotification> notifications;
  const _NotificationsList({required this.notifications});

  @override
  ConsumerState<_NotificationsList> createState() => _NotificationsListState();
}

class _NotificationsListState extends ConsumerState<_NotificationsList> {
  /// Near-bottom threshold that fires `loadMore`. Picked so a slow
  /// network has roughly one screen of runway before the loader spins.
  static const _loadMoreThresholdPx = 240.0;

  bool _loadingMore = false;
  String? _lastError;

  Future<void> _maybeLoadMore() async {
    final notifier = ref.read(notificationsProvider.notifier);
    if (!notifier.hasMore || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _lastError = null;
    });
    try {
      await notifier.loadMore();
    } catch (e) {
      if (mounted) {
        setState(() => _lastError = ErrorHandler.getUserMessage(e));
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool _onScroll(ScrollNotification n) {
    if (n is ScrollEndNotification || n is UserScrollNotification) {
      final pos = n.metrics;
      if (pos.axis == Axis.vertical &&
          pos.pixels >= pos.maxScrollExtent - _loadMoreThresholdPx) {
        unawaited(_maybeLoadMore());
      }
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final notifier = ref.watch(notificationsProvider.notifier);
    final hasMore = notifier.hasMore;
    final entries = _groupByBucket(widget.notifications);

    return RefreshIndicator(
      color: HavenColors.primary,
      onRefresh: () async {
        await ref.read(notificationsProvider.notifier).refresh();
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm),
          // +1 footer slot reserved for the loader / error chip when
          // there are more pages to fetch.
          itemCount: entries.length + (hasMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == entries.length) {
              if (_lastError != null) {
                return Padding(
                  padding: const EdgeInsets.all(HavenSpacing.lg),
                  child: Center(
                    child: TextButton.icon(
                      onPressed: _maybeLoadMore,
                      icon: const Icon(Icons.refresh, size: 16),
                      label: Text('Retry • $_lastError'),
                      style: TextButton.styleFrom(
                        foregroundColor: HavenColors.expired,
                      ),
                    ),
                  ),
                );
              }
              return const Padding(
                padding: EdgeInsets.all(HavenSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: HavenLoader(color: HavenColors.primary),
                  ),
                ),
              );
            }

            final entry = entries[index];
            if (entry is _BucketHeader) {
              return Padding(
                padding: const EdgeInsets.fromLTRB(
                  HavenSpacing.md,
                  HavenSpacing.md,
                  HavenSpacing.md,
                  HavenSpacing.xs,
                ),
                child: Text(
                  entry.label,
                  style: HavenText.badge.copyWith(
                    color: HavenColors.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
              );
            }
            final n = (entry as _BucketItem).notification;
            return Dismissible(
              key: ValueKey('notif-${n.id}'),
              direction: DismissDirection.endToStart,
              background: Container(
                color: HavenColors.expired.withValues(alpha: 0.9),
                alignment: Alignment.centerRight,
                padding: const EdgeInsets.only(right: HavenSpacing.lg),
                child: const Icon(Icons.archive_outlined,
                    color: HavenColors.textPrimary),
              ),
              onDismissed: (_) async {
                await ref
                    .read(notificationsProvider.notifier)
                    .dismiss(n.id);
              },
              child: _NotificationCard(notification: n),
            );
          },
        ),
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
    // Ch08-Notification-D047: navigation is driven off [type] + [data] now.
    // The server doesn't emit a separate `action_type` column — the action
    // is implied by the notification's category, with the optional payload
    // in `data` providing the resource id.
    final itemId = notification.itemId ?? notification.data['item_id'] as String?;
    final type = notification.type;
    bool navigated = false;

    if (type == NotificationType.warranty_expiring ||
        type == NotificationType.warranty_expired ||
        type == NotificationType.warranty_extended ||
        type == NotificationType.maintenance_due ||
        type == NotificationType.item_added ||
        type == NotificationType.claim_update) {
      if (itemId != null) {
        context.push('/items/$itemId');
        navigated = true;
      }
    } else if (type == NotificationType.claim_opportunity) {
      // Free users get protection upsells, premium users get item detail.
      context.push('/premium');
      navigated = true;
    } else if (type == NotificationType.gift_received ||
        type == NotificationType.gift_activated) {
      context.push('/premium');
      navigated = true;
    }

    if (!notification.isRead) {
      ref.read(notificationsProvider.notifier).markAsRead(notification.id);
    }

    // Silence the unused-local lint when the if-chain falls through with
    // no navigation target (system / promotional / tip notifications).
    if (!navigated) return;
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
                  color: typeColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(HavenRadius.pill),
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

              // Chevron only when there's a known navigation target derived
              // from the notification type (Ch08-Notification-D047).
              if (_navigates(notification))
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

/// True if the notification's [type] (and required `data` keys) implies a
/// navigation target. Mirrors the switch in `_NotificationCard._handleTap`.
bool _navigates(AppNotification notification) {
  switch (notification.type) {
    case NotificationType.warranty_expiring:
    case NotificationType.warranty_expired:
    case NotificationType.warranty_extended:
    case NotificationType.maintenance_due:
    case NotificationType.item_added:
    case NotificationType.claim_update:
      return notification.itemId != null ||
          notification.data['item_id'] != null;
    case NotificationType.claim_opportunity:
    case NotificationType.gift_received:
    case NotificationType.gift_activated:
      return true;
    case NotificationType.health_score_update:
    case NotificationType.promotional:
    case NotificationType.tip:
    case NotificationType.system:
      return false;
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
              child: HavenLoader(color: HavenColors.secondary),
            )
          : const Text(
              'Mark All Read',
              style: TextStyle(color: HavenColors.secondary, fontSize: 13),
            ),
    );
  }
}

/// Virtual list entry — either a bucket header or a notification row.
sealed class _Entry {
  const _Entry();
}

class _BucketHeader extends _Entry {
  final String label;
  const _BucketHeader(this.label);
}

class _BucketItem extends _Entry {
  final AppNotification notification;
  const _BucketItem(this.notification);
}

/// Groups notifications into Today / Yesterday / This week / Earlier buckets.
List<_Entry> _groupByBucket(List<AppNotification> notifications) {
  final now = DateTime.now();
  final startOfToday = DateTime(now.year, now.month, now.day);
  final startOfYesterday = startOfToday.subtract(const Duration(days: 1));
  final startOfWeek = startOfToday.subtract(Duration(days: now.weekday - 1));

  String bucket(DateTime t) {
    if (!t.isBefore(startOfToday)) return 'TODAY';
    if (!t.isBefore(startOfYesterday)) return 'YESTERDAY';
    if (!t.isBefore(startOfWeek)) return 'THIS WEEK';
    return 'EARLIER';
  }

  final entries = <_Entry>[];
  String? currentBucket;
  for (final n in notifications) {
    final label = bucket(n.createdAt);
    if (label != currentBucket) {
      entries.add(_BucketHeader(label));
      currentBucket = label;
    }
    entries.add(_BucketItem(n));
  }
  return entries;
}

