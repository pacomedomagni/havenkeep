import 'enums.dart';

/// A tracked item (appliance, system, etc.) with warranty information.
class Item {
  final String id;
  final String homeId;
  final String userId;

  // Product info
  final String name;
  final String? brand;
  final String? modelNumber;
  final String? serialNumber;
  final ItemCategory category;
  final ItemRoom? room;
  final String? productImageUrl;
  final String? barcode;

  // Purchase info
  final DateTime purchaseDate;
  final String? store;
  final double? price;

  // Warranty info
  final int warrantyMonths;
  final DateTime? warrantyEndDate; // GENERATED column — read-only from DB
  final WarrantyType warrantyType;
  final String? warrantyProvider;

  // Computed (from views, not stored in items table)
  final WarrantyStatus? warrantyStatus;
  final int? daysRemaining;

  // Meta
  final String? notes;
  final bool isArchived;
  final ItemAddedVia addedVia;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Item({
    required this.id,
    required this.homeId,
    required this.userId,
    required this.name,
    this.brand,
    this.modelNumber,
    this.serialNumber,
    this.category = ItemCategory.other,
    this.room,
    this.productImageUrl,
    this.barcode,
    required this.purchaseDate,
    this.store,
    this.price,
    this.warrantyMonths = 12,
    this.warrantyEndDate,
    this.warrantyType = WarrantyType.manufacturer,
    this.warrantyProvider,
    this.warrantyStatus,
    this.daysRemaining,
    this.notes,
    this.isArchived = false,
    this.addedVia = ItemAddedVia.manual,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String,
      homeId: json['home_id'] as String,
      userId: json['user_id'] as String,
      name: json['name'] as String,
      brand: json['brand'] as String?,
      modelNumber: json['model_number'] as String?,
      serialNumber: json['serial_number'] as String?,
      category: ItemCategory.fromJson(json['category'] as String),
      room: json['room'] != null
          ? ItemRoom.fromJson(json['room'] as String)
          : null,
      productImageUrl: json['product_image_url'] as String?,
      barcode: json['barcode'] as String?,
      purchaseDate: DateTime.parse(json['purchase_date'] as String),
      store: json['store'] as String?,
      price: json['price'] != null ? (json['price'] as num).toDouble() : null,
      warrantyMonths: json['warranty_months'] as int? ?? 12,
      warrantyEndDate: json['warranty_end_date'] != null
          ? DateTime.parse(json['warranty_end_date'] as String)
          : null,
      warrantyType: json['warranty_type'] != null
          ? WarrantyType.fromJson(json['warranty_type'] as String)
          : WarrantyType.manufacturer,
      warrantyProvider: json['warranty_provider'] as String?,
      warrantyStatus: json['warranty_status'] != null
          ? WarrantyStatus.fromJson(json['warranty_status'] as String)
          : null,
      daysRemaining: json['days_remaining'] as int?,
      notes: json['notes'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
      addedVia: json['added_via'] != null
          ? ItemAddedVia.fromJson(json['added_via'] as String)
          : ItemAddedVia.manual,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  /// Full JSON for reads / updates.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'home_id': homeId,
      'user_id': userId,
      'name': name,
      'brand': brand,
      'model_number': modelNumber,
      'serial_number': serialNumber,
      'category': category.toJson(),
      'room': room?.toJson(),
      'product_image_url': productImageUrl,
      'barcode': barcode,
      'purchase_date': purchaseDate.toIso8601String().split('T').first,
      'store': store,
      'price': price,
      'warranty_months': warrantyMonths,
      // warranty_end_date is GENERATED — don't send on insert/update
      'warranty_type': warrantyType.toJson(),
      'warranty_provider': warrantyProvider,
      'notes': notes,
      'is_archived': isArchived,
      'added_via': addedVia.toJson(),
    };
  }

  /// JSON for inserts — excludes generated/read-only columns.
  Map<String, dynamic> toInsertJson() {
    final json = toJson();
    json.remove('id'); // Let DB generate UUID
    return json;
  }

  /// Compute the warranty end date using proper month arithmetic
  /// matching the server's calculation (avoids 30-day-per-month approximation).
  DateTime get computedEndDate => _computedEndDate;

  DateTime get _computedEndDate {
    if (warrantyEndDate != null) return warrantyEndDate!;
    var year = purchaseDate.year;
    var month = purchaseDate.month + warrantyMonths;
    var day = purchaseDate.day;
    // Normalize month overflow
    year += (month - 1) ~/ 12;
    month = ((month - 1) % 12) + 1;
    // Clamp day to last day of target month
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day > lastDay) day = lastDay;
    return DateTime(year, month, day);
  }

