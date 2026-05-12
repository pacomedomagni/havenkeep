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
import '../../core/providers/warranty_claims_provider.dart' show savingsFeedProvider;
import '../../core/router/router.dart';
import '../../core/widgets/value_dashboard_card.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_image.dart';
import '../../core/widgets/responsive_box.dart';
import '../premium/premium_teaser_card.dart';
import 'milestone_banner.dart';
import 'recent_activity_card.dart';
import '../../core/utils/haven_haptics.dart';
import '../../core/utils/money_formatter.dart';
import '../settings/settings_screen.dart' show failedSyncCountProvider;

/// Home dashboard — the main screen (Screen 3.1).
///
/// Top of the screen answers "what's the state of things, and what needs me"
/// — the value hero (which now carries the active/expiring/expired
/// breakdown so there's no duplicate stats card) followed by Needs
/// Attention. Everything below the fold is supporting context.
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

  void _navigateToItemsWithFilter(String filter) {
    context.go(AppRoutes.items, extra: {'filter': filter});
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(warrantyStatsProvider);
    final needsAttention = ref.watch(needsAttentionProvider);
    final items = ref.watch(itemsProvider);
    final firstName = user.value?.fullName.split(' ').first ?? 'there';

    final hasItems = items.valueOrNull?.isNotEmpty ?? false;

    return Scaffold(
      backgroundColor: HavenColors.canvas,
      appBar: AppBar(
        titleSpacing: HavenSpacing.md,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SvgPicture.asset('assets/images/logo-icon.svg',
                width: 26, height: 26),
            const SizedBox(width: HavenSpacing.sm),
            const _HomeSwitcher(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.search),
            tooltip: 'Search warranties',
            onPressed: () => context.push(AppRoutes.search),
          ),
          _NotificationBell(),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
          const SizedBox(width: HavenSpacing.xs),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(itemsProvider);
          // Await the new future so the spinner stays visible until data
          // is actually loaded; otherwise RefreshIndicator resolves
          // immediately.
          await ref.read(itemsProvider.future);
        },
        color: HavenColors.primary,
        backgroundColor: HavenColors.surfaceHigh,
        child: ResponsiveBox(
          maxWidth: 720,
          child: ListView(
            // Generous bottom inset — the body extends under the floating
            // nav bar + docked FAB (extendBody), so content needs to clear
            // ~96px before the safe-area inset adds its own.
            padding: EdgeInsets.fromLTRB(
              HavenSpacing.md,
              HavenSpacing.sm,
              HavenSpacing.md,
              HavenSpacing.xxl + HavenSpacing.lg +
                  MediaQuery.paddingOf(context).bottom,
            ),
            children: [
              // Greeting with avatar.
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

              if (!hasItems && items.hasValue)
                _buildEmptyState(context)
              else ...[
                // ---- Hero: value + warranty health + status breakdown ---
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
                      expiringWarranties: expiring,
                      expiredWarranties: expired,
                      onTap: () => context.push(AppRoutes.items),
                      onStatusTap: _navigateToItemsWithFilter,
                    );
                  },
                  loading: () => const _HeroSkeleton(),
                  error: (_, __) => HavenCard(
                    child: Center(
                      child: TextButton.icon(
                        onPressed: () => ref.invalidate(itemsProvider),
                        icon: const Icon(Icons.refresh, size: 16),
                        label: const Text('Retry'),
                      ),
                    ),
                  ),
                ),
                // Hero gets the most air beneath it — it's the anchor.
                const SizedBox(height: HavenSpacing.xl),

                // 3.14: failed-offline-sync banner (auto-hides at count=0).
                const _FailedSyncBanner(),

                // Maturity milestone banner (auto-hides when none applies).
                const MilestoneBanner(),

                // ---- Needs attention -----------------------------------
                _buildNeedsAttention(needsAttention),

                // ---- Maintenance (auto-hides when nothing due) ----------
                const _MaintenanceCard(),

                // ---- Recent activity -----------------------------------
                const SizedBox(height: HavenSpacing.xl),
                const RecentActivityCard(),

                // ---- Premium teaser ------------------------------------
                const SizedBox(height: HavenSpacing.xl),
                const PremiumTeaserCard(),

                // ---- Tip (subtle one-liner) ---------------------------
                if (!_tipDismissed) ...[
                  const SizedBox(height: HavenSpacing.md),
                  _buildTipCard(),
                ],

                // ---- Community savings (auto-hides when empty) ---------
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
            const Text(
              'Add your first warranty to start protecting your purchases.',
              textAlign: TextAlign.center,
              style: HavenText.bodySecondary,
            ),
            const SizedBox(height: HavenSpacing.lg),
            SizedBox(
              width: 240,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.addItem),
                icon: const Icon(Icons.add),
                label: const Text('Add Your First Warranty'),
              ),
            ),
            const SizedBox(height: HavenSpacing.xs),
            TextButton(
              onPressed: () => context.go(AppRoutes.homeSetup),
              child: const Text('Just moved in? Set up your home'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNeedsAttention(AsyncValue<List<Item>> needsAttention) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionLabel(
          icon: Icons.priority_high_rounded,
          text: 'NEEDS ATTENTION',
        ),
        const SizedBox(height: HavenSpacing.sm + 2),
        needsAttention.when(
          data: (attentionItems) {
            if (attentionItems.isEmpty) {
              return HavenCard(
                width: double.infinity,
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(HavenSpacing.xs + 2),
                      decoration: BoxDecoration(
                        color: HavenColors.active.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(HavenRadius.button),
                      ),
                      child: const Icon(Icons.check_circle_outline,
                          size: 18, color: HavenColors.active),
                    ),
                    const SizedBox(width: HavenSpacing.sm + 2),
                    const Expanded(
                      child: Text(
                        'All clear — no warranties need your attention right now.',
                        style: HavenText.bodySecondary,
                      ),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                for (final item in attentionItems) ...[
                  _AttentionCard(item: item),
                  const SizedBox(height: HavenSpacing.sm),
                ],
                if (attentionItems.length >= 3)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: () => _navigateToItemsWithFilter('expiring'),
                      child: const Text('View all warranties'),
                    ),
                  ),
              ],
            );
          },
          loading: () => Column(
            children: List.generate(
              2,
              (_) => const Padding(
                padding: EdgeInsets.only(bottom: HavenSpacing.sm),
                child: SkeletonCard(),
              ),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
        ),
      ],
    );
  }

  /// A subtle one-line hint, not a full card — sits quietly above the
  /// premium teaser. Dismissible.
  Widget _buildTipCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.xs),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline,
              size: 14, color: HavenColors.textTertiary),
          const SizedBox(width: HavenSpacing.sm),
          const Expanded(
            child: Text(
              'Tip — add receipts to your warranties so you have proof of purchase ready for claims.',
              style: HavenText.caption,
            ),
          ),
          GestureDetector(
            onTap: _dismissTip,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(HavenSpacing.xs),
              child: Icon(Icons.close, size: 14, color: HavenColors.textTertiary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section label — small-caps overline with a leading icon, used for the
// dashboard's grouped sections.
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SectionLabel({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: HavenColors.textTertiary),
        const SizedBox(width: HavenSpacing.xs + 2),
        Text(text, style: HavenText.overline),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Hero skeleton — placeholder while the value card's data resolves.
// ---------------------------------------------------------------------------

class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 196,
      decoration: BoxDecoration(
        gradient: HavenGradients.brandSoft,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        boxShadow: HavenElevation.glow(HavenColors.primary, strength: 0.6),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Needs-attention row.
// ---------------------------------------------------------------------------

class _AttentionCard extends StatelessWidget {
  final Item item;
  const _AttentionCard({required this.item});

  @override
  Widget build(BuildContext context) {
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;
    final isExpired = status == WarrantyStatus.expired;
    final color = isExpired ? HavenColors.expired : HavenColors.expiring;

    final String timeText;
    if (isExpired) {
      final absDays = (-days).abs();
      timeText = absDays == 1 ? 'Expired 1 day ago' : 'Expired $absDays days ago';
    } else {
      timeText = days == 1 ? '1 day left' : '$days days left';
    }
    final displayName = '${item.brand ?? ''} ${item.name}'.trim();

    // Left accent stripe in the status color, then the category chip, then
    // the text. The stripe is the hierarchy cue — the eye reads "warning"
    // before it reads anything else.
    return HavenCard(
      radius: HavenRadius.button,
      width: double.infinity,
      padding: EdgeInsets.zero,
      semanticLabel: '$displayName, $timeText',
      onTap: () {
        HavenHaptics.tap();
        context.push('/items/${item.id}');
      },
      child: IntrinsicHeight(
        child: Row(
          children: [
            Container(width: 3, color: color),
            const SizedBox(width: HavenSpacing.md - 3),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm + 2),
              child: CategoryIcon.widget(item.category, size: 18),
            ),
            const SizedBox(width: HavenSpacing.sm + 2),
            Expanded(
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(vertical: HavenSpacing.sm + 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      displayName,
                      style:
                          HavenText.body.copyWith(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(
                          isExpired
                              ? Icons.error_outline
                              : Icons.schedule_outlined,
                          size: 12,
                          color: color,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          timeText,
                          style: HavenText.caption.copyWith(
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.only(right: HavenSpacing.md),
              child: Icon(Icons.chevron_right,
                  color: HavenColors.textTertiary, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Maintenance summary card.
// ---------------------------------------------------------------------------

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
        final hasOverdue = summary.totalOverdue > 0;
        final accent = hasOverdue ? HavenColors.expired : HavenColors.expiring;

        return Padding(
          padding: const EdgeInsets.only(top: HavenSpacing.lg),
          child: HavenCard(
            width: double.infinity,
            // Overdue gets a tinted border + glow so it visibly reads as
            // "this needs you now" — upcoming-only stays a plain card.
            borderColor:
                hasOverdue ? HavenColors.expired.withValues(alpha: 0.45) : null,
            glow: hasOverdue ? HavenColors.expired : null,
            semanticLabel: hasOverdue
                ? '${summary.totalOverdue} maintenance tasks overdue'
                : '${summary.totalDue} maintenance tasks coming up',
            onTap: () {
              HavenHaptics.tap();
              context.push(AppRoutes.maintenance);
            },
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.sm + 2),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(HavenRadius.button),
                    border: Border.all(color: accent.withValues(alpha: 0.18)),
                  ),
                  child: Icon(
                    hasOverdue ? Icons.warning_amber_rounded : Icons.build_outlined,
                    color: accent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: HavenSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasOverdue ? 'Maintenance overdue' : 'Maintenance',
                        style: HavenText.titleMedium.copyWith(
                          color:
                              hasOverdue ? HavenColors.expired : null,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasOverdue
                            ? '${summary.totalOverdue} ${summary.totalOverdue == 1 ? "task is" : "tasks are"} past due'
                                '${summary.totalDue - summary.totalOverdue > 0 ? ' · ${summary.totalDue - summary.totalOverdue} upcoming' : ''}'
                            : '${summary.totalDue} ${summary.totalDue == 1 ? "task" : "tasks"} coming up',
                        style: HavenText.caption,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right,
                    color: HavenColors.textTertiary, size: 20),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Community-savings feed — hides itself entirely when there's no data
// (matching the maintenance card's "no row" behaviour).
// ---------------------------------------------------------------------------

class _CommunitySavingsCard extends ConsumerWidget {
  const _CommunitySavingsCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final feedAsync = ref.watch(savingsFeedProvider);
    final feed = feedAsync.valueOrNull;
    // Nothing to show (loading, error, or empty) → render nothing. The
    // dashboard shouldn't carry a "no data yet" placeholder.
    if (feed == null || feed.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(top: HavenSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(
            icon: Icons.emoji_events_outlined,
            text: 'COMMUNITY SAVINGS',
          ),
          const SizedBox(height: HavenSpacing.sm + 2),
          HavenCard(
            width: double.infinity,
            padding: EdgeInsets.zero,
            child: Column(
              children: [
                for (var i = 0; i < feed.take(5).length; i++) ...[
                  if (i > 0)
                    const Divider(
                        height: 1, indent: HavenSpacing.md, endIndent: HavenSpacing.md),
                  _SavingsEntry(
                    itemName: feed[i]['item_name'] as String? ?? 'their item',
                    amount: _parseAmount(feed[i]['amount']),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Single-pass amount parse with explicit fallthrough — the previous
  // double-parse silently rendered "$0" when payload shape drifted (F042).
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
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HavenColors.active.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HavenRadius.pill),
            ),
            child: const Icon(Icons.savings_outlined,
                size: 17, color: HavenColors.active),
          ),
          const SizedBox(width: HavenSpacing.sm + 2),
          Expanded(
            child: Text(
              'A homeowner saved $formatted on their $itemName',
              style: HavenText.meta,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Home switcher in the app bar.
// ---------------------------------------------------------------------------

class _HomeSwitcher extends ConsumerWidget {
  const _HomeSwitcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final homesAsync = ref.watch(homesProvider);
    final currentHome = ref.watch(currentHomeProvider);
    final homesList = homesAsync.valueOrNull ?? [];

    if (homesList.length <= 1) {
      // Flexible + ellipsis — a long home name must not overflow the
      // AppBar Row (which is mainAxisSize.min next to the logo).
      return Flexible(
        child: Text(
          currentHome?.name ?? 'HavenKeep',
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
            color: HavenColors.textPrimary,
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      onSelected: (homeId) {
        HavenHaptics.tap();
        ref.read(selectedHomeIdProvider.notifier).state = homeId;
      },
      offset: const Offset(0, 40),
      itemBuilder: (context) => homesList.map((home) {
        final isSelected = home.id == currentHome?.id;
        return PopupMenuItem<String>(
          value: home.id,
          child: Row(
            children: [
              Icon(Icons.home_outlined,
                  size: 18,
                  color: isSelected
                      ? HavenColors.primary
                      : HavenColors.textSecondary),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: Text(
                  home.name,
                  style: TextStyle(
                    color: isSelected
                        ? HavenColors.primary
                        : HavenColors.textPrimary,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w400,
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
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
                color: HavenColors.textPrimary,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 2),
          const Icon(Icons.arrow_drop_down,
              size: 20, color: HavenColors.textSecondary),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// User avatar.
// ---------------------------------------------------------------------------

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

// ---------------------------------------------------------------------------
// Notification bell with unread badge.
// ---------------------------------------------------------------------------

class _NotificationBell extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unreadCount =
        ref.watch(unreadNotificationCountProvider).valueOrNull ?? 0;

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
                decoration: BoxDecoration(
                  color: HavenColors.expired,
                  shape: BoxShape.circle,
                  border: Border.all(color: HavenColors.canvas, width: 1.5),
                ),
                constraints:
                    const BoxConstraints(minWidth: 16, minHeight: 16),
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

// ---------------------------------------------------------------------------
// 3.14: failed-offline-sync banner. Tap → settings → conflicts screen.
// ---------------------------------------------------------------------------

class _FailedSyncBanner extends ConsumerWidget {
  const _FailedSyncBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(failedSyncCountProvider).valueOrNull ?? 0;
    if (count == 0) return const SizedBox.shrink();

    final label = count == 1
        ? '1 change failed to sync'
        : '$count changes failed to sync';

    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.lg),
      child: HavenCard(
        width: double.infinity,
        borderColor: HavenColors.expired.withValues(alpha: 0.4),
        semanticLabel: '$label. Tap to review.',
        onTap: () => context.push(AppRoutes.conflicts),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(HavenSpacing.xs + 2),
              decoration: BoxDecoration(
                color: HavenColors.expired.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(HavenRadius.button),
              ),
              child: const Icon(Icons.cloud_off,
                  size: 18, color: HavenColors.expired),
            ),
            const SizedBox(width: HavenSpacing.sm + 2),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: HavenText.body.copyWith(
                      fontWeight: FontWeight.w600,
                      color: HavenColors.expired,
                    ),
                  ),
                  const SizedBox(height: 2),
                  const Text('Tap to review and retry or discard',
                      style: HavenText.caption),
                ],
              ),
            ),
            const Icon(Icons.chevron_right,
                size: 18, color: HavenColors.textTertiary),
          ],
        ),
      ),
    );
  }
}
