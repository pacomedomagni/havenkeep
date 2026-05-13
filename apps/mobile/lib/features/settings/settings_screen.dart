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
import '../../core/services/app_prefs_service.dart';
import '../../core/services/auto_archive_service.dart';
import '../../core/services/biometric_service.dart';
import '../../core/services/csv_export_service.dart';
import '../../core/services/offline_sync_service.dart';
import '../../core/services/pdf_export_service.dart';
import '../../core/services/secure_storage_service.dart';
import '../../main.dart';
import '../../core/widgets/haven_image.dart';
import '../../core/widgets/haven_loader.dart';

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

  /// CSV / PDF export is a Premium feature (PRODUCT.md §5.1). The data is
  /// the user's own item list, so this gate is UI-only — a free user who
  /// taps export is sent to the upgrade screen instead. Returns true when
  /// the action may proceed.
  bool _requirePremiumOrUpsell(BuildContext context, String feature) {
    final isPremium =
        ref.read(currentUserProvider).valueOrNull?.plan == UserPlan.premium;
    if (isPremium) return true;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature is a Premium feature.')),
    );
    context.push(AppRoutes.premium);
    return false;
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
      backgroundColor: HavenColors.canvas,
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(
          HavenSpacing.md,
          HavenSpacing.md,
          HavenSpacing.md,
          HavenSpacing.xl + MediaQuery.paddingOf(context).bottom,
        ),
        children: [
          // Profile card — the hero of this screen.
          user.when(
            data: (u) => HavenCard.elevated(
              onTap: () => context.push(AppRoutes.profile),
              glow: HavenColors.primary,
              padding: const EdgeInsets.all(HavenSpacing.md + 2),
              semanticLabel:
                  '${u?.fullName ?? "User"}, ${u?.email ?? ""}. Edit profile.',
              child: Row(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: HavenColors.primary.withValues(alpha: 0.4),
                          width: 1.5),
                    ),
                    padding: const EdgeInsets.all(2),
                    child: HavenAvatar(
                      url: u?.avatarUrl,
                      radius: 24,
                      fallback: Text(
                        _getInitials(u?.fullName),
                        style: HavenText.titleLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: HavenSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(u?.fullName ?? 'User', style: HavenText.titleLarge),
                        const SizedBox(height: 2),
                        Text(u?.email ?? '', style: HavenText.meta),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right,
                      color: HavenColors.textTertiary),
                ],
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: HavenSpacing.xl),

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

          // WARRANTIES section
          const SectionHeader(title: 'WARRANTIES'),
          const SizedBox(height: HavenSpacing.sm),

          _SettingsTile(
            icon: Icons.archive_outlined,
            title: 'Archived Warranties',
            subtitle: archivedAsync.whenOrNull(
                  data: (items) =>
                      '${items.length} ${items.length == 1 ? 'warranty' : 'warranties'}',
                ) ??
                'Loading...',
            onTap: () => context.push(AppRoutes.archivedItems),
          ),
          const SizedBox(height: HavenSpacing.xs),
          const _AutoArchiveToggleTile(),
          const SizedBox(height: HavenSpacing.xs),
          _SettingsTile(
            icon: Icons.file_download_outlined,
            title: 'Export Warranties (CSV)',
            subtitle: 'Download all warranties as a spreadsheet',
            onTap: () async {
              if (!_requirePremiumOrUpsell(context, 'CSV export')) return;
              final items = ref.read(itemsProvider).valueOrNull ?? [];
              if (items.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No warranties to export')),
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
            icon: Icons.picture_as_pdf_outlined,
            title: 'Export Warranties (PDF)',
            subtitle: 'Warranty summary you can keep or forward',
            onTap: () async {
              if (!_requirePremiumOrUpsell(context, 'PDF export')) return;
              final items = ref.read(itemsProvider).valueOrNull ?? [];
              if (items.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('No warranties to export')),
                );
                return;
              }
              try {
                final svc = ref.read(pdfExportServiceProvider);
                final bytes = await svc.generateWarrantiesSummaryPdf(items);
                final stamp = DateTime.now().toIso8601String().split('T').first;
                await svc.sharePdf(bytes, 'havenkeep-warranties-$stamp.pdf');
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('PDF export failed. Please try again.')),
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
          const _ConflictsBanner(),
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
                        child: Text(
                          'Upgrade',
                          style: HavenText.badge.copyWith(
                            color: HavenColors.primary,
                            letterSpacing: 0,
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

          // APPEARANCE section
          const SectionHeader(title: 'APPEARANCE'),
          const SizedBox(height: HavenSpacing.sm),
          const _ThemePickerTile(),
          const SizedBox(height: HavenSpacing.xs),
          const _LocalePickerTile(),

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
                    style: HavenText.titleMedium,
                  ),
                  subtitle: const Text(
                    'Use fingerprint or face to unlock',
                    style: HavenText.caption,
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

          const _KeepSignedInTile(),

          const SizedBox(height: HavenSpacing.xs),

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
                builder: (_) => _AboutDialog(version: appVersion),
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
                  body:
                      'Sign out? Local data will be cleared and you will need to sign in again to see your warranties.',
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
    return HavenCard(
      onTap: onTap,
      semanticLabel: subtitle != null ? '$title. $subtitle' : title,
      padding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md, vertical: HavenSpacing.sm + 4),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: HavenColors.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(HavenRadius.pill),
              border: Border.all(
                  color: HavenColors.primary.withValues(alpha: 0.16)),
            ),
            child: Icon(icon, color: HavenColors.primary, size: 18),
          ),
          const SizedBox(width: HavenSpacing.md - 2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: HavenText.titleMedium),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: HavenText.caption),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (onTap != null && trailing == null)
            const Icon(Icons.chevron_right,
                color: HavenColors.textTertiary, size: 20),
        ],
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
                      style: HavenText.titleMedium.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      failedCount > 0
                          ? 'Some changes could not be synced'
                          : 'Changes waiting to sync',
                      style: HavenText.caption,
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
                              style: HavenText.meta,
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
                child: HavenLoader(),
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

/// Switch tile for "Keep me signed in". Off → next cold launch signs out.
class _KeepSignedInTile extends ConsumerWidget {
  const _KeepSignedInTile();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final value = ref.watch(keepSignedInProvider);
    return _SettingsTile(
      icon: Icons.lock_clock_outlined,
      title: 'Keep Me Signed In',
      subtitle: value
          ? 'Stay signed in across launches'
          : 'Sign out automatically on next launch',
      trailing: Switch.adaptive(
        value: value,
        onChanged: (v) => ref.read(keepSignedInProvider.notifier).set(v),
        activeThumbColor: HavenColors.primary,
      ),
    );
  }
}

