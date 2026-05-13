import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:api_client/api_client.dart';
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
  Timer? _searchDebounce;
  final Set<ItemRoom?> _collapsedRooms = {};
  bool _didApplyRouteFilter = false;
  final Set<String> _archivingIds = {};

  // Debounce keystrokes by 300ms so the filter cascade doesn't run on every
  // character at 60fps (F061).
  static const _searchDebounceDuration = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _searchDebounce?.cancel();
    final raw = _searchController.text.trim().toLowerCase();
    if (raw == _searchQuery) return;
    _searchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      setState(() => _searchQuery = raw);
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Apply route-extra filter only once, and only if the user hasn't
    // already curated a filter set — otherwise dashboard-driven nav would
    // silently overwrite a manual selection (F057).
    if (!_didApplyRouteFilter) {
      _didApplyRouteFilter = true;
      final extra = GoRouterState.of(context).extra;
      if (extra is Map<String, dynamic> && extra.containsKey('filter')) {
        final existing = ref.read(itemsFilterProvider);
        if (existing.isEmpty) {
          final filterStr = extra['filter'] as String;
          final status = WarrantyStatus.values.where((s) => s.name == filterStr);
          if (status.isNotEmpty) {
            // Defer the provider write until after the current frame so we
            // don't mutate state during dependency resolution.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              ref.read(itemsFilterProvider.notifier).state = {status.first};
            });
          }
        }
      }
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<Item> _applyFilters(
    List<Item> items,
    Set<WarrantyStatus> activeFilters,
  ) {
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
    if (activeFilters.isNotEmpty) {
      filtered = filtered.where((item) {
        return activeFilters.contains(item.computedWarrantyStatus);
      }).toList();
    }

    return filtered;
  }

  List<Item> _applySorting(List<Item> items, ItemSortMode sortMode) {
    final sorted = List<Item>.from(items);
    switch (sortMode) {
      case ItemSortMode.warrantyExpiry:
        sorted.sort((a, b) =>
            a.computedDaysRemaining.compareTo(b.computedDaysRemaining));
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
    HavenHaptics.tap();
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
    final sortMode = ref.watch(itemsSortProvider);

    return Scaffold(
      backgroundColor: HavenColors.canvas,
      appBar: AppBar(
        title: const Text('Items'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sort_rounded, size: 22),
            tooltip: 'Sort',
            onPressed: _showSortPicker,
          ),
          // Inline "+" replaces the removed FAB. Lives next to the sort
          // affordance because that's where a user expects list-affordances.
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 24),
            tooltip: 'Add item',
            onPressed: () => context.push(AppRoutes.addItem),
          ),
          const SizedBox(width: HavenSpacing.xs),
        ],
      ),
      body: itemsAsync.when(
        data: (allItems) {
          if (allItems.isEmpty) {
            return _buildEmptyState();
          }

          final filtered = _applyFilters(allItems, activeFilters);
          final sorted = _applySorting(filtered, sortMode);
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

              // Search bar — flush flat field on the canvas.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  HavenSpacing.md,
                  HavenSpacing.sm,
                  HavenSpacing.md,
                  HavenSpacing.sm + 2,
                ),
                child: TextField(
                  controller: _searchController,
                  style: HavenText.body,
                  decoration: InputDecoration(
                    hintText: 'Search by name, brand, model…',
                    prefixIcon: const Icon(Icons.search, size: 20),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded, size: 18),
                            onPressed: _searchController.clear,
                          )
                        : null,
                    isDense: true,
                  ),
                ),
              ),

              // Filter chips
              SizedBox(
                height: 36,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                      horizontal: HavenSpacing.md),
                  children: [
                    _FilterChip(
                      label: 'All',
                      isActive: activeFilters.isEmpty,
                      onTap: _selectAll,
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    _FilterChip(
                      label: 'Active',
                      isActive: activeFilters.contains(WarrantyStatus.active),
                      dotColor: HavenColors.active,
                      onTap: () => _toggleFilter(WarrantyStatus.active),
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    _FilterChip(
                      label: 'Expiring',
                      isActive: activeFilters.contains(WarrantyStatus.expiring),
                      dotColor: HavenColors.expiring,
                      onTap: () => _toggleFilter(WarrantyStatus.expiring),
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    _FilterChip(
                      label: 'Expired',
                      isActive: activeFilters.contains(WarrantyStatus.expired),
                      dotColor: HavenColors.expired,
                      onTap: () => _toggleFilter(WarrantyStatus.expired),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: HavenSpacing.sm),

              // Items list — fades between filter states and supports
              // pull-to-refresh for parity with the dashboard.
              Expanded(
                child: RefreshIndicator(
                  color: HavenColors.primary,
                  onRefresh: () async {
                    ref.invalidate(itemsProvider);
                    await ref.read(itemsProvider.future);
                  },
                  // Re-key only on filter/sort changes — debounced search
                  // already prevents per-keystroke rebuilds, and the
                  // sub-tree handles its own scroll preservation (F060).
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 220),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: child,
                    ),
                    child: KeyedSubtree(
                      // Order-stable key — a Set's iteration order is
                      // insertion order, so sort before joining or
                      // toggling the same two filters in a different
                      // order would spuriously refade + reset scroll.
                      key: ValueKey(
                        '${(activeFilters.map((s) => s.index).toList()..sort()).join(",")}'
                        '_${sortMode.name}',
                      ),
                      child: sorted.isEmpty
                          ? _buildNoResults()
                          : _buildGroupedList(sorted),
                    ),
                  ),
                ),
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
    return HavenEmptyState(
      icon: Icons.inventory_2_outlined,
      title: 'No items yet',
      body: 'Add your first item to start tracking warranties, '
          'receipts, and maintenance.',
      primaryAction: HavenEmptyAction(
        label: 'Add item',
        icon: Icons.add,
        onPressed: () => context.push(AppRoutes.addItem),
      ),
    );
  }

  Widget _buildNoResults() {
    final hasSearch = _searchQuery.isNotEmpty;
    final hasFilters = ref.read(itemsFilterProvider).isNotEmpty;

    // Use a scrollable ListView so RefreshIndicator has a scrollable child.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: HavenSpacing.xl),
      children: [
        Column(
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
                  ? "No warranties match '$_searchQuery'"
                  : 'No warranties match the selected filters',
              style: HavenText.body.copyWith(color: HavenColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: HavenSpacing.xs),
            Text(
              hasSearch
                  ? 'Try a different search term or check your spelling'
                  : 'Try selecting a different status filter above',
              style: HavenText.meta,
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
                label: const Text('Show all warranties'),
                style: TextButton.styleFrom(
                  foregroundColor: HavenColors.secondary,
                ),
              ),
          ],
        ),
      ],
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

    // Flatten headers + items into a single flat list so ListView.builder
    // can virtualize across rooms — collapsing a room contributes only its
    // header to the index space (F062).
    final flat = <_FlatRow>[];
    for (final room in sortedRooms) {
      final roomItems = grouped[room]!;
      flat.add(_FlatRow.header(room: room, count: roomItems.length));
      if (!_collapsedRooms.contains(room)) {
        for (final item in roomItems) {
          flat.add(_FlatRow.item(item));
        }
        // Trailing spacer per room.
        flat.add(_FlatRow.spacer());
      }
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        HavenSpacing.md,
        0,
        HavenSpacing.md,
        // Clear the floating nav + docked FAB.
        HavenSpacing.xxl + HavenSpacing.lg + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: flat.length,
      itemBuilder: (context, index) {
        final row = flat[index];
        switch (row.kind) {
          case _FlatRowKind.header:
            final room = row.room;
            final isCollapsed = _collapsedRooms.contains(room);
            final roomLabel = room?.displayLabel ?? 'Unassigned';
            return SectionHeader(
              title: roomLabel,
              count: row.count,
              trailing: AnimatedRotation(
                turns: isCollapsed ? -0.25 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: const Icon(
                  Icons.keyboard_arrow_down,
                  color: HavenColors.textTertiary,
                  size: 20,
                ),
              ),
              onTap: () {
                HavenHaptics.tap();
                setState(() {
                  if (isCollapsed) {
                    _collapsedRooms.remove(room);
                  } else {
                    _collapsedRooms.add(room);
                  }
                });
              },
            );
          case _FlatRowKind.item:
            return _buildItemCard(row.item!);
          case _FlatRowKind.spacer:
            return const SizedBox(height: HavenSpacing.md);
        }
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

          // Surface failures to the user so the swipe doesn't appear to
          // succeed silently when the API rejected the archive (F059).
          Object? archiveError;
          try {
            await ref.read(itemsProvider.notifier).archiveItem(item.id)
                .timeout(const Duration(seconds: 15));
          } catch (e) {
            archiveError = e;
          } finally {
            _archivingIds.remove(item.id);
          }
          if (!mounted) return false;

          final messenger = ScaffoldMessenger.of(context);
          messenger.clearSnackBars();

          if (archiveError != null) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(ErrorHandler.getUserMessage(archiveError)),
                behavior: SnackBarBehavior.floating,
              ),
            );
            return false;
          }

          final displayName = '${item.brand ?? ''} ${item.name}'.trim();
          messenger.showSnackBar(
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
            borderRadius: BorderRadius.circular(HavenRadius.button),
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
        // 3.6: a11y pass.
        // - The outer `Semantics(button: true, label: ...)` aggregates
        //   brand + name + warranty status + days remaining into a single
        //   announcement so VoiceOver/TalkBack reads one row's worth of
        //   information per swipe instead of every nested Text node.
        // - Material+InkWell replaces the bare GestureDetector so
        //   keyboard / D-Pad focus draws a focus ring AND the user gets
        //   the standard tap ripple. The `Material` parent matches the
        //   row's surface color so the ink isn't visible against a
        //   contrasting background.
        // - The hit-test region is at least 56px tall (icon + padding)
        //   which clears the 48px Material guideline. We also pass
        //   `borderRadius` to InkWell so the ripple is clipped to the
        //   card's rounded corners.
        child: _ItemCardTapTarget(item: item),
      ),
    );
  }
}

