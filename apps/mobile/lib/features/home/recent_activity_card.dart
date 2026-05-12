import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/recent_activity_provider.dart';
import '../../core/services/audit_log_repository.dart';
import '../../core/widgets/haven_loader.dart';

/// "What just happened" feed on the dashboard. Hydrates from the
/// `audit_log` projection — the same rows admin tooling sees, scoped to
/// the current user via `/audit/logs/me`.
///
/// Keeps the surface deliberately small: top 5 events, each one line, with
/// an icon mapped from the action verb. Heavier audit inspection lives in
/// admin tooling — this card is just a "you added X · 2m ago" sanity check.
class RecentActivityCard extends ConsumerWidget {
  const RecentActivityCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(recentActivityProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: 'RECENT ACTIVITY'),
        HavenCard.flat(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: HavenSpacing.md,
            vertical: HavenSpacing.xs,
          ),
          child: async.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Center(child: HavenLoader.small()),
            ),
            error: (_, __) => const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.sm),
              child: Text("Couldn't load recent activity",
                  style: HavenText.caption),
            ),
            data: (events) {
              if (events.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: HavenSpacing.sm),
                  child: Text(
                    'Nothing yet — your first add or claim will show up here.',
                    style: HavenText.caption,
                  ),
                );
              }
              // Bound to 5 — anything more crowds the dashboard. Full
              // history isn't a UX goal here; admin tooling owns that.
              final shown = events.take(5).toList();
              return Column(
                children: [
                  for (var i = 0; i < shown.length; i++) ...[
                    _ActivityRow(event: shown[i]),
                    if (i != shown.length - 1) const Divider(height: 1),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ActivityRow extends StatelessWidget {
  final RecentActivity event;

  const _ActivityRow({required this.event});

  /// Map an audit action verb to an icon. Defaults to a generic event icon
  /// for any action this card hasn't been taught about yet.
  IconData _iconFor(String action) {
    if (action.startsWith('item.')) return Icons.inventory_2_outlined;
    if (action.startsWith('claim.')) return Icons.assignment_outlined;
    if (action.startsWith('document.')) return Icons.attach_file;
    if (action.startsWith('maintenance.')) return Icons.build_outlined;
    if (action.startsWith('warranty.')) return Icons.shield_outlined;
    if (action.startsWith('partner.')) return Icons.handshake_outlined;
    if (action.startsWith('user.')) return Icons.person_outline;
    if (action.startsWith('auth.')) return Icons.login_rounded;
    return Icons.event_note_outlined;
  }

  /// A human label. Prefer the server-provided description; otherwise map
  /// the action verb to friendly copy. The fallback is a Title-Cased,
  /// space-separated render of the verb (e.g. `partner.gift_claimed` →
  /// "Partner gift claimed") so raw `auth.login`-style strings never leak
  /// into the UI.
  String _label() {
    final desc = event.description?.trim();
    if (desc != null && desc.isNotEmpty) return desc;
    final mapped = switch (event.action) {
      'item.created' => 'Added an item',
      'item.updated' => 'Updated an item',
      'item.deleted' => 'Deleted an item',
      'item.archived' => 'Archived an item',
      'item.unarchived' => 'Restored an item',
      'claim.created' => 'Filed a warranty claim',
      'claim.updated' => 'Updated a claim',
      'document.uploaded' => 'Uploaded a document',
      'document.deleted' => 'Removed a document',
      'maintenance.completed' => 'Logged maintenance',
      'auth.login' => 'Signed in',
      'auth.logout' => 'Signed out',
      'auth.register' => 'Created your account',
      'auth.password_change' => 'Changed your password',
      'user.updated' => 'Updated your profile',
      'home.created' => 'Added a home',
      'home.updated' => 'Updated a home',
      _ => null,
    };
    if (mapped != null) return mapped;
    // Generic fall-through: "partner.gift_claimed" → "Partner gift claimed".
    final words = event.action.replaceAll('.', ' ').replaceAll('_', ' ').trim();
    if (words.isEmpty) return 'Activity';
    return words[0].toUpperCase() + words.substring(1);
  }

  String _ago(DateTime ts) {
    final diff = DateTime.now().difference(ts);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 30) return '${diff.inDays}d ago';
    final months = (diff.inDays / 30).floor();
    return '${months}mo ago';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: HavenSpacing.sm + 2),
      child: Row(
        children: [
          Icon(_iconFor(event.action),
              size: 16, color: HavenColors.textSecondary),
          const SizedBox(width: HavenSpacing.sm + 2),
          Expanded(
            child: Text(
              _label(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: HavenText.meta.copyWith(color: HavenColors.textPrimary),
            ),
          ),
          const SizedBox(width: HavenSpacing.sm),
          Text(_ago(event.createdAt), style: HavenText.caption),
        ],
      ),
    );
  }
}
