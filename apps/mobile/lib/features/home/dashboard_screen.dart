import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/providers/notifications_provider.dart';
import '../../core/router/router.dart';
import '../../core/widgets/value_dashboard_card.dart';

/// Home dashboard — the main screen (Screen 3.1).
///
/// Shows:
/// - Time-based greeting
/// - Warranty summary card (active / expiring / expired counts)
/// - Needs Attention section (max 3 items)
/// - Tip card (contextual, dismissible)
/// - Empty state when no items
class DashboardScreen extends ConsumerStatefulWidget {
  const DashboardScreen({super.key});

  @override
  ConsumerState<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends ConsumerState<DashboardScreen> {
  bool _tipDismissed = false;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _tipDismissed = prefs.getBool('tip_dismissed') ?? false;
        });
      }
    });
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good morning';
    if (hour >= 12 && hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(warrantyStatsProvider);
    final needsAttention = ref.watch(needsAttentionProvider);
    final items = ref.watch(itemsProvider);
    final firstName =
        user.value?.fullName?.split(' ').first ?? 'there';

    final hasItems =
        items.value != null && items.value!.isNotEmpty;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset(
              'assets/images/logo-icon.svg',
              width: 28,
              height: 28,
            ),
            const SizedBox(width: 8),
            const _HomeSwitcher(),
          ],
        ),
        actions: [
          // Notification bell with unread badge
          _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(itemsProvider);
        },
        color: HavenColors.primary,
        child: ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: [
            // Greeting with avatar
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_getGreeting()}, $firstName',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                ),
                _UserAvatar(user: user.value),
              ],
            ),
            const SizedBox(height: HavenSpacing.lg),

            // Empty state
            if (!hasItems && items.hasValue) ...[
              _buildEmptyState(context),
            ] else ...[
              // Value dashboard card
              stats.when(
                data: (data) {
                  final totalValue = items.value?.fold<double>(
                        0,
                        (sum, item) => sum + (item.price ?? 0),
                      ) ??
                      0;
                  final totalItems = items.value?.length ?? 0;
                  final active = data['active'] ?? 0;
                  final expiring = data['expiring'] ?? 0;
                  final expired = data['expired'] ?? 0;
                  final totalWithWarranty = active + expiring + expired;
                  final warrantyHealth = totalWithWarranty > 0
                      ? (active / totalWithWarranty * 100).round()
                      : 0;

                  return ValueDashboardCard(
                    totalValue: totalValue,
                    warrantyHealth: warrantyHealth,
                    totalItems: totalItems,
                    activeWarranties: active,
                    onTap: () => context.push(AppRoutes.items),
                  );
                },
                loading: () => Container(
                  height: 280,
                  decoration: BoxDecoration(
                    color: HavenColors.surface,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                error: (error, _) => Center(
                  child: TextButton.icon(
                    onPressed: () => ref.invalidate(itemsProvider),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Retry'),
                  ),
                ),
              ),
              const SizedBox(height: HavenSpacing.lg),

              // Warranty summary card
              _buildWarrantySummary(stats),
              const SizedBox(height: HavenSpacing.lg),

              // Needs attention section
              _buildNeedsAttention(needsAttention),

              // Maintenance card
              const SizedBox(height: HavenSpacing.lg),
              const _MaintenanceCard(),

              // Tip card
              if (!_tipDismissed) ...[
                const SizedBox(height: HavenSpacing.lg),
                _buildTipCard(),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: HavenSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.inventory_2_outlined,
              size: 72,
              color: HavenColors.textTertiary,
            ),
            const SizedBox(height: HavenSpacing.md),
            const Text(
              'Your vault is empty',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: HavenColors.textPrimary,
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),
            const Text(
              'Add your first item to start\ntracking your warranties.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: HavenColors.textSecondary,
                height: 1.4,
              ),
            ),
            const SizedBox(height: HavenSpacing.lg),
            SizedBox(
              width: 220,
              child: ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.addItem),
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Item'),
              ),
            ),
            const SizedBox(height: HavenSpacing.sm),
            TextButton(
              onPressed: () => context.go(AppRoutes.homeSetup),
              child: const Text(
                'Just moved in? Set Up Your Home',
                style: TextStyle(color: HavenColors.secondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarrantySummary(AsyncValue<Map<String, int>> stats) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'YOUR WARRANTIES',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: HavenColors.textTertiary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: HavenSpacing.md),
          stats.when(
            data: (data) => Row(
              children: [
                _StatCard(
                  count: data['active'] ?? 0,
                  label: 'Active',
                  color: HavenColors.active,
                  onTap: () => _navigateToItemsWithFilter('active'),
                ),
                const SizedBox(width: HavenSpacing.sm),
                _StatCard(
                  count: data['expiring'] ?? 0,
                  label: 'Expiring',
                  color: HavenColors.expiring,
                  onTap: () => _navigateToItemsWithFilter('expiring'),
                ),
                const SizedBox(width: HavenSpacing.sm),
                _StatCard(
                  count: data['expired'] ?? 0,
                  label: 'Expired',
                  color: HavenColors.expired,
                  onTap: () => _navigateToItemsWithFilter('expired'),
                ),
              ],
            ),
            loading: () => Row(
              children: List.generate(
                3,
                (_) => Expanded(
                  child: Container(
                    height: 80,
                    margin:
                        const EdgeInsets.symmetric(horizontal: HavenSpacing.xs),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                    ),
                  ),
                ),
              ),
            ),
            error: (_, __) => const Text(
              'Could not load stats',
              style: TextStyle(color: HavenColors.expired),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNeedsAttention(AsyncValue<List<Item>> needsAttention) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '⚠️  NEEDS ATTENTION',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: HavenColors.textTertiary,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: HavenSpacing.md),
        needsAttention.when(
          data: (items) {
            if (items.isEmpty) {
              return Container(
                width: double.infinity,
                padding: const EdgeInsets.all(HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                  border: Border.all(color: HavenColors.border),
                ),
                child: const Text(
                  'All clear! No warranties need\nyour attention right now. ✓',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: HavenColors.textSecondary,
                  ),
                ),
              );
            }

            return Column(
              children: [
                ...items.map((item) => _buildAttentionCard(item)),
                if (items.length >= 3) ...[
                  const SizedBox(height: HavenSpacing.sm),
                  GestureDetector(
                    onTap: () => _navigateToItemsWithFilter('expiring'),
                    child: const Text(
                      'View all items →',
                      style: TextStyle(
                        fontSize: 14,
                        color: HavenColors.secondary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            );
          },
          loading: () => Column(
            children: List.generate(
              2,
              (_) => Container(
                width: double.infinity,
                height: 72,
                margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                ),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildAttentionCard(Item item) {
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;
    final isExpired = status == WarrantyStatus.expired;
    final color = isExpired ? HavenColors.expired : HavenColors.expiring;

    String timeText;
    if (isExpired) {
      final absDays = (-days).abs();
      timeText = absDays == 1 ? 'Expired 1 day ago' : 'Expired $absDays days ago';
    } else {
      timeText = days == 1 ? '1 day remaining' : '$days days remaining';
    }

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        context.push('/items/${item.id}');
      },
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
        padding: const EdgeInsets.all(HavenSpacing.md),
        decoration: BoxDecoration(
          color: HavenColors.surface,
          borderRadius: BorderRadius.circular(HavenRadius.button),
          border: Border.all(color: HavenColors.border),
        ),
        child: Row(
          children: [
            // Status dot
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: HavenSpacing.md),
            // Item info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.brand ?? ''} ${item.name}'.trim(),
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: TextStyle(
                      fontSize: 12,
                      color: color,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: HavenColors.textTertiary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTipCard() {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.button),
        border: Border.all(color: HavenColors.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡', style: TextStyle(fontSize: 20)),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'TIP',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: HavenSpacing.xs),
                const Text(
                  'Add receipts to your items so you have proof of purchase ready for claims.',
                  style: TextStyle(
                    fontSize: 13,
                    color: HavenColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {
              setState(() => _tipDismissed = true);
              SharedPreferences.getInstance().then((prefs) => prefs.setBool('tip_dismissed', true));
            },
            child: const Icon(
              Icons.close,
              size: 18,
              color: HavenColors.textTertiary,
            ),
          ),
        ],
      ),
    );
  }

  void _navigateToItemsWithFilter(String filter) {
    context.go(AppRoutes.items, extra: {'filter': filter});
  }
}

/// Maintenance summary card for the dashboard.
class _MaintenanceCard extends ConsumerWidget {
  const _MaintenanceCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(maintenanceDueProvider);

    return dueAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (summary) {
        if (summary.totalDue == 0 && summary.totalOverdue == 0) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            context.push(AppRoutes.maintenance);
          },
          child: Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: BorderRadius.circular(HavenRadius.card),
              border: Border.all(color: HavenColors.border),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (summary.totalOverdue > 0
                            ? HavenColors.expired
                            : HavenColors.expiring)
                        .withOpacity(0.15),
                    borderRadius: BorderRadius.circular(HavenRadius.card),
                  ),
                  child: Icon(
                    Icons.build_outlined,
                    color: summary.totalOverdue > 0
                        ? HavenColors.expired
                        : HavenColors.expiring,
                    size: 22,
                  ),
                ),
                const SizedBox(width: HavenSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Maintenance',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HavenColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.totalOverdue > 0
                            ? '${summary.totalOverdue} overdue, ${summary.totalDue - summary.totalOverdue} upcoming'
                            : '${summary.totalDue} tasks coming up',
                        style: TextStyle(
                          fontSize: 12,
                          color: summary.totalOverdue > 0
                              ? HavenColors.expired
                              : HavenColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: HavenColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shows "HavenKeep" when user has one home, or a dropdown to switch homes.
class _HomeSwitcher extends ConsumerWidget {
  const _HomeSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homesAsync = ref.watch(homesProvider);
    final currentHome = ref.watch(currentHomeProvider);

    final homesList = homesAsync.valueOrNull ?? [];

    // Single home or loading: just show the home name or "HavenKeep"
    if (homesList.length <= 1) {
      return Text(
        currentHome?.name ?? 'HavenKeep',
        style: const TextStyle(fontWeight: FontWeight.bold),
      );
    }

    // Multiple homes: show dropdown
    return PopupMenuButton<String>(
      onSelected: (homeId) {
        HapticFeedback.lightImpact();
        ref.read(selectedHomeIdProvider.notifier).state = homeId;
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: HavenColors.elevated,
      itemBuilder: (context) => homesList.map((home) {
        final isSelected = home.id == currentHome?.id;
        return PopupMenuItem<String>(
          value: home.id,
          child: Row(
            children: [
              Icon(
                Icons.home_outlined,
                size: 18,
                color: isSelected ? HavenColors.primary : HavenColors.textSecondary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  home.name,
                  style: TextStyle(
                    color: isSelected ? HavenColors.primary : HavenColors.textPrimary,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              if (isSelected)
                const Icon(Icons.check, size: 16, color: HavenColors.primary),
            ],
          ),
        );
      }).toList(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              currentHome?.name ?? 'HavenKeep',
              style: const TextStyle(fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.arrow_drop_down, size: 20),
        ],
      ),
    );
  }
}

/// Tappable stat card for the warranty summary.
class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _StatCard({
    required this.count,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onTap?.call();
        },
        child: Container(
          padding: const EdgeInsets.all(HavenSpacing.md),
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.card),
          ),
          child: Column(
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(height: HavenSpacing.xs),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 12,
                  color: HavenColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// User avatar with initials fallback.
class _UserAvatar extends StatelessWidget {
  final User? user;

  const _UserAvatar({this.user});

  @override
  Widget build(BuildContext context) {
    final hasAvatar = user?.avatarUrl != null && user!.avatarUrl!.isNotEmpty;

    return CircleAvatar(
      radius: 20,
      backgroundColor: HavenColors.primary,
      backgroundImage: hasAvatar ? NetworkImage(user!.avatarUrl!) : null,
      onBackgroundImageError: hasAvatar
          ? (error, __) => debugPrint('[Dashboard] Avatar load failed: $error')
          : null,
      child: hasAvatar
          ? null
          : Text(
              _getInitials(user?.fullName),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
    );
  }

  String _getInitials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return parts.first[0].toUpperCase();
  }
}

/// Notification bell with unread badge.
class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount = ref.watch(unreadNotificationCountProvider);

    return IconButton(
      icon: Stack(
        clipBehavior: Clip.none,
        children: [
          const Icon(Icons.notifications_outlined),
          if (unreadCount > 0)
            Positioned(
              right: -4,
              top: -4,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: HavenColors.expired,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(
                  minWidth: 16,
                  minHeight: 16,
                ),
                child: Text(
                  unreadCount > 9 ? '9+' : '$unreadCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      onPressed: () => context.push(AppRoutes.notifications),
    );
  }
}
