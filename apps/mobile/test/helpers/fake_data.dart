import 'package:shared_models/shared_models.dart';

/// Realistic test fixture data for HavenKeep tests.
///
/// Contains predefined test data that mimics real-world usage patterns.
class FakeData {
  // Common appliance brands by category
  static const Map<ItemCategory, List<String>> brandsByCategory = {
    ItemCategory.refrigerator: ['Samsung', 'LG', 'Whirlpool', 'GE', 'Frigidaire'],
    ItemCategory.dishwasher: ['Bosch', 'KitchenAid', 'Whirlpool', 'GE', 'LG'],
    ItemCategory.washer: ['Maytag', 'LG', 'Samsung', 'Whirlpool', 'GE'],
    ItemCategory.dryer: ['Maytag', 'LG', 'Samsung', 'Whirlpool', 'GE'],
    ItemCategory.oven_range: ['GE', 'Whirlpool', 'Frigidaire', 'Samsung', 'LG'],
    ItemCategory.microwave: ['Panasonic', 'GE', 'Samsung', 'LG', 'Sharp'],
    ItemCategory.hvac: ['Carrier', 'Trane', 'Lennox', 'Rheem', 'Bryant'],
    ItemCategory.water_heater: ['Rheem', 'AO Smith', 'Bradford White', 'State', 'Rinnai'],
    ItemCategory.tv: ['Samsung', 'LG', 'Sony', 'TCL', 'Vizio'],
  };

  // Common stores
  static const List<String> stores = [
    'Home Depot',
    'Lowe\'s',
    'Best Buy',
    'Costco',
    'Amazon',
    'Sears',
    'Local Appliance Store',
  ];

  // Sample item names with realistic model numbers
  static const Map<ItemCategory, Map<String, String>> sampleItems = {
    ItemCategory.refrigerator: {
      'Samsung French Door': 'RF28R7351SR',
      'LG Side-by-Side': 'LRSDS2706S',
      'Whirlpool Top Freezer': 'WRT518SZFM',
    },
    ItemCategory.dishwasher: {
      'Bosch 800 Series': 'SHPM88Z75N',
      'KitchenAid Built-In': 'KDTM404KPS',
      'Whirlpool Stainless': 'WDT750SAKZ',
    },
    ItemCategory.washer: {
      'Maytag Front Load': 'MHW6630HC',
      'LG TurboWash': 'WM9000HVA',
      'Samsung AddWash': 'WF45R6100AP',
    },
    ItemCategory.hvac: {
      'Carrier Infinity': '24VNA0',
      'Trane XV20i': 'XV20',
      'Lennox Elite': 'EL16XC1',
    },
  };

  // Realistic warranty durations by category (in months)
  static const Map<ItemCategory, int> warrantyMonthsByCategory = {
    ItemCategory.refrigerator: 12,
    ItemCategory.dishwasher: 12,
    ItemCategory.washer: 12,
    ItemCategory.dryer: 12,
    ItemCategory.oven_range: 12,
    ItemCategory.microwave: 12,
    ItemCategory.hvac: 60, // 5 years
    ItemCategory.water_heater: 72, // 6 years
    ItemCategory.tv: 12,
    ItemCategory.roofing: 300, // 25 years
    ItemCategory.windows: 240, // 20 years
  };

  // Realistic price ranges by category (min, max in USD)
  static const Map<ItemCategory, (double, double)> priceRanges = {
    ItemCategory.refrigerator: (800, 3500),
    ItemCategory.dishwasher: (400, 1500),
    ItemCategory.washer: (600, 2000),
    ItemCategory.dryer: (500, 1800),
    ItemCategory.oven_range: (600, 3000),
    ItemCategory.microwave: (100, 500),
    ItemCategory.hvac: (3000, 10000),
    ItemCategory.water_heater: (400, 2500),
    ItemCategory.tv: (300, 3000),
  };

  /// Returns a realistic brand for a given category.
  static String getBrandFor(ItemCategory category) {
    final brands = brandsByCategory[category];
    if (brands == null || brands.isEmpty) return 'Generic';
    return brands[0]; // Return first brand as default
  }

  /// Returns a realistic warranty duration for a given category.
  static int getWarrantyMonthsFor(ItemCategory category) {
    return warrantyMonthsByCategory[category] ?? 12;
  }

  /// Returns a realistic price for a given category.
  static double getPriceFor(ItemCategory category) {
    final range = priceRanges[category];
    if (range == null) return 500.0;
    // Return midpoint of range
    return (range.$1 + range.$2) / 2;
  }

  /// Returns a sample item name and model number for a category.
  static (String name, String model)? getSampleItemFor(ItemCategory category) {
    final items = sampleItems[category];
    if (items == null || items.isEmpty) return null;
    final entry = items.entries.first;
    return (entry.key, entry.value);
  }
}
