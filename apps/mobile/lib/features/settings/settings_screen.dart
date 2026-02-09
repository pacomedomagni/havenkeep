import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/router/router.dart';

/// Profile & Settings screen (Screen 7.1).
///
/// Shows:
/// - User profile section (name, email, avatar)
/// - Home management
/// - Notification preferences
/// - App settings (theme, biometric lock)
/// - Plan / upgrade
/// - Sign out
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

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
            data: (u) => Card(
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: HavenColors.primary,
                  child: Text(
                    (u?.fullName ?? '?')[0].toUpperCase(),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text(u?.fullName ?? 'User'),
                subtitle: Text(u?.email ?? ''),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.profile),
              ),
            ),
            loading: () => const SizedBox.shrink(),
            error: (_, __) => const SizedBox.shrink(),
          ),

          const SizedBox(height: HavenSpacing.lg),

          // TODO: Settings sections
          // - Home management
          // - Notification preferences
          // - Archived items
          // - Plan / upgrade
          // - About / legal

          // Sign out
          const SizedBox(height: HavenSpacing.lg),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: HavenColors.surface,
              foregroundColor: HavenColors.expired,
            ),
            onPressed: () async {
              await ref.read(currentUserProvider.notifier).signOut();
            },
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
  }
}
