import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/maintenance_provider.dart';
import '../../core/utils/error_handler.dart';

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
        offset: _items.length,
      );

      setState(() {
        _items.addAll(newItems);
        _hasMore = newItems.length >= _pageSize;
        _isInitialLoad = false;
        _isLoading = false;
      });
    } catch (e) {
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
      return const Center(child: CircularProgressIndicator());
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
              child: Center(child: CircularProgressIndicator()),
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
          setState(() {
            _items.removeWhere((e) => e.id == entry.id);
          });
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
  }
}
