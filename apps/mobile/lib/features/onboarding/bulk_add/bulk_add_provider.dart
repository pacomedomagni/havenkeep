import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences key for the bulk-add walkthrough's resume cursor.
/// Lets a user re-launch mid-setup and pick up at the same room
/// (Ch05-F081). Cleared on `reset()` and on the success branch of
/// `BulkAddCompleteScreen`.
const kOnboardingStepKey = 'onboarding_step';

/// Data class for a single item being added during bulk setup.
class BulkAddItem {
  final String name;
  final ItemCategory category;
  final ItemRoom room;
  final String? brand;
  final DateTime purchaseDate;
  final int warrantyMonths;
  final bool isCustom;

  const BulkAddItem({
    required this.name,
    required this.category,
    required this.room,
    this.brand,
    required this.purchaseDate,
    this.warrantyMonths = 12,
    this.isCustom = false,
  });

  BulkAddItem copyWith({
    String? name,
    ItemCategory? category,
    ItemRoom? room,
    String? brand,
    bool clearBrand = false,
    DateTime? purchaseDate,
    int? warrantyMonths,
    bool? isCustom,
  }) {
    return BulkAddItem(
      name: name ?? this.name,
      category: category ?? this.category,
      room: room ?? this.room,
      brand: clearBrand ? null : (brand ?? this.brand),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      isCustom: isCustom ?? this.isCustom,
    );
  }
}

/// Definition of a room in the bulk-add walkthrough.
class BulkAddRoom {
  final String name;
  final String icon;
  final ItemRoom room;
  final List<BulkAddAppliance> appliances;

  const BulkAddRoom({
    required this.name,
    required this.icon,
    required this.room,
    required this.appliances,
  });
}

/// An appliance option that can be selected in a room.
class BulkAddAppliance {
  final String name;
  final String icon;
  final ItemCategory category;
  final int defaultWarrantyMonths;

  const BulkAddAppliance({
    required this.name,
    required this.icon,
    required this.category,
    this.defaultWarrantyMonths = 12,
  });
}

