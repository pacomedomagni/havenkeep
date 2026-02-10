import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';

/// Test helpers and utilities for HavenKeep tests.
///
/// Provides factory methods for creating test data and setting up test
/// containers with mocked dependencies.
class TestHelpers {
  /// Consistent test user ID used across tests.
  static const String testUserId = 'test-user-123';

  /// Consistent test home ID used across tests.
  static const String testHomeId = 'test-home-123';
  /// Creates a test Item with sensible defaults.
  ///
  /// Pass [status] to create an item with a specific warranty status:
  /// - `WarrantyStatus.active`: Purchase date 30 days ago, 12-month warranty
  /// - `WarrantyStatus.expiring`: Purchase date 300 days ago (within 90 days of expiration)
  /// - `WarrantyStatus.expired`: Purchase date 400 days ago (past warranty period)
  static Item createTestItem({
    String? id,
    String? homeId,
    String? userId,
    String? name,
    String? brand,
    String? modelNumber,
    String? serialNumber,
    ItemCategory? category,
    ItemRoom? room,
    DateTime? purchaseDate,
    String? store,
    double? price,
    int? warrantyMonths,
    WarrantyType? warrantyType,
    String? warrantyProvider,
    DateTime? warrantyEndDate,
    WarrantyStatus? status,
    String? notes,
    bool? isArchived,
    ItemAddedVia? addedVia,
  }) {
    // Auto-generate purchase date based on desired warranty status
    final effectivePurchaseDate = purchaseDate ?? _dateForStatus(status);
    final effectiveWarrantyMonths = warrantyMonths ?? 12;

    return Item(
      id: id ?? 'test-item-${DateTime.now().millisecondsSinceEpoch}',
      homeId: homeId ?? testHomeId,
      userId: userId ?? testUserId,
      name: name ?? 'Test Refrigerator',
      brand: brand,
      modelNumber: modelNumber,
      serialNumber: serialNumber,
      category: category ?? ItemCategory.refrigerator,
      room: room,
      purchaseDate: effectivePurchaseDate,
      store: store,
      price: price,
      warrantyMonths: effectiveWarrantyMonths,
      warrantyType: warrantyType ?? WarrantyType.manufacturer,
      warrantyProvider: warrantyProvider,
      warrantyEndDate: warrantyEndDate,
      notes: notes,
      isArchived: isArchived ?? false,
      addedVia: addedVia ?? ItemAddedVia.manual,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Calculates purchase date based on desired warranty status.
  static DateTime _dateForStatus(WarrantyStatus? status) {
    final now = DateTime.now();
    if (status == null) return now;

    switch (status) {
      case WarrantyStatus.active:
        // 30 days ago with 12-month warranty = 11 months remaining
        return now.subtract(const Duration(days: 30));
      case WarrantyStatus.expiring:
        // 300 days ago with 12-month warranty = ~65 days remaining (within 90 days)
        return now.subtract(const Duration(days: 300));
      case WarrantyStatus.expired:
        // 400 days ago with 12-month warranty = expired ~35 days ago
        return now.subtract(const Duration(days: 400));
    }
  }

  /// Creates a test User with sensible defaults.
  static User createTestUser({
    String? id,
    String? email,
    String? fullName,
    String? avatarUrl,
    AuthProvider? authProvider,
    UserPlan? plan,
    DateTime? planExpiresAt,
    String? referredBy,
    String? referralCode,
  }) {
    return User(
      id: id ?? 'test-user',
      email: email ?? 'test@havenkeep.com',
      fullName: fullName ?? 'Test User',
      avatarUrl: avatarUrl,
      authProvider: authProvider ?? AuthProvider.email,
      plan: plan ?? UserPlan.free,
      planExpiresAt: planExpiresAt,
      referredBy: referredBy,
      referralCode: referralCode,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a test Home with sensible defaults.
  static Home createTestHome({
    String? id,
    String? userId,
    String? name,
    String? address,
    String? city,
    String? state,
    String? zip,
    HomeType? homeType,
    DateTime? moveInDate,
  }) {
    return Home(
      id: id ?? 'test-home',
      userId: userId ?? 'test-user',
      name: name ?? 'Test Home',
      address: address,
      city: city,
      state: state,
      zip: zip,
      homeType: homeType ?? HomeType.house,
      moveInDate: moveInDate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
  }

  /// Creates a test Document with sensible defaults.
  static Document createTestDocument({
    String? id,
    String? itemId,
    String? userId,
    DocumentType? type,
    String? fileUrl,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? thumbnailUrl,
  }) {
    return Document(
      id: id ?? 'test-document',
      itemId: itemId ?? 'test-item',
      userId: userId ?? 'test-user',
      type: type ?? DocumentType.receipt,
      fileUrl: fileUrl ?? 'https://example.com/receipt.pdf',
      fileName: fileName ?? 'receipt.pdf',
      fileSize: fileSize ?? 1024,
      mimeType: mimeType ?? 'application/pdf',
      thumbnailUrl: thumbnailUrl,
      createdAt: DateTime.now(),
    );
  }

  /// Creates a ProviderContainer for testing with optional overrides.
  ///
  /// Example:
  /// ```dart
  /// final container = TestHelpers.createContainer(overrides: [
  ///   itemsRepositoryProvider.overrideWithValue(mockRepository),
  /// ]);
  /// ```
  static ProviderContainer createContainer({
    List<Override>? overrides,
  }) {
    return ProviderContainer(
      overrides: overrides ?? [],
    );
  }

  /// Creates a list of test items with varying warranty statuses.
  static List<Item> createTestItems({
    int count = 5,
    String? homeId,
    String? userId,
  }) {
    final statuses = [
      WarrantyStatus.active,
      WarrantyStatus.active,
      WarrantyStatus.expiring,
      WarrantyStatus.expiring,
      WarrantyStatus.expired,
    ];

    return List.generate(count, (index) {
      final status = statuses[index % statuses.length];
      return createTestItem(
        id: 'test-item-$index',
        homeId: homeId,
        userId: userId,
        name: 'Test Item $index',
        status: status,
      );
    });
  }
}
