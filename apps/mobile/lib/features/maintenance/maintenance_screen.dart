import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers/auth_provider.dart';
import '../../core/providers/maintenance_provider.dart';
import '../../core/providers/maintenance_snooze_provider.dart';
import '../../core/router/router.dart';
import '../../core/services/maintenance_snooze_service.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';

/// Due-window filter for the maintenance dashboard. `all` shows everything
/// the API returned; the day-bounded options trim to tasks whose
/// `daysUntilDue` falls within the window (overdue tasks are always shown
/// — they're never "out of window").
enum _DueWindow { all, sevenDays, thirtyDays, ninetyDays }

extension _DueWindowLabel on _DueWindow {
  String get label => switch (this) {
        _DueWindow.all => 'All',
        _DueWindow.sevenDays => 'Next 7 days',
        _DueWindow.thirtyDays => 'Next 30 days',
        _DueWindow.ninetyDays => 'Next 90 days',
      };

  int? get days => switch (this) {
        _DueWindow.all => null,
        _DueWindow.sevenDays => 7,
        _DueWindow.thirtyDays => 30,
        _DueWindow.ninetyDays => 90,
      };
}

/// Composite key for selection mode — a task is uniquely identified by
/// `itemId|scheduleId`.
String _taskKey(String itemId, String scheduleId) => '$itemId|$scheduleId';

/// Dashboard showing due/overdue maintenance tasks grouped by item.
class MaintenanceScreen extends ConsumerStatefulWidget {
  const MaintenanceScreen({super.key});

  @override
  ConsumerState<MaintenanceScreen> createState() => _MaintenanceScreenState();
}

class _MaintenanceScreenState extends ConsumerState<MaintenanceScreen> {
  _DueWindow _filter = _DueWindow.all;
  bool _selectionMode = false;
  final Set<String> _selected = <String>{};

  void _toggleSelectionMode() {
    setState(() {
      _selectionMode = !_selectionMode;
      if (!_selectionMode) _selected.clear();
    });
  }

  void _toggleSelected(String key) {
    setState(() {
      if (_selected.contains(key)) {
        _selected.remove(key);
      } else {
        _selected.add(key);
      }
    });
  }