class _ItemCardTapTarget extends StatelessWidget {
  final Item item;

  const _ItemCardTapTarget({required this.item});

  String _semanticStatus(Item item) {
    final status = item.computedWarrantyStatus;
    final days = item.computedDaysRemaining;
    return switch (status) {
      WarrantyStatus.active => 'warranty active, $days days remaining',
      WarrantyStatus.expiring => 'warranty expiring in $days days',
      WarrantyStatus.expired =>
        'warranty expired ${days.abs()} days ago',
    };
  }

  @override
  Widget build(BuildContext context) {
    final displayName = '${item.brand ?? ''} ${item.name}'.trim();
    final semanticLabel = '$displayName, ${_semanticStatus(item)}';
    final subtitle = (item.modelNumber != null && item.modelNumber!.isNotEmpty)
        ? item.modelNumber!
        : item.category.displayLabel;

    return HavenCard(
      radius: HavenRadius.button,
      padding: const EdgeInsets.symmetric(
          horizontal: HavenSpacing.md, vertical: HavenSpacing.sm + 2),
      semanticLabel: semanticLabel,
      onTap: () {
        HavenHaptics.tap();
        context.push('/items/${item.id}');
      },
      child: Row(
        children: [
          Hero(
            tag: HavenHeroTag.item(item.id),
            child: CategoryIcon.widget(item.category, size: 20),
          ),
          const SizedBox(width: HavenSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: HavenText.body.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),
                Text(
                  subtitle,
                  style: HavenText.caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: HavenSpacing.sm),
          WarrantyStatusBadge(
            status: item.computedWarrantyStatus,
            compact: true,
          ),
          const SizedBox(width: HavenSpacing.xs),
          const Icon(Icons.chevron_right,
              color: HavenColors.textTertiary, size: 18),
        ],
      ),
    );
  }
}

