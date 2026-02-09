import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';

/// Profile editing screen.
///
/// Allows editing: name, avatar, email preferences.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Profile'),
      ),
      body: user.when(
        data: (u) => Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            children: [
              // Avatar
              CircleAvatar(
                radius: 48,
                backgroundColor: HavenColors.primary,
                child: Text(
                  (u?.fullName ?? '?')[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 36,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: HavenSpacing.md),
              Text(
                u?.fullName ?? 'User',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              Text(
                u?.email ?? '',
                style: const TextStyle(color: HavenColors.textSecondary),
              ),
              const SizedBox(height: HavenSpacing.xl),

              // TODO: Edit form fields
              const Center(
                child: Text(
                  'Profile editing coming soon',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Error loading profile')),
      ),
    );
  }
}
