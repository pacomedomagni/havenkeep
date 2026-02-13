import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/csv_export_service.dart';

/// Profile & Settings screen (Screen 7.1).
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
                      backgroundImage: u?.avatarUrl != null
                          ? NetworkImage(u!.avatarUrl!)
                          : null,
                      onBackgroundImageError: u?.avatarUrl != null
                          ? (_, __) {}
                          : null,
                      child: u?.avatarUrl == null
                          ? Text(
                              _getInitials(u?.fullName),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            )
                          : null,
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
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.file_download_outlined,
            title: 'Export Items (CSV)',
            subtitle: 'Download all items as a spreadsheet',
            onTap: () async {
              final items = ref.read(itemsProvider).valueOrNull ?? [];
              if (items.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No items to export')),
                );
                return;
              }
              try {
                await ref.read(csvExportServiceProvider).exportItemsToCsv(items);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Export failed: $e')),
                  );
                }
              }
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.mark_email_read_outlined,
            title: 'Email Scanner',
            subtitle: 'Import receipts from Gmail or Outlook',
            onTap: () => context.push(AppRoutes.emailScanner),
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.shield_outlined,
            title: 'Warranty Coverage',
            subtitle: 'Track extended warranties',
            onTap: () => context.push(AppRoutes.warrantyPurchases),
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
                    : Container(
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
                          'Upgrade',
                          style: TextStyle(
                            fontSize: 10,
                            color: HavenColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                onTap: () => context.push('/premium'),
              );
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // SECURITY section
          const SectionHeader(title: 'SECURITY'),
          const SizedBox(height: HavenSpacing.sm),

          // Only show Change Password for email auth users
          user.when(
            data: (u) {
              if (u?.authProvider == AuthProvider.email) {
                return Column(
                  children: [
                    _SettingsTile(
                      icon: Icons.lock_outline,
                      title: 'Change Password',
                      onTap: () => context.push(AppRoutes.changePassword),
                    ),
                    const SizedBox(height: HavenSpacing.xs),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          _SettingsTile(
            icon: Icons.delete_outline,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account and data',
            onTap: () => context.push(AppRoutes.deleteAccount),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // HELP & SUPPORT section
          const SectionHeader(title: 'HELP & SUPPORT'),
          const SizedBox(height: HavenSpacing.sm),

          _SettingsTile(
            icon: Icons.help_outline,
            title: 'Help Center',
            subtitle: 'FAQs and guides',
            onTap: () async {
              final uri = Uri.parse('https://havenkeep.app/help');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.email_outlined,
            title: 'Contact Support',
            subtitle: 'support@havenkeep.app',
            onTap: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: 'support@havenkeep.app',
                queryParameters: {'subject': 'HavenKeep Support Request'},
              );
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            },
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
            onTap: () async {
              final uri = Uri.parse('https://havenkeep.app/privacy');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.description_outlined,
            title: 'Terms of Service',
            onTap: () async {
              final uri = Uri.parse('https://havenkeep.app/terms');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
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
                final confirmed = await showHavenConfirmDialog(
                  context,
                  title: 'Sign out?',
                  body: 'Are you sure you want to sign out?',
                  confirmLabel: 'Sign Out',
                  isDestructive: true,
                );
                if (confirmed && context.mounted) {
                  await ref.read(currentUserProvider.notifier).signOut();
                }
              },
              child: const Text('Sign Out'),
            ),
          ),

          const SizedBox(height: HavenSpacing.xxl),
        ],
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
