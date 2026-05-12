import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/items_provider.dart';

/// Pulls the current user's signup date and item count to pick a
/// milestone banner, if any. Each banner is only shown once per user.
class _Milestone {
  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  const _Milestone({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
  });
}

/// Computes which, if any, milestone banner to show on the dashboard.
/// Returns null when no milestone applies or every candidate has been
/// dismissed.
final milestoneBannerProvider = FutureProvider<_MilestoneView?>((ref) async {
  final items = ref.watch(itemsProvider).valueOrNull ?? const [];
  final user = ref.watch(currentUserProvider).valueOrNull;
  if (items.isEmpty) return null;

  final prefs = await SharedPreferences.getInstance();
  final seen = prefs.getStringList('milestones_seen') ?? const <String>[];

  final count = items.length;
  final ageDays = user?.createdAt != null
      ? DateTime.now().difference(user!.createdAt).inDays
      : 0;

  // A "value protected" milestone was intentionally dropped — the
  // dashboard hero already shows that figure, so a banner repeating it is
  // pure redundancy. Milestones are about *engagement* moments the hero
  // doesn't surface (item count, tenure).
  final candidates = <_Milestone>[
    if (count >= 25 && count < 100)
      const _Milestone(
        id: 'items_25',
        icon: Icons.verified_outlined,
        title: '25 warranties protected',
        subtitle: "You're building a real safety net.",
      ),
    if (count >= 100)
      const _Milestone(
        id: 'items_100',
        icon: Icons.workspace_premium_outlined,
        title: '100 warranties tracked',
        subtitle: 'Power-user territory.',
      ),
    if (ageDays >= 365)
      const _Milestone(
        id: 'year_1',
        icon: Icons.celebration_outlined,
        title: 'One year with HavenKeep',
        subtitle: 'Thanks for trusting us with your home.',
      ),
  ];

  for (final m in candidates) {
    if (!seen.contains(m.id)) {
      return _MilestoneView(milestone: m);
    }
  }
  return null;
});

class _MilestoneView {
  final _Milestone milestone;
  _MilestoneView({required this.milestone});
}

/// Dismissible maturity-moment banner. Read the provider; render nothing if
/// null; otherwise show a compact card with confetti-adjacent styling.
class MilestoneBanner extends ConsumerWidget {
  const MilestoneBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(milestoneBannerProvider);
    return async.when(
      data: (view) {
        if (view == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(bottom: HavenSpacing.lg),
          child: _MilestoneCard(
            view: view,
            onDismiss: () async {
              final prefs = await SharedPreferences.getInstance();
              // Use Set semantics so a double-tap can't write a duplicated
              // id list (F045).
              final seen = <String>{
                ...?prefs.getStringList('milestones_seen'),
                view.milestone.id,
              };
              await prefs.setStringList('milestones_seen', seen.toList());
              ref.invalidate(milestoneBannerProvider);
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final _MilestoneView view;
  final VoidCallback onDismiss;

  const _MilestoneCard({required this.view, required this.onDismiss});

  @override
  Widget build(BuildContext context) {
    final m = view.milestone;
    return HavenCard(
      width: double.infinity,
      borderColor: HavenColors.gold.withValues(alpha: 0.35),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(HavenSpacing.sm),
            decoration: BoxDecoration(
              color: HavenColors.gold.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(HavenRadius.button),
            ),
            child: Icon(m.icon, color: HavenColors.gold, size: 22),
          ),
          const SizedBox(width: HavenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.title,
                    style: HavenText.titleMedium
                        .copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(m.subtitle, style: HavenText.caption),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close,
                size: 18, color: HavenColors.textTertiary),
            onPressed: onDismiss,
            tooltip: 'Dismiss',
          ),
        ],
      ),
    );
  }
}
