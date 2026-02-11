/// HavenKeep enum definitions.
///
/// All enum values use snake_case to match database column values exactly.
/// Dart's `.name` property returns the snake_case string automatically.

// ============================================
// ITEM CATEGORY
// ============================================

enum ItemCategory {
  refrigerator,
  dishwasher,
  washer,
  dryer,
  oven_range,
  microwave,
  garbage_disposal,
  range_hood,
  hvac,
  water_heater,
  furnace,
  water_softener,
  sump_pump,
  tv,
  computer,
  smart_home,
  roofing,
  windows,
  doors,
  flooring,
  plumbing,
  electrical,
  furniture,
  other;

  factory ItemCategory.fromJson(String value) {
    return ItemCategory.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ItemCategory.other,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ItemCategory.refrigerator => 'Refrigerator',
        ItemCategory.dishwasher => 'Dishwasher',
        ItemCategory.washer => 'Washer',
        ItemCategory.dryer => 'Dryer',
        ItemCategory.oven_range => 'Oven / Range',
        ItemCategory.microwave => 'Microwave',
        ItemCategory.garbage_disposal => 'Garbage Disposal',
        ItemCategory.range_hood => 'Range Hood',
        ItemCategory.hvac => 'HVAC',
        ItemCategory.water_heater => 'Water Heater',
        ItemCategory.furnace => 'Furnace',
        ItemCategory.water_softener => 'Water Softener',
        ItemCategory.sump_pump => 'Sump Pump',
        ItemCategory.tv => 'TV',
        ItemCategory.computer => 'Computer',
        ItemCategory.smart_home => 'Smart Home',
        ItemCategory.roofing => 'Roofing',
        ItemCategory.windows => 'Windows',
        ItemCategory.doors => 'Doors',
        ItemCategory.flooring => 'Flooring',
        ItemCategory.plumbing => 'Plumbing',
        ItemCategory.electrical => 'Electrical',
        ItemCategory.furniture => 'Furniture',
        ItemCategory.other => 'Other',
      };
}

// ============================================
// ITEM ROOM
// ============================================

enum ItemRoom {
  kitchen,
  bathroom,
  master_bedroom,
  bedroom,
  living_room,
  dining_room,
  laundry,
  garage,
  basement,
  attic,
  outdoor,
  hvac_utility,
  office,
  other;

  factory ItemRoom.fromJson(String value) {
    return ItemRoom.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ItemRoom.other,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ItemRoom.kitchen => 'Kitchen',
        ItemRoom.bathroom => 'Bathroom',
        ItemRoom.master_bedroom => 'Master Bedroom',
        ItemRoom.bedroom => 'Bedroom',
        ItemRoom.living_room => 'Living Room',
        ItemRoom.dining_room => 'Dining Room',
        ItemRoom.laundry => 'Laundry',
        ItemRoom.garage => 'Garage',
        ItemRoom.basement => 'Basement',
        ItemRoom.attic => 'Attic',
        ItemRoom.outdoor => 'Outdoor',
        ItemRoom.hvac_utility => 'HVAC / Utility',
        ItemRoom.office => 'Office',
        ItemRoom.other => 'Other',
      };
}

// ============================================
// WARRANTY TYPE
// ============================================

enum WarrantyType {
  manufacturer,
  extended,
  store,
  home_warranty;

  factory WarrantyType.fromJson(String value) {
    return WarrantyType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WarrantyType.manufacturer,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        WarrantyType.manufacturer => 'Manufacturer',
        WarrantyType.extended => 'Extended',
        WarrantyType.store => 'Store',
        WarrantyType.home_warranty => 'Home Warranty',
      };
}

// ============================================
// WARRANTY STATUS (computed, not stored)
// ============================================

enum WarrantyStatus {
  active,
  expiring,
  expired;

  factory WarrantyStatus.fromJson(String value) {
    return WarrantyStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => WarrantyStatus.active,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        WarrantyStatus.active => 'Active',
        WarrantyStatus.expiring => 'Expiring Soon',
        WarrantyStatus.expired => 'Expired',
      };
}

// ============================================
// AUTH PROVIDER
// ============================================

enum AuthProvider {
  email,
  google,
  apple;

  factory AuthProvider.fromJson(String value) {
    return AuthProvider.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AuthProvider.email,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        AuthProvider.email => 'Email',
        AuthProvider.google => 'Google',
        AuthProvider.apple => 'Apple',
      };
}

// ============================================
// USER PLAN
// ============================================

enum UserPlan {
  free,
  premium;

  factory UserPlan.fromJson(String value) {
    return UserPlan.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UserPlan.free,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        UserPlan.free => 'Free',
        UserPlan.premium => 'Premium',
      };
}

// ============================================
// HOME TYPE
// ============================================

enum HomeType {
  house,
  condo,
  apartment,
  townhouse,
  other;

  factory HomeType.fromJson(String value) {
    return HomeType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => HomeType.other,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        HomeType.house => 'House',
        HomeType.condo => 'Condo',
        HomeType.apartment => 'Apartment',
        HomeType.townhouse => 'Townhouse',
        HomeType.other => 'Other',
      };
}

