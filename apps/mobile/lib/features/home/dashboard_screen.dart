import 'package:flutter/material.dart';
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
import '../../core/providers/warranty_claims_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/value_dashboard_card.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_image.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/widgets/responsive_box.dart';
import '../premium/premium_teaser_card.dart';
import 'milestone_banner.dart';
import '../../core/utils/haven_haptics.dart';

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
    _loadTipState();
  }

  // Mounted-guarded async — if the screen is disposed before prefs resolve
  // we avoid setState on a defunct State (F038).
  Future<void> _loadTipState() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _tipDismissed = prefs.getBool('tip_dismissed') ?? false;
    });
  }

  // Persist + revert pattern: await the prefs write so a failure rolls
  // the dismiss back rather than leaving UI/state diverged from storage
  // (F039).
  Future<void> _dismissTip() async {
    setState(() => _tipDismissed = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('tip_dismissed', true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _tipDismissed = false);
    }
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
        user.value?.fullName.split(' ').first ?? 'there';

    final hasItems =
        items.valueOrNull?.isNotEmpty ?? false;

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
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search warranties',
            onPressed: () => context.push(AppRoutes.search),
          ),
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
          // Await the new future so the spinner stays visible until data
          // is actually loaded; otherwise RefreshIndicator resolves immediately.
          await ref.read(itemsProvider.future);
        },
        color: HavenColors.primary,
        child: ResponsiveBox(
          maxWidth: 720,
          child: ListView(
            padding: const EdgeInsets.all(HavenSpacing.md),
            children: [
            // Greeting with avatar
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${_getGreeting()}, $firstName',
                    style: HavenText.displayLarge,
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
                    borderRadius: BorderRadius.circular(HavenRadius.chip),
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

              // Maturity milestone banner (auto-hides when none applies)
              const MilestoneBanner(),

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

              // Premium teaser (contextual — appears before the wall)
              const SizedBox(height: HavenSpacing.lg),
              const PremiumTeaserCard(),

              // Community Savings feed
              const SizedBox(height: HavenSpacing.lg),
              const _CommunitySavingsCard(),
            ],
          ],
          ),
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
            const HavenIllustration(
              kind: HavenIllustrationKind.emptyVault,
              size: 180,
            ),
            const SizedBox(height: HavenSpacing.md),
            const Text('Your vault is empty', style: HavenText.displayMedium),
            const SizedBox(height: HavenSpacing.sm),
            Text(
              'Add your first warranty to\nstart protecting your purchases.',
              textAlign: TextAlign.center,
              style: HavenText.bodySecondary.copyWith(height: 1.4),
            ),
            const SizedBox(height: HavenSpacing.lg),
            SizedBox(
              width: 220,
              child: ElevatedButton.icon(
                onPressed: () => context.push(AppRoutes.addItem),
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Warranty'),
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
          Text(
            'YOUR WARRANTIES',
            style: HavenText.badge.copyWith(
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
        Text(
          '⚠️  NEEDS ATTENTION',
          style: HavenText.badge.copyWith(
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
                  style: HavenText.bodySecondary,
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
                    child: Text(
                      'View all warranties →',
                      style: HavenText.body.copyWith(
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
        HavenHaptics.tap();
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
                    style: HavenText.body.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    timeText,
                    style: HavenText.caption.copyWith(
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
                Text(
                  'TIP',
                  style: HavenText.badge.copyWith(
                    color: HavenColors.textTertiary,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: HavenSpacing.xs),
                Text(
                  'Add receipts to your warranties so you have proof of purchase ready for claims.',
                  style: HavenText.meta.copyWith(height: 1.4),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: _dismissTip,
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
            HavenHaptics.tap();
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
                  padding: const EdgeInsets.all(HavenSpacing.sm),
                  decoration: BoxDecoration(
                    color: (summary.totalOverdue > 0
                            ? HavenColors.expired
                            : HavenColors.expiring)
                        .withValues(alpha: 0.15),
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
                      Text(
                        'Maintenance',
                        style: HavenText.body.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        summary.totalOverdue > 0
                            ? '${summary.totalOverdue} overdue, ${summary.totalDue - summary.totalOverdue} upcoming'
                            : '${summary.totalDue} tasks coming up',
                        style: HavenText.caption.copyWith(
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

/// Community savings feed card — shows anonymized savings from other users.
class _CommunitySavingsCard extends ConsumerWidget {
  const _CommunitySavingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(savingsFeedProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section header
        Row(
          children: [
            const Icon(
              Icons.emoji_events_outlined,
              size: 18,
              color: HavenColors.active,
            ),
            const SizedBox(width: HavenSpacing.xs),
            Text(
              'COMMUNITY SAVINGS',
              style: HavenText.badge.copyWith(
                color: HavenColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: HavenSpacing.md),

        // Feed card
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.card),
            border: Border.all(color: HavenColors.border),
          ),
          child: feedAsync.when(
            data: (feed) {
              if (feed.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(HavenSpacing.lg),
                  child: Center(
                    child: Text(
                      'No community savings data yet',
                      style: HavenText.meta,
                    ),
                  ),
                );
              }
              return _buildEntries(feed.take(5).toList());
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(HavenSpacing.lg),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: HavenLoader(),
                ),
              ),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.all(HavenSpacing.lg),
              child: Center(
                child: Text(
                  'Unable to load community savings',
                  style: HavenText.meta,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEntries(List<Map<String, dynamic>> entries) {
    return Column(
      children: [
        for (int i = 0; i < entries.length; i++) ...[
          _SavingsEntry(
            itemName: entries[i]['item_name'] as String? ?? 'their item',
            amount: _parseAmount(entries[i]['amount']),
          ),
          if (i < entries.length - 1)
            const Divider(height: 1, color: HavenColors.border),
        ],
      ],
    );
  }

  // Single-pass amount parse with explicit fallthrough — the previous
  // double-parse (`is num` *and* `tryParse`) silently rendered "$0" when
  // payload shape drifted (F042).
  static double _parseAmount(Object? raw) {
    if (raw is num) return raw.toDouble();
    if (raw is String) {
      final v = double.tryParse(raw);
      if (v != null) return v;
    }
    debugPrint('[CommunitySavings] unexpected amount payload: $raw');
    return 0;
  }
}

/// A single savings feed entry row.
class _SavingsEntry extends StatelessWidget {
  final String itemName;
  final double amount;

  const _SavingsEntry({required this.itemName, required this.amount});

  @override
  Widget build(BuildContext context) {
    final formatted = Money.formatCompact(amount);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: HavenSpacing.md,
        vertical: HavenSpacing.sm + 2,
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: HavenColors.active.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HavenRadius.pill),
            ),
            child: const Icon(
              Icons.attach_money,
              size: 18,
              color: HavenColors.active,
            ),
          ),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Text(
              'A homeowner saved $formatted on their $itemName',
              style: HavenText.meta.copyWith(height: 1.3),
            ),
          ),
        ],
      ),
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
        HavenHaptics.tap();
        ref.read(selectedHomeIdProvider.notifier).state = homeId;
      },
      offset: const Offset(0, 40),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HavenRadius.button),
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
          HavenHaptics.tap();
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
                style: HavenText.stat.copyWith(color: color),
              ),
              const SizedBox(height: HavenSpacing.xs),
              Text(
                label,
                style: HavenText.caption.copyWith(
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
    return HavenAvatar(
      url: user?.avatarUrl,
      radius: 20,
      fallback: Text(
        _getInitials(user?.fullName),
        style: HavenText.body.copyWith(
          color: HavenColors.textPrimary,
          fontWeight: FontWeight.w700,
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
    final unreadCount = ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

    // Surface the badge count to screen readers (F043).
    return IconButton(
      tooltip: unreadCount > 0
          ? '$unreadCount unread notifications'
          : 'Notifications',
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
                    color: HavenColors.textPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
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
