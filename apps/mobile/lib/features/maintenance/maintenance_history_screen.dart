import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/maintenance_provider.dart';
import '../../core/utils/error_handler.dart';
import '../../core/utils/money_formatter.dart';
import '../../core/widgets/haven_illustration.dart';
import '../../core/widgets/haven_loader.dart';

/// Paginated maintenance history list with infinite scroll and delete.
class MaintenanceHistoryScreen extends ConsumerStatefulWidget {
  const MaintenanceHistoryScreen({super.key});

  @override
  ConsumerState<MaintenanceHistoryScreen> createState() =>
      _MaintenanceHistoryScreenState();
}

class _MaintenanceHistoryScreenState
    extends ConsumerState<MaintenanceHistoryScreen> {
  static const _pageSize = 20;

  final ScrollController _scrollController = ScrollController();
  final List<MaintenanceHistory> _items = [];
  int _currentPage = 1;
  bool _isLoading = false;
  bool _isInitialLoad = true;
  bool _hasMore = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadPage();
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadPage();
    }
  }

  Future<void> _loadPage() async {
    if (_isLoading) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final repo = ref.read(maintenanceRepositoryProvider);
      final newItems = await repo.getHistoryPaginated(
        limit: _pageSize,
        page: _currentPage,
      );

      // Guard every async-followup setState — user can pop the route
      // before the page resolves (F067).
      if (!mounted) return;
      setState(() {
        _items.addAll(newItems);
        _currentPage++;
        _hasMore = newItems.length >= _pageSize;
        _isInitialLoad = false;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = ErrorHandler.getUserMessage(e);
        _isInitialLoad = false;
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    setState(() {
      _items.clear();
      _currentPage = 1;
      _hasMore = true;
      _isInitialLoad = true;
      _error = null;
    });
    await _loadPage();
  }

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat.yMMMd();

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(title: const Text('Maintenance History')),
      body: _buildBody(dateFormat),
    );
  }

  Widget _buildBody(DateFormat dateFormat) {
    // Initial loading state
    if (_isInitialLoad && _isLoading) {
      return const Center(child: HavenLoader());
    }

    // Error on initial load with no data
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!,
                style: const TextStyle(color: HavenColors.textSecondary)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _refresh,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    // Empty state
    if (_items.isEmpty && !_hasMore) {
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
              Text(
                'No maintenance history',
                style: HavenText.displayMedium,
              ),
              SizedBox(height: HavenSpacing.sm),
              Text(
                'Completed maintenance tasks\nwill appear here.',
                textAlign: TextAlign.center,
                style: HavenText.bodySecondary,
              ),
            ],
          ),
        ),
      );
    }

    // List with infinite scroll
    return RefreshIndicator(
      onRefresh: _refresh,
      color: HavenColors.primary,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.all(HavenSpacing.md),
        itemCount: _items.length + (_hasMore ? 1 : 0),
        itemBuilder: (context, index) {
          // Loading indicator at the bottom
          if (index == _items.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: HavenSpacing.md),
              child: Center(child: HavenLoader()),
            );
          }

          final entry = _items[index];
          return _buildHistoryTile(entry, dateFormat);
        },
      ),
    );
  }

  Widget _buildHistoryTile(MaintenanceHistory entry, DateFormat dateFormat) {
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
      // confirmDismiss returns whether the dismiss should proceed; we don't
      // mutate _items here. onDismissed handles the actual list removal so
      // the slide animation plays end-to-end before the row disappears
      // (F068).
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
          ref.invalidate(maintenanceDueProvider);
          return true;
        } catch (e) {
          if (!mounted) return false;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ErrorHandler.getUserMessage(e))),
          );
          return false;
        }
      },
      onDismissed: (_) {
        if (!mounted) return;
        setState(() {
          _items.removeWhere((e) => e.id == entry.id);
        });
      },
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
                      Money.format(entry.cost),
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
  }
}
