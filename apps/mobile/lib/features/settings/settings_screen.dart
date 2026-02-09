import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Profile & Settings screen (Screen 7.1).
///
/// Shows:
/// - User profile card
/// - Home management section
/// - Notification preferences
/// - Archived items
/// - Plan info
/// - About / legal
/// - Sign out
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final home = ref.watch(currentHomeProvider);
    final archivedAsync = ref.watch(archivedItemsProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(HavenSpacing.md),
        children: [
          // Profile card
          user.when(
            data: (u) => GestureDetector(
              onTap: () => context.push(AppRoutes.profile),
              child: Container(
                padding: const EdgeInsets.all(HavenSpacing.md),
                decoration: BoxDecoration(
                  color: HavenColors.elevated,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                ),
                child: Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: HavenColors.primary,
                      child: Text(
                        (u?.fullName ?? '?')[0].toUpperCase(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    const SizedBox(width: HavenSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            u?.fullName ?? 'User',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: HavenColors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            u?.email ?? '',
                            style: const TextStyle(
                              fontSize: 13,
                              color: HavenColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.chevron_right,
                      color: HavenColors.textTertiary,
                    ),
                  ],
                ),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // HOME section
          const SectionHeader(title: 'HOME'),
          const SizedBox(height: HavenSpacing.sm),

          if (home != null)
            _SettingsTile(
              icon: Icons.home_outlined,
              title: home.name,
              subtitle: home.fullAddress.isNotEmpty
                  ? home.fullAddress
                  : home.homeType.displayLabel,
              onTap: () => context.push('/settings/home/${home.id}'),
            ),

          const SizedBox(height: HavenSpacing.lg),

          // NOTIFICATIONS section
          const SectionHeader(title: 'NOTIFICATIONS'),
          const SizedBox(height: HavenSpacing.sm),

          _SettingsTile(
            icon: Icons.notifications_outlined,
            title: 'Notification Preferences',
            subtitle: 'Reminders, alerts & delivery',
            onTap: () => context.push(AppRoutes.notificationPreferences),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // ITEMS section
          const SectionHeader(title: 'ITEMS'),
          const SizedBox(height: HavenSpacing.sm),

          _SettingsTile(
            icon: Icons.archive_outlined,
            title: 'Archived Items',
            subtitle: archivedAsync.whenOrNull(
                  data: (items) =>
                      '${items.length} ${items.length == 1 ? 'item' : 'items'}',
                ) ??
                'Loading...',
            onTap: () => context.push(AppRoutes.archivedItems),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // PLAN section
          const SectionHeader(title: 'PLAN'),
          const SizedBox(height: HavenSpacing.sm),

          user.when(
            data: (u) {
              final isPremium = u?.plan == UserPlan.premium;
              final itemCount = itemCountAsync.value ?? 0;
              return _SettingsTile(
                icon: isPremium ? Icons.star : Icons.star_outline,
                title: '${isPremium ? 'Premium' : 'Free'} Plan',
                subtitle: isPremium
                    ? 'Unlimited items'
                    : '$itemCount/$kFreePlanItemLimit items used',
                trailing: isPremium
                    ? null
                    : Opacity(
                        opacity: 0.5,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: HavenSpacing.sm,
                            vertical: HavenSpacing.xs,
                          ),
                          decoration: BoxDecoration(
                            color: HavenColors.primary.withOpacity(0.2),
                            borderRadius:
                                BorderRadius.circular(HavenRadius.chip),
                          ),
                          child: const Text(
                            'Coming soon',
                            style: TextStyle(
                              fontSize: 10,
                              color: HavenColors.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                onTap: null, // Phase 3
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // ABOUT section
          const SectionHeader(title: 'ABOUT'),
          const SizedBox(height: HavenSpacing.sm),

          _SettingsTile(
            icon: Icons.info_outline,
            title: 'About HavenKeep',
            onTap: () {
              showDialog(
                context: context,
                builder: (_) => AlertDialog(
                  backgroundColor: HavenColors.elevated,
                  title: const Text(
                    'HavenKeep',
                    style: TextStyle(color: HavenColors.textPrimary),
                  ),
                  content: const Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version 1.0.0',
                        style: TextStyle(color: HavenColors.textSecondary),
                      ),
                      SizedBox(height: HavenSpacing.sm),
                      Text(
                        'Your home warranty tracker.\nNever miss a warranty claim again.',
                        style: TextStyle(
                          color: HavenColors.textTertiary,
                          height: 1.4,
                        ),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Close'),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.privacy_tip_outlined,
            title: 'Privacy Policy',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening Privacy Policy...')),
              );
              // TODO: url_launcher to privacy policy URL
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Opening Terms of Service...')),
              );
              // TODO: url_launcher to terms URL
            },
          ),

          const SizedBox(height: HavenSpacing.xl),

          // Sign Out
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: HavenColors.surface,
                foregroundColor: HavenColors.expired,
              ),
              onPressed: () async {
                await ref.read(currentUserProvider.notifier).signOut();
              },
              child: const Text('Sign Out'),
            ),
          ),

          const SizedBox(height: HavenSpacing.xxl),
        ],
      ),
    );
  }
}

/// A reusable settings list tile.
class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(HavenSpacing.md),
        decoration: BoxDecoration(
          color: HavenColors.surface,
          borderRadius: BorderRadius.circular(HavenRadius.card),
          border: Border.all(color: HavenColors.border),
        ),
        child: Row(
          children: [
            Icon(icon, color: HavenColors.textSecondary, size: 22),
            const SizedBox(width: HavenSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing!,
            if (onTap != null && trailing == null)
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
}
