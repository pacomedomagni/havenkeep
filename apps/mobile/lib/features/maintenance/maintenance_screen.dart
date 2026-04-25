import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';
import '../../core/utils/haven_haptics.dart';

/// Dashboard showing due/overdue maintenance tasks grouped by item.
class MaintenanceScreen extends ConsumerWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dueAsync = ref.watch(maintenanceDueProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text('Maintenance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'History',
            onPressed: () => context.push(AppRoutes.maintenanceHistory),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(AppRoutes.logMaintenance),
        icon: const Icon(Icons.add),
        label: const Text('Log Task'),
        backgroundColor: HavenColors.primary,
        foregroundColor: HavenColors.textPrimary,
      ),
      body: dueAsync.when(
        loading: () => const Center(child: HavenLoader()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ErrorHandler.getUserMessage(e), style: const TextStyle(color: HavenColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(maintenanceDueProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (summary) {
          if (summary.items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(HavenSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HavenIllustration(
                      kind: HavenIllustrationKind.noMaintenance,
                      size: 180,
                    ),
                    SizedBox(height: HavenSpacing.md),
                    Text('All caught up', style: HavenText.displayMedium),
                    SizedBox(height: HavenSpacing.sm),
                    Text(
                      'Maintenance schedules will appear here\nbased on your warranties.',
                      textAlign: TextAlign.center,
                      style: HavenText.bodySecondary,
                    ),
                  ],
                ),
              ),
            );
          }

          // Virtualized list so users with 200+ items don't build every card.
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(maintenanceDueProvider);
              await ref.read(maintenanceDueProvider.future);
            },
            color: HavenColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.all(HavenSpacing.md),
              itemCount: summary.items.length + 1, // +1 for summary card
              itemBuilder: (context, index) {
                if (index == 0) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: HavenSpacing.lg),
                    child: Container(
                      padding: const EdgeInsets.all(HavenSpacing.md),
                      decoration: BoxDecoration(
                        color: HavenColors.elevated,
                        borderRadius:
                            BorderRadius.circular(HavenRadius.card),
                      ),
                      child: Row(
                        children: [
                          _SummaryChip(
                            count: summary.totalOverdue,
                            label: 'Overdue',
                            color: HavenColors.expired,
                          ),
                          const SizedBox(width: HavenSpacing.md),
                          _SummaryChip(
                            count:
                                summary.totalDue - summary.totalOverdue,
                            label: 'Coming Up',
                            color: HavenColors.expiring,
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final item = summary.items[index - 1];
                return _MaintenanceItemCard(
                  item: item,
                  dateFormat: dateFormat,
                  onMarkDone: (task) async {
                    // Bail out clearly if the user is missing rather than
                    // submitting userId='' to the server (F069).
                    final userId =
                        ref.read(currentUserProvider).value?.id;
                    if (userId == null) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                                'You need to be signed in to log maintenance.'),
                          ),
                        );
                      }
                      return;
                    }

                    final entry = MaintenanceHistory(
                      id: '',
                      userId: userId,
                      itemId: item.itemId,
                      scheduleId: task.scheduleId,
                      taskName: task.taskName,
                      completedDate: DateTime.now(),
                      createdAt: DateTime.now(),
                    );
                    try {
                      await ref
                          .read(maintenanceRepositoryProvider)
                          .logTask(entry);
                      HavenHaptics.confirm();
                      ref.invalidate(maintenanceDueProvider);
                      ref.invalidate(maintenanceHistoryProvider);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content: Text(
                                  '${task.taskName} marked as done')),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                              content:
                                  Text(ErrorHandler.getUserMessage(e))),
                        );
                      }
                    }
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  final int count;
  final String label;
  final Color color;

  const _SummaryChip({
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

class _MaintenanceItemCard extends StatelessWidget {
  final MaintenanceDueItem item;
  final DateFormat dateFormat;
  final void Function(MaintenanceDueTask task) onMarkDone;

  const _MaintenanceItemCard({
    required this.item,
    required this.dateFormat,
    required this.onMarkDone,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item header
          Padding(
            padding: const EdgeInsets.all(HavenSpacing.md),
            child: Row(
              children: [
                const Icon(Icons.inventory_2_outlined,
                    size: 20, color: HavenColors.primary),
                const SizedBox(width: HavenSpacing.sm),
                Expanded(
                  child: Text(
                    item.itemName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: HavenColors.textPrimary,
                    ),
                  ),
                ),
                if (item.overdueCount > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: HavenSpacing.sm,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: HavenColors.expired.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(HavenRadius.chip),
                    ),
                    child: Text(
                      '${item.overdueCount} overdue',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: HavenColors.expired,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: HavenColors.border),

          // Tasks
          ...item.tasks.map((task) {
            final color =
                task.isOverdue ? HavenColors.expired : HavenColors.expiring;
            final dueText = task.isOverdue
                ? '${(-task.daysUntilDue)} days overdue'
                : task.daysUntilDue <= 0
                    ? 'Due today'
                    : 'Due in ${task.daysUntilDue} days';

            return Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: HavenSpacing.md,
                vertical: HavenSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: HavenSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                task.taskName,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: HavenColors.textPrimary,
                                ),
                              ),
                            ),
                            if (task.isRequiredForWarranty)
                              Tooltip(
                                message: 'Required to maintain warranty',
                                child: Container(
                                  margin: const EdgeInsets.only(left: 6),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: HavenColors.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(HavenRadius.micro),
                                  ),
                                  child: const Text(
                                    'WARRANTY',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: HavenColors.primary,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              dueText,
                              style: TextStyle(
                                fontSize: 12,
                                color: color,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (task.frequencyLabel != null) ...[
                              const Text(
                                ' · ',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: HavenColors.textTertiary,
                                ),
                              ),
                              Text(
                                task.frequencyLabel!,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: HavenColors.textTertiary,
                                ),
                              ),
                            ],
                          ],
                        ),
                        if (task.howToUrl != null || task.videoUrl != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Row(
                              children: [
                                if (task.howToUrl != null)
                                  _ResourceLink(
                                    label: 'How-to',
                                    icon: Icons.article_outlined,
                                    url: task.howToUrl!,
                                  ),
                                if (task.howToUrl != null && task.videoUrl != null)
                                  const SizedBox(width: 8),
                                if (task.videoUrl != null)
                                  _ResourceLink(
                                    label: 'Video',
                                    icon: Icons.play_circle_outline,
                                    url: task.videoUrl!,
                                  ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  TextButton(
                    onPressed: () => onMarkDone(task),
                    style: TextButton.styleFrom(
                      foregroundColor: HavenColors.active,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: const Size(0, 32),
                    ),
                    child: const Text('Done', style: TextStyle(fontSize: 13)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: HavenSpacing.xs),
        ],
      ),
    );
  }
}

class _ResourceLink extends StatelessWidget {
  final String label;
  final IconData icon;
  final String url;

  const _ResourceLink({
    required this.label,
    required this.icon,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final messenger = ScaffoldMessenger.of(context);
        final uri = Uri.tryParse(url);
        if (uri != null && await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          // Surface a failure rather than silently no-op'ing (F070).
          messenger.showSnackBar(
            const SnackBar(content: Text('Could not open link.')),
          );
        }
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: HavenColors.primary),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: HavenColors.primary,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}
