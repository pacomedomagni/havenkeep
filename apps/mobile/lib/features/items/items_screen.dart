import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../core/providers/items_provider.dart';
import '../../core/router/router.dart';

/// Items list screen with search, filter chips, room grouping, and swipe actions.
class ItemsScreen extends ConsumerStatefulWidget {
  const ItemsScreen({super.key});

  @override
  ConsumerState<ItemsScreen> createState() => _ItemsScreenState();
}

class _ItemsScreenState extends ConsumerState<ItemsScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Set<WarrantyStatus> _activeFilters = {};
  final Set<ItemRoom?> _collapsedRooms = {};

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
    // Check for initial filter passed via route extra
    final extra = GoRouterState.of(context).extra;
    if (extra is Map<String, dynamic> && extra.containsKey('filter')) {
      final filterStr = extra['filter'] as String;
      final status = WarrantyStatus.values.where((s) => s.name == filterStr);
      if (status.isNotEmpty) {
        _activeFilters = {status.first};
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Item> _applyFilters(List<Item> items) {
    var filtered = items.where((item) => !item.isArchived).toList();

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
    if (_activeFilters.isNotEmpty) {
      filtered = filtered.where((item) {
        return _activeFilters.contains(item.computedWarrantyStatus);
      }).toList();
    }

    return filtered;
  }

  Map<ItemRoom?, List<Item>> _groupByRoom(List<Item> items) {
    final grouped = <ItemRoom?, List<Item>>{};
    for (final item in items) {
      final room = item.room;
      grouped.putIfAbsent(room, () => []);
      grouped[room]!.add(item);
    }
    // Sort items within each room by warranty end date
    for (final list in grouped.values) {
      list.sort((a, b) {
        final aEnd = a.warrantyEndDate ??
            a.purchaseDate.add(Duration(days: a.warrantyMonths * 30));
        final bEnd = b.warrantyEndDate ??
            b.purchaseDate.add(Duration(days: b.warrantyMonths * 30));
        return aEnd.compareTo(bEnd);
      });
    }
    return grouped;
  }

  void _toggleFilter(WarrantyStatus status) {
    setState(() {
      if (_activeFilters.contains(status)) {
        _activeFilters.remove(status);
      } else {
        _activeFilters.add(status);
      }
    });
  }

  void _selectAll() {
    setState(() {
      _activeFilters.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final itemsAsync = ref.watch(itemsProvider);
    final itemCountAsync = ref.watch(activeItemCountProvider);
    final isAtLimitAsync = ref.watch(isAtItemLimitProvider);

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        title: const Text(
          'My Items',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
      ),
      body: itemsAsync.when(
        data: (allItems) {
          if (allItems.isEmpty) {
            return _buildEmptyState();
          }

          final filtered = _applyFilters(allItems);
          final itemCount = itemCountAsync.value ?? 0;
          final showLimitBanner = itemCount >= 20;

          return Column(
            children: [
              // Item limit banner
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
                        isActive: _activeFilters.isEmpty,
                        onTap: _selectAll,
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Active',
                        isActive:
                            _activeFilters.contains(WarrantyStatus.active),
                        dotColor: HavenColors.active,
                        onTap: () => _toggleFilter(WarrantyStatus.active),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Expiring',
                        isActive:
                            _activeFilters.contains(WarrantyStatus.expiring),
                        dotColor: HavenColors.expiring,
                        onTap: () => _toggleFilter(WarrantyStatus.expiring),
                      ),
                      const SizedBox(width: HavenSpacing.sm),
                      _FilterChip(
                        label: 'Expired',
                        isActive:
                            _activeFilters.contains(WarrantyStatus.expired),
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
                child: filtered.isEmpty
                    ? _buildNoResults()
                    : _buildGroupedList(filtered),
              ),
            ],
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
          child: Text(
            'Error: $error',
            style: const TextStyle(color: HavenColors.expired),
          ),
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
            _searchQuery.isNotEmpty
                ? "No items match '$_searchQuery'"
                : 'No items match the selected filters',
            style: const TextStyle(
              fontSize: 16,
              color: HavenColors.textSecondary,
            ),
            textAlign: TextAlign.center,
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
          // Show action sheet with archive/delete
          return await _showSwipeActions(item);
        },
        background: const SizedBox.shrink(),
        secondaryBackground: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _SwipeAction(
              color: HavenColors.primary,
              icon: Icons.archive_outlined,
              label: 'Archive',
            ),
            _SwipeAction(
              color: HavenColors.expired,
              icon: Icons.delete_outline,
              label: 'Delete',
            ),
          ],
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
                      Text(
                        '${item.brand ?? ''} ${item.name}'.trim(),
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: HavenColors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Future<bool?> _showSwipeActions(Item item) async {
    final action = await showModalBottomSheet<String>(
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
            children: [
              ListTile(
                leading: const Icon(Icons.archive_outlined,
                    color: HavenColors.primary),
                title: const Text(
                  'Archive',
                  style: TextStyle(color: HavenColors.textPrimary),
                ),
                subtitle: const Text(
                  'Hide from list but keep data',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
                onTap: () => Navigator.of(ctx).pop('archive'),
              ),
              ListTile(
                leading: const Icon(Icons.delete_outline,
                    color: HavenColors.expired),
                title: const Text(
                  'Delete',
                  style: TextStyle(color: HavenColors.expired),
                ),
                subtitle: const Text(
                  'Permanently remove this item',
                  style: TextStyle(color: HavenColors.textTertiary),
                ),
                onTap: () => Navigator.of(ctx).pop('delete'),
              ),
            ],
          ),
        ),
      ),
    );

    if (action == null || !mounted) return false;

    if (action == 'archive') {
      final confirmed = await showHavenConfirmDialog(
        context,
        title: 'Archive item?',
        body:
            'This will hide "${item.brand ?? ''} ${item.name}".trim() from your list. You can restore it later.',
        confirmLabel: 'Archive',
      );
      if (confirmed && mounted) {
        await ref.read(itemsProvider.notifier).archiveItem(item.id);
        return true;
      }
    } else if (action == 'delete') {
      final confirmed = await showHavenConfirmDialog(
        context,
        title: 'Delete item?',
        body:
            'This will permanently delete "${item.brand ?? ''} ${item.name}".trim(). This action cannot be undone.',
        confirmLabel: 'Delete',
        isDestructive: true,
      );
      if (confirmed && mounted) {
        await ref.read(itemsProvider.notifier).deleteItem(item.id);
        return true;
      }
    }

    return false;
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

/// Colored action shown behind a dismissible item card.
class _SwipeAction extends StatelessWidget {
  final Color color;
  final IconData icon;
  final String label;

  const _SwipeAction({
    required this.color,
    required this.icon,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      alignment: Alignment.center,
      margin: const EdgeInsets.only(left: HavenSpacing.xs),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(height: 2),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
