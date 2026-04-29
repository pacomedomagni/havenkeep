import 'enums.dart';

/// A tracked item (appliance, system, etc.) with warranty information.
///
/// Field-by-field the model mirrors the `items` table; computed fields
/// (warranty status, days remaining, lifespan %) come from the API view
/// rather than the table.
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

  /// Price.
  ///
  /// Ch08-Item-D009: the wire format is Postgres `DECIMAL(10, 2)` which
  /// arrives as a JSON string ("1234.56") OR a JSON number depending on
  /// the route's serializer. We coerce to [double] for display ergonomics;
  /// callers that need ledger-grade precision must NOT use this for
  /// arithmetic — use [num.parse] on the original string at the call site
  /// (Phase 9 plans a `Decimal`-typed migration of the math paths).
  final double? price;

  // Warranty info
  final int warrantyMonths;

  /// Computed by the DB. NEVER null — the column is `NOT NULL` (Ch08-Item-D010).
  final DateTime warrantyEndDate;
  final WarrantyType warrantyType;
  final String? warrantyProvider;

  // Computed (from views, not stored in items table)
  final WarrantyStatus? warrantyStatus;
  final int? daysRemaining;

  // Informational (from DB, read-only — populated for some categories)
  final double? estimatedRepairCost;

  // Lifespan tracking (computed by API from purchase_date + expected lifespan)
  final int? expectedLifespanYears;
  final int? lifespanPercentage;

  // Maintenance tracking
  final DateTime? installationDate;
  final DateTime? lastMaintenanceDate;
  final DateTime? nextMaintenanceDue;

  // Meta
  final String? notes;
  final bool isArchived;
  final ItemAddedVia addedVia;
  final DateTime? archivedAt;
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
    required this.warrantyEndDate,
    this.warrantyType = WarrantyType.manufacturer,
    this.warrantyProvider,
    this.warrantyStatus,
    this.daysRemaining,
    this.estimatedRepairCost,
    this.expectedLifespanYears,
    this.lifespanPercentage,
    this.installationDate,
    this.lastMaintenanceDate,
    this.nextMaintenanceDue,
    this.notes,
    this.isArchived = false,
    this.addedVia = ItemAddedVia.manual,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Item.fromJson(Map<String, dynamic> json) {
    return Item(
      id: json['id'] as String? ?? '',
      homeId: json['home_id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      brand: json['brand'] as String?,
      modelNumber: json['model_number'] as String?,
      serialNumber: json['serial_number'] as String?,
      category: ItemCategory.fromJson(json['category'] as String? ?? 'other'),
      room: json['room'] != null
          ? ItemRoom.fromJson(json['room'] as String)
          : null,
      productImageUrl: json['product_image_url'] as String?,
      barcode: json['barcode'] as String?,
      purchaseDate: _parseDate(json['purchase_date'])!,
      store: json['store'] as String?,
      // Ch08-Item-D009: handle both numeric and DECIMAL-string envelopes.
      price: json['price'] != null
          ? (json['price'] is num
              ? (json['price'] as num).toDouble()
              : double.tryParse(json['price'].toString()))
          : null,
      warrantyMonths: (json['warranty_months'] as num?)?.toInt() ?? 12,
      warrantyEndDate: _parseDate(json['warranty_end_date'])!,
      warrantyType: WarrantyType.fromJson(
        json['warranty_type'] as String? ?? 'manufacturer',
      ),
      warrantyProvider: json['warranty_provider'] as String?,
      warrantyStatus: json['warranty_status'] != null
          ? WarrantyStatus.fromJson(json['warranty_status'] as String)
          : null,
      daysRemaining: (json['days_remaining'] as num?)?.toInt(),
      estimatedRepairCost: json['estimated_repair_cost'] != null
          ? (json['estimated_repair_cost'] is num
              ? (json['estimated_repair_cost'] as num).toDouble()
              : double.tryParse(json['estimated_repair_cost'].toString()))
          : null,
      expectedLifespanYears: (json['expected_lifespan_years'] as num?)?.toInt(),
      lifespanPercentage: (json['lifespan_percentage'] as num?)?.toInt(),
      installationDate: _parseDate(json['installation_date']),
      lastMaintenanceDate: _parseDate(json['last_maintenance_date']),
      nextMaintenanceDue: _parseDate(json['next_maintenance_due']),
      notes: json['notes'] as String?,
      isArchived: json['is_archived'] as bool? ?? false,
      addedVia: ItemAddedVia.fromJson(json['added_via'] as String? ?? 'manual'),
      archivedAt: _parseDate(json['archived_at']),
      // 4.1: server-stamped timestamps fall back instead of crashing.
      // `purchaseDate` + `warrantyEndDate` keep `!` because they're
      // required-by-contract user input the API rejects when null.
      createdAt: _parseDate(json['created_at']) ?? DateTime.now(),
      updatedAt: _parseDate(json['updated_at']) ?? DateTime.now(),
    );
  }

  /// Full JSON for reads / updates.
  ///
  /// 1.8: `product_image_url` is server-managed (set via
  /// POST /uploads/item-image, mirrored back as a presigned URL by the
  /// /items GET response). It's deliberately NOT emitted here — the
  /// server's update validator rejects it, and re-sending the
  /// presigned URL we just received back would be meaningless. Use
  /// [productImageUrl] for display only.
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
      'barcode': barcode,
      'purchase_date': purchaseDate.toIso8601String().split('T').first,
      'store': store,
      'price': price,
      'warranty_months': warrantyMonths,
      'warranty_end_date':
          warrantyEndDate.toIso8601String().split('T').first,
      'warranty_type': warrantyType.toJson(),
      'warranty_provider': warrantyProvider,
      'installation_date': installationDate?.toIso8601String().split('T').first,
      'last_maintenance_date':
          lastMaintenanceDate?.toIso8601String().split('T').first,
      'next_maintenance_due':
          nextMaintenanceDue?.toIso8601String().split('T').first,
      'notes': notes,
      'is_archived': isArchived,
      'added_via': addedVia.toJson(),
      'archived_at': archivedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// JSON for inserts. Strips id (server generates the UUID) and
  /// `warranty_end_date` (GENERATED column, server computes from
  /// `purchase_date + warranty_months`). Ch08-Item-D013/D014/D015:
  /// [installationDate], [lastMaintenanceDate], and [nextMaintenanceDue]
  /// ARE included — clients need them on initial create-from-receipt
  /// flows. Server enforces ownership / date ordering.
  Map<String, dynamic> toInsertJson() {
    final json = toJson();
    json.remove('id');
    json.remove('warranty_end_date');
    json.remove('archived_at');
    json.remove('created_at');
    json.remove('updated_at');
    return json;
  }

  /// Compute warranty_end_date the same way the API does (calendar-month
  /// arithmetic, day-clamped to the last day of the target month). Used by
  /// demo-mode + add-item flows that need to pre-fill the field locally
  /// before the server roundtrips it back.
  static DateTime computeWarrantyEndDate(
    DateTime purchaseDate,
    int warrantyMonths,
  ) {
    var year = purchaseDate.year;
    var month = purchaseDate.month + warrantyMonths;
    var day = purchaseDate.day;
    year += (month - 1) ~/ 12;
    month = ((month - 1) % 12) + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    if (day > lastDay) day = lastDay;
    return DateTime(year, month, day);
  }

  /// Compute warranty status client-side (when not using the view).
  ///
  /// S2-A: compares in UTC. The server stores `warranty_end_date` as a
  /// UTC instant; comparing it to a *local* `DateTime(now.year, ...)` flips
  /// the result around midnight in the device's local zone (e.g. a warranty
  /// ending at 00:00Z appeared expired on a -08:00 device for the last 8
  /// hours of its valid life).
  WarrantyStatus get computedWarrantyStatus {
    if (warrantyStatus != null) return warrantyStatus!;

    final nowUtc = DateTime.now().toUtc();
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    final endUtc = warrantyEndDate.toUtc();

    if (endUtc.isBefore(today)) return WarrantyStatus.expired;
    if (endUtc.difference(today).inDays <= 90) {
      return WarrantyStatus.expiring;
    }
    return WarrantyStatus.active;
  }

  /// Compute days remaining client-side.
  int get computedDaysRemaining {
    if (daysRemaining != null) return daysRemaining!;

    final nowUtc = DateTime.now().toUtc();
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    return warrantyEndDate.toUtc().difference(today).inDays;
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
    double? estimatedRepairCost,
    bool clearEstimatedRepairCost = false,
    int? expectedLifespanYears,
    bool clearExpectedLifespanYears = false,
    int? lifespanPercentage,
    bool clearLifespanPercentage = false,
    DateTime? installationDate,
    bool clearInstallationDate = false,
    DateTime? lastMaintenanceDate,
    bool clearLastMaintenanceDate = false,
    DateTime? nextMaintenanceDue,
    bool clearNextMaintenanceDue = false,
    String? notes,
    bool clearNotes = false,
    bool? isArchived,
    ItemAddedVia? addedVia,
    DateTime? archivedAt,
    bool clearArchivedAt = false,
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
      productImageUrl: this.productImageUrl,
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
      estimatedRepairCost: clearEstimatedRepairCost
          ? null
          : (estimatedRepairCost ?? this.estimatedRepairCost),
      expectedLifespanYears: clearExpectedLifespanYears
          ? null
          : (expectedLifespanYears ?? this.expectedLifespanYears),
      lifespanPercentage: clearLifespanPercentage
          ? null
          : (lifespanPercentage ?? this.lifespanPercentage),
      installationDate: clearInstallationDate
          ? null
          : (installationDate ?? this.installationDate),
      lastMaintenanceDate: clearLastMaintenanceDate
          ? null
          : (lastMaintenanceDate ?? this.lastMaintenanceDate),
      nextMaintenanceDue: clearNextMaintenanceDue
          ? null
          : (nextMaintenanceDue ?? this.nextMaintenanceDue),
      notes: clearNotes ? null : (notes ?? this.notes),
      isArchived: isArchived ?? this.isArchived,
      addedVia: addedVia ?? this.addedVia,
      archivedAt: clearArchivedAt ? null : (archivedAt ?? this.archivedAt),
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

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  if (value is DateTime) return value;
  if (value is String) return DateTime.tryParse(value);
  return null;
}
