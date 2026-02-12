import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../providers/connectivity_provider.dart';
import '../services/offline_sync_service.dart';

/// A banner that shows offline status and sync progress.
///
/// Displays at the top of the screen when:
/// - Device is offline (red banner)
/// - Offline changes are being synced (blue banner)
class ConnectivityBanner extends ConsumerWidget {
  const ConnectivityBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(isOnlineProvider);
    final isSyncing = ref.watch(isSyncingProvider);
    final pendingCount = ref.watch(offlineQueueCountProvider);

    if (isOnline && !isSyncing && (pendingCount.value ?? 0) == 0) {
      return const SizedBox.shrink();
    }

    if (!isOnline) {
      return _Banner(
        icon: Icons.cloud_off_outlined,
        message: 'You\'re offline. Changes will sync when back online.',
        color: HavenColors.expiring,
        trailing: pendingCount.whenOrNull(
          data: (count) => count > 0
              ? Text(
                  '$count pending',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: HavenColors.expiring,
                  ),
                )
              : null,
        ),
      );
    }

    if (isSyncing) {
      final count = pendingCount.value ?? 0;
      return _Banner(
        icon: Icons.sync,
        message: count > 0
            ? 'Syncing $count ${count == 1 ? 'change' : 'changes'}...'
            : 'Syncing...',
        color: HavenColors.primary,
        showSpinner: true,
      );
    }

    return const SizedBox.shrink();
  }
}

class _Banner extends StatelessWidget {
  final IconData icon;
  final String message;
  final Color color;
  final Widget? trailing;
  final bool showSpinner;

  const _Banner({
    required this.icon,
    required this.message,
    required this.color,
    this.trailing,
    this.showSpinner = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: HavenSpacing.md,
        vertical: HavenSpacing.sm,
      ),
      color: color.withOpacity(0.15),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            if (showSpinner)
              SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: color,
                ),
              )
            else
              Icon(icon, size: 16, color: color),
            const SizedBox(width: HavenSpacing.sm),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}