/// Tile that opens a bottom-sheet picker for the theme mode (light /
/// dark / system). Persisted via [themeModeProvider].
class _ThemePickerTile extends ConsumerWidget {
  const _ThemePickerTile();

  String _label(ThemeMode mode) => switch (mode) {
        ThemeMode.light => 'Light',
        ThemeMode.dark => 'Dark',
        ThemeMode.system => 'System',
      };

  IconData _icon(ThemeMode mode) => switch (mode) {
        ThemeMode.light => Icons.light_mode_outlined,
        ThemeMode.dark => Icons.dark_mode_outlined,
        ThemeMode.system => Icons.brightness_auto_outlined,
      };

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final current = ref.read(themeModeProvider);
    final picked = await HavenSheet.show<ThemeMode>(
      context: context,
      title: 'Theme',
      padded: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: ThemeMode.values.map((mode) {
          return ListTile(
            leading: Icon(_icon(mode), color: HavenColors.textPrimary),
            title: Text(_label(mode), style: HavenText.body),
            trailing: mode == current
                ? const Icon(Icons.check, color: HavenColors.primary)
                : null,
            onTap: () => Navigator.of(context).pop(mode),
          );
        }).toList(),
      ),
    );
    if (picked != null) {
      await ref.read(themeModeProvider.notifier).set(picked);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider);
    return _SettingsTile(
      icon: _icon(mode),
      title: 'Theme',
      subtitle: _label(mode),
      onTap: () => _open(context, ref),
    );
  }
}

/// Tile that opens a bottom-sheet picker for the app locale.
class _LocalePickerTile extends ConsumerWidget {
  const _LocalePickerTile();