// ============================================
// DOCUMENT TYPE
// ============================================

enum DocumentType {
  receipt,
  warranty_card,
  manual,
  invoice,
  other;

  factory DocumentType.fromJson(String value) {
    return DocumentType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => DocumentType.other,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        DocumentType.receipt => 'Receipt',
        DocumentType.warranty_card => 'Warranty Card',
        DocumentType.manual => 'Manual',
        DocumentType.invoice => 'Invoice',
        DocumentType.other => 'Other',
      };
}

// ============================================
// NOTIFICATION TYPE
// ============================================

enum NotificationType {
  warranty_expiring,
  warranty_expired,
  item_added,
  warranty_extended,
  tip,
  system;

  factory NotificationType.fromJson(String value) {
    return NotificationType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationType.system,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        NotificationType.warranty_expiring => 'Warranty Expiring',
        NotificationType.warranty_expired => 'Warranty Expired',
        NotificationType.item_added => 'Item Added',
        NotificationType.warranty_extended => 'Warranty Extended',
        NotificationType.tip => 'Tip',
        NotificationType.system => 'System',
      };
}

// ============================================
// NOTIFICATION ACTION
// ============================================

enum NotificationAction {
  view_item,
  get_protection,
  find_repair;

  factory NotificationAction.fromJson(String value) {
    return NotificationAction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => NotificationAction.view_item,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        NotificationAction.view_item => 'View Item',
        NotificationAction.get_protection => 'Get Protection',
        NotificationAction.find_repair => 'Find Repair',
      };
}

// ============================================
// PARTNER TYPE
// ============================================

enum PartnerType {
  realtor,
  builder,
  other;

  factory PartnerType.fromJson(String value) {
    return PartnerType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => PartnerType.other,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        PartnerType.realtor => 'Realtor',
        PartnerType.builder => 'Builder',
        PartnerType.other => 'Other',
      };
}

// ============================================
// REFERRAL SOURCE
// ============================================

enum ReferralSource {
  realtor,
  builder,
  user_invite;

  factory ReferralSource.fromJson(String value) {
    return ReferralSource.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ReferralSource.realtor,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ReferralSource.realtor => 'Realtor',
        ReferralSource.builder => 'Builder',
        ReferralSource.user_invite => 'User Invite',
      };
}

// ============================================
// CONVERSION TYPE
// ============================================

enum ConversionType {
  extended_warranty,
  repair_referral,
  premium_sub;

  factory ConversionType.fromJson(String value) {
    return ConversionType.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConversionType.extended_warranty,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ConversionType.extended_warranty => 'Extended Warranty',
        ConversionType.repair_referral => 'Repair Referral',
        ConversionType.premium_sub => 'Premium Subscription',
      };
}

// ============================================
// CONVERSION STATUS
// ============================================

enum ConversionStatus {
  pending,
  confirmed,
  paid;

  factory ConversionStatus.fromJson(String value) {
    return ConversionStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ConversionStatus.pending,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ConversionStatus.pending => 'Pending',
        ConversionStatus.confirmed => 'Confirmed',
        ConversionStatus.paid => 'Paid',
      };
}

// ============================================
// ITEM ADDED VIA
// ============================================

enum ItemAddedVia {
  quick_add,
  receipt_scan,
  barcode_scan,
  manual,
  bulk_setup;

  factory ItemAddedVia.fromJson(String value) {
    return ItemAddedVia.values.firstWhere(
      (e) => e.name == value,
      orElse: () => ItemAddedVia.manual,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        ItemAddedVia.quick_add => 'Quick Add',
        ItemAddedVia.receipt_scan => 'Receipt Scan',
        ItemAddedVia.barcode_scan => 'Barcode Scan',
        ItemAddedVia.manual => 'Manual Entry',
        ItemAddedVia.bulk_setup => 'Bulk Setup',
      };
}

// ============================================
// OFFLINE ACTION
// ============================================

enum OfflineAction {
  create_item,
  update_item,
  delete_item,
  create_document,
  update_preferences;

  factory OfflineAction.fromJson(String value) {
    return OfflineAction.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OfflineAction.create_item,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        OfflineAction.create_item => 'Create Item',
        OfflineAction.update_item => 'Update Item',
        OfflineAction.delete_item => 'Delete Item',
        OfflineAction.create_document => 'Create Document',
        OfflineAction.update_preferences => 'Update Preferences',
      };
}

// ============================================
// OFFLINE STATUS
// ============================================

enum OfflineStatus {
  pending,
  synced,
  failed;

  factory OfflineStatus.fromJson(String value) {
    return OfflineStatus.values.firstWhere(
      (e) => e.name == value,
      orElse: () => OfflineStatus.pending,
    );
  }

  String toJson() => name;

  String get displayLabel => switch (this) {
        OfflineStatus.pending => 'Pending',
        OfflineStatus.synced => 'Synced',
        OfflineStatus.failed => 'Failed',
      };
}
