import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:uuid/uuid.dart';

import '../../core/providers/items_provider.dart';
import '../../core/providers/maintenance_customization_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/services/maintenance_customization_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/haven_haptics.dart';
import '../../core/widgets/haven_loader.dart';

/// Per-item maintenance customization screen. Lets the user override task
/// frequency, opt out of catalog defaults, and add their own recurring tasks.
class CustomizeScheduleScreen extends ConsumerWidget {
  final String itemId;

  const CustomizeScheduleScreen({required this.itemId, super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final itemAsync = ref.watch(itemDetailProvider(itemId));

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Customize Schedule')),
      body: itemAsync.when(
        loading: () => const Center(child: HavenLoader()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(HavenSpacing.lg),
            child: Text(
              ErrorHandler.getUserMessage(e),
              textAlign: TextAlign.center,
              style: const TextStyle(color: HavenColors.textSecondary),
            ),
          ),
        ),
        data: (item) => _CustomizeBody(item: item),
      ),
    );
  }
}

class _CustomizeBody extends ConsumerWidget {
  final Item item;
  const _CustomizeBody({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schedulesAsync =
        ref.watch(maintenanceSchedulesProvider(item.category.toJson()));
    final customAsync = ref.watch(maintenanceCustomizationProvider(item.id));

    return schedulesAsync.when(
      loading: () => const Center(child: HavenLoader()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.lg),
          child: Text(
            ErrorHandler.getUserMessage(e),
            textAlign: TextAlign.center,
            style: const TextStyle(color: HavenColors.textSecondary),
          ),
        ),
      ),
      data: (schedules) {
        final custom = customAsync.value ??
            MaintenanceCustomization.empty(item.id);
        return ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: [
            _ItemHeader(item: item),
            const SizedBox(height: HavenSpacing.lg),
            const SectionHeader(title: 'CATALOG TASKS'),
            const SizedBox(height: HavenSpacing.sm),
            if (schedules.isEmpty)
              const _EmptyHint(
                text:
                    'No catalog tasks for this category yet. Add a custom task below.',
              )
            else
              ...schedules.map(
                (s) => _ScheduleTile(
                  itemId: item.id,
                  schedule: s,
                  custom: custom,
                ),
              ),
            const SizedBox(height: HavenSpacing.lg),
            const SectionHeader(title: 'CUSTOM TASKS'),
            const SizedBox(height: HavenSpacing.sm),
            if (custom.extraTasks.isEmpty)
              const _EmptyHint(
                text: 'Tap "Add custom task" to track work the catalog misses.',
              )
            else
              ...custom.extraTasks.map(
                (t) => _CustomTaskTile(itemId: item.id, task: t),
              ),
            const SizedBox(height: HavenSpacing.md),
            OutlinedButton.icon(
              onPressed: () => _showAddCustomTaskDialog(context, ref, item.id),
              icon: const Icon(Icons.add),
              label: const Text('Add custom task'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HavenColors.primary,
                side: const BorderSide(color: HavenColors.primary),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
            const SizedBox(height: HavenSpacing.xxl),
          ],
        );
      },
    );
  }

  Future<void> _showAddCustomTaskDialog(
    BuildContext context,
    WidgetRef ref,
    String itemId,
  ) async {
    final nameController = TextEditingController();
    int frequencyMonths = 6;

    final result = await () async {
      try {
        return await showDialog<CustomMaintenanceTask>(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (ctx, setState) => AlertDialog(
            backgroundColor: HavenColors.elevated,
            title: const Text('New custom task'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  style: const TextStyle(color: HavenColors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Task name',
                    hintText: 'e.g. Replace HEPA filter',
                  ),
                ),
                const SizedBox(height: HavenSpacing.md),
                Row(
                  children: [
                    const Text('Every',
                        style: TextStyle(color: HavenColors.textSecondary)),
                    const SizedBox(width: HavenSpacing.sm),
                    Expanded(
                      child: Slider(
                        value: frequencyMonths.toDouble(),
                        min: 1,
                        max: 24,
                        divisions: 23,
                        label: '$frequencyMonths mo',
                        activeColor: HavenColors.primary,
                        onChanged: (v) =>
                            setState(() => frequencyMonths = v.round()),
                      ),
                    ),
                    SizedBox(
                      width: 56,
                      child: Text(
                        '$frequencyMonths mo',
                        style: const TextStyle(color: HavenColors.textPrimary),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;
                  Navigator.of(dialogCtx).pop(
                    CustomMaintenanceTask(
                      id: const Uuid().v4(),
                      name: name,
                      frequencyMonths: frequencyMonths,
                    ),
                  );
                },
                child: const Text('Add'),
              ),
            ],
          ),
        );
      },
    );
      } finally {
        // H60: dispose the dialog-scoped controller on every exit
        // path. The prior shape leaked the controller (and its
        // attached listeners) on cancel because dispose() was never
        // called.
        nameController.dispose();
      }
    }();

