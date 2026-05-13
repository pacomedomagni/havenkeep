import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_ui/shared_ui.dart';

import '../../../core/providers/items_provider.dart';
import '../../../core/router/router.dart';
import 'bulk_add_provider.dart';

/// Room walkthrough screen (Screens 2.2–2.4).
///
/// Shows one room at a time with a grid of appliances to select.
/// Selected items get a compact form for brand, purchase date, and warranty.
class RoomSetupScreen extends ConsumerStatefulWidget {
  const RoomSetupScreen({super.key});

  @override
  ConsumerState<RoomSetupScreen> createState() => _RoomSetupScreenState();
}

class _RoomSetupScreenState extends ConsumerState<RoomSetupScreen> {
  final Map<int, TextEditingController> _brandControllers = {};
  final Map<int, DateTime> _purchaseDates = {};
  final Map<int, int> _warrantyMonths = {};

  @override
  void dispose() {
    for (final c in _brandControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _toggleAppliance(BulkAddAppliance appliance) {
    HavenHaptics.confirm();
    final notifier = ref.read(bulkAddProvider.notifier);
    final state = ref.read(bulkAddProvider);
    final items = state.currentRoomItems;

    // Check if already selected (by category + name)
    final existingIndex = items.indexWhere(
      (i) => i.category == appliance.category && i.name == appliance.name,
    );

    if (existingIndex >= 0) {
      // Deselect. Removing an item shifts every later index down by one,
      // so the per-index maps would alias the wrong rows for a frame —
      // clear them all and let the next build re-seed from the (updated)
      // provider list, which is the source of truth.
      notifier.removeItem(existingIndex);
      _disposeAndClearControllers();
      _purchaseDates.clear();
      _warrantyMonths.clear();
    } else {
      // Select
      final item = BulkAddItem(
        name: appliance.name,
        category: appliance.category,
        room: state.currentRoom.room,
        purchaseDate: DateTime.now(),
        warrantyMonths: appliance.defaultWarrantyMonths,
      );
      notifier.addItem(item);
    }
  }

  bool _isSelected(BulkAddAppliance appliance) {
    final items = ref.read(bulkAddProvider).currentRoomItems;
    return items.any(
      (i) => i.category == appliance.category && i.name == appliance.name,
    );
  }

  void _updateItemBrand(int index, String brand) {
    final state = ref.read(bulkAddProvider);
    final items = state.currentRoomItems;
    if (index < items.length) {
      ref
          .read(bulkAddProvider.notifier)
          .updateItem(index, items[index].copyWith(brand: brand));
    }
  }

  void _updateItemDate(int index, DateTime date) {
    final state = ref.read(bulkAddProvider);
    final items = state.currentRoomItems;
    if (index < items.length) {
      ref
          .read(bulkAddProvider.notifier)
          .updateItem(index, items[index].copyWith(purchaseDate: date));
    }
    setState(() => _purchaseDates[index] = date);
  }

  void _updateItemWarranty(int index, int months) {
    final state = ref.read(bulkAddProvider);
    final items = state.currentRoomItems;
    if (index < items.length) {
      ref
          .read(bulkAddProvider.notifier)
          .updateItem(index, items[index].copyWith(warrantyMonths: months));
    }
    setState(() => _warrantyMonths[index] = months);
  }

  void _disposeAndClearControllers() {
    for (final c in _brandControllers.values) {
      c.dispose();
    }
    _brandControllers.clear();
    _purchaseDates.clear();
    _warrantyMonths.clear();
  }

  void _nextRoom() {
    final state = ref.read(bulkAddProvider);
    if (state.isLastRoom) {
      // Navigate to complete screen
      context.go(AppRoutes.bulkAddComplete);
    } else {
      ref.read(bulkAddProvider.notifier).nextRoom();
      // Clear local form state for new room
      _disposeAndClearControllers();
    }
  }

  void _previousRoom() {
    final state = ref.read(bulkAddProvider);
    if (state.currentRoomIndex == 0) {
      context.go(AppRoutes.homeSetup);
    } else {
      ref.read(bulkAddProvider.notifier).previousRoom();
      _disposeAndClearControllers();
    }
  }

  Future<void> _skipRoom() async {
    final items = ref.read(bulkAddProvider).currentRoomItems;
    if (items.isNotEmpty) {
      final confirmed = await showHavenConfirmDialog(
        context,
        title: 'Skip this room?',
        body: 'You have ${items.length} ${items.length == 1 ? 'item' : 'items'} selected. Skipping will discard them.',
        confirmLabel: 'Skip',
        isDestructive: true,
      );
      if (!confirmed) return;
    }
    _nextRoom();
  }

  Future<void> _pickDate(int index) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDates[index] ?? now,
      // Ch05-F022: align with the rest of the add-item surfaces; people
      // do still own appliances bought before 2000 (built-in HVAC,
      // boilers, etc.) and the picker shouldn't punt them to "manual
      // entry" for that.
      firstDate: DateTime(1970),
      lastDate: now.add(const Duration(days: 30)),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.dark(
              primary: HavenColors.primary,
              surface: HavenColors.elevated,
            ),
          ),
          child: child!,
        );
      },
    );
    if (picked != null) {
      // Ch05-F005: anchor at local midnight so DST flips don't push the
      // displayed day around between sessions.
      _updateItemDate(
        index,
        DateTime(picked.year, picked.month, picked.day),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(bulkAddProvider);
    final room = state.currentRoom;
    final items = state.currentRoomItems;
    final progress = (state.currentRoomIndex + 1) / kBulkAddRooms.length;

    return Scaffold(
      backgroundColor: HavenColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _previousRoom,
        ),
        actions: [
          TextButton(
            onPressed: _skipRoom,
            child: const Text(
              'Skip Room',
              style: TextStyle(color: HavenColors.textSecondary),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Room header + progress
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(HavenSpacing.sm),
                      decoration: BoxDecoration(
                        color: HavenColors.primary.withValues(alpha: 0.12),
                        borderRadius:
                            BorderRadius.circular(HavenRadius.button),
                        border: Border.all(
                          color: HavenColors.primary.withValues(alpha: 0.16),
                        ),
                      ),
                      child: Icon(room.icon,
                          size: 22, color: HavenColors.primary),
                    ),
                    const SizedBox(width: HavenSpacing.sm),
                    Expanded(
                      child: Text(
                        room.name,
                        style: HavenText.displayLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: HavenSpacing.xs),
                Text(
                  'Room ${state.currentRoomIndex + 1} of ${kBulkAddRooms.length}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: HavenColors.textSecondary,
                  ),
                ),
                const SizedBox(height: HavenSpacing.sm),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(HavenRadius.micro),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: HavenColors.border,
                    color: HavenColors.primary,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: HavenSpacing.lg),
              ],
            ),
          ),

          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: HavenSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // "Tap what you have"
                  const Text(
                    'Tap what you have:',
                    style: TextStyle(
                      fontSize: 16,
                      color: HavenColors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: HavenSpacing.md),

                  // Appliance grid
                  _buildApplianceGrid(room),

                  // Selected items forms
                  if (items.isNotEmpty) ...[
                    const SizedBox(height: HavenSpacing.lg),
                    Text(
                      'SELECTED (${items.length})',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: HavenColors.textTertiary,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.sm),
                    const Text(
                      'Fill in the basics:',
                      style: TextStyle(
                        fontSize: 14,
                        color: HavenColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: HavenSpacing.md),
                    ...List.generate(items.length, (i) {
                      return _buildItemForm(i, items[i]);
                    }),
                  ],

                  const SizedBox(height: HavenSpacing.lg),
                ],
              ),
            ),
          ),

          // Bottom button
          Padding(
            padding: const EdgeInsets.all(HavenSpacing.md),
            child: SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: _nextRoom,
                child: Text(
                  state.isLastRoom ? 'Finish Setup' : 'Next Room →',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildApplianceGrid(BulkAddRoom room) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: HavenSpacing.sm,
        mainAxisSpacing: HavenSpacing.sm,
        childAspectRatio: 1.0,
      ),
      itemCount: room.appliances.length,
      itemBuilder: (context, index) {
        final appliance = room.appliances[index];
        final selected = _isSelected(appliance);

        return Semantics(
          button: true,
          selected: selected,
          label: appliance.name,
          excludeSemantics: true,
          child: Material(
            color: HavenColors.surfaceElevated,
            borderRadius: BorderRadius.circular(HavenRadius.button),
            child: InkWell(
              onTap: () => _toggleAppliance(appliance),
              borderRadius: BorderRadius.circular(HavenRadius.button),
              child: AnimatedContainer(
                duration: HavenMotion.fast,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(HavenRadius.button),
                  border: Border.all(
                    color: selected
                        ? HavenColors.primary
                        : HavenColors.border,
                    width: selected ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      appliance.icon,
                      size: 26,
                      color: selected
                          ? HavenColors.primary
                          : HavenColors.textSecondary,
                    ),
                    const SizedBox(height: HavenSpacing.xs),
                    Text(
                      appliance.name,
                      textAlign: TextAlign.center,
                      style: HavenText.caption.copyWith(
                        color: selected
                            ? HavenColors.textPrimary
                            : HavenColors.textSecondary,
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                    if (selected) ...[
                      const SizedBox(height: 2),
                      const Icon(
                        Icons.check_circle,
                        size: 16,
                        color: HavenColors.primary,
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildItemForm(int index, BulkAddItem item) {
    // Load brand suggestions for category
    final brandsAsync = ref.watch(brandSuggestionsProvider(item.category));
    final brands = brandsAsync.value ?? [];

    // Controller is only needed for the *no-suggestions* TextFormField
    // branch — and only that one is screen-owned, so only that one gets
    // disposed in [dispose]. The Autocomplete branch manages its own
    // internal controller; we must never store it here (storing it caused
    // a double-dispose: screen disposed it AND Autocomplete's State did).
    // Edits flow to the provider via [_updateItemBrand] in both branches,
    // so re-reading `item.brand` is always the source of truth.
    if (brands.isEmpty && !_brandControllers.containsKey(index)) {
      _brandControllers[index] =
          TextEditingController(text: item.brand ?? '');
    }
    _purchaseDates.putIfAbsent(index, () => item.purchaseDate);
    _warrantyMonths.putIfAbsent(index, () => item.warrantyMonths);

    final date = _purchaseDates[index] ?? item.purchaseDate;
    final warranty = _warrantyMonths[index] ?? item.warrantyMonths;

    return Container(
      margin: const EdgeInsets.only(bottom: HavenSpacing.md),
      padding: const EdgeInsets.all(HavenSpacing.md),
      decoration: BoxDecoration(
        color: HavenColors.surface,
        borderRadius: BorderRadius.circular(HavenRadius.button),
        border: Border.all(color: HavenColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Item header
          Row(
            children: [
              CategoryIcon.widget(item.category, size: 18),
              const SizedBox(width: HavenSpacing.sm),
              Expanded(
                child: Text(
                  item.name,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: HavenColors.textPrimary,
                  ),
                ),
              ),
              // Remove button
              GestureDetector(
                onTap: () async {
                  final confirmed = await showHavenConfirmDialog(
                    context,
                    title: 'Remove ${item.name}?',
                    body: 'This item will be removed from the setup.',
                    confirmLabel: 'Remove',
                    isDestructive: true,
                  );
                  if (confirmed) {
                    // See _toggleAppliance — clear the per-index maps so
                    // the post-removal index shift doesn't alias rows.
                    ref.read(bulkAddProvider.notifier).removeItem(index);
                    _disposeAndClearControllers();
                    _purchaseDates.clear();
                    _warrantyMonths.clear();
                    if (mounted) setState(() {});
                  }
                },
                child: const Icon(
                  Icons.close,
                  size: 18,
                  color: HavenColors.textTertiary,
                ),
              ),
            ],
          ),
          const SizedBox(height: HavenSpacing.md),

          // Brand field
          if (brands.isNotEmpty)
            Autocomplete<String>(
              initialValue: TextEditingValue(text: item.brand ?? ''),
              optionsBuilder: (textEditingValue) {
                if (textEditingValue.text.isEmpty) return brands;
                return brands.where((b) => b
                    .toLowerCase()
                    .contains(textEditingValue.text.toLowerCase()));
              },
              fieldViewBuilder:
                  (context, controller, focusNode, onFieldSubmitted) {
                return TextFormField(
                  controller: controller,
                  focusNode: focusNode,
                  decoration: const InputDecoration(
                    labelText: 'Brand',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: HavenSpacing.sm,
                      vertical: HavenSpacing.sm,
                    ),
                  ),
                  style: HavenText.body,
                  onChanged: (value) => _updateItemBrand(index, value),
                );
              },
              optionsViewBuilder: (context, onSelected, options) {
                return Align(
                  alignment: Alignment.topLeft,
                  child: Material(
                    color: HavenColors.elevated,
                    elevation: 4,
                    borderRadius: BorderRadius.circular(HavenRadius.input),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 200),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (context, i) {
                          final option = options.elementAt(i);
                          return ListTile(
                            dense: true,
                            title: Text(
                              option,
                              style: HavenText.body,
                            ),
                            onTap: () {
                              onSelected(option);
                              _updateItemBrand(index, option);
                            },
                          );
                        },
                      ),
                    ),
                  ),
                );
              },
            )
          else
            TextFormField(
              controller: _brandControllers[index],
              decoration: const InputDecoration(
                labelText: 'Brand',
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: HavenSpacing.sm,
                  vertical: HavenSpacing.sm,
                ),
              ),
              style: HavenText.body,
              onChanged: (value) => _updateItemBrand(index, value),
            ),

          const SizedBox(height: HavenSpacing.sm),

          // Purchase date + Warranty in a row
          Row(
            children: [
              // Purchase date
              Expanded(
                child: GestureDetector(
                  onTap: () => _pickDate(index),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Purchased',
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: HavenSpacing.sm,
                        vertical: HavenSpacing.sm,
                      ),
                    ),
                    child: Text(
                      _formatDate(date),
                      style: HavenText.meta,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: HavenSpacing.sm),
              // Warranty duration
              SizedBox(
                width: 100,
                child: DropdownButtonFormField<int>(
                  initialValue: warranty,
                  isDense: true,
                  decoration: const InputDecoration(
                    labelText: 'Warranty',
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: HavenSpacing.sm,
                      vertical: HavenSpacing.sm,
                    ),
                  ),
                  dropdownColor: HavenColors.elevated,
                  style: HavenText.meta,
                  items: const [
                    DropdownMenuItem(value: 6, child: Text('6 mo')),
                    DropdownMenuItem(value: 12, child: Text('1 yr')),
                    DropdownMenuItem(value: 24, child: Text('2 yr')),
                    DropdownMenuItem(value: 36, child: Text('3 yr')),
                    DropdownMenuItem(value: 60, child: Text('5 yr')),
                    DropdownMenuItem(value: 120, child: Text('10 yr')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      _updateItemWarranty(index, value);
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }
}