/// The 6 rooms with their appliance options.
const kBulkAddRooms = <BulkAddRoom>[
  BulkAddRoom(
    name: 'Kitchen',
    icon: '🍳',
    room: ItemRoom.kitchen,
    appliances: [
      BulkAddAppliance(
        name: 'Refrigerator',
        icon: '🧊',
        category: ItemCategory.refrigerator,
      ),
      BulkAddAppliance(
        name: 'Dishwasher',
        icon: '🍽️',
        category: ItemCategory.dishwasher,
      ),
      BulkAddAppliance(
        name: 'Oven / Range',
        icon: '🔥',
        category: ItemCategory.oven_range,
      ),
      BulkAddAppliance(
        name: 'Microwave',
        icon: '📡',
        category: ItemCategory.microwave,
      ),
      BulkAddAppliance(
        name: 'Garbage Disposal',
        icon: '♻️',
        category: ItemCategory.garbage_disposal,
      ),
      BulkAddAppliance(
        name: 'Range Hood',
        icon: '🌬️',
        category: ItemCategory.range_hood,
      ),
    ],
  ),
  BulkAddRoom(
    name: 'Laundry',
    icon: '👕',
    room: ItemRoom.laundry,
    appliances: [
      BulkAddAppliance(
        name: 'Washer',
        icon: '👕',
        category: ItemCategory.washer,
      ),
      BulkAddAppliance(
        name: 'Dryer',
        icon: '💨',
        category: ItemCategory.dryer,
      ),
    ],
  ),
  BulkAddRoom(
    name: 'HVAC / Utility',
    icon: '❄️',
    room: ItemRoom.hvac_utility,
    appliances: [
      BulkAddAppliance(
        name: 'A/C Unit',
        icon: '❄️',
        category: ItemCategory.hvac,
        defaultWarrantyMonths: 60,
      ),
      BulkAddAppliance(
        name: 'Furnace',
        icon: '🔥',
        category: ItemCategory.furnace,
        defaultWarrantyMonths: 60,
      ),
      BulkAddAppliance(
        name: 'Water Heater',
        icon: '🚿',
        category: ItemCategory.water_heater,
        defaultWarrantyMonths: 60,
      ),
      BulkAddAppliance(
        name: 'Water Softener',
        icon: '💧',
        category: ItemCategory.water_softener,
        defaultWarrantyMonths: 24,
      ),
      BulkAddAppliance(
        name: 'Sump Pump',
        icon: '🌊',
        category: ItemCategory.sump_pump,
        defaultWarrantyMonths: 24,
      ),
    ],
  ),
  BulkAddRoom(
    name: 'Bathroom',
    icon: '🚿',
    room: ItemRoom.bathroom,
    appliances: [
      BulkAddAppliance(
        name: 'Toilet',
        icon: '🚽',
        category: ItemCategory.plumbing,
      ),
      BulkAddAppliance(
        name: 'Faucet',
        icon: '🚰',
        category: ItemCategory.plumbing,
      ),
      BulkAddAppliance(
        name: 'Exhaust Fan',
        icon: '🌀',
        category: ItemCategory.electrical,
      ),
    ],
  ),
  BulkAddRoom(
    name: 'Living Areas',
    icon: '🛋️',
    room: ItemRoom.living_room,
    appliances: [
      BulkAddAppliance(
        name: 'TV',
        icon: '📺',
        category: ItemCategory.tv,
      ),
      BulkAddAppliance(
        name: 'Smart Home Hub',
        icon: '🏠',
        category: ItemCategory.smart_home,
      ),
      BulkAddAppliance(
        name: 'Fireplace',
        icon: '🔥',
        category: ItemCategory.furniture,
      ),
    ],
  ),
  BulkAddRoom(
    name: 'Garage',
    icon: '🏗️',
    room: ItemRoom.garage,
    appliances: [
      BulkAddAppliance(
        name: 'Garage Door Opener',
        icon: '🚪',
        category: ItemCategory.doors,
      ),
      BulkAddAppliance(
        name: 'Chest Freezer',
        icon: '🧊',
        category: ItemCategory.other,
      ),
      BulkAddAppliance(
        name: 'Power Tools',
        icon: '⚡',
        category: ItemCategory.electrical,
      ),
    ],
  ),
];

/// State for the bulk-add flow.
class BulkAddState {
  final String? homeId;
  final int currentRoomIndex;
  final Map<int, List<BulkAddItem>> roomSelections;

  const BulkAddState({
    this.homeId,
    this.currentRoomIndex = 0,
    this.roomSelections = const {},
  });

  /// Total items selected across all rooms.
  int get totalItemCount =>
      roomSelections.values.fold(0, (sum, items) => sum + items.length);

  /// Number of rooms that have at least one item selected.
  int get roomsWithItemsCount =>
      roomSelections.values.where((items) => items.isNotEmpty).length;

  /// Summary of items per room (room name → count), only non-empty rooms.
  Map<String, int> get roomSummary {
    final summary = <String, int>{};
    for (final entry in roomSelections.entries) {
      if (entry.value.isNotEmpty) {
        final room = kBulkAddRooms[entry.key];
        summary['${room.icon} ${room.name}'] = entry.value.length;
      }
    }
    return summary;
  }

  /// All items flattened.
  List<BulkAddItem> get allItems =>
      roomSelections.values.expand((items) => items).toList();

  /// Whether the current room is the last one.
  bool get isLastRoom => currentRoomIndex >= kBulkAddRooms.length - 1;

  /// Current room definition.
  BulkAddRoom get currentRoom => kBulkAddRooms[currentRoomIndex];

  /// Items selected for the current room.
  List<BulkAddItem> get currentRoomItems =>
      roomSelections[currentRoomIndex] ?? [];