  String _label(Locale? locale) {
    if (locale == null) return 'System default';
    return switch (locale.languageCode) {
      'en' => 'English',
      'fr' => 'Français',
      _ => locale.languageCode,
    };
  }

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final current = ref.read(localeProvider);
    final options = <Locale?>[null, ...AppPrefsService.supportedLocales];
    final picked = await HavenSheet.show<_LocaleChoice>(
      context: context,
      title: 'Language',
      padded: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: options.map((locale) {
          final selected =
              (current?.languageCode) == (locale?.languageCode);
          return ListTile(
            leading: const Icon(Icons.language, color: HavenColors.textPrimary),
            title: Text(_label(locale), style: HavenText.body),
            trailing: selected
                ? const Icon(Icons.check, color: HavenColors.primary)
                : null,
            onTap: () =>
                Navigator.of(context).pop(_LocaleChoice(value: locale)),
          );
        }).toList(),
      ),
    );
    if (picked != null) {
      await ref.read(localeProvider.notifier).set(picked.value);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    return _SettingsTile(
      icon: Icons.language,
      title: 'Language',
      subtitle: _label(locale),
      onTap: () => _open(context, ref),
    );
  }
}

/// Wrapper because `null` isn't a valid `showModalBottomSheet` return
/// value when nullable types share a sentinel for "system default".
class _LocaleChoice {
  final Locale? value;
  const _LocaleChoice({required this.value});
}

/// Switch tile for the auto-archive behavior (warranties expired > 90 days).
class _AutoArchiveToggleTile extends StatefulWidget {
  const _AutoArchiveToggleTile();

  @override
  State<_AutoArchiveToggleTile> createState() => _AutoArchiveToggleTileState();
}

class _AutoArchiveToggleTileState extends State<_AutoArchiveToggleTile> {
  bool? _enabled;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final v = await AutoArchiveService.isEnabled();
    if (mounted) setState(() => _enabled = v);
  }

  Future<void> _set(bool value) async {
    setState(() => _enabled = value);
    await AutoArchiveService.setEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsTile(
      icon: Icons.auto_delete_outlined,
      title: 'Auto-Archive Expired',
      subtitle: 'Hide warranties expired more than 90 days',
      trailing: Switch.adaptive(
        value: _enabled ?? true,
        onChanged: _enabled == null ? null : _set,
        activeThumbColor: HavenColors.primary,
      ),
    );
  }
}

/// Banner above the pending-changes section that surfaces parked sync
/// conflicts (C108). Hidden when the count is zero so the settings page
/// stays uncluttered for the happy path.
class _ConflictsBanner extends ConsumerWidget {
  const _ConflictsBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(syncConflictCountProvider);
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: GestureDetector(
        onTap: () => context.push(AppRoutes.conflicts),
        child: Container(
          padding: const EdgeInsets.all(HavenSpacing.md),
          decoration: BoxDecoration(
            color: HavenColors.expiring.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(HavenRadius.card),
            border: Border.all(
              color: HavenColors.expiring.withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: HavenColors.expiring,
                size: 22,
              ),
              const SizedBox(width: HavenSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$count sync ${count == 1 ? 'conflict' : 'conflicts'} need attention',
                      style: HavenText.titleMedium.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Tap to review local vs server changes',
                      style: HavenText.caption,
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
      ),
    );
  }
}

/// About dialog with a hidden 5-tap escape hatch on the version label
/// that opens [DeveloperOptionsScreen] (C201/C202). Lifted into its own
/// widget so the tap counter can live in real state instead of being
/// reset on every parent rebuild.
class _AboutDialog extends StatefulWidget {
  const _AboutDialog({required this.version});

  final String version;

  @override
  State<_AboutDialog> createState() => _AboutDialogState();
}

class _AboutDialogState extends State<_AboutDialog> {
  static const _kTapsToReveal = 5;
  int _versionTaps = 0;

  void _onVersionTap() {
    final next = _versionTaps + 1;
    if (next >= _kTapsToReveal) {
      _versionTaps = 0;
      Navigator.of(context).pop();
      context.push(AppRoutes.developerOptions);
      return;
    }
    setState(() => _versionTaps = next);
  }

  @override
  Widget build(BuildContext context) {
    final tapsLeft = _kTapsToReveal - _versionTaps;
    return AlertDialog(
      backgroundColor: HavenColors.elevated,
      title: const Text(
        'HavenKeep',
        style: TextStyle(color: HavenColors.textPrimary),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onVersionTap,
            child: Text(
              'Version ${widget.version}',
              style: const TextStyle(color: HavenColors.textSecondary),
            ),
          ),
          if (_versionTaps > 0 && _versionTaps < _kTapsToReveal) ...[
            const SizedBox(height: HavenSpacing.xs),
            Text(
              '$tapsLeft more ${tapsLeft == 1 ? 'tap' : 'taps'} to unlock developer options',
              style: const TextStyle(
                color: HavenColors.textTertiary,
                fontSize: 11,
              ),
            ),
          ],
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
    );
  }
}