  /// Bulk mark-done. Logs each selected task as a `MaintenanceHistory`
  /// entry and invalidates the dependent providers in one pass at the end.
  Future<void> _bulkMarkDone(
      List<MaintenanceDueItem> visibleItems, String userId) async {
    if (_selected.isEmpty) return;
    final repo = ref.read(maintenanceRepositoryProvider);
    final touchedItemIds = <String>{};
    int successCount = 0;
    final failures = <String>[];

    for (final item in visibleItems) {
      for (final task in item.tasks) {
        if (!_selected.contains(_taskKey(item.itemId, task.scheduleId))) {
          continue;
        }
        try {
          await repo.logTask(MaintenanceHistory(
            id: '',
            userId: userId,
            itemId: item.itemId,
            scheduleId: task.scheduleId,
            taskName: task.taskName,
            completedDate: DateTime.now(),
            createdAt: DateTime.now(),
          ));
          touchedItemIds.add(item.itemId);
          successCount++;
        } catch (e) {
          failures.add('${task.taskName}: ${ErrorHandler.getUserMessage(e)}');
        }
      }
    }

    HavenHaptics.confirm();
    ref.invalidate(maintenanceDueProvider);
    ref.invalidate(maintenanceHistoryProvider);
    for (final id in touchedItemIds) {
      ref.invalidate(maintenanceHistoryByItemProvider(id));
    }

    if (!mounted) return;
    setState(() {
      _selectionMode = false;
      _selected.clear();
    });
    final messenger = ScaffoldMessenger.of(context);
    if (failures.isEmpty) {
      messenger.showSnackBar(
        SnackBar(content: Text('Marked $successCount task${successCount == 1 ? '' : 's'} done')),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(content: Text(
            'Marked $successCount done · ${failures.length} failed')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final dueAsync = ref.watch(maintenanceDueProvider);
    final snoozesAsync = ref.watch(activeMaintenanceSnoozesProvider);
    // Snoozes are local-only and load instantly; treat the loading window as
    // "no snoozes" so the list isn't gated on it.
    final snoozes = snoozesAsync.valueOrNull ?? const <String, DateTime>{};
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: Text(_selectionMode
            ? '${_selected.length} selected'
            : 'Maintenance'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _toggleSelectionMode,
              )
            : null,
        actions: [
          if (!_selectionMode) ...[
            IconButton(
              icon: const Icon(Icons.checklist),
              tooltip: 'Select tasks',
              onPressed: _toggleSelectionMode,
            ),
            IconButton(
              icon: const Icon(Icons.history),
              tooltip: 'History',
              onPressed: () => context.push(AppRoutes.maintenanceHistory),
            ),
            IconButton(
              icon: const Icon(Icons.add_rounded, size: 24),
              tooltip: 'Log maintenance',
              onPressed: () => context.push(AppRoutes.logMaintenance),
            ),
          ],
        ],
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
          // Hide snoozed tasks AND apply the due-window filter. Overdue
          // tasks always pass through — they're never "out of window".
          final windowDays = _filter.days;
          final visibleItems = summary.items
              .map((it) {
                final visibleTasks = it.tasks.where((t) {
                  final key = MaintenanceSnoozeService.storageKey(
                      it.itemId, t.scheduleId);
                  if (snoozes.containsKey(key)) return false;
                  if (windowDays == null) return true;
                  if (t.isOverdue) return true;
                  return t.daysUntilDue <= windowDays;
                }).toList();
                if (visibleTasks.length == it.tasks.length) return it;
                return MaintenanceDueItem(
                  itemId: it.itemId,
                  itemName: it.itemName,
                  category: it.category,
                  dueCount: visibleTasks.length,
                  overdueCount: visibleTasks.where((t) => t.isOverdue).length,
                  tasks: visibleTasks,
                );
              })
              .where((it) => it.tasks.isNotEmpty)
              .toList();

          // Drop selected keys that no longer correspond to a visible task
          // (e.g. user changed the filter). Without this the bottom bar
          // count drifts above what the user can actually see.
          if (_selectionMode) {
            final visibleKeys = <String>{
              for (final it in visibleItems)
                for (final t in it.tasks) _taskKey(it.itemId, t.scheduleId),
            };
            _selected.retainWhere(visibleKeys.contains);
          }

          if (visibleItems.isEmpty) {
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

          // Recompute totals against the post-snooze list so the summary
          // card matches what the user actually sees below.
          final totalVisible =
              visibleItems.fold<int>(0, (s, it) => s + it.tasks.length);
          final totalOverdueVisible = visibleItems.fold<int>(
              0, (s, it) => s + it.tasks.where((t) => t.isOverdue).length);

          // Virtualized list so users with 200+ items don't build every card.
          // Indexes:  0 = filter chips,  1 = summary card,  2..N = items.
          return Stack(
            children: [
              RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(maintenanceDueProvider);
                  await ref.read(maintenanceDueProvider.future);
                },
                color: HavenColors.primary,
                child: ListView.builder(
                  padding: EdgeInsets.fromLTRB(
                    HavenSpacing.md,
                    HavenSpacing.md,
                    HavenSpacing.md,
                    // Leave room for the bulk-action bar so the last card
                    // isn't covered when selection mode is active.
                    _selectionMode && _selected.isNotEmpty
                        ? 96
                        : HavenSpacing.md,
                  ),
                  itemCount: visibleItems.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: HavenSpacing.md),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              for (final w in _DueWindow.values) ...[
                                FilterChip(
                                  label: Text(w.label),
                                  selected: _filter == w,
                                  onSelected: (_) =>
                                      setState(() => _filter = w),
                                  backgroundColor: HavenColors.surface,
                                  selectedColor: HavenColors.primary
                                      .withValues(alpha: 0.2),
                                  side: BorderSide(
                                    color: _filter == w
                                        ? HavenColors.primary
                                        : HavenColors.border,
                                  ),
                                  labelStyle: TextStyle(
                                    color: _filter == w
                                        ? HavenColors.primary
                                        : HavenColors.textPrimary,
                                  ),
                                ),
                                const SizedBox(width: HavenSpacing.sm),
                              ],
                            ],
                          ),
                        ),
                      );
                    }
                    if (index == 1) {
                      return Padding(
                        padding:
                            const EdgeInsets.only(bottom: HavenSpacing.lg),
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
                                count: totalOverdueVisible,
                                label: 'Overdue',
                                color: HavenColors.expired,
                              ),
                              const SizedBox(width: HavenSpacing.md),
                              _SummaryChip(
                                count: totalVisible - totalOverdueVisible,
                                label: 'Coming Up',
                                color: HavenColors.expiring,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                final item = visibleItems[index - 2];
                return _MaintenanceItemCard(
                  item: item,
                  dateFormat: dateFormat,
                  selectionMode: _selectionMode,
                  selectedKeys: _selected,
                  onToggleSelected: _toggleSelected,
                  onSnooze: (task, option) async {
                    final nextDue = DateTime.now()
                        .add(Duration(days: task.daysUntilDue));
                    await ref
                        .read(activeMaintenanceSnoozesProvider.notifier)
                        .snooze(
                          itemId: item.itemId,
                          scheduleId: task.scheduleId,
                          option: option,
                          nextDue: nextDue,
                        );
                    HavenHaptics.confirm();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                              '${task.taskName} snoozed for ${option.displayLabel.toLowerCase()}'),
                        ),
                      );
                    }
                  },
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
                      ref.invalidate(
                        maintenanceHistoryByItemProvider(item.itemId),
                      );
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
              ),
              if (_selectionMode && _selected.isNotEmpty)
                Positioned(
                  left: HavenSpacing.md,
                  right: HavenSpacing.md,
                  bottom: HavenSpacing.md,
                  child: SafeArea(
                    top: false,
                    child: Material(
                      elevation: 8,
                      color: HavenColors.elevated,
                      borderRadius: BorderRadius.circular(HavenRadius.card),
                      child: Padding(
                        padding: const EdgeInsets.all(HavenSpacing.md),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${_selected.length} task${_selected.length == 1 ? '' : 's'} selected',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: HavenColors.textPrimary,
                                ),
                              ),
                            ),
                            ElevatedButton.icon(
                              icon: const Icon(Icons.check, size: 18),
                              label: Text(
                                  'Mark ${_selected.length} done'),
                              onPressed: () {
                                final userId = ref
                                    .read(currentUserProvider)
                                    .value
                                    ?.id;
                                if (userId == null) {
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(const SnackBar(
                                          content: Text(
                                              'You need to be signed in to log maintenance.')));
                                  return;
                                }
                                _bulkMarkDone(visibleItems, userId);
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
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
  final Future<void> Function(
      MaintenanceDueTask task, MaintenanceSnoozeOption option) onSnooze;
  final bool selectionMode;
  final Set<String> selectedKeys;
  final void Function(String key) onToggleSelected;

  const _MaintenanceItemCard({
    required this.item,
    required this.dateFormat,
    required this.onMarkDone,
    required this.onSnooze,
    required this.selectionMode,
    required this.selectedKeys,
    required this.onToggleSelected,
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
                  if (selectionMode)
                    Checkbox(
                      value: selectedKeys
                          .contains(_taskKey(item.itemId, task.scheduleId)),
                      onChanged: (_) => onToggleSelected(
                          _taskKey(item.itemId, task.scheduleId)),
                      activeColor: HavenColors.primary,
                    )
                  else ...[
                    TextButton(
                      onPressed: () => onMarkDone(task),
                      style: TextButton.styleFrom(
                        foregroundColor: HavenColors.active,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: const Size(0, 32),
                      ),
                      child: const Text('Done', style: HavenText.meta),
                    ),
                    PopupMenuButton<MaintenanceSnoozeOption>(
                      tooltip: 'Snooze',
                      icon: const Icon(Icons.snooze,
                          size: 18, color: HavenColors.textSecondary),
                      padding: EdgeInsets.zero,
                      onSelected: (option) => onSnooze(task, option),
                      itemBuilder: (_) => [
                        for (final opt in MaintenanceSnoozeService.options)
                          PopupMenuItem<MaintenanceSnoozeOption>(
                            value: opt,
                            child: Text(
                                'Snooze ${opt.displayLabel.toLowerCase()}'),
                          ),
                      ],
                    ),
                  ],
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
