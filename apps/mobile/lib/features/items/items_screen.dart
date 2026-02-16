import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';
import '../../core/utils/error_handler.dart';
import '../../core/widgets/error_state_widget.dart';

/// Sort mode for the items list.
enum ItemSortMode {
  warrantyExpiry('Warranty Expiry'),
  dateAdded('Date Added'),
  name('Name'),
  price('Price');

  final String label;
  const ItemSortMode(this.label);
}

/// Persisted filter/sort state so it survives tab navigation.
final itemsFilterProvider =
    StateProvider<Set<WarrantyStatus>>((ref) => {});

final itemsSortProvider =
    StateProvider<ItemSortMode>((ref) => ItemSortMode.warrantyExpiry);

/// Items list screen with search, filter chips, sort, room grouping, and swipe actions.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<ItemRoom?> _collapsedRooms = {};
  bool _didApplyRouteFilter = false;
  final Set<String> _archivingIds = {};

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.trim().toLowerCase();
      });
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Check for initial filter passed via route extra (only once)
    if (!_didApplyRouteFilter) {
      final extra = GoRouterState.of(context).extra;
      if (extra is Map<String, dynamic> && extra.containsKey('filter')) {
        final filterStr = extra['filter'] as String;
        final status = WarrantyStatus.values.where((s) => s.name == filterStr);
        if (status.isNotEmpty) {
          ref.read(itemsFilterProvider.notifier).state = {status.first};
        }
      }
      _didApplyRouteFilter = true;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Item> _applyFilters(List<Item> items) {
    var filtered = items.where((item) => !item.isArchived).toList();
    final activeFilters = ref.read(itemsFilterProvider);

    // Apply search
    if (_searchQuery.isNotEmpty) {
      filtered = filtered.where((item) {
        final name = item.name.toLowerCase();
        final brand = (item.brand ?? '').toLowerCase();
        final model = (item.modelNumber ?? '').toLowerCase();
        return name.contains(_searchQuery) ||
            brand.contains(_searchQuery) ||
            model.contains(_searchQuery);
      }).toList();
    }

    // Apply status filters
    if (activeFilters.isNotEmpty) {
      filtered = filtered.where((item) {
        return activeFilters.contains(item.computedWarrantyStatus);
      }).toList();
    }

    return filtered;
  }

  List<Item> _applySorting(List<Item> items) {
    final sorted = List<Item>.from(items);
    final sortMode = ref.read(itemsSortProvider);
    switch (sortMode) {
      case ItemSortMode.warrantyExpiry:
        sorted.sort((a, b) =>
            (a.computedDaysRemaining ?? 0).compareTo(b.computedDaysRemaining ?? 0));
        break;
      case ItemSortMode.dateAdded:
        sorted.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        break;
      case ItemSortMode.name:
        sorted.sort((a, b) {
          final aName = '${a.brand ?? ''} ${a.name}'.trim().toLowerCase();
          final bName = '${b.brand ?? ''} ${b.name}'.trim().toLowerCase();
          return aName.compareTo(bName);
        });
        break;
      case ItemSortMode.price:
        sorted.sort((a, b) {
          final aPrice = a.price ?? 0;
          final bPrice = b.price ?? 0;
          return bPrice.compareTo(aPrice);
        });
        break;
    }
    return sorted;
  }

  Map<ItemRoom?, List<Item>> _groupByRoom(List<Item> items) {
    final grouped = <ItemRoom?, List<Item>>{};
    for (final item in items) {
      final room = item.room;
      grouped.putIfAbsent(room, () => []);
      grouped[room]!.add(item);
    }
    return grouped;
  }

  void _toggleFilter(WarrantyStatus status) {
    final current = ref.read(itemsFilterProvider);
    final updated = Set<WarrantyStatus>.from(current);
    if (updated.contains(status)) {
      updated.remove(status);
    } else {
      updated.add(status);
    }
    ref.read(itemsFilterProvider.notifier).state = updated;
  }

  void _selectAll() {
    ref.read(itemsFilterProvider.notifier).state = {};
  }

  void _showSortPicker() {
    HapticFeedback.lightImpact();
    final currentSort = ref.read(itemsSortProvider);
    showModalBottomSheet(
      context: context,
      backgroundColor: HavenColors.elevated,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(HavenRadius.card),
        ),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(HavenSpacing.md),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Sort by',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: HavenColors.textPrimary,
                ),
              ),
              const SizedBox(height: HavenSpacing.md),
              ...ItemSortMode.values.map((mode) => ListTile(
                    leading: Icon(
                      currentSort == mode
                          ? Icons.radio_button_checked
                          : Icons.radio_button_off,
                      color: currentSort == mode
                          ? HavenColors.primary
                          : HavenColors.textTertiary,
                    ),
                    title: Text(
                      mode.label,
                      style: TextStyle(
                        color: currentSort == mode
                            ? HavenColors.primary
                            : HavenColors.textPrimary,
                        fontWeight: currentSort == mode
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    onTap: () {
                      ref.read(itemsSortProvider.notifier).state = mode;
                      Navigator.of(ctx).pop();
                    },
                  )),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);
    final activeFilters = ref.watch(itemsFilterProvider);
    ref.watch(itemsSortProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'My Items',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort, size: 22),
            tooltip: 'Sort',
            onPressed: _showSortPicker,
          ),
        ],
      ),
      body: itemsAsync.when(
        data: (allItems) {
          if (allItems.isEmpty) {
            return _buildEmptyState();
          }

          final filtered = _applyFilters(allItems);
          final sorted = _applySorting(filtered);
          final itemCount = itemCountAsync.value ?? 0;
          // Soft warn when approaching limit (1 item before cap)
          final showLimitBanner = itemCount >= kFreePlanItemLimit - 1;

          return Column(
            children: [
              // Item limit banner (soft warning)
              if (showLimitBanner)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    HavenSpacing.md,
                    HavenSpacing.sm,
                    HavenSpacing.md,
                    0,
                  ),
                  child: ItemLimitBanner(
                    currentCount: itemCount,
                    maxCount: kFreePlanItemLimit,
                    onArchive: () =>
                        context.push(AppRoutes.archivedItems),
                    onUpgrade: () =>
                        context.push(AppRoutes.premium),
                  ),
                ),

              // Search bar
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HavenSpacing.md,
                  HavenSpacing.sm,
                  HavenSpacing.md,
                  HavenSpacing.sm,
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: HavenColors.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Search items...',
                    hintStyle:
                        const TextStyle(color: HavenColors.textTertiary),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: HavenColors.textTertiary,
                    ),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(
                              Icons.clear,
                              color: HavenColors.textTertiary,
                            ),
                            onPressed: () {
                              _searchController.clear();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: HavenColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HavenRadius.input),
                      borderSide:
                          const BorderSide(color: HavenColors.border),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HavenRadius.input),
                      borderSide:
                          const BorderSide(color: HavenColors.border),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HavenRadius.input),
                      borderSide: const BorderSide(
                          color: HavenColors.primary, width: 2),
                    ),
                  ),
                ),
              ),

              // Filter chips
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: HavenSpacing.md,
                ),
                child: SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      _FilterChip(
                        label: 'All',
                        isActive: activeFilters.isEmpty,
                        onTap: _selectAll,
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Active',
                        isActive:
                            activeFilters.contains(WarrantyStatus.active),
                        dotColor: HavenColors.active,
                        onTap: () => _toggleFilter(WarrantyStatus.active),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Expiring',
                        isActive:
                            activeFilters.contains(WarrantyStatus.expiring),
                        dotColor: HavenColors.expiring,
                        onTap: () => _toggleFilter(WarrantyStatus.expiring),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Expired',
                        isActive:
                            activeFilters.contains(WarrantyStatus.expired),
                        dotColor: HavenColors.expired,
                        onTap: () => _toggleFilter(WarrantyStatus.expired),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),

              // Items list
              Expanded(
                child: sorted.isEmpty
                    ? _buildNoResults()
                    : _buildGroupedList(sorted),
              ),
            ],
          );
        },
        loading: () => ListView(
          padding: const EdgeInsets.all(HavenSpacing.md),
          children: const [
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
            SizedBox(height: HavenSpacing.sm),
            SkeletonCard(),
          ],
        ),
        error: (error, _) => ErrorStateWidget(
          message: ErrorHandler.getUserMessage(error),
          onRetry: () => ref.invalidate(itemsProvider),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.inventory_2_outlined,
            size: 64,
            color: HavenColors.textTertiary,
          ),
          SizedBox(height: HavenSpacing.md),
          Text(
            'No items yet',
            style: TextStyle(
              fontSize: 18,
              color: HavenColors.textSecondary,
            ),
          ),
          SizedBox(height: HavenSpacing.xs),
          Text(
            'Tap + to add your first item',
            style: TextStyle(color: HavenColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildNoResults() {
    final hasSearch = _searchQuery.isNotEmpty;
    final hasFilters = ref.read(itemsFilterProvider).isNotEmpty;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.search_off,
            size: 48,
            color: HavenColors.textTertiary,
          ),
          const SizedBox(height: HavenSpacing.md),
          Text(
            hasSearch
                ? "No items match '$_searchQuery'"
                : 'No items match the selected filters',
            style: const TextStyle(
              fontSize: 16,
              color: HavenColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HavenSpacing.xs),
          Text(
            hasSearch
                ? 'Try a different search term or check your spelling'
                : 'Try selecting a different status filter above',
            style: const TextStyle(
              fontSize: 13,
              color: HavenColors.textTertiary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: HavenSpacing.lg),
          if (hasSearch)
            TextButton.icon(
              onPressed: () => _searchController.clear(),
              icon: const Icon(Icons.clear, size: 16),
              label: const Text('Clear search'),
              style: TextButton.styleFrom(
                foregroundColor: HavenColors.secondary,
              ),
            ),
          if (hasFilters)
            TextButton.icon(
              onPressed: _selectAll,
              icon: const Icon(Icons.filter_alt_off, size: 16),
              label: const Text('Show all items'),
              style: TextButton.styleFrom(
                foregroundColor: HavenColors.secondary,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGroupedList(List<Item> items) {
    final grouped = _groupByRoom(items);
    // Sort room groups: non-null rooms alphabetically, null last
    final sortedRooms = grouped.keys.toList()
      ..sort((a, b) {
        if (a == null && b == null) return 0;
        if (a == null) return 1;
        if (b == null) return -1;
        return a.displayLabel.compareTo(b.displayLabel);
      });

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
      itemCount: sortedRooms.length,
      itemBuilder: (context, index) {
        final room = sortedRooms[index];
        final roomItems = grouped[room]!;
        final isCollapsed = _collapsedRooms.contains(room);
        final roomLabel = room?.displayLabel ?? 'Unassigned';

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              title: roomLabel,
              count: roomItems.length,
              trailing: Icon(
                isCollapsed
                    ? Icons.keyboard_arrow_right
                    : Icons.keyboard_arrow_down,
                color: HavenColors.textTertiary,
                size: 20,
              ),
              onTap: () {
                HapticFeedback.lightImpact();
                setState(() {
                  if (isCollapsed) {
                    _collapsedRooms.remove(room);
                  } else {
                    _collapsedRooms.add(room);
                  }
                });
              },
            ),
            if (!isCollapsed) ...[
              ...roomItems.map((item) => _buildItemCard(item)),
              const SizedBox(height: HavenSpacing.md),
            ],
          ],
        );
      },
    );
  }

  Widget _buildItemCard(Item item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: HavenSpacing.sm),
      child: Dismissible(
        key: ValueKey(item.id),
        direction: DismissDirection.endToStart,
        confirmDismiss: (direction) async {
          // Prevent double-fire while archive API is in-flight
          if (_archivingIds.contains(item.id)) return false;
          _archivingIds.add(item.id);

          try {
            await ref.read(itemsProvider.notifier).archiveItem(item.id)
                .timeout(const Duration(seconds: 15));
          } finally {
            _archivingIds.remove(item.id);
          }
          if (!mounted) return false;

          final displayName = '${item.brand ?? ''} ${item.name}'.trim();
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$displayName archived'),
              behavior: SnackBarBehavior.floating,
              action: SnackBarAction(
                label: 'Undo',
                textColor: HavenColors.primary,
                onPressed: () {
                  ref.read(itemsProvider.notifier).unarchiveItem(item.id);
                },
              ),
              duration: const Duration(seconds: 4),
            ),
          );
          return false; // Don't remove from list — provider handles it
        },
        background: const SizedBox.shrink(),
        secondaryBackground: Container(
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: HavenSpacing.lg),
          margin: const EdgeInsets.only(left: HavenSpacing.xs),
          decoration: BoxDecoration(
            color: HavenColors.primary,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.archive_outlined, color: Colors.white, size: 22),
              SizedBox(height: 2),
              Text(
                'Archive',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        child: GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            context.push('/items/${item.id}');
          },
          child: Container(
            padding: const EdgeInsets.all(HavenSpacing.md),
            decoration: BoxDecoration(
              color: HavenColors.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: HavenColors.border),
            ),
            child: Row(
              children: [
                CategoryIcon.widget(item.category),
                const SizedBox(width: HavenSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Builder(builder: (_) {
                        final displayName = '${item.brand ?? ''} ${item.name}'.trim();
                        return Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: HavenColors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        );
                      }),
                      if (item.modelNumber != null &&
                          item.modelNumber!.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          item.modelNumber!,
                          style: const TextStyle(
                            fontSize: 12,
                            color: HavenColors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: HavenSpacing.xs),
                      WarrantyStatusBadge(
                        status: item.computedWarrantyStatus,
                        compact: true,
                      ),
                    ],
                  ),
                ),
                const Icon(
                  Icons.chevron_right,
                  color: HavenColors.textTertiary,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A filter chip for the status filter row.
class _FilterChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color? dotColor;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.isActive,
    this.dotColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md,
          vertical: HavenSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: isActive ? HavenColors.primary : HavenColors.surface,
          borderRadius: BorderRadius.circular(HavenRadius.chip),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (dotColor != null) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: isActive ? Colors.white : dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: HavenSpacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isActive
                    ? Colors.white
                    : HavenColors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