    if (result == null) return;
    await ref
        .read(maintenanceCustomizationProvider(itemId).notifier)
        .addExtraTask(result);
    HavenHaptics.confirm();
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Added "${result.name}"')),
      );
    }
  }
}

class _ItemHeader extends StatelessWidget {
  final Item item;
  const _ItemHeader({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.elevated,
        borderRadius: BorderRadius.circular(HavenRadius.card),
      ),
      child: Row(
        children: [
          const Icon(Icons.tune, color: HavenColors.primary),
          const SizedBox(width: HavenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.brand != null ? '${item.brand} ${item.name}' : item.name,
                  style: HavenText.titleMedium,
                ),
                const SizedBox(height: 2),
                const Text(
                  'Override the catalog cadence or add tasks specific to this unit.',
                  style: HavenText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ScheduleTile extends ConsumerWidget {
  final String itemId;
  final MaintenanceSchedule schedule;
  final MaintenanceCustomization custom;

  const _ScheduleTile({
    required this.itemId,
    required this.schedule,
    required this.custom,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disabled = custom.disabledScheduleIds.contains(schedule.id);
    final override = custom.frequencyOverrides[schedule.id];
    final cadence = override ?? schedule.frequencyMonths;

    return Container(
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
              Expanded(
                child: Text(
                  schedule.taskName,
                  style: TextStyle(
                    color: disabled
                        ? HavenColors.textTertiary
                        : HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                    decoration:
                        disabled ? TextDecoration.lineThrough : TextDecoration.none,
                  ),
                ),
              ),
              Switch.adaptive(
                value: !disabled,
                onChanged: (value) async {
                  await ref
                      .read(maintenanceCustomizationProvider(itemId).notifier)
                      .setEnabled(schedule.id, value);
                  HavenHaptics.tap();
                },
                activeThumbColor: HavenColors.primary,
              ),
            ],
          ),
          if (!disabled) ...[
            Row(
              children: [
                const Text('Every',
                    style: TextStyle(color: HavenColors.textSecondary)),
                Expanded(
                  child: Slider(
                    value: cadence
                        .toDouble()
                        .clamp(1, 24)
                        .toDouble(),
                    min: 1,
                    max: 24,
                    divisions: 23,
                    label: '$cadence mo',
                    activeColor: HavenColors.primary,
                    onChanged: (v) {
                      ref
                          .read(maintenanceCustomizationProvider(itemId).notifier)
                          .setFrequencyOverride(schedule.id, v.round());
                    },
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Text(
                    '$cadence mo',
                    style: const TextStyle(color: HavenColors.textPrimary),
                  ),
                ),
              ],
            ),
            if (override != null)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    ref
                        .read(maintenanceCustomizationProvider(itemId).notifier)
                        .setFrequencyOverride(schedule.id, null);
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: HavenColors.textTertiary,
                    minimumSize: const Size(0, 28),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: Text(
                    'Reset to ${schedule.frequencyMonths} mo',
                    style: HavenText.caption,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CustomTaskTile extends ConsumerWidget {
  final String itemId;
  final CustomMaintenanceTask task;

  const _CustomTaskTile({required this.itemId, required this.task});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.sm),
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Row(
        children: [
          const Icon(Icons.build_outlined,
              size: 18, color: HavenColors.primary),
          const SizedBox(width: HavenSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  task.name,
                  style: const TextStyle(
                    color: HavenColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  'Every ${task.frequencyMonths} mo',
                  style: const TextStyle(
                    color: HavenColors.textTertiary,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove',
            icon: const Icon(Icons.close, color: HavenColors.textTertiary),
            onPressed: () {
              ref
                  .read(maintenanceCustomizationProvider(itemId).notifier)
                  .removeExtraTask(task.id);
            },
          ),
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  final String text;
  const _EmptyHint({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.card),
        border: Border.all(color: HavenColors.border),
      ),
      child: Text(
        text,
        style: const TextStyle(color: HavenColors.textSecondary, fontSize: 13),
      ),
    );
  }
}
