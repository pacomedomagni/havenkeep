import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';
import '../../core/providers/auth_provider.dart';
import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Home dashboard — the main screen (Screen 3.1).
///
/// Shows:
/// - Greeting ("Good morning, Pacome")
/// - Warranty summary card (active / expiring / expired counts)
/// - Coverage stat (conditional)
/// - Needs Attention section (max 3 items)
/// - Tip card (contextual, dismissible)
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final stats = ref.watch(warrantyStatsProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('HavenKeep'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Greeting
              user.when(
                data: (u) => Text(
                  'Welcome, ${u?.fullName ?? 'there'}',
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: HavenColors.textPrimary,
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              const SizedBox(height: HavenSpacing.lg),

              // Warranty summary
              stats.when(
                data: (data) => Row(
                  children: [
                    _StatCard(
                      count: data['active'] ?? 0,
                      label: 'Active',
                      color: HavenColors.active,
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    _StatCard(
                      count: data['expiring'] ?? 0,
                      label: 'Expiring',
                      color: HavenColors.expiring,
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    _StatCard(
                      count: data['expired'] ?? 0,
                      label: 'Expired',
                      color: HavenColors.expired,
                    ),
                  ],
                ),
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (_, __) => const Text(
                  'Could not load stats',
                  style: TextStyle(color: HavenColors.expired),
                ),
              ),

              const SizedBox(height: HavenSpacing.lg),

              // TODO: Needs Attention section
              // TODO: Coverage stat
              // TODO: Tip card
              const Center(
                child: Text(
                  'Dashboard content coming soon',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _StatCard({
    required this.count,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
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
    );
  }
}