  BulkAddState copyWith({
    String? homeId,
    int? currentRoomIndex,
    Map<int, List<BulkAddItem>>? roomSelections,
  }) {
    return BulkAddState(
      homeId: homeId ?? this.homeId,
      currentRoomIndex: currentRoomIndex ?? this.currentRoomIndex,
      roomSelections: roomSelections ?? this.roomSelections,
    );
  }
}

/// Notifier for the bulk-add flow state.
class BulkAddNotifier extends StateNotifier<BulkAddState> {
  BulkAddNotifier() : super(const BulkAddState()) {
    _restoreStep();
  }

  /// Restore the persisted room cursor so a user re-launching the app
  /// mid-walkthrough lands back where they left off (Ch05-F081). The
  /// per-room item selections themselves stay in memory; we don't
  /// re-hydrate those because they'd race with whatever bulk_add
  /// already committed and we'd risk doubling up server-side.
  Future<void> _restoreStep() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getInt(kOnboardingStepKey);
      if (saved == null) return;
      if (saved <= 0 || saved >= kBulkAddRooms.length) return;
      // Don't clobber an already-progressed in-memory state.
      if (state.currentRoomIndex != 0) return;
      state = state.copyWith(currentRoomIndex: saved);
    } catch (_) {
      // Prefs unavailable (e.g. tests without binding) — fall back to
      // starting at the first room.
    }
  }

  Future<void> _persistStep(int index) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (index <= 0) {
        await prefs.remove(kOnboardingStepKey);
      } else {
        await prefs.setInt(kOnboardingStepKey, index);
      }
    } catch (_) {
      // Best-effort persistence; nothing depends on the write.
    }
  }

  /// Set the home ID after creating the home.
  void setHomeId(String homeId) {
    state = state.copyWith(homeId: homeId);
  }

  /// Add an item to the current room.
  void addItem(BulkAddItem item) {
    final currentItems =
        List<BulkAddItem>.from(state.currentRoomItems);
    currentItems.add(item);
    final selections = Map<int, List<BulkAddItem>>.from(state.roomSelections);
    selections[state.currentRoomIndex] = currentItems;
    state = state.copyWith(roomSelections: selections);
  }

  /// Remove an item from the current room by index.
  void removeItem(int index) {
    final currentItems =
        List<BulkAddItem>.from(state.currentRoomItems);
    if (index >= 0 && index < currentItems.length) {
      currentItems.removeAt(index);
    }
    final selections = Map<int, List<BulkAddItem>>.from(state.roomSelections);
    selections[state.currentRoomIndex] = currentItems;
    state = state.copyWith(roomSelections: selections);
  }

  /// Update an item in the current room by index.
  void updateItem(int index, BulkAddItem item) {
    final currentItems =
        List<BulkAddItem>.from(state.currentRoomItems);
    if (index >= 0 && index < currentItems.length) {
      currentItems[index] = item;
    }
    final selections = Map<int, List<BulkAddItem>>.from(state.roomSelections);
    selections[state.currentRoomIndex] = currentItems;
    state = state.copyWith(roomSelections: selections);
  }

  /// Move to the next room.
  void nextRoom() {
    if (!state.isLastRoom) {
      final next = state.currentRoomIndex + 1;
      state = state.copyWith(currentRoomIndex: next);
      _persistStep(next);
    }
  }

  /// Move to the previous room.
  void previousRoom() {
    if (state.currentRoomIndex > 0) {
      final next = state.currentRoomIndex - 1;
      state = state.copyWith(currentRoomIndex: next);
      _persistStep(next);
    }
  }

  /// Reset the entire state.
  void reset() {
    state = const BulkAddState();
    // Wipe the persisted resume cursor too so the next visit starts
    // from room 0 instead of the last completed room.
    _persistStep(0);
  }
}

/// Provider for the bulk-add flow.
final bulkAddProvider =
    StateNotifierProvider<BulkAddNotifier, BulkAddState>((ref) {
  return BulkAddNotifier();
});
