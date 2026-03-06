import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/database/database.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/homes_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/csv_export_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/services/secure_storage_service.dart';
import '../../main.dart';

/// Reads the app version + build number from the package metadata.
final appVersionProvider = FutureProvider<String>((ref) async {
  final info = await PackageInfo.fromPlatform();
  return '${info.version} (${info.buildNumber})';
});

/// Counts of pending offline sync queue entries.
final pendingSyncCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(localDatabaseProvider);
  return db.pendingCount;
});

/// Counts of failed offline sync queue entries.
final failedSyncCountProvider = FutureProvider<int>((ref) async {
  final db = ref.read(localDatabaseProvider);
  return db.failedCount;
});

/// Failed offline queue entries for display.
final failedSyncItemsProvider = FutureProvider<List<OfflineQueueData>>((ref) async {
  final db = ref.read(localDatabaseProvider);
  return db.getFailedActions();
});

/// Profile & Settings screen (Screen 7.1).
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _biometricsAvailable = false;
  bool _biometricEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadBiometricState();
  }

  Future<void> _loadBiometricState() async {
    final available = await BiometricService.isAvailable();
    final enabled = await SecureStorageService.isBiometricEnabled();
    if (mounted) {
      setState(() {
        _biometricsAvailable = available;
        _biometricEnabled = enabled;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final home = ref.watch(currentHomeProvider);
    final archivedAsync = ref.watch(archivedItemsProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);
    final appVersion = ref.watch(appVersionProvider).valueOrNull ?? '—';
    final config = ref.watch(environmentConfigProvider);

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
                      backgroundImage: u?.avatarUrl != null && u!.avatarUrl!.isNotEmpty
                          ? NetworkImage(u.avatarUrl!)
                          : null,
                      onBackgroundImageError: u?.avatarUrl != null
                          ? (error, __) {
                              debugPrint('Avatar load failed: $error');
                            }
                          : null,
                      child: u?.avatarUrl == null || u!.avatarUrl!.isEmpty
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
                    const SnackBar(content: Text('Export failed. Please try again.')),
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

          // PENDING CHANGES section — offline sync queue status
          _PendingChangesSection(),

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
                          color: HavenColors.primary.withValues(alpha: 0.2),
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

          // Biometric unlock toggle – only visible when the device supports it
          if (_biometricsAvailable)
            Padding(
              padding: const EdgeInsets.only(bottom: HavenSpacing.xs),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: HavenSpacing.md,
                  vertical: HavenSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: HavenColors.surface,
                  borderRadius: BorderRadius.circular(HavenRadius.card),
                  border: Border.all(color: HavenColors.border),
                ),
                child: SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  secondary: const Icon(
                    Icons.fingerprint,
                    color: HavenColors.textSecondary,
                    size: 22,
                  ),
                  title: const Text(
                    'Biometric Unlock',
                    style: TextStyle(
                      fontSize: 15,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                  subtitle: const Text(
                    'Use fingerprint or face to unlock',
                    style: TextStyle(
                      fontSize: 12,
                      color: HavenColors.textTertiary,
                    ),
                  ),
                  value: _biometricEnabled,
                  activeThumbColor: HavenColors.primary,
                  onChanged: (value) async {
                    if (value) {
                      // Require biometric verification before enabling
                      final authenticated =
                          await BiometricService.authenticate();
                      if (!authenticated) return;
                    }
                    await SecureStorageService.setBiometricEnabled(value);
                    if (mounted) {
                      setState(() => _biometricEnabled = value);
                    }
                  },
                ),
              ),
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
              final uri = Uri.parse('${config.appUrl}/help');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.email_outlined,
            title: 'Contact Support',
            subtitle: config.supportEmail,
            onTap: () async {
              final uri = Uri(
                scheme: 'mailto',
                path: config.supportEmail,
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
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version $appVersion',
                        style: const TextStyle(color: HavenColors.textSecondary),
                      ),
                      const SizedBox(height: HavenSpacing.sm),
                      const Text(
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
              final uri = Uri.parse('${config.appUrl}/privacy');
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
              final uri = Uri.parse('${config.appUrl}/terms');
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

/// Displays pending/failed offline sync queue items with a "Retry All" button.
/// Only renders when there are pending or failed items.
class _PendingChangesSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingSyncCountProvider);
    final failedAsync = ref.watch(failedSyncCountProvider);
    final failedItemsAsync = ref.watch(failedSyncItemsProvider);

    final pendingCount = pendingAsync.valueOrNull ?? 0;
    final failedCount = failedAsync.valueOrNull ?? 0;

    // Hide the section entirely when there is nothing to show
    if (pendingCount == 0 && failedCount == 0) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'PENDING CHANGES'),
        const SizedBox(height: HavenSpacing.sm),

        // Summary tile
        Container(
          padding: const EdgeInsets.all(HavenSpacing.md),
          decoration: BoxDecoration(
            color: failedCount > 0
                ? HavenColors.expired.withValues(alpha: 0.08)
                : HavenColors.surface,
            borderRadius: BorderRadius.circular(HavenRadius.card),
            border: Border.all(
              color: failedCount > 0
                  ? HavenColors.expired.withValues(alpha: 0.3)
                  : HavenColors.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                failedCount > 0
                    ? Icons.cloud_off_outlined
                    : Icons.cloud_sync_outlined,
                color: failedCount > 0
                    ? HavenColors.expired
                    : HavenColors.textSecondary,
                size: 22,
              ),
              const SizedBox(width: HavenSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$pendingCount pending, $failedCount failed',
                      style: const TextStyle(
                        fontSize: 15,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failedCount > 0
                          ? 'Some changes could not be synced'
                          : 'Changes waiting to sync',
                      style: const TextStyle(
                        fontSize: 12,
                        color: HavenColors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Failed items list + Retry All button
        if (failedCount > 0) ...[
          const SizedBox(height: HavenSpacing.sm),

          failedItemsAsync.when(
            data: (failedItems) => Column(
              children: [
                ...failedItems.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: HavenSpacing.xs),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: HavenSpacing.md,
                        vertical: HavenSpacing.sm,
                      ),
                      decoration: BoxDecoration(
                        color: HavenColors.surface,
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                        border: Border.all(color: HavenColors.border),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: HavenColors.expired,
                            size: 18,
                          ),
                          const SizedBox(width: HavenSpacing.sm),
                          Expanded(
                            child: Text(
                              '${item.action} ${item.entityType} (${item.attempts} attempts)',
                              style: const TextStyle(
                                fontSize: 13,
                                color: HavenColors.textSecondary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('Retry All'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: HavenColors.primary,
                      side: const BorderSide(color: HavenColors.primary),
                    ),
                    onPressed: () async {
                      final db = ref.read(localDatabaseProvider);
                      await db.retryAllFailedActions();
                      // Trigger a sync pass
                      ref.read(offlineSyncServiceProvider).syncPendingChanges();
                      // Refresh the counts
                      ref.invalidate(pendingSyncCountProvider);
                      ref.invalidate(failedSyncCountProvider);
                      ref.invalidate(failedSyncItemsProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Retrying failed changes...'),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(HavenSpacing.md),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
        ],

        const SizedBox(height: HavenSpacing.lg),
      ],
    );
  }
}
