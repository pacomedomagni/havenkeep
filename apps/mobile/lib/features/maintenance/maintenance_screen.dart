import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/router/router.dart';

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
        foregroundColor: Colors.white,
      ),
      body: dueAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Error: $e', style: const TextStyle(color: HavenColors.textSecondary)),
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
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(HavenSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.build_outlined,
                        size: 64, color: HavenColors.textTertiary),
                    const SizedBox(height: HavenSpacing.md),
                    const Text(
                      'No maintenance tasks',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    const Text(
                      'Maintenance schedules will appear\nhere based on your items.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(maintenanceDueProvider),
            color: HavenColors.primary,
            child: ListView(
              padding: const EdgeInsets.all(HavenSpacing.md),
              children: [
                // Summary card
                Container(
                  padding: const EdgeInsets.all(HavenSpacing.md),
                  decoration: BoxDecoration(
                    color: HavenColors.elevated,
                    borderRadius: BorderRadius.circular(HavenRadius.card),
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
                        count: summary.totalDue - summary.totalOverdue,
                        label: 'Coming Up',
                        color: HavenColors.expiring,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),

                // Items with tasks
                ...summary.items.map((item) => _MaintenanceItemCard(
                      item: item,
                      dateFormat: dateFormat,
                      onMarkDone: (task) async {
                        final entry = MaintenanceHistory(
                          id: '',
                          userId: ref.read(currentUserProvider).value?.id ?? '',
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
                          HapticFeedback.mediumImpact();
                          ref.invalidate(maintenanceDueProvider);
                          ref.invalidate(maintenanceHistoryProvider);
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                  content:
                                      Text('${task.taskName} marked as done')),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text('Failed: $e')),
                            );
                          }
                        }
                      },
                    )),
              ],
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
                      color: HavenColors.expired.withOpacity(0.15),
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
                        Text(
                          task.taskName,
                          style: const TextStyle(
                            fontSize: 14,
                            color: HavenColors.textPrimary,
                          ),
                        ),
                        Text(
                          dueText,
                          style: TextStyle(
                            fontSize: 12,
                            color: color,
                            fontWeight: FontWeight.w500,
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