  /// Compute warranty status client-side (when not using the view).
  WarrantyStatus get computedWarrantyStatus {
    if (warrantyStatus != null) return warrantyStatus!;

    final endDate = _computedEndDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (endDate.isBefore(today)) return WarrantyStatus.expired;
    if (endDate.difference(today).inDays <= 90) return WarrantyStatus.expiring;
    return WarrantyStatus.active;
  }

  /// Compute days remaining client-side.
  int get computedDaysRemaining {
    if (daysRemaining != null) return daysRemaining!;

    final endDate = _computedEndDate;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return endDate.difference(today).inDays;
  }

  Item copyWith({
    String? id,
    String? homeId,
    String? userId,
    String? name,
    String? brand,
    bool clearBrand = false,
    String? modelNumber,
    bool clearModelNumber = false,
    String? serialNumber,
    bool clearSerialNumber = false,
    ItemCategory? category,
    ItemRoom? room,
    bool clearRoom = false,
    String? productImageUrl,
    bool clearProductImageUrl = false,
    String? barcode,
    bool clearBarcode = false,
    DateTime? purchaseDate,
    String? store,
    bool clearStore = false,
    double? price,
    bool clearPrice = false,
    int? warrantyMonths,
    DateTime? warrantyEndDate,
    WarrantyType? warrantyType,
    String? warrantyProvider,
    bool clearWarrantyProvider = false,
    WarrantyStatus? warrantyStatus,
    int? daysRemaining,
    String? notes,
    bool clearNotes = false,
    bool? isArchived,
    ItemAddedVia? addedVia,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Item(
      id: id ?? this.id,
      homeId: homeId ?? this.homeId,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      brand: clearBrand ? null : (brand ?? this.brand),
      modelNumber:
          clearModelNumber ? null : (modelNumber ?? this.modelNumber),
      serialNumber:
          clearSerialNumber ? null : (serialNumber ?? this.serialNumber),
      category: category ?? this.category,
      room: clearRoom ? null : (room ?? this.room),
      productImageUrl: clearProductImageUrl
          ? null
          : (productImageUrl ?? this.productImageUrl),
      barcode: clearBarcode ? null : (barcode ?? this.barcode),
      purchaseDate: purchaseDate ?? this.purchaseDate,
      store: clearStore ? null : (store ?? this.store),
      price: clearPrice ? null : (price ?? this.price),
      warrantyMonths: warrantyMonths ?? this.warrantyMonths,
      warrantyEndDate: warrantyEndDate ?? this.warrantyEndDate,
      warrantyType: warrantyType ?? this.warrantyType,
      warrantyProvider: clearWarrantyProvider
          ? null
          : (warrantyProvider ?? this.warrantyProvider),
      warrantyStatus: warrantyStatus ?? this.warrantyStatus,
      daysRemaining: daysRemaining ?? this.daysRemaining,
      notes: clearNotes ? null : (notes ?? this.notes),
      isArchived: isArchived ?? this.isArchived,
      addedVia: addedVia ?? this.addedVia,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() => 'Item(id: $id, name: $name, category: ${category.name})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Item && other.id == id;

  @override
  int get hashCode => id.hashCode;
}