/// Lightweight discriminator for the flat-virtualized grouped list.
enum _FlatRowKind { header, item, spacer }

class _FlatRow {
  final _FlatRowKind kind;
  final ItemRoom? room;
  final int count;
  final Item? item;

  const _FlatRow._(this.kind, this.room, this.count, this.item);

  factory _FlatRow.header({required ItemRoom? room, required int count}) =>
      _FlatRow._(_FlatRowKind.header, room, count, null);
  factory _FlatRow.item(Item item) =>
      _FlatRow._(_FlatRowKind.item, null, 0, item);
  factory _FlatRow.spacer() =>
      const _FlatRow._(_FlatRowKind.spacer, null, 0, null);
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
    // Compact pill: 36px tall row, but the InkWell hit-target stretches
    // the full slot height so it still clears the touch-target guideline
    // in practice (the surrounding ListView is 36, padded). `selected`
    // drives both the visual fill and the SR announcement.
    final fg = isActive ? Colors.white : HavenColors.textSecondary;
    return Semantics(
      button: true,
      selected: isActive,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(HavenRadius.chip),
          onTap: () {
            HavenHaptics.tap();
            onTap();
          },
          child: AnimatedContainer(
            duration: HavenMotion.fast,
            padding: const EdgeInsets.symmetric(
                horizontal: HavenSpacing.md, vertical: HavenSpacing.sm),
            decoration: BoxDecoration(
              color: isActive ? HavenColors.primary : HavenColors.surface,
              borderRadius: BorderRadius.circular(HavenRadius.chip),
              border: Border.all(
                color: isActive ? HavenColors.primary : HavenColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (dotColor != null) ...[
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : dotColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
