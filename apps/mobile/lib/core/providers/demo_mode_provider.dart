import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Provider for demo mode state.
final demoModeProvider = StateNotifierProvider<DemoModeNotifier, DemoModeState>(
  (ref) => DemoModeNotifier(),
);

/// Demo mode state.
class DemoModeState {
  final bool isEnabled;
  final List<Item> demoItems;
  final Home? demoHome;

  const DemoModeState({
    required this.isEnabled,
    required this.demoItems,
    this.demoHome,
  });

  DemoModeState copyWith({
    bool? isEnabled,
    List<Item>? demoItems,
    Home? demoHome,
  }) {
    return DemoModeState(
      isEnabled: isEnabled ?? this.isEnabled,
      demoItems: demoItems ?? this.demoItems,
      demoHome: demoHome ?? this.demoHome,
    );
  }
}

/// Manages demo mode state and data.
class DemoModeNotifier extends StateNotifier<DemoModeState> {
  DemoModeNotifier()
      : super(const DemoModeState(
          isEnabled: false,
          demoItems: [],
        ));

  /// Enters demo mode with pre-populated sample data.
  void enterDemoMode() {
    final now = DateTime.now();

    // Create demo home
    final demoHome = Home(
      id: 'demo-home',
      name: 'My Home',
      userId: 'demo-user',
      createdAt: now.subtract(const Duration(days: 365)),
      updatedAt: now,
    );

    // Create realistic demo items
    final demoItems = [
      // Recently added - active warranty
      Item(
        id: 'demo-item-1',
        name: 'Samsung Refrigerator',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.refrigerator,
        brand: 'Samsung',
        modelNumber: 'RF28R7351SR',
        purchaseDate: now.subtract(const Duration(days: 45)),
        price: 2899.99,
        store: 'Best Buy',
        warrantyMonths: 12,
        warrantyType: WarrantyType.manufacturer,
        room: ItemRoom.kitchen,
        createdAt: now.subtract(const Duration(days: 45)),
        updatedAt: now.subtract(const Duration(days: 45)),
      ),

      // Expiring soon
      Item(
        id: 'demo-item-2',
        name: 'MacBook Pro 16"',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.computer,
        brand: 'Apple',
        modelNumber: 'MK1E3LL/A',
        purchaseDate: now.subtract(const Duration(days: 300)),
        price: 2499.00,
        store: 'Apple Store',
        warrantyMonths: 12,
        warrantyType: WarrantyType.manufacturer,
        room: ItemRoom.office,
        notes: 'Space Gray, 32GB RAM, 1TB SSD',
        createdAt: now.subtract(const Duration(days: 300)),
        updatedAt: now.subtract(const Duration(days: 300)),
      ),

      // Extended warranty
      Item(
        id: 'demo-item-3',
        name: 'LG OLED TV 65"',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.tv,
        brand: 'LG',
        modelNumber: 'OLED65C2PUA',
        purchaseDate: now.subtract(const Duration(days: 180)),
        price: 1899.99,
        store: 'Costco',
        warrantyMonths: 36,
        warrantyType: WarrantyType.extended,
        warrantyProvider: 'SquareTrade',
        room: ItemRoom.living_room,
        createdAt: now.subtract(const Duration(days: 180)),
        updatedAt: now.subtract(const Duration(days: 180)),
      ),

      // Active warranty - kitchen
      Item(
        id: 'demo-item-4',
        name: 'KitchenAid Stand Mixer',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.other,
        brand: 'KitchenAid',
        modelNumber: 'KSM150PSER',
        purchaseDate: now.subtract(const Duration(days: 120)),
        price: 379.99,
        store: 'Williams Sonoma',
        warrantyMonths: 12,
        warrantyType: WarrantyType.manufacturer,
        room: ItemRoom.kitchen,
        createdAt: now.subtract(const Duration(days: 120)),
        updatedAt: now.subtract(const Duration(days: 120)),
      ),

      // Recently expired
      Item(
        id: 'demo-item-5',
        name: 'Dyson V11 Vacuum',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.other,
        brand: 'Dyson',
        modelNumber: 'SV14',
        purchaseDate: now.subtract(const Duration(days: 400)),
        price: 599.99,
        store: 'Target',
        warrantyMonths: 24,
        warrantyType: WarrantyType.manufacturer,
        room: ItemRoom.hvac_utility,
        createdAt: now.subtract(const Duration(days: 400)),
        updatedAt: now.subtract(const Duration(days: 400)),
      ),

      // Active warranty - bedroom
      Item(
        id: 'demo-item-6',
        name: 'Purple Mattress King',
        homeId: demoHome.id,
        userId: 'demo-user',
        category: ItemCategory.furniture,
        brand: 'Purple',
        purchaseDate: now.subtract(const Duration(days: 200)),
        price: 1799.00,
        store: 'Purple.com',
        warrantyMonths: 120, // 10 year warranty
        warrantyType: WarrantyType.manufacturer,
        room: ItemRoom.bedroom,
        createdAt: now.subtract(const Duration(days: 200)),
        updatedAt: now.subtract(const Duration(days: 200)),
      ),
    ];

    state = DemoModeState(
      isEnabled: true,
      demoItems: demoItems,
      demoHome: demoHome,
    );
  }

  /// Exits demo mode and clears demo data.
  void exitDemoMode() {
    state = const DemoModeState(
      isEnabled: false,
      demoItems: [],
    );
  }

  /// Gets demo stats for dashboard.
  DemoStats getStats() {
    if (!state.isEnabled) {
      return const DemoStats(
        totalItems: 0,
        totalValue: 0,
        activeWarranties: 0,
        expiringWarranties: 0,
        warrantyHealth: 0,
      );
    }

    final items = state.demoItems;
    final totalValue = items.fold<double>(
      0,
      (sum, item) => sum + (item.price ?? 0),
    );

    final active = items.where((i) {
      return i.computedWarrantyStatus == WarrantyStatus.active;
    }).length;

    final expiring = items.where((i) {
      return i.computedWarrantyStatus == WarrantyStatus.expiring;
    }).length;

    final expired = items.where((i) {
      return i.computedWarrantyStatus == WarrantyStatus.expired;
    }).length;

    // Warranty health = (active + expiring) / total
    final totalWithWarranty = active + expiring + expired;
    final warrantyHealth = totalWithWarranty > 0
        ? ((active + expiring) / totalWithWarranty * 100).round()
        : 0;

    return DemoStats(
      totalItems: items.length,
      totalValue: totalValue,
      activeWarranties: active,
      expiringWarranties: expiring,
      warrantyHealth: warrantyHealth,
    );
  }
}

/// Demo dashboard statistics.
class DemoStats {
  final int totalItems;
  final double totalValue;
  final int activeWarranties;
  final int expiringWarranties;
  final int warrantyHealth;

  const DemoStats({
    required this.totalItems,
    required this.totalValue,
    required this.activeWarranties,
    required this.expiringWarranties,
    required this.warrantyHealth,
  });
}
