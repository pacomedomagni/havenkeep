import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/maintenance_provider.dart';
import '../../core/utils/error_handler.dart';

/// Paginated maintenance history list with delete.
class MaintenanceHistoryScreen extends ConsumerWidget {
  const MaintenanceHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyAsync = ref.watch(maintenanceHistoryProvider);
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Maintenance History')),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(ErrorHandler.getUserMessage(e),
                  style: const TextStyle(color: HavenColors.textSecondary)),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => ref.invalidate(maintenanceHistoryProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
        data: (history) {
          if (history.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(HavenSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.history, size: 64, color: HavenColors.textTertiary),
                    SizedBox(height: HavenSpacing.md),
                    Text(
                      'No maintenance history',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textPrimary,
                      ),
                    ),
                    SizedBox(height: HavenSpacing.sm),
                    Text(
                      'Completed maintenance tasks\nwill appear here.',
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
            onRefresh: () async => ref.invalidate(maintenanceHistoryProvider),
            color: HavenColors.primary,
            child: ListView.builder(
              padding: const EdgeInsets.all(HavenSpacing.md),
              itemCount: history.length,
              itemBuilder: (context, index) {
                final entry = history[index];
                final itemLabel = entry.itemBrand != null
                    ? '${entry.itemBrand} ${entry.itemName ?? ''}'.trim()
                    : entry.itemName ?? 'Item';

                return Dismissible(
                  key: Key(entry.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: HavenSpacing.lg),
                    margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
                    decoration: BoxDecoration(
                      color: HavenColors.expired,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                    ),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                  confirmDismiss: (_) async {
                    final confirmed = await showHavenConfirmDialog(
                      context,
                      title: 'Delete Log?',
                      body: 'This action cannot be undone.',
                      confirmLabel: 'Delete',
                      isDestructive: true,
                    );
                    if (confirmed != true) return false;
                    try {
                      await ref.read(maintenanceRepositoryProvider).deleteLog(entry.id);
                      ref.invalidate(maintenanceHistoryProvider);
                      ref.invalidate(maintenanceDueProvider);
                      return true;
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
                        );
                      }
                      return false;
                    }
                  },
                  onDismissed: (_) {},
                  child: Container(
                    margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
                    padding: const EdgeInsets.all(HavenSpacing.md),
                    decoration: BoxDecoration(
                      color: HavenColors.surface,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      border: Border.all(color: HavenColors.border),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.check_circle_outline,
                                size: 18, color: HavenColors.active),
                            const SizedBox(width: HavenSpacing.sm),
                            Expanded(
                              child: Text(
                                entry.taskName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: HavenColors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: HavenSpacing.xs),
                        Row(
                          children: [
                            Text(
                              itemLabel,
                              style: const TextStyle(
                                fontSize: 13,
                                color: HavenColors.textSecondary,
                              ),
                            ),
                            const Spacer(),
                            Text(
                              dateFormat.format(entry.completedDate),
                              style: const TextStyle(
                                fontSize: 12,
                                color: HavenColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        if (entry.durationMinutes != null ||
                            entry.cost != null) ...[
                          const SizedBox(height: HavenSpacing.xs),
                          Row(
                            children: [
                              if (entry.durationMinutes != null)
                                Text(
                                  '${entry.durationMinutes} min',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: HavenColors.textTertiary,
                                  ),
                                ),
                              if (entry.durationMinutes != null &&
                                  entry.cost != null)
                                const Text(' · ',
                                    style: TextStyle(
                                        color: HavenColors.textTertiary)),
                              if (entry.cost != null)
                                Text(
                                  '\$${entry.cost!.toStringAsFixed(2)}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: HavenColors.textTertiary,
                                  ),
                                ),
                            ],
                          ),
                        ],
                        if (entry.notes != null &&
                            entry.notes!.isNotEmpty) ...[
                          const SizedBox(height: HavenSpacing.xs),
                          Text(
                            entry.notes!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: HavenColors.textTertiary,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
